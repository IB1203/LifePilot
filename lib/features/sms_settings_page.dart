import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/bank_sms.dart' show knownBankSenders;
import '../core/local_store.dart';
import '../services/sms_capture.dart';
import '../ui/widgets.dart';
import '../ui/platform.dart';

/// Bank SMS: live capture, privacy, extra bank senders and category rules.
class SmsSettingsPage extends StatelessWidget {
  const SmsSettingsPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final settings = store.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('Bank SMS')),
          body: ListView(
            padding: pagePadding,
            children: [
              const SectionHeader(title: 'Capture'),
              CardList(
                indent: 56,
                children: [
                  if (!isDesktop)
                    SwitchListTile(
                      secondary: const Icon(Icons.mark_email_unread_outlined),
                      title: const Text('Read bank SMS as they arrive'),
                      subtitle: const Text(
                          'Bank and UPI messages become drafts for you to approve, with a notification. Other messages are ignored.'),
                      value: settings.smsCapture,
                      onChanged: (on) => _setCapture(context, on),
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.notes_outlined),
                    title: const Text('Keep full message text'),
                    subtitle: const Text(
                        'Off: drafts keep the message without balances and links.'),
                    value: settings.keepSmsText,
                    onChanged: (value) => store
                        .updateSettings(settings.copyWith(keepSmsText: value)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: const Text('Forget stored message text'),
                    subtitle: const Text(
                        'Removes message text from drafts and the scam list'),
                    onTap: () async {
                      if (await confirmAction(context,
                          title: 'Forget stored message text?',
                          message:
                              'Drafts and recorded entries stay. LifePilot keeps only a one-way fingerprint of each message so it is not imported again.',
                          confirmLabel: 'Forget')) {
                        await store.forgetSmsText();
                        if (context.mounted) {
                          showMessage(context, 'Stored message text removed.');
                        }
                      }
                    },
                  ),
                ],
              ),
              const SectionHeader(title: 'Your bank'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'LifePilot recognises ${knownBankSenders.values.toSet().length} banks by their registered sender names (like HDFCBK). If your bank or cooperative bank is not recognised, add the six letters after the dash in its messages, e.g. "MYCOOP" from "AX-MYCOOP".'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final sender in settings.extraSmsSenders)
                            InputChip(
                              label: Text(sender),
                              onDeleted: () => store.updateSettings(
                                  settings.copyWith(
                                      extraSmsSenders: settings.extraSmsSenders
                                          .where((item) => item != sender)
                                          .toList())),
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: const Text('Add sender'),
                            onPressed: () => _addSender(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SectionHeader(
                title: 'Category rules',
                action: 'Add',
                onAction: () => _addRule(context),
              ),
              if (store.categoryRules.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Rules set the category for drafts automatically, e.g. "zomato" → Food. They apply to bank SMS and UPI drafts before LifePilot\'s own guess.'),
                  ),
                )
              else
                CardList(
                  children: [
                    for (final rule in store.categoryRules)
                      ListTile(
                        leading: const Icon(Icons.rule),
                        title: Text('Contains "${rule.contains}"'),
                        subtitle: Text('→ ${rule.category}'),
                        trailing: IconButton(
                          tooltip: 'Delete rule',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => store.deleteCategoryRule(rule.id),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Text(
                'Messages are read on this phone only and are never sent anywhere. Google Play does not allow SMS access for most finance apps, so a Play Store version would offer only "Paste messages".',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setCapture(BuildContext context, bool on) async {
    if (!on) {
      await store.updateSettings(store.settings.copyWith(smsCapture: false));
      await syncSmsCapture(store);
      return;
    }
    final agreed = await confirmAction(
      context,
      title: 'Read bank SMS as they arrive?',
      message:
          'When a message arrives, LifePilot checks whether it looks like a bank or UPI transaction. Those are kept encrypted on this phone until you open the app, then turned into drafts you approve. Other messages are ignored and not stored. Nothing is sent anywhere. You can turn this off at any time.',
      confirmLabel: 'Turn on',
    );
    if (!agreed || !context.mounted) return;
    final status = await Permission.sms.request();
    if (!context.mounted) return;
    if (!status.isGranted) {
      showMessage(
          context,
          status.isPermanentlyDenied
              ? 'SMS permission is blocked. Allow it in Android settings to use this.'
              : 'SMS permission was not granted.',
          error: true);
      return;
    }
    await store.updateSettings(store.settings.copyWith(smsCapture: true));
    await syncSmsCapture(store);
    if (context.mounted) {
      showMessage(context,
          'On. New bank messages will appear as drafts under Finance › Recurring.');
    }
  }

  Future<void> _addSender(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add bank sender'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(
              labelText: 'Sender ID', hintText: 'e.g. MYCOOP'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    final sender = value?.toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(sender)) {
      if (value != null && context.mounted) {
        showMessage(context, 'A sender ID is 6 letters or digits.',
            error: true);
      }
      return;
    }
    final current = store.settings.extraSmsSenders;
    if (current.contains(sender)) return;
    await store.updateSettings(
        store.settings.copyWith(extraSmsSenders: [...current, sender]));
  }

  Future<void> _addRule(BuildContext context) async {
    final controller = TextEditingController();
    var category = store.categories.first;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New category rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'When the payee or message contains',
                    hintText: 'e.g. zomato'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final item in store.categories)
                    DropdownMenuItem(
                        value: item,
                        child: Text(item, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) =>
                    setDialogState(() => category = value ?? category),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().length >= 2) {
                  Navigator.pop(
                      dialogContext, (controller.text.trim(), category));
                }
              },
              child: const Text('Add rule'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await store.addCategoryRule(result.$1, result.$2);
  }
}
