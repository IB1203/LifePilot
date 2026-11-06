import 'finance_calc.dart';
import 'models.dart';
import 'personal.dart' show accountBalance;
import 'recurrence.dart';

/// "Your money at a glance": available money, month-end forecasts, a daily
/// safe-to-spend amount, month-on-month comparison and a financial health
/// score. Every figure comes from the user's own records and says what it
/// is based on.

// ---------------------------------------------------------------------------
// Available money and net worth

/// A figure plus a short note on what it is based on.
typedef Figure = ({int paise, String basis});

/// Money available now: the latest bank SMS balances when there are any
/// (cards' credit limits excluded), otherwise recorded balances of the
/// user's non-card accounts. Null when neither exists.
Figure? availableMoney({
  required Iterable<BankBalance> bankBalances,
  required Iterable<Account> accounts,
  required Iterable<LedgerEntry> entries,
  required Iterable<AccountTransfer> transfers,
}) {
  final fromBank = bankBalances.where((item) => !item.isLimit).toList();
  if (fromBank.isNotEmpty) {
    return (
      paise: fromBank.fold(0, (sum, item) => sum + item.paise),
      basis: 'Latest balance in bank SMS for ${fromBank.length} '
          'account${fromBank.length == 1 ? '' : 's'}',
    );
  }
  final held = accounts
      .where((item) => !item.archived && item.kind != AccountKind.card)
      .toList();
  if (held.isEmpty) return null;
  return (
    paise: held.fold(
        0, (sum, item) => sum + accountBalance(item, entries, transfers)),
    basis: 'Recorded balances of ${held.length} '
        'account${held.length == 1 ? '' : 's'}',
  );
}

/// Recorded balances of every active account, cards included (a card with
/// dues is negative), plus money saved in goals, minus [debtsPaise].
Figure? netWorth({
  required Iterable<Account> accounts,
  required Iterable<LedgerEntry> entries,
  required Iterable<AccountTransfer> transfers,
  required Iterable<SavingsGoal> goals,
  int debtsPaise = 0,
  int lentPaise = 0,
  int investmentsPaise = 0,
}) {
  final active = accounts.where((item) => !item.archived).toList();
  final saved = goals.fold(0, (sum, goal) => sum + goal.savedPaise);
  if (active.isEmpty &&
      saved == 0 &&
      debtsPaise == 0 &&
      lentPaise == 0 &&
      investmentsPaise == 0) {
    return null;
  }
  final balances = active.fold(
      0, (sum, item) => sum + accountBalance(item, entries, transfers));
  return (
    paise: balances + saved + lentPaise + investmentsPaise - debtsPaise,
    basis: [
      if (active.isNotEmpty) 'Recorded account balances',
      if (saved > 0) 'savings goals',
      if (investmentsPaise > 0) 'investments',
      if (lentPaise > 0) 'money lent',
      if (debtsPaise > 0) 'minus loans and money owed',
    ].join(', '),
  );
}

// ---------------------------------------------------------------------------
// Upcoming commitments

class Commitment {
  const Commitment(this.title, this.amountPaise, this.due,
      {this.isBill = true});

  final String title;
  final int amountPaise;
  final DateTime due;
  final bool isBill;
}

/// Bills and recurring expenses due from today up to [days] days ahead,
/// soonest first. Each occurrence of a frequent rule is listed.
List<Commitment> upcomingCommitments({
  required Iterable<Bill> bills,
  required Iterable<RecurringEntry> rules,
  required DateTime now,
  int days = 30,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(today.year, today.month, today.day + days + 1);
  final items = <Commitment>[];
  void expand(String title, int paise, DateTime first, Recurrence recurrence,
      bool isBill) {
    var due = first;
    for (var step = 0; step < 400 && due.isBefore(end); step++) {
      if (!due.isBefore(today)) {
        items.add(Commitment(title, paise, due, isBill: isBill));
      }
      final next = recurrence.next(due);
      if (next == null) break;
      due = next;
    }
  }

  for (final bill in bills.where((bill) => bill.active)) {
    final due = bill.nextDueAt;
    // An overdue bill is still a commitment: count it once, today.
    if (due.isBefore(today)) {
      items.add(Commitment(bill.name, bill.amountPaise, today));
      final next = bill.recurrence.nextAfter(due, today);
      if (next != null) {
        expand(bill.name, bill.amountPaise, next, bill.recurrence, true);
      }
    } else {
      expand(bill.name, bill.amountPaise, due, bill.recurrence, true);
    }
  }
  for (final rule
      in rules.where((rule) => rule.active && rule.kind == EntryKind.expense)) {
    expand(rule.title, rule.amountPaise, rule.nextDate, rule.recurrence, false);
  }
  items.sort((a, b) => a.due.compareTo(b.due));
  return items;
}

// ---------------------------------------------------------------------------
// Month-end forecast and safe to spend

class MonthForecast {
  const MonthForecast({
    required this.spentPaise,
    required this.dailyPacePaise,
    required this.daysLeft,
    required this.committedPaise,
  });

  /// Spent so far this month.
  final int spentPaise;

  /// Average day-to-day spending so far, excluding bills and recurring
  /// payments (they are counted when due instead).
  final int dailyPacePaise;

  /// Days after today until the month ends.
  final int daysLeft;

  /// Bills and recurring expenses still due this month.
  final int committedPaise;

  int get projectedPaise =>
      spentPaise + dailyPacePaise * daysLeft + committedPaise;
}

bool _isFixed(LedgerEntry entry) =>
    entry.billId != null || entry.source == 'recurring';

MonthForecast monthForecast({
  required Iterable<LedgerEntry> entries,
  required Iterable<Bill> bills,
  required Iterable<RecurringEntry> rules,
  required DateTime now,
}) {
  final month = monthRange(now);
  final today = DateTime(now.year, now.month, now.day);
  final spent = sumEntries(entries, kind: EntryKind.expense, range: month);
  final variable = entries
      .where((entry) =>
          entry.kind == EntryKind.expense &&
          month.contains(entry.occurredAt) &&
          !_isFixed(entry))
      .fold(0, (sum, entry) => sum + entry.amountPaise);
  final elapsed = now.day;
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final daysLeft = daysInMonth - now.day;
  final committed =
      upcomingCommitments(bills: bills, rules: rules, now: now, days: daysLeft)
          .where((item) => item.due.month == today.month)
          .fold(0, (sum, item) => sum + item.amountPaise);
  return MonthForecast(
    spentPaise: spent,
    dailyPacePaise: variable ~/ elapsed,
    daysLeft: daysLeft,
    committedPaise: committed,
  );
}

/// Where a monthly budget is heading at the current pace.
class BudgetForecast {
  const BudgetForecast(this.category, this.limitPaise, this.projectedPaise);

  final String category;
  final int limitPaise;
  final int projectedPaise;

  bool get willExceed => projectedPaise > limitPaise;
  int get overPaise => projectedPaise - limitPaise;
}

/// Month-end projection for one monthly budget: spent so far plus the
/// category's daily pace for the remaining days.
BudgetForecast? budgetForecast(
    SpendingBudget budget, Iterable<LedgerEntry> entries, DateTime now) {
  if (budget.period != BudgetPeriod.monthly) return null;
  final status = budgetStatus(budget, entries, now);
  final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;
  final pace = status.spentPaise ~/ now.day;
  return BudgetForecast(
      budget.category, status.limitPaise, status.spentPaise + pace * daysLeft);
}

/// How much can be spent today without breaking the month's plan, with the
/// basis: monthly budgets left when there are budgets, otherwise income this
/// month minus spending and what is still due. Null when neither is known.
Figure? safeToSpendToday({
  required Iterable<LedgerEntry> entries,
  required Iterable<SpendingBudget> budgets,
  required Iterable<Bill> bills,
  required Iterable<RecurringEntry> rules,
  required DateTime now,
}) {
  final daysIncludingToday =
      DateTime(now.year, now.month + 1, 0).day - now.day + 1;
  final totals = monthlyBudgetTotals(budgets, entries, now);
  if (totals.limitPaise > 0) {
    final left = totals.remainingPaise < 0 ? 0 : totals.remainingPaise;
    return (
      paise: left ~/ daysIncludingToday,
      basis: 'Budgets left this month ÷ $daysIncludingToday days',
    );
  }
  final month = summarize(entries, monthRange(now));
  if (month.income <= 0) return null;
  final forecast =
      monthForecast(entries: entries, bills: bills, rules: rules, now: now);
  final free = month.income - month.expenses - forecast.committedPaise;
  return (
    paise: (free < 0 ? 0 : free) ~/ daysIncludingToday,
    basis:
        'Income this month − spending − bills still due, ÷ $daysIncludingToday days',
  );
}

// ---------------------------------------------------------------------------
// Month-on-month comparison

class CategoryChange {
  const CategoryChange(this.category, this.thisMonthPaise, this.lastMonthPaise);

  final String category;
  final int thisMonthPaise;
  final int lastMonthPaise;

  int get changePaise => thisMonthPaise - lastMonthPaise;

  /// Percentage change, or null when last month was zero.
  int? get changePercent =>
      lastMonthPaise == 0 ? null : (changePaise * 100 / lastMonthPaise).round();
}

/// Spending per category this month so far against the same days of last
/// month, biggest changes first.
List<CategoryChange> compareWithLastMonth(
    Iterable<LedgerEntry> entries, DateTime now) {
  final previous = DateTime(now.year, now.month - 1);
  final previousDays = DateTime(now.year, now.month, 0).day;
  final sameDay = now.day > previousDays ? previousDays : now.day;
  final thisMonth = categoryTotals(entries,
      DateRange(monthRange(now).start, now.add(const Duration(seconds: 1))));
  final lastMonth = categoryTotals(
      entries,
      DateRange(
          previous,
          DateTime(previous.year, previous.month, sameDay, now.hour, now.minute,
              now.second + 1)));
  final changes = [
    for (final category in {...thisMonth.keys, ...lastMonth.keys})
      CategoryChange(
          category, thisMonth[category] ?? 0, lastMonth[category] ?? 0),
  ]..sort((a, b) => b.changePaise.abs().compareTo(a.changePaise.abs()));
  return changes;
}

// ---------------------------------------------------------------------------
// Financial health score

class HealthFactor {
  const HealthFactor(this.name, this.score, this.detail, this.tip);

  final String name;

  /// 0 to 1.
  final double score;
  final String detail;

  /// What would improve it; empty when there is nothing to do.
  final String tip;
}

class HealthScore {
  const HealthScore(this.factors);

  final List<HealthFactor> factors;

  int get value => (factors.fold(0.0, (sum, item) => sum + item.score) *
          100 /
          factors.length)
      .round();

  String get label => value >= 75
      ? 'Good'
      : value >= 50
          ? 'Fair'
          : 'Needs attention';
}

double _clamp(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);

/// A 0–100 score from the factors that can be measured with the user's
/// records: savings rate, budgets kept, emergency fund and bills paid on
/// time. Factors without data are left out; null when fewer than two can be
/// measured.
HealthScore? healthScore({
  required Iterable<LedgerEntry> entries,
  required Iterable<SpendingBudget> budgets,
  required Iterable<Bill> bills,
  required Iterable<SavingsGoal> goals,
  required DateTime now,
  int monthlyDebtPaise = 0,
}) {
  final factors = <HealthFactor>[];

  // Savings rate over the last three complete months; 20% or more is full.
  final threeMonths = DateRange(
      DateTime(now.year, now.month - 3), DateTime(now.year, now.month));
  final past = summarize(entries, threeMonths);
  if (past.income > 0) {
    final rate = past.netCashFlow / past.income;
    factors.add(HealthFactor(
      'Savings rate',
      _clamp(rate / 0.2),
      'You kept ${(rate * 100).round()}% of your income over the last three months.',
      rate >= 0.2 ? '' : 'Aim to keep at least 20% of what comes in.',
    ));
  }

  // Monthly budgets on track this month.
  final monthly = budgets
      .where((budget) => budget.period == BudgetPeriod.monthly)
      .map((budget) => budgetStatus(budget, entries, now))
      .toList();
  if (monthly.isNotEmpty) {
    final kept = monthly.where((status) => !status.isOver).length;
    factors.add(HealthFactor(
      'Budgets',
      kept / monthly.length,
      '$kept of ${monthly.length} monthly budgets within their limit.',
      kept == monthly.length
          ? ''
          : 'Over: ${monthly.where((status) => status.isOver).map((status) => status.budget.category).join(', ')}.',
    ));
  }

  // Emergency fund against three months of spending.
  final monthlySpend = past.expenses ~/ 3;
  if (monthlySpend > 0) {
    final fund = goals
        .where((goal) => goal.type == GoalType.emergency)
        .fold(0, (sum, goal) => sum + goal.savedPaise);
    final months = fund / monthlySpend;
    factors.add(HealthFactor(
      'Emergency fund',
      _clamp(months / 3),
      fund == 0
          ? 'No emergency savings recorded.'
          : 'Covers about ${months.toStringAsFixed(1)} months of spending.',
      months >= 3
          ? ''
          : 'Build an emergency fund goal worth three months of spending.',
    ));
  }

  // Bills paid by their due date over the last six months.
  final since = now.subtract(const Duration(days: 182));
  var onTime = 0;
  var total = 0;
  final today = DateTime(now.year, now.month, now.day);
  for (final bill in bills) {
    for (final payment
        in bill.payments.where((item) => item.paidAt.isAfter(since))) {
      total++;
      final due = DateTime(
          payment.dueAt.year, payment.dueAt.month, payment.dueAt.day + 1);
      if (payment.paidAt.isBefore(due)) onTime++;
    }
    if (bill.active && bill.nextDueAt.isBefore(today)) total++;
  }
  if (total > 0) {
    factors.add(HealthFactor(
      'Bills on time',
      onTime / total,
      '$onTime of $total bill payments made by the due date.',
      onTime == total ? '' : 'Turn on bill reminders a few days early.',
    ));
  }

  // Debt payments against income: up to 30% is comfortable, 60% or more
  // leaves little room.
  final monthlyIncome = past.income ~/ 3;
  if (monthlyDebtPaise > 0 && monthlyIncome > 0) {
    final ratio = monthlyDebtPaise / monthlyIncome;
    factors.add(HealthFactor(
      'Debt payments',
      _clamp((0.6 - ratio) / 0.3),
      'EMIs and card payments take ${(ratio * 100).round()}% of your monthly income.',
      ratio <= 0.3
          ? ''
          : 'Lenders prefer under 30%. The debt-free planner shows the fastest way down.',
    ));
  }

  return factors.length < 2 ? null : HealthScore(factors);
}
