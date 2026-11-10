import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/statement_import.dart';
import '../core/transaction_intelligence.dart';
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
  BankIdentification? bankIdentification;
  try {
    final bytes = await picked.xFile.readAsBytes();
    final table = readStatementTable(picked.name, bytes);
    final saved = findStatementMapping(store.statementMappings, table);
    parsed = parseStatementTable(table, mapping: saved);

    // Identify bank from the header row (first row of the table)
    if (table.isNotEmpty) {
      final headerRow = table.first.join(' ');
      bankIdentification = identifyBankFromStatement(headerRow);
    }
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
  await reviewStatement(context, store, parsed, bankIdentification);
}

/// Shows the summary of [parsed] and, on confirmation, creates the drafts.
Future<void> reviewStatement(
    BuildContext context, LifePilotStore store, StatementParse parsed,
    [BankIdentification? bankIdentification]) async {
  final accounts = store.accounts.where((item) => !item.archived).toList();
  final chosen = await showDialog<_StatementChoice>(
    context: context,
    builder: (_) => _StatementDialog(
        store: store, parsed: parsed, bankIdentification: bankIdentification),
  );
  if (chosen == null || !chosen.ok || !context.mounted) return;
  final account = accounts.where((item) => item.id == chosen.accountId);
  // The dialog already resolved each row for the chosen account.
  final import =
      buildStatementImport(store, chosen.rows, accountId: chosen.accountId);
  await store.applyStatementImport(
    import,
    balanceLabel: account.isEmpty ? 'Bank statement' : account.first.name,
    accountId: chosen.accountId,
    bankName: bankIdentification?.bankName,
    accountHint: bankIdentification?.accountNumberMasked
        ?.replaceAll(RegExp(r'\D'), ''),
    mapping: parsed.mapping,
  );
  if (!context.mounted) return;
  showMessage(
      context,
      import.drafts.isEmpty
          ? 'Nothing new: every transaction is already in LifePilot.'
          : '${import.drafts.length} draft${import.drafts.length == 1 ? '' : 's'} to review under Finance › Recurring.');
}

class _StatementChoice {
  const _StatementChoice({
    required this.ok,
    required this.accountId,
    required this.rows,
  });

  final bool ok;
  final String? accountId;
  final List<StatementRow> rows;
}

class _StatementDialog extends StatefulWidget {
  const _StatementDialog({
    required this.store,
    required this.parsed,
    this.bankIdentification,
  });

  final LifePilotStore store;
  final StatementParse parsed;
  final BankIdentification? bankIdentification;

  @override
  State<_StatementDialog> createState() => _StatementDialogState();
}

class _StatementDialogState extends State<_StatementDialog> {
  String? _accountId;

  /// Rows the user flipped individually, by position.
  final _flipped = <int>{};

  /// When true, every row's credit/debit direction is inverted.
  var _invertAll = false;

  List<StatementRow> get _resolved {
    final selected = widget.store.accountById(_accountId);
    final rows = <StatementRow>[];
    for (var i = 0; i < widget.parsed.rows.length; i++) {
      var row = widget.parsed.rows[i].forAccount(
          creditCard: selected?.isCard ?? false);
      final individuallyFlipped = _flipped.contains(i);
      // Invert all toggles every row; individual flips combine with it.
      if (_invertAll != individuallyFlipped) row = row.flipped();
      rows.add(row);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _resolved;
    final preview = buildStatementImport(widget.store, rows);
    final dates = rows.map((row) => row.date).toList()..sort();
    final accounts =
        widget.store.accounts.where((item) => !item.archived).toList();
    final flagged = widget.parsed.rows.where((row) => row.needsReview).length;
    return AlertDialog(
      title: const Text('Import statement'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
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
              if (widget.bankIdentification != null) ...[
                const SizedBox(height: 12),
                Text('Bank Identification',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (widget.bankIdentification!.bankName != null)
                  Text('Bank: ${widget.bankIdentification!.bankName}',
                      style: Theme.of(context).textTheme.bodyMedium),
                if (widget.bankIdentification!.accountHolder != null)
                  Text('Account Holder: ${widget.bankIdentification!.accountHolder}',
                      style: Theme.of(context).textTheme.bodyMedium),
                if (widget.bankIdentification!.accountNumberMasked != null)
                  Text('Account: ${widget.bankIdentification!.accountNumberMasked}',
                      style: Theme.of(context).textTheme.bodyMedium),
                if (widget.bankIdentification!.ifscCode != null)
                  Text('IFSC: ${widget.bankIdentification!.ifscCode}',
                      style: Theme.of(context).textTheme.bodyMedium),
                if (widget.bankIdentification!.accountType != null)
                  Text('Type: ${widget.bankIdentification!.accountType}',
                      style: Theme.of(context).textTheme.bodyMedium),
                Text('Confidence: ${(widget.bankIdentification!.confidence * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Switch(
                    value: _invertAll,
                    onChanged: (value) => setState(() => _invertAll = value),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Invert all credit/debit directions'),
                  ),
                ],
              ),
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
              if (flagged > 0)
                Text(
                  '$flagged row${flagged == 1 ? '' : 's'} could not be read with confidence. Tap a row to flip credit and debit before importing.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          rows[i].isIncome
                              ? Icons.south_west
                              : Icons.north_east,
                          size: 18,
                          color: rows[i].isIncome
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          '${rows[i].isIncome ? 'Credit' : 'Debit'} · ${formatMoney(rows[i].amountPaise)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        subtitle: Text(rows[i].narration,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: 'Flip credit and debit',
                          icon: const Icon(Icons.swap_vert),
                          onPressed: () => setState(() {
                            if (!_flipped.add(i)) _flipped.remove(i);
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                  'New transactions become drafts you approve. The file is not kept.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
              context,
              _StatementChoice(ok: false, accountId: null, rows: rows)),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: preview.drafts.isEmpty && preview.closing == null
              ? null
              : () => Navigator.pop(context,
                  _StatementChoice(ok: true, accountId: _accountId, rows: rows)),
          child: Text(preview.drafts.isEmpty
              ? 'Update balance'
              : 'Create ${preview.drafts.length} drafts'),
        ),
      ],
    );
  }
}
