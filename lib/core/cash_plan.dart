import 'finance_calc.dart';
import 'investments.dart' show Investment, sipDates;
import 'models.dart';
import 'recurrence.dart';
import 'recurring_detect.dart' show monthlyEquivalent;

/// Planning ahead: a money calendar, a cash-flow forecast, subscriptions
/// and their price changes, and a suggested salary plan. Everything is
/// computed from the user's own records; nothing moves money.

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

/// Dates of a repeating item from [first], within [from] to [to] inclusive.
Iterable<DateTime> occurrences(
    DateTime first, Recurrence recurrence, DateTime from, DateTime to) sync* {
  var due = _day(first);
  final start = _day(from);
  final end = _day(to);
  for (var step = 0; step < 800 && !due.isAfter(end); step++) {
    if (!due.isBefore(start)) yield due;
    final next = recurrence.next(due);
    if (next == null) return;
    due = _day(next);
  }
}

// ---------------------------------------------------------------------------
// Money calendar

enum MoneyEventKind { bill, income, expense, goal, sip }

class MoneyEvent {
  const MoneyEvent(this.day, this.title, this.kind, {this.amountPaise});

  final DateTime day;
  final String title;
  final MoneyEventKind kind;
  final int? amountPaise;

  /// Positive for money in, negative for money out, zero for goal dates.
  int get flowPaise => switch (kind) {
        MoneyEventKind.income => amountPaise ?? 0,
        MoneyEventKind.goal => 0,
        _ => -(amountPaise ?? 0),
      };
}

/// Bills, recurring income and expenses, and goal target dates between
/// [from] and [to], in date order.
List<MoneyEvent> moneyEvents({
  required Iterable<Bill> bills,
  required Iterable<RecurringEntry> rules,
  required Iterable<SavingsGoal> goals,
  required DateTime from,
  required DateTime to,
  Iterable<Investment> investments = const [],
}) {
  final events = <MoneyEvent>[
    for (final sip in sipDates(investments, from, to))
      MoneyEvent(sip.day, 'SIP · ${sip.item.name}', MoneyEventKind.sip,
          amountPaise: sip.item.sipPaise),
    for (final bill in bills.where((bill) => bill.active))
      for (final day in occurrences(bill.nextDueAt, bill.recurrence, from, to))
        MoneyEvent(day, bill.name, MoneyEventKind.bill,
            amountPaise: bill.amountPaise),
    for (final rule in rules.where((rule) => rule.active))
      for (final day in occurrences(rule.nextDate, rule.recurrence, from, to))
        MoneyEvent(
            day,
            rule.title,
            rule.kind == EntryKind.income
                ? MoneyEventKind.income
                : MoneyEventKind.expense,
            amountPaise: rule.amountPaise),
    for (final goal in goals)
      if (goal.targetDate != null &&
          goal.remainingPaise > 0 &&
          !_day(goal.targetDate!).isBefore(_day(from)) &&
          !_day(goal.targetDate!).isAfter(_day(to)))
        MoneyEvent(
            _day(goal.targetDate!), '${goal.name} target', MoneyEventKind.goal,
            amountPaise: goal.remainingPaise),
  ]..sort((a, b) => a.day.compareTo(b.day));
  return events;
}

// ---------------------------------------------------------------------------
// Cash-flow forecast

class CashForecast {
  const CashForecast({
    required this.days,
    required this.balances,
    required this.startKnown,
    required this.dailySpendPaise,
  });

  /// One entry per day from today.
  final List<DateTime> days;

  /// Projected balance at the end of each day.
  final List<int> balances;

  /// False when no balance is known and the forecast starts from zero, so
  /// it shows the change rather than the balance.
  final bool startKnown;

  /// Day-to-day spending assumed for each day.
  final int dailySpendPaise;

  int get lowestIndex {
    var index = 0;
    for (var i = 1; i < balances.length; i++) {
      if (balances[i] < balances[index]) index = i;
    }
    return index;
  }

  int get lowestPaise => balances[lowestIndex];
  DateTime get lowestDay => days[lowestIndex];
  int get endPaise => balances.last;

  /// First day the balance goes below zero, if it does.
  DateTime? get shortfallDay {
    for (var i = 0; i < balances.length; i++) {
      if (balances[i] < 0) return days[i];
    }
    return null;
  }
}

/// Day-by-day balance for the next [days] days: [startPaise] (or zero),
/// plus recurring income, minus bills and recurring expenses on their
/// dates, minus the average day-to-day spending of the last 30 days.
CashForecast forecastCash({
  required int? startPaise,
  required Iterable<LedgerEntry> entries,
  required Iterable<Bill> bills,
  required Iterable<RecurringEntry> rules,
  required DateTime now,
  int days = 60,
  Iterable<Investment> investments = const [],
}) {
  final today = _day(now);
  final since = today.subtract(const Duration(days: 30));
  final variable = entries
      .where((entry) =>
          entry.kind == EntryKind.expense &&
          entry.billId == null &&
          entry.source != 'recurring' &&
          !entry.occurredAt.isBefore(since) &&
          entry.occurredAt.isBefore(today))
      .fold(0, (sum, entry) => sum + entry.amountPaise);
  final daily = variable ~/ 30;
  final last = DateTime(today.year, today.month, today.day + days - 1);
  final flows = <DateTime, int>{};
  for (final event in moneyEvents(
      bills: bills,
      rules: rules,
      goals: const [],
      investments: investments,
      from: today,
      to: last)) {
    flows.update(event.day, (value) => value + event.flowPaise,
        ifAbsent: () => event.flowPaise);
  }
  // Overdue bills are still to be paid: take them today.
  for (final bill in bills
      .where((bill) => bill.active && _day(bill.nextDueAt).isBefore(today))) {
    flows.update(today, (value) => value - bill.amountPaise,
        ifAbsent: () => -bill.amountPaise);
  }
  var balance = startPaise ?? 0;
  final dayList = <DateTime>[];
  final balances = <int>[];
  for (var i = 0; i < days; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    balance += (flows[day] ?? 0) - daily;
    dayList.add(day);
    balances.add(balance);
  }
  return CashForecast(
    days: dayList,
    balances: balances,
    startKnown: startPaise != null,
    dailySpendPaise: daily,
  );
}

// ---------------------------------------------------------------------------
// Subscriptions and price changes

const _subscriptionWords = [
  'netflix', 'prime', 'spotify', 'hotstar', 'jiohotstar', 'youtube', //
  'jiocinema', 'zee5', 'sonyliv', 'apple', 'icloud', 'google one',
  'audible', 'kindle', 'linkedin', 'chatgpt', 'openai', 'claude',
  'microsoft', 'office 365', 'adobe', 'canva', 'notion', 'dropbox',
  'swiggy one', 'zomato gold', 'gaana', 'wynk', 'disney',
];

bool _looksLikeSubscription(String title, String category) {
  final lower = '$title $category'.toLowerCase();
  return category.toLowerCase().contains('subscription') ||
      _subscriptionWords.any(lower.contains);
}

class Subscription {
  const Subscription(this.name, this.amountPaise, this.repeat, this.nextDate);

  final String name;
  final int amountPaise;
  final Repeat repeat;
  final DateTime nextDate;

  int get monthlyPaise => monthlyEquivalent(amountPaise, repeat);
  int get yearlyPaise => monthlyPaise * 12;
}

/// Subscription bills, and recurring expenses that look like subscriptions
/// (a Subscriptions category or a known service name), dearest first.
List<Subscription> subscriptions(
    Iterable<Bill> bills, Iterable<RecurringEntry> rules) {
  final items = <Subscription>[
    for (final bill in bills.where((bill) =>
        bill.active &&
        (bill.kind == BillKind.subscription ||
            _looksLikeSubscription(bill.name, bill.category))))
      Subscription(
          bill.name, bill.amountPaise, bill.recurrence.repeat, bill.nextDueAt),
    for (final rule in rules.where((rule) =>
        rule.active &&
        rule.kind == EntryKind.expense &&
        _looksLikeSubscription(rule.title, rule.category)))
      Subscription(
          rule.title, rule.amountPaise, rule.recurrence.repeat, rule.nextDate),
  ]..sort((a, b) => b.monthlyPaise.compareTo(a.monthlyPaise));
  return items;
}

class PriceChange {
  const PriceChange(this.name, this.oldPaise, this.newPaise, this.on);

  final String name;
  final int oldPaise;
  final int newPaise;
  final DateTime on;

  int get changePaise => newPaise - oldPaise;
  int get percent => (changePaise * 100 / oldPaise).round();
}

/// Regular payments whose latest amount went up compared with the one
/// before, in the last [days] days: bill payments, and entries recorded
/// from a recurring rule.
List<PriceChange> priceIncreases({
  required Iterable<Bill> bills,
  required Iterable<RecurringEntry> rules,
  required Iterable<LedgerEntry> entries,
  required DateTime now,
  int days = 60,
}) {
  final since = now.subtract(Duration(days: days));
  final changes = <PriceChange>[];
  void check(String name, List<({int paise, DateTime at})> history) {
    if (history.length < 2) return;
    history.sort((a, b) => a.at.compareTo(b.at));
    final latest = history.last;
    final previous = history[history.length - 2];
    // Ignore rounding-level changes (under 1% and ₹1).
    if (latest.at.isAfter(since) &&
        latest.paise > previous.paise &&
        (latest.paise - previous.paise) * 100 >= previous.paise &&
        latest.paise - previous.paise >= 100) {
      changes.add(PriceChange(name, previous.paise, latest.paise, latest.at));
    }
  }

  for (final bill in bills) {
    check(bill.name, [
      for (final payment in bill.payments)
        (paise: payment.amountPaise, at: payment.paidAt),
    ]);
  }
  for (final rule in rules) {
    check(rule.title, [
      for (final entry in entries)
        if (entry.source == 'recurring' &&
            entry.kind == rule.kind &&
            entry.title == rule.title)
          (paise: entry.amountPaise, at: entry.occurredAt),
    ]);
  }
  changes.sort((a, b) => b.on.compareTo(a.on));
  return changes;
}

// ---------------------------------------------------------------------------
// Salary plan

class PlanLine {
  const PlanLine(this.label, this.amountPaise, this.basis);

  final String label;
  final int amountPaise;
  final String basis;
}

class SalaryPlan {
  const SalaryPlan(this.incomePaise, this.incomeBasis, this.lines);

  final int incomePaise;
  final String incomeBasis;

  /// Commitments, goals, emergency fund and day-to-day spending.
  final List<PlanLine> lines;

  int get plannedPaise => lines.fold(0, (sum, line) => sum + line.amountPaise);

  /// What is left to save or invest; negative when the plan is short.
  int get leftPaise => incomePaise - plannedPaise;
}

/// A suggested split of monthly income from the user's own records:
/// commitments first, then goals, an emergency fund top-up, and usual
/// day-to-day spending; the rest can be saved or invested. Null when no
/// income is known.
SalaryPlan? salaryPlan({
  required Iterable<LedgerEntry> entries,
  required Iterable<RecurringEntry> rules,
  required Iterable<Bill> bills,
  required Iterable<SpendingBudget> budgets,
  required Iterable<SavingsGoal> goals,
  required DateTime now,
}) {
  final threeMonths = DateRange(
      DateTime(now.year, now.month - 3), DateTime(now.year, now.month));
  final past = summarize(entries, threeMonths);

  // Income: recurring income rules if there are any, else the average of
  // the last three complete months.
  final incomeRules = rules
      .where((rule) => rule.active && rule.kind == EntryKind.income)
      .toList();
  final ruleIncome = incomeRules.fold(
      0,
      (sum, rule) =>
          sum + monthlyEquivalent(rule.amountPaise, rule.recurrence.repeat));
  final int income;
  final String incomeBasis;
  if (ruleIncome > 0) {
    income = ruleIncome;
    incomeBasis =
        'Recurring income: ${incomeRules.map((rule) => rule.title).join(', ')}';
  } else if (past.income > 0) {
    income = past.income ~/ 3;
    incomeBasis = 'Average income of the last three months';
  } else {
    return null;
  }

  final lines = <PlanLine>[];
  final int commitments = bills.where((bill) => bill.active).fold<int>(
          0,
          (sum, bill) =>
              sum +
              monthlyEquivalent(bill.amountPaise, bill.recurrence.repeat)) +
      rules
          .where((rule) => rule.active && rule.kind == EntryKind.expense)
          .fold<int>(
              0,
              (sum, rule) =>
                  sum +
                  monthlyEquivalent(rule.amountPaise, rule.recurrence.repeat));
  if (commitments > 0) {
    lines.add(PlanLine('Bills and recurring payments', commitments,
        'Monthly equivalent of active bills and recurring expenses'));
  }

  final goalNeeds = <String>[];
  var goalTotal = 0;
  for (final goal in goals) {
    final monthly = suggestedMonthlyContribution(goal, now);
    if (monthly == null || monthly <= 0) continue;
    goalTotal += monthly;
    goalNeeds.add(goal.name);
  }
  if (goalTotal > 0) {
    lines.add(PlanLine('Savings goals', goalTotal,
        'To reach ${goalNeeds.join(', ')} by their target dates'));
  }

  final monthlySpend = past.expenses ~/ 3;
  final emergency = goals
      .where((goal) => goal.type == GoalType.emergency)
      .fold(0, (sum, goal) => sum + goal.savedPaise);
  if (monthlySpend > 0 && emergency < monthlySpend * 3) {
    final topUp = income ~/ 10;
    final needed = monthlySpend * 3 - emergency;
    lines.add(PlanLine('Emergency fund', topUp < needed ? topUp : needed,
        '10% of income until it covers three months of spending'));
  }

  final budgetTotal = budgets
      .where((budget) => budget.period == BudgetPeriod.monthly)
      .fold(0, (sum, budget) => sum + budget.limitPaise);
  if (budgetTotal > 0) {
    lines.add(PlanLine(
        'Day-to-day spending', budgetTotal, 'Total of your monthly budgets'));
  } else {
    final variable = entries
        .where((entry) =>
            entry.kind == EntryKind.expense &&
            entry.billId == null &&
            entry.source != 'recurring' &&
            threeMonths.contains(entry.occurredAt))
        .fold(0, (sum, entry) => sum + entry.amountPaise);
    if (variable > 0) {
      lines.add(PlanLine('Day-to-day spending', variable ~/ 3,
          'Average of the last three months, excluding bills'));
    }
  }
  return SalaryPlan(income, incomeBasis, lines);
}
