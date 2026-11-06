import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/investments.dart';
import '../core/local_store.dart';
import '../ui/charts.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Finance › Investments: holdings with values the user enters, deposit
/// maturity, returns, allocation and the SIP calendar.
class InvestmentsTab extends StatelessWidget {
  const InvestmentsTab({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final now = store.now();
    final book = portfolio(store.investments, now);
    final sips = sipDates(
        store.investments, now, DateTime(now.year, now.month, now.day + 30));
    final monthlySip = store.investments
        .where((item) => !item.closed)
        .fold(0, (sum, item) => sum + item.sipPaise);
    final gain = book.gainPaise;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
          title: 'Investments',
          action: 'Add',
          onAction: () => showInvestmentForm(context, store),
        ),
        if (book.lines.isEmpty)
          EmptyState(
            icon: Icons.trending_up,
            title: 'No investments yet',
            message:
                'Add mutual funds, stocks, FDs, RDs, PPF, EPF, NPS or gold. You enter the values; LifePilot never fetches market prices.',
            actionLabel: 'Add an investment',
            onAction: () => showInvestmentForm(context, store),
          )
        else ...[
          TileGrid(
            children: [
              StatTile(
                label: 'Invested',
                value: formatMoney(book.investedPaise),
                icon: Icons.savings_outlined,
              ),
              StatTile(
                label: 'Current value',
                value: formatMoney(book.valuePaise),
                icon: Icons.account_balance_outlined,
                caption: 'Entered or worked out',
              ),
              StatTile(
                label: gain >= 0 ? 'Gain' : 'Loss',
                value: formatMoney(gain.abs()),
                icon: gain >= 0 ? Icons.trending_up : Icons.trending_down,
                color: gain >= 0 ? colors.income : colors.expense,
                caption: book.investedPaise == 0
                    ? null
                    : '${gain >= 0 ? '+' : '−'}${(gain.abs() * 100 / book.investedPaise).toStringAsFixed(1)}%',
              ),
              StatTile(
                label: 'Monthly SIPs',
                value: formatMoney(monthlySip),
                icon: Icons.event_repeat,
                caption: '${sips.length} in the next 30 days',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Values are what you entered (with their date) or worked out from deposit rates. Not live market prices.',
            style: muted,
          ),
          if (book.allocation.length > 1) ...[
            const SectionHeader(title: 'Allocation'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DonutChart(
                  slices: [
                    for (var i = 0; i < book.allocation.length; i++)
                      DonutSlice(
                          book.allocation[i].kind.label,
                          book.allocation[i].paise,
                          colors.chart[i % colors.chart.length]),
                  ],
                  centerLabel: 'Total',
                  centerValue: formatMoneyCompact(book.valuePaise),
                ),
              ),
            ),
          ],
          const SectionHeader(title: 'Holdings'),
          for (final line in book.lines)
            _InvestmentCard(store: store, line: line, now: now),
          if (sips.isNotEmpty) ...[
            const SectionHeader(title: 'SIPs in the next 30 days'),
            CardList(
              children: [
                for (final sip in sips)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.event_repeat),
                    title: Text(sip.item.name),
                    subtitle: Text(formatDate(sip.day)),
                    trailing: Text(formatMoney(sip.item.sipPaise)),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class _InvestmentCard extends StatelessWidget {
  const _InvestmentCard(
      {required this.store, required this.line, required this.now});

  final LifePilotStore store;
  final PortfolioLine line;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final item = line.item;
    final gain = line.gainPaise;
    final maturity = maturityValue(item);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: theme.textTheme.titleMedium),
                        Text(
                          [
                            item.kind.label,
                            if (item.annualRatePercent > 0)
                              '${item.annualRatePercent}% a year',
                            if (item.sipPaise > 0)
                              'SIP ${formatMoney(item.sipPaise)} on day ${item.sipDay}',
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Investment options',
                    onSelected: (value) async {
                      switch (value) {
                        case 'value':
                          await _askAmount(context,
                              title: 'Current value of ${item.name}',
                              initial: line.value?.paise,
                              onSave: (paise) =>
                                  store.setInvestmentValue(item.id, paise));
                        case 'add':
                          await _askAmount(context,
                              title: 'Money put into ${item.name}',
                              onSave: (paise) =>
                                  store.addInvestmentFlow(item.id, paise));
                        case 'withdraw':
                          await _askAmount(context,
                              title: 'Money taken out of ${item.name}',
                              onSave: (paise) =>
                                  store.addInvestmentFlow(item.id, -paise));
                        case 'close':
                          await store
                              .updateInvestment(item.copyWith(closed: true));
                        case 'delete':
                          if (await confirmAction(context,
                              title: 'Delete “${item.name}”?',
                              message: 'Its history is deleted too.',
                              confirmLabel: 'Delete',
                              destructive: true)) {
                            await store.deleteInvestment(item.id);
                          }
                      }
                    },
                    itemBuilder: (_) => [
                      if (!item.kind.isDeposit) ...const [
                        PopupMenuItem(
                            value: 'value', child: Text('Update value')),
                        PopupMenuItem(value: 'add', child: Text('Add money')),
                        PopupMenuItem(
                            value: 'withdraw', child: Text('Take money out')),
                      ],
                      const PopupMenuItem(
                          value: 'close', child: Text('Mark as closed')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(
                                'Invested ${formatMoney(line.investedPaise)}')),
                        Text(
                          line.value == null
                              ? 'No value yet'
                              : formatMoney(line.value!.paise),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    if (line.value != null)
                      Text(line.value!.basis, style: muted),
                    if (gain != null)
                      Text(
                        '${gain >= 0 ? 'Gain' : 'Loss'} ${formatMoney(gain.abs())}'
                        '${line.xirr == null ? '' : ' · ${(line.xirr! * 100).toStringAsFixed(1)}% a year (XIRR)'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: gain >= 0 ? colors.income : colors.expense),
                      ),
                    if (item.maturityDate != null)
                      Text(
                        '${item.maturityDate!.isAfter(now) ? 'Matures' : 'Matured'} ${formatDate(item.maturityDate!)}'
                        '${maturity == null ? '' : ' · about ${formatMoney(maturity)}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _askAmount(BuildContext context,
    {required String title,
    int? initial,
    required Future<void> Function(int paise) onSave}) async {
  final paise = await showDialog<int>(
    context: context,
    builder: (_) => _AmountDialog(title: title, initial: initial),
  );
  if (paise != null) await onSave(paise);
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, this.initial});

  final String title;
  final int? initial;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _controller = TextEditingController(
      text: widget.initial == null ? '' : paiseToInput(widget.initial!));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              prefixText: '${MoneyFormat.symbol} ', errorText: _error),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final paise = parseRupeesToPaise(_controller.text);
              if (paise == null) {
                setState(() => _error = 'Enter an amount greater than zero.');
                return;
              }
              Navigator.pop(context, paise);
            },
            child: const Text('Save'),
          ),
        ],
      );
}

Future<void> showInvestmentForm(BuildContext context, LifePilotStore store) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InvestmentForm(store: store),
    );

class _InvestmentForm extends StatefulWidget {
  const _InvestmentForm({required this.store});

  final LifePilotStore store;

  @override
  State<_InvestmentForm> createState() => _InvestmentFormState();
}

class _InvestmentFormState extends State<_InvestmentForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _invested = TextEditingController();
  final _value = TextEditingController();
  final _rate = TextEditingController();
  final _sip = TextEditingController();
  final _sipDay = TextEditingController();
  var _kind = InvestmentKind.mutualFund;
  late var _start = dateOnly(widget.store.now());
  DateTime? _maturity;

  @override
  void dispose() {
    for (final controller in [_name, _invested, _value, _rate, _sip, _sipDay]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _money(String? value, {bool required = false}) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return required ? 'Enter an amount.' : null;
    return parseRupeesToPaise(text) == null ? 'Enter a valid amount.' : null;
  }

  Future<void> _pick(bool maturity) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: maturity
          ? (_maturity ?? DateTime(_start.year + 1, _start.month, _start.day))
          : _start,
      firstDate: DateTime(1980),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => maturity ? _maturity = picked : _start = picked);
  }

  @override
  Widget build(BuildContext context) {
    final deposit = _kind.isDeposit;
    final rd = _kind == InvestmentKind.recurringDeposit;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Add an investment',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            DropdownButtonFormField<InvestmentKind>(
              isExpanded: true,
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final kind in InvestmentKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.label)),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Add a name.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _invested,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: rd
                    ? 'Monthly instalment'
                    : deposit
                        ? 'Amount deposited'
                        : 'Amount invested so far',
                prefixText: '${MoneyFormat.symbol} ',
              ),
              validator: (value) => _money(value, required: deposit),
            ),
            if (!deposit) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Current value (from your statement or app)',
                  prefixText: '${MoneyFormat.symbol} ',
                ),
                validator: _money,
              ),
            ],
            if (deposit ||
                _kind == InvestmentKind.ppf ||
                _kind == InvestmentKind.epf) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _rate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Interest rate (% a year)', suffixText: '%'),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return deposit ? 'Enter the rate.' : null;
                  final rate = double.tryParse(text);
                  return rate == null || rate < 0 || rate > 50
                      ? 'Enter a rate from 0 to 50.'
                      : null;
                },
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text('Started ${formatDate(_start)}'),
              onTap: () => _pick(false),
            ),
            if (deposit)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: Text(_maturity == null
                    ? 'Set maturity date'
                    : 'Matures ${formatDate(_maturity!)}'),
                onTap: () => _pick(true),
              ),
            if (_kind == InvestmentKind.mutualFund ||
                _kind == InvestmentKind.stock ||
                _kind == InvestmentKind.nps ||
                _kind == InvestmentKind.gold)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sip,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Monthly SIP (optional)',
                          prefixText: '${MoneyFormat.symbol} '),
                      validator: _money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: TextFormField(
                      controller: _sipDay,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Day'),
                      validator: (value) {
                        if (_sip.text.trim().isEmpty) return null;
                        final day = int.tryParse((value ?? '').trim());
                        return day == null || day < 1 || day > 31
                            ? '1–31'
                            : null;
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kind.isDeposit && _maturity == null) {
      showMessage(context, 'Set the maturity date.', error: true);
      return;
    }
    final amount = parseRupeesToPaise(_invested.text) ?? 0;
    final rd = _kind == InvestmentKind.recurringDeposit;
    await widget.store.addInvestment(
      name: _name.text,
      kind: _kind,
      startDate: _start,
      investedPaise: rd ? 0 : amount,
      installmentPaise: rd ? amount : 0,
      valuePaise: parseRupeesToPaise(_value.text),
      annualRatePercent: double.tryParse(_rate.text.trim()) ?? 0,
      maturityDate: _maturity,
      sipPaise: parseRupeesToPaise(_sip.text) ?? 0,
      sipDay: int.tryParse(_sipDay.text.trim()),
    );
    if (mounted) Navigator.pop(context);
  }
}
