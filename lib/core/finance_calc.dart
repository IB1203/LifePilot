import 'models.dart';

/// Half-open date range [start, end).
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime value) =>
      !value.isBefore(start) && value.isBefore(end);

  int get days => DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(start.year, start.month, start.day))
      .inDays;
}

DateRange monthRange(DateTime date, {int offset = 0}) => DateRange(
      DateTime(date.year, date.month + offset),
      DateTime(date.year, date.month + offset + 1),
    );

/// Monday-based week containing [date].
DateRange weekRange(DateTime date, {int offset = 0}) {
  final start = DateTime(
      date.year, date.month, date.day - (date.weekday - 1) + 7 * offset);
  return DateRange(start, DateTime(start.year, start.month, start.day + 7));
}

DateRange dayRange(DateTime date, {int offset = 0}) {
  final start = DateTime(date.year, date.month, date.day + offset);
  return DateRange(start, DateTime(start.year, start.month, start.day + 1));
}

DateRange yearRange(DateTime date) =>
    DateRange(DateTime(date.year), DateTime(date.year + 1));

DateRange budgetRange(BudgetPeriod period, DateTime now, {int offset = 0}) =>
    period == BudgetPeriod.weekly
        ? weekRange(now, offset: offset)
        : monthRange(now, offset: offset);

int sumEntries(
  Iterable<LedgerEntry> entries, {
  EntryKind? kind,
  DateRange? range,
  String? category,
}) {
  var total = 0;
  for (final entry in entries) {
    if (kind != null && entry.kind != kind) continue;
    if (range != null && !range.contains(entry.occurredAt)) continue;
    if (category != null && entry.category != category) continue;
    total += entry.amountPaise;
  }
  return total;
}

class PeriodSummary {
  const PeriodSummary({required this.income, required this.expenses});

  final int income;
  final int expenses;

  /// Recorded income minus recorded expenses. This is not net worth.
  int get netCashFlow => income - expenses;
}

PeriodSummary summarize(Iterable<LedgerEntry> entries, DateRange range) =>
    PeriodSummary(
      income: sumEntries(entries, kind: EntryKind.income, range: range),
      expenses: sumEntries(entries, kind: EntryKind.expense, range: range),
    );

Map<String, int> categoryTotals(
  Iterable<LedgerEntry> entries,
  DateRange range, {
  EntryKind kind = EntryKind.expense,
}) {
  final totals = <String, int>{};
  for (final entry in entries) {
    if (entry.kind != kind || !range.contains(entry.occurredAt)) continue;
    totals.update(entry.category, (value) => value + entry.amountPaise,
        ifAbsent: () => entry.amountPaise);
  }
  final sorted = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(sorted);
}

/// Expense total for each day in [range], in order.
List<({DateTime day, int amount})> dailyExpenses(
  Iterable<LedgerEntry> entries,
  DateRange range,
) {
  final totals = List<int>.filled(range.days, 0);
  for (final entry in entries) {
    if (entry.kind != EntryKind.expense || !range.contains(entry.occurredAt)) {
      continue;
    }
    final index = DateRange(range.start, entry.occurredAt).days;
    if (index >= 0 && index < totals.length) totals[index] += entry.amountPaise;
  }
  return [
    for (var index = 0; index < totals.length; index++)
      (
        day: DateTime(
            range.start.year, range.start.month, range.start.day + index),
        amount: totals[index],
      ),
  ];
}

/// Income and expenses for the [count] months ending with [now]'s month.
List<({DateTime month, PeriodSummary summary})> monthlyHistory(
  Iterable<LedgerEntry> entries,
  DateTime now, {
  int count = 6,
}) =>
    [
      for (var offset = -(count - 1); offset <= 0; offset++)
        (
          month: DateTime(now.year, now.month + offset),
          summary: summarize(entries, monthRange(now, offset: offset)),
        ),
    ];

class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.range,
    required this.spentPaise,
    required this.carriedOverPaise,
  });

  final SpendingBudget budget;
  final DateRange range;
  final int spentPaise;
  final int carriedOverPaise;

  int get limitPaise => budget.limitPaise + carriedOverPaise;
  int get remainingPaise => limitPaise - spentPaise;
  bool get isOver => spentPaise > limitPaise;

  /// Utilization percentage, not clamped (can exceed 100).
  double get utilization => limitPaise <= 0 ? 0 : spentPaise * 100 / limitPaise;

  int get utilizationPercent => utilization.round();
  bool get isApproaching => !isOver && utilization >= budget.alertPercent;
}

BudgetStatus budgetStatus(
  SpendingBudget budget,
  Iterable<LedgerEntry> entries,
  DateTime now,
) {
  final range = budgetRange(budget.period, now);
  final spent = sumEntries(entries,
      kind: EntryKind.expense, range: range, category: budget.category);
  var carried = 0;
  if (budget.rollover) {
    final previous = sumEntries(entries,
        kind: EntryKind.expense,
        range: budgetRange(budget.period, now, offset: -1),
        category: budget.category);
    if (previous < budget.limitPaise) carried = budget.limitPaise - previous;
  }
  return BudgetStatus(
    budget: budget,
    range: range,
    spentPaise: spent,
    carriedOverPaise: carried,
  );
}

class BudgetTotals {
  const BudgetTotals({required this.limitPaise, required this.spentPaise});

  final int limitPaise;
  final int spentPaise;

  int get remainingPaise => limitPaise - spentPaise;
  double get utilization => limitPaise <= 0 ? 0 : spentPaise / limitPaise;
}

/// Totals across all monthly budgets for the current month. Weekly budgets
/// are reported separately because their periods do not line up.
BudgetTotals monthlyBudgetTotals(
  Iterable<SpendingBudget> budgets,
  Iterable<LedgerEntry> entries,
  DateTime now,
) {
  var limit = 0;
  var spent = 0;
  for (final budget in budgets) {
    if (budget.period != BudgetPeriod.monthly) continue;
    final status = budgetStatus(budget, entries, now);
    limit += status.limitPaise;
    spent += status.spentPaise;
  }
  return BudgetTotals(limitPaise: limit, spentPaise: spent);
}

/// Budget-versus-actual for one category over the last [count] periods.
List<({DateRange range, int limit, int spent})> budgetHistory(
  SpendingBudget budget,
  Iterable<LedgerEntry> entries,
  DateTime now, {
  int count = 6,
}) =>
    [
      for (var offset = -(count - 1); offset <= 0; offset++)
        () {
          final range = budgetRange(budget.period, now, offset: offset);
          return (
            range: range,
            limit: budget.limitPaise,
            spent: sumEntries(entries,
                kind: EntryKind.expense,
                range: range,
                category: budget.category),
          );
        }(),
    ];

/// Whole months between [now] and [target], counting a partial month as one.
int monthsUntil(DateTime now, DateTime target) {
  if (!target.isAfter(now)) return 0;
  var months = (target.year - now.year) * 12 + target.month - now.month;
  if (target.day > now.day) months += 1;
  return months < 1 ? 1 : months;
}

/// Monthly amount needed to reach the goal by its target date, or null when
/// the goal has no target date or is already reached.
int? suggestedMonthlyContribution(SavingsGoal goal, DateTime now) {
  final target = goal.targetDate;
  if (target == null || goal.remainingPaise == 0) return null;
  final months = monthsUntil(now, target);
  if (months == 0) return goal.remainingPaise;
  return (goal.remainingPaise + months - 1) ~/ months;
}

/// Average monthly contribution over the last [days] days.
int recentMonthlyContribution(SavingsGoal goal, DateTime now, {int days = 90}) {
  final since = now.subtract(Duration(days: days));
  final total = goal.contributions
      .where((item) => item.at.isAfter(since))
      .fold(0, (sum, item) => sum + item.amountPaise);
  return (total * 30) ~/ days;
}

/// Existing entries that look like the same transaction as [candidate]: same
/// kind and amount, recorded within [window], with a matching title,
/// merchant, or category.
List<LedgerEntry> findPossibleDuplicates(
  Iterable<LedgerEntry> entries,
  LedgerEntry candidate, {
  Duration window = const Duration(hours: 24),
}) {
  String normal(String value) => value.trim().toLowerCase();
  return entries.where((entry) {
    if (entry.id == candidate.id ||
        entry.kind != candidate.kind ||
        entry.amountPaise != candidate.amountPaise) {
      return false;
    }
    if (entry.occurredAt.difference(candidate.occurredAt).abs() > window) {
      return false;
    }
    return normal(entry.title) == normal(candidate.title) ||
        (candidate.merchant.isNotEmpty &&
            normal(entry.merchant) == normal(candidate.merchant)) ||
        entry.category == candidate.category;
  }).toList();
}

/// Bills ordered by next due date, excluding inactive ones.
List<Bill> upcomingBills(Iterable<Bill> bills, DateTime now,
    {int withinDays = 30}) {
  final limit = DateTime(now.year, now.month, now.day + withinDays + 1);
  return bills
      .where((bill) => bill.active && bill.nextDueAt.isBefore(limit))
      .toList()
    ..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
}

bool isBillOverdue(Bill bill, DateTime now) =>
    bill.active &&
    DateTime(bill.nextDueAt.year, bill.nextDueAt.month, bill.nextDueAt.day)
        .isBefore(DateTime(now.year, now.month, now.day));

/// Sum of active recurring bills normalized to a monthly amount.
int monthlyRecurringObligations(Iterable<Bill> bills) {
  var total = 0;
  for (final bill in bills.where((bill) => bill.active)) {
    total += switch (bill.recurrence.repeat.name) {
      'monthly' => bill.amountPaise,
      'quarterly' => bill.amountPaise ~/ 3,
      'yearly' => bill.amountPaise ~/ 12,
      'weekly' => bill.amountPaise * 52 ~/ 12,
      'daily' => bill.amountPaise * 365 ~/ 12,
      _ => 0,
    };
  }
  return total;
}
