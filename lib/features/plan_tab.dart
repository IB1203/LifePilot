import 'package:flutter/material.dart';

import '../core/cash_plan.dart';
import '../core/formatters.dart';
import '../core/local_store.dart';
import '../core/money_glance.dart' show availableMoney;
import '../core/recurrence.dart';
import '../ui/charts.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Finance › Plan: cash-flow forecast, money calendar, salary plan and
/// subscriptions.
class PlanTab extends StatelessWidget {
  const PlanTab({required this.store, super.key});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) => ListView(
        padding: pagePadding,
        children: [
          _CashFlowSection(store: store),
          MoneyCalendar(store: store),
          _SalaryPlanSection(store: store),
          _SubscriptionsSection(store: store),
        ],
      );
}

class _CashFlowSection extends StatelessWidget {
  const _CashFlowSection({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final now = store.now();
    final start = availableMoney(
      bankBalances: store.bankBalances,
      accounts: store.accounts,
      entries: store.entries,
      transfers: store.transfers,
    );
    final forecast = forecastCash(
      startPaise: start?.paise,
      entries: store.entries,
      bills: store.bills,
      rules: store.recurring,
      now: now,
      investments: store.investments,
    );
    final points = [
      for (var i = 0; i < forecast.days.length; i += 7) i,
      if ((forecast.days.length - 1) % 7 != 0) forecast.days.length - 1,
    ];
    final shortfall = forecast.shortfallDay;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Cash flow, next 60 days'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (shortfall != null && forecast.startKnown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Money may run short around ${formatDate(shortfall)}. Move a payment, trim spending, or keep a buffer before then.',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                LineChart(
                  labels: [
                    for (final i in points) formatShortDate(forecast.days[i]),
                  ],
                  values: [for (final i in points) forecast.balances[i]],
                  color: colors.chart.first,
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => showForecastBreakdown(context, forecast, start?.basis),
                  child: Text(
                    forecast.startKnown
                        ? 'Lowest: ${formatMoney(forecast.lowestPaise)} on ${formatDate(forecast.lowestDay)} · in 60 days: ${formatMoney(forecast.endPaise)} · details'
                        : 'Change from today: lowest ${formatMoney(forecast.lowestPaise)} on ${formatDate(forecast.lowestDay)} · details',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${forecast.startKnown ? 'Starts from: ${start!.basis}.' : 'No balance known yet: add an account or scan bank SMS to see a real balance.'} '
                  'Adds recurring income, takes off bills and recurring payments on their dates, and ${formatMoney(forecast.dailySpendPaise)} a day of usual spending (last 30 days).',
                  style: muted,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Month grid of bills, recurring income and expenses, and goal dates.
class MoneyCalendar extends StatefulWidget {
  const MoneyCalendar({required this.store, super.key});

  final LifePilotStore store;

  @override
  State<MoneyCalendar> createState() => _MoneyCalendarState();
}

class _MoneyCalendarState extends State<MoneyCalendar> {
  late DateTime _selected = dateOnly(widget.store.now());
  late DateTime _month = DateTime(_selected.year, _selected.month);

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final now = store.now();
    final first = _month;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final events = moneyEvents(
      bills: store.bills,
      rules: store.recurring,
      goals: store.goals,
      investments: store.investments,
      from: first,
      to: DateTime(first.year, first.month, days),
    );
    final byDay = <DateTime, List<MoneyEvent>>{};
    for (final event in events) {
      byDay.putIfAbsent(event.day, () => []).add(event);
    }
    Color tone(MoneyEventKind kind) => switch (kind) {
          MoneyEventKind.income => colors.income,
          MoneyEventKind.goal => scheme.primary,
          _ => colors.warning,
        };
    final leading = first.weekday - 1;
    final cells = ((leading + days) / 7).ceil() * 7;
    final selectedEvents = byDay[_selected] ?? const <MoneyEvent>[];
    final monthIn = events.fold(
        0, (sum, item) => sum + (item.flowPaise > 0 ? item.flowPaise : 0));
    final monthOut = events.fold(
        0, (sum, item) => sum + (item.flowPaise < 0 ? -item.flowPaise : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Money calendar'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => setState(() =>
                          _month = DateTime(_month.year, _month.month - 1)),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(monthLabel(_month),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => setState(() =>
                          _month = DateTime(_month.year, _month.month + 1)),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Text(
                  'Scheduled: ${formatMoney(monthIn)} in · ${formatMoney(monthOut)} out',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var day = 1; day <= 7; day++)
                      Expanded(
                        child: Text(weekdayShort(day).substring(0, 2),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall),
                      ),
                  ],
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cells,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, childAspectRatio: 0.95),
                  itemBuilder: (context, index) {
                    final number = index - leading + 1;
                    if (number < 1 || number > days) return const SizedBox();
                    final day = DateTime(first.year, first.month, number);
                    final selected = day == _selected;
                    final today = day == dateOnly(now);
                    final kinds = {
                      for (final event in byDay[day] ?? const <MoneyEvent>[])
                        event.kind == MoneyEventKind.bill
                            ? MoneyEventKind.expense
                            : event.kind,
                    };
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _selected = day),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : null,
                          borderRadius: BorderRadius.circular(10),
                          border: today && !selected
                              ? Border.all(color: scheme.primary)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$number',
                                style: TextStyle(
                                    color: selected ? scheme.onPrimary : null,
                                    fontWeight:
                                        today ? FontWeight.w700 : null)),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (final kind in kinds)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 1),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? scheme.onPrimary
                                          : tone(kind),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (selectedEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Nothing scheduled on ${formatDate(_selected)}.',
                style: theme.textTheme.bodySmall),
          )
        else
          CardList(
            children: [
              for (final event in selectedEvents)
                ListTile(
                  dense: true,
                  leading: Icon(
                    switch (event.kind) {
                      MoneyEventKind.bill => Icons.receipt_long_outlined,
                      MoneyEventKind.income => Icons.south_west,
                      MoneyEventKind.expense => Icons.autorenew,
                      MoneyEventKind.goal => Icons.flag_outlined,
                      MoneyEventKind.sip => Icons.trending_up,
                    },
                    color: tone(event.kind),
                  ),
                  title: Text(event.title),
                  subtitle: Text(switch (event.kind) {
                    MoneyEventKind.bill => 'Bill due',
                    MoneyEventKind.income => 'Expected income',
                    MoneyEventKind.expense => 'Recurring payment',
                    MoneyEventKind.goal => 'Goal target date · still needed',
                    MoneyEventKind.sip => 'SIP instalment',
                  }),
                  trailing: event.amountPaise == null
                      ? null
                      : Text(
                          '${event.flowPaise > 0 ? '+' : event.flowPaise < 0 ? '−' : ''}${formatMoney(event.amountPaise!)}'),
                ),
            ],
          ),
      ],
    );
  }
}

class _SalaryPlanSection extends StatelessWidget {
  const _SalaryPlanSection({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final plan = salaryPlan(
      entries: store.entries,
      rules: store.recurring,
      bills: store.bills,
      budgets: store.budgets,
      goals: store.goals,
      now: store.now(),
    );
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Salary plan'),
        if (plan == null)
          const EmptyState(
            compact: true,
            icon: Icons.account_balance_outlined,
            title: 'No income yet',
            message:
                'Add your salary as a recurring entry, or record income, to get a suggested monthly split.',
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text('Monthly income',
                              style: theme.textTheme.titleSmall)),
                      Text(formatMoney(plan.incomePaise),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Text(plan.incomeBasis, style: muted),
                  for (final line in plan.lines) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: Text(line.label)),
                        Text(formatMoney(line.amountPaise)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedBar(
                        value: plan.incomePaise == 0
                            ? 0
                            : line.amountPaise / plan.incomePaise),
                    Text(line.basis, style: muted),
                  ],
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.leftPaise >= 0
                              ? 'Left to save or invest'
                              : 'Short by',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        formatMoney(plan.leftPaise.abs()),
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: plan.leftPaise >= 0
                                ? colors.income
                                : theme.colorScheme.error),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A suggestion from your records. LifePilot never moves money.',
                    style: muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SubscriptionsSection extends StatelessWidget {
  const _SubscriptionsSection({required this.store});

  final LifePilotStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final items = subscriptions(store.bills, store.recurring);
    final increases = priceIncreases(
      bills: store.bills,
      rules: store.recurring,
      entries: store.entries,
      now: store.now(),
    );
    final monthly = items.fold(0, (sum, item) => sum + item.monthlyPaise);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Subscriptions'),
        if (items.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.subscriptions_outlined,
            title: 'No subscriptions found',
            message:
                'Add them as bills of type Subscription, or as recurring expenses (Netflix, Spotify, Prime…).',
          )
        else ...[
          TileGrid(
            children: [
              StatTile(
                label: 'Per month',
                value: formatMoney(monthly),
                icon: Icons.calendar_view_month,
                caption:
                    '${items.length} subscription${items.length == 1 ? '' : 's'}',
              ),
              StatTile(
                label: 'Per year',
                value: formatMoney(monthly * 12),
                icon: Icons.calendar_today_outlined,
                color: colors.expense,
                caption: 'If nothing changes',
              ),
            ],
          ),
          const SizedBox(height: 10),
          CardList(
            children: [
              for (final item in items)
                ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                      '${Recurrence(item.repeat).label} · next ${formatDate(item.nextDate)}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatMoney(item.amountPaise)),
                      if (item.repeat != Repeat.monthly)
                        Text('${formatMoney(item.monthlyPaise)}/month',
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (increases.isNotEmpty) ...[
          const SectionHeader(title: 'Price increases'),
          CardList(
            children: [
              for (final change in increases)
                ListTile(
                  leading: Icon(Icons.trending_up, color: colors.warning),
                  title: Text('${change.name} +${change.percent}%'),
                  subtitle: Text(
                      '${formatMoney(change.oldPaise)} → ${formatMoney(change.newPaise)} on ${formatDate(change.on)}'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shows how the cash-flow forecast is built up, so its lowest point and
/// closing balance can be checked against the figures that produced them.
Future<void> showForecastBreakdown(
        BuildContext context, CashForecast forecast, String? startBasis) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final rows = <(String, int)>[
          (
            forecast.startKnown
                ? 'Confirmed starting balance'
                : 'Starting balance (unknown)',
            forecast.startPaise,
          ),
          ('Expected recurring income', forecast.scheduledIncomePaise),
          ('Bills and recurring payments', -forecast.scheduledExpensePaise),
          ('Usual day-to-day spending', -forecast.estimatedSpendPaise),
        ];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('How this forecast is built',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Day by day over ${forecast.days.length} days. $startBasis'.trim(),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final (label, amount) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text(label)),
                      Text(
                        amount < 0
                            ? '− ${formatMoney(-amount)}'
                            : formatMoney(amount),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text('Lowest projected balance',
                      style: theme.textTheme.titleSmall)),
                  Text('${formatMoney(forecast.lowestPaise)} · ${formatDate(forecast.lowestDay)}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: Text('Projected closing balance',
                      style: theme.textTheme.titleSmall)),
                  Text(formatMoney(forecast.endPaise),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Day-to-day spending is estimated from your last 30 days of '
                'everyday spending (${formatMoney(forecast.dailySpendPaise)} a day), '
                'apart from bills and recurring payments, which are placed on their dates.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
