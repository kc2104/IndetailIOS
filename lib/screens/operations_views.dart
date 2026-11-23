import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../native_bridge.dart';
import '../repository.dart';
import '../supabase_api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../xlsx_workbooks.dart';

class WorkspaceView extends StatelessWidget {
  const WorkspaceView({
    super.key,
    required this.page,
    required this.session,
    required this.repository,
    required this.onSignOut,
  });
  final WorkspacePage page;
  final AppSession session;
  final WorkspaceRepository repository;
  final Future<void> Function() onSignOut;

  String get _title => switch (page) {
    WorkspacePage.attendance => 'Attendance',
    WorkspacePage.reports => 'Reports',
    WorkspacePage.gallery => 'Project gallery',
    WorkspacePage.team => 'My team',
    WorkspacePage.analytics => 'Insights',
    WorkspacePage.settings => 'Workspace settings',
    WorkspacePage.history => 'Work history',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      actions: [
        if (session.isDemo)
          const Padding(
            padding: EdgeInsets.only(right: 15),
            child: Center(child: StatusPill(value: 'Preview')),
          ),
      ],
    ),
    body: Column(
      children: [
        if (session.isDemo) const PreviewBanner(),
        Expanded(
          child: switch (page) {
            WorkspacePage.attendance => AttendanceView(
              session: session,
              repository: repository,
            ),
            WorkspacePage.reports => ReportsView(
              session: session,
              repository: repository,
            ),
            WorkspacePage.gallery => GalleryView(
              session: session,
              repository: repository,
            ),
            WorkspacePage.team => TeamView(
              session: session,
              repository: repository,
            ),
            WorkspacePage.analytics => AnalyticsView(
              session: session,
              repository: repository,
            ),
            WorkspacePage.settings => SettingsView(
              session: session,
              repository: repository,
              onSignOut: onSignOut,
            ),
            WorkspacePage.history => HistoryView(
              session: session,
              repository: repository,
            ),
          },
        ),
      ],
    ),
  );
}

class AttendanceView extends StatefulWidget {
  const AttendanceView({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  late Future<List<AttendanceSite>> _sitesFuture;
  late Future<AttendanceSite?> _openSiteFuture;
  late Future<Map<String, Object?>> _summaryFuture;
  late Future<List<Map<String, Object?>>> _holidaysFuture;
  late Future<List<Map<String, Object?>>> _leaveRequestsFuture;
  String? _siteId;
  AttendanceSite? _verifiedSite;
  LocationFix? _fix;
  double? _distance;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sitesFuture = widget.repository.attendanceSites();
    _openSiteFuture = widget.repository.openAttendanceSite();
    _summaryFuture = widget.repository.myAttendanceSummary();
    _holidaysFuture = widget.repository.paidHolidays();
    _leaveRequestsFuture = widget.repository.leaveRequests();
  }

  Future<void> _refresh({bool clearMessage = true}) async {
    setState(() {
      _sitesFuture = widget.repository.attendanceSites();
      _openSiteFuture = widget.repository.openAttendanceSite();
      _summaryFuture = widget.repository.myAttendanceSummary();
      _holidaysFuture = widget.repository.paidHolidays();
      _leaveRequestsFuture = widget.repository.leaveRequests();
      _fix = null;
      _verifiedSite = null;
      _distance = null;
      if (clearMessage) _message = null;
    });
  }

  Future<void> _verify(List<AttendanceSite> sites) async {
    if (sites.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
      _fix = null;
      _verifiedSite = null;
    });
    try {
      final fix = await NativeBridge.currentLocation();
      final matches = sites.where((site) => site.id == _siteId);
      final target = matches.isEmpty ? sites.first : matches.first;
      final distance = distanceInMeters(
        fix.latitude,
        fix.longitude,
        target.latitude,
        target.longitude,
      );
      setState(() {
        _fix = fix;
        _verifiedSite = target;
        _distance = distance;
        if (fix.accuracyMeters > 35) {
          _message =
              'GPS accuracy is ${fix.accuracyMeters.round()} m. Move to a clearer area; attendance needs 35 m accuracy or better.';
        } else if (fix.isMocked) {
          _message = 'This device reports a simulated location. Attendance will be rejected and flagged by the server.';
        } else if (distance > target.radiusMeters) {
          _message =
              'You are ${distance.round()} m from ${target.name}, outside its ${target.radiusMeters} m radius.';
        } else {
          _message = 'Location is inside the approved radius. The server will verify again when you punch.';
        }
      });
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _punch(bool isOpen) async {
    final fix = _fix;
    final site = _verifiedSite;
    if (fix == null || site == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.repository.recordAttendance(
        action: isOpen ? 'out' : 'in',
        site: site,
        location: fix,
      );
      final accepted = result['accepted'] == true;
      setState(
        () => _message = accepted
            ? (isOpen ? 'Punch-out recorded.' : 'Punch-in recorded.')
            : '${result['reason'] ?? 'The server rejected this attendance event.'}',
      );
      if (accepted) await _refresh(clearMessage: false);
    } catch (error) {
      setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSite() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => SiteEditor(repository: widget.repository),
    );
    if (saved == true) _refresh();
  }

  Future<void> _applyForLeave() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => _LeaveRequestEditor(repository: widget.repository),
    );
    if (saved == true) _refresh();
  }

  bool _inside(LocationFix? fix, AttendanceSite? site, double? distance) =>
      fix != null &&
      site != null &&
      distance != null &&
      fix.accuracyMeters <= 35 &&
      !fix.isMocked &&
      distance <= site.radiusMeters;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AttendanceSite>>(
    future: _sitesFuture,
    builder: (context, siteSnapshot) {
      if (siteSnapshot.hasError)
        return ErrorState(
          message: siteSnapshot.error.toString(),
          onRetry: _refresh,
        );
      if (!siteSnapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final sites = siteSnapshot.data!;
      if (_siteId == null && sites.isNotEmpty) _siteId = sites.first.id;
      final sundayOff = DateTime.now().weekday == DateTime.sunday;
      return FutureBuilder<AttendanceSite?>(
        future: _openSiteFuture,
        builder: (context, openSnapshot) {
          if (openSnapshot.hasError) {
            return ErrorState(
              message: openSnapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          if (openSnapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final openSite = openSnapshot.data;
          final isOpen = openSite != null;
          final punchSites = isOpen ? [openSite] : sites;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
            children: [
              Text(
                'A verified place to begin.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              const Text(
                'INDETAIL checks one location when you punch. It does not track you in the background.',
                style: TextStyle(
                  color: Palette.muted,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _AttendanceSummaryCard(
                future: _summaryFuture,
                isDemo: widget.session.isDemo,
              ),
              const SizedBox(height: 15),
              if (!widget.session.isDemo) ...[
                _PaidHolidayCalendar(future: _holidaysFuture),
                const SizedBox(height: 15),
              ],
              if (widget.session.isDemo)
                const _AttendanceLockedCard(
                  title: 'Preview mode',
                  detail: 'Punching is disabled in the preview. It never requests location or records attendance.',
                  icon: Icons.visibility_outlined,
                )
              else if (sundayOff && !isOpen)
                const _AttendanceLockedCard(
                  title: 'Sunday · weekly off',
                  detail: 'Punch-in is unavailable on Sundays. If a shift is already open, you can still punch out at its approved site.',
                  icon: Icons.event_busy_outlined,
                )
              else if (punchSites.isEmpty)
                _AttendanceLockedCard(
                  title: 'No approved site yet',
                  detail: widget.session.role.canAssign
                      ? 'Add your real office coordinates or a project site. Attendance stays unavailable until a site is configured.'
                      : 'Your Admin or Team Leader needs to configure an office or project site before you can punch.',
                  icon: Icons.location_off_outlined,
                  action: widget.session.role.canAssign ? _addSite : null,
                )
              else ...[
                SurfaceCard(
                  padding: const EdgeInsets.all(17),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.near_me_outlined,
                            color: Palette.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Choose an approved site',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      DropdownButtonFormField<String>(
                        initialValue:
                            punchSites.any((site) => site.id == _siteId)
                            ? _siteId
                            : punchSites.first.id,
                        decoration: const InputDecoration(
                          labelText: 'Work location',
                        ),
                        items: punchSites
                            .map(
                              (site) => DropdownMenuItem(
                                value: site.id,
                                child: Text('${site.name}  ·  ${site.kind}'),
                              ),
                            )
                            .toList(),
                        onChanged: isOpen
                            ? null
                            : (value) => setState(() {
                                _siteId = value;
                                _fix = null;
                                _verifiedSite = null;
                                _distance = null;
                                _message = null;
                              }),
                      ),
                      const SizedBox(height: 11),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _verify(punchSites),
                        icon: const Icon(Icons.gps_fixed_rounded),
                        label: Text(
                          _busy && _fix == null
                              ? 'Checking GPS…'
                              : 'Verify my location',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(49),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_fix != null && _verifiedSite != null) ...[
                  const SizedBox(height: 12),
                  _VerificationCard(
                    fix: _fix!,
                    site: _verifiedSite!,
                    distance: _distance ?? 0,
                    allowed: _inside(_fix, _verifiedSite, _distance),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _message!.contains('recorded')
                          ? const Color(0xFFE7F3EC)
                          : const Color(0xFFF8E9E5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _message!.contains('recorded')
                            ? Palette.green
                            : Palette.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy || !_inside(_fix, _verifiedSite, _distance)
                      ? null
                      : () => _punch(isOpen),
                  icon: Icon(
                    isOpen ? Icons.logout_rounded : Icons.login_rounded,
                  ),
                  label: Text(isOpen ? 'Punch out' : 'Punch in'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isOpen ? Palette.blue : Palette.navy,
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A punch is saved only after the server verifies your account, assignment, site radius, GPS accuracy and shift state.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Palette.muted,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (widget.session.role.isAdmin && !widget.session.isDemo) ...[
                _AdminAttendanceWorkspace(
                  repository: widget.repository,
                  onChanged: _refresh,
                ),
                const SizedBox(height: 24),
              ],
              SectionHeading(
                title: 'Attendance history',
                actionLabel: 'Refresh',
                onAction: _refresh,
              ),
              const SizedBox(height: 8),
              _AttendanceHistory(repository: widget.repository),
              if (!widget.session.isDemo) ...[
                const SizedBox(height: 13),
                OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      backgroundColor: Palette.ivory,
                      builder: (_) =>
                          CorrectionEditor(repository: widget.repository),
                    );
                    if (saved == true) _refresh();
                  },
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: const Text('Request an attendance correction'),
                ),
                const SizedBox(height: 17),
                SectionHeading(
                  title: widget.session.role.isAdmin
                      ? 'Review missed / incorrect punches'
                      : widget.session.role.canReview
                      ? 'Review team punch requests'
                      : 'My punch requests',
                  actionLabel: 'Refresh',
                  onAction: _refresh,
                ),
                const SizedBox(height: 8),
                _AttendanceCorrections(
                  repository: widget.repository,
                  canReview: widget.session.role.canReview,
                ),
                const SizedBox(height: 20),
                SectionHeading(
                  title: widget.session.role.canReview
                      ? 'Leave requests'
                      : 'My leave requests',
                  actionLabel: 'Refresh',
                  onAction: _refresh,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _applyForLeave,
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Apply for leave'),
                ),
                const SizedBox(height: 11),
                _LeaveRequests(
                  future: _leaveRequestsFuture,
                  repository: widget.repository,
                  canReview: widget.session.role.canReview,
                  onChanged: _refresh,
                ),
              ],
              if (widget.session.role.canAssign && !widget.session.isDemo) ...[
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  onPressed: _addSite,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Manage approved sites'),
                ),
              ],
            ],
          );
        },
      );
    },
  );
}

String _correctionTypeLabel(Object? type) => switch ('$type') {
  'incorrect_punch' => 'Incorrect / false punch',
  _ => 'Missed punch',
};

class _AttendanceSummaryCard extends StatelessWidget {
  const _AttendanceSummaryCard({required this.future, required this.isDemo});
  final Future<Map<String, Object?>> future;
  final bool isDemo;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SurfaceCard(
          child: Text(
            'Attendance totals are unavailable right now.',
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const SurfaceCard(child: LinearProgressIndicator(minHeight: 2));
      }
      final summary = snapshot.data!;
      final month =
          DateTime.tryParse('${summary['month_start']}') ?? DateTime.now();
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final monthLabel = '${months[month.month - 1]} ${month.year}';
      final present = _attendanceDayCount(summary['present_days']);
      final leave = _attendanceDayCount(summary['approved_leave_days']);
      final absent = _attendanceDayCount(summary['absent_days']);
      final holidays =
          int.tryParse('${summary['paid_holiday_days'] ?? 0}') ?? 0;
      final workMinutes =
          int.tryParse('${summary['worked_minutes'] ?? 0}') ?? 0;
      final leaveBalance =
          double.tryParse('${summary['paid_leave_balance'] ?? 0}') ?? 0;
      return SurfaceCard(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  color: Palette.blue,
                  size: 19,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'My monthly totals',
                    style: TextStyle(
                      color: Palette.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  monthLabel,
                  style: const TextStyle(color: Palette.muted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _AttendanceCount(
                    value: present,
                    label: 'Present days',
                    icon: Icons.check_circle_outline_rounded,
                    color: Palette.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AttendanceCount(
                    value: leave,
                    label: 'Approved leave days',
                    icon: Icons.event_available_outlined,
                    color: Palette.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AttendanceCount(
                    value: absent,
                    label: 'Absent days',
                    icon: Icons.event_busy_outlined,
                    color: Palette.red,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AttendanceCount(
                    value: leaveBalance.toStringAsFixed(1),
                    label: 'Paid leave balance',
                    icon: Icons.account_balance_wallet_outlined,
                    color: Palette.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _AttendanceCount(
              value: '${workMinutes ~/ 60}h ${workMinutes % 60}m',
              label: 'Worked this month',
              icon: Icons.schedule_rounded,
              color: Palette.navy,
            ),
            const SizedBox(height: 10),
            Text(
              isDemo
                  ? 'Preview mode shows sample totals only.'
                  : 'Two paid days accrue each month from November 2026. Approved paid leave counts as present and is deducted only for days you are absent. Unpaid leave counts as absent. Sundays and paid holidays count as present; Saturdays count as half days unless Admin sets full-day credit. $holidays paid holiday ${holidays == 1 ? 'day' : 'days'} this month.',
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PaidHolidayCalendar extends StatelessWidget {
  const _PaidHolidayCalendar({required this.future});
  final Future<List<Map<String, Object?>>> future;

  DateTime? _date(Map<String, Object?> holiday) =>
      DateTime.tryParse('${holiday['holiday_date']}');

  Future<void> _showAll(
    BuildContext context,
    List<Map<String, Object?>> holidays,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paid holidays'),
        content: SizedBox(
          width: 460,
          height: 460,
          child: holidays.isEmpty
              ? const Center(child: Text('No paid holidays have been added.'))
              : ListView.separated(
                  itemCount: holidays.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final holiday = holidays[index];
                    final date = _date(holiday);
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.celebration_outlined,
                        color: Palette.blue,
                      ),
                      title: Text('${holiday['name'] ?? 'Paid holiday'}'),
                      subtitle: Text(
                        date == null
                            ? '${holiday['holiday_date'] ?? ''}'
                            : formattedDate(date, withYear: true),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const SizedBox.shrink();
      if (!snapshot.hasData) {
        return const SurfaceCard(child: LinearProgressIndicator(minHeight: 2));
      }
      final holidays = [...snapshot.data!]
        ..sort(
          (a, b) => '${a['holiday_date']}'.compareTo('${b['holiday_date']}'),
        );
      final today = DateTime.now();
      final upcoming = holidays
          .where((holiday) {
            final date = _date(holiday);
            return date != null &&
                !date.isBefore(DateTime(today.year, today.month, today.day));
          })
          .take(5)
          .toList();
      return SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.celebration_outlined,
                  color: Palette.blue,
                  size: 19,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Paid holidays',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () => _showAll(context, holidays),
                  child: const Text('View all'),
                ),
              ],
            ),
            if (upcoming.isEmpty)
              const Text(
                'No upcoming paid holidays.',
                style: TextStyle(color: Palette.muted, fontSize: 11),
              )
            else
              for (final holiday in upcoming)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '${formattedDate(_date(holiday)!, withYear: true)}  ·  ${holiday['name'] ?? 'Paid holiday'}',
                    style: const TextStyle(color: Palette.ink, fontSize: 11),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

String _attendanceDayCount(Object? value) {
  final days = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  return days == days.roundToDouble()
      ? days.toInt().toString()
      : days.toStringAsFixed(1);
}

class _AttendanceCount extends StatelessWidget {
  const _AttendanceCount({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .12)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 2,
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 9,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AdminAttendanceWorkspace extends StatefulWidget {
  const _AdminAttendanceWorkspace({
    required this.repository,
    required this.onChanged,
  });
  final WorkspaceRepository repository;
  final Future<void> Function() onChanged;
  @override
  State<_AdminAttendanceWorkspace> createState() =>
      _AdminAttendanceWorkspaceState();
}

class _AdminAttendanceWorkspaceState extends State<_AdminAttendanceWorkspace> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<Map<String, Object?>>> _report = widget.repository
      .adminAttendanceReport(month: _month);
  late Future<List<Map<String, Object?>>> _holidays = widget.repository
      .paidHolidays();
  bool _busy = false;

  void _reload() => setState(() {
    _report = widget.repository.adminAttendanceReport(month: _month);
    _holidays = widget.repository.paidHolidays();
  });

  void _moveMonth(int amount) => setState(() {
    _month = DateTime(_month.year, _month.month + amount);
    _report = widget.repository.adminAttendanceReport(month: _month);
  });

  String _hours(Object? value) {
    final minutes = (value as num?)?.toInt() ?? 0;
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }

  void _error(Object error) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final rows = await widget.repository.adminAttendanceReport(month: _month);
      await NativeBridge.saveSpreadsheet(
        name: XlsxWorkbooks.attendanceFileName(_month),
        bytes: XlsxWorkbooks.buildAttendanceReport(rows, _month),
      );
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _template() async {
    try {
      await NativeBridge.saveSpreadsheet(
        name: XlsxWorkbooks.holidayTemplateFileName(),
        bytes: XlsxWorkbooks.buildHolidayTemplate(),
      );
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _import() async {
    try {
      final file = await NativeBridge.chooseSpreadsheet();
      if (file == null) return;
      final holidays = XlsxWorkbooks.parsePaidHolidays(file.bytes);
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import paid holidays?'),
          content: Text(
            '${holidays.length} holidays from ${file.name} will be added. Existing dates will be updated.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      setState(() => _busy = true);
      await widget.repository.importPaidHolidays(holidays);
      _reload();
      await widget.onChanged();
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addHoliday() async {
    final name = TextEditingController();
    var date = DateTime.now();
    final item = await showDialog<Map<String, Object?>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Add paid holiday'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Holiday name'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (value != null) setDialog(() => date = value);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(formattedDate(date, withYear: true)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'date': date.toIso8601String().split('T').first,
                  'name': name.text.trim(),
                  'paid_days': 1,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (item == null) return;
    try {
      await widget.repository.importPaidHolidays([item]);
      _reload();
      await widget.onChanged();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _editLeaveSettings(Map<String, Object?> person) async {
    var start = DateTime.tryParse('${person['leave_accrual_start']}') ?? _month;
    final opening = TextEditingController(
      text: '${person['leave_opening_balance'] ?? 0}',
    );
    final result = await showDialog<Map<String, Object?>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Paid leave · ${person['display_name'] ?? 'Employee'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Two paid days accrue each month from November 2026. Unused days carry forward. Set the employee’s current balance from the attendance list.',
                style: TextStyle(fontSize: 12, color: Palette.muted),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: start,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (value != null) setDialog(() => start = value);
                },
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  'Accrual starts · ${formattedDate(start, withYear: true)}',
                ),
              ),
              TextField(
                controller: opening,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Opening balance (days)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(opening.text.trim());
                if (value == null || value < 0) return;
                Navigator.pop(context, {'start': start, 'opening': value});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    opening.dispose();
    if (result == null) return;
    try {
      await widget.repository.updateEmployeeAttendanceSettings(
        userId: '${person['user_id']}',
        saturdayFullDayCredit: person['saturday_full_day_credit'] == true,
        leaveAccrualStart: result['start']! as DateTime,
        leaveOpeningBalance: result['opening']! as double,
      );
      _reload();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _setCurrentPaidLeaveBalance(Map<String, Object?> person) async {
    final balance = TextEditingController(
      text: '${person['paid_leave_balance'] ?? 0}',
    );
    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Paid leave · ${person['display_name'] ?? 'Employee'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Two paid days accrue each month from November 2026. Set this employee’s current balance; the change is recorded in the audit log.',
              style: TextStyle(fontSize: 12, color: Palette.muted),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: balance,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Current balance (days)',
                hintText: 'For example, 4 or 3.5',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(balance.text.trim());
              if (value == null ||
                  value < 0 ||
                  value > 500 ||
                  value * 2 != (value * 2).roundToDouble()) {
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Save balance'),
          ),
        ],
      ),
    );
    balance.dispose();
    if (result == null) return;
    try {
      await widget.repository.setEmployeePaidLeaveBalance(
        userId: '${person['user_id']}',
        balance: result,
      );
      _reload();
      await widget.onChanged();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _toggleSaturday(Map<String, Object?> person, bool value) async {
    try {
      await widget.repository.updateEmployeeAttendanceSettings(
        userId: '${person['user_id']}',
        saturdayFullDayCredit: value,
        leaveAccrualStart:
            DateTime.tryParse('${person['leave_accrual_start']}') ?? _month,
        leaveOpeningBalance:
            double.tryParse('${person['leave_opening_balance'] ?? 0}') ?? 0,
      );
      _reload();
    } catch (error) {
      _error(error);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Palette.blue,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Admin attendance',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const Text(
              'Review everyone’s attendance, leave, absences, punch times and work hours. Saturdays count as half days unless you enable full-day credit per employee.',
              style: TextStyle(color: Palette.muted, fontSize: 11),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_month.year}-${_month.month.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(
                _busy ? 'Preparing Excel…' : 'Export attendance Excel',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(45),
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 5,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addHoliday,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add paid holiday'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.upload_file_outlined, size: 16),
                  label: const Text('Import Excel'),
                ),
                TextButton.icon(
                  onPressed: _template,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Holiday template'),
                ),
              ],
            ),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _holidays,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty)
                  return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    'Paid holidays: ${snapshot.data!.take(6).map((h) => '${h['holiday_date']} · ${h['name']}').join('  |  ')}',
                    style: const TextStyle(
                      color: Palette.muted,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 9),
      FutureBuilder<List<Map<String, Object?>>>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return EmptyInline(
              icon: Icons.table_chart_outlined,
              title: 'Attendance report unavailable',
              detail: snapshot.error.toString(),
            );
          if (!snapshot.hasData)
            return const LinearProgressIndicator(minHeight: 2);
          if (snapshot.data!.isEmpty)
            return const EmptyInline(
              icon: Icons.people_outline,
              title: 'No active employees',
              detail: 'Employee attendance will appear here.',
            );
          return Column(
            children: [
              for (final person in snapshot.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: SurfaceCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        '${person['display_name'] ?? 'Employee'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: Text(
                        '${person['employee_id'] ?? ''} · Present ${_attendanceDayCount(person['present_days'])} · Leave ${_attendanceDayCount(person['leave_days'])} · Absent ${_attendanceDayCount(person['absent_days'])} · ${_hours(person['worked_minutes'] ?? 0)}',
                        style: const TextStyle(
                          color: Palette.muted,
                          fontSize: 10,
                          height: 1.5,
                        ),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Paid leave balance · ${person['paid_leave_balance'] ?? 0} days',
                            style: const TextStyle(
                              color: Palette.blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () =>
                                _setCurrentPaidLeaveBalance(person),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 16,
                            ),
                            label: const Text('Set current paid leave balance'),
                          ),
                        ),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: person['saturday_full_day_credit'] == true,
                          title: const Text(
                            'Credit worked Saturdays as a full day',
                            style: TextStyle(fontSize: 11),
                          ),
                          subtitle: const Text(
                            'When off, an attended Saturday counts as 0.5 day.',
                            style: TextStyle(fontSize: 10),
                          ),
                          onChanged: (value) => _toggleSaturday(person, value),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _editLeaveSettings(person),
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: const Text(
                              'Adjust leave start and opening balance',
                            ),
                          ),
                        ),
                        if (person['daily'] is List)
                          for (final day
                              in (person['daily'] as List).whereType<Map>())
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${day['date']} · ${day['status']}${'${day['day_note'] ?? ''}'.isEmpty ? '' : ' · ${day['day_note']}'} · ${_attendanceDayCount(day['credited_days'])} day credit · ${day['punch_in'] == null ? '—' : _localDateTime('${day['punch_in']}')} → ${day['punch_out'] == null ? '—' : _localDateTime('${day['punch_out']}')} · ${_hours(day['worked_minutes'] ?? 0)}${'${day['holiday_name'] ?? ''}'.isEmpty ? '' : ' · ${day['holiday_name']}'}',
                                  style: const TextStyle(
                                    color: Palette.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                        const SizedBox(height: 7),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _AttendanceLockedCard extends StatelessWidget {
  const _AttendanceLockedCard({
    required this.title,
    required this.detail,
    required this.icon,
    this.action,
  });
  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: Palette.sand,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Palette.navy),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Palette.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                detail,
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 13),
                OutlinedButton.icon(
                  onPressed: action,
                  icon: const Icon(Icons.add_location_alt_outlined, size: 17),
                  label: const Text('Add real site'),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.fix,
    required this.site,
    required this.distance,
    required this.allowed,
  });
  final LocationFix fix;
  final AttendanceSite site;
  final double distance;
  final bool allowed;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              allowed ? Icons.verified_rounded : Icons.gps_not_fixed_rounded,
              color: allowed ? Palette.green : Palette.amber,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                allowed ? 'Location verified' : 'Location not verified',
                style: TextStyle(
                  color: allowed ? Palette.green : Palette.amber,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            StatusPill(value: allowed ? 'Ready' : 'Blocked'),
          ],
        ),
        const SizedBox(height: 12),
        _InfoPair(label: 'Selected site', value: site.name),
        _InfoPair(
          label: 'Distance from site',
          value: '${distance.round()} m  /  ${site.radiusMeters} m radius',
        ),
        _InfoPair(
          label: 'GPS accuracy',
          value: '±${fix.accuracyMeters.round()} m',
        ),
        if (fix.isMocked)
          const _InfoPair(
            label: 'Device signal',
            value: 'Simulated location flagged',
          ),
      ],
    ),
  );
}

class _AttendanceHistory extends StatelessWidget {
  const _AttendanceHistory({required this.repository});
  final WorkspaceRepository repository;
  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: repository.siteHistory(),
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return const EmptyInline(
          icon: Icons.history_rounded,
          title: 'History unavailable',
          detail: 'Connect to your live workspace to load verified events.',
        );
      if (!snapshot.hasData) return const LinearProgressIndicator(minHeight: 2);
      final rows = snapshot.data!;
      if (rows.isEmpty)
        return EmptyInline(
          icon: Icons.history_rounded,
          title: 'No punches yet',
          detail: repository.isDemo
              ? 'Preview mode does not create attendance history.'
              : 'Your verified punch-in and punch-out events will appear here.',
        );
      return Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.fingerprint_rounded,
                      color: Palette.blue,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['action'] ?? 'Attendance'} · ${row['site_name'] ?? 'Approved site'}',
                            style: const TextStyle(
                              color: Palette.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _localDateTime('${row['created_at']}'),
                            style: const TextStyle(
                              color: Palette.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '±${(row['accuracy_meters'] as num?)?.round() ?? 0} m',
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class CorrectionEditor extends StatefulWidget {
  const CorrectionEditor({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<CorrectionEditor> createState() => _CorrectionEditorState();
}

class _CorrectionEditorState extends State<CorrectionEditor> {
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  String _requestType = 'missed_punch';
  TimeOfDay? _requestedIn;
  TimeOfDay? _requestedOut;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _pickTime(bool isIn) async {
    final time = await showTimePicker(
      context: context,
      initialTime: isIn
          ? (_requestedIn ?? const TimeOfDay(hour: 9, minute: 0))
          : (_requestedOut ?? const TimeOfDay(hour: 17, minute: 0)),
    );
    if (time != null)
      setState(() {
        isIn ? _requestedIn = time : _requestedOut = time;
      });
  }

  DateTime? _combine(TimeOfDay? time) => time == null
      ? null
      : DateTime(_date.year, _date.month, _date.day, time.hour, time.minute);
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance correction',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'This asks a reviewer to correct a record. It never creates a punch or changes location history.',
            style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined),
            label: Text('Shift date · ${formattedDate(_date, withYear: true)}'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _requestType,
            decoration: const InputDecoration(labelText: 'Request type'),
            items: const [
              DropdownMenuItem(
                value: 'missed_punch',
                child: Text('Missed punch'),
              ),
              DropdownMenuItem(
                value: 'incorrect_punch',
                child: Text('Incorrect / false punch'),
              ),
            ],
            onChanged: (value) => setState(() {
              if (value != null) _requestType = value;
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(true),
                  icon: const Icon(Icons.login_rounded, size: 17),
                  label: Text(
                    _requestedIn == null
                        ? 'Requested in'
                        : _requestedIn!.format(context),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(false),
                  icon: const Icon(Icons.logout_rounded, size: 17),
                  label: Text(
                    _requestedOut == null
                        ? 'Requested out'
                        : _requestedOut!.format(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const Text(
            'Enter the corrected in or out time. An Admin or Team Leader will review the request.',
            style: TextStyle(color: Palette.muted, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Explain what needs correction',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Palette.red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 13),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_requestedIn == null && _requestedOut == null ||
                        _reason.text.trim().isEmpty) {
                      setState(
                        () => _error =
                            'Add at least one requested time and a reason.',
                      );
                      return;
                    }
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await widget.repository.submitAttendanceCorrection(
                        date: _date,
                        requestType: _requestType,
                        requestedIn:
                            _combine(_requestedIn)?.toIso8601String() ?? '',
                        requestedOut:
                            _combine(_requestedOut)?.toIso8601String() ?? '',
                        reason: _reason.text.trim(),
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (error) {
                      if (mounted) setState(() => _error = error.toString());
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Send for review'),
          ),
        ],
      ),
    ),
  );
}

class _AttendanceCorrections extends StatefulWidget {
  const _AttendanceCorrections({
    required this.repository,
    required this.canReview,
  });
  final WorkspaceRepository repository;
  final bool canReview;
  @override
  State<_AttendanceCorrections> createState() => _AttendanceCorrectionsState();
}

class _AttendanceCorrectionsState extends State<_AttendanceCorrections> {
  late Future<List<Map<String, Object?>>> _future = widget.repository
      .attendanceCorrections();
  Future<void> _refresh() async =>
      setState(() => _future = widget.repository.attendanceCorrections());
  Future<void> _review(Map<String, Object?> item) async {
    final decision = await _reviewDialog(
      context,
      title: 'Review punch correction',
      body:
          '${(item['requester'] as Map?)?['display_name'] ?? 'Workspace member'} · ${_correctionTypeLabel(item['request_type'])}\n${item['event_date']}${widget.repository.session.role.isAdmin && '${item['reason'] ?? ''}'.isNotEmpty ? '\n${item['reason']}' : ''}',
      rejectLabel: 'Reject request',
      rejectStatus: 'rejected',
    );
    if (decision == null) return;
    try {
      await widget.repository.reviewAttendanceCorrection(
        '${item['id']}',
        decision.status == 'approved' ? 'approved' : 'rejected',
        decision.comment,
      );
      await _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return EmptyInline(
          icon: Icons.rule_outlined,
          title: 'Requests unavailable',
          detail: snapshot.error.toString(),
        );
      if (!snapshot.hasData) return const LinearProgressIndicator(minHeight: 2);
      if (snapshot.data!.isEmpty)
        return const EmptyInline(
          icon: Icons.rule_outlined,
          title: 'No correction requests',
          detail: 'Requests stay separate from verified attendance events.',
        );
      return Column(
        children: [
          for (final item in snapshot.data!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SurfaceCard(
                onTap: widget.canReview && '${item['status']}' == 'submitted'
                    ? () => _review(item)
                    : null,
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_calendar_outlined,
                      color: Palette.blue,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${(item['requester'] as Map?)?['display_name'] ?? 'Workspace member'} · ${_correctionTypeLabel(item['request_type'])}',
                            style: const TextStyle(
                              color: Palette.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item['event_date']}${widget.repository.session.role.isAdmin && '${item['reason'] ?? ''}'.isNotEmpty ? ' · ${item['reason']}' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Palette.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(value: '${item['status'] ?? 'submitted'}'),
                    if (widget.canReview &&
                        '${item['status']}' == 'submitted') ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.rate_review_outlined,
                        size: 18,
                        color: Palette.blue,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _LeaveRequests extends StatelessWidget {
  const _LeaveRequests({
    required this.future,
    required this.repository,
    required this.canReview,
    required this.onChanged,
  });
  final Future<List<Map<String, Object?>>> future;
  final WorkspaceRepository repository;
  final bool canReview;
  final Future<void> Function() onChanged;

  Future<void> _review(BuildContext context, Map<String, Object?> item) async {
    final start = DateTime.tryParse('${item['start_date']}');
    final end = DateTime.tryParse('${item['end_date']}');
    final requester = item['requester'];
    final name = requester is Map
        ? '${requester['display_name'] ?? 'Workspace member'}'
        : 'Workspace member';
    final dates = start == null || end == null
        ? '${item['start_date']} – ${item['end_date']}'
        : _leaveDateRange(start, end);
    final payment = item['use_paid_leave'] == true
        ? 'Paid leave · deducted for approved days absent'
        : 'Unpaid leave · approved days count as absent';
    final decision = await _reviewDialog(
      context,
      title: 'Review leave request',
      body:
          '$name · ${_leaveTypeLabel(item['leave_type'])}\n$dates\n$payment${repository.session.role.isAdmin && '${item['reason'] ?? ''}'.isNotEmpty ? '\n${item['reason']}' : ''}',
      rejectLabel: 'Reject leave',
      rejectStatus: 'rejected',
    );
    if (decision == null) return;
    try {
      await repository.reviewLeaveRequest(
        '${item['id']}',
        decision.status == 'approved' ? 'approved' : 'rejected',
        decision.comment,
      );
      await onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return EmptyInline(
          icon: Icons.event_busy_outlined,
          title: 'Leave requests unavailable',
          detail: snapshot.error.toString(),
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator(minHeight: 2);
      if (snapshot.data!.isEmpty) {
        return EmptyInline(
          icon: Icons.event_available_outlined,
          title: 'No leave requests',
          detail: canReview
              ? 'Team leave requests will appear here for review.'
              : 'Your applications and their approval status will appear here.',
        );
      }
      return Column(
        children: [
          for (final item in snapshot.data!)
            Builder(
              builder: (context) {
                final requester = item['requester'];
                final name = requester is Map
                    ? '${requester['display_name'] ?? 'Workspace member'}'
                    : 'Workspace member';
                final start = DateTime.tryParse('${item['start_date']}');
                final end = DateTime.tryParse('${item['end_date']}');
                final status = '${item['status'] ?? 'submitted'}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    onTap: canReview && status == 'submitted'
                        ? () => _review(context, item)
                        : null,
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_available_outlined,
                          color: Palette.blue,
                          size: 19,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${canReview ? '$name · ' : ''}${_leaveTypeLabel(item['leave_type'])}',
                                style: const TextStyle(
                                  color: Palette.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${start == null || end == null ? '${item['start_date']} – ${item['end_date']}' : _leaveDateRange(start, end)}',
                                style: const TextStyle(
                                  color: Palette.muted,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item['use_paid_leave'] == true
                                    ? 'Paid leave · deducted for approved days absent'
                                    : 'Unpaid leave · approved days count as absent',
                                style: const TextStyle(
                                  color: Palette.blue,
                                  fontSize: 10,
                                ),
                              ),
                              if (repository.session.role.isAdmin &&
                                  '${item['reason'] ?? ''}'.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${item['reason']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Palette.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                              if ('${item['review_comment'] ?? ''}'
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Reviewer: ${item['review_comment']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Palette.blue,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 7),
                        StatusPill(value: status),
                        if (canReview && status == 'submitted') ...[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.rate_review_outlined,
                            color: Palette.blue,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

class _LeaveRequestEditor extends StatefulWidget {
  const _LeaveRequestEditor({required this.repository});
  final WorkspaceRepository repository;

  @override
  State<_LeaveRequestEditor> createState() => _LeaveRequestEditorState();
}

class _LeaveRequestEditorState extends State<_LeaveRequestEditor> {
  final _reason = TextEditingController();
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  String _leaveType = 'annual';
  bool _usePaidLeave = true;
  double _paidLeaveBalance = 0;
  bool _busy = false;
  bool _rulesLoading = true;
  bool _saturdayFullDayCredit = false;
  Set<String> _paidHolidayDates = const {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLeaveRules();
  }

  Future<void> _loadLeaveRules() async {
    try {
      final values = await Future.wait([
        widget.repository.myAttendanceSummary(),
        widget.repository.paidHolidays(),
      ]);
      if (!mounted) return;
      final summary = values[0] as Map<String, Object?>;
      final holidays = values[1] as List<Map<String, Object?>>;
      setState(() {
        _saturdayFullDayCredit = summary['saturday_full_day_credit'] == true;
        _paidLeaveBalance =
            double.tryParse('${summary['paid_leave_balance'] ?? 0}') ?? 0;
        _paidHolidayDates = {
          for (final holiday in holidays) '${holiday['holiday_date']}',
        };
        _rulesLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rulesLoading = false;
        _error = 'Could not load leave rules. Close and try again. $error';
      });
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate(bool isStart) async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
        if (_end.isBefore(_start)) _start = _end;
      }
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = leaveWorkdayCount(
      _start,
      _end,
      saturdayFullDayCredit: _saturdayFullDayCredit,
      paidHolidayDates: _paidHolidayDates,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        5,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apply for leave',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose whether to use your paid leave balance. Approved paid leave counts as present and is deducted only for days you are absent; without paid leave, approved days count as absent.',
              style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _leaveType,
              decoration: const InputDecoration(labelText: 'Leave type'),
              items: const [
                DropdownMenuItem(value: 'annual', child: Text('Annual leave')),
                DropdownMenuItem(value: 'sick', child: Text('Sick leave')),
                DropdownMenuItem(
                  value: 'personal',
                  child: Text('Personal leave'),
                ),
                DropdownMenuItem(value: 'unpaid', child: Text('Unpaid leave')),
              ],
              onChanged: (value) => setState(() {
                if (value != null) {
                  _leaveType = value;
                  if (value == 'unpaid') _usePaidLeave = false;
                }
              }),
            ),
            const SizedBox(height: 5),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _usePaidLeave && _leaveType != 'unpaid',
              onChanged: _leaveType == 'unpaid'
                  ? null
                  : (value) => setState(() => _usePaidLeave = value),
              title: const Text('Use my paid leave balance'),
              subtitle: Text(
                _leaveType == 'unpaid'
                    ? 'Unpaid leave is recorded as absent.'
                    : 'Available: ${_paidLeaveBalance.toStringAsFixed(1)} days. The balance is charged for approved days you are absent.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.event_outlined, size: 17),
                    label: Text(
                      'From · ${formattedDate(_start, withYear: true)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.event_outlined, size: 17),
                    label: Text('To · ${formattedDate(_end, withYear: true)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_attendanceDayCount(days)} leave ${days == 1 ? 'day' : 'days'} requested',
              style: const TextStyle(
                color: Palette.blue,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              maxLength: 1200,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Tell the reviewer why you need leave',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Palette.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy || _rulesLoading
                  ? null
                  : () async {
                      if (days <= 0) {
                        setState(
                          () => _error =
                              'Choose at least one non-Sunday leave day.',
                        );
                        return;
                      }
                      if (_usePaidLeave && days > _paidLeaveBalance) {
                        setState(
                          () => _error =
                              'This request needs ${_attendanceDayCount(days)} paid days, but your balance is ${_paidLeaveBalance.toStringAsFixed(1)} days. Turn off paid leave or shorten the request.',
                        );
                        return;
                      }
                      if (_reason.text.trim().isEmpty) {
                        setState(
                          () => _error = 'Add a reason for your leave request.',
                        );
                        return;
                      }
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        await widget.repository.submitLeaveRequest(
                          leaveType: _leaveType,
                          usePaidLeave: _usePaidLeave && _leaveType != 'unpaid',
                          start: _start,
                          end: _end,
                          reason: _reason.text.trim(),
                          saturdayFullDayCredit: _saturdayFullDayCredit,
                          paidHolidayDates: _paidHolidayDates,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        if (mounted) setState(() => _error = error.toString());
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(
                _rulesLoading
                    ? 'Loading leave rules…'
                    : _busy
                    ? 'Sending request…'
                    : 'Submit leave request',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _leaveTypeLabel(Object? type) => switch ('$type') {
  'annual' => 'Annual leave',
  'sick' => 'Sick leave',
  'personal' => 'Personal leave',
  'unpaid' => 'Unpaid leave',
  _ => 'Leave',
};

String _leaveDateRange(DateTime start, DateTime end) =>
    start.year == end.year && start.month == end.month && start.day == end.day
    ? formattedDate(start, withYear: true)
    : '${formattedDate(start, withYear: true)} – ${formattedDate(end, withYear: true)}';

class SiteEditor extends StatefulWidget {
  const SiteEditor({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<SiteEditor> createState() => _SiteEditorState();
}

class _SiteEditorState extends State<SiteEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  late final Future<List<ProjectItem>> _projects = widget.repository
      .manageableProjects();
  String _kind = 'office';
  String? _projectId;
  double _radius = 100;
  bool _busy = false;
  bool _findingGps = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.repository.session.role == UserRole.teamLeader)
      _kind = 'project';
  }

  @override
  void dispose() {
    _name.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _findingGps = true;
      _error = null;
    });
    try {
      final fix = await NativeBridge.currentLocation();
      if (fix.accuracyMeters > 35 || fix.isMocked)
        throw Exception(
          'Use a precise, non-simulated GPS reading (35 m accuracy or better).',
        );
      _latitude.text = fix.latitude.toStringAsFixed(7);
      _longitude.text = fix.longitude.toStringAsFixed(7);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _findingGps = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final lat = double.parse(_latitude.text.trim());
    final lon = double.parse(_longitude.text.trim());
    if (lat.abs() > 90 || lon.abs() > 180) {
      setState(() => _error = 'Enter valid latitude and longitude.');
      return;
    }
    if (_kind == 'project' && _projectId == null) {
      setState(() => _error = 'Choose the project connected to this site.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createSite(
        name: _name.text.trim(),
        kind: _kind,
        latitude: lat,
        longitude: lon,
        radiusMeters: _radius.round(),
        projectId: _kind == 'project' ? _projectId : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add attendance site',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter a real location. The app will not add any sample coordinates.',
              style: TextStyle(color: Palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 15),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Site name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add a site name.'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Site type'),
              items: [
                const DropdownMenuItem(value: 'office', child: Text('Office')),
                const DropdownMenuItem(
                  value: 'project',
                  child: Text('Project site'),
                ),
              ],
              onChanged: (value) => setState(() => _kind = value ?? 'project'),
            ),
            if (_kind == 'project') ...[
              const SizedBox(height: 12),
              FutureBuilder<List<ProjectItem>>(
                future: _projects,
                builder: (context, snapshot) => snapshot.hasData
                    ? DropdownButtonFormField<String>(
                        initialValue:
                            _projectId ??
                            (snapshot.data!.isNotEmpty
                                ? snapshot.data!.first.id
                                : null),
                        decoration: const InputDecoration(
                          labelText: 'Assigned project',
                        ),
                        items: snapshot.data!
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Text(item.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _projectId = value),
                      )
                    : const LinearProgressIndicator(minHeight: 2),
              ),
            ],
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    validator: _coordinateRequired,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _longitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    validator: _coordinateRequired,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _findingGps ? null : _useCurrentLocation,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(
                _findingGps ? 'Reading GPS…' : 'Use my current GPS position',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Allowed radius',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${_radius.round()} m',
                  style: const TextStyle(
                    color: Palette.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Slider(
              value: _radius,
              min: 50,
              max: 500,
              divisions: 18,
              label: '${_radius.round()} m',
              onChanged: (value) => setState(() => _radius = value),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Palette.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 11),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save approved site'),
            ),
          ],
        ),
      ),
    ),
  );
}

String? _coordinateRequired(String? value) =>
    value == null || double.tryParse(value.trim()) == null
    ? 'Enter a coordinate.'
    : null;

class ReportsView extends StatefulWidget {
  const ReportsView({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView>
    with SingleTickerProviderStateMixin {
  late Future<_ReportData> _future;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_ReportData> _load() async {
    final values = await Future.wait([
      widget.repository.reports(),
      widget.repository.weeklySummaries(),
    ]);
    return _ReportData(
      values[0] as List<DailyReport>,
      values[1] as List<Map<String, Object?>>,
    );
  }

  Future<void> _refresh() async => setState(() => _future = _load());

  Future<void> _openEditor({required bool weekly}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => weekly
          ? WeeklySummaryEditor(repository: widget.repository)
          : DailyReportEditor(repository: widget.repository),
    );
    if (saved == true) _refresh();
  }

  Future<void> _reviewDaily(DailyReport report) async {
    final decision = await _reviewDialog(
      context,
      title: 'Review daily report',
      body: 'Choose whether to approve this report or request a revision.',
    );
    if (decision == null) return;
    try {
      await widget.repository.reviewReport(
        report,
        decision.status,
        decision.comment,
      );
      await _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reviewWeekly(Map<String, Object?> report) async {
    final decision = await _reviewDialog(
      context,
      title: 'Review weekly summary',
      body: 'Choose whether to approve this summary or request a revision.',
    );
    if (decision == null) return;
    try {
      await widget.repository.reviewWeeklySummary(
        '${report['id']}',
        decision.status,
        decision.comment,
      );
      await _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReportData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return ErrorState(
          message: snapshot.error.toString(),
          onRetry: _refresh,
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progress worth sharing.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 7),
                const Text(
                  'Daily notes become a useful record of the work.',
                  style: TextStyle(color: Palette.muted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TabBar(
                  controller: _tabs,
                  labelColor: Palette.navy,
                  unselectedLabelColor: Palette.muted,
                  indicatorColor: Palette.blue,
                  tabs: const [
                    Tab(text: 'Daily reports'),
                    Tab(text: 'Weekly summary'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    children: [
                      if (widget.session.role.canReview)
                        const _ReviewInfoBanner(),
                      if (data.daily.isEmpty)
                        EmptyInline(
                          icon: Icons.edit_note_rounded,
                          title: 'No daily reports yet',
                          detail: 'Submit today’s progress; your team lead can review it.',
                          actionLabel: 'Write report',
                          onAction: () => _openEditor(weekly: false),
                        )
                      else
                        for (final report in data.daily)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DailyReportCard(
                              report: report,
                              canReview: widget.session.role.canReview,
                              onTap: () =>
                                  widget.session.role.canReview &&
                                      report.status != 'approved'
                                  ? _reviewDaily(report)
                                  : _showDailyDetail(context, report),
                            ),
                          ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _openEditor(weekly: false),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Write daily report'),
                      ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                    children: [
                      _WeeklyPrompt(),
                      const SizedBox(height: 12),
                      if (data.weekly.isEmpty)
                        EmptyInline(
                          icon: Icons.date_range_rounded,
                          title: 'No weekly summary yet',
                          detail: 'Bring the week together with progress, blockers and your next plan.',
                          actionLabel: 'Write summary',
                          onAction: () => _openEditor(weekly: true),
                        )
                      else
                        for (final report in data.weekly)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _WeeklyCard(
                              report: report,
                              canReview: widget.session.role.canReview,
                              onTap: () =>
                                  widget.session.role.canReview &&
                                      '${report['status']}' != 'approved'
                                  ? _reviewWeekly(report)
                                  : _showWeeklyDetail(context, report),
                            ),
                          ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _openEditor(weekly: true),
                        icon: const Icon(Icons.summarize_outlined),
                        label: const Text('Write weekly summary'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _ReportData {
  const _ReportData(this.daily, this.weekly);
  final List<DailyReport> daily;
  final List<Map<String, Object?>> weekly;
}

class _ReviewInfoBanner extends StatelessWidget {
  const _ReviewInfoBanner();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 13),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1F7),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Row(
      children: [
        Icon(Icons.fact_check_outlined, color: Palette.navy, size: 18),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'Tap a submitted report to approve it or request a revision.',
            style: TextStyle(color: Palette.navy, fontSize: 11, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _DailyReportCard extends StatelessWidget {
  const _DailyReportCard({
    required this.report,
    required this.canReview,
    required this.onTap,
  });
  final DailyReport report;
  final bool canReview;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                formattedDate(report.date, withYear: true),
                style: const TextStyle(
                  color: Palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            StatusPill(value: report.status),
          ],
        ),
        if (report.projectName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            report.projectName,
            style: const TextStyle(color: Palette.muted, fontSize: 11),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          report.completed.isEmpty
              ? 'No completed work added.'
              : report.completed,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Palette.ink, height: 1.4, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 15, color: Palette.muted),
            const SizedBox(width: 5),
            Text(
              '${report.hours.toStringAsFixed(1)} h logged',
              style: const TextStyle(color: Palette.muted, fontSize: 10),
            ),
            const Spacer(),
            Text(
              canReview && report.status != 'approved'
                  ? 'Review report'
                  : 'Open details',
              style: const TextStyle(
                color: Palette.blue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Palette.blue,
              size: 18,
            ),
          ],
        ),
      ],
    ),
  );
}

class _WeeklyPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Palette.navy,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      children: [
        Icon(Icons.auto_graph_rounded, color: Palette.powder, size: 23),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A thoughtful close to the week',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Capture outcomes, blockers and what comes next.',
                style: TextStyle(color: Palette.powder, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({
    required this.report,
    required this.canReview,
    required this.onTap,
  });
  final Map<String, Object?> report;
  final bool canReview;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    padding: const EdgeInsets.all(15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Week of ${report['week_start'] ?? '—'}',
                style: const TextStyle(
                  color: Palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            StatusPill(value: '${report['status'] ?? 'submitted'}'),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          '${report['summary'] ?? ''}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Palette.ink, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              canReview && '${report['status']}' != 'approved'
                  ? 'Review summary'
                  : 'Open details',
              style: const TextStyle(
                color: Palette.blue,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right_rounded,
              color: Palette.blue,
              size: 18,
            ),
          ],
        ),
      ],
    ),
  );
}

class DailyReportEditor extends StatefulWidget {
  const DailyReportEditor({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<DailyReportEditor> createState() => _DailyReportEditorState();
}

class _DailyReportEditorState extends State<DailyReportEditor> {
  final _formKey = GlobalKey<FormState>();
  final _completed = TextEditingController();
  final _inProgress = TextEditingController();
  final _pending = TextEditingController();
  final _issues = TextEditingController();
  final _tomorrow = TextEditingController();
  late final Future<List<ProjectItem>> _projects = widget.repository.projects();
  String? _projectId;
  double _hours = 8;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final controller in [
      _completed,
      _inProgress,
      _pending,
      _issues,
      _tomorrow,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily work report',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 5),
            Text(
              'Today · ${formattedDate(DateTime.now(), withYear: true)}',
              style: const TextStyle(color: Palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<ProjectItem>>(
              future: _projects,
              builder: (context, snapshot) =>
                  snapshot.hasData && snapshot.data!.isNotEmpty
                  ? DropdownButtonFormField<String?>(
                      initialValue: _projectId,
                      decoration: const InputDecoration(
                        labelText: 'Project (optional)',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No specific project'),
                        ),
                        ...snapshot.data!.map(
                          (item) => DropdownMenuItem<String?>(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _projectId = value),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            _reportField(
              _completed,
              'Completed work',
              'What did you finish?',
              required: true,
            ),
            const SizedBox(height: 11),
            _reportField(_inProgress, 'In progress', 'What is moving forward?'),
            const SizedBox(height: 11),
            _reportField(
              _pending,
              'Pending work',
              'What still needs attention?',
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Hours spent',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${_hours.toStringAsFixed(1)} h',
                  style: const TextStyle(
                    color: Palette.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Slider(
              value: _hours,
              min: 0,
              max: 16,
              divisions: 32,
              onChanged: (value) => setState(() => _hours = value),
            ),
            const SizedBox(height: 7),
            _reportField(_issues, 'Challenges', 'Any blockers or issues?'),
            const SizedBox(height: 11),
            _reportField(
              _tomorrow,
              'Plan for tomorrow',
              'What will you focus on?',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Palette.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        await widget.repository.submitReport(
                          completed: _completed.text.trim(),
                          inProgress: _inProgress.text.trim(),
                          pending: _pending.text.trim(),
                          hours: _hours,
                          issues: _issues.text.trim(),
                          tomorrow: _tomorrow.text.trim(),
                          projectId: _projectId,
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        if (mounted) setState(() => _error = error.toString());
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit for review'),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _reportField(
  TextEditingController controller,
  String title,
  String hint, {
  bool required = false,
}) => TextFormField(
  controller: controller,
  maxLines: 3,
  decoration: InputDecoration(
    labelText: title,
    hintText: hint,
    alignLabelWithHint: true,
  ),
  validator: required
      ? (value) => value == null || value.trim().isEmpty
            ? 'Add a short note about completed work.'
            : null
      : null,
);

class WeeklySummaryEditor extends StatefulWidget {
  const WeeklySummaryEditor({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<WeeklySummaryEditor> createState() => _WeeklySummaryEditorState();
}

class _WeeklySummaryEditorState extends State<WeeklySummaryEditor> {
  final _formKey = GlobalKey<FormState>();
  final _summary = TextEditingController();
  final _blockers = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _summary.dispose();
    _blockers.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 7),
            const Text(
              'Summarize the week, then look ahead.',
              style: TextStyle(color: Palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _reportField(
              _summary,
              'Wins and progress',
              'What moved forward this week?',
              required: true,
            ),
            const SizedBox(height: 11),
            _reportField(
              _blockers,
              'Blockers',
              'What needs help or a decision?',
            ),
            const SizedBox(height: 11),
            _reportField(
              _next,
              'Next week plan',
              'What is the most important next step?',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Palette.red, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        await widget.repository.submitWeeklySummary(
                          summary: _summary.text.trim(),
                          blockers: _blockers.text.trim(),
                          nextWeek: _next.text.trim(),
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (error) {
                        if (mounted) setState(() => _error = error.toString());
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit weekly summary'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReviewDecision {
  const _ReviewDecision(this.status, this.comment);
  final String status;
  final String comment;
}

Future<_ReviewDecision?> _reviewDialog(
  BuildContext context, {
  required String title,
  required String body,
  String rejectLabel = 'Request changes',
  String rejectStatus = 'revision_required',
}) async {
  final comment = TextEditingController();
  final decision = await showDialog<_ReviewDecision>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          const SizedBox(height: 12),
          TextField(
            controller: comment,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reviewer comment (optional)',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _ReviewDecision(rejectStatus, comment.text.trim()),
          ),
          child: Text(rejectLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ReviewDecision('approved', comment.text.trim()),
          ),
          child: const Text('Approve'),
        ),
      ],
    ),
  );
  comment.dispose();
  return decision;
}

void _showDailyDetail(BuildContext context, DailyReport report) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 25),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily report',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                formattedDate(report.date, withYear: true),
                style: const TextStyle(color: Palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _InfoPair(label: 'Status', value: report.status),
              _InfoPair(label: 'Hours', value: report.hours.toStringAsFixed(1)),
              _ReportSection(title: 'Completed', body: report.completed),
              _ReportSection(title: 'In progress', body: report.inProgress),
              _ReportSection(title: 'Pending', body: report.pending),
              _ReportSection(title: 'Challenges', body: report.issues),
              _ReportSection(title: 'Tomorrow', body: report.tomorrow),
              if (report.reviewComment.isNotEmpty)
                _ReportSection(
                  title: 'Reviewer comment',
                  body: report.reviewComment,
                ),
            ],
          ),
        ),
      ),
    );

void _showWeeklyDetail(BuildContext context, Map<String, Object?> report) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 25),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weekly summary',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                'Week of ${report['week_start'] ?? '—'}',
                style: const TextStyle(color: Palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _InfoPair(
                label: 'Status',
                value: '${report['status'] ?? 'submitted'}',
              ),
              _ReportSection(
                title: 'Wins and progress',
                body: '${report['summary'] ?? ''}',
              ),
              _ReportSection(
                title: 'Blockers',
                body: '${report['blockers'] ?? ''}',
              ),
              _ReportSection(
                title: 'Next week',
                body: '${report['next_week_plan'] ?? ''}',
              ),
              if ('${report['review_comment'] ?? ''}'.isNotEmpty)
                _ReportSection(
                  title: 'Reviewer comment',
                  body: '${report['review_comment']}',
                ),
            ],
          ),
        ),
      ),
    );

class _InfoPair extends StatelessWidget {
  const _InfoPair({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 124,
          child: Text(
            label,
            style: const TextStyle(color: Palette.muted, fontSize: 11),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Palette.ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.body});
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Palette.navy,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          body.isEmpty ? '—' : body,
          style: const TextStyle(
            color: Palette.ink,
            height: 1.45,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

String _localDateTime(String raw) {
  final value = DateTime.tryParse(raw)?.toLocal();
  return value == null
      ? raw
      : '${formattedDate(value, withYear: true)}  ·  ${formattedTime(value)}';
}

class TeamView extends StatefulWidget {
  const TeamView({super.key, required this.session, required this.repository});
  final AppSession session;
  final WorkspaceRepository repository;
  @override
  State<TeamView> createState() => _TeamViewState();
}

class _TeamViewState extends State<TeamView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<_TeamData> _future = _load();
  Future<_TeamData> _load() async {
    final values = await Future.wait([
      widget.repository.people(),
      widget.repository.teams(),
    ]);
    return _TeamData(values[0], values[1]);
  }

  Future<void> _refresh() async => setState(() => _future = _load());
  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _createTeam(List<Map<String, Object?>> people) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) =>
          _TeamEditor(repository: widget.repository, people: people),
    );
    if (saved == true) _refresh();
  }

  Future<void> _manageMembers(
    Map<String, Object?> team,
    List<Map<String, Object?>> people,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => _TeamMembersEditor(
        repository: widget.repository,
        team: team,
        people: people,
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _changeRole(Map<String, Object?> person) async {
    if (!widget.session.role.isAdmin) return;
    final role = await showModalBottomSheet<UserRole>(
      context: context,
      showDragHandle: true,
      backgroundColor: Palette.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            const Text(
              'Change workspace role',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            for (final value in UserRole.values)
              ListTile(
                title: Text(value.label),
                trailing: roleFromString(person['role']) == value
                    ? const Icon(Icons.check_rounded, color: Palette.green)
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (role == null) return;
    try {
      await widget.repository.setMemberRole('${person['id']}', role);
      await _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TeamData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return ErrorState(
          message: snapshot.error.toString(),
          onRetry: _refresh,
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'People, in sync.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 7),
                const Text(
                  'Role based access keeps each workspace focused.',
                  style: TextStyle(color: Palette.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabs,
                  labelColor: Palette.navy,
                  unselectedLabelColor: Palette.muted,
                  indicatorColor: Palette.blue,
                  tabs: const [
                    Tab(text: 'People'),
                    Tab(text: 'Teams'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 25),
                    children: [
                      if (data.people.isEmpty)
                        const EmptyInline(
                          icon: Icons.groups_2_outlined,
                          title: 'No employees yet',
                          detail: 'Employees can sign up with their email from the welcome screen. Their Employee IDs will appear here.',
                        )
                      else
                        for (final person in data.people)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PersonCard(
                              person: person,
                              canChangeRole: widget.session.role.isAdmin,
                              onTap: () => _changeRole(person),
                            ),
                          ),
                      if (widget.session.role.isAdmin && data.people.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 7),
                          child: Text(
                            'Employee signups start with Employee access. Only an Admin can change workspace roles.',
                            style: TextStyle(
                              color: Palette.muted,
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 25),
                    children: [
                      if (data.teams.isEmpty)
                        EmptyInline(
                          icon: Icons.diversity_3_outlined,
                          title: 'No teams yet',
                          detail: widget.session.role.canAssign
                              ? 'Create a team now, even before employees sign up.'
                              : 'Teams you belong to will appear here.',
                          actionLabel: widget.session.role.canAssign
                              ? 'Create team'
                              : null,
                          onAction: widget.session.role.canAssign
                              ? () => _createTeam(data.people)
                              : null,
                        )
                      else
                        for (final team in data.teams)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _TeamCard(
                              team: team,
                              repository: widget.repository,
                              canManage: widget.session.role.canAssign,
                              people: data.people,
                              onManageMembers: () =>
                                  _manageMembers(team, data.people),
                            ),
                          ),
                      if (widget.session.role.canAssign) ...[
                        const SizedBox(height: 7),
                        FilledButton.icon(
                          onPressed: () => _createTeam(data.people),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create team'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _TeamData {
  const _TeamData(this.people, this.teams);
  final List<Map<String, Object?>> people;
  final List<Map<String, Object?>> teams;
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.canChangeRole,
    required this.onTap,
  });
  final Map<String, Object?> person;
  final bool canChangeRole;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final role = roleFromString(person['role']);
    final name = '${person['display_name'] ?? 'Workspace member'}';
    return SurfaceCard(
      onTap: canChangeRole ? onTap : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Palette.sand,
            foregroundColor: Palette.navy,
            child: Text(
              name.isEmpty ? '·' : name.substring(0, 1).toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Palette.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${person['employee_id'] ?? 'No ID'}  ·  ${role.label}',
                  style: const TextStyle(color: Palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (canChangeRole)
            const Icon(Icons.tune_rounded, color: Palette.muted, size: 18),
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.repository,
    required this.canManage,
    required this.people,
    required this.onManageMembers,
  });
  final Map<String, Object?> team;
  final WorkspaceRepository repository;
  final bool canManage;
  final List<Map<String, Object?>> people;
  final VoidCallback onManageMembers;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: Palette.sand,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.diversity_3_outlined,
                color: Palette.navy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${team['name'] ?? 'Team'}',
                    style: const TextStyle(
                      color: Palette.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${team['description'] ?? ''}',
                    style: const TextStyle(color: Palette.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        FutureBuilder<List<Map<String, Object?>>>(
          future: repository.teamMembers('${team['id']}'),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const LinearProgressIndicator(minHeight: 2);
            if (snapshot.data!.isEmpty)
              return const Text(
                'No members assigned.',
                style: TextStyle(color: Palette.muted, fontSize: 11),
              );
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final member in snapshot.data!)
                  Chip(
                    avatar: Icon(
                      member['member_role'] == 'leader'
                          ? Icons.star_rounded
                          : Icons.person_outline_rounded,
                      color: member['member_role'] == 'leader'
                          ? Palette.amber
                          : Palette.blue,
                      size: 15,
                    ),
                    label: Text(
                      '${(member['profiles'] as Map?)?['display_name'] ?? 'Member'} · ${(member['profiles'] as Map?)?['employee_id'] ?? ''}',
                    ),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: Palette.ivory,
                  ),
              ],
            );
          },
        ),
        if (canManage) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onManageMembers,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
              label: const Text('Add employees'),
            ),
          ),
        ],
      ],
    ),
  );
}

class _TeamEditor extends StatefulWidget {
  const _TeamEditor({required this.repository, required this.people});
  final WorkspaceRepository repository;
  final List<Map<String, Object?>> people;
  @override
  State<_TeamEditor> createState() => _TeamEditorState();
}

class _TeamEditorState extends State<_TeamEditor> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _members = <String>{};
  String? _leaderId;
  bool _busy = false;
  String? _error;
  bool get _isAdmin => widget.repository.session.role.isAdmin;
  @override
  void initState() {
    super.initState();
    if (!_isAdmin) _leaderId = widget.repository.session.userId;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create team', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Team name'),
          ),
          const SizedBox(height: 11),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Department or notes'),
          ),
          const SizedBox(height: 12),
          if (_isAdmin)
            DropdownButtonFormField<String?>(
              initialValue: _leaderId,
              decoration: const InputDecoration(
                labelText: 'Team Leader (optional)',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Assign later'),
                ),
                ...widget.people.map(
                  (person) => DropdownMenuItem<String?>(
                    value: '${person['id']}',
                    child: Text(
                      '${person['display_name'] ?? 'Member'} · ${person['employee_id'] ?? ''}',
                    ),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _leaderId = value),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'You will lead this team. Add employees now or later.',
                style: TextStyle(color: Palette.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 13),
          const Text(
            'Team members',
            style: TextStyle(color: Palette.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            children: [
              for (final person in widget.people)
                FilterChip(
                  label: Text('${person['display_name'] ?? 'Member'}'),
                  selected: _members.contains('${person['id']}'),
                  onSelected: (value) => setState(() {
                    value
                        ? _members.add('${person['id']}')
                        : _members.remove('${person['id']}');
                  }),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Palette.red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 13),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_name.text.trim().isEmpty) {
                      setState(() => _error = 'Add a team name.');
                      return;
                    }
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await widget.repository.createTeam(
                        name: _name.text.trim(),
                        description: _description.text.trim(),
                        leaderId: _leaderId,
                        memberIds: _members.toList(),
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (error) {
                      if (mounted) setState(() => _error = error.toString());
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(51),
            ),
            child: const Text('Create team'),
          ),
        ],
      ),
    ),
  );
}

class _TeamMembersEditor extends StatefulWidget {
  const _TeamMembersEditor({
    required this.repository,
    required this.team,
    required this.people,
  });
  final WorkspaceRepository repository;
  final Map<String, Object?> team;
  final List<Map<String, Object?>> people;
  @override
  State<_TeamMembersEditor> createState() => _TeamMembersEditorState();
}

class _TeamMembersEditorState extends State<_TeamMembersEditor> {
  final Set<String> _selected = {};
  String? _leaderId;
  bool _busy = false;
  String? _error;

  Future<void> _save(String? existingLeaderId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.manageTeamMembers(
        teamId: '${widget.team['id']}',
        memberIds: _selected.toList(),
        leaderId: widget.repository.session.role.isAdmin
            ? (_leaderId ?? existingLeaderId)
            : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: widget.repository.teamMembers('${widget.team['id']}'),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return ErrorState(
            message: snapshot.error.toString(),
            onRetry: () async {},
          );
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        final current = snapshot.data!;
        final existingIds = current.map((row) => '${row['user_id']}').toSet();
        final existingLeader = current.where(
          (row) => row['member_role'] == 'leader',
        );
        final existingLeaderId = existingLeader.isEmpty
            ? null
            : '${existingLeader.first['user_id']}';
        final available = widget.people
            .where((person) => !existingIds.contains('${person['id']}'))
            .toList();
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage ${widget.team['name'] ?? 'team'}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              const Text(
                'Add signed-up employees by name and Employee ID.',
                style: TextStyle(color: Palette.muted, fontSize: 12),
              ),
              if (widget.repository.session.role.isAdmin) ...[
                const SizedBox(height: 13),
                DropdownButtonFormField<String?>(
                  initialValue: _leaderId ?? existingLeaderId,
                  decoration: const InputDecoration(labelText: 'Team Leader'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Leave unassigned'),
                    ),
                    ...widget.people.map(
                      (person) => DropdownMenuItem<String?>(
                        value: '${person['id']}',
                        child: Text(
                          '${person['display_name'] ?? 'Member'} · ${person['employee_id'] ?? ''}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _leaderId = value),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'Current team members · ${current.length}',
                style: const TextStyle(
                  color: Palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 7),
              if (current.isEmpty)
                const Text(
                  'No employees are assigned yet.',
                  style: TextStyle(color: Palette.muted, fontSize: 12),
                )
              else
                Wrap(
                  spacing: 6,
                  children: [
                    for (final member in current)
                      Chip(
                        label: Text(
                          '${(member['profiles'] as Map?)?['display_name'] ?? 'Member'} · ${(member['profiles'] as Map?)?['employee_id'] ?? ''}',
                        ),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        backgroundColor: Palette.ivory,
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              Text(
                'Add employees · ${available.length} available',
                style: const TextStyle(
                  color: Palette.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 7),
              if (available.isEmpty)
                const Text(
                  'New employees will appear after they sign up.',
                  style: TextStyle(color: Palette.muted, fontSize: 12),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 3,
                  children: [
                    for (final person in available)
                      FilterChip(
                        label: Text(
                          '${person['display_name'] ?? 'Member'} · ${person['employee_id'] ?? ''}',
                        ),
                        selected: _selected.contains('${person['id']}'),
                        onSelected: (selected) => setState(() {
                          selected
                              ? _selected.add('${person['id']}')
                              : _selected.remove('${person['id']}');
                        }),
                      ),
                  ],
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Palette.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy ? null : () => _save(existingLeaderId),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(51),
                ),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save team members'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  late Future<_AnalyticsData> _future = _load();
  Future<_AnalyticsData> _load() async {
    final values = await Future.wait([
      widget.repository.projects(),
      widget.repository.tasks(),
      widget.repository.reports(),
      widget.repository.attendanceSites(),
    ]);
    return _AnalyticsData(
      values[0] as List<ProjectItem>,
      values[1] as List<TaskItem>,
      values[2] as List<DailyReport>,
      values[3] as List<AttendanceSite>,
    );
  }

  Future<void> _refresh() async => setState(() => _future = _load());
  @override
  Widget build(BuildContext context) => FutureBuilder<_AnalyticsData>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return ErrorState(
          message: snapshot.error.toString(),
          onRetry: _refresh,
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      final done = data.tasks.where((task) => task.status == 'done').length;
      final avgProgress = data.projects.isEmpty
          ? 0.0
          : data.projects.map((item) => item.progress).reduce((a, b) => a + b) /
                data.projects.length;
      final approved = data.reports
          .where((report) => report.status == 'approved')
          .length;
      final hours = data.reports.fold<double>(
        0,
        (sum, report) => sum + report.hours,
      );
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Text(
              'A clearer picture.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 7),
            Text(
              widget.session.role.isAdmin
                  ? 'Workspace-wide results available to your role.'
                  : widget.session.role == UserRole.teamLeader
                  ? 'Team and assigned project results.'
                  : 'Your assigned work at a glance.',
              style: const TextStyle(color: Palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 17),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Projects',
                    value: '${data.projects.length}',
                    icon: Icons.folder_copy_outlined,
                    accent: Palette.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Tasks done',
                    value: '$done',
                    icon: Icons.task_alt_rounded,
                    accent: Palette.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Hours reported',
                    value: hours.toStringAsFixed(1),
                    icon: Icons.schedule_rounded,
                    accent: Palette.amber,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    label: 'Active sites',
                    value: '${data.sites.length}',
                    icon: Icons.location_on_outlined,
                    accent: Palette.navy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Project progress',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${(avgProgress * 100).round()}%',
                        style: const TextStyle(
                          color: Palette.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  ProgressLine(value: avgProgress),
                  const SizedBox(height: 9),
                  Text(
                    '${data.projects.where((item) => item.status == 'active').length} active projects · ${data.projects.where((item) => item.status == 'completed').length} completed',
                    style: const TextStyle(color: Palette.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: const EdgeInsets.all(17),
              child: Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: Palette.green.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: Palette.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report approvals',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$approved approved from ${data.reports.length} reports',
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.repository.isDemo)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'Preview figures are derived from example projects and tasks. Live analytics use only data visible to your role.',
                  style: TextStyle(
                    color: Palette.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _AnalyticsData {
  const _AnalyticsData(this.projects, this.tasks, this.reports, this.sites);
  final List<ProjectItem> projects;
  final List<TaskItem> tasks;
  final List<DailyReport> reports;
  final List<AttendanceSite> sites;
}

class GalleryView extends StatefulWidget {
  const GalleryView({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  @override
  State<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<GalleryView> {
  late final Future<List<ProjectItem>> _projects = widget.repository.projects();
  String? _projectId;
  late Future<List<_GalleryPhoto>>? _photos;

  @override
  void initState() {
    super.initState();
    _photos = null;
  }

  Future<List<_GalleryPhoto>> _loadPhotos(String projectId) async {
    final rows = await widget.repository.photos(projectId);
    return Future.wait(
      rows.map(
        (row) async => _GalleryPhoto(
          caption: '${row['caption'] ?? ''}',
          createdAt:
              DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
          url: await widget.repository.createStorageSignedUrl(
            '${row['object_path']}',
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    if (_projectId != null) setState(() => _photos = _loadPhotos(_projectId!));
  }

  Future<void> _upload(ProjectItem project) async {
    try {
      final image = await NativeBridge.chooseImage();
      if (image == null || !mounted) return;
      final captionController = TextEditingController();
      final caption = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add a photo caption'),
          content: TextField(
            controller: captionController,
            decoration: const InputDecoration(
              hintText: 'Describe this project moment',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, captionController.text.trim()),
              child: const Text('Add photo'),
            ),
          ],
        ),
      );
      captionController.dispose();
      if (caption == null) return;
      await widget.repository.uploadProjectPhoto(
        projectId: project.id,
        image: image,
        caption: caption,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo added to the project gallery.')),
        );
        await _refresh();
      }
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProjectItem>>(
    future: _projects,
    builder: (context, projectSnapshot) {
      if (projectSnapshot.hasError)
        return ErrorState(
          message: projectSnapshot.error.toString(),
          onRetry: () async {},
        );
      if (!projectSnapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final projects = projectSnapshot.data!;
      if (projects.isEmpty)
        return ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            EmptyInline(
              icon: Icons.collections_outlined,
              title: 'No projects to browse',
              detail: 'Project photographs and past work appear after your workspace is connected.',
            ),
          ],
        );
      _projectId ??= projects.first.id;
      _photos ??= _loadPhotos(_projectId!);
      final selected = projects.where((project) => project.id == _projectId);
      final project = selected.isEmpty ? projects.first : selected.first;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        children: [
          Text(
            'Work, captured.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 7),
          const Text(
            'Project photographs and a visual record of progress.',
            style: TextStyle(color: Palette.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: project.id,
            decoration: const InputDecoration(labelText: 'Project gallery'),
            items: projects
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(item.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null)
                setState(() {
                  _projectId = value;
                  _photos = _loadPhotos(value);
                });
            },
          ),
          const SizedBox(height: 15),
          if (widget.session.isDemo)
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Preview projects do not include fabricated employee photographs. Connect Supabase Storage to upload real work images.',
                style: TextStyle(
                  color: Palette.navy,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
          if (!widget.session.isDemo) ...[
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: () => _upload(project),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add project photo'),
            ),
          ],
          const SizedBox(height: 14),
          FutureBuilder<List<_GalleryPhoto>>(
            future: _photos,
            builder: (context, photoSnapshot) {
              if (photoSnapshot.hasError)
                return EmptyInline(
                  icon: Icons.cloud_off_outlined,
                  title: 'Photos could not load',
                  detail: photoSnapshot.error.toString(),
                  actionLabel: 'Retry',
                  onAction: _refresh,
                );
              if (!photoSnapshot.hasData)
                return const Padding(
                  padding: EdgeInsets.all(25),
                  child: Center(child: CircularProgressIndicator()),
                );
              final photos = photoSnapshot.data!;
              if (photos.isEmpty)
                return EmptyInline(
                  icon: Icons.photo_library_outlined,
                  title: 'No project photos yet',
                  detail: 'Uploaded photos are stored privately with this project and visible to its assigned team.',
                );
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: photos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                  childAspectRatio: .85,
                ),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return InkWell(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(photo.url, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(17),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            photo.url,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                                  color: Palette.sand,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Palette.navy,
                                  ),
                                ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xCC183B63),
                                  ],
                                ),
                              ),
                              child: Text(
                                photo.caption.isEmpty
                                    ? formattedDate(photo.createdAt)
                                    : photo.caption,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 17),
          SectionHeading(title: 'Project history'),
          const SizedBox(height: 7),
          const Text(
            'Daily reports, task updates and approvals are kept in the work history. Photo files stay private in Supabase Storage.',
            style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.45),
          ),
        ],
      );
    },
  );
}

class _GalleryPhoto {
  const _GalleryPhoto({
    required this.caption,
    required this.createdAt,
    required this.url,
  });
  final String caption;
  final DateTime createdAt;
  final String url;
}

class HistoryView extends StatefulWidget {
  const HistoryView({
    super.key,
    required this.session,
    required this.repository,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  late Future<List<_HistoryRecord>> _future = _load();
  Future<List<_HistoryRecord>> _load() async {
    final result = await Future.wait([
      widget.repository.reports(),
      widget.repository.siteHistory(),
    ]);
    final reports = result[0] as List<DailyReport>;
    final punches = result[1] as List<Map<String, Object?>>;
    return [
      ...reports.map(
        (report) => _HistoryRecord(
          date: report.date,
          title: 'Daily report · ${report.status.replaceAll('_', ' ')}',
          detail: report.projectName.isEmpty
              ? 'Progress and next steps recorded'
              : report.projectName,
          icon: Icons.edit_note_rounded,
          color: Palette.blue,
        ),
      ),
      ...punches.map(
        (row) => _HistoryRecord(
          date:
              DateTime.tryParse('${row['created_at']}')?.toLocal() ??
              DateTime.now(),
          title: 'Attendance · ${row['action'] ?? 'Punch'}',
          detail:
              '${row['site_name'] ?? 'Authorized site'}  ·  ±${(row['accuracy_meters'] as num?)?.round() ?? 0} m',
          icon: Icons.fingerprint_rounded,
          color: Palette.green,
        ),
      ),
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _refresh() async => setState(() => _future = _load());
  @override
  Widget build(BuildContext context) => FutureBuilder<List<_HistoryRecord>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return ErrorState(
          message: snapshot.error.toString(),
          onRetry: _refresh,
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final entries = snapshot.data!;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Text(
              'A record of the work.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 7),
            const Text(
              'Reports, approvals and verified attendance events.',
              style: TextStyle(color: Palette.muted, fontSize: 13),
            ),
            const SizedBox(height: 17),
            if (entries.isEmpty)
              EmptyInline(
                icon: Icons.history_rounded,
                title: 'History starts here',
                detail: widget.session.isDemo
                    ? 'Preview mode creates no attendance history. Submit a local sample report to explore the workflow.'
                    : 'Submitted reports and punch events will appear as your workspace is used.',
              )
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: entry.color.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(entry.icon, color: entry.color),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.title,
                                style: const TextStyle(
                                  color: Palette.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.detail,
                                style: const TextStyle(
                                  color: Palette.muted,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _localDateTime(entry.date.toIso8601String()),
                                style: const TextStyle(
                                  color: Palette.muted,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

class _HistoryRecord {
  const _HistoryRecord({
    required this.date,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });
  final DateTime date;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
}

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.session,
    required this.repository,
    required this.onSignOut,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  final Future<void> Function() onSignOut;
  Future<void> _manageSites(BuildContext context) async {
    if (session.isDemo) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => SiteEditor(repository: repository),
    );
    if (saved == true && context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Approved attendance site saved.')),
      );
  }

  Future<void> _changePin(BuildContext context) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => const _ChangePinSheet(),
    );
    if (saved == true && context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('App PIN changed.')));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
    children: [
      Text(
        'Set up with care.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 7),
      const Text(
        'INDETAIL keeps preview data separate from your live workspace.',
        style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 16),
      SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  session.isDemo
                      ? Icons.visibility_outlined
                      : Icons.cloud_done_outlined,
                  color: session.isDemo ? Palette.amber : Palette.green,
                ),
                const SizedBox(width: 9),
                Text(
                  session.isDemo ? 'Demo mode' : 'Live workspace',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Palette.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              session.isDemo
                  ? 'Sample projects and tasks are kept in memory on this device. Attendance, photo uploads and account changes are disabled.'
                  : 'Supabase is configured. Access is controlled by PostgreSQL row-level security and the signed-in role.',
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            _InfoPair(
              label: 'Supabase URL',
              value: isSupabaseConfigured
                  ? _host(supabaseUrl)
                  : 'Not configured',
            ),
            _InfoPair(label: 'Signed-in role', value: session.role.label),
          ],
        ),
      ),
      const SizedBox(height: 13),
      SectionHeading(title: 'Security'),
      if (!session.isDemo)
        _SettingsAction(
          icon: Icons.password_rounded,
          title: 'Change app PIN',
          detail: 'Update your six-digit local unlock code',
          onTap: () => _changePin(context),
        ),
      const _SettingsAction(
        icon: Icons.fingerprint_rounded,
        title: 'PIN + fingerprint',
        detail: 'Android fingerprint prompt with PIN fallback',
        onTap: null,
      ),
      const SizedBox(height: 12),
      SectionHeading(title: 'Attendance sites'),
      if (session.role.canAssign) ...[
        _SettingsAction(
          icon: Icons.add_location_alt_outlined,
          title: 'Add an approved site',
          detail: 'Set real office or project coordinates and a radius',
          onTap: session.isDemo ? null : () => _manageSites(context),
        ),
        _SettingsAction(
          icon: Icons.policy_outlined,
          title: 'Site access rules',
          detail: 'Managers can configure office sites; project sites follow team and project access',
          onTap: null,
        ),
      ] else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Ask your Admin to configure authorized office and project sites.',
            style: TextStyle(color: Palette.muted, fontSize: 12),
          ),
        ),
      const SizedBox(height: 12),
      SectionHeading(title: 'Workspace permissions'),
      for (final row in const [
        ('Admin', 'Manage people, sites, projects, reports and settings'),
        (
          'Team Leader',
          'Manage teams, assign employees and projects, create tasks and project sites; review reports',
        ),
        (
          'Employee',
          'View assigned work, punch at authorized sites and submit reports',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: Palette.blue,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.$1,
                        style: const TextStyle(
                          color: Palette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row.$2,
                        style: const TextStyle(
                          color: Palette.muted,
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 9),
      SurfaceCard(
        padding: const EdgeInsets.all(15),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Workspace setup',
              style: TextStyle(
                color: Palette.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 7),
            Text(
              '1. Employees sign up with email and receive an ids#### Employee ID.\n2. Admins and Team Leaders create teams, add employees, assign projects and tasks, and set deadlines.\n3. Admins configure the company office site; Team Leaders configure project sites for teams they lead.\n4. Attendance is enabled only after a real location and radius are saved.',
              style: TextStyle(
                color: Palette.muted,
                fontSize: 11,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 13),
      if (!session.isDemo)
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      const SizedBox(height: 17),
      const Text(
        'GPS is checked only when the user requests attendance verification. Failed accuracy, site distance, account, assignment or shift checks prevent the punch.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Palette.muted, fontSize: 10, height: 1.45),
      ),
    ],
  );
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 3),
    leading: Container(
      width: 39,
      height: 39,
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Palette.line),
      ),
      child: Icon(icon, color: Palette.navy, size: 18),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: Palette.ink,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
    subtitle: Text(
      detail,
      style: const TextStyle(color: Palette.muted, fontSize: 10),
    ),
    trailing: onTap == null
        ? null
        : const Icon(Icons.chevron_right_rounded, color: Palette.muted),
    onTap: onTap,
  );
}

class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet();
  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: InputDecoration(labelText: label, counterText: ''),
      inputFormatters: const [],
    ),
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change app PIN', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          _field(_old, 'Current PIN'),
          _field(_new, 'New six-digit PIN'),
          _field(_confirm, 'Confirm new PIN'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: Palette.red, fontSize: 12),
              ),
            ),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_old.text.length != 6 ||
                        _new.text.length != 6 ||
                        _confirm.text.length != 6) {
                      setState(
                        () => _error = 'Enter all three six-digit PIN values.',
                      );
                      return;
                    }
                    if (_new.text != _confirm.text) {
                      setState(() => _error = 'New PINs do not match.');
                      return;
                    }
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      if (!await NativeBridge.verifyPin(_old.text))
                        throw Exception('Current PIN is incorrect.');
                      await NativeBridge.setPin(_new.text);
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (error) {
                      if (mounted) setState(() => _error = error.toString());
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Save new PIN'),
          ),
        ],
      ),
    ),
  );
}

String _host(String value) => Uri.tryParse(value)?.host ?? 'Configured';
