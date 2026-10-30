import 'formatters.dart';
import 'models.dart';

/// Effective due moment. Date-only tasks are due at the end of that day.
DateTime? effectiveDue(LocalTask task) {
  final due = task.dueAt;
  if (due == null) return null;
  return task.dueHasTime
      ? due
      : DateTime(due.year, due.month, due.day, 23, 59, 59);
}

bool isOverdue(LocalTask task, DateTime now) {
  if (task.isDone) return false;
  final due = effectiveDue(task);
  return due != null && due.isBefore(now);
}

bool isDueOn(LocalTask task, DateTime day) =>
    task.dueAt != null && isSameDay(task.dueAt!, day);

/// Whether the task belongs on [day]'s calendar: due, starting, or spanning it.
bool isScheduledOn(LocalTask task, DateTime day) {
  if (isDueOn(task, day)) return true;
  final start = task.startAt;
  if (start == null) return false;
  if (isSameDay(start, day)) return true;
  final due = task.dueAt;
  final dayStart = dateOnly(day);
  return due != null &&
      dateOnly(start).isBefore(dayStart) &&
      dateOnly(due).isAfter(dayStart);
}

int compareTasks(LocalTask a, LocalTask b) {
  if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
  final dueA = effectiveDue(a);
  final dueB = effectiveDue(b);
  if (dueA != null && dueB != null && dueA != dueB) {
    return dueA.compareTo(dueB);
  }
  if ((dueA == null) != (dueB == null)) return dueA == null ? 1 : -1;
  if (a.priority != b.priority) {
    return b.priority.index.compareTo(a.priority.index);
  }
  return a.createdAt.compareTo(b.createdAt);
}

class TaskBuckets {
  const TaskBuckets({
    required this.overdue,
    required this.today,
    required this.upcoming,
    required this.noDeadline,
    required this.highPriority,
    required this.completed,
  });

  final List<LocalTask> overdue;
  final List<LocalTask> today;
  final List<LocalTask> upcoming;
  final List<LocalTask> noDeadline;
  final List<LocalTask> highPriority;
  final List<LocalTask> completed;

  factory TaskBuckets.from(Iterable<LocalTask> tasks, DateTime now) {
    final sorted = tasks.toList()..sort(compareTasks);
    final open = sorted.where((task) => !task.isDone);
    return TaskBuckets(
      overdue: open.where((task) => isOverdue(task, now)).toList(),
      today: open
          .where((task) => isDueOn(task, now) && !isOverdue(task, now))
          .toList(),
      upcoming: open
          .where((task) =>
              task.dueAt != null &&
              dateOnly(task.dueAt!).isAfter(dateOnly(now)))
          .toList(),
      noDeadline: open.where((task) => task.dueAt == null).toList(),
      highPriority: open
          .where((task) => task.priority.index >= TaskPriority.high.index)
          .toList(),
      completed: sorted.where((task) => task.isDone).toList()
        ..sort((a, b) => (b.completedAt ?? b.createdAt)
            .compareTo(a.completedAt ?? a.createdAt)),
    );
  }
}

class TaskFilter {
  const TaskFilter({
    this.statuses = const {},
    this.priorities = const {},
    this.category,
    this.project,
    this.query = '',
  });

  final Set<TaskStatus> statuses;
  final Set<TaskPriority> priorities;
  final String? category;
  final String? project;
  final String query;

  bool get isEmpty =>
      statuses.isEmpty &&
      priorities.isEmpty &&
      category == null &&
      project == null &&
      query.trim().isEmpty;

  bool matches(LocalTask task) {
    if (statuses.isNotEmpty && !statuses.contains(task.status)) return false;
    if (priorities.isNotEmpty && !priorities.contains(task.priority)) {
      return false;
    }
    if (category != null && task.category != category) return false;
    if (project != null && task.project != project) return false;
    final text = query.trim().toLowerCase();
    if (text.isEmpty) return true;
    return task.title.toLowerCase().contains(text) ||
        task.description.toLowerCase().contains(text) ||
        task.tags.any((tag) => tag.toLowerCase().contains(text));
  }
}

/// Pairs of open tasks whose scheduled time blocks overlap.
List<(LocalTask, LocalTask)> findConflicts(Iterable<LocalTask> tasks) {
  final blocks = tasks
      .where((task) => !task.isDone && task.timeBlock != null)
      .map((task) => (task: task, block: task.timeBlock!))
      .toList()
    ..sort((a, b) => a.block.start.compareTo(b.block.start));
  final conflicts = <(LocalTask, LocalTask)>[];
  for (var i = 0; i < blocks.length; i++) {
    for (var j = i + 1; j < blocks.length; j++) {
      if (!blocks[j].block.start.isBefore(blocks[i].block.end)) break;
      conflicts.add((blocks[i].task, blocks[j].task));
    }
  }
  return conflicts;
}

Set<String> conflictingTaskIds(Iterable<LocalTask> tasks) => {
      for (final (a, b) in findConflicts(tasks)) ...[a.id, b.id],
    };

class PlannedBlock {
  const PlannedBlock({
    required this.task,
    required this.start,
    required this.end,
    required this.fixed,
  });

  final LocalTask task;
  final DateTime start;
  final DateTime end;

  /// True when the task already had a time; false when the planner placed it.
  final bool fixed;
}

/// A suggested order for today's open tasks. Timed tasks keep their times;
/// the rest are placed in free gaps by urgency, using their estimated
/// duration or 30 minutes. Nothing is saved.
List<PlannedBlock> planDay(
  Iterable<LocalTask> tasks,
  DateTime now, {
  int dayEndHour = 21,
}) {
  final candidates = tasks.where((task) =>
      !task.isDone &&
      task.status != TaskStatus.backlog &&
      (task.dueAt == null ||
          !dateOnly(task.dueAt!).isAfter(dateOnly(now)) ||
          (task.startAt != null && isSameDay(task.startAt!, now))));
  final fixed = <PlannedBlock>[];
  final flexible = <LocalTask>[];
  for (final task in candidates) {
    final block = task.timeBlock;
    if (block != null && isSameDay(block.start, now)) {
      fixed.add(PlannedBlock(
          task: task, start: block.start, end: block.end, fixed: true));
    } else if (task.dueHasTime &&
        task.dueAt != null &&
        isSameDay(task.dueAt!, now) &&
        task.dueAt!.isAfter(now)) {
      final minutes = task.durationMinutes ?? 30;
      fixed.add(PlannedBlock(
        task: task,
        start: task.dueAt!.subtract(Duration(minutes: minutes)),
        end: task.dueAt!,
        fixed: true,
      ));
    } else {
      flexible.add(task);
    }
  }
  fixed.sort((a, b) => a.start.compareTo(b.start));
  flexible.sort((a, b) {
    final overdueA = isOverdue(a, now);
    final overdueB = isOverdue(b, now);
    if (overdueA != overdueB) return overdueA ? -1 : 1;
    if (a.priority != b.priority) {
      return b.priority.index.compareTo(a.priority.index);
    }
    return compareTasks(a, b);
  });

  final minute = now.minute;
  var cursor = DateTime(
      now.year, now.month, now.day, now.hour, minute + (15 - minute % 15) % 15);
  final dayEnd = DateTime(now.year, now.month, now.day, dayEndHour);
  final placed = <PlannedBlock>[];
  for (final task in flexible) {
    final length = Duration(minutes: task.durationMinutes ?? 30);
    var moved = true;
    while (moved) {
      moved = false;
      for (final block in fixed) {
        if (cursor.isBefore(block.end) &&
            cursor.add(length).isAfter(block.start)) {
          cursor = block.end;
          moved = true;
        }
      }
    }
    if (cursor.add(length).isAfter(dayEnd)) break;
    placed.add(PlannedBlock(
        task: task, start: cursor, end: cursor.add(length), fixed: false));
    cursor = cursor.add(length);
  }
  return [...fixed.where((block) => block.end.isAfter(now)), ...placed]
    ..sort((a, b) => a.start.compareTo(b.start));
}
