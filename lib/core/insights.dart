import 'finance_calc.dart';
import 'formatters.dart';
import 'models.dart';

enum InsightLevel { info, attention, warning }

/// An observation derived only from records on this device. [basis] explains
/// which records or comparison support it.
class Insight {
  const Insight({
    required this.id,
    required this.title,
    required this.detail,
    required this.basis,
    this.level = InsightLevel.info,
  });

  final String id;
  final String title;
  final String detail;
  final String basis;
  final InsightLevel level;
}

/// Minimum amount for a change to be worth mentioning (₹500).
const _meaningfulPaise = 50000;

List<Insight> buildInsights({
  required List<LedgerEntry> entries,
  required List<SpendingBudget> budgets,
  required List<Bill> bills,
  required List<SavingsGoal> goals,
  required DateTime now,
}) {
  final insights = <Insight>[
    ..._billInsights(bills, now),
    ..._budgetInsights(budgets, entries, now),
    ..._categoryTrendInsights(entries, now),
    ..._unusualTransactionInsights(entries, now),
    ..._goalInsights(goals, now),
  ];
  insights.sort((a, b) => b.level.index.compareTo(a.level.index));
  return insights;
}

Iterable<Insight> _billInsights(List<Bill> bills, DateTime now) sync* {
  for (final bill in upcomingBills(bills, now, withinDays: 3)) {
    final overdue = isBillOverdue(bill, now);
    yield Insight(
      id: 'bill-${bill.id}',
      title: overdue
          ? '${bill.name} is past its due date'
          : '${bill.name} is due ${friendlyDay(bill.nextDueAt, now).toLowerCase()}',
      detail:
          '${formatMoney(bill.amountPaise)} was due ${formatDate(bill.nextDueAt)}. '
          '${overdue ? 'It stays unpaid until you confirm a payment.' : 'Mark it paid once you have paid it.'}',
      basis: 'Next due date saved for this bill.',
      level: overdue ? InsightLevel.warning : InsightLevel.attention,
    );
  }
}

Iterable<Insight> _budgetInsights(
  List<SpendingBudget> budgets,
  List<LedgerEntry> entries,
  DateTime now,
) sync* {
  for (final budget in budgets) {
    final status = budgetStatus(budget, entries, now);
    final period = budget.period == BudgetPeriod.weekly ? 'week' : 'month';
    if (status.isOver) {
      yield Insight(
        id: 'budget-over-${budget.category}',
        title: '${budget.category} budget exceeded',
        detail:
            '${formatMoney(status.spentPaise)} spent against ${formatMoney(status.limitPaise)} this $period '
            '(${formatMoney(-status.remainingPaise)} over).',
        basis:
            'Expenses in ${budget.category} recorded since ${formatShortDate(status.range.start)}.',
        level: InsightLevel.warning,
      );
    } else if (status.isApproaching) {
      yield Insight(
        id: 'budget-near-${budget.category}',
        title:
            '${budget.category} budget is ${status.utilizationPercent}% used',
        detail:
            '${formatMoney(status.remainingPaise)} left of ${formatMoney(status.limitPaise)} this $period.',
        basis:
            'Expenses in ${budget.category} recorded since ${formatShortDate(status.range.start)}; alert set at ${budget.alertPercent}%.',
        level: InsightLevel.attention,
      );
    }
  }
}

/// Compares month-to-date spending per category with the same days of the
/// previous month, so a partial month is never compared with a full one.
Iterable<Insight> _categoryTrendInsights(
  List<LedgerEntry> entries,
  DateTime now,
) sync* {
  final current = DateRange(DateTime(now.year, now.month), now);
  final previousStart = DateTime(now.year, now.month - 1);
  final previousMonthDays = DateTime(now.year, now.month, 0).day;
  final comparableDay =
      now.day > previousMonthDays ? previousMonthDays : now.day;
  final previous = DateRange(
    previousStart,
    DateTime(previousStart.year, previousStart.month, comparableDay, now.hour,
        now.minute, now.second),
  );
  final currentTotals = categoryTotals(entries, current);
  final previousTotals = categoryTotals(entries, previous);
  for (final MapEntry(key: category, value: spent) in currentTotals.entries) {
    final before = previousTotals[category] ?? 0;
    if (before <= 0) continue;
    final increase = spent - before;
    if (increase < _meaningfulPaise || spent < before * 1.25) continue;
    final percent = (increase * 100 / before).round();
    yield Insight(
      id: 'trend-$category',
      title: '$category spending is up $percent%',
      detail:
          '${formatMoney(spent)} so far this month compared with ${formatMoney(before)} by the same day last month.',
      basis:
          '$category expenses from 1–${now.day} ${shortMonthLabel(now)} versus 1–$comparableDay ${shortMonthLabel(previousStart)}.',
      level: InsightLevel.info,
    );
  }
}

/// Flags recent expenses at least three times the median of that category,
/// only when the category has at least five earlier expenses.
Iterable<Insight> _unusualTransactionInsights(
  List<LedgerEntry> entries,
  DateTime now,
) sync* {
  final recentStart = now.subtract(const Duration(days: 7));
  final recent = entries.where((entry) =>
      entry.kind == EntryKind.expense &&
      entry.occurredAt.isAfter(recentStart) &&
      !entry.occurredAt.isAfter(now));
  for (final entry in recent) {
    final history = entries
        .where((item) =>
            item.kind == EntryKind.expense &&
            item.category == entry.category &&
            item.occurredAt.isBefore(recentStart))
        .map((item) => item.amountPaise)
        .toList()
      ..sort();
    if (history.length < 5) continue;
    final median = history[history.length ~/ 2];
    if (median <= 0 ||
        entry.amountPaise < median * 3 ||
        entry.amountPaise - median < _meaningfulPaise) {
      continue;
    }
    yield Insight(
      id: 'unusual-${entry.id}',
      title: 'Unusually large ${entry.category} expense',
      detail:
          '“${entry.title}” on ${formatShortDate(entry.occurredAt)} was ${formatMoney(entry.amountPaise)}, '
          'about ${(entry.amountPaise / median).toStringAsFixed(1)}× your typical ${entry.category} expense.',
      basis:
          'Median of ${history.length} earlier ${entry.category} expenses: ${formatMoney(median)}.',
      level: InsightLevel.info,
    );
  }
}

Iterable<Insight> _goalInsights(List<SavingsGoal> goals, DateTime now) sync* {
  for (final goal in goals) {
    final needed = suggestedMonthlyContribution(goal, now);
    if (needed == null) continue;
    final target = goal.targetDate!;
    if (!target.isAfter(now)) {
      yield Insight(
        id: 'goal-late-${goal.id}',
        title: '${goal.name} passed its target date',
        detail:
            '${formatMoney(goal.remainingPaise)} remains. Consider setting a new target date.',
        basis: 'Target date ${formatDate(target)} and recorded contributions.',
        level: InsightLevel.attention,
      );
      continue;
    }
    // Only judge the pace once the goal has had time to collect contributions.
    if (now.difference(goal.createdAt).inDays < 30) continue;
    final pace = recentMonthlyContribution(goal, now);
    if (pace >= needed) continue;
    yield Insight(
      id: 'goal-pace-${goal.id}',
      title: '${goal.name} may need larger contributions',
      detail:
          'To reach ${formatMoney(goal.targetPaise)} by ${formatDate(target)}, about ${formatMoney(needed)} a month is needed. '
          'Recent contributions average ${formatMoney(pace)} a month.',
      basis:
          'Contributions recorded in the last 90 days and ${formatMoney(goal.remainingPaise)} remaining.',
      level: InsightLevel.attention,
    );
  }
}
