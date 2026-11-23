import 'dart:math';

import 'models.dart';
import 'native_bridge.dart';
import 'supabase_api.dart';

class WorkspaceRepository {
  WorkspaceRepository(
    AppSession initialSession, {
    required this.onSessionUpdated,
  }) : api = SupabaseApi(initialSession, onSessionUpdated: onSessionUpdated);

  // Auth/profile sync replaces SupabaseApi.session after sign-in and token
  // refresh. Always read that current value so permission checks cannot use the
  // pre-auth Employee placeholder captured when the repository was created.
  AppSession get session => api.session;
  final Future<void> Function(AppSession session) onSessionUpdated;
  final SupabaseApi api;
  final List<ProjectItem> _demoProjects = [
    ProjectItem(
      id: 'demo-project-1',
      name: 'Example residence',
      category: 'Interior',
      progress: .64,
      status: 'active',
      dueDate: DateTime.now().add(const Duration(days: 12)),
      description: 'Illustrative project shown only in preview mode.',
    ),
    ProjectItem(
      id: 'demo-project-2',
      name: 'Example workspace',
      category: 'Architecture',
      progress: .32,
      status: 'active',
      dueDate: DateTime.now().add(const Duration(days: 23)),
      description: 'Illustrative project shown only in preview mode.',
    ),
  ];
  final List<TaskItem> _demoTasks = [
    TaskItem(
      id: 'demo-task-1',
      title: 'Review finish schedule',
      projectName: 'Example residence',
      status: 'in_progress',
      priority: 'high',
      dueDate: DateTime.now().add(const Duration(days: 1)),
    ),
    TaskItem(
      id: 'demo-task-2',
      title: 'Prepare weekly site notes',
      projectName: 'Example workspace',
      status: 'todo',
      priority: 'normal',
      dueDate: DateTime.now().add(const Duration(days: 2)),
    ),
    TaskItem(
      id: 'demo-task-3',
      title: 'Upload progress photographs',
      projectName: 'Example residence',
      status: 'todo',
      priority: 'normal',
      dueDate: DateTime.now().add(const Duration(days: 3)),
    ),
  ];
  final List<DailyReport> _demoReports = [];
  final List<Map<String, Object?>> _demoWeeklySummaries = [];
  final List<CalendarItem> _demoEvents = [];

  bool get isDemo => session.isDemo;

  Future<List<ProjectItem>> projects() async {
    if (isDemo) return List.unmodifiable(_demoProjects);
    final rows = await api.select(
      'projects',
      query: 'select=*&order=updated_at.desc',
    );
    return rows.map(ProjectItem.fromJson).toList();
  }

  Future<List<TaskItem>> tasks() async {
    if (isDemo) return List.unmodifiable(_demoTasks);
    final rows = await api.select(
      'tasks',
      query: 'select=*,projects(name)&order=due_at.asc.nullslast',
    );
    return rows.map((row) {
      final project = row['projects'];
      if (project is Map) row['project_name'] = project['name'];
      return TaskItem.fromJson(row);
    }).toList();
  }

  Future<List<CalendarItem>> calendarItems() async {
    if (isDemo) {
      return [
        ..._demoEvents,
        ..._demoTasks
            .where((task) => task.dueDate != null)
            .map(
              (task) => CalendarItem(
                title: task.title,
                subtitle: task.projectName,
                kind: 'Task deadline',
                date: task.dueDate!,
              ),
            ),
        ..._demoProjects
            .where((project) => project.dueDate != null)
            .map(
              (project) => CalendarItem(
                title: project.name,
                subtitle: 'Project deadline',
                kind: 'Deadline',
                date: project.dueDate!,
              ),
            ),
      ]..sort((a, b) => a.date.compareTo(b.date));
    }
    final eventRows = await api.select(
      'calendar_events',
      query: 'select=*&order=starts_at.asc',
    );
    final taskRows = await api.select(
      'tasks',
      query: 'select=title,due_at,projects(name)&due_at=not.is.null&order=due_at.asc',
    );
    final projects = await api.select(
      'projects',
      query: 'select=name,due_date&due_date=not.is.null&order=due_date.asc',
    );
    return [
      ...eventRows.map(
        (row) => CalendarItem(
          title: '${row['title']}',
          subtitle: '${row['description'] ?? ''}',
          kind: '${row['kind'] ?? 'Event'}',
          date: DateTime.tryParse('${row['starts_at']}') ?? DateTime.now(),
        ),
      ),
      ...taskRows.map((row) {
        final project = row['projects'];
        return CalendarItem(
          title: '${row['title']}',
          subtitle: project is Map ? '${project['name'] ?? ''}' : '',
          kind: 'Task deadline',
          date: DateTime.tryParse('${row['due_at']}') ?? DateTime.now(),
        );
      }),
      ...projects.map(
        (row) => CalendarItem(
          title: '${row['name']}',
          subtitle: 'Project deadline',
          kind: 'Deadline',
          date: DateTime.tryParse('${row['due_date']}') ?? DateTime.now(),
        ),
      ),
    ]..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<List<DailyReport>> reports() async {
    if (isDemo) return List.unmodifiable(_demoReports);
    final rows = await api.select(
      'daily_reports',
      query: 'select=*,projects(name)&order=report_date.desc',
    );
    return rows.map((row) {
      final project = row['projects'];
      if (project is Map) row['project_name'] = project['name'];
      return DailyReport.fromJson(row);
    }).toList();
  }

  Future<List<Map<String, Object?>>> weeklySummaries() async {
    if (isDemo) return List.unmodifiable(_demoWeeklySummaries);
    return api.select(
      'weekly_summaries',
      query: 'select=*&order=week_start.desc',
    );
  }

  Future<List<Map<String, Object?>>> people() async {
    if (isDemo) return const [];
    final response = await api.rpc('employee_directory', const {});
    return response is List
        ? response.map((row) => (row as Map).cast<String, Object?>()).toList()
        : const [];
  }

  Future<List<Map<String, Object?>>> teams() async {
    if (isDemo) return const [];
    return api.select(
      'teams',
      query: 'select=id,name,description&order=name.asc',
    );
  }

  Future<List<Map<String, Object?>>> manageableTeams() async {
    if (isDemo) return const [];
    final available = await teams();
    if (session.role.isAdmin) return available;
    if (session.role != UserRole.teamLeader || session.userId == null)
      return const [];
    final memberships = await api.select(
      'team_members',
      query:
          'select=team_id&user_id=eq.${session.userId}&member_role=eq.leader',
    );
    final ids = memberships.map((row) => '${row['team_id']}').toSet();
    return available.where((team) => ids.contains('${team['id']}')).toList();
  }

  Future<List<Map<String, Object?>>> teamMembers(String teamId) async {
    if (isDemo) return const [];
    return api.select(
      'team_members',
      query:
          'select=team_id,user_id,member_role,profiles(display_name,role,employee_id)&team_id=eq.$teamId',
    );
  }

  Future<void> setMemberRole(String userId, UserRole role) async {
    if (isDemo)
      throw const ApiException(
        'Role updates require a configured live workspace.',
      );
    if (!session.role.isAdmin)
      throw const ApiException('Only an Admin can change workspace roles.');
    await api.patch('profiles', 'id=eq.$userId', {
      'role': role.name == 'teamLeader' ? 'team_leader' : role.name,
    });
  }

  Future<void> createTeam({
    required String name,
    required String description,
    required String? leaderId,
    required List<String> memberIds,
  }) async {
    if (isDemo)
      throw const ApiException(
        'Team setup requires a configured live workspace.',
      );
    if (!session.role.canAssign)
      throw const ApiException(
        'Only an Admin or Team Leader can create teams.',
      );
    await api.rpc('create_team', {
      'p_name': name,
      'p_description': description,
      'p_leader_id': leaderId,
      'p_member_ids': memberIds.toSet().toList(),
    });
  }

  Future<void> manageTeamMembers({
    required String teamId,
    required List<String> memberIds,
    String? leaderId,
  }) async {
    if (isDemo)
      throw const ApiException(
        'Team management requires a configured live workspace.',
      );
    if (!session.role.canAssign)
      throw const ApiException(
        'Only an Admin or Team Leader can manage team members.',
      );
    await api.rpc('manage_team_members', {
      'p_team_id': teamId,
      'p_member_ids': memberIds.toSet().toList(),
      'p_leader_id': leaderId,
    });
  }

  Future<List<ProjectItem>> manageableProjects() async {
    final available = await projects();
    if (isDemo || session.role.isAdmin) return available;
    final teamIds = (await manageableTeams())
        .map((team) => '${team['id']}')
        .toSet();
    return available
        .where(
          (project) =>
              project.teamId != null && teamIds.contains(project.teamId),
        )
        .toList();
  }

  Future<List<Map<String, Object?>>> gallery(String projectId) async {
    if (isDemo) return const [];
    return api.select(
      'project_photos',
      query: 'select=*&project_id=eq.$projectId&order=created_at.desc',
    );
  }

  Future<List<AttendanceSite>> attendanceSites() async {
    if (isDemo) return const [];
    final rows = await api.select(
      'attendance_sites',
      query: 'select=id,name,kind,latitude,longitude,radius_meters&is_active=eq.true&order=name.asc',
    );
    return rows.map(AttendanceSite.fromJson).toList();
  }

  Future<AttendanceSite?> openAttendanceSite() async {
    if (isDemo) return null;
    final response = await api.rpc('my_open_attendance_site', {});
    final item = response is List && response.isNotEmpty
        ? response.first
        : response;
    if (item == null) return null;
    if (item is Map)
      return AttendanceSite.fromJson(item.cast<String, Object?>());
    throw const ApiException('The open attendance site could not be loaded.');
  }

  Future<Map<String, Object?>> myAttendanceSummary({DateTime? month}) async {
    final selected = month ?? DateTime.now();
    final monthStart = DateTime(selected.year, selected.month, 1);
    final monthText = monthStart.toIso8601String().split('T').first;
    if (isDemo) {
      return {
        'month_start': monthText,
        'present_days': 0,
        'approved_leave_days': 0,
        'paid_holiday_days': 0,
        'worked_minutes': 0,
        'paid_leave_balance': 0,
        'saturday_full_day_credit': false,
        'weekly_off_day': 'Sunday',
      };
    }
    final response = await api.rpc('my_attendance_summary', {
      'p_month_start': monthText,
    });
    if (response is Map) return response.cast<String, Object?>();
    throw const ApiException('Attendance totals could not be loaded.');
  }

  Future<Map<String, Object?>> recordAttendance({
    required String action,
    required AttendanceSite site,
    required LocationFix location,
  }) async {
    if (isDemo)
      throw const ApiException('Attendance is disabled in preview mode.');
    final response = await api.rpc('record_attendance', {
      'p_action': action,
      'p_site_id': site.id,
      'p_latitude': location.latitude,
      'p_longitude': location.longitude,
      'p_accuracy_meters': location.accuracyMeters,
      'p_mocked_signal': location.isMocked,
    });
    final item = response is List && response.isNotEmpty
        ? response.first
        : response;
    return item is Map
        ? item.cast<String, Object?>()
        : <String, Object?>{'accepted': true};
  }

  Future<void> createProject({
    required String name,
    required String category,
    required String description,
    required DateTime? dueDate,
    required List<String> assignedUserIds,
    String? teamId,
  }) async {
    if (isDemo) {
      _demoProjects.insert(
        0,
        ProjectItem(
          id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
          name: name,
          category: category,
          progress: 0,
          status: 'active',
          dueDate: dueDate,
          description: description,
        ),
      );
      return;
    }
    if (!session.role.canAssign)
      throw const ApiException(
        'Only Admin or Team Leader can create projects.',
      );
    if (session.role == UserRole.teamLeader && teamId == null) {
      throw const ApiException(
        'Choose a team you lead before creating a project.',
      );
    }
    final response = await api.insert('projects', {
      'name': name,
      'category': category,
      'description': description,
      'due_date': dueDate?.toIso8601String(),
      'status': 'active',
      'team_id': teamId,
    });
    final result = response is List && response.isNotEmpty
        ? response.first
        : response;
    final id = result is Map ? '${result['id'] ?? ''}' : '';
    if (id.isNotEmpty) {
      for (final userId in assignedUserIds) {
        await api.insert('project_assignments', {
          'project_id': id,
          'user_id': userId,
        });
      }
    }
  }

  Future<void> createTask({
    required String title,
    required String description,
    required String projectId,
    required String? assigneeId,
    required DateTime? dueDate,
    required String priority,
  }) async {
    if (isDemo) {
      final matches = _demoProjects.where((item) => item.id == projectId);
      final project = matches.isEmpty ? null : matches.first;
      _demoTasks.insert(
        0,
        TaskItem(
          id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
          title: title,
          projectName: project?.name ?? 'Example project',
          status: 'todo',
          priority: priority,
          dueDate: dueDate,
        ),
      );
      return;
    }
    if (!session.role.canAssign)
      throw const ApiException('Only Admin or Team Leader can assign tasks.');
    final response = await api.insert('tasks', {
      'title': title,
      'description': description,
      'project_id': projectId,
      'assignee_id': assigneeId,
      'due_at': dueDate?.toIso8601String(),
      'priority': priority,
      'status': 'todo',
    });
    final result = response is List && response.isNotEmpty
        ? response.first
        : response;
    final id = result is Map ? '${result['id'] ?? ''}' : '';
    if (id.isNotEmpty && assigneeId != null) {
      await api.insert('task_assignments', {
        'task_id': id,
        'user_id': assigneeId,
      });
    }
  }

  Future<void> updateTaskStatus(TaskItem task, String status) async {
    if (isDemo) {
      final index = _demoTasks.indexWhere((item) => item.id == task.id);
      if (index >= 0) {
        _demoTasks[index] = TaskItem(
          id: task.id,
          title: task.title,
          projectName: task.projectName,
          status: status,
          priority: task.priority,
          dueDate: task.dueDate,
        );
      }
      return;
    }
    await api.patch('tasks', 'id=eq.${task.id}', {'status': status});
  }

  Future<void> createCalendarEvent({
    required String title,
    required String kind,
    required String description,
    required DateTime startsAt,
  }) async {
    if (isDemo) {
      _demoEvents.add(
        CalendarItem(
          title: title,
          kind: kind,
          subtitle: description,
          date: startsAt,
        ),
      );
      return;
    }
    if (!session.role.canAssign)
      throw const ApiException(
        'Only Admin or Team Leader can add shared calendar events.',
      );
    await api.insert('calendar_events', {
      'title': title,
      'kind': kind,
      'description': description,
      'starts_at': startsAt.toUtc().toIso8601String(),
    });
  }

  Future<void> submitReport({
    required String completed,
    required String inProgress,
    required String pending,
    required double hours,
    required String issues,
    required String tomorrow,
    required String? projectId,
  }) async {
    if (isDemo) {
      _demoReports.insert(
        0,
        DailyReport(
          id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
          date: DateTime.now(),
          completed: completed,
          inProgress: inProgress,
          pending: pending,
          hours: hours,
          status: 'submitted',
          issues: issues,
          tomorrow: tomorrow,
        ),
      );
      return;
    }
    await api.insert('daily_reports', {
      'project_id': projectId,
      'report_date': DateTime.now().toIso8601String().split('T').first,
      'completed_work': completed,
      'in_progress_work': inProgress,
      'pending_work': pending,
      'hours_spent': hours,
      'issues': issues,
      'tomorrow_plan': tomorrow,
      'status': 'submitted',
    });
  }

  Future<void> reviewReport(
    DailyReport report,
    String status,
    String comment,
  ) async {
    if (isDemo) {
      final index = _demoReports.indexWhere((item) => item.id == report.id);
      if (index >= 0) {
        final old = _demoReports[index];
        _demoReports[index] = DailyReport(
          id: old.id,
          date: old.date,
          completed: old.completed,
          inProgress: old.inProgress,
          pending: old.pending,
          hours: old.hours,
          status: status,
          issues: old.issues,
          tomorrow: old.tomorrow,
          reviewComment: comment,
        );
      }
      return;
    }
    if (!session.role.canReview)
      throw const ApiException('Only Admin or Team Leader can review reports.');
    await api.patch('daily_reports', 'id=eq.${report.id}', {
      'status': status,
      'review_comment': comment,
      'reviewed_by': session.userId,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> submitWeeklySummary({
    required String summary,
    required String blockers,
    required String nextWeek,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    if (isDemo) {
      _demoWeeklySummaries.insert(0, {
        'id': 'preview-${DateTime.now().microsecondsSinceEpoch}',
        'week_start': start.toIso8601String().split('T').first,
        'summary': summary,
        'blockers': blockers,
        'next_week_plan': nextWeek,
        'status': 'submitted',
      });
      return;
    }
    await api.insert('weekly_summaries', {
      'week_start': start.toIso8601String().split('T').first,
      'summary': summary,
      'blockers': blockers,
      'next_week_plan': nextWeek,
      'status': 'submitted',
    });
  }

  Future<void> reviewWeeklySummary(
    String id,
    String status,
    String comment,
  ) async {
    if (isDemo) {
      final item = _demoWeeklySummaries.where((row) => row['id'] == id);
      if (item.isNotEmpty) {
        item.first['status'] = status;
        item.first['review_comment'] = comment;
      }
      return;
    }
    if (!session.role.canReview)
      throw const ApiException(
        'Only Admin or Team Leader can review weekly summaries.',
      );
    await api.patch('weekly_summaries', 'id=eq.$id', {
      'status': status,
      'review_comment': comment,
      'reviewed_by': session.userId,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> createSite({
    required String name,
    required String kind,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    required String? projectId,
  }) async {
    if (isDemo)
      throw const ApiException(
        'Site setup requires a configured live workspace.',
      );
    if (!session.role.canAssign)
      throw const ApiException(
        'Only an Admin or Team Leader can add attendance sites.',
      );
    await api.insert('attendance_sites', {
      'name': name,
      'kind': kind,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'project_id': projectId,
      'is_active': true,
    });
  }

  Future<List<Map<String, Object?>>> siteHistory() async {
    if (isDemo) return const [];
    return api.select(
      'attendance_events',
      query: 'select=id,action,created_at,accuracy_meters,distance_meters,site_name&order=created_at.desc&limit=30',
    );
  }

  Future<List<Map<String, Object?>>> adminAttendanceReport({
    DateTime? month,
  }) async {
    if (isDemo || !session.role.isAdmin) return const [];
    final selected = month ?? DateTime.now();
    final monthStart = DateTime(selected.year, selected.month, 1);
    final response = await api.rpc('admin_attendance_report', {
      'p_month_start': monthStart.toIso8601String().split('T').first,
    });
    if (response is List) {
      return response
          .map((row) => (row as Map).cast<String, Object?>())
          .toList();
    }
    throw const ApiException(
      'The Admin attendance report could not be loaded.',
    );
  }

  Future<List<Map<String, Object?>>> paidHolidays() async {
    if (isDemo) return const [];
    return api.select(
      'paid_holidays',
      query: 'select=id,holiday_date,name,paid_days&order=holiday_date.asc&limit=500',
    );
  }

  Future<void> importPaidHolidays(List<Map<String, Object?>> holidays) async {
    if (isDemo || !session.role.isAdmin) {
      throw const ApiException('Only an Admin can manage paid holidays.');
    }
    await api.rpc('admin_import_paid_holidays', {'p_holidays': holidays});
  }

  Future<void> updateEmployeeAttendanceSettings({
    required String userId,
    required bool saturdayFullDayCredit,
    required DateTime leaveAccrualStart,
    required double leaveOpeningBalance,
  }) async {
    if (isDemo || !session.role.isAdmin) {
      throw const ApiException(
        'Only an Admin can edit employee attendance settings.',
      );
    }
    await api.rpc('admin_update_attendance_settings', {
      'p_user_id': userId,
      'p_saturday_full_day_credit': saturdayFullDayCredit,
      'p_leave_accrual_start': DateTime(
        leaveAccrualStart.year,
        leaveAccrualStart.month,
        1,
      ).toIso8601String().split('T').first,
      'p_leave_opening_balance': leaveOpeningBalance,
    });
  }

  Future<void> setEmployeePaidLeaveBalance({
    required String userId,
    required double balance,
  }) async {
    if (isDemo || !session.role.isAdmin) {
      throw const ApiException(
        'Only an Admin can adjust employee paid leave balances.',
      );
    }
    await api.rpc('admin_set_paid_leave_balance', {
      'p_user_id': userId,
      'p_balance': balance,
      'p_note': 'Admin set the current paid leave balance in INDETAIL',
    });
  }

  Future<Map<String, String>> adminPrivateRequestReasons() async {
    if (isDemo || !session.role.isAdmin) return const {};
    final response = await api.rpc('admin_private_request_reasons', const {});
    if (response is! List) return const {};
    return {
      for (final item in response.whereType<Map>())
        '${item['kind']}:${item['id']}': '${item['reason'] ?? ''}',
    };
  }

  Future<List<Map<String, Object?>>> attendanceCorrections() async {
    if (isDemo) return const [];
    final rows = await api.select(
      'attendance_correction_requests',
      query: 'select=id,user_id,event_date,requested_in,requested_out,request_type,status,review_comment,reviewed_by,reviewed_at,created_at,requester:profiles!attendance_correction_requests_user_id_fkey(display_name)&order=created_at.desc&limit=100',
    );
    if (!session.role.isAdmin || rows.isEmpty) return rows;
    final reasons = await adminPrivateRequestReasons();
    for (final row in rows) {
      row['reason'] = reasons['correction:${row['id']}'] ?? '';
    }
    return rows;
  }

  Future<void> submitAttendanceCorrection({
    required DateTime date,
    required String requestType,
    required String requestedIn,
    required String requestedOut,
    required String reason,
  }) async {
    if (isDemo)
      throw const ApiException(
        'Attendance correction requests require a live workspace.',
      );
    await api.insert('attendance_correction_requests', {
      'event_date': date.toIso8601String().split('T').first,
      'request_type': requestType,
      'requested_in': requestedIn.isEmpty
          ? null
          : DateTime.parse(requestedIn).toUtc().toIso8601String(),
      'requested_out': requestedOut.isEmpty
          ? null
          : DateTime.parse(requestedOut).toUtc().toIso8601String(),
      'reason': reason,
    });
  }

  Future<void> reviewAttendanceCorrection(
    String id,
    String status,
    String comment,
  ) async {
    if (isDemo)
      throw const ApiException('Correction review requires a live workspace.');
    if (!session.role.canReview)
      throw const ApiException(
        'Only Admin or Team Leader can review correction requests.',
      );
    final response = await api.patch(
      'attendance_correction_requests',
      'id=eq.$id&status=eq.submitted',
      {
        'status': status,
        'review_comment': comment,
        'reviewed_by': session.userId,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (response is List && response.isEmpty) {
      throw const ApiException(
        'This request was already reviewed. Refresh the list.',
      );
    }
  }

  Future<List<Map<String, Object?>>> leaveRequests() async {
    if (isDemo) return const [];
    final rows = await api.select(
      'leave_requests',
      query: 'select=id,user_id,leave_type,use_paid_leave,start_date,end_date,status,review_comment,reviewed_by,reviewed_at,created_at,requester:profiles!leave_requests_user_id_fkey(display_name,saturday_full_day_credit)&order=created_at.desc&limit=100',
    );
    if (!session.role.isAdmin || rows.isEmpty) return rows;
    final reasons = await adminPrivateRequestReasons();
    for (final row in rows) {
      row['reason'] = reasons['leave:${row['id']}'] ?? '';
    }
    return rows;
  }

  Future<void> submitLeaveRequest({
    required String leaveType,
    required bool usePaidLeave,
    required DateTime start,
    required DateTime end,
    required String reason,
    required bool saturdayFullDayCredit,
    required Set<String> paidHolidayDates,
  }) async {
    if (isDemo) {
      throw const ApiException('Leave requests require a live workspace.');
    }
    if (leaveWorkdayCount(
          start,
          end,
          saturdayFullDayCredit: saturdayFullDayCredit,
          paidHolidayDates: paidHolidayDates,
        ) <=
        0) {
      throw const ApiException('Choose at least one non-Sunday leave day.');
    }
    await api.insert('leave_requests', {
      'leave_type': leaveType,
      'use_paid_leave': usePaidLeave,
      'start_date': start.toIso8601String().split('T').first,
      'end_date': end.toIso8601String().split('T').first,
      'reason': reason.trim(),
    });
  }

  Future<void> reviewLeaveRequest(
    String id,
    String status,
    String comment,
  ) async {
    if (isDemo) {
      throw const ApiException('Leave review requires a live workspace.');
    }
    if (!session.role.canReview) {
      throw const ApiException(
        'Only Admin or Team Leader can review leave requests.',
      );
    }
    final response = await api.patch(
      'leave_requests',
      'id=eq.$id&status=eq.submitted',
      {
        'status': status,
        'review_comment': comment,
        'reviewed_by': session.userId,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (response is List && response.isEmpty) {
      throw const ApiException(
        'This leave request was already reviewed. Refresh the list.',
      );
    }
  }

  Future<List<Map<String, Object?>>> photos(String projectId) =>
      gallery(projectId);

  Future<void> uploadProjectPhoto({
    required String projectId,
    required PickedImage image,
    required String caption,
  }) async {
    if (isDemo)
      throw const ApiException(
        'Photos are local-only in preview mode. Configure Supabase Storage to upload.',
      );
    final objectName =
        '${session.userId}/${DateTime.now().microsecondsSinceEpoch}_${_safeName(image.name)}';
    await api.upload('project-media', '$projectId/$objectName', image);
    await api.insert('project_photos', {
      'project_id': projectId,
      'object_path': '$projectId/$objectName',
      'caption': caption,
      'content_type': image.contentType,
    });
  }

  String _safeName(String value) =>
      value.replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_');

  Future<String> createStorageSignedUrl(String objectPath) async {
    return api.signedObjectUrl('project-media', objectPath);
  }

  Future<void> signOut() async {
    await NativeBridge.deleteSecure('session');
  }

  String newLocalId() => 'preview-${Random().nextInt(1 << 32)}';
}
