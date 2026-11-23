import 'dart:math' as math;

enum UserRole { admin, teamLeader, employee }

enum WorkspacePage {
  attendance,
  reports,
  gallery,
  team,
  analytics,
  settings,
  history,
}

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.admin => 'Admin',
    UserRole.teamLeader => 'Team Leader',
    UserRole.employee => 'Employee',
  };

  bool get canAssign => this != UserRole.employee;
  bool get canReview => this != UserRole.employee;
  bool get isAdmin => this == UserRole.admin;
}

UserRole roleFromString(Object? value) => switch ('$value'.toLowerCase()) {
  'admin' => UserRole.admin,
  'team_leader' || 'team leader' || 'teamleader' => UserRole.teamLeader,
  _ => UserRole.employee,
};

class AppSession {
  const AppSession({
    required this.name,
    required this.email,
    required this.role,
    this.isDemo = false,
    this.userId,
    this.employeeId,
    this.accessToken,
    this.refreshToken,
  });

  final String name;
  final String email;
  final UserRole role;
  final bool isDemo;
  final String? userId;
  final String? employeeId;
  final String? accessToken;
  final String? refreshToken;

  Map<String, Object?> toJson() => {
    'name': name,
    'email': email,
    'role': role.name,
    'isDemo': isDemo,
    'userId': userId,
    'employeeId': employeeId,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };

  factory AppSession.fromJson(Map<Object?, Object?> json) => AppSession(
    name: '${json['name'] ?? 'Workspace member'}',
    email: '${json['email'] ?? ''}',
    role: roleFromString(json['role']),
    isDemo: json['isDemo'] == true,
    userId: json['userId'] as String?,
    employeeId: json['employeeId'] as String?,
    accessToken: json['accessToken'] as String?,
    refreshToken: json['refreshToken'] as String?,
  );
}

class ProjectItem {
  const ProjectItem({
    required this.id,
    required this.name,
    required this.category,
    required this.progress,
    required this.status,
    this.dueDate,
    this.description = '',
    this.teamId,
  });

  final String id;
  final String name;
  final String category;
  final double progress;
  final String status;
  final DateTime? dueDate;
  final String description;
  final String? teamId;

  factory ProjectItem.fromJson(Map<String, Object?> row) => ProjectItem(
    id: '${row['id']}',
    name: '${row['name'] ?? 'Untitled project'}',
    category: '${row['category'] ?? 'Project'}',
    progress: (row['progress'] as num?)?.toDouble() ?? 0,
    status: '${row['status'] ?? 'active'}',
    dueDate: DateTime.tryParse('${row['due_date'] ?? ''}'),
    description: '${row['description'] ?? ''}',
    teamId: row['team_id'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'progress': progress,
    'status': status,
    'due_date': dueDate?.toIso8601String(),
    'description': description,
    'team_id': teamId,
  };
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    this.projectName = '',
    this.dueDate,
  });

  final String id;
  final String title;
  final String status;
  final String priority;
  final String projectName;
  final DateTime? dueDate;

  factory TaskItem.fromJson(Map<String, Object?> row) => TaskItem(
    id: '${row['id']}',
    title: '${row['title'] ?? 'Untitled task'}',
    status: '${row['status'] ?? 'todo'}',
    priority: '${row['priority'] ?? 'normal'}',
    projectName: '${row['project_name'] ?? ''}',
    dueDate: DateTime.tryParse('${row['due_at'] ?? ''}'),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'status': status,
    'priority': priority,
    'project_name': projectName,
    'due_at': dueDate?.toIso8601String(),
  };
}

class AttendanceSite {
  const AttendanceSite({
    required this.id,
    required this.name,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String id;
  final String name;
  final String kind;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  factory AttendanceSite.fromJson(Map<String, Object?> row) => AttendanceSite(
    id: '${row['id']}',
    name: '${row['name']}',
    kind: '${row['kind'] ?? 'office'}',
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    radiusMeters: (row['radius_meters'] as num).round(),
  );
}

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isMocked,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final bool isMocked;
}

class DailyReport {
  const DailyReport({
    required this.id,
    required this.date,
    required this.completed,
    required this.inProgress,
    required this.pending,
    required this.hours,
    required this.status,
    this.projectName = '',
    this.issues = '',
    this.tomorrow = '',
    this.reviewComment = '',
  });

  final String id;
  final DateTime date;
  final String completed;
  final String inProgress;
  final String pending;
  final double hours;
  final String status;
  final String projectName;
  final String issues;
  final String tomorrow;
  final String reviewComment;

  factory DailyReport.fromJson(Map<String, Object?> row) => DailyReport(
    id: '${row['id']}',
    date: DateTime.tryParse('${row['report_date']}') ?? DateTime.now(),
    completed: '${row['completed_work'] ?? ''}',
    inProgress: '${row['in_progress_work'] ?? ''}',
    pending: '${row['pending_work'] ?? ''}',
    hours: (row['hours_spent'] as num?)?.toDouble() ?? 0,
    status: '${row['status'] ?? 'submitted'}',
    projectName: '${row['project_name'] ?? ''}',
    issues: '${row['issues'] ?? ''}',
    tomorrow: '${row['tomorrow_plan'] ?? ''}',
    reviewComment: '${row['review_comment'] ?? ''}',
  );
}

class CalendarItem {
  const CalendarItem({
    required this.title,
    required this.kind,
    required this.date,
    this.subtitle = '',
  });

  final String title;
  final String kind;
  final DateTime date;
  final String subtitle;
}

double leaveWorkdayCount(
  DateTime start,
  DateTime end, {
  bool saturdayFullDayCredit = false,
  Set<String> paidHolidayDates = const {},
}) {
  final first = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  if (last.isBefore(first)) return 0;
  var days = 0.0;
  for (
    var day = first;
    !day.isAfter(last);
    day = day.add(const Duration(days: 1))
  ) {
    final dateKey =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    if (day.weekday == DateTime.sunday || paidHolidayDates.contains(dateKey)) {
      continue;
    }
    days += day.weekday == DateTime.saturday && !saturdayFullDayCredit
        ? 0.5
        : 1;
  }
  return days;
}

double distanceInMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;
  final dLat = _radians(lat2 - lat1);
  final dLon = _radians(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_radians(lat1)) *
          math.cos(_radians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180;
