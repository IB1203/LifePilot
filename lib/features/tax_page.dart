import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/tax_rules.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

String _rupees(num value) => formatMoney((value * 100).round(), reveal: true);

/// More › Tax and GST: income tax under both regimes and a GST calculator,
/// driven by rules the user can update when a budget changes them.
class TaxPage extends StatefulWidget {
  const TaxPage({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<TaxPage> createState() => _TaxPageState();
}

class _TaxPageState extends State<TaxPage> {
  late String _year = financialYearOf(widget.store.now());
  final _salary = TextEditingController();
  final _other = TextEditingController();
  final _c80 = TextEditingController();
  final _deductions = TextEditingController();
  final _gstAmount = TextEditingController();
  var _age = AgeGroup.below60;
  double? _gstRate;
  var _inclusive = false;
  var _interState = false;

  LifePilotStore get store => widget.store;

  @override
  void dispose() {
    for (final controller in [_salary, _other, _c80, _deductions, _gstAmount]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController controller) =>
      (parseRupeesToPaise(controller.text) ?? 0) ~/ 100;

  List<String> get _years {
    final years = {
      ...builtInTaxRules.keys,
      ...store.taxRuleOverrides.keys,
      financialYearOf(store.now()),
    }.toList()
      ..sort();
    return years.reversed.toList();
  }

  /// Fills income from the last 12 months of records.
  void _fillFromRecords() {
    final now = store.now();
    final range = DateRange(DateTime(now.year - 1, now.month, now.day), now);
    final salary = sumEntries(store.entries,
        kind: EntryKind.income, range: range, category: 'Salary');
    final all = sumEntries(store.entries, kind: EntryKind.income, range: range);
    setState(() {
      _salary.text = salary == 0 ? '' : '${salary ~/ 100}';
      _other.text = all - salary <= 0 ? '' : '${(all - salary) ~/ 100}';
    });
    showMessage(context,
        'Filled from income recorded in the last 12 months. Adjust for the full year.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = store.taxRulesFor(_year);
    final rules = parseTaxRules(active.source);
    _gstRate ??= rules.gstRates
        .firstWhere((item) => item.rate == 18,
            orElse: () => rules.gstRates.first)
        .rate;
    final input = TaxInput(
      salary: _int(_salary),
      otherIncome: _int(_other),
      section80C: _int(_c80),
      otherDeductions: _int(_deductions),
      age: _age,
    );
    final hasIncome = input.salary + input.otherIncome > 0;
    final newTax = computeTax(rules, input, newRegime: true);
    final oldTax = computeTax(rules, input, newRegime: false);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Tax and GST')),
      body: ListView(
        padding: pagePadding,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _year,
            decoration: const InputDecoration(labelText: 'Financial year'),
            items: [
              for (final year in _years)
                DropdownMenuItem(
                  value: year,
                  child: Text(year == financialYearOf(store.now())
                      ? 'FY $year (this year)'
                      : 'FY $year'),
                ),
            ],
            onChanged: (value) => setState(() => _year = value ?? _year),
          ),
          const SizedBox(height: 8),
          if (!active.exact)
            Card(
              color: theme.colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    'No rules for FY $_year yet, so FY ${rules.financialYear} rules are used. If the budget changed anything, import or edit the rules below.'),
              ),
            ),
          Text(
            active.custom
                ? 'Using your rules for FY ${rules.financialYear}${rules.lastVerified.isEmpty ? '' : ' (checked ${rules.lastVerified})'}.'
                : 'Built-in rules for FY ${rules.financialYear}, checked ${rules.lastVerified}.',
            style: muted,
          ),
          const SectionHeader(title: 'Income tax'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(_salary, 'Salary or pension for the year'),
                  _field(_other, 'Other income (interest, rent, freelance)'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _fillFromRecords,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('Fill from my records'),
                    ),
                  ),
                  Text('Old regime only', style: theme.textTheme.labelLarge),
                  _field(_c80,
                      '80C (PPF, ELSS, EPF, LIC…; up to ${_rupees(rules.section80CLimit)})'),
                  _field(_deductions,
                      'Other deductions (80D, HRA, home-loan interest…)'),
                  DropdownButtonFormField<AgeGroup>(
                    isExpanded: true,
                    initialValue: _age,
                    decoration: const InputDecoration(labelText: 'Age'),
                    items: [
                      for (final age in AgeGroup.values)
                        DropdownMenuItem(value: age, child: Text(age.label)),
                    ],
                    onChanged: (value) => setState(() => _age = value ?? _age),
                  ),
                ],
              ),
            ),
          ),
          if (hasIncome) ...[
            const SizedBox(height: 10),
            TileGrid(
              children: [
                StatTile(
                  label: 'New regime',
                  value: _rupees(newTax.total),
                  icon: Icons.fiber_new_outlined,
                  color: newTax.total <= oldTax.total
                      ? AppColors.of(context).income
                      : null,
                  caption: 'Taxable ${_rupees(newTax.taxableIncome)}',
                ),
                StatTile(
                  label: 'Old regime',
                  value: _rupees(oldTax.total),
                  icon: Icons.history,
                  color: oldTax.total < newTax.total
                      ? AppColors.of(context).income
                      : null,
                  caption: 'Taxable ${_rupees(oldTax.taxableIncome)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              newTax.total == oldTax.total
                  ? 'Both regimes come to the same tax.'
                  : newTax.total < oldTax.total
                      ? 'The new regime saves ${_rupees(oldTax.total - newTax.total)} a year.'
                      : 'The old regime saves ${_rupees(newTax.total - oldTax.total)} a year with these deductions.',
              style: theme.textTheme.titleSmall,
            ),
            for (final (label, result) in [
              ('New regime working', newTax),
              ('Old regime working', oldTax),
            ])
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(label),
                children: [
                  for (final step in result.steps)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(step, style: theme.textTheme.bodySmall),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('= ${_rupees(result.total)}',
                        style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
            Text(
                'An estimate from the rules above, for individuals. Not tax advice; special incomes such as capital gains are taxed differently.',
                style: muted),
          ],
          const SectionHeader(title: 'GST calculator'),
          _GstCard(
            rules: rules,
            amount: _gstAmount,
            rate: _gstRate!,
            inclusive: _inclusive,
            interState: _interState,
            onRate: (value) => setState(() => _gstRate = value),
            onInclusive: (value) => setState(() => _inclusive = value),
            onInterState: (value) => setState(() => _interState = value),
            onChanged: () => setState(() {}),
          ),
          const SectionHeader(title: 'Rules'),
          CardList(
            indent: 56,
            children: [
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: const Text('Import a rules file'),
                subtitle: const Text(
                    'JSON in the same format. You see every change before it is applied.'),
                onTap: () => _import(active.source),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text('Edit FY ${rules.financialYear} rules'),
                onTap: () => _edit(active.source),
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy rules as JSON'),
                subtitle:
                    const Text('To share, or as a template for next year'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(
                      text: const JsonEncoder.withIndent('  ')
                          .convert(jsonDecode(active.source))));
                  if (context.mounted) showMessage(context, 'Rules copied.');
                },
              ),
              if (active.custom)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Reset to built-in rules'),
                  onTap: () async {
                    if (await confirmAction(context,
                        title: 'Reset FY ${rules.financialYear} rules?',
                        message: 'Your changes for this year are removed.',
                        confirmLabel: 'Reset')) {
                      await store.resetTaxRules(rules.financialYear);
                      setState(() {});
                    }
                  },
                ),
              if (rules.source.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Source'),
                  subtitle: Text('${rules.source}\n${rules.notes}'),
                  isThreeLine: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, prefixText: '₹ '),
          onChanged: (_) => setState(() {}),
        ),
      );

  Future<void> _import(String current) async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(dialogTitle: 'Choose a rules file');
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, 'Could not open the file picker: $error',
            error: true);
      }
      return;
    }
    if (picked == null || !mounted) return;
    final text =
        utf8.decode(await picked.xFile.readAsBytes(), allowMalformed: true);
    if (mounted) await _review(text);
  }

  Future<void> _edit(String current) async {
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _RulesEditor(
          initial:
              const JsonEncoder.withIndent('  ').convert(jsonDecode(current))),
    );
    if (edited != null && mounted) await _review(edited);
  }

  /// Validates [text], shows what changes against the rules now in use for
  /// that year, and saves on confirmation.
  Future<void> _review(String text) async {
    final TaxRules rules;
    try {
      rules = parseTaxRules(text);
    } on FormatException catch (error) {
      showMessage(context, 'Not applied: ${error.message}', error: true);
      return;
    }
    final before = store.taxRulesFor(rules.financialYear).source;
    final changes = diffTaxRules(before, text);
    if (changes.isEmpty) {
      showMessage(context, 'No changes for FY ${rules.financialYear}.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Apply FY ${rules.financialYear} rules?'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                  '${changes.length} change${changes.length == 1 ? '' : 's'}:'),
              const SizedBox(height: 8),
              for (final change in changes)
                Text('• $change',
                    style: Theme.of(dialogContext).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await store.saveTaxRules(text);
    if (!mounted) return;
    setState(() => _year = rules.financialYear);
    showMessage(context, 'FY ${rules.financialYear} rules updated.');
  }
}

class _RulesEditor extends StatefulWidget {
  const _RulesEditor({required this.initial});

  final String initial;

  @override
  State<_RulesEditor> createState() => _RulesEditorState();
}

class _RulesEditorState extends State<_RulesEditor> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit rules'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: _text,
            maxLines: 18,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(errorText: _error, errorMaxLines: 3),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              try {
                parseTaxRules(_text.text);
              } on FormatException catch (error) {
                setState(() => _error = error.message);
                return;
              }
              Navigator.pop(context, _text.text);
            },
            child: const Text('Review changes'),
          ),
        ],
      );
}

class _GstCard extends StatelessWidget {
  const _GstCard({
    required this.rules,
    required this.amount,
    required this.rate,
    required this.inclusive,
    required this.interState,
    required this.onRate,
    required this.onInclusive,
    required this.onInterState,
    required this.onChanged,
  });

  final TaxRules rules;
  final TextEditingController amount;
  final double rate;
  final bool inclusive;
  final bool interState;
  final ValueChanged<double> onRate;
  final ValueChanged<bool> onInclusive;
  final ValueChanged<bool> onInterState;
  final VoidCallback onChanged;

  String _pct(double value) =>
      value == value.roundToDouble() ? '${value.round()}%' : '$value%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = double.tryParse(amount.text.replaceAll(',', '').trim());
    final result =
        value == null ? null : gst(value, rate, inclusive: inclusive);
    final label = rules.gstRates
        .where((item) => item.rate == rate)
        .map((item) => item.label)
        .firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    inclusive ? 'Price including GST' : 'Price before GST',
                prefixText: '₹ ',
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final item in rules.gstRates)
                  ChoiceChip(
                    label: Text(_pct(item.rate)),
                    selected: item.rate == rate,
                    onSelected: (_) => onRate(item.rate),
                  ),
              ],
            ),
            if (label != null) Text(label, style: theme.textTheme.bodySmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Price already includes GST'),
              value: inclusive,
              onChanged: onInclusive,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inter-state (IGST)'),
              value: interState,
              onChanged: onInterState,
            ),
            if (result != null) ...[
              const Divider(),
              _row('Before GST', _rupees(result.base)),
              if (interState)
                _row('IGST ${_pct(rate)}', _rupees(result.gst))
              else ...[
                _row('CGST ${_pct(rate / 2)}', _rupees(result.cgst)),
                _row('SGST ${_pct(rate / 2)}', _rupees(result.sgst)),
              ],
              _row('Total', _rupees(result.total), bold: true),
            ],
            const SizedBox(height: 6),
            Text(
                'Rates from ${rules.gstEffectiveFrom.isEmpty ? 'the rules file' : 'rules effective ${rules.gstEffectiveFrom}'}. Check the rate for a specific item with the seller or a tax adviser.',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
          ],
        ),
      );
}
