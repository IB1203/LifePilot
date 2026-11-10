import 'package:flutter/material.dart';

import '../core/debts.dart';
import '../core/finance_calc.dart';
import '../core/formatters.dart';
import '../core/investments.dart' show portfolio;
import '../core/local_store.dart';
import '../core/money_glance.dart';
import '../core/models.dart';
import '../core/personal.dart' show accountBalance;
import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../ui/forms.dart' show showMarkPaidForm;

/// Home section: money available, spent, saved and coming up, with a
/// safe-to-spend amount, month-end forecast, net worth and health score.
class MoneyGlanceSection extends StatelessWidget {
  const MoneyGlanceSection(
      {required this.store,
      required this.now,
      required this.onOpen,
      super.key});

  final LifePilotStore store;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final hidden = store.settings.hideAmounts;
    final month = summarize(store.entries, monthRange(now));
    final available = availableMoney(
      bankBalances: store.bankBalances,
      accounts: store.accounts,
      entries: store.entries,
      transfers: store.transfers,
    );
    final saved = store.goals.fold(0, (sum, goal) => sum + goal.savedPaise);
    final upcoming = upcomingCommitments(
        bills: store.bills, rules: store.recurring, now: now);
    final upcomingTotal =
        upcoming.fold(0, (sum, item) => sum + item.amountPaise);
    final dueSoon = upcomingBills(store.bills, now, withinDays: 3)
      ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
    final budgetWarnings = <SpendingBudget>[];
    for (final budget in store.budgets
        .where((b) => b.period == BudgetPeriod.monthly)) {
      final projected = budgetForecast(budget, store.entries, now);
      if (projected != null && projected.willExceed) {
        budgetWarnings.add(budget);
      }
    }
    final debt = debtTotals(store.debts, asOf: now);
    final safe = safeToSpend(
      entries: store.entries,
      budgets: store.budgets,
      bills: store.bills,
      rules: store.recurring,
      now: now,
      availablePaise: available?.paise,
      monthlyEmiPaise: debt.monthlyPaise,
    );
    final forecast = monthForecast(
        entries: store.entries,
        bills: store.bills,
        rules: store.recurring,
        now: now);
    final budgets = monthlyBudgetTotals(store.budgets, store.entries, now);
    final overBudget =
        budgets.limitPaise > 0 && forecast.projectedPaise > budgets.limitPaise;
    final worth = netWorth(
      accounts: store.accounts,
      entries: store.entries,
      transfers: store.transfers,
      goals: store.goals,
      debtsPaise: debt.owedPaise,
      lentPaise: debt.lentPaise,
      investmentsPaise: portfolio(store.investments, now).valuePaise,
    );
    final health = healthScore(
      entries: store.entries,
      budgets: store.budgets,
      bills: store.bills,
      goals: store.goals,
      now: now,
      monthlyDebtPaise: debt.monthlyPaise,
    );
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your money at a glance',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: hidden ? 'Show amounts' : 'Hide amounts',
              icon: Icon(hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => store.updateSettings(
                  store.settings.copyWith(hideAmounts: !hidden)),
            ),
          ],
        ),
        TileGrid(
          children: [
            StatTile(
              label: 'Available',
              value: available == null ? '—' : formatMoney(available.paise),
              icon: Icons.account_balance_wallet_outlined,
              caption: available?.basis ?? 'Add an account or bank SMS',
              onTap: onOpen,
            ),
            StatTile(
              label: 'Spent this month',
              value: formatMoney(month.expenses),
              icon: Icons.north_east,
              color: colors.expense,
              caption: 'Income ${formatMoney(month.income)}',
              onTap: onOpen,
            ),
            StatTile(
              label: 'Saved',
              value: formatMoney(saved),
              icon: Icons.savings_outlined,
              color: colors.income,
              caption: month.netCashFlow > 0
                  ? '+${formatMoney(month.netCashFlow)} kept this month'
                  : 'In savings goals',
              onTap: onOpen,
            ),
            StatTile(
              label: 'Due in 30 days',
              value: formatMoney(upcomingTotal),
              icon: Icons.event_note_outlined,
              color: colors.warning,
              caption: upcoming.isEmpty
                  ? 'No bills or recurring payments'
                  : '${upcoming.length} payment${upcoming.length == 1 ? '' : 's'} · next ${upcoming.first.title}',
              onTap: onOpen,
            ),
            for (final account in store.accounts.where((item) => !item.archived).take(4))
              StatTile(
                label: account.name,
                value: formatMoney(accountBalance(account, store.entries, store.transfers)),
                icon: _accountIcon(account.kind),
                color: accountBalance(account, store.entries, store.transfers) < 0
                    ? colors.expense
                    : null,
                caption: '${account.kind.label} · tap to open Finance',
                onTap: onOpen,
              ),
          ],
        ),
        if (dueSoon.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_busy_outlined,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Bills due soon',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final bill in dueSoon.take(3))
                    ListTile(
                      dense: true,
                      title: Text(bill.name),
                      subtitle: Text(
                        isBillOverdue(bill, now)
                            ? 'Overdue since ${formatDate(bill.nextDueAt)}'
                            : 'Due ${friendlyDay(bill.nextDueAt, now)}',
                      ),
                      trailing: Text(formatMoney(bill.amountPaise),
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700)),
                      onTap: () => showMarkPaidForm(context, store, bill),
                    ),
                  if (dueSoon.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                          '+${dueSoon.length - 3} more due soon',
                          style: muted),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (budgetWarnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.trending_up,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Budget may exceed limit',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final budget in budgetWarnings.take(3))
                    ListTile(
                      dense: true,
                      title: Text(budget.category),
                      subtitle: const Text('Monthly budget · on track to exceed'),
                      trailing: Text(
                          '${formatMoney(budget.limitPaise)} limit',
                          style: theme.textTheme.bodySmall),
                      onTap: () => onOpen(),
                    ),
                  if (budgetWarnings.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                          '+${budgetWarnings.length - 3} more at risk',
                          style: muted),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (safe != null) ...[
                  Row(
                    children: [
                      Expanded(
                          child: Text('Safe to spend today',
                              style: theme.textTheme.labelLarge)),
                      Text(formatMoney(safe.perDayPaise),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      IconButton(
                        tooltip: 'How this is calculated',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.info_outline, size: 18),
                        onPressed: () => showSafeToSpend(context, safe),
                      ),
                    ],
                  ),
                  Text(safe.basis, style: muted),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Icon(
                        overBudget
                            ? Icons.warning_amber_rounded
                            : Icons.insights_outlined,
                        size: 18,
                        color: overBudget ? colors.warning : null),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'By month end: about ${formatMoney(forecast.projectedPaise)} spent'
                        '${budgets.limitPaise > 0 ? ' of ${formatMoney(budgets.limitPaise)} budgeted' : ''}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${formatMoney(forecast.spentPaise)} spent so far + '
                  '${formatMoney(forecast.dailyPacePaise)}/day × ${forecast.daysLeft} day${forecast.daysLeft == 1 ? '' : 's'} left'
                  '${forecast.committedPaise > 0 ? ' + ${formatMoney(forecast.committedPaise)} of bills and recurring payments' : ''}.',
                  style: muted,
                ),
                if (worth != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: Text('Net worth',
                              style: theme.textTheme.labelLarge)),
                      Text(formatMoney(worth.paise),
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: worth.paise < 0 ? colors.expense : null)),
                    ],
                  ),
                  Text(worth.basis, style: muted),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ActionChip(
                    avatar: const Icon(Icons.favorite_outline, size: 18),
                    label: Text(health == null
                        ? 'Health score: not enough data yet'
                        : 'Health score ${health.value} · ${health.label}'),
                    onPressed: () => showHealthScore(context, health),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showSafeToSpend(BuildContext context, SafeToSpend safe) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final rows = <(String, int)>[
          (safe.fundsLabel, safe.fundsPaise),
          if (safe.spentPaise > 0) ('Spent this month', -safe.spentPaise),
          if (safe.committedPaise > 0)
            ('Bills and recurring payments still due', -safe.committedPaise),
          if (safe.emiPaise > 0) ('Loan EMIs this month', -safe.emiPaise),
          if (safe.bufferPaise > 0) ('Buffer kept back', -safe.bufferPaise),
        ];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('Safe to spend today', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'How the ${formatMoney(safe.perDayPaise)} a day is worked out.',
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
                  Expanded(child: Text('Left for the month',
                      style: theme.textTheme.titleSmall)),
                  Text(formatMoney(safe.remainingPaise),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child: Text('÷ ${safe.days} day${safe.days == 1 ? '' : 's'} left including today')),
                  Text(formatMoney(safe.perDayPaise),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                safe.basis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );

Future<void> showHealthScore(BuildContext context, HealthScore? health) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                  health == null
                      ? 'Financial health score'
                      : 'Financial health: ${health.value} / 100',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                health == null
                    ? 'The score needs at least two of: income recorded over the last three months, a monthly budget, and bill payments.'
                    : 'An average of the parts below that your records can measure. It is a guide, not financial advice.',
                style: theme.textTheme.bodySmall,
              ),
              for (final factor in health?.factors ?? const <HealthFactor>[])
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(factor.name,
                                  style: theme.textTheme.titleSmall)),
                          Text('${(factor.score * 100).round()}%'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      AnimatedBar(value: factor.score),
                      const SizedBox(height: 4),
                      Text(factor.detail, style: theme.textTheme.bodySmall),
                      if (factor.tip.isNotEmpty)
                        Text(factor.tip,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );


IconData _accountIcon(AccountKind kind) => switch (kind) {
      AccountKind.cash => Icons.payments_outlined,
      AccountKind.bank => Icons.account_balance_outlined,
      AccountKind.upi => Icons.qr_code_2,
      AccountKind.card => Icons.credit_card,
      AccountKind.wallet => Icons.account_balance_wallet_outlined,
      AccountKind.other => Icons.savings_outlined,
    };
