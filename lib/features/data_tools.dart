import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/secure.dart';
import '../services/report_export.dart';
import '../ui/widgets.dart';
import 'lock_screen.dart' show confirmIdentity;

/// Lets the user share a generated file (e.g. to Google Drive or email) or
/// save it to a folder on the phone.
Future<void> deliverFile(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String subject,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(fileName,
                style: Theme.of(sheetContext).textTheme.titleMedium),
            subtitle: Text('${(bytes.length / 1024).toStringAsFixed(1)} KB'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share'),
            subtitle: const Text('Send to Drive, email, chat…'),
            onTap: () => Navigator.pop(sheetContext, 'share'),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Save to phone'),
            subtitle: const Text('Choose a folder such as Downloads'),
            onTap: () => Navigator.pop(sheetContext, 'save'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    if (choice == 'share') {
      final folder = await getTemporaryDirectory();
      final file = File('${folder.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject,
      ));
    } else {
      final uri = await FilePicker.saveFile(
          fileName: fileName, bytes: bytes, mimeType: mimeType);
      if (uri != null && context.mounted) {
        showMessage(context, 'Saved $fileName');
      }
    }
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not export the file: $error', error: true);
    }
  }
}

String _stamp(DateTime now) =>
    '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

Future<void> exportEncryptedBackup(
    BuildContext context, LifePilotStore store) async {
  if (!await confirmIdentity(
          context, store, 'Confirm to back up your records') ||
      !context.mounted) {
    return;
  }
  final first = TextEditingController();
  final second = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final password = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Encrypted backup'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Your records are encrypted with AES-256 using this password. Without the password the backup cannot be restored, and it cannot be recovered.'),
            const SizedBox(height: 12),
            TextFormField(
              controller: first,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
              validator: (value) => value == null || value.length < 8
                  ? 'Use at least 8 characters.'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: second,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat password'),
              validator: (value) =>
                  value != first.text ? 'The passwords do not match.' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, first.text);
            }
          },
          child: const Text('Create backup'),
        ),
      ],
    ),
  );
  first.dispose();
  second.dispose();
  if (password == null || !context.mounted) return;
  final encrypted = await _withProgress(
    context,
    'Encrypting…',
    () => encryptBackup(store.exportJson(), password),
  );
  if (encrypted == null || !context.mounted) return;
  await deliverFile(
    context,
    bytes: Uint8List.fromList(utf8.encode(encrypted)),
    fileName: 'lifepilot-backup-${_stamp(store.now())}.lpbackup',
    mimeType: 'application/octet-stream',
    subject: 'LifePilot encrypted backup',
  );
}

Future<void> restoreBackupFromFile(
    BuildContext context, LifePilotStore store) async {
  final PlatformFile? picked;
  try {
    picked =
        await FilePicker.pickFile(dialogTitle: 'Choose a LifePilot backup');
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not open the file picker: $error',
          error: true);
    }
    return;
  }
  if (picked == null || !context.mounted) return;
  String source;
  try {
    source = utf8.decode(await picked.xFile.readAsBytes());
  } on Object {
    if (context.mounted) {
      showMessage(context, 'That file could not be read as a backup.',
          error: true);
    }
    return;
  }
  if (!context.mounted) return;
  if (isEncryptedBackup(source)) {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Backup password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Decrypt')),
        ],
      ),
    );
    controller.dispose();
    if (password == null || !context.mounted) return;
    final clear = await _withProgress(
        context, 'Decrypting…', () => decryptBackup(source, password));
    if (clear == null || !context.mounted) return;
    source = clear;
  }
  final confirmed = await confirmAction(
    context,
    title: 'Replace local records?',
    message:
        'Restoring replaces everything currently on this device with the backup.',
    confirmLabel: 'Restore',
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
    if (context.mounted) showMessage(context, 'Backup restored.');
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not restore: $error', error: true);
    }
  }
}

Future<void> exportMonthlyReport(
    BuildContext context, LifePilotStore store) async {
  if (!await confirmIdentity(context, store, 'Confirm to export a statement') ||
      !context.mounted) {
    return;
  }
  final now = store.now();
  var month = DateTime(now.year, now.month);
  var format = 'pdf';
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Monthly report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => setDialogState(
                      () => month = DateTime(month.year, month.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(monthLabel(month),
                      textAlign: TextAlign.center,
                      style: Theme.of(dialogContext).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: month.year == now.year && month.month == now.month
                      ? null
                      : () => setDialogState(
                          () => month = DateTime(month.year, month.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pdf', label: Text('PDF')),
                ButtonSegment(value: 'xlsx', label: Text('Excel')),
              ],
              selected: {format},
              onSelectionChanged: (value) =>
                  setDialogState(() => format = value.first),
            ),
            const SizedBox(height: 8),
            const Text(
                'Includes the summary, categories, budgets, bills paid, goals and every transaction for the month.'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create')),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;
  final report = MonthlyReport.from(store, month);
  final bytes = await _withProgress(
    context,
    'Creating report…',
    () async => format == 'pdf'
        ? await buildReportPdf(report)
        : buildReportXlsx(report),
  );
  if (bytes == null || !context.mounted) return;
  await deliverFile(
    context,
    bytes: bytes,
    fileName: '${report.fileStem}.$format',
    mimeType: format == 'pdf'
        ? 'application/pdf'
        : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    subject: report.title,
  );
}

/// Runs [work] behind a small progress dialog. Returns null on error, after
/// telling the user what went wrong.
Future<T?> _withProgress<T>(
    BuildContext context, String label, Future<T> Function() work) async {
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
                dimension: 24, child: CircularProgressIndicator()),
            const SizedBox(width: 16),
            Text(label),
          ],
        ),
      ),
    ),
  );
  try {
    final result = await work();
    navigator.pop();
    return result;
  } on Object catch (error) {
    navigator.pop();
    if (context.mounted) {
      showMessage(
          context,
          error is WrongPasswordException
              ? error.toString()
              : 'Something went wrong: $error',
          error: true);
    }
    return null;
  }
}
