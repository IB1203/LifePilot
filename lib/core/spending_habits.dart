import 'finance_calc.dart';
import 'models.dart';

/// Day-to-day spending patterns: a heatmap of the month, the no-spend
/// challenge, and trip budgets.

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

/// Everyday spending: expenses other than bills, recurring payments and
/// loan instalments, which a no-spend day does not count against.
bool isEverydaySpend(LedgerEntry entry) =>
    entry.kind == EntryKind.expense &&
    entry.billId == null &&
    entry.source != 'recurring' &&
    entry.category != 'Loans';

/// Spending per day of [month] (all expenses), and a 0–4 intensity for each
/// day relative to the month's own spending days (quartiles), so the
/// heatmap reads the same for small and large spenders.
({Map<DateTime, int> totals, Map<DateTime, int> level}) monthHeatmap(
    Iterable<LedgerEntry> entries, DateTime month) {
  final totals = <DateTime, int>{
    for (final item in dailyExpenses(entries, monthRange(month)))
      if (item.amount > 0) _day(item.day): item.amount,
  };
  final sorted = totals.values.toList()..sort();
  int quartile(double q) =>
      sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * q).round()];
  final cuts = [quartile(0.25), quartile(0.5), quartile(0.75)];
  return (
    totals: totals,
    level: {
      for (final MapEntry(key: day, value: amount) in totals.entries)
        day: amount <= cuts[0]
            ? 1
            : amount <= cuts[1]
                ? 2
                : amount <= cuts[2]
                    ? 3
                    : 4,
    },
  );
}

class NoSpendStats {
  const NoSpendStats({
    required this.noSpendDays,
    required this.daysSoFar,
    required this.currentStreak,
    required this.bestStreak,
    required this.days,
  });

  /// Days this month, up to today, with no everyday spending.
  final int noSpendDays;
  final int daysSoFar;

  /// No-spend days in a row ending today (or yesterday, if today has
  /// spending already).
  final int currentStreak;
  final int bestStreak;
  final Set<DateTime> days;
}

NoSpendStats noSpendStats(Iterable<LedgerEntry> entries, DateTime now) {
  final today = _day(now);
  final spentDays = {
    for (final entry in entries)
      if (isEverydaySpend(entry) &&
          entry.occurredAt.year == now.year &&
          entry.occurredAt.month == now.month)
        _day(entry.occurredAt),
  };
  final days = <DateTime>{};
  var best = 0;
  var run = 0;
  for (var d = 1; d <= now.day; d++) {
    final day = DateTime(now.year, now.month, d);
    if (spentDays.contains(day)) {
      run = 0;
    } else {
      days.add(day);
      run++;
      if (run > best) best = run;
    }
  }
  var current = 0;
  var day = spentDays.contains(today)
      ? today.subtract(const Duration(days: 1))
      : today;
  while (day.month == now.month && days.contains(day)) {
    current++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return NoSpendStats(
    noSpendDays: days.length,
    daysSoFar: now.day,
    currentStreak: current,
    bestStreak: best,
    days: days,
  );
}

// ---------------------------------------------------------------------------
// Trips

class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.budgetPaise,
  });

  final String id;
  final String name;
  final DateTime start;

  /// Last day of the trip, inclusive.
  final DateTime end;
  final int budgetPaise;

  DateRange get range =>
      DateRange(_day(start), DateTime(end.year, end.month, end.day + 1));

  int get days => range.days;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'budgetPaise': budgetPaise,
      };

  factory Trip.fromJson(Map<String, dynamic> json) {
    final trip = Trip(
      id: json['id'] as String,
      name: json['name'] as String,
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      budgetPaise: json['budgetPaise'] as int,
    );
    if (trip.name.trim().isEmpty ||
        trip.budgetPaise <= 0 ||
        trip.end.isBefore(trip.start)) {
      throw const FormatException('Invalid trip in backup.');
    }
    return trip;
  }
}

class TripStatus {
  const TripStatus({
    required this.trip,
    required this.spentPaise,
    required this.byCategory,
    required this.daysLeft,
  });

  final Trip trip;
  final int spentPaise;
  final Map<String, int> byCategory;

  /// Days of the trip from today on, including today; 0 once it is over.
  final int daysLeft;

  int get leftPaise => trip.budgetPaise - spentPaise;

  /// What can be spent per remaining day to stay within budget.
  int? get perDayPaise =>
      daysLeft <= 0 || leftPaise <= 0 ? null : leftPaise ~/ daysLeft;
}

/// Expenses dated within the trip count towards it.
TripStatus tripStatus(Trip trip, Iterable<LedgerEntry> entries, DateTime now) {
  final range = trip.range;
  final today = _day(now);
  final daysLeft = today.isBefore(range.start)
      ? trip.days
      : today.isBefore(range.end)
          ? DateRange(today, range.end).days
          : 0;
  return TripStatus(
    trip: trip,
    spentPaise: sumEntries(entries, kind: EntryKind.expense, range: range),
    byCategory: categoryTotals(entries, range),
    daysLeft: daysLeft,
  );
}
