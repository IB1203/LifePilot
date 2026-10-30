import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/clock_ops.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import 'device_security.dart';
import 'home_widget_service.dart';
import 'notification_service.dart';
import 'receipts.dart';
import 'sms_capture.dart';

/// Keeps scheduled notifications in line with the store, handles taps and
/// actions on notifications, and finishes timers that end while the app is
/// open. Scheduling is reconciled on start, after every change, and when the
/// app returns to the foreground (which also picks up time-zone changes).
class ReminderCoordinator with WidgetsBindingObserver {
  ReminderCoordinator(this.store, this.scheduler);

  final LifePilotStore store;
  final ReminderScheduler scheduler;

  /// Destination requested by a notification tap: 'tasks', 'finance', 'clock'.
  final navigation = ValueNotifier<String?>(null);

  /// Short in-app messages, such as a timer finishing.
  final messages = ValueNotifier<String?>(null);

  Timer? _debounce;
  Timer? _watch;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await scheduler.initialize(_onResponse);
    } on Object catch (error) {
      debugPrint('Notifications unavailable: $error');
    }
    store.addListener(_scheduleSoon);
    WidgetsBinding.instance.addObserver(this);
    await _settleClock(announce: false);
    await store.prepareDueRecurring();
    // Only when the data loaded normally; an unreadable data file leaves the
    // store empty, and every receipt would look unreferenced.
    if (store.storageError == null) {
      unawaited(() async {
        // Encrypt first, so cleanup sees the new file names.
        await encryptPlainReceipts(store);
        if (store.storageError != null) return;
        await cleanOrphanReceipts({
          for (final entry in store.entries)
            if (entry.receiptPath != null) entry.receiptPath!,
          for (final draft in store.pending)
            if (draft.entry.receiptPath != null) draft.entry.receiptPath!,
        });
      }());
    }
    await syncNow();
    await _checkSms();
    _watch = Timer.periodic(const Duration(seconds: 1), (_) => _checkClock());
  }

  void dispose() {
    _debounce?.cancel();
    _watch?.cancel();
    store.removeListener(_scheduleSoon);
    WidgetsBinding.instance.removeObserver(this);
    navigation.dispose();
    messages.dispose();
  }

  List<PlannedNotification> currentPlan() => store.notificationPlan();

  Future<void> syncNow() async {
    unawaited(updateHomeWidget(store));
    unawaited(syncSmsCapture(store));
    try {
      await scheduler.sync(currentPlan());
    } on Object catch (error) {
      debugPrint('Notification sync failed: $error');
    }
  }

  /// Asks for notification permission if it has not been granted. Returns
  /// whether notifications can be shown.
  Future<bool> ensurePermission() async {
    final current = await scheduler.status();
    // Nothing to ask for where system notifications are not supported.
    if (!current.supported || current.enabled) return true;
    return scheduler.requestPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(flushClipboardClear());
    unawaited(() async {
      await scheduler.refreshTimeZone();
      await _settleClock(announce: true);
      await store.prepareDueRecurring();
      await syncNow();
      await _checkSms();
    }());
  }

  /// Imports bank SMS captured in the background and follows a tap on the
  /// "new bank message" notification.
  Future<void> _checkSms() async {
    final import = await drainCapturedSms(store);
    final target = await takeLaunchTarget();
    if (target == 'finance') navigation.value = 'finance';
    if (import != null && !import.isEmpty) {
      messages.value = 'Bank messages: ${import.summary()}';
    }
  }

  void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), syncNow);
  }

  void _checkClock() {
    final clock = store.clock;
    final now = store.now();
    final timerDone = clock.timer.isRunning && clock.timer.remaining(now) == 0;
    final focusDone = clock.focus.isRunning && clock.focus.remaining(now) == 0;
    if (timerDone || focusDone) unawaited(_settleClock(announce: true));
  }

  Future<void> _settleClock({required bool announce}) async {
    final label = store.clock.timer.label;
    final timerFinished = await store.settleTimer();
    final focusFinished = await store.settleFocus();
    if (!announce || (!timerFinished && focusFinished == null)) return;
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(HapticFeedback.heavyImpact());
    messages.value = focusFinished != null
        ? (focusFinished == FocusKind.focus
            ? 'Focus session complete. Time for a break.'
            : 'Break finished. Ready to focus?')
        : '${label.isEmpty ? 'Timer' : label} finished.';
  }

  void _onResponse(String payload, String? actionId) {
    final parts = payload.split(':');
    switch (parts.first) {
      case 'task' when parts.length > 1:
        final id = parts.sublist(1).join(':');
        if (actionId == 'done') {
          unawaited(store.setTaskStatus(id, TaskStatus.done));
          messages.value = 'Task marked done.';
        } else if (actionId == 'snooze') {
          unawaited(store.snoozeTask(id, 10));
          messages.value = 'Reminder snoozed for 10 minutes.';
        }
        navigation.value = 'tasks';
      case 'habit':
        navigation.value = 'tasks';
      case 'bill':
        navigation.value = 'finance';
      default:
        navigation.value = 'clock';
    }
  }
}

/// Makes the coordinator available to widgets below the app shell.
class ReminderScope extends InheritedWidget {
  const ReminderScope({
    required this.coordinator,
    required super.child,
    super.key,
  });

  final ReminderCoordinator coordinator;

  static ReminderCoordinator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReminderScope>()?.coordinator;

  @override
  bool updateShouldNotify(ReminderScope oldWidget) =>
      coordinator != oldWidget.coordinator;
}

/// Requests notification permission when a reminder is created, and tells the
/// user if reminders will not appear.
Future<void> ensureReminderPermission(BuildContext context) async {
  final coordinator = ReminderScope.maybeOf(context);
  if (coordinator == null) return;
  final granted = await coordinator.ensurePermission();
  if (granted || !context.mounted) return;
  coordinator.messages.value =
      'Notifications are off, so reminders will only show inside LifePilot. You can allow them in More › Notifications.';
}
