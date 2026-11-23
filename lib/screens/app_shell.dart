import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../repository.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'operations_views.dart';
import 'workspace_views.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.session,
    required this.repository,
    required this.onSignOut,
  });

  final AppSession session;
  final WorkspaceRepository repository;
  final Future<void> Function() onSignOut;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _titles = [
    'Overview',
    'Projects',
    'Calendar',
    'My tasks',
    'Profile',
  ];

  void _open(WorkspacePage page) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 270),
        pageBuilder: (context, animation, secondaryAnimation) => WorkspaceView(
          page: page,
          session: widget.session,
          repository: widget.repository,
          onSignOut: widget.onSignOut,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(.025, .02),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1000;
      return Scaffold(
        appBar: desktop
            ? null
            : AppBar(
                titleSpacing: 20,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titles[_index],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                    Text(
                      widget.session.role.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.2,
                        color: Palette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                actions: [
                  if (widget.session.isDemo) _previewBadge(),
                  IconButton(
                    tooltip: 'Attendance',
                    onPressed: () => _open(WorkspacePage.attendance),
                    icon: const Icon(Icons.location_on_outlined),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
        body: Row(
          children: [
            if (desktop) _desktopNavigation(),
            Expanded(
              child: Column(
                children: [
                  if (desktop) _desktopHeader(),
                  if (widget.session.isDemo) const PreviewBanner(),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1480),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(.025, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _pageForIndex(_index),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: desktop
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.folder_open_outlined),
                    selectedIcon: Icon(Icons.folder_rounded),
                    label: 'Projects',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    selectedIcon: Icon(Icons.calendar_month_rounded),
                    label: 'Calendar',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.checklist_rounded),
                    selectedIcon: Icon(Icons.checklist),
                    label: 'Tasks',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
      );
    },
  );

  Widget _previewBadge() => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Palette.sand,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'PREVIEW',
          style: TextStyle(
            color: Palette.navy,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      ),
    ),
  );

  Widget _desktopHeader() => Container(
    height: 78,
    padding: const EdgeInsets.symmetric(horizontal: 30),
    decoration: const BoxDecoration(
      color: Palette.surface,
      border: Border(bottom: BorderSide(color: Palette.line)),
    ),
    child: Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titles[_index],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Palette.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              widget.session.role.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                color: Palette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (widget.session.isDemo) _previewBadge(),
        IconButton.filledTonal(
          tooltip: 'Attendance',
          onPressed: () => _open(WorkspacePage.attendance),
          icon: const Icon(Icons.location_on_outlined),
        ),
        const SizedBox(width: 14),
        CircleAvatar(
          radius: 17,
          backgroundColor: Palette.powder.withValues(alpha: .45),
          child: Text(
            widget.session.name.isEmpty
                ? 'I'
                : widget.session.name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Palette.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          widget.session.name,
          style: const TextStyle(
            color: Palette.ink,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
  );

  Widget _desktopNavigation() => Container(
    width: 248,
    decoration: const BoxDecoration(
      color: Palette.surface,
      border: Border(right: BorderSide(color: Palette.line)),
    ),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 16, 22),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Palette.navy,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.architecture_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                const Text(
                  'INDETAIL',
                  style: TextStyle(
                    color: Palette.navy,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.7,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          _navSection('WORKSPACE'),
          _navItem(0, 'Overview', Icons.grid_view_rounded),
          _navItem(1, 'Projects', Icons.folder_copy_outlined),
          _navItem(2, 'Calendar', Icons.calendar_month_outlined),
          _navItem(3, 'My tasks', Icons.checklist_rounded),
          _navItem(4, 'Profile', Icons.person_outline_rounded),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 15, 18, 12),
            child: Divider(height: 1, color: Palette.line),
          ),
          _navSection('TOOLS'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                _toolItem(
                  'Attendance',
                  Icons.location_on_outlined,
                  WorkspacePage.attendance,
                ),
                _toolItem(
                  'Daily reports',
                  Icons.fact_check_outlined,
                  WorkspacePage.reports,
                ),
                _toolItem(
                  'Project gallery',
                  Icons.photo_library_outlined,
                  WorkspacePage.gallery,
                ),
                if (widget.session.role.canAssign) ...[
                  _toolItem(
                    'Teams & people',
                    Icons.groups_2_outlined,
                    WorkspacePage.team,
                  ),
                  _toolItem(
                    'Analytics',
                    Icons.insights_rounded,
                    WorkspacePage.analytics,
                  ),
                  _toolItem(
                    'Workspace settings',
                    Icons.tune_rounded,
                    WorkspacePage.settings,
                  ),
                ],
                _toolItem(
                  'Work history',
                  Icons.history_rounded,
                  WorkspacePage.history,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Palette.line),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Palette.muted),
            title: const Text('Sign out', style: TextStyle(fontSize: 13)),
            onTap: widget.onSignOut,
          ),
        ],
      ),
    ),
  );

  Widget _navSection(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 5, 12, 8),
    child: Text(
      label,
      style: const TextStyle(
        color: Palette.muted,
        fontSize: 9,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _navItem(int index, String title, IconData icon) {
    final selected = _index == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      child: Material(
        color: selected
            ? Palette.powder.withValues(alpha: .30)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => setState(() => _index = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? Palette.navy : Palette.muted,
                ),
                const SizedBox(width: 13),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? Palette.navy : Palette.ink,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolItem(String title, IconData icon, WorkspacePage page) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 1),
    child: ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, size: 19, color: Palette.muted),
      title: Text(title, style: const TextStyle(fontSize: 12.5)),
      onTap: () => _open(page),
    ),
  );

  Widget _pageForIndex(int index) {
    final key = ValueKey(index);
    return switch (index) {
      0 => DashboardView(
        key: key,
        session: widget.session,
        repository: widget.repository,
        onOpen: _open,
      ),
      1 => ProjectsView(
        key: key,
        session: widget.session,
        repository: widget.repository,
        onOpen: _open,
      ),
      2 => CalendarView(key: key, repository: widget.repository),
      3 => TasksView(
        key: key,
        session: widget.session,
        repository: widget.repository,
        onOpen: _open,
      ),
      _ => ProfileView(
        key: key,
        session: widget.session,
        onOpen: _open,
        onSignOut: widget.onSignOut,
      ),
    };
  }
}

class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpen,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  final void Function(WorkspacePage page) onOpen;
  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late Future<_OverviewData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_OverviewData> _load() async {
    final items = await Future.wait([
      widget.repository.projects(),
      widget.repository.tasks(),
      widget.repository.reports(),
    ]);
    return _OverviewData(
      projects: items[0] as List<ProjectItem>,
      tasks: items[1] as List<TaskItem>,
      reports: items[2] as List<DailyReport>,
    );
  }

  Future<void> _refresh() async => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<_OverviewData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            ),
          ),
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      final activeProjects = data.projects
          .where((item) => item.status == 'active')
          .length;
      final openTasks = data.tasks
          .where((item) => item.status != 'done')
          .length;
      final dueSoon = [
        ...data.projects
            .where((item) => item.dueDate != null)
            .map(
              (item) => OverviewDeadline(item.name, item.dueDate!, 'Project'),
            ),
        ...data.tasks
            .where((item) => item.dueDate != null && item.status != 'done')
            .map((item) => OverviewDeadline(item.title, item.dueDate!, 'Task')),
      ]..sort((a, b) => a.date.compareTo(b.date));
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 17, 20, 30),
          children: [
            _welcome(context),
            const SizedBox(height: 18),
            _attendanceCard(context),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'Active projects',
                    value: '$activeProjects',
                    icon: Icons.folder_copy_outlined,
                    accent: Palette.blue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: MetricCard(
                    label: 'Open tasks',
                    value: '$openTasks',
                    icon: Icons.check_circle_outline_rounded,
                    accent: Palette.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionHeading(
              title: 'Your shortcuts',
              actionLabel: 'All tools',
              onAction: () => widget.onOpen(WorkspacePage.settings),
            ),
            const SizedBox(height: 12),
            _shortcuts(context),
            const SizedBox(height: 24),
            SectionHeading(
              title: 'Coming up',
              actionLabel: 'Calendar',
              onAction: () => widget.onOpen(WorkspacePage.history),
            ),
            const SizedBox(height: 11),
            if (dueSoon.isEmpty)
              const EmptyInline(
                icon: Icons.event_available_outlined,
                title: 'Nothing due yet',
                detail: 'Deadlines will show here when projects and tasks are connected.',
              )
            else
              for (final deadline in dueSoon.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _DeadlineRow(deadline: deadline),
                ),
            const SizedBox(height: 18),
            _weeklyCard(context, data),
          ],
        ),
      );
    },
  );

  Widget _welcome(BuildContext context) {
    final now = DateTime.now();
    final date = '${_weekday(now.weekday)}, ${now.day} ${_month(now.month)}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date.toUpperCase(),
                style: const TextStyle(
                  color: Palette.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your workday,\nin focus.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'A little more clarity for the work ahead.',
                style: TextStyle(color: Palette.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Palette.sand,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(
            _roleIcon(widget.session.role),
            color: Palette.navy,
            size: 25,
          ),
        ),
      ],
    );
  }

  Widget _attendanceCard(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Palette.navy,
      borderRadius: BorderRadius.circular(21),
      boxShadow: [
        BoxShadow(
          color: Palette.navy.withValues(alpha: .13),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.my_location_rounded,
              color: Palette.powder,
              size: 19,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'LOCATION ATTENDANCE',
                style: TextStyle(
                  color: Palette.powder,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'SETUP REQUIRED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        const Text(
          'Punch in at an\napproved work site.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.session.isDemo ? 'Preview mode never records attendance.' : 'Add your authorized office or project site to enable location verification.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .76),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => widget.onOpen(WorkspacePage.attendance),
          icon: const Icon(Icons.location_searching_rounded, size: 17),
          label: const Text('View attendance'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: .34)),
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
        ),
      ],
    ),
  );

  Widget _shortcuts(BuildContext context) => GridView.count(
    crossAxisCount: 2,
    childAspectRatio: 1.42,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: [
      ShortcutCard(
        icon: Icons.edit_note_rounded,
        title: 'Daily report',
        detail: 'Write your progress',
        onTap: () => widget.onOpen(WorkspacePage.reports),
        color: Palette.blue,
      ),
      ShortcutCard(
        icon: Icons.collections_outlined,
        title: 'Project gallery',
        detail: 'Photos & history',
        onTap: () => widget.onOpen(WorkspacePage.gallery),
        color: Palette.green,
      ),
      ShortcutCard(
        icon: Icons.groups_2_outlined,
        title: 'My team',
        detail: 'People & roles',
        onTap: () => widget.onOpen(WorkspacePage.team),
        color: Palette.amber,
      ),
      ShortcutCard(
        icon: Icons.insights_outlined,
        title: 'Insights',
        detail: 'Weekly summary',
        onTap: () => widget.onOpen(WorkspacePage.analytics),
        color: Palette.navy,
      ),
    ],
  );

  Widget _weeklyCard(BuildContext context, _OverviewData data) => SurfaceCard(
    padding: const EdgeInsets.all(17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Weekly pulse',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Icon(Icons.trending_up_rounded, color: Palette.green),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${data.reports.length} report${data.reports.length == 1 ? '' : 's'} in the current view',
          style: const TextStyle(color: Palette.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: CustomPaint(painter: _PulsePainter()),
              ),
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${data.tasks.where((task) => task.status == 'done').length} done',
                  style: const TextStyle(
                    color: Palette.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const Text(
                  'tasks',
                  style: TextStyle(color: Palette.muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.admin => Icons.admin_panel_settings_outlined,
    UserRole.teamLeader => Icons.groups_2_outlined,
    UserRole.employee => Icons.person_outline_rounded,
  };
}

class _OverviewData {
  const _OverviewData({
    required this.projects,
    required this.tasks,
    required this.reports,
  });
  final List<ProjectItem> projects;
  final List<TaskItem> tasks;
  final List<DailyReport> reports;
}

class OverviewDeadline {
  const OverviewDeadline(this.title, this.date, this.kind);
  final String title;
  final DateTime date;
  final String kind;
}

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.deadline});
  final OverviewDeadline deadline;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Palette.sand,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.event_outlined,
            color: Palette.navy,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deadline.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Palette.ink,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${deadline.kind}  ·  ${_dateLabel(deadline.date)}',
                style: const TextStyle(color: Palette.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.arrow_forward_ios_rounded,
          color: Palette.muted,
          size: 14,
        ),
      ],
    ),
  );
}

String _dateLabel(DateTime date) {
  final now = DateTime.now();
  final difference = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  return '${date.day} ${_month(date.month)}';
}

String _weekday(int day) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1];
String _month(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

class _PulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      Offset(0, size.height * .72),
      Offset(size.width * .18, size.height * .42),
      Offset(size.width * .36, size.height * .61),
      Offset(size.width * .54, size.height * .24),
      Offset(size.width * .72, size.height * .43),
      Offset(size.width, size.height * .12),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      path.cubicTo(
        a.dx + (b.dx - a.dx) * .46,
        a.dy,
        b.dx - (b.dx - a.dx) * .46,
        b.dy,
        b.dx,
        b.dy,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Palette.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(points.last, 3.5, Paint()..color = Palette.green);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
