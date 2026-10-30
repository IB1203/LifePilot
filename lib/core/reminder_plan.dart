import 'formatters.dart';
import 'models.dart';

enum ReminderChannel { tasks, bills, timers, alarms }

enum AlarmRepeat { once, daily, weekly }

/// A notification that should exist. The scheduler makes the system's
/// pending notifications match a list of these, which prevents duplicates and
/// handles cancellation and rescheduling in one place.
class PlannedNotification {
  const PlannedNotification({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    required this.channel,
    required this.payload,
    this.repeat = AlarmRepeat.once,
    this.taskActions = false,
  });

  /// Stable identity, e.g. `task:<id>:<due>:<offset>`.
  final String key;
  final DateTime at;
  final String title;
  final String body;
  final ReminderChannel channel;
  final String payload;
  final AlarmRepeat repeat;

  /// Whether to show Snooze / Done actions.
  final bool taskActions;

  /// 31-bit FNV-1a hash of [key], used as the platform notification id.
  int get id {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}

/// Default time for reminders on tasks and bills that only have a date.
const defaultReminderHour = 9;

/// Android limits each app to 500 pending alarms; stay well below it.
const maxPlannedNotifications = 60;

List<PlannedNotification> buildNotificationPlan({
  required List<LocalTask> tasks,
  required List<Bill> bills,
  required List<Alarm> alarms,
  required ClockState clock,
  required DateTime now,
  List<Habit> habits = const [],
  bool use24h = false,
  Duration horizon = const Duration(days: 30),
}) {
  final until = now.add(horizon);
  final fixed = <PlannedNotification>[];
  final dated = <PlannedNotification>[];

  for (final alarm in alarms.where((alarm) => alarm.enabled)) {
    final title = alarm.label.isEmpty ? 'Alarm' : alarm.label;
    final body = formatTime(DateTime(2000, 1, 1, alarm.hour, alarm.minute),
        use24h: use24h);
    if (alarm.weekdays.isEmpty) {
      fixed.add(PlannedNotification(
        key: 'alarm:${alarm.id}',
        at: alarm.nextFire(now),
        title: title,
        body: body,
        channel: ReminderChannel.alarms,
        payload: 'alarm:${alarm.id}',
        repeat: AlarmRepeat.daily,
      ));
    } else {
      for (final weekday in alarm.weekdays.toSet()) {
        fixed.add(PlannedNotification(
          key: 'alarm:${alarm.id}:$weekday',
          at: alarm.copyWith(weekdays: [weekday]).nextFire(now),
          title: title,
          body: '$body · every ${weekdayShort(weekday)}',
          channel: ReminderChannel.alarms,
          payload: 'alarm:${alarm.id}',
          repeat: AlarmRepeat.weekly,
        ));
      }
    }
  }

  void addTimer(String key, CountdownState state, String title, String body) {
    final end = state.endsAt;
    if (end == null || !end.isAfter(now)) return;
    fixed.add(PlannedNotification(
      key: key,
      at: end,
      title: title,
      body: body,
      channel: ReminderChannel.timers,
      payload: key,
    ));
  }

  addTimer(
    'timer',
    clock.timer,
    clock.timer.label.isEmpty
        ? 'Timer finished'
        : '${clock.timer.label} timer finished',
    'Your ${formatDuration(Duration(milliseconds: clock.timer.totalMs))} timer is done.',
  );
  addTimer(
    'focus',
    clock.focus,
    clock.focus.kind == FocusKind.focus
        ? 'Focus session complete'
        : 'Break is over',
    clock.focus.kind == FocusKind.focus
        ? 'Time for a break${clock.focus.label.isEmpty ? '' : ' from ${clock.focus.label}'}.'
        : 'Ready for the next focus session?',
  );

  for (final task in tasks) {
    if (task.isDone) continue;
    final snooze = task.snoozedUntil;
    if (snooze != null && snooze.isAfter(now)) {
      dated.add(PlannedNotification(
        key: 'task:${task.id}:snooze:${snooze.toIso8601String()}',
        at: snooze,
        title: task.title,
        body: 'Snoozed reminder',
        channel: ReminderChannel.tasks,
        payload: 'task:${task.id}',
        taskActions: true,
      ));
    }
    final due = task.dueAt;
    if (due == null || task.reminderOffsets.isEmpty) continue;
    // A recurring task keeps one record; remind for its upcoming occurrences.
    var occurrence = task.dueHasTime
        ? due
        : DateTime(due.year, due.month, due.day, defaultReminderHour);
    for (var count = 0; count < 8 && !occurrence.isAfter(until); count++) {
      for (final offset in task.reminderOffsets.toSet()) {
        final at = occurrence.subtract(Duration(minutes: offset));
        if (!at.isAfter(now) || at.isAfter(until)) continue;
        final when = task.dueHasTime
            ? formatTime(occurrence, use24h: use24h)
            : friendlyDay(occurrence, at);
        dated.add(PlannedNotification(
          key: 'task:${task.id}:${occurrence.toIso8601String()}:$offset',
          at: at,
          title: task.title,
          body: offset == 0
              ? (task.dueHasTime ? 'Due now ($when)' : 'Due today')
              : 'Due ${task.dueHasTime ? 'at $when' : when.toLowerCase()} · in ${formatDuration(Duration(minutes: offset))}',
          channel: ReminderChannel.tasks,
          payload: 'task:${task.id}',
          taskActions: true,
        ));
      }
      final next = task.recurrence.next(occurrence);
      if (next == null) break;
      occurrence = next;
    }
  }

  for (final habit in habits) {
    final minutes = habit.reminderMinutes;
    if (habit.archived || minutes == null) continue;
    for (var offset = 0; offset < 7; offset++) {
      final day = DateTime(now.year, now.month, now.day + offset);
      if (!habit.appliesOn(day) || habit.doneOn(day)) continue;
      final at =
          DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
      if (!at.isAfter(now)) continue;
      dated.add(PlannedNotification(
        key: 'habit:${habit.id}:${day.toIso8601String()}',
        at: at,
        title: habit.name,
        body: 'Habit check-in · tap to mark it done',
        channel: ReminderChannel.tasks,
        payload: 'habit:${habit.id}',
      ));
    }
  }

  for (final bill in bills.where((bill) => bill.active)) {
    final due = DateTime(bill.nextDueAt.year, bill.nextDueAt.month,
        bill.nextDueAt.day, defaultReminderHour);
    final times = <(String, DateTime, String)>[
      if (bill.remindDaysBefore > 0)
        (
          'before',
          due.subtract(Duration(days: bill.remindDaysBefore)),
          'Due ${formatShortDate(due)} · ${formatMoney(bill.amountPaise)}',
        ),
      ('due', due, 'Due today · ${formatMoney(bill.amountPaise)}'),
    ];
    for (final (label, at, body) in times) {
      if (!at.isAfter(now) || at.isAfter(until)) continue;
      dated.add(PlannedNotification(
        key: 'bill:${bill.id}:${due.toIso8601String()}:$label',
        at: at,
        title: bill.name,
        body: body,
        channel: ReminderChannel.bills,
        payload: 'bill:${bill.id}',
      ));
    }
  }

  dated.sort((a, b) => a.at.compareTo(b.at));
  final room = maxPlannedNotifications - fixed.length;
  final plan = <int, PlannedNotification>{};
  for (final item in [...fixed, ...dated.take(room < 0 ? 0 : room)]) {
    plan.putIfAbsent(item.id, () => item);
  }
  return plan.values.toList()..sort((a, b) => a.at.compareTo(b.at));
}

/// The next task, bill, or timer reminder after [now], if any.
PlannedNotification? nextReminder(List<PlannedNotification> plan) {
  for (final item in plan) {
    if (item.channel != ReminderChannel.alarms) return item;
  }
  return null;
}
