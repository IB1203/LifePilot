import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../core/task_logic.dart';

const _provider = 'com.lifepilot.app.lifepilot_ai.LifePilotWidgetProvider';

/// Text shown on the home-screen widget, computed from the store.
({String date, String tasks, String next, String money}) widgetContent(
    LifePilotStore store) {
  final now = store.now();
  final buckets = TaskBuckets.from(store.tasks, now);
  final due = buckets.today.length;
  final overdue = buckets.overdue.length;
  final tasks = due == 0 && overdue == 0
      ? 'Nothing due today'
      : [
          if (due > 0) '$due due today',
          if (overdue > 0) '$overdue overdue',
        ].join(' · ');
  final first = buckets.overdue.isNotEmpty
      ? buckets.overdue.first
      : buckets.today.isNotEmpty
          ? buckets.today.first
          : null;
  final reminder = nextReminder(store.notificationPlan());
  final use24h = store.settings.use24HourClock;
  final next = reminder != null
      ? 'Next: ${reminder.title} · ${friendlyDay(reminder.at, now)} ${formatTime(reminder.at, use24h: use24h)}'
      : first == null
          ? ''
          : 'Next: ${first.title}';
  // With the app lock on, amounts stay off the home screen.
  final money = store.settings.lockEnabled
      ? 'Finances hidden while app lock is on'
      : 'Spent ${formatMoney(sumEntries(store.entries, kind: EntryKind.expense, range: monthRange(now)))} in ${shortMonthLabel(now)}';
  return (
    date: '${weekdayName(now)}, ${formatShortDate(now)}',
    tasks: tasks,
    next: next,
    money: money,
  );
}

/// Pushes the latest summary to the Android widget. Errors are ignored: the
/// widget is optional and may not be placed on the home screen.
Future<void> updateHomeWidget(LifePilotStore store) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final content = widgetContent(store);
    await HomeWidget.saveWidgetData<String>('lp_date', content.date);
    await HomeWidget.saveWidgetData<String>('lp_tasks', content.tasks);
    await HomeWidget.saveWidgetData<String>('lp_next', content.next);
    await HomeWidget.saveWidgetData<String>('lp_money', content.money);
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
  } on Object catch (error) {
    debugPrint('Home widget update failed: $error');
  }
}
