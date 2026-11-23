import 'dart:convert';

import 'package:archive/archive.dart';

class XlsxWorkbooks {
  static const mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static List<Map<String, Object?>> parsePaidHolidays(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = {for (final file in archive.files) file.name: file};
    final sheetPath = _firstWorksheetPath(files);
    final sheetFile = files[sheetPath];
    if (sheetFile == null)
      throw const FormatException('The Excel workbook has no worksheet.');
    final sheet = utf8.decode(sheetFile.content as List<int>);
    final shared = _readSharedStrings(files);
    final rows = <List<String>>[];
    for (final rowMatch in RegExp(
      r'<row\b[^>]*>(.*?)</row>',
      dotAll: true,
    ).allMatches(sheet)) {
      final cells = <int, String>{};
      for (final cell in RegExp(
        r'<c\b([^>]*)>(.*?)</c>',
        dotAll: true,
      ).allMatches(rowMatch.group(1)!)) {
        final attributes = cell.group(1)!;
        final ref = RegExp(r'\br="([A-Z]+)\d+"')
            .firstMatch(attributes)
            ?.group(1);
        if (ref == null) continue;
        final column = _columnIndex(ref);
        final type = RegExp(r'\bt="([^"]+)"').firstMatch(attributes)?.group(1);
        final body = cell.group(2)!;
        String value;
        if (type == 'inlineStr') {
          value = _textNodes(body);
        } else {
          final raw =
              RegExp(
                r'<v[^>]*>(.*?)</v>',
                dotAll: true,
              ).firstMatch(body)?.group(1) ??
              '';
          if (type == 's') {
            final index = int.tryParse(raw) ?? -1;
            value = index >= 0 && index < shared.length ? shared[index] : '';
          } else {
            value = _xmlUnescape(raw);
          }
        }
        cells[column] = value;
      }
      if (cells.isNotEmpty) {
        final maxColumn = cells.keys.reduce((a, b) => a > b ? a : b);
        rows.add(List.generate(maxColumn + 1, (i) => cells[i] ?? ''));
      }
    }
    if (rows.length < 2)
      throw const FormatException('The holiday sheet is empty.');
    final headings = rows.first
        .map((value) => value.trim().toLowerCase())
        .toList();
    final dateColumn = _headingIndex(headings, const ['date', 'holiday date']);
    final nameColumn = _headingIndex(headings, const [
      'holiday',
      'name',
      'holiday name',
    ]);
    final daysColumn = _headingIndex(headings, const ['paid days', 'days']);
    if (dateColumn < 0 || nameColumn < 0) {
      throw const FormatException(
        'The first worksheet needs Date and Holiday columns.',
      );
    }
    final holidays = <String, Map<String, Object?>>{};
    for (final row in rows.skip(1)) {
      final dateValue = dateColumn < row.length ? row[dateColumn].trim() : '';
      final name = nameColumn < row.length ? row[nameColumn].trim() : '';
      if (dateValue.isEmpty && name.isEmpty) continue;
      if (name.isEmpty)
        throw const FormatException('Every holiday row needs a holiday name.');
      final date = _parseDate(dateValue);
      final paidDays = daysColumn >= 0 && daysColumn < row.length
          ? (double.tryParse(row[daysColumn].trim()) ?? 1)
          : 1.0;
      if (paidDays != 1) {
        throw const FormatException(
          'Paid holidays must be full-day entries with Paid Days set to 1.',
        );
      }
      holidays[date] = {'date': date, 'name': name, 'paid_days': paidDays};
      if (holidays.length > 500) {
        throw const FormatException(
          'Import up to 500 holidays per Excel file.',
        );
      }
    }
    if (holidays.isEmpty)
      throw const FormatException('No holiday rows were found.');
    return holidays.values.toList();
  }

  static List<int> buildAttendanceReport(
    List<Map<String, Object?>> employees,
    DateTime month,
  ) {
    final archive = Archive();
    final summaryRows = <List<Object?>>[
      [
        'Employee ID',
        'Employee',
        'Attendance credits (includes Sunday and holidays)',
        'Leave days',
        'Absent days',
        'Paid holidays',
        'Total work hours',
        'Paid leave balance',
        'Saturday full-day credit',
      ],
    ];
    final dailyRows = <List<Object?>>[
      [
        'Employee ID',
        'Employee',
        'Date',
        'Day status',
        'Attendance credit (days)',
        'Punch in (UTC)',
        'Punch out (UTC)',
        'Worked hours',
        'Paid holiday',
        'Leave type',
        'Paid leave deducted',
        'Saturday credited as full day',
      ],
    ];
    for (final employee in employees) {
      final employeeId = '${employee['employee_id'] ?? ''}';
      final displayName = '${employee['display_name'] ?? ''}';
      summaryRows.add([
        employeeId,
        displayName,
        _number(employee['present_days']),
        _number(employee['leave_days']),
        _number(employee['absent_days']),
        _number(employee['paid_holiday_days']),
        _hours(employee['worked_minutes']),
        _number(employee['paid_leave_balance']),
        employee['saturday_full_day_credit'] == true ? 'Yes' : 'No',
      ]);
      final daily = employee['daily'];
      if (daily is! List) continue;
      for (final item in daily.whereType<Map>()) {
        final minutes = _number(item['worked_minutes']);
        final status = '${item['status'] ?? ''}';
        final dayNote = '${item['day_note'] ?? ''}';
        dailyRows.add([
          employeeId,
          displayName,
          '${item['date'] ?? ''}',
          '$status${dayNote.isEmpty ? '' : ' · $dayNote'}',
          _number(item['credited_days']),
          _time(item['punch_in']),
          _time(item['punch_out']),
          _hours(minutes),
          '${item['holiday_name'] ?? ''}',
          '${item['leave_type'] ?? ''}',
          item['paid_leave_deducted'] == true ? 'Yes' : 'No',
          item['saturday_full_day_credit'] == true ? 'Yes' : 'No',
        ]);
      }
    }
    archive.addFile(_zipFile('[Content_Types].xml', _contentTypes(2)));
    archive.addFile(_zipFile('_rels/.rels', _rootRelationships));
    archive.addFile(
      _zipFile(
        'xl/workbook.xml',
        _workbookXml(const ['Monthly Summary', 'Daily Attendance']),
      ),
    );
    archive.addFile(
      _zipFile('xl/_rels/workbook.xml.rels', _workbookRelationships(2)),
    );
    archive.addFile(
      _zipFile('xl/worksheets/sheet1.xml', _worksheetXml(summaryRows)),
    );
    archive.addFile(
      _zipFile('xl/worksheets/sheet2.xml', _worksheetXml(dailyRows)),
    );
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null)
      throw const FormatException('Could not create the Excel report.');
    return encoded;
  }

  static String attendanceFileName(DateTime month) =>
      'INDETAIL-attendance-${month.year}-${month.month.toString().padLeft(2, '0')}.xlsx';

  static String holidayTemplateFileName() =>
      'INDETAIL-paid-holidays-template.xlsx';

  static List<int> buildHolidayTemplate() {
    final archive = Archive();
    final rows = <List<Object?>>[
      ['Date', 'Holiday', 'Paid Days'],
      ['2026-12-25', 'Christmas Day', 1],
    ];
    archive.addFile(_zipFile('[Content_Types].xml', _contentTypes(1)));
    archive.addFile(_zipFile('_rels/.rels', _rootRelationships));
    archive.addFile(
      _zipFile('xl/workbook.xml', _workbookXml(const ['Holidays'])),
    );
    archive.addFile(
      _zipFile('xl/_rels/workbook.xml.rels', _workbookRelationships(1)),
    );
    archive.addFile(_zipFile('xl/worksheets/sheet1.xml', _worksheetXml(rows)));
    return ZipEncoder().encode(archive)!;
  }

  static List<String> _readSharedStrings(Map<String, ArchiveFile> files) {
    final file = files['xl/sharedStrings.xml'];
    if (file == null) return const [];
    final xml = utf8.decode(file.content as List<int>);
    return RegExp(
      r'<si\b[^>]*>(.*?)</si>',
      dotAll: true,
    ).allMatches(xml).map((match) => _textNodes(match.group(1)!)).toList();
  }

  static String _firstWorksheetPath(Map<String, ArchiveFile> files) {
    final workbook = files['xl/workbook.xml'];
    final relationships = files['xl/_rels/workbook.xml.rels'];
    if (workbook == null || relationships == null)
      return 'xl/worksheets/sheet1.xml';
    final rid = RegExp(r'<sheet\b[^>]*\br:id="([^"]+)"')
        .firstMatch(utf8.decode(workbook.content as List<int>))
        ?.group(1);
    if (rid == null) return 'xl/worksheets/sheet1.xml';
    final relationPattern = RegExp(
      '<Relationship\\b(?=[^>]*\\bId="${RegExp.escape(rid)}")(?=[^>]*\\bTarget="([^"]+)")[^>]*/?>',
    );
    final target = relationPattern
        .firstMatch(utf8.decode(relationships.content as List<int>))
        ?.group(1);
    if (target == null) return 'xl/worksheets/sheet1.xml';
    if (target.startsWith('/')) return target.substring(1);
    return target.startsWith('xl/') ? target : 'xl/$target';
  }

  static int _columnIndex(String reference) {
    var value = 0;
    for (final rune in reference.codeUnits) {
      value = value * 26 + rune - 64;
    }
    return value - 1;
  }

  static int _headingIndex(List<String> headings, List<String> names) =>
      headings.indexWhere(names.contains);

  static String _textNodes(String xml) => RegExp(
    r'<t\b[^>]*>(.*?)</t>',
    dotAll: true,
  ).allMatches(xml).map((match) => _xmlUnescape(match.group(1)!)).join();

  static String _xmlUnescape(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static String _parseDate(String raw) {
    final normalized = raw.trim();
    final direct = DateTime.tryParse(normalized);
    if (direct != null) return _dateString(direct);
    final serial = double.tryParse(normalized);
    if (serial != null && serial >= 1 && serial <= 2958465) {
      return _dateString(
        DateTime(1899, 12, 30).add(Duration(days: serial.floor())),
      );
    }
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$')
        .firstMatch(normalized);
    if (slash != null) {
      final first = int.parse(slash.group(1)!);
      final second = int.parse(slash.group(2)!);
      final year = int.parse(slash.group(3)!);
      // Excel-local dates are accepted as month/day/year, with day/month/year
      // as a fallback when the first component cannot be a month.
      final date = first <= 12
          ? DateTime(year, first, second)
          : DateTime(year, second, first);
      final expectedMonth = first <= 12 ? first : second;
      final expectedDay = first <= 12 ? second : first;
      if (date.year != year ||
          date.month != expectedMonth ||
          date.day != expectedDay) {
        throw FormatException('Could not read holiday date "$normalized".');
      }
      return _dateString(date);
    }
    throw FormatException(
      'Could not read holiday date "$normalized". Use a real Excel date or YYYY-MM-DD.',
    );
  }

  static String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  static double _hours(Object? minutes) => _number(minutes) / 60;

  static String _time(Object? value) {
    final date = DateTime.tryParse('$value');
    if (date == null) return '';
    final utc = date.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')} ${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}';
  }

  static ArchiveFile _zipFile(String name, String xml) {
    final bytes = utf8.encode(xml);
    return ArchiveFile(name, bytes.length, bytes);
  }

  static String _contentTypes(int sheetCount) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheetCount, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>''';

  static const _rootRelationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''';

  static String _workbookXml(List<String> names) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${List.generate(names.length, (i) => '<sheet name="${_xmlEscape(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>').join()}</sheets></workbook>''';

  static String _workbookRelationships(int count) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(count, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}</Relationships>''';

  static String _worksheetXml(List<List<Object?>> rows) {
    final body = <String>[];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final cells = <String>[];
      for (
        var columnIndex = 0;
        columnIndex < rows[rowIndex].length;
        columnIndex++
      ) {
        final value = rows[rowIndex][columnIndex];
        final ref = '${_columnName(columnIndex)}${rowIndex + 1}';
        if (value is num) {
          cells.add('<c r="$ref"><v>$value</v></c>');
        } else {
          cells.add(
            '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xmlEscape('$value')}</t></is></c>',
          );
        }
      }
      body.add('<row r="${rowIndex + 1}">${cells.join()}</row>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${body.join()}</sheetData></worksheet>';
  }

  static String _columnName(int index) {
    var value = index + 1;
    var result = '';
    while (value > 0) {
      final rem = (value - 1) % 26;
      result = String.fromCharCode(65 + rem) + result;
      value = (value - rem - 1) ~/ 26;
    }
    return result;
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
