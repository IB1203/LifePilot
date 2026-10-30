import 'package:flutter/material.dart';

import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/task_logic.dart';
import '../ui/forms.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'habits_tab.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Column(
          children: [
            Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const TabBar(
                tabs: [
                  Tab(text: 'List'),
                  Tab(text: 'Calendar'),
                  Tab(text: 'Timeline'),
                  Tab(text: 'Habits'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ListTab(store: store),
                  _CalendarTab(store: store),
                  _TimelineTab(store: store),
                  HabitsTab(store: store),
                ],
              ),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// List

enum _View { smart, all, done }

class _ListTab extends StatefulWidget {
  const _ListTab({required this.store});

  final LifePilotStore store;

  @override
  State<_ListTab> createState() => _ListTabState();
}

class _ListTabState extends State<_ListTab> {
  final _search = TextEditingController();
  _View _view = _View.smart;
  TaskFilter _filter = const TaskFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = store.now();
    final filter = TaskFilter(
      statuses: _filter.statuses,
      priorities: _filter.priorities,
      category: _filter.category,
      project: _filter.project,
      query: _search.text,
    );
    final tasks = store.tasks.where(filter.matches).toList();
    final buckets = TaskBuckets.from(tasks, now);
    final conflicts = conflictingTaskIds(store.tasks);
    Widget tile(LocalTask task) => TaskTile(
          key: ValueKey(task.id),
          store: store,
          task: task,
          now: now,
          conflict: conflicts.contains(task.id),
        );

    final open = buckets.overdue.length +
        buckets.today.length +
        buckets.upcoming.length +
        buckets.noDeadline.length;
    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search tasks and tags',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: !_filter.isEmpty,
              child: IconButton.filledTonal(
                tooltip: 'Filter tasks',
                onPressed: _openFilters,
                icon: const Icon(Icons.filter_list),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<_View>(
          segments: [
            ButtonSegment(value: _View.smart, label: Text('Open ($open)')),
            const ButtonSegment(value: _View.all, label: Text('All')),
            ButtonSegment(
                value: _View.done,
                label: Text('Done (${buckets.completed.length})')),
          ],
          selected: {_view},
          onSelectionChanged: (value) => setState(() => _view = value.first),
        ),
        if (conflicts.isNotEmpty && _view != _View.done)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.event_busy),
                title: Text('${conflicts.length} tasks have overlapping times'),
                subtitle: const Text(
                    'Look for the clash marker and reschedule one of them.'),
              ),
            ),
          ),
        const SizedBox(height: 4),
        if (store.tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No tasks yet',
              message:
                  'Add tasks with due times, priorities, subtasks and reminders.',
              actionLabel: 'Add task',
              onAction: () => showTaskForm(context, store),
            ),
          )
        else if (_view == _View.smart) ...[
          _Section(
              title: 'Overdue',
              tasks: buckets.overdue,
              tile: tile,
              danger: true),
          _Section(title: 'Today', tasks: buckets.today, tile: tile),
          _Section(title: 'Upcoming', tasks: buckets.upcoming, tile: tile),
          _Section(title: 'No deadline', tasks: buckets.noDeadline, tile: tile),
          if (open == 0)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: EmptyState(
                icon: Icons.celebration_outlined,
                title: 'All caught up',
                message: 'No open tasks match this view.',
              ),
            ),
        ] else if (_view == _View.all)
          _Section(
              title: 'All tasks',
              tasks: [...tasks]..sort(compareTasks),
              tile: tile)
        else
          buckets.completed.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'Nothing completed yet',
                    message: 'Completed tasks will be collected here.',
                  ),
                )
              : _Section(
                  title: 'Completed', tasks: buckets.completed, tile: tile),
      ],
    );
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<TaskFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(store: widget.store, initial: _filter),
    );
    if (result != null) setState(() => _filter = result);
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.tasks,
    required this.tile,
    this.danger = false,
  });

  final String title;
  final List<LocalTask> tasks;
  final Widget Function(LocalTask) tile;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text('$title · ${tasks.length}',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ),
        AnimatedSize(
          duration: motion(context, 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (final task in tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: tile(task),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A task row with priority marker, due details, animated completion and
/// expandable subtasks.
class TaskTile extends StatefulWidget {
  const TaskTile({
    required this.store,
    required this.task,
    required this.now,
    this.conflict = false,
    super.key,
  });

  final LifePilotStore store;
  final LocalTask task;
  final DateTime now;
  final bool conflict;

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool _expanded = false;
  bool _completing = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final store = widget.store;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overdue = isOverdue(task, widget.now);
    final done = task.isDone || _completing;
    final use24h = store.settings.use24HourClock;
    final doneSubtasks = task.subtasks.where((s) => s.done).length;
    final due = task.dueAt;
    final details = <Widget>[
      if (due != null)
        Pill(
          icon: overdue ? Icons.error_outline : Icons.event_outlined,
          color: overdue ? scheme.error : null,
          label: '${overdue ? 'Overdue · ' : ''}${friendlyDay(due, widget.now)}'
              '${task.dueHasTime ? ' ${formatTime(due, use24h: use24h)}' : ''}',
        ),
      if (task.status != TaskStatus.todo && !task.isDone)
        Pill(label: task.status.label, color: scheme.tertiary),
      if (task.project.isNotEmpty)
        Pill(icon: Icons.folder_outlined, label: task.project),
      if (!task.recurrence.isNone)
        Pill(icon: Icons.repeat, label: task.recurrence.label),
      if (task.reminderOffsets.isNotEmpty && !task.isDone)
        const Pill(icon: Icons.notifications_none, label: 'Reminder'),
      if (task.snoozedUntil != null && task.snoozedUntil!.isAfter(widget.now))
        Pill(
            icon: Icons.snooze,
            label: 'Until ${formatTime(task.snoozedUntil!, use24h: use24h)}'),
      if (task.subtasks.isNotEmpty)
        Pill(
            icon: Icons.checklist,
            label: '$doneSubtasks/${task.subtasks.length}'),
      if (task.durationMinutes != null)
        Pill(
            icon: Icons.hourglass_empty,
            label: formatDuration(Duration(minutes: task.durationMinutes!))),
      if (widget.conflict)
        Pill(icon: Icons.event_busy, label: 'Time clash', color: scheme.error),
      for (final tag in task.tags) Pill(label: '#$tag'),
    ];
    return AnimatedOpacity(
      opacity: done && !task.isDone ? 0.5 : 1,
      duration: motion(context, 200),
      child: Card(
        child: InkWell(
          onTap: () => showTaskForm(context, store, task: task),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                    width: 4, color: priorityColor(context, task.priority)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 0, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Semantics(
                              label: done ? 'Mark not done' : 'Mark done',
                              child: IconButton(
                                onPressed: _toggle,
                                icon: AnimatedSwitcher(
                                  duration: motion(context, 220),
                                  transitionBuilder: (child, animation) =>
                                      ScaleTransition(
                                          scale: animation, child: child),
                                  child: Icon(
                                    done
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    key: ValueKey(done),
                                    color: done
                                        ? AppColors.of(context).income
                                        : priorityColor(context, task.priority),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedDefaultTextStyle(
                                    duration: motion(context, 200),
                                    style: theme.textTheme.titleSmall!.copyWith(
                                      decoration: done
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      color:
                                          done ? scheme.onSurfaceVariant : null,
                                    ),
                                    child: Text(task.title),
                                  ),
                                  if (task.description.isNotEmpty)
                                    Text(task.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                            if (task.priority.index >= TaskPriority.high.index)
                              PriorityBadge(priority: task.priority),
                            _menu(context),
                          ],
                        ),
                        if (details.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, right: 12),
                            child: Wrap(
                                spacing: 6, runSpacing: 4, children: details),
                          ),
                        if (task.subtasks.isNotEmpty) ...[
                          InkWell(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                              child: Row(
                                children: [
                                  AnimatedRotation(
                                    turns: _expanded ? 0.5 : 0,
                                    duration: motion(context, 200),
                                    child:
                                        const Icon(Icons.expand_more, size: 18),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                      _expanded
                                          ? 'Hide subtasks'
                                          : 'Show subtasks',
                                      style: theme.textTheme.labelMedium),
                                ],
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: motion(context, 220),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: !_expanded
                                ? const SizedBox(width: double.infinity)
                                : Column(
                                    children: [
                                      for (final subtask in task.subtasks)
                                        CheckboxListTile(
                                          dense: true,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          value: subtask.done,
                                          title: Text(subtask.title,
                                              style: subtask.done
                                                  ? const TextStyle(
                                                      decoration: TextDecoration
                                                          .lineThrough)
                                                  : null),
                                          onChanged: (_) => store.toggleSubtask(
                                              task.id, subtask.id),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final task = widget.task;
    if (task.isDone) {
      await widget.store.setTaskStatus(task.id, TaskStatus.todo);
      return;
    }
    // Show the completed state briefly before the task moves sections.
    setState(() => _completing = true);
    await Future<void>.delayed(motion(context, 350));
    await widget.store.setTaskStatus(task.id, TaskStatus.done);
    if (mounted) setState(() => _completing = false);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(task.recurrence.isNone
            ? 'Completed “${task.title}”'
            : 'Completed · next one scheduled'),
        action: task.recurrence.isNone
            ? SnackBarAction(
                label: 'Undo',
                onPressed: () =>
                    widget.store.setTaskStatus(task.id, TaskStatus.todo))
            : null,
      ));
  }

  Widget _menu(BuildContext context) {
    final task = widget.task;
    final store = widget.store;
    return PopupMenuButton<String>(
      tooltip: 'Task options',
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await showTaskForm(context, store, task: task);
          case 'reschedule':
            await showRescheduleSheet(context, store, task);
          case 'snooze':
            await showSnoozeSheet(context, store, task);
          case 'cancel':
            await store.cancelTaskReminders(task.id);
            if (context.mounted) showMessage(context, 'Reminders cancelled');
          case 'delete':
            if (await confirmAction(context,
                title: 'Delete task?',
                message: '“${task.title}” and its reminders will be removed.',
                confirmLabel: 'Delete',
                destructive: true)) {
              await store.deleteTask(task.id);
            }
          default:
            if (value.startsWith('status:')) {
              await store.setTaskStatus(
                  task.id, TaskStatus.values.byName(value.substring(7)));
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (!task.isDone) ...[
          const PopupMenuItem(value: 'reschedule', child: Text('Reschedule')),
          const PopupMenuItem(value: 'snooze', child: Text('Snooze reminder')),
          if (task.reminderOffsets.isNotEmpty || task.snoozedUntil != null)
            const PopupMenuItem(
                value: 'cancel', child: Text('Cancel reminders')),
        ],
        const PopupMenuDivider(),
        for (final status in TaskStatus.values)
          if (status != task.status)
            PopupMenuItem(
                value: 'status:${status.name}',
                child: Text('Move to ${status.label}')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.store, required this.initial});

  final LifePilotStore store;
  final TaskFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<TaskStatus> _statuses = {...widget.initial.statuses};
  late final Set<TaskPriority> _priorities = {...widget.initial.priorities};
  late String? _category = widget.initial.category;
  late String? _project = widget.initial.project;

  @override
  Widget build(BuildContext context) {
    final categories = {
      for (final task in widget.store.tasks)
        if (task.category.isNotEmpty) task.category,
    }.toList()
      ..sort();
    final label = Theme.of(context).textTheme.labelLarge;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text('Filter tasks',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text('Status', style: label),
          Wrap(spacing: 6, children: [
            for (final status in TaskStatus.values)
              FilterChip(
                label: Text(status.label),
                selected: _statuses.contains(status),
                onSelected: (on) => setState(() =>
                    on ? _statuses.add(status) : _statuses.remove(status)),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Priority', style: label),
          Wrap(spacing: 6, children: [
            for (final priority in TaskPriority.values)
              FilterChip(
                label: Text(priority.label),
                selected: _priorities.contains(priority),
                onSelected: (on) => setState(() => on
                    ? _priorities.add(priority)
                    : _priorities.remove(priority)),
              ),
          ]),
          if (widget.store.projects.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Project', style: label),
            Wrap(spacing: 6, children: [
              for (final project in widget.store.projects)
                ChoiceChip(
                  label: Text(project),
                  selected: _project == project,
                  onSelected: (on) =>
                      setState(() => _project = on ? project : null),
                ),
            ]),
          ],
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Category', style: label),
            Wrap(spacing: 6, children: [
              for (final category in categories)
                ChoiceChip(
                  label: Text(category),
                  selected: _category == category,
                  onSelected: (on) =>
                      setState(() => _category = on ? category : null),
                ),
            ]),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, const TaskFilter()),
                child: const Text('Clear'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  TaskFilter(
                    statuses: _statuses,
                    priorities: _priorities,
                    category: _category,
                    project: _project,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar

enum _CalendarMode { month, week, day }

class _CalendarTab extends StatefulWidget {
  const _CalendarTab({required this.store});

  final LifePilotStore store;

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
  late DateTime _selected = dateOnly(widget.store.now());
  late DateTime _month = DateTime(_selected.year, _selected.month);
  _CalendarMode _mode = _CalendarMode.month;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final now = store.now();
    return ListView(
      padding: pagePadding,
      children: [
        const SizedBox(height: 8),
        SegmentedButton<_CalendarMode>(
          segments: const [
            ButtonSegment(value: _CalendarMode.month, label: Text('Month')),
            ButtonSegment(value: _CalendarMode.week, label: Text('Week')),
            ButtonSegment(value: _CalendarMode.day, label: Text('Day')),
          ],
          selected: {_mode},
          onSelectionChanged: (value) => setState(() => _mode = value.first),
        ),
        const SizedBox(height: 10),
        if (_mode == _CalendarMode.month) _monthGrid(context, now),
        if (_mode == _CalendarMode.week) _weekStrip(context, now),
        if (_mode == _CalendarMode.day) _dayHeader(context),
        const SizedBox(height: 12),
        _Agenda(store: store, day: _selected, now: now),
      ],
    );
  }

  ({int tasks, int bills}) _counts(DateTime day) => (
        tasks: widget.store.tasks
            .where((task) => !task.isDone && isScheduledOn(task, day))
            .length,
        bills: widget.store.bills
            .where((bill) => bill.active && isSameDay(bill.nextDueAt, day))
            .length,
      );

  Widget _navigator(String label, VoidCallback previous, VoidCallback next) =>
      Row(
        children: [
          IconButton(
              tooltip: 'Previous',
              onPressed: previous,
              icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
              tooltip: 'Next',
              onPressed: next,
              icon: const Icon(Icons.chevron_right)),
        ],
      );

  Widget _monthGrid(BuildContext context, DateTime now) {
    final first = _month;
    final leading = first.weekday - 1;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final cells = ((leading + days) / 7).ceil() * 7;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          children: [
            _navigator(
              monthLabel(_month),
              () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1)),
            ),
            Row(
              children: [
                for (var day = 1; day <= 7; day++)
                  Expanded(
                    child: Text(weekdayShort(day).substring(0, 2),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, childAspectRatio: 0.95),
              itemBuilder: (context, index) {
                final dayNumber = index - leading + 1;
                if (dayNumber < 1 || dayNumber > days) return const SizedBox();
                final day = DateTime(first.year, first.month, dayNumber);
                final selected = isSameDay(day, _selected);
                final today = isSameDay(day, now);
                final counts = _counts(day);
                return DragTarget<LocalTask>(
                  onAcceptWithDetails: (details) =>
                      _moveTask(details.data, day),
                  builder: (context, candidates, _) => InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selected = day),
                    child: AnimatedContainer(
                      duration: motion(context, 180),
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: candidates.isNotEmpty
                            ? scheme.tertiaryContainer
                            : selected
                                ? scheme.primary
                                : null,
                        borderRadius: BorderRadius.circular(10),
                        border: today && !selected
                            ? Border.all(color: scheme.primary)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$dayNumber',
                              style: TextStyle(
                                color: selected ? scheme.onPrimary : null,
                                fontWeight: today ? FontWeight.w700 : null,
                              )),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (counts.tasks > 0)
                                _Dot(
                                    color: selected
                                        ? scheme.onPrimary
                                        : scheme.primary),
                              if (counts.bills > 0)
                                _Dot(
                                    color: selected
                                        ? scheme.onPrimary
                                        : AppColors.of(context).warning),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Moves a task dropped on a calendar day, keeping its time of day.
  Future<void> _moveTask(LocalTask task, DateTime day) async {
    final due = task.dueAt;
    final hasTime = task.dueHasTime && due != null;
    final target = DateTime(day.year, day.month, day.day,
        hasTime ? due.hour : 0, hasTime ? due.minute : 0);
    if (due != null && target == due) return;
    await widget.store.rescheduleTask(task.id, target, hasTime: hasTime);
    if (!mounted) return;
    setState(() => _selected = day);
    showMessage(context, 'Moved “${task.title}” to ${formatDate(day)}');
  }

  Widget _weekStrip(BuildContext context, DateTime now) {
    final week = weekRange(_selected);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          children: [
            _navigator(
              'Week of ${formatShortDate(week.start)}',
              () => setState(() => _selected =
                  DateTime(_selected.year, _selected.month, _selected.day - 7)),
              () => setState(() => _selected =
                  DateTime(_selected.year, _selected.month, _selected.day + 7)),
            ),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final day = DateTime(week.start.year, week.start.month,
                          week.start.day + i);
                      final selected = isSameDay(day, _selected);
                      final counts = _counts(day);
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selected = day),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? scheme.primary : null,
                            borderRadius: BorderRadius.circular(12),
                            border: isSameDay(day, now) && !selected
                                ? Border.all(color: scheme.primary)
                                : null,
                          ),
                          child: Column(
                            children: [
                              Text(weekdayShort(day.weekday),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: selected
                                              ? scheme.onPrimary
                                              : null)),
                              Text('${day.day}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                          color: selected
                                              ? scheme.onPrimary
                                              : null)),
                              Text(
                                  counts.tasks + counts.bills == 0
                                      ? ' '
                                      : '${counts.tasks + counts.bills}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: selected
                                              ? scheme.onPrimary
                                              : scheme.primary)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayHeader(BuildContext context) => Card(
        child: _navigator(
          formatLongDate(_selected),
          () => setState(() => _selected =
              DateTime(_selected.year, _selected.month, _selected.day - 1)),
          () => setState(() => _selected =
              DateTime(_selected.year, _selected.month, _selected.day + 1)),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _Agenda extends StatelessWidget {
  const _Agenda({required this.store, required this.day, required this.now});

  final LifePilotStore store;
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tasks = store.tasks.where((task) => isScheduledOn(task, day)).toList()
      ..sort((a, b) {
        final startA = a.timeBlock?.start ?? (a.dueHasTime ? a.dueAt : null);
        final startB = b.timeBlock?.start ?? (b.dueHasTime ? b.dueAt : null);
        if (startA == null && startB == null) return compareTasks(a, b);
        if (startA == null) return 1;
        if (startB == null) return -1;
        return startA.compareTo(startB);
      });
    final bills = store.bills
        .where((bill) => bill.active && isSameDay(bill.nextDueAt, day))
        .toList();
    final conflicts = conflictingTaskIds(tasks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: friendlyDay(day, now),
          action: 'Add task',
          onAction: () => showTaskForm(context, store, initialDue: day),
        ),
        if (tasks.isEmpty && bills.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.event_available_outlined,
            title: 'Nothing scheduled',
            message: 'Tasks and bills due on this day appear here.',
          ),
        for (final bill in bills)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.receipt_outlined,
                    color: AppColors.of(context).warning),
                title: Text('${bill.name} due'),
                subtitle: Text(formatMoney(bill.amountPaise)),
                trailing: TextButton(
                  onPressed: () => showMarkPaidForm(context, store, bill),
                  child: const Text('Mark paid'),
                ),
              ),
            ),
          ),
        if (tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
                'Tip: in Month view, long-press a task and drop it on another day to reschedule.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        for (final task in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LongPressDraggable<LocalTask>(
              data: task,
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.drag_indicator, size: 18),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(task.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.4,
                child: TaskTile(
                    store: store, task: task, now: now, conflict: false),
              ),
              child: TaskTile(
                key: ValueKey(task.id),
                store: store,
                task: task,
                now: now,
                conflict: conflicts.contains(task.id),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final now = store.now();
    final today = dateOnly(now);
    final until = DateTime(today.year, today.month, today.day + 31);
    final items = <({DateTime at, bool timed, Widget child})>[];
    final conflicts = conflictingTaskIds(store.tasks);
    final use24h = store.settings.use24HourClock;
    for (final task in store.tasks) {
      final due = task.dueAt;
      if (task.isDone || due == null || !due.isBefore(until)) continue;
      final start = task.timeBlock?.start ?? due;
      items.add((
        at: isOverdue(task, now) ? today : start,
        timed: task.dueHasTime || task.startAt != null,
        child: TaskTile(
          key: ValueKey(task.id),
          store: store,
          task: task,
          now: now,
          conflict: conflicts.contains(task.id),
        ),
      ));
    }
    for (final bill in upcomingBills(store.bills, now, withinDays: 31)) {
      items.add((
        at: isBillOverdue(bill, now) ? today : bill.nextDueAt,
        timed: false,
        child: Card(
          child: ListTile(
            leading: Icon(Icons.receipt_outlined,
                color: AppColors.of(context).warning),
            title: Text('${bill.name} · ${formatMoney(bill.amountPaise)}'),
            subtitle: Text(isBillOverdue(bill, now)
                ? 'Overdue since ${formatDate(bill.nextDueAt)}'
                : 'Bill due'),
            trailing: TextButton(
              onPressed: () => showMarkPaidForm(context, store, bill),
              child: const Text('Mark paid'),
            ),
          ),
        ),
      ));
    }
    items.sort((a, b) => a.at.compareTo(b.at));
    final children = <Widget>[
      const SectionHeader(title: 'Next 30 days'),
    ];
    if (items.isEmpty) {
      children.add(EmptyState(
        icon: Icons.timeline,
        title: 'Nothing on the timeline',
        message:
            'Tasks with due dates and upcoming bills appear here in order.',
        actionLabel: 'Add task',
        onAction: () => showTaskForm(context, store),
      ));
    }
    DateTime? currentDay;
    for (final item in items) {
      final day = dateOnly(item.at);
      if (day != currentDay) {
        currentDay = day;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(
            day == today
                ? 'Today (including overdue)'
                : '${friendlyDay(day, now)} · ${formatDate(day)}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(
                  item.timed ? formatTime(item.at, use24h: use24h) : 'All day',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            Expanded(child: item.child),
          ],
        ),
      ));
    }
    return ListView(padding: pagePadding, children: children);
  }
}
