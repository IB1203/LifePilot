import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/reminder_plan.dart';
import '../services/device_security.dart';
import '../services/notification_service.dart';
import '../services/reminder_coordinator.dart';
import '../ui/forms.dart';
import '../ui/widgets.dart';
import 'calculator_page.dart';
import 'clock_page.dart';
import 'data_tools.dart';
import 'lock_screen.dart';
import 'onboarding_page.dart' show AccentPicker;
import 'sms_settings_page.dart';
import 'weekly_review_page.dart';

class MorePage extends StatelessWidget {
  const MorePage({required this.store, required this.onOpenClock, super.key});

  final LifePilotStore store;
  final ValueChanged<ClockTab> onOpenClock;

  @override
  Widget build(BuildContext context) {
    final settings = store.settings;
    return ListView(
      padding: pagePadding,
      children: [
        if (store.storageError != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Storage problem'),
              subtitle: Text(store.storageError!),
            ),
          ),
        if (store.migratedFrom != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.upgrade),
              title: const Text('Data upgraded'),
              subtitle: Text(
                  'Your records were upgraded from version ${store.migratedFrom}. A copy of the original file was kept on this device.'),
            ),
          ),
        const SectionHeader(title: 'Tools'),
        CardList(
          indent: 56,
          children: [
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Weekly review'),
              subtitle:
                  const Text('Tasks, focus, habits and money for the week'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AnimatedBuilder(
                    animation: store,
                    builder: (context, _) => WeeklyReviewPage(store: store),
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Calculator'),
              subtitle: const Text('Quick sums, GST-style percentages'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => CalculatorPage(store: store)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Clock and world clock'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenClock(ClockTab.clock),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Stopwatch and timer'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenClock(ClockTab.timer),
            ),
            ListTile(
              leading: const Icon(Icons.self_improvement),
              title: const Text('Focus timer'),
              subtitle: const Text('Pomodoro sessions and statistics'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenClock(ClockTab.focus),
            ),
            ListTile(
              leading: const Icon(Icons.alarm),
              title: const Text('Alarms'),
              subtitle: Text(store.alarms.isEmpty
                  ? 'None set'
                  : '${store.alarms.where((a) => a.enabled).length} on'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenClock(ClockTab.alarms),
            ),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Notes'),
              subtitle: Text('${store.notes.length} saved'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => NotesPage(store: store)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Reminders'),
              subtitle: const Text('Scheduled reminders and history'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => ReminderHistoryPage(store: store)),
              ),
            ),
          ],
        ),
        const SectionHeader(title: 'Notifications'),
        _NotificationSettings(store: store),
        const SectionHeader(title: 'Appearance'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: AppThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('System')),
                    ButtonSegment(
                        value: AppThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light')),
                    ButtonSegment(
                        value: AppThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (value) => store.updateSettings(
                      settings.copyWith(themeMode: value.first)),
                ),
                const SizedBox(height: 16),
                Text('Accent colour',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                AccentPicker(
                  selected: settings.accentColor,
                  onSelected: (color) => store
                      .updateSettings(settings.copyWith(accentColor: color)),
                ),
              ],
            ),
          ),
        ),
        const SectionHeader(title: 'App lock'),
        _SecuritySettings(store: store),
        const SectionHeader(title: 'Display'),
        CardList(
          indent: 56,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.access_time),
              title: const Text('24-hour time'),
              value: settings.use24HourClock,
              onChanged: (value) => store
                  .updateSettings(settings.copyWith(use24HourClock: value)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.timer_10_outlined),
              title: const Text('Show seconds on clocks'),
              value: settings.showSeconds,
              onChanged: (value) =>
                  store.updateSettings(settings.copyWith(showSeconds: value)),
            ),
            ListTile(
              leading: const Icon(Icons.currency_rupee),
              title: const Text('Currency symbol'),
              subtitle: Text(
                  '${settings.currencySymbol} · amounts are stored exactly in minor units'),
              onTap: () => _currency(context),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_paused_outlined),
              title: const Text('Default task reminder'),
              subtitle: Text(settings.defaultReminderMinutes == 0
                  ? 'At the due time'
                  : '${settings.defaultReminderMinutes} minutes before'),
              onTap: () => _defaultReminder(context),
            ),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('Bank SMS and category rules'),
              subtitle: const Text('Live capture, your bank, privacy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => SmsSettingsPage(store: store)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Categories'),
              subtitle: Text('${store.categories.length} available'),
              onTap: () => _showCategories(context, store),
            ),
          ],
        ),
        const SectionHeader(title: 'Reports, backup and data'),
        CardList(
          indent: 56,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Monthly report'),
              subtitle: const Text('PDF or Excel statement to share or save'),
              onTap: () => exportMonthlyReport(context, store),
            ),
            ListTile(
              leading: const Icon(Icons.enhanced_encryption_outlined),
              title: const Text('Encrypted backup'),
              subtitle:
                  const Text('Password-protected file for Drive or Downloads'),
              onTap: () => exportEncryptedBackup(context, store),
            ),
            ListTile(
              leading: const Icon(Icons.restore_page_outlined),
              title: const Text('Restore from file'),
              subtitle: const Text('Encrypted or plain LifePilot backup'),
              onTap: () => restoreBackupFromFile(context, store),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Copy local backup'),
              subtitle: const Text('All records as JSON text'),
              onTap: () => _copyBackup(context, store),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore_outlined),
              title: const Text('Restore backup'),
              subtitle: const Text('Paste a LifePilot JSON backup'),
              onTap: () => _restoreBackup(context, store),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete all local data',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () => _clearData(context, store),
            ),
          ],
        ),
        const SectionHeader(title: 'Privacy'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Your records are stored in a private file on this device and are not sent anywhere. Where the phone supports it, the file and receipt photos are encrypted with a key that never leaves the device. '
              'Android app backup and device-to-device transfer are turned off, so use an encrypted backup file when you change phones. The JSON backup you copy is plain text, not encrypted. '
              'UPI handoffs are never treated as proof of payment, and no PIN, password or OTP is requested or stored.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('LifePilot AI · offline-first',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Future<void> _currency(BuildContext context) async {
    const options = ['₹', 'Rs ', '\$', '€', '£', 'AED '];
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Currency symbol'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option),
              child: Text(option.trim()),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
                'This changes only how amounts are shown. It does not convert existing amounts.'),
          ),
        ],
      ),
    );
    if (picked != null) {
      await store
          .updateSettings(store.settings.copyWith(currencySymbol: picked));
    }
  }

  Future<void> _defaultReminder(BuildContext context) async {
    const options = [0, 5, 10, 15, 30, 60];
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Default reminder for timed tasks'),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option),
              child: Text(
                  option == 0 ? 'At the due time' : '$option minutes before'),
            ),
        ],
      ),
    );
    if (picked != null) {
      await store.updateSettings(
          store.settings.copyWith(defaultReminderMinutes: picked));
    }
  }
}

class _NotificationSettings extends StatefulWidget {
  const _NotificationSettings({required this.store});

  final LifePilotStore store;

  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<_NotificationSettings>
    with WidgetsBindingObserver {
  NotificationStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final coordinator = ReminderScope.maybeOf(context);
    if (coordinator == null) return;
    final status = await coordinator.scheduler.status();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = ReminderScope.maybeOf(context);
    final status = _status;
    if (coordinator == null || status == null || !status.supported) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.notifications_off_outlined),
          title: Text('System notifications are available on Android'),
          subtitle: Text('Reminders still appear inside the app.'),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return CardList(
      indent: 56,
      children: [
        ListTile(
          leading: Icon(
            status.enabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: status.enabled ? null : scheme.error,
          ),
          title: Text(status.enabled
              ? 'Notifications allowed'
              : 'Notifications are off'),
          subtitle: Text(status.enabled
              ? 'Task, bill, timer and alarm reminders can appear.'
              : 'Reminders will not appear outside the app.'),
          trailing: status.enabled
              ? null
              : FilledButton.tonal(
                  onPressed: () async {
                    await coordinator.scheduler.requestPermission();
                    await coordinator.syncNow();
                    await _refresh();
                  },
                  child: const Text('Allow'),
                ),
        ),
        ListTile(
          leading: const Icon(Icons.alarm_on_outlined),
          title:
              Text(status.exactAlarms ? 'Exact timing on' : 'Exact timing off'),
          subtitle: Text(status.exactAlarms
              ? 'Reminders are scheduled for the exact minute.'
              : 'Android may deliver reminders a few minutes late to save battery. Allow “Alarms & reminders” for exact timing.'),
          trailing: status.exactAlarms
              ? null
              : FilledButton.tonal(
                  onPressed: () async {
                    await coordinator.scheduler.requestExactAlarms();
                  },
                  child: const Text('Allow'),
                ),
        ),
        const ListTile(
          leading: Icon(Icons.battery_alert_outlined),
          title: Text('Battery optimisation'),
          subtitle: Text(
              'Some phones stop background alarms for apps under battery optimisation. If reminders arrive late, set LifePilot to “Unrestricted” in the system battery settings. Reminders are restored automatically after a restart.'),
        ),
      ],
    );
  }
}

class NotesPage extends StatelessWidget {
  const NotesPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notes')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showNoteForm(context, store),
          icon: const Icon(Icons.add),
          label: const Text('Note'),
        ),
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final notes = [...store.notes]..sort((a, b) {
                if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                return b.updatedAt.compareTo(a.updatedAt);
              });
            if (notes.isEmpty) {
              return Padding(
                padding: pagePadding,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: EmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    title: 'No notes yet',
                    message: 'Jot down quick thoughts, lists or ideas.',
                    actionLabel: 'New note',
                    onAction: () => showNoteForm(context, store),
                  ),
                ),
              );
            }
            return ListView(
              padding: pagePadding,
              children: [
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        onTap: () => showNoteForm(context, store, note: note),
                        title: Text(note.text,
                            maxLines: 4, overflow: TextOverflow.ellipsis),
                        subtitle:
                            Text('Edited ${formatDateTime(note.updatedAt)}'),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Note options',
                          onSelected: (value) async {
                            if (value == 'pin') {
                              await store.updateNote(
                                  note.copyWith(pinned: !note.pinned));
                            } else if (value == 'delete' &&
                                await confirmAction(context,
                                    title: 'Delete note?',
                                    message: 'This cannot be undone.',
                                    confirmLabel: 'Delete',
                                    destructive: true)) {
                              await store.deleteNote(note.id);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'pin',
                                child:
                                    Text(note.pinned ? 'Unpin' : 'Pin to top')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                          icon: Icon(
                              note.pinned ? Icons.push_pin : Icons.more_vert),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class ReminderHistoryPage extends StatelessWidget {
  const ReminderHistoryPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reminders')),
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final now = store.now();
            final use24h = store.settings.use24HourClock;
            final plan = store.notificationPlan();
            return ListView(
              padding: pagePadding,
              children: [
                const SectionHeader(title: 'Scheduled'),
                if (plan.isEmpty)
                  const EmptyState(
                    compact: true,
                    icon: Icons.notifications_none,
                    title: 'No reminders scheduled',
                    message:
                        'Add a reminder to a task, a bill, a timer or an alarm.',
                  )
                else
                  CardList(
                    children: [
                      for (final item in plan.take(30))
                        ListTile(
                          dense: true,
                          leading: Icon(switch (item.channel) {
                            ReminderChannel.tasks => Icons.task_alt,
                            ReminderChannel.bills => Icons.receipt_outlined,
                            ReminderChannel.timers => Icons.timer_outlined,
                            ReminderChannel.alarms => Icons.alarm,
                          }),
                          title: Text(item.title),
                          subtitle: Text(item.body),
                          trailing: Text(
                            '${friendlyDay(item.at, now)}\n${formatTime(item.at, use24h: use24h)}',
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                const SectionHeader(title: 'History'),
                if (store.reminderLog.isEmpty)
                  const Text(
                      'Completions, snoozes and reschedules will be listed here.')
                else
                  CardList(
                    children: [
                      for (final item in store.reminderLog.take(100))
                        ListTile(
                          dense: true,
                          title: Text(item.title),
                          subtitle: Text(item.action),
                          trailing: Text(
                              formatDateTime(item.at, use24h: use24h),
                              style: Theme.of(context).textTheme.labelSmall),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      );
}

Future<void> _showCategories(BuildContext context, LifePilotStore store) async {
  final controller = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Categories'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: store.categories
                        .map((category) => Chip(label: Text(category)))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Add a category'),
                onSubmitted: (_) async {
                  await store.addCategory(controller.text);
                  controller.clear();
                  setDialogState(() {});
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
          FilledButton(
            onPressed: () async {
              await store.addCategory(controller.text);
              controller.clear();
              setDialogState(() {});
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
}

Future<void> _copyBackup(BuildContext context, LifePilotStore store) async {
  final go = await confirmAction(
    context,
    title: 'Copy an unencrypted backup?',
    message:
        'The copied text contains all your records in readable form, and other apps can read the clipboard. LifePilot clears it after a minute. An encrypted backup file is safer.',
    confirmLabel: 'Copy anyway',
  );
  if (!go || !context.mounted) return;
  if (!await confirmIdentity(context, store, 'Confirm to copy your records') ||
      !context.mounted) {
    return;
  }
  await copySensitive(store.exportJson());
  if (!context.mounted) return;
  showMessage(context,
      'Backup copied. Paste it somewhere private within a minute; the clipboard is then cleared.');
}

Future<void> _restoreBackup(BuildContext context, LifePilotStore store) async {
  final pasted = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return;
  final controller = TextEditingController(text: pasted?.text ?? '');
  final source = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Restore backup'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: controller,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
              hintText: 'Paste the LifePilot JSON backup'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (source == null || !context.mounted) return;
  final confirmed = await confirmAction(
    context,
    title: 'Replace local records?',
    message: 'Restoring replaces all records currently on this device.',
    confirmLabel: 'Replace records',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  if (!await confirmIdentity(
          context, store, 'Confirm to replace your records') ||
      !context.mounted) {
    return;
  }
  try {
    await store.restoreJson(source);
    await clearClipboardIf(source);
    if (!context.mounted) return;
    showMessage(context, 'Backup restored to this device.');
  } on Object catch (error) {
    if (!context.mounted) return;
    showMessage(context, 'Could not restore backup: $error', error: true);
  }
}

Future<void> _clearData(BuildContext context, LifePilotStore store) async {
  final confirmed = await confirmAction(
    context,
    title: 'Delete all local data?',
    message:
        'This permanently removes your transactions, budgets, bills, goals, tasks, notes, alarms, focus history and payment handoff history from this device.',
    confirmLabel: 'Delete all',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  if (await confirmIdentity(
      context, store, 'Confirm to delete all your records')) {
    await store.clearAllData();
  }
}

class _SecuritySettings extends StatelessWidget {
  const _SecuritySettings({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final settings = store.settings;
    return CardList(
      indent: 56,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('Require a PIN'),
          subtitle: Text(settings.lockEnabled
              ? 'Locks after 30 seconds in the background'
              : 'Protect your records with a 4 to 6 digit PIN'),
          value: settings.lockEnabled,
          onChanged: (on) async {
            if (on) {
              final set = await showSetPinDialog(context, store);
              if (set && context.mounted) {
                AppLockScope.maybeOf(context)?.unlock();
                showMessage(context, 'App lock is on.');
              }
              return;
            }
            final confirmed = await confirmAction(context,
                title: 'Turn off the app lock?',
                message:
                    'Anyone with your phone will be able to open LifePilot.',
                confirmLabel: 'Turn off');
            if (!confirmed || !context.mounted) return;
            if (await confirmIdentity(
                context, store, 'Confirm to turn off the app lock',
                always: true)) {
              await store.updateSettings(settings.copyWith(
                  lockEnabled: false, clearPin: true, clearPinLockout: true));
            }
          },
        ),
        if (settings.lockEnabled) ...[
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('What to lock'),
            trailing: DropdownButton<LockScope>(
              value: settings.lockScope,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                    value: LockScope.app, child: Text('Whole app')),
                DropdownMenuItem(
                    value: LockScope.finance, child: Text('Finance only')),
              ],
              onChanged: (value) async {
                if (value == null || value == settings.lockScope) return;
                // Locking less needs the PIN; locking more does not.
                if (value == LockScope.finance &&
                    !await confirmIdentity(
                        context, store, 'Confirm to lock only Finance',
                        always: true)) {
                  return;
                }
                await store
                    .updateSettings(store.settings.copyWith(lockScope: value));
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Unlock with fingerprint or face'),
            subtitle:
                const Text('If your phone supports it. The PIN always works.'),
            value: settings.lockUseBiometrics,
            onChanged: (value) => store
                .updateSettings(settings.copyWith(lockUseBiometrics: value)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.verified_user_outlined),
            title: const Text('Ask for the PIN before sensitive actions'),
            subtitle: const Text(
                'UPI payments, exports, backups, restores and deleting data'),
            value: settings.confirmSensitive,
            onChanged: (value) => _changeProtected(context,
                weaker: !value,
                reason: 'Confirm to stop asking before sensitive actions',
                apply: (current) => current.copyWith(confirmSensitive: value)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.screenshot_outlined),
            title: const Text('Allow screenshots'),
            subtitle: const Text(
                'When off, screenshots, screen recording and the recent-apps preview show a blank screen'),
            value: settings.allowScreenshots,
            onChanged: (value) => _changeProtected(context,
                weaker: value,
                reason: 'Confirm to allow screenshots',
                apply: (current) => current.copyWith(allowScreenshots: value)),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('Change PIN'),
            onTap: () async {
              if (await confirmIdentity(
                      context, store, 'Enter your current PIN',
                      always: true) &&
                  context.mounted) {
                await showSetPinDialog(context, store);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Lock now'),
            onTap: () => AppLockScope.maybeOf(context)?.lockNow(),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.price_check_outlined),
          title: const Text('Large UPI payment warning'),
          subtitle: Text(
              'Extra check for payments of ${formatMoney(settings.largePaymentPaise)} or more'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editLargePayment(context),
        ),
        ListTile(
          leading: Icon(store.encryptedAtRest
              ? Icons.enhanced_encryption_outlined
              : Icons.no_encryption_outlined),
          title: Text(store.encryptedAtRest
              ? 'Records encrypted on this device'
              : 'Device encryption not available'),
          subtitle: Text(store.encryptedAtRest
              ? 'Records and receipt photos are encrypted with a key held in this phone\'s secure key store.'
              : 'Records are kept in the app\'s private storage without LifePilot\'s own encryption.'),
        ),
      ],
    );
  }

  Future<void> _editLargePayment(BuildContext context) async {
    final controller = TextEditingController(
        text: (store.settings.largePaymentPaise ~/ 100).toString());
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Large UPI payment warning'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
              labelText: 'Warn at or above',
              prefixText: '${MoneyFormat.symbol} '),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final rupees = int.tryParse(controller.text);
              if (rupees != null && rupees > 0) {
                Navigator.pop(dialogContext, rupees * 100);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    // Raising the limit means fewer checks, so it needs the PIN.
    await _changeProtected(context,
        weaker: value > store.settings.largePaymentPaise,
        reason: 'Confirm to raise the payment warning limit',
        apply: (current) => current.copyWith(largePaymentPaise: value));
  }

  /// Applies a security setting, asking for the PIN first when the change
  /// makes the app less protected.
  Future<void> _changeProtected(
    BuildContext context, {
    required bool weaker,
    required String reason,
    required AppSettings Function(AppSettings current) apply,
  }) async {
    if (weaker &&
        !await confirmIdentity(context, store, reason, always: true)) {
      return;
    }
    await store.updateSettings(apply(store.settings));
  }
}
