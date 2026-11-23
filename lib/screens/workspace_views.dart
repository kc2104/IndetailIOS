import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../repository.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class ProjectsView extends StatefulWidget {
  const ProjectsView({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpen,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  final void Function(WorkspacePage page) onOpen;
  @override
  State<ProjectsView> createState() => _ProjectsViewState();
}

class _ProjectsViewState extends State<ProjectsView> {
  late Future<List<ProjectItem>> _future;
  final _search = TextEditingController();
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = widget.repository.projects();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async =>
      setState(() => _future = widget.repository.projects());

  Future<void> _add() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => ProjectEditor(repository: widget.repository),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: widget.session.role.canAssign
        ? FloatingActionButton.extended(
            onPressed: _add,
            backgroundColor: Palette.navy,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New project'),
          )
        : null,
    body: FutureBuilder<List<ProjectItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return ErrorState(
            message: snapshot.error.toString(),
            onRetry: _refresh,
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final all = snapshot.data!;
        final filtered = all.where((project) {
          final query = _search.text.trim().toLowerCase();
          final matchesText =
              query.isEmpty ||
              project.name.toLowerCase().contains(query) ||
              project.category.toLowerCase().contains(query);
          final matchesStatus = _filter == 'all' || project.status == _filter;
          return matchesText && matchesStatus;
        }).toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              Text(
                'Make progress visible.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                '${all.length} project${all.length == 1 ? '' : 's'} in this workspace',
                style: const TextStyle(color: Palette.muted, fontSize: 13),
              ),
              const SizedBox(height: 17),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search projects',
                ),
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                children: [
                  for (final filter in ['all', 'active', 'completed'])
                    ChoiceChip(
                      label: Text(
                        filter == 'all'
                            ? 'All'
                            : filter == 'active'
                            ? 'Active'
                            : 'Completed',
                      ),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                EmptyInline(
                  icon: Icons.folder_open_outlined,
                  title: all.isEmpty
                      ? 'No projects yet'
                      : 'No matching projects',
                  detail: all.isEmpty
                      ? 'Create a project or connect your live workspace to get started.'
                      : 'Try another search or status filter.',
                  actionLabel: widget.session.role.canAssign
                      ? 'Add project'
                      : null,
                  onAction: widget.session.role.canAssign ? _add : null,
                )
              else
                for (final project in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ProjectCard(
                      project: project,
                      onTap: () => _showProject(
                        context,
                        project,
                        widget.repository,
                        widget.onOpen,
                      ),
                    ),
                  ),
              if (widget.session.isDemo)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Example project names are preview content. Create your own to try the workflow.',
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
    ),
  );
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project, this.onTap});
  final ProjectItem project;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(16),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: Palette.sand,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                project.category.toLowerCase().contains('interior')
                    ? Icons.chair_outlined
                    : Icons.apartment_outlined,
                color: Palette.navy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Palette.ink,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    project.category,
                    style: const TextStyle(color: Palette.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.more_horiz_rounded, color: Palette.muted),
          ],
        ),
        const SizedBox(height: 17),
        Row(
          children: [
            const Text(
              'Project progress',
              style: TextStyle(color: Palette.muted, fontSize: 11),
            ),
            const Spacer(),
            Text(
              '${(project.progress * 100).round()}%',
              style: const TextStyle(
                color: Palette.navy,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ProgressLine(value: project.progress),
        const SizedBox(height: 12),
        Row(
          children: [
            StatusPill(value: project.status),
            const Spacer(),
            const Icon(Icons.event_outlined, size: 14, color: Palette.muted),
            const SizedBox(width: 5),
            Text(
              formattedDate(project.dueDate),
              style: const TextStyle(color: Palette.muted, fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<void> _showProject(
  BuildContext context,
  ProjectItem project,
  WorkspaceRepository repository,
  void Function(WorkspacePage) onOpen,
) async {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Palette.ivory,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(project.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${project.category}  ·  ${formattedDate(project.dueDate, withYear: true)}',
            style: const TextStyle(color: Palette.muted, fontSize: 12),
          ),
          if (project.description.isNotEmpty) ...[
            const SizedBox(height: 13),
            Text(
              project.description,
              style: const TextStyle(color: Palette.ink, height: 1.4),
            ),
          ],
          const SizedBox(height: 18),
          ProgressLine(value: project.progress),
          const SizedBox(height: 6),
          Text(
            '${(project.progress * 100).round()}% complete',
            style: const TextStyle(color: Palette.muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onOpen(WorkspacePage.gallery);
                  },
                  icon: const Icon(Icons.collections_outlined),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.checklist_rounded),
                  label: const Text('View tasks'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class TasksView extends StatefulWidget {
  const TasksView({
    super.key,
    required this.session,
    required this.repository,
    required this.onOpen,
  });
  final AppSession session;
  final WorkspaceRepository repository;
  final void Function(WorkspacePage page) onOpen;
  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  late Future<List<TaskItem>> _future;
  String _filter = 'all';
  @override
  void initState() {
    super.initState();
    _future = widget.repository.tasks();
  }

  Future<void> _refresh() async =>
      setState(() => _future = widget.repository.tasks());

  Future<void> _add() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => TaskEditor(repository: widget.repository),
    );
    if (saved == true) _refresh();
  }

  Future<void> _advance(TaskItem task) async {
    final next = task.status == 'todo'
        ? 'in_progress'
        : task.status == 'in_progress'
        ? 'done'
        : 'todo';
    try {
      await widget.repository.updateTaskStatus(task, next);
      await _refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: widget.session.role.canAssign
        ? FloatingActionButton.extended(
            onPressed: _add,
            backgroundColor: Palette.navy,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Assign task'),
          )
        : null,
    body: FutureBuilder<List<TaskItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return ErrorState(
            message: snapshot.error.toString(),
            onRetry: _refresh,
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final all = snapshot.data!;
        final filtered = all
            .where(
              (task) =>
                  _filter == 'all' ||
                  (_filter == 'open'
                      ? task.status != 'done'
                      : task.status == 'done'),
            )
            .toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              Text(
                'Small steps, clear progress.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 7),
              Text(
                '${all.where((item) => item.status == 'done').length} completed · ${all.where((item) => item.status != 'done').length} still moving',
                style: const TextStyle(color: Palette.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final filter in ['all', 'open', 'done'])
                    ChoiceChip(
                      label: Text(
                        filter == 'all'
                            ? 'All tasks'
                            : filter == 'open'
                            ? 'Open'
                            : 'Completed',
                      ),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                EmptyInline(
                  icon: Icons.checklist_rounded,
                  title: all.isEmpty ? 'No tasks yet' : 'Nothing in this view',
                  detail: all.isEmpty
                      ? 'Tasks assigned to your role will appear here.'
                      : 'Change the filter to see more tasks.',
                  actionLabel: widget.session.role.canAssign
                      ? 'Assign task'
                      : null,
                  onAction: widget.session.role.canAssign ? _add : null,
                )
              else
                for (final task in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TaskTile(
                      task: task,
                      onAdvance: () => _advance(task),
                    ),
                  ),
            ],
          ),
        );
      },
    ),
  );
}

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.onAdvance});
  final TaskItem task;
  final VoidCallback onAdvance;
  @override
  Widget build(BuildContext context) {
    final done = task.status == 'done';
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          InkWell(
            onTap: onAdvance,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: done ? Palette.green : Palette.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: done ? Palette.green : Palette.line,
                  width: 1.5,
                ),
              ),
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 17,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Palette.ink,
                    fontSize: 13,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task.projectName.isEmpty
                      ? 'Workspace task'
                      : task.projectName,
                  style: const TextStyle(color: Palette.muted, fontSize: 11),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    StatusPill(value: task.status),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: task.priority == 'high'
                            ? const Color(0xFFF8E5E3)
                            : Palette.sand,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        task.priority.toUpperCase(),
                        style: TextStyle(
                          color: task.priority == 'high'
                              ? Palette.red
                              : Palette.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formattedDate(task.dueDate),
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CalendarView extends StatefulWidget {
  const CalendarView({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late Future<List<CalendarItem>> _future;
  DateTime _selected = DateTime.now();
  @override
  void initState() {
    super.initState();
    _future = widget.repository.calendarItems();
  }

  Future<void> _refresh() async =>
      setState(() => _future = widget.repository.calendarItems());

  Future<void> _addEvent() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Palette.ivory,
      builder: (_) => EventEditor(repository: widget.repository),
    );
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<CalendarItem>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return ErrorState(
          message: snapshot.error.toString(),
          onRetry: _refresh,
        );
      if (!snapshot.hasData)
        return const Center(child: CircularProgressIndicator());
      final events = snapshot.data!;
      final sameDay = events
          .where(
            (event) =>
                event.date.year == _selected.year &&
                event.date.month == _selected.month &&
                event.date.day == _selected.day,
          )
          .toList();
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan the next move.',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Meetings, visits and delivery dates.',
                        style: TextStyle(color: Palette.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: _selected,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (value != null) setState(() => _selected = value);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ],
            ),
            const SizedBox(height: 17),
            _WeekStrip(
              selected: _selected,
              events: events,
              onSelect: (value) => setState(() => _selected = value),
            ),
            const SizedBox(height: 22),
            SectionHeading(
              title: 'Selected day',
              actionLabel: sameDay.isEmpty && events.isNotEmpty
                  ? 'Upcoming'
                  : null,
              onAction: () => setState(() => _selected = events.first.date),
            ),
            const SizedBox(height: 10),
            if (sameDay.isEmpty)
              const EmptyInline(
                icon: Icons.event_available_outlined,
                title: 'Nothing scheduled',
                detail: 'Try another date or create a shared event.',
              )
            else
              for (final item in sameDay)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _CalendarEventTile(item: item),
                ),
            const SizedBox(height: 20),
            SectionHeading(
              title: 'Upcoming',
              actionLabel: widget.repository.session.role.canAssign
                  ? 'Add event'
                  : null,
              onAction: widget.repository.session.role.canAssign
                  ? _addEvent
                  : null,
            ),
            const SizedBox(height: 10),
            if (events.isEmpty)
              const EmptyInline(
                icon: Icons.event_note_outlined,
                title: 'Your calendar is clear',
                detail: 'Project and task deadlines will appear here automatically.',
              )
            else
              for (final item
                  in events
                      .where(
                        (item) => !item.date.isBefore(
                          DateTime.now().subtract(const Duration(days: 1)),
                        ),
                      )
                      .take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _CalendarEventTile(item: item),
                ),
            const SizedBox(height: 10),
            if (widget.repository.isDemo)
              const Text(
                'Preview calendar entries are sample content; dates and tasks are illustrative.',
                style: TextStyle(color: Palette.muted, fontSize: 11),
              ),
          ],
        ),
      );
    },
  );
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.events,
    required this.onSelect,
  });
  final DateTime selected;
  final List<CalendarItem> events;
  final ValueChanged<DateTime> onSelect;
  @override
  Widget build(BuildContext context) {
    final start = DateTime(
      selected.year,
      selected.month,
      selected.day,
    ).subtract(Duration(days: selected.weekday - 1));
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final date = start.add(Duration(days: i));
                  final active =
                      date.year == selected.year &&
                      date.month == selected.month &&
                      date.day == selected.day;
                  final hasEvent = events.any(
                    (item) =>
                        item.date.year == date.year &&
                        item.date.month == date.month &&
                        item.date.day == date.day,
                  );
                  return InkWell(
                    onTap: () => onSelect(date),
                    borderRadius: BorderRadius.circular(14),
                    child: Column(
                      children: [
                        Text(
                          _shortDay(date.weekday),
                          style: TextStyle(
                            color: active ? Palette.navy : Palette.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 34,
                          height: 38,
                          decoration: BoxDecoration(
                            color: active ? Palette.navy : Colors.transparent,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Center(
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                color: active ? Colors.white : Palette.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: hasEvent ? Palette.blue : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({required this.item});
  final CalendarItem item;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 45,
          decoration: BoxDecoration(
            color: Palette.sand,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${item.date.day}',
                style: const TextStyle(
                  color: Palette.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              Text(
                _monthShort(item.date.month),
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Palette.ink,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.subtitle.isEmpty
                    ? item.kind
                    : '${item.kind}  ·  ${item.subtitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Palette.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        Text(
          '${item.date.hour.toString().padLeft(2, '0')}:${item.date.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(
            color: Palette.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    required this.session,
    required this.onOpen,
    required this.onSignOut,
  });
  final AppSession session;
  final void Function(WorkspacePage) onOpen;
  final Future<void> Function() onSignOut;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 17, 20, 26),
    children: [
      Text(
        'Your workspace.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 15),
      SurfaceCard(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Palette.navy,
                borderRadius: BorderRadius.circular(19),
              ),
              child: Icon(
                _profileIcon(session.role),
                color: Colors.white,
                size: 27,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.isDemo ? 'Preview role' : session.name,
                    style: const TextStyle(
                      color: Palette.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.role.label,
                    style: const TextStyle(
                      color: Palette.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!session.isDemo && session.employeeId != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Employee ID  ·  ${session.employeeId}',
                      style: const TextStyle(
                        color: Palette.navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (!session.isDemo) ...[
                    const SizedBox(height: 3),
                    Text(
                      session.email,
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.verified_user_outlined, color: Palette.green),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SectionHeading(title: 'Manage your day'),
      const SizedBox(height: 9),
      _ProfileAction(
        icon: Icons.location_on_outlined,
        title: 'Location attendance',
        subtitle: 'Verified office and project sites',
        onTap: () => onOpen(WorkspacePage.attendance),
      ),
      _ProfileAction(
        icon: Icons.edit_note_rounded,
        title: 'Daily reports & weekly summaries',
        subtitle: 'Submit progress and review work',
        onTap: () => onOpen(WorkspacePage.reports),
      ),
      _ProfileAction(
        icon: Icons.collections_outlined,
        title: 'Project gallery',
        subtitle: 'Photos and previous work',
        onTap: () => onOpen(WorkspacePage.gallery),
      ),
      _ProfileAction(
        icon: Icons.history_rounded,
        title: 'Work history',
        subtitle: 'Reports, updates and approvals',
        onTap: () => onOpen(WorkspacePage.history),
      ),
      _ProfileAction(
        icon: Icons.groups_2_outlined,
        title: 'My team',
        subtitle: 'Workspace people and roles',
        onTap: () => onOpen(WorkspacePage.team),
      ),
      _ProfileAction(
        icon: Icons.insights_outlined,
        title: 'Analytics',
        subtitle: 'Attendance and productivity',
        onTap: () => onOpen(WorkspacePage.analytics),
      ),
      if (session.role.canAssign)
        _ProfileAction(
          icon: Icons.tune_rounded,
          title: 'Attendance sites',
          subtitle: 'Configure authorized sites and radii',
          onTap: () => onOpen(WorkspacePage.settings),
        ),
      const SizedBox(height: 13),
      if (session.isDemo)
        OutlinedButton.icon(
          onPressed: () => onOpen(WorkspacePage.settings),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Live setup guide'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(49),
          ),
        )
      else
        OutlinedButton.icon(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(49),
          ),
        ),
      const SizedBox(height: 18),
      const Center(
        child: Text(
          'INDETAIL  ·  PROJECTS • PEOPLE • PRODUCTIVITY',
          style: TextStyle(
            color: Palette.muted,
            fontSize: 9,
            letterSpacing: .7,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Icon(icon, size: 20, color: Palette.navy),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: Palette.ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: Palette.muted, fontSize: 10),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, color: Palette.muted),
    onTap: onTap,
  );
}

class ProjectEditor extends StatefulWidget {
  const ProjectEditor({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<ProjectEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _people = <String>{};
  String _category = 'Interior';
  String? _teamId;
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;
  late final Future<List<Object>> _managementData = Future.wait([
    widget.repository.manageableTeams(),
    widget.repository.people(),
  ]);
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 1825)),
    );
    if (date != null) setState(() => _dueDate = date);
  }

  Future<void> _save(List<Map<String, Object?>> teams) async {
    if (!_formKey.currentState!.validate()) return;
    final selectedTeamId =
        _teamId ??
        (widget.repository.session.role == UserRole.teamLeader &&
                teams.isNotEmpty
            ? '${teams.first['id']}'
            : null);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createProject(
        name: _name.text.trim(),
        category: _category,
        description: _description.text.trim(),
        dueDate: _dueDate,
        assignedUserIds: _people.toList(),
        teamId: selectedTeamId,
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
      MediaQuery.viewInsetsOf(context).bottom + 22,
    ),
    child: FutureBuilder<List<Object>>(
      future: _managementData,
      builder: (context, managementSnapshot) {
        if (managementSnapshot.hasError)
          return ErrorState(
            message: managementSnapshot.error.toString(),
            onRetry: () async {},
          );
        if (!managementSnapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          );
        final teams = managementSnapshot.data![0] as List<Map<String, Object?>>;
        final people =
            managementSnapshot.data![1] as List<Map<String, Object?>>;
        final effectiveTeamId =
            _teamId ??
            (widget.repository.session.role == UserRole.teamLeader &&
                    teams.isNotEmpty
                ? '${teams.first['id']}'
                : null);
        return SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New project',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Project name'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Add a project name.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items:
                      const ['Interior', 'Architecture', 'Renovation', 'Other']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => _category = value ?? 'Interior'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Project notes',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: effectiveTeamId,
                  decoration: InputDecoration(
                    labelText: widget.repository.session.role.isAdmin
                        ? 'Team (optional)'
                        : 'Team you lead',
                  ),
                  items: [
                    if (widget.repository.session.role.isAdmin)
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No team'),
                      ),
                    ...teams.map(
                      (team) => DropdownMenuItem<String?>(
                        value: '${team['id']}',
                        child: Text('${team['name'] ?? 'Team'}'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _teamId = value;
                    _people.clear();
                  }),
                ),
                if (widget.repository.session.role == UserRole.teamLeader &&
                    teams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Text(
                      'Create a team and add yourself as Team Leader before creating projects.',
                      style: TextStyle(color: Palette.red, fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _dueDate == null
                        ? 'Add deadline'
                        : 'Deadline · ${formattedDate(_dueDate, withYear: true)}',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(47),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  'Assign project',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                const Text(
                  'Choose workspace members. Team Leaders can assign within their team scope.',
                  style: TextStyle(
                    color: Palette.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 9),
                _projectAssignees(people, effectiveTeamId),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Palette.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 15),
                FilledButton(
                  onPressed:
                      _busy ||
                          (widget.repository.session.role ==
                                  UserRole.teamLeader &&
                              teams.isEmpty)
                      ? null
                      : () => _save(teams),
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
                      : const Text('Create project'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _projectAssignees(List<Map<String, Object?>> people, String? teamId) {
    if (widget.repository.session.role != UserRole.teamLeader ||
        teamId == null) {
      if (people.isEmpty)
        return const Text(
          'No employees have signed up yet.',
          style: TextStyle(color: Palette.muted, fontSize: 11),
        );
      return Wrap(
        spacing: 7,
        runSpacing: 2,
        children: [
          for (final person in people)
            FilterChip(
              label: Text(
                '${person['display_name'] ?? 'Member'} · ${person['employee_id'] ?? ''}',
              ),
              selected: _people.contains('${person['id']}'),
              onSelected: (selected) => setState(() {
                selected
                    ? _people.add('${person['id']}')
                    : _people.remove('${person['id']}');
              }),
            ),
        ],
      );
    }
    return FutureBuilder<List<Map<String, Object?>>>(
      future: widget.repository.teamMembers(teamId),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Text(
            snapshot.error.toString(),
            style: const TextStyle(color: Palette.red, fontSize: 11),
          );
        if (!snapshot.hasData)
          return const LinearProgressIndicator(minHeight: 2);
        final memberIds = snapshot.data!
            .map((item) => '${item['user_id']}')
            .toSet();
        final assignable = people
            .where((person) => memberIds.contains('${person['id']}'))
            .toList();
        if (assignable.isEmpty)
          return const Text(
            'Add employees to this team before assigning the project.',
            style: TextStyle(color: Palette.muted, fontSize: 11),
          );
        return Wrap(
          spacing: 7,
          runSpacing: 2,
          children: [
            for (final person in assignable)
              FilterChip(
                label: Text(
                  '${person['display_name'] ?? 'Member'} · ${person['employee_id'] ?? ''}',
                ),
                selected: _people.contains('${person['id']}'),
                onSelected: (selected) => setState(() {
                  selected
                      ? _people.add('${person['id']}')
                      : _people.remove('${person['id']}');
                }),
              ),
          ],
        );
      },
    );
  }
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late final Future<List<Object>> _data = Future.wait([
    widget.repository.manageableProjects(),
    widget.repository.people(),
  ]);
  String? _projectId;
  String? _assignee;
  String _priority = 'normal';
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save(List<ProjectItem> projects) async {
    if (!_formKey.currentState!.validate()) return;
    final projectId =
        _projectId ?? (projects.isNotEmpty ? projects.first.id : null);
    if (projectId == null) {
      setState(() => _error = 'Create a project before assigning a task.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.createTask(
        title: _title.text.trim(),
        description: _description.text.trim(),
        projectId: projectId,
        assigneeId: _assignee,
        dueDate: _dueDate,
        priority: _priority,
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
      MediaQuery.viewInsetsOf(context).bottom + 22,
    ),
    child: FutureBuilder<List<Object>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return ErrorState(
            message: snapshot.error.toString(),
            onRetry: () async {},
          );
        if (!snapshot.hasData)
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          );
        final projects = snapshot.data![0] as List<ProjectItem>;
        final people = snapshot.data![1] as List<Map<String, Object?>>;
        return SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assign a task',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Task title'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Add a task title.'
                      : null,
                ),
                const SizedBox(height: 12),
                if (projects.isEmpty)
                  const EmptyInline(
                    icon: Icons.folder_open_outlined,
                    title: 'No project is available',
                    detail: 'Create a project before adding its tasks.',
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _projectId ?? projects.first.id,
                    decoration: const InputDecoration(labelText: 'Project'),
                    items: projects
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      _projectId = value;
                      _assignee = null;
                    }),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Task notes',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const ['low', 'normal', 'high', 'urgent']
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _priority = value ?? 'normal'),
                ),
                const SizedBox(height: 12),
                _taskAssigneeField(projects, people),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate:
                          _dueDate ??
                          DateTime.now().add(const Duration(days: 2)),
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 1825)),
                    );
                    if (date != null) setState(() => _dueDate = date);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _dueDate == null
                        ? 'Add deadline'
                        : 'Deadline · ${formattedDate(_dueDate, withYear: true)}',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(47),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Palette.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 15),
                FilledButton(
                  onPressed: _busy || projects.isEmpty
                      ? null
                      : () => _save(projects),
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
                      : const Text('Save task'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _taskAssigneeField(
    List<ProjectItem> projects,
    List<Map<String, Object?>> people,
  ) {
    if (widget.repository.session.role != UserRole.teamLeader) {
      return DropdownButtonFormField<String?>(
        initialValue: _assignee,
        decoration: const InputDecoration(labelText: 'Assign to'),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Leave unassigned'),
          ),
          ...people.map(
            (person) => DropdownMenuItem<String?>(
              value: '${person['id']}',
              child: Text(
                '${person['display_name'] ?? 'Member'} · ${person['employee_id'] ?? ''}',
              ),
            ),
          ),
        ],
        onChanged: (value) => setState(() => _assignee = value),
      );
    }
    final project = projects.where(
      (item) =>
          item.id ==
          (_projectId ?? (projects.isNotEmpty ? projects.first.id : null)),
    );
    if (project.isEmpty || project.first.teamId == null)
      return const Text(
        'Select a project connected to a team you lead.',
        style: TextStyle(color: Palette.muted, fontSize: 11),
      );
    return FutureBuilder<List<Map<String, Object?>>>(
      future: widget.repository.teamMembers(project.first.teamId!),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Text(
            snapshot.error.toString(),
            style: const TextStyle(color: Palette.red, fontSize: 11),
          );
        if (!snapshot.hasData)
          return const LinearProgressIndicator(minHeight: 2);
        final memberIds = snapshot.data!
            .map((row) => '${row['user_id']}')
            .toSet();
        final assignable = people
            .where((person) => memberIds.contains('${person['id']}'))
            .toList();
        return DropdownButtonFormField<String?>(
          initialValue: _assignee,
          decoration: const InputDecoration(labelText: 'Assign to team member'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Leave unassigned'),
            ),
            ...assignable.map(
              (person) => DropdownMenuItem<String?>(
                value: '${person['id']}',
                child: Text(
                  '${person['display_name'] ?? 'Member'} · ${person['employee_id'] ?? ''}',
                ),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _assignee = value),
        );
      },
    );
  }
}

class EventEditor extends StatefulWidget {
  const EventEditor({super.key, required this.repository});
  final WorkspaceRepository repository;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String _kind = 'Meeting';
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 1825)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time != null && mounted)
      setState(
        () => _date = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 22,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add calendar event',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Event title'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Event type'),
            items: const ['Meeting', 'Site visit', 'Review', 'Delivery']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() => _kind = value ?? 'Meeting'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDateTime,
            icon: const Icon(Icons.event_outlined),
            label: Text(
              '${formattedDate(_date, withYear: true)}  ·  ${formattedTime(_date)}',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: Palette.red, fontSize: 12),
            ),
          const SizedBox(height: 15),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (_title.text.trim().isEmpty) {
                      setState(() => _error = 'Add an event title.');
                      return;
                    }
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await widget.repository.createCalendarEvent(
                        title: _title.text.trim(),
                        kind: _kind,
                        description: _description.text.trim(),
                        startsAt: _date,
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
            child: const Text('Add event'),
          ),
        ],
      ),
    ),
  );
}

String _shortDay(int day) => const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day - 1];
String _monthShort(int month) => const [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
][month - 1];
IconData _profileIcon(UserRole role) => switch (role) {
  UserRole.admin => Icons.admin_panel_settings_outlined,
  UserRole.teamLeader => Icons.groups_2_outlined,
  UserRole.employee => Icons.person_outline_rounded,
};
