import 'models.dart';
import 'recurrence.dart';

/// Finding regular payments in the ledger, and recognising when a bank SMS
/// and a recurring rule describe the same payment. Everything here is a
/// suggestion; the user decides what is recorded.

// ---------------------------------------------------------------------------
// Matching a payment to a recurring rule

Set<String> _words(String value) => value
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.length >= 3 && !RegExp(r'^\d+$').hasMatch(word))
    .toSet();

/// Amounts that are the same payment: equal, or within 10% (salaries and
/// utility bills vary a little month to month).
bool closeAmount(int a, int b) {
  final gap = (a - b).abs();
  return gap <= 100 || gap * 10 <= (a > b ? a : b);
}

/// Whether [entry] is the payment a recurring rule expected on [due]:
/// same direction, within five days, and an equal amount, or a close amount
/// with a matching name (or any close income, since incomes are rare).
/// With [requireName], an expense must also share a word with the rule's
/// title even when the amount is equal.
bool matchesRecurring({
  required EntryKind kind,
  required int amountPaise,
  required String title,
  required DateTime due,
  required LedgerEntry entry,
  bool requireName = false,
}) {
  if (entry.kind != kind) return false;
  if (entry.occurredAt.difference(due).inHours.abs() > 5 * 24 + 12) {
    return false;
  }
  if (!closeAmount(entry.amountPaise, amountPaise)) return false;
  final named = _words(title)
      .intersection(_words('${entry.title} ${entry.merchant}'))
      .isNotEmpty;
  if (kind == EntryKind.income || named) return true;
  return !requireName && entry.amountPaise == amountPaise;
}

/// Monthly equivalent of an amount repeating on [repeat]. [interval] is the
/// number of days between occurrences for [Repeat.everyNDays].
int monthlyEquivalent(int paise, Repeat repeat, {int interval = 1}) =>
    switch (repeat) {
      Repeat.monthly => paise,
      Repeat.quarterly => paise ~/ 3,
      Repeat.yearly => paise ~/ 12,
      Repeat.weekly => paise * 52 ~/ 12,
      Repeat.daily => paise * 365 ~/ 12,
      Repeat.weekdays => paise * 261 ~/ 12,
      Repeat.everyNDays =>
        paise * 365 ~/ (12 * (interval <= 0 ? 1 : interval)),
      Repeat.none => 0,
    };

// ---------------------------------------------------------------------------
// Suggestions

/// A payment that has happened at a steady rhythm and is not yet a
/// recurring entry.
class RecurringSuggestion {
  const RecurringSuggestion({
    required this.key,
    required this.kind,
    required this.title,
    required this.category,
    required this.amountPaise,
    required this.repeat,
    required this.nextDate,
    required this.lastDate,
    required this.occurrences,
    required this.amountVaries,
    this.accountId,
    this.paymentMethod = 'Other',
  });

  /// Stable identity, used to remember "not recurring" answers.
  final String key;
  final EntryKind kind;
  final String title;
  final String category;

  /// The latest amount, or the typical one when it varies.
  final int amountPaise;
  final Repeat repeat;
  final DateTime nextDate;
  final DateTime lastDate;
  final int occurrences;
  final bool amountVaries;
  final String? accountId;
  final String paymentMethod;

  int get monthlyPaise => monthlyEquivalent(amountPaise, repeat);
}

const _rhythms = [
  (repeat: Repeat.weekly, days: 7, slack: 2, minCount: 4),
  (repeat: Repeat.monthly, days: 30, slack: 5, minCount: 3),
  (repeat: Repeat.quarterly, days: 91, slack: 10, minCount: 2),
  (repeat: Repeat.yearly, days: 365, slack: 15, minCount: 2),
];

/// Name used to group payments to the same payee: merchant if known,
/// otherwise the title, without numbers and short words.
String payeeKey(LedgerEntry entry) {
  final words = _words(entry.merchant.isNotEmpty ? entry.merchant : entry.title)
    ..removeAll(const {'upi', 'neft', 'imps', 'rtgs', 'ref', 'txn', 'payment'});
  return (words.toList()..sort()).join(' ');
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

T _mostCommon<T>(Iterable<T> values) {
  final counts = <T, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Payments in [entries] that repeat weekly, monthly, quarterly or yearly
/// at a steady amount and are not covered by one of [rules]. Needs four
/// weekly, three monthly or two quarterly/yearly occurrences; the latest
/// must be recent enough that the payment still looks active.
List<RecurringSuggestion> suggestRecurring({
  required Iterable<LedgerEntry> entries,
  required Iterable<RecurringEntry> rules,
  required DateTime now,
  Set<String> dismissed = const {},
  int limit = 6,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final since = today.subtract(const Duration(days: 800));
  final groups = <String, List<LedgerEntry>>{};
  for (final entry in entries) {
    if (entry.source == 'recurring' || entry.occurredAt.isBefore(since)) {
      continue;
    }
    if (entry.title.toLowerCase().startsWith('atm')) continue;
    final name = payeeKey(entry);
    if (name.isEmpty) continue;
    groups.putIfAbsent('${entry.kind.name}:$name', () => []).add(entry);
  }

  final suggestions = <RecurringSuggestion>[];
  for (final MapEntry(key: key, value: group) in groups.entries) {
    if (dismissed.contains(key) || group.length < 2) continue;
    // Keep payments near the typical amount: a one-off big order from a
    // shop you also pay monthly should not break the rhythm.
    final typical = _median([for (final entry in group) entry.amountPaise]);
    final steady = group
        .where((entry) => closeAmount(entry.amountPaise, typical))
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    // One payment per day at most.
    final days = <DateTime>[];
    final kept = <LedgerEntry>[];
    for (final entry in steady) {
      final day = DateTime(
          entry.occurredAt.year, entry.occurredAt.month, entry.occurredAt.day);
      if (days.isNotEmpty && days.last == day) continue;
      days.add(day);
      kept.add(entry);
    }
    if (kept.length < 2) continue;
    final gaps = [
      for (var i = 1; i < days.length; i++)
        days[i].difference(days[i - 1]).inHours ~/ 24,
    ];
    final gap = _median(gaps);
    final rhythm = _rhythms
        .where((item) => (gap - item.days).abs() <= item.slack)
        .firstOrNull;
    if (rhythm == null || kept.length < rhythm.minCount) continue;
    final onBeat = gaps
        .where((value) => (value - rhythm.days).abs() <= rhythm.slack)
        .length;
    if (onBeat * 4 < gaps.length * 3) continue;
    // Stopped? The last payment must be within one and a half periods.
    if (today.difference(days.last).inDays > rhythm.days * 3 ~/ 2) continue;

    final last = kept.last;
    final amounts = [for (final entry in kept) entry.amountPaise];
    final varies =
        amounts.any((value) => (value - last.amountPaise).abs() > 100);
    final amount = varies ? _median(amounts) : last.amountPaise;
    final recurrence = Recurrence(rhythm.repeat,
        anchorDay: rhythm.repeat == Repeat.weekly ? null : days.last.day);
    var next = days.last;
    for (var step = 0; step < 60 && next.isBefore(today); step++) {
      next = recurrence.next(next) ?? today;
    }
    if (next == days.last) next = recurrence.next(next) ?? today;

    final covered = rules.any((rule) =>
        rule.kind == last.kind &&
        (_words(rule.title)
                .intersection(_words('${last.title} ${last.merchant}'))
                .isNotEmpty ||
            (rule.recurrence.repeat == rhythm.repeat &&
                closeAmount(rule.amountPaise, amount))));
    if (covered) continue;

    suggestions.add(RecurringSuggestion(
      key: key,
      kind: last.kind,
      title: last.title,
      category: _mostCommon(kept.map((entry) => entry.category)),
      amountPaise: amount,
      repeat: rhythm.repeat,
      nextDate: next,
      lastDate: days.last,
      occurrences: kept.length,
      amountVaries: varies,
      accountId: last.accountId,
      paymentMethod: last.paymentMethod,
    ));
  }
  suggestions.sort((a, b) {
    final byCount = b.occurrences.compareTo(a.occurrences);
    return byCount != 0 ? byCount : b.monthlyPaise.compareTo(a.monthlyPaise);
  });
  return suggestions.take(limit).toList();
}
