import 'package:flutter/material.dart';

import '../core/debts.dart';
import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Finance › Debts: loans, card dues, money borrowed and lent, and the
/// debt-free planner.
class DebtsTab extends StatelessWidget {
  const DebtsTab({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = store.now();
    final open = store.debts.where((debt) => !debt.closed).toList();
    final mine = open.where((debt) => !debt.owedToMe).toList();
    final lent = open.where((debt) => debt.owedToMe).toList();
    final closed = store.debts.where((debt) => debt.closed).length;
    final totals = debtTotals(store.debts, asOf: now);
    final income = summarize(
                store.entries,
                DateRange(DateTime(now.year, now.month - 3),
                    DateTime(now.year, now.month)))
            .income ~/
        3;
    return ListView(
      padding: pagePadding,
      children: [
        SectionHeader(
          title: 'Debts and loans',
          action: 'Add',
          onAction: () => showDebtForm(context, store),
        ),
        if (store.debts.isEmpty)
          EmptyState(
            icon: Icons.account_balance_outlined,
            title: 'No loans or debts',
            message:
                'Add a loan, credit card dues, or money you borrowed or lent to see what is left, the interest, and when it will be cleared.',
            actionLabel: 'Add a debt',
            onAction: () => showDebtForm(context, store),
          )
        else ...[
          TileGrid(
            children: [
              StatTile(
                label: 'You owe',
                value: formatMoney(totals.owedPaise),
                icon: Icons.north_east,
                color: colors.expense,
                caption: '${mine.length} open',
              ),
              StatTile(
                label: 'Owed to you',
                value: formatMoney(totals.lentPaise),
                icon: Icons.south_west,
                color: colors.income,
                caption: '${lent.length} open',
              ),
              StatTile(
                label: 'Monthly payments',
                value: formatMoney(totals.monthlyPaise),
                icon: Icons.event_repeat,
                caption: income > 0 && totals.monthlyPaise > 0
                    ? '${(totals.monthlyPaise * 100 / income).round()}% of income'
                    : 'EMIs and card minimums',
              ),
              StatTile(
                label: 'Closed',
                value: '$closed',
                icon: Icons.task_alt,
                caption: 'Paid off or settled',
              ),
            ],
          ),
          if (mine.isNotEmpty) ...[
            const SectionHeader(title: 'You owe'),
            for (final debt in mine)
              _DebtCard(store: store, debt: debt, now: now),
            DebtFreePlanner(store: store),
          ],
          if (lent.isNotEmpty) ...[
            const SectionHeader(title: 'Owed to you'),
            for (final debt in lent)
              _DebtCard(store: store, debt: debt, now: now),
          ],
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => showSplitForm(context, store),
          icon: const Icon(Icons.call_split),
          label: const Text('Split a bill with others'),
        ),
      ],
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.store, required this.debt, required this.now});

  final LifePilotStore store;
  final Debt debt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final status = debtStatus(debt, asOf: now);
    final monthly = monthlyPaymentFor(debt, status.outstandingPaise);
    final plan = debt.owedToMe
        ? null
        : payoff(status.outstandingPaise, debt.annualRatePercent, monthly, now);
    final paidShare = debt.openingPaise == 0
        ? 0.0
        : status.principalPaidPaise / debt.openingPaise;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(debt.name, style: theme.textTheme.titleMedium),
                        Text(
                          [
                            debt.kind.label,
                            if (debt.counterparty.isNotEmpty) debt.counterparty,
                            if (debt.annualRatePercent > 0)
                              '${debt.annualRatePercent}% a year',
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Debt options',
                    onSelected: (value) async {
                      switch (value) {
                        case 'edit':
                          await showDebtForm(context, store, debt: debt);
                        case 'close':
                          await store.updateDebt(debt.copyWith(closed: true));
                        case 'delete':
                          if (await confirmAction(context,
                              title: 'Delete “${debt.name}”?',
                              message:
                                  'Its payment history is deleted too. Expenses already recorded stay.',
                              confirmLabel: 'Delete',
                              destructive: true)) {
                            await store.deleteDebt(debt.id);
                          }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                          value: 'close', child: Text('Mark as settled')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: Text(debt.owedToMe
                                ? 'Still to get back'
                                : 'Outstanding')),
                        Text(formatMoney(status.outstandingPaise),
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: debt.owedToMe
                                    ? colors.income
                                    : colors.expense)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedBar(value: paidShare),
                    const SizedBox(height: 4),
                    Text(
                      '${formatMoney(status.principalPaidPaise)} of ${formatMoney(debt.openingPaise)} repaid'
                      '${status.interestPaidPaise > 0 ? ' · ${formatMoney(status.interestPaidPaise)} interest paid' : ''}',
                      style: muted,
                    ),
                    if (!debt.owedToMe) ...[
                      const SizedBox(height: 4),
                      Text(
                        monthly <= 0
                            ? 'No monthly payment set. Edit it to see when it will be cleared.'
                            : plan == null
                                ? '${formatMoney(monthly)} a month does not cover the interest, so this debt keeps growing.'
                                : '${formatMoney(monthly)} a month clears it in ${plan.months} month${plan.months == 1 ? '' : 's'} (${monthLabel(plan.closesOn)})'
                                    '${plan.interestPaise > 0 ? ' with ${formatMoney(plan.interestPaise)} more interest' : ''}.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: plan == null && monthly > 0
                                ? theme.colorScheme.error
                                : null),
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: () =>
                            showDebtPaymentForm(context, store, debt),
                        child: Text(debt.owedToMe
                            ? 'Record repayment'
                            : 'Record payment'),
                      ),
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

/// Compares paying off debts smallest-first and highest-interest-first,
/// with an optional extra amount each month.
class DebtFreePlanner extends StatefulWidget {
  const DebtFreePlanner({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<DebtFreePlanner> createState() => _DebtFreePlannerState();
}

class _DebtFreePlannerState extends State<DebtFreePlanner> {
  final _extra = TextEditingController();

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extra = parseRupeesToPaise(_extra.text) ?? 0;
    final now = widget.store.now();
    final plans = {
      for (final strategy in PayoffStrategy.values)
        strategy: debtFreePlan(widget.store.debts, strategy,
            extraPaise: extra, asOf: now),
    };
    final base = debtFreePlan(widget.store.debts, PayoffStrategy.avalanche,
        asOf: now);
    final best = plans.entries
        .where((item) => item.value != null)
        .fold<MapEntry<PayoffStrategy, DebtFreePlan?>?>(
            null,
            (best, item) => best == null ||
                    item.value!.interestPaise < best.value!.interestPaise
                ? item
                : best);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Debt-free planner', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pay every usual instalment, and put anything extra on one debt at a time.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _extra,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Extra each month (optional)',
                prefixText: '${MoneyFormat.symbol} ',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            for (final MapEntry(key: strategy, value: plan) in plans.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(best?.key == strategy
                    ? Icons.star_rounded
                    : Icons.circle_outlined),
                title: Text(strategy.label),
                subtitle: Text(plan == null
                    ? 'Payments do not cover the interest. Add an extra amount.'
                    : 'Debt-free in ${plan.months} months (${monthLabel(DateTime(now.year, now.month + plan.months))}) · ${formatMoney(plan.interestPaise)} interest'
                        '${plan.order.length > 1 ? '\nOrder: ${plan.order.join(' → ')}' : ''}'),
                isThreeLine: plan != null && plan.order.length > 1,
              ),
            if (extra > 0 && base != null && best?.value != null)
              Text(
                'Paying ${formatMoney(extra)} more a month saves ${formatMoney(base.interestPaise - best!.value!.interestPaise)} in interest and ${base.months - best.value!.months} months.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Forms

Future<void> showDebtForm(BuildContext context, LifePilotStore store,
        {Debt? debt}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DebtForm(store: store, debt: debt),
    );

class _DebtForm extends StatefulWidget {
  const _DebtForm({required this.store, this.debt});

  final LifePilotStore store;
  final Debt? debt;

  @override
  State<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<_DebtForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.debt?.name ?? '');
  late final _person =
      TextEditingController(text: widget.debt?.counterparty ?? '');
  late final _amount = TextEditingController(
      text: widget.debt == null ? '' : paiseToInput(widget.debt!.openingPaise));
  late final _rate = TextEditingController(
      text: (widget.debt?.annualRatePercent ?? 0) == 0
          ? ''
          : '${widget.debt!.annualRatePercent}');
  late final _emi = TextEditingController(
      text: (widget.debt?.emiPaise ?? 0) == 0
          ? ''
          : paiseToInput(widget.debt!.emiPaise));
  final _months = TextEditingController();
  late var _kind = widget.debt?.kind ?? DebtKind.loan;
  late var _start = widget.debt?.startDate ?? dateOnly(widget.store.now());

  @override
  void dispose() {
    for (final controller in [_name, _person, _amount, _rate, _emi, _months]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _personal => _kind == DebtKind.borrowed || _kind == DebtKind.lent;

  double? get _rateValue {
    final text = _rate.text.trim();
    if (text.isEmpty) return 0;
    final value = double.tryParse(text);
    return value == null || value < 0 || value > 100 ? null : value;
  }

  void _workOutEmi() {
    final amount = parseRupeesToPaise(_amount.text);
    final months = int.tryParse(_months.text.trim());
    final rate = _rateValue;
    if (amount == null || months == null || months <= 0 || rate == null) {
      showMessage(context, 'Enter the amount, rate and number of months first.',
          error: true);
      return;
    }
    setState(() => _emi.text = paiseToInput(emiFor(amount, rate, months)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(widget.debt == null ? 'Add a debt' : 'Edit debt',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            DropdownButtonFormField<DebtKind>(
              isExpanded: true,
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final kind in DebtKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.label)),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: _personal
                      ? 'Trip money, rent share…'
                      : 'Home loan, HDFC card…'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Add a name.' : null,
            ),
            if (_personal) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _person,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Person'),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: widget.debt == null
                    ? 'Amount outstanding now'
                    : 'Amount outstanding on the start date',
                prefixText: '${MoneyFormat.symbol} ',
              ),
              validator: (value) => parseRupeesToPaise(value ?? '') == null
                  ? 'Enter an amount greater than zero.'
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text('As of ${formatDate(_start)}'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: DateTime(1990),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _start = picked);
              },
            ),
            TextFormField(
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Interest rate (% a year, optional)',
                  suffixText: '%'),
              validator: (_) =>
                  _rateValue == null ? 'Enter a rate from 0 to 100.' : null,
            ),
            if (!_personal) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _emi,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _kind == DebtKind.creditCard
                      ? 'Monthly payment (optional; 5% minimum if empty)'
                      : 'EMI (monthly instalment)',
                  prefixText: '${MoneyFormat.symbol} ',
                ),
                validator: (value) => (value ?? '').trim().isEmpty ||
                        parseRupeesToPaise(value!) != null
                    ? null
                    : 'Enter a valid amount.',
              ),
              if (_kind == DebtKind.loan)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _months,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Months left (to work out the EMI)'),
                      ),
                    ),
                    TextButton(
                        onPressed: _workOutEmi,
                        child: const Text('Work out EMI')),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseRupeesToPaise(_amount.text)!;
    final emi = _personal ? 0 : parseRupeesToPaise(_emi.text) ?? 0;
    final rate = _rateValue ?? 0;
    final debt = widget.debt;
    if (debt == null) {
      await widget.store.addDebt(
        name: _name.text,
        kind: _kind,
        openingPaise: amount,
        startDate: _start,
        annualRatePercent: rate,
        emiPaise: emi,
        counterparty: _personal ? _person.text : '',
      );
    } else {
      await widget.store.updateDebt(debt.copyWith(
        name: _name.text.trim(),
        kind: _kind,
        openingPaise: amount,
        startDate: dateOnly(_start),
        annualRatePercent: rate,
        emiPaise: emi,
        counterparty: _personal ? _person.text.trim() : '',
      ));
    }
    if (mounted) Navigator.pop(context);
  }
}

Future<void> showDebtPaymentForm(
        BuildContext context, LifePilotStore store, Debt debt) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentForm(store: store, debt: debt),
    );

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.store, required this.debt});

  final LifePilotStore store;
  final Debt debt;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: () {
    final outstanding = debtStatus(widget.debt, asOf: widget.store.now()).outstandingPaise;
    final usual = monthlyPaymentFor(widget.debt, outstanding);
    final suggested = usual > 0 && usual < outstanding ? usual : outstanding;
    return suggested > 0 ? paiseToInput(suggested) : '';
  }());
  late var _date = widget.store.now();
  late var _record =
      !widget.debt.owedToMe && widget.debt.kind != DebtKind.borrowed;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debt = widget.debt;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(debt.owedToMe ? 'Repayment received' : 'Payment made',
                style: Theme.of(context).textTheme.headlineSmall),
            Text(
                '${debt.name} · ${formatMoney(debtStatus(debt, asOf: widget.store.now()).outstandingPaise)} outstanding'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Amount', prefixText: '${MoneyFormat.symbol} '),
              validator: (value) => parseRupeesToPaise(value ?? '') == null
                  ? 'Enter an amount greater than zero.'
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(formatDate(_date)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1990),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            if (!debt.owedToMe)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _record,
                onChanged: (value) => setState(() => _record = value ?? false),
                title: const Text('Also record as an expense (Loans)'),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                try {
                  final updated = await widget.store.addDebtPayment(
                    debt.id,
                    amountPaise: parseRupeesToPaise(_amount.text)!,
                    at: _date,
                    recordExpense: _record,
                  );
                  if (!context.mounted) return;
                  showMessage(
                      context,
                      updated.closed
                          ? '${debt.name} is cleared!'
                          : '${formatMoney(debtStatus(updated, asOf: widget.store.now()).outstandingPaise)} left on ${debt.name}');
                  Navigator.pop(context);
                } on Object catch (error) {
                  if (context.mounted) {
                    showMessage(context, '$error', error: true);
                  }
                }
              },
              child: const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showSplitForm(BuildContext context, LifePilotStore store) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SplitForm(store: store),
    );

class _SplitForm extends StatefulWidget {
  const _SplitForm({required this.store});

  final LifePilotStore store;

  @override
  State<_SplitForm> createState() => _SplitFormState();
}

class _SplitFormState extends State<_SplitForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _people = TextEditingController();
  late var _category = widget.store.categories.contains('Food')
      ? 'Food'
      : widget.store.categories.first;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _people.dispose();
    super.dispose();
  }

  List<String> get _names => _people.text
      .split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final total = parseRupeesToPaise(_amount.text);
    final ways = _names.length + 1;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('Split a bill',
                style: Theme.of(context).textTheme.headlineSmall),
            const Text(
                'You paid the whole bill. Your share is recorded as an expense; everyone else\'s share is tracked as money owed to you.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'What for', hintText: 'Dinner, cab, groceries…'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add a description.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Total paid',
                  prefixText: '${MoneyFormat.symbol} '),
              onChanged: (_) => setState(() {}),
              validator: (value) {
                final parsed = parseRupeesToPaise(value ?? '');
                if (parsed == null) {
                  return 'Enter an amount greater than zero.';
                }
                if (parsed ~/ (_names.length + 1) <= 0) {
                  return 'Each share would be less than ₹0.01.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _people,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Split with',
                  hintText: 'Names, separated by commas'),
              onChanged: (_) => setState(() {}),
              validator: (_) =>
                  _names.isEmpty ? 'Add at least one other person.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final item in widget.store.categories)
                  DropdownMenuItem(value: item, child: Text(item)),
              ],
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            if (total != null && _names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(total ~/ ways <= 0
                    ? 'Too small to split $ways ways.'
                    : '$ways ways: ${formatMoney(total ~/ ways)} each.'),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                try {
                  await widget.store.splitBill(
                    title: _title.text,
                    totalPaise: parseRupeesToPaise(_amount.text)!,
                    people: _names,
                    category: _category,
                  );
                  if (context.mounted) Navigator.pop(context);
                } on Object catch (error) {
                  if (context.mounted) {
                    showMessage(context, 'Could not split the bill: $error',
                        error: true);
                  }
                }
              },
              child: const Text('Split'),
            ),
          ],
        ),
      ),
    );
  }
}
