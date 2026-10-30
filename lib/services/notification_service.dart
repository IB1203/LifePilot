import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/reminder_plan.dart';

typedef NotificationResponseHandler = void Function(
    String payload, String? actionId);

class NotificationStatus {
  const NotificationStatus({
    required this.supported,
    required this.enabled,
    required this.exactAlarms,
  });

  final bool supported;
  final bool enabled;
  final bool exactAlarms;
}

/// Schedules system notifications to match a [PlannedNotification] list.
abstract class ReminderScheduler {
  Future<void> initialize(NotificationResponseHandler onResponse);
  Future<void> sync(List<PlannedNotification> plan);
  Future<bool> requestPermission();
  Future<void> requestExactAlarms();
  Future<NotificationStatus> status();
  Future<void> refreshTimeZone();
}

/// Used in tests and on platforms without notification support.
class NoopReminderScheduler implements ReminderScheduler {
  List<PlannedNotification> lastPlan = const [];

  @override
  Future<void> initialize(NotificationResponseHandler onResponse) async {}

  @override
  Future<void> sync(List<PlannedNotification> plan) async => lastPlan = plan;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> requestExactAlarms() async {}

  @override
  Future<NotificationStatus> status() async => const NotificationStatus(
      supported: false, enabled: false, exactAlarms: false);

  @override
  Future<void> refreshTimeZone() async {}
}

bool _timeZonesLoaded = false;

/// Loads the time-zone database once. Safe to call repeatedly.
void ensureTimeZones() {
  if (_timeZonesLoaded) return;
  tzdata.initializeTimeZones();
  _timeZonesLoaded = true;
}

class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  final Map<int, String> _scheduled = {};
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  static bool get _windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Future<void> initialize(NotificationResponseHandler onResponse) async {
    ensureTimeZones();
    await refreshTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_lifepilot'),
        windows: WindowsInitializationSettings(
          appName: 'LifePilot',
          appUserModelId: 'IB1203.LifePilot',
          guid: '6f1c2b4e-8d3a-4f6b-9c2e-1a5d7e9b3c40',
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) onResponse(payload, response.actionId);
      },
    );
    _ready = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if (launch?.didNotificationLaunchApp == true && response?.payload != null) {
      onResponse(response!.payload!, response.actionId);
    }
  }

  /// Sets the local zone from the device. Times are scheduled as absolute
  /// instants, so one-time reminders stay correct even if this falls back to
  /// UTC; only repeating alarms depend on the zone being right.
  @override
  Future<void> refreshTimeZone() async {
    ensureTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } on Object {
      tz.setLocalLocation(tz.UTC);
    }
    _scheduled.clear();
  }

  @override
  Future<bool> requestPermission() async =>
      _windows || (await _android?.requestNotificationsPermission() ?? false);

  @override
  Future<void> requestExactAlarms() async =>
      _android?.requestExactAlarmsPermission();

  @override
  Future<NotificationStatus> status() async {
    if (_windows) {
      // Windows has no per-app prompt; toasts follow system settings.
      return const NotificationStatus(
          supported: true, enabled: true, exactAlarms: true);
    }
    final android = _android;
    if (android == null) {
      return const NotificationStatus(
          supported: false, enabled: false, exactAlarms: false);
    }
    return NotificationStatus(
      supported: true,
      enabled: await android.areNotificationsEnabled() ?? false,
      exactAlarms: await android.canScheduleExactNotifications() ?? false,
    );
  }

  @override
  Future<void> sync(List<PlannedNotification> plan) async {
    if (!_ready) return;
    final pending =
        (await _plugin.pendingNotificationRequests()).map((r) => r.id).toSet();
    final wanted = {for (final item in plan) item.id: item};
    for (final id in pending.difference(wanted.keys.toSet())) {
      await _plugin.cancel(id: id);
      _scheduled.remove(id);
    }
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    for (final item in plan) {
      final signature =
          '${item.at.toIso8601String()}|${item.title}|${item.body}|${item.repeat.name}';
      if (_scheduled[item.id] == signature && pending.contains(item.id)) {
        continue;
      }
      try {
        await _plugin.zonedSchedule(
          id: item.id,
          scheduledDate: tz.TZDateTime.from(item.at, tz.local),
          title: item.title,
          body: item.body,
          payload: item.payload,
          notificationDetails: NotificationDetails(
            android: _details(item),
            windows: const WindowsNotificationDetails(),
          ),
          androidScheduleMode: !exact
              ? AndroidScheduleMode.inexactAllowWhileIdle
              : item.channel == ReminderChannel.alarms
                  ? AndroidScheduleMode.alarmClock
                  : AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: switch (item.repeat) {
            AlarmRepeat.once => null,
            AlarmRepeat.daily => DateTimeComponents.time,
            AlarmRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
          },
        );
        _scheduled[item.id] = signature;
      } on Object catch (error) {
        debugPrint('Could not schedule ${item.key}: $error');
      }
    }
  }

  AndroidNotificationDetails _details(PlannedNotification item) =>
      switch (item.channel) {
        ReminderChannel.tasks => AndroidNotificationDetails(
            'lifepilot_tasks',
            'Task reminders',
            channelDescription: 'Reminders for tasks you schedule',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            actions: item.taskActions
                ? const [
                    AndroidNotificationAction('snooze', 'Snooze 10 min',
                        showsUserInterface: true),
                    AndroidNotificationAction('done', 'Mark done',
                        showsUserInterface: true),
                  ]
                : null,
          ),
        ReminderChannel.bills => const AndroidNotificationDetails(
            'lifepilot_bills',
            'Bill reminders',
            channelDescription: 'Upcoming bill and subscription due dates',
            // Amounts stay hidden on a secure lock screen.
            visibility: NotificationVisibility.private,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
        ReminderChannel.timers => const AndroidNotificationDetails(
            'lifepilot_timers',
            'Timers',
            channelDescription: 'Countdown and focus timer completion',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.alarm,
          ),
        ReminderChannel.alarms => const AndroidNotificationDetails(
            'lifepilot_alarms',
            'Alarms',
            channelDescription: 'Alarms you set in LifePilot',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
      };
}
