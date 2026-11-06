import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/statement_import.dart';
import '../services/statement_files.dart';
import '../ui/widgets.dart';

/// Picks a CSV or Excel statement, shows what it contains, and turns new
/// rows into drafts for review.
Future<void> importStatement(BuildContext context, LifePilotStore store) async {
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(
        dialogTitle: 'Choose a bank statement (CSV or Excel)');
  } on Object catch (error) {
    if (context.mounted) {
      showMessage(context, 'Could not open the file picker: $error',
          error: true);
    }
    return;
  }
  if (picked == null || !context.mounted) return;
  final StatementParse parsed;
  try {
    final bytes = await picked.xFile.readAsBytes();
    parsed = parseStatementTable(readStatementTable(picked.name, bytes));
  } on FormatException catch (error) {
    if (context.mounted) showMessage(context, error.message, error: true);
    return;
  } on Object {
    if (context.mounted) {
      showMessage(context, 'That file could not be read as a statement.',
          error: true);
    }
    return;
  }
  if (!context.mounted) return;
  if (parsed.rows.isEmpty) {
    showMessage(context, parsed.error ?? 'No transactions found.', error: true);
    return;
  }
  await reviewStatement(context, store, parsed);
}

/// Shows the summary of [parsed] and, on confirmation, creates the drafts.
Future<void> reviewStatement(
    BuildContext context, LifePilotStore store, StatementParse parsed) async {
  final accounts = store.accounts.where((item) => !item.archived).toList();
  final chosen = await showDialog<({bool ok, String? accountId})>(
    context: context,
    builder: (_) => _StatementDialog(store: store, parsed: parsed),
  );
  if (chosen == null || !chosen.ok || !context.mounted) return;
  final import =
      buildStatementImport(store, parsed.rows, accountId: chosen.accountId);
  final account = accounts.where((item) => item.id == chosen.accountId);
  await store.applyStatementImport(import,
      balanceLabel: account.isEmpty ? 'Bank statement' : account.first.name);
  if (!context.mounted) return;
  showMessage(
      context,
      import.drafts.isEmpty
          ? 'Nothing new: every transaction is already in LifePilot.'
          : '${import.drafts.length} draft${import.drafts.length == 1 ? '' : 's'} to review under Finance › Recurring.');
}

class _StatementDialog extends StatefulWidget {
  const _StatementDialog({required this.store, required this.parsed});

  final LifePilotStore store;
  final StatementParse parsed;

  @override
  State<_StatementDialog> createState() => _StatementDialogState();
}

class _StatementDialogState extends State<_StatementDialog> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final rows = widget.parsed.rows;
    final preview = buildStatementImport(widget.store, rows);
    final dates = rows.map((row) => row.date).toList()..sort();
    final accounts =
        widget.store.accounts.where((item) => !item.archived).toList();
    return AlertDialog(
      title: const Text('Import statement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${rows.length} transactions, ${formatDate(dates.first)} to ${formatDate(dates.last)}.'),
            const SizedBox(height: 8),
            Text(
                'New: ${preview.drafts.length} (credited ${formatMoney(preview.creditedPaise)}, debited ${formatMoney(preview.debitedPaise)})'),
            if (preview.duplicates > 0)
              Text('Already recorded: ${preview.duplicates}'),
            if (preview.alreadyImported > 0)
              Text('Imported before: ${preview.alreadyImported}'),
            if (widget.parsed.skipped > 0)
              Text('Rows skipped (not transactions): ${widget.parsed.skipped}'),
            if (preview.closing != null)
              Text(
                  'Closing balance ${formatMoney(preview.closing!.paise)} on ${formatDate(preview.closing!.at)}'),
            if (accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Not set')),
                  for (final account in accounts)
                    DropdownMenuItem(
                        value: account.id, child: Text(account.name)),
                ],
                onChanged: (value) => setState(() => _accountId = value),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
                'New transactions become drafts you approve. The file is not kept.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (ok: false, accountId: null)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: preview.drafts.isEmpty && preview.closing == null
              ? null
              : () => Navigator.pop(context, (ok: true, accountId: _accountId)),
          child: Text(preview.drafts.isEmpty
              ? 'Update balance'
              : 'Create ${preview.drafts.length} drafts'),
        ),
      ],
    );
  }
}
