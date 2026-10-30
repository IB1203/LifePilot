import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/core/reminder_plan.dart';
import 'package:lifepilot_ai/core/task_logic.dart';

void main() {
  group('recurrence', () {
    test('daily keeps wall-clock time', () {
      const rule = Recurrence(Repeat.daily);
      expect(rule.next(DateTime(2026, 3, 28, 19)), DateTime(2026, 3, 29, 19));
    });

    test('weekdays skip the weekend', () {
      const rule = Recurrence(Repeat.weekdays);
      expect(rule.next(DateTime(2026, 10, 30, 9)), DateTime(2026, 11, 2, 9));
    });

    test('every N days and yearly leap day', () {
      expect(
          const Recurrence(Repeat.everyNDays, interval: 3)
              .next(DateTime(2026, 10, 30)),
          DateTime(2026, 11, 2));
      expect(const Recurrence(Repeat.yearly).next(DateTime(2028, 2, 29)),
          DateTime(2029, 2, 28));
    });
  });

  group('task store operations', () {
    late DateTime now;
    late LifePilotStore store;

    setUp(() {
      now = DateTime(2026, 10, 29, 10);
      store = LifePilotStore.inMemory(clock: () => now);
    });

    test('creates and completes a task', () async {
      final task = await store.addTask(
        title: '  Finish report ',
        project: 'Work',
        dueAt: DateTime(2026, 10, 30, 17),
        dueHasTime: true,
        priority: TaskPriority.high,
        subtasks: ['Draft', ' ', 'Review'],
        reminderOffsets: [15],
      );
      expect(task.title, 'Finish report');
      expect(task.subtasks, hasLength(2));
      await store.setTaskStatus(task.id, TaskStatus.done);
      final done = store.taskById(task.id)!;
      expect(done.isDone, isTrue);
      expect(done.completedAt, now);
      expect(store.reminderLog.first.action, 'Completed');
    });

    test('completing a recurring task advances to the next occurrence',
        () async {
      final task = await store.addTask(
        title: 'Water plants',
        project: '',
        dueAt: DateTime(2026, 10, 29, 8),
        dueHasTime: true,
        recurrence: const Recurrence(Repeat.daily),
        subtasks: ['Balcony'],
      );
      await store.toggleSubtask(task.id, task.subtasks.single.id);
      await store.setTaskStatus(task.id, TaskStatus.done);
      final next = store.taskById(task.id)!;
      expect(next.isDone, isFalse);
      expect(next.dueAt, DateTime(2026, 10, 30, 8));
      expect(next.completionHistory, [now]);
      expect(next.subtasks.single.done, isFalse);
    });

    test('a long-overdue recurring task skips to today or later', () async {
      final task = await store.addTask(
        title: 'Log weight',
        project: '',
        dueAt: DateTime(2026, 10, 20, 21),
        dueHasTime: true,
        recurrence: const Recurrence(Repeat.daily),
      );
      await store.setTaskStatus(task.id, TaskStatus.done);
      expect(store.taskById(task.id)!.dueAt, DateTime(2026, 10, 29, 21));
    });

    test('snooze and reschedule are logged', () async {
      final task = await store.addTask(
          title: 'Call bank',
          project: '',
          dueAt: DateTime(2026, 10, 29, 11),
          dueHasTime: true,
          reminderOffsets: [0]);
      await store.snoozeTask(task.id, 10);
      expect(store.taskById(task.id)!.snoozedUntil,
          now.add(const Duration(minutes: 10)));
      await store.rescheduleTask(task.id, DateTime(2026, 10, 31, 9),
          hasTime: true);
      final moved = store.taskById(task.id)!;
      expect(moved.dueAt, DateTime(2026, 10, 31, 9));
      expect(moved.snoozedUntil, isNull);
      expect(store.reminderLog.first.action, startsWith('Rescheduled'));
    });
  });

  group('task buckets and conflicts', () {
    final now = DateTime(2026, 10, 29, 12);
    LocalTask task(String id,
            {DateTime? due,
            bool time = false,
            DateTime? start,
            int? minutes,
            TaskPriority priority = TaskPriority.medium,
            TaskStatus status = TaskStatus.todo}) =>
        LocalTask(
          id: id,
          title: id,
          project: '',
          createdAt: DateTime(2026, 10, 1),
          dueAt: due,
          dueHasTime: time,
          startAt: start,
          durationMinutes: minutes,
          priority: priority,
          status: status,
        );

    test('buckets classify overdue, today, upcoming, no deadline, done', () {
      final buckets = TaskBuckets.from([
        task('late', due: DateTime(2026, 10, 28)),
        task('earlier-today', due: DateTime(2026, 10, 29, 9), time: true),
        task('today', due: DateTime(2026, 10, 29)),
        task('later', due: DateTime(2026, 11, 2)),
        task('someday', priority: TaskPriority.urgent),
        task('done', status: TaskStatus.done),
      ], now);
      expect(buckets.overdue.map((t) => t.id), ['late', 'earlier-today']);
      expect(buckets.today.map((t) => t.id), ['today']);
      expect(buckets.upcoming.map((t) => t.id), ['later']);
      expect(buckets.noDeadline.map((t) => t.id), ['someday']);
      expect(buckets.highPriority.map((t) => t.id), ['someday']);
      expect(buckets.completed.map((t) => t.id), ['done']);
    });

    test('overlapping time blocks are conflicts', () {
      final conflicts = findConflicts([
        task('a', start: DateTime(2026, 10, 30, 9), minutes: 60),
        task('b', start: DateTime(2026, 10, 30, 9, 30), minutes: 30),
        task('c', start: DateTime(2026, 10, 30, 10), minutes: 30),
      ]);
      expect(conflicts.map((pair) => '${pair.$1.id}-${pair.$2.id}'), ['a-b']);
    });

    test('day plan keeps fixed tasks and fills gaps by priority', () {
      final plan = planDay([
        task('meeting', start: DateTime(2026, 10, 29, 12, 30), minutes: 60),
        task('low', priority: TaskPriority.low, minutes: 30),
        task('urgent', priority: TaskPriority.urgent, minutes: 30),
      ], now);
      expect(plan.map((block) => block.task.id), ['urgent', 'meeting', 'low']);
      expect(plan.first.start, DateTime(2026, 10, 29, 12));
      expect(plan.last.start, DateTime(2026, 10, 29, 13, 30));
    });
  });

  group('notification plan', () {
    final now = DateTime(2026, 10, 29, 10);

    LocalTask reminderTask(
            {List<int> offsets = const [0, 15],
            TaskStatus status = TaskStatus.todo,
            Recurrence recurrence = Recurrence.none}) =>
        LocalTask(
          id: 't1',
          title: 'Pay electricity bill',
          project: '',
          createdAt: now,
          dueAt: DateTime(2026, 10, 30, 19),
          dueHasTime: true,
          reminderOffsets: offsets,
          status: status,
          recurrence: recurrence,
        );

    List<PlannedNotification> plan(List<LocalTask> tasks,
            {List<Alarm> alarms = const [],
            ClockState clock = const ClockState(),
            List<Bill> bills = const []}) =>
        buildNotificationPlan(
            tasks: tasks, bills: bills, alarms: alarms, clock: clock, now: now);

    test('schedules each reminder offset once with stable ids', () {
      final first = plan([reminderTask()]);
      expect(first.map((item) => item.at), [
        DateTime(2026, 10, 30, 18, 45),
        DateTime(2026, 10, 30, 19),
      ]);
      final second = plan([reminderTask()]);
      expect(second.map((item) => item.id), first.map((item) => item.id));
      expect(first.map((item) => item.id).toSet(), hasLength(2));
      expect(first.every((item) => item.taskActions), isTrue);
    });

    test('completed tasks and cancelled reminders produce nothing', () {
      expect(plan([reminderTask(status: TaskStatus.done)]), isEmpty);
      expect(plan([reminderTask(offsets: const [])]), isEmpty);
    });

    test('past reminders are skipped and recurring ones expand', () {
      final daily = plan([
        reminderTask(
            offsets: const [0], recurrence: const Recurrence(Repeat.daily))
      ]);
      expect(daily, hasLength(8));
      expect(daily[1].at, DateTime(2026, 10, 31, 19));
    });

    test('alarms, timers, bills and snoozes are included', () {
      final result = plan(
        [
          reminderTask(offsets: const [])
              .copyWith(snoozedUntil: now.add(const Duration(minutes: 10)))
        ],
        alarms: const [
          Alarm(id: 'a', hour: 6, minute: 30, weekdays: [1, 3]),
        ],
        clock: ClockState(
          timer: CountdownState(
              label: 'Tea',
              totalMs: 300000,
              endsAt: now.add(const Duration(minutes: 5))),
        ),
        bills: [
          Bill(
            id: 'b',
            name: 'Rent',
            kind: BillKind.rent,
            amountPaise: 100,
            nextDueAt: DateTime(2026, 11, 1),
          ),
        ],
      );
      final keys = result.map((item) => item.key).toList();
      expect(keys.where((key) => key.startsWith('alarm:a:')), hasLength(2));
      expect(keys, contains('timer'));
      expect(keys.where((key) => key.startsWith('bill:b')), hasLength(2));
      expect(keys.where((key) => key.contains(':snooze:')), hasLength(1));
      final monday = result.firstWhere((item) => item.key == 'alarm:a:1');
      expect(monday.at, DateTime(2026, 11, 2, 6, 30));
      expect(monday.repeat, AlarmRepeat.weekly);
    });

    test('never exceeds the platform-safe limit', () {
      final many = [
        for (var i = 0; i < 100; i++) reminderTask().copyWith(title: 'Task $i'),
      ].indexed.map((pair) => LocalTask.fromJson({
            ...pair.$2.toJson(),
            'id': 'task-${pair.$1}',
          }));
      expect(plan(many.toList()).length,
          lessThanOrEqualTo(maxPlannedNotifications));
    });
  });

  group('persistence and migration', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('lifepilot_test');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('data survives a restart', () async {
      final store = await LifePilotStore.load(directory: directory);
      await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 25000,
        category: 'Food',
        title: 'Lunch',
        occurredAt: DateTime(2026, 10, 29, 13),
      );
      final task = await store.addTask(title: 'Persist me', project: 'Home');
      await store.updateSettings(store.settings.copyWith(use24HourClock: true));

      final reloaded = await LifePilotStore.load(directory: directory);
      expect(reloaded.storageError, isNull);
      expect(reloaded.entries.single.amountPaise, 25000);
      expect(reloaded.taskById(task.id)!.project, 'Home');
      expect(reloaded.settings.use24HourClock, isTrue);
    });

    test('editing updates the same record', () async {
      final store = await LifePilotStore.load(directory: directory);
      final entry = await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 1000,
        category: 'Food',
        title: 'Tea',
        occurredAt: DateTime(2026, 10, 29),
      );
      await store
          .updateEntry(entry.copyWith(amountPaise: 2000, title: 'Tea x2'));
      final reloaded = await LifePilotStore.load(directory: directory);
      expect(reloaded.entries, hasLength(1));
      expect(reloaded.entries.single.title, 'Tea x2');
      expect(reloaded.entries.single.amountPaise, 2000);
    });

    test('version 1 data is migrated and the original kept', () async {
      final v1 = {
        'format': 'lifepilot-backup',
        'version': 1,
        'entries': [
          {
            'id': 'e1',
            'kind': 'expense',
            'amountPaise': 32000,
            'category': 'Food',
            'title': 'Groceries',
            'occurredAt': '2026-10-02T10:00:00.000',
            'note': '',
            'paymentMethod': 'UPI',
          },
        ],
        'budgets': [
          {'category': 'Food', 'limitPaise': 500000},
        ],
        'goals': [
          {
            'id': 'g1',
            'name': 'Trip',
            'targetPaise': 1000000,
            'savedPaise': 250000,
            'createdAt': '2026-05-01T00:00:00.000',
          },
        ],
        'tasks': [
          {
            'id': 't1',
            'title': 'Old task',
            'project': 'Home',
            'createdAt': '2026-09-01T00:00:00.000',
            'dueAt': '2026-10-01T00:00:00.000',
            'isDone': true,
          },
        ],
        'handoffs': [],
        'categories': ['Pets', 'Food'],
      };
      final file = File('${directory.path}/lifepilot.local.v1.json');
      await file.writeAsString(jsonEncode(v1));

      final store = await LifePilotStore.load(directory: directory);
      expect(store.storageError, isNull);
      expect(store.migratedFrom, 1);
      expect(store.entries.single.paymentMethod, 'UPI');
      expect(store.budgets.single.period, BudgetPeriod.monthly);
      expect(store.goals.single.savedPaise, 250000);
      expect(store.tasks.single.status, TaskStatus.done);
      expect(store.categories, contains('Pets'));

      final backup =
          File('${directory.path}/lifepilot.local.v1.v1.backup.json');
      expect(await backup.exists(), isTrue);
      expect(jsonDecode(await file.readAsString())['version'], 3);

      final again = await LifePilotStore.load(directory: directory);
      expect(again.migratedFrom, isNull);
      expect(again.goals.single.savedPaise, 250000);
    });

    test('unreadable data is left untouched and saving is disabled', () async {
      final file = File('${directory.path}/lifepilot.local.v1.json');
      await file.writeAsString('{"format":"lifepilot-backup","version":99}');
      final store = await LifePilotStore.load(directory: directory);
      expect(store.storageError, isNotNull);
      await store.addTask(title: 'Not saved', project: '');
      expect(await file.readAsString(), contains('"version":99'));
    });

    test('restore rejects malformed backups without changing data', () async {
      final store = LifePilotStore.inMemory();
      await store.addTask(title: 'Keep me', project: '');
      await expectLater(
        store.restoreJson(jsonEncode({
          'format': 'lifepilot-backup',
          'version': 2,
          'entries': [
            {'id': 'x', 'kind': 'expense', 'amountPaise': -1},
          ],
        })),
        throwsA(anything),
      );
      expect(store.tasks.single.title, 'Keep me');
    });
  });
}
