import 'models.dart';
import 'recurring_detect.dart' show monthlyEquivalent;

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

/// True when an entry only moves money between the user's own pockets, such
/// as an account-to-account or credit-card-bill transfer. It is never income
/// or an expense, so it must not reach cash-flow, budget or report totals.
bool isInternalMovement(LedgerEntry entry) =>
    entry.classification == TransactionClassification.transfer;

/// True when an entry moves money into or out of an investment. Buying one
/// is saving, not spending, and selling one is not earned income, so these
/// stay out of income, expense and budget totals as well.
bool isInvestmentMovement(LedgerEntry entry) =>
    entry.classification == TransactionClassification.investment;

/// Entries that are neither income nor spending: internal transfers and
/// investment purchases or redemptions.
bool isNonCashFlow(LedgerEntry entry) =>
    isInternalMovement(entry) || isInvestmentMovement(entry);

int sumEntries(
  Iterable<LedgerEntry> entries, {
  EntryKind? kind,
  DateRange? range,
  String? category,
}) {
  var total = 0;
  for (final entry in entries) {
    if (isNonCashFlow(entry)) continue;
    if (kind != null && entry.kind != kind) continue;
    if (range != null && !range.contains(entry.occurredAt)) continue;
    if (category != null && entry.category != category) continue;
    total += entry.amountPaise;
  }
  return total;
}

class PeriodSummary {
  const PeriodSummary({
    required this.income,
    required this.expenses,
    this.investments = 0,
    this.refunds = 0,
    this.internalTransfers = 0,
    this.moneyReceived = 0,
    this.moneySent = 0,
    this.openingBalance = 0,
    this.closingBalance = 0,
  });

  final int income;
  final int expenses;
  final int investments;
  final int refunds;
  final int internalTransfers;
  final int moneyReceived;
  final int moneySent;
  final int openingBalance;
  final int closingBalance;

  /// Recorded income minus recorded expenses, excluding transfers and investments.
  int get netCashFlow => income - expenses;

  /// Total money flowing in (income + received money + refunds).
  int get totalIn => income + moneyReceived + refunds;

  /// Total money flowing out (expenses + sent money + investments).
  int get totalOut => expenses + moneySent + investments;
}

PeriodSummary summarize(Iterable<LedgerEntry> entries, DateRange range) =>
    PeriodSummary(
      income: sumEntries(entries, kind: EntryKind.income, range: range),
      expenses: sumEntries(entries, kind: EntryKind.expense, range: range),
    );

/// Smart summary that classifies entries by [TransactionClassification] so
/// that transfers, investments, and refunds are not confused with regular
/// income or expenses.
SmartSummary smartSummarize(Iterable<LedgerEntry> entries, DateRange range) {
  var income = 0;
  var expenses = 0;
  var investments = 0;
  var refunds = 0;
  var internalTransfers = 0;
  var moneyReceived = 0;
  var moneySent = 0;

  for (final entry in entries) {
    if (!range.contains(entry.occurredAt)) continue;

    switch (entry.classification) {
      case TransactionClassification.investment:
        investments += entry.amountPaise;
      case TransactionClassification.refund:
        refunds += entry.amountPaise;
      case TransactionClassification.transfer:
        internalTransfers += entry.amountPaise;
      case TransactionClassification.receivedMoney:
        moneyReceived += entry.amountPaise;
      case TransactionClassification.cashWithdrawal:
        moneySent += entry.amountPaise;
      case TransactionClassification.loanReceived:
        moneyReceived += entry.amountPaise;
      case TransactionClassification.income:
      case TransactionClassification.expense:
      case TransactionClassification.bills:
      case TransactionClassification.shopping:
      case TransactionClassification.food:
      case TransactionClassification.debtPayment:
      case TransactionClassification.other:
        // Spending types and plain income follow the entry's direction, so
        // a mislabelled entry is never counted on the wrong side.
        if (entry.kind == EntryKind.income) {
          income += entry.amountPaise;
        } else {
          expenses += entry.amountPaise;
        }
    }
  }

  return SmartSummary(
    income: income,
    expenses: expenses,
    investments: investments,
    refunds: refunds,
    internalTransfers: internalTransfers,
    moneyReceived: moneyReceived,
    moneySent: moneySent,
    openingBalance: 0,
    closingBalance: 0,
  );
}

/// Smart summary with classification-aware totals.
class SmartSummary {
  const SmartSummary({
    required this.income,
    required this.expenses,
    required this.investments,
    required this.refunds,
    required this.internalTransfers,
    required this.moneyReceived,
    required this.moneySent,
    required this.openingBalance,
    required this.closingBalance,
  });

  final int income;
  final int expenses;
  final int investments;
  final int refunds;
  final int internalTransfers;
  final int moneyReceived;
  final int moneySent;
  final int openingBalance;
  final int closingBalance;

  int get netCashFlow => income - expenses;
  int get totalIn => income + moneyReceived + refunds;
  int get totalOut => expenses + moneySent + investments;
}

Map<String, int> categoryTotals(
  Iterable<LedgerEntry> entries,
  DateRange range, {
  EntryKind kind = EntryKind.expense,
}) {
  final totals = <String, int>{};
  for (final entry in entries) {
    if (isNonCashFlow(entry)) continue;
    if (entry.kind != kind || !range.contains(entry.occurredAt)) continue;
    totals.update(entry.category, (value) => value + entry.amountPaise,
        ifAbsent: () => entry.amountPaise);
  }
  final sorted = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(sorted);
}

/// Spending within [category] by subcategory, largest first; entries
/// without a subcategory are grouped under "Other".
Map<String, int> subcategoryTotals(
    Iterable<LedgerEntry> entries, DateRange range, String category) {
  final totals = <String, int>{};
  for (final entry in entries) {
    if (entry.kind != EntryKind.expense ||
        isNonCashFlow(entry) ||
        entry.category != category ||
        !range.contains(entry.occurredAt)) {
      continue;
    }
    final key = entry.subcategory.isEmpty ? 'Other' : entry.subcategory;
    totals.update(key, (value) => value + entry.amountPaise,
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
    if (entry.kind != EntryKind.expense ||
        isNonCashFlow(entry) ||
        !range.contains(entry.occurredAt)) {
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
  if (budget.rollover && _hadPreviousPeriod(budget, range)) {
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

/// Whether [budget] already existed during the period before [range], so
/// that period's unspent money may roll over. Budgets without a creation
/// date (saved by older versions) are treated as long-standing.
bool _hadPreviousPeriod(SpendingBudget budget, DateRange range) {
  final created = budget.createdAt;
  return created == null || created.isBefore(range.start);
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
}) {
  int spentIn(DateRange range) => sumEntries(entries,
      kind: EntryKind.expense, range: range, category: budget.category);
  return [
    for (var offset = -(count - 1); offset <= 0; offset++)
      () {
        final range = budgetRange(budget.period, now, offset: offset);
        var limit = budget.limitPaise;
        if (budget.rollover && _hadPreviousPeriod(budget, range)) {
          final previous = spentIn(
              budgetRange(budget.period, now, offset: offset - 1));
          if (previous < budget.limitPaise) {
            limit += budget.limitPaise - previous;
          }
        }
        return (range: range, limit: limit, spent: spentIn(range));
      }(),
  ];
}

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
/// kind and amount, recorded within [window], with a matching title or
/// merchant. Category alone is not enough, since many purchases share one.
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
            normal(entry.merchant) == normal(candidate.merchant));
  }).toList();
}

/// Entries that describe the same transaction, from SMS, a statement or a
/// manual entry. Amount, kind and date must match, and either a reference
/// (UTR/UPI/RRN) or the title/merchant must agree, so two equal payments are
/// not merged just because they share an amount.
class DuplicateGroup {
  const DuplicateGroup(this.entries);

  final List<LedgerEntry> entries;

  LedgerEntry get keep => entries.first;

  Iterable<String> get duplicateIds => entries.skip(1).map((e) => e.id);

  int get totalPaise =>
      entries.fold(0, (sum, entry) => sum + entry.amountPaise);
}

final _referencePattern = RegExp(
    r'\b(?:ref(?:erence)?|utr|rrn|upi\s*ref|txn|transaction)(?:\s*(?:no|num|number|id))?\.?\s*[:#-]?\s*([A-Za-z0-9]*\d[A-Za-z0-9]*)',
    caseSensitive: false);

/// A bank reference (UTR/RRN/UPI ref) on the entry, if it has one. It must
/// contain a digit and be 6–24 characters, so words such as "transaction
/// successful" are not mistaken for one.
String? _referenceOf(LedgerEntry entry) {
  final stored = entry.sourceReference;
  if (stored != null &&
      stored.length >= 6 &&
      !stored.contains('|') &&
      RegExp(r'\d').hasMatch(stored)) {
    return stored;
  }
  for (final match
      in _referencePattern.allMatches('${entry.note} ${entry.title}')) {
    final value = match.group(1)!;
    if (value.length >= 6 && value.length <= 24) return value;
  }
  return null;
}

String _plain(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

List<DuplicateGroup> findDuplicateGroups(
  Iterable<LedgerEntry> entries, {
  Duration window = const Duration(days: 3),
}) {
  final list = entries.toList();
  // Only entries with the same kind and amount can be duplicates, so compare
  // inside those buckets instead of every pair in the ledger.
  final buckets = <String, List<int>>{};
  for (var i = 0; i < list.length; i++) {
    final key = '${list[i].kind.name}|${list[i].amountPaise}';
    buckets.putIfAbsent(key, () => []).add(i);
  }
  final used = <int>{};
  final groups = <DuplicateGroup>[];
  for (var i = 0; i < list.length; i++) {
    if (used.contains(i)) continue;
    final first = list[i];
    final candidates =
        buckets['${first.kind.name}|${first.amountPaise}'] ?? const <int>[];
    final members = <LedgerEntry>[first];
    for (final j in candidates) {
      if (j <= i || used.contains(j)) continue;
      final other = list[j];
      if (other.occurredAt.difference(first.occurredAt).abs() > window) {
        continue;
      }
      final firstRef = _referenceOf(first);
      final otherRef = _referenceOf(other);
      // Two different bank references are two different transactions.
      if (firstRef != null && otherRef != null && firstRef != otherRef) {
        continue;
      }
      final sameReference = firstRef != null && firstRef == otherRef;
      Set<String> words(LedgerEntry entry) =>
          _plain('${entry.title} ${entry.merchant}')
              .split(' ')
              .where((word) => word.isNotEmpty)
              .toSet();
      final firstWords = words(first);
      final otherWords = words(other);
      // Whole words, not substrings: "tea" must not match "steam".
      final sameWords = firstWords.isNotEmpty &&
          otherWords.isNotEmpty &&
          (firstWords.containsAll(otherWords) ||
              otherWords.containsAll(firstWords));
      if (!sameReference && !sameWords) continue;
      members.add(other);
      used.add(j);
    }
    if (members.length > 1) {
      members.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      groups.add(DuplicateGroup(members));
      used.add(i);
    }
  }
  return groups;
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
    total += monthlyEquivalent(bill.amountPaise, bill.recurrence.repeat,
        interval: bill.recurrence.interval);
  }
  return total;
}
