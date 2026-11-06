import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/core/recurring_detect.dart';

final _now = DateTime(2026, 10, 30, 10);

LedgerEntry _entry(String title, int paise, DateTime at,
        {EntryKind kind = EntryKind.expense, String category = 'Other'}) =>
    LedgerEntry(
      id: '$title-$at',
      kind: kind,
      amountPaise: paise,
      category: category,
      title: title,
      merchant: title.toUpperCase(),
      occurredAt: at,
      source: 'sms',
    );

void main() {
  final netflix = [
    for (final month in [7, 8, 9, 10])
      _entry('Netflix', 64900, DateTime(2026, month, 5, 8),
          category: 'Entertainment'),
  ];

  group('suggestRecurring', () {
    test('finds a monthly subscription and its next date', () {
      final suggestion = suggestRecurring(
              entries: netflix, rules: const [], now: _now)
          .single;
      expect(suggestion.title, 'Netflix');
      expect(suggestion.repeat, Repeat.monthly);
      expect(suggestion.amountPaise, 64900);
      expect(suggestion.amountVaries, isFalse);
      expect(suggestion.occurrences, 4);
      expect(suggestion.category, 'Entertainment');
      expect(suggestion.lastDate, DateTime(2026, 10, 5));
      expect(suggestion.nextDate, DateTime(2026, 11, 5));
    });

    test('a varying salary is suggested at its typical amount', () {
      final salary = [
        _entry('ACME TECH', 5000000, DateTime(2026, 7, 31),
            kind: EntryKind.income),
        _entry('ACME TECH', 5000000, DateTime(2026, 8, 29),
            kind: EntryKind.income),
        _entry('ACME TECH', 5200000, DateTime(2026, 9, 30),
            kind: EntryKind.income),
        _entry('ACME TECH', 5100000, DateTime(2026, 10, 30),
            kind: EntryKind.income),
      ];
      final suggestion = suggestRecurring(
              entries: salary, rules: const [], now: _now)
          .single;
      expect(suggestion.kind, EntryKind.income);
      expect(suggestion.amountVaries, isTrue);
      expect(suggestion.amountPaise, 5100000);
      expect(suggestion.nextDate, DateTime(2026, 11, 30));
    });

    test('irregular spending, stopped payments and one-offs are not', () {
      final entries = [
        // Food orders on random days.
        for (final (day, paise) in [
          (1, 25000),
          (3, 40000),
          (10, 18000),
          (22, 32000),
          (29, 30000),
        ])
          _entry('Swiggy', paise, DateTime(2026, 10, day)),
        // A gym membership that stopped in June.
        for (final month in [3, 4, 5, 6])
          _entry('Gym', 150000, DateTime(2026, month, 1)),
        // Two payments only: not enough for monthly.
        _entry('Insurance', 90000, DateTime(2026, 9, 12)),
        _entry('Insurance', 90000, DateTime(2026, 10, 12)),
      ];
      expect(suggestRecurring(entries: entries, rules: const [], now: _now),
          isEmpty);
    });

    test('a big one-off at the same shop does not break the rhythm', () {
      final entries = [
        ...netflix,
        _entry('Netflix', 1200000, DateTime(2026, 9, 20)),
      ];
      final suggestion =
          suggestRecurring(entries: entries, rules: const [], now: _now)
              .single;
      expect(suggestion.amountPaise, 64900);
    });

    test('covered by a rule or dismissed: no suggestion', () {
      final rule = RecurringEntry(
        id: 'r1',
        kind: EntryKind.expense,
        amountPaise: 64900,
        category: 'Entertainment',
        title: 'Netflix subscription',
        recurrence: const Recurrence(Repeat.monthly),
        nextDate: DateTime(2026, 11, 5),
      );
      expect(suggestRecurring(entries: netflix, rules: [rule], now: _now),
          isEmpty);
      final key = suggestRecurring(entries: netflix, rules: const [], now: _now)
          .single
          .key;
      expect(
          suggestRecurring(
              entries: netflix, rules: const [], now: _now, dismissed: {key}),
          isEmpty);
    });

    test('entries recorded from a recurring rule are not re-suggested', () {
      final fromRule = [
        for (final entry in netflix)
          LedgerEntry(
            id: entry.id,
            kind: entry.kind,
            amountPaise: entry.amountPaise,
            category: entry.category,
            title: entry.title,
            occurredAt: entry.occurredAt,
            source: 'recurring',
          ),
      ];
      expect(suggestRecurring(entries: fromRule, rules: const [], now: _now),
          isEmpty);
    });
  });

  group('matchesRecurring', () {
    final due = DateTime(2026, 11, 1, 9);
    bool matches(LedgerEntry entry,
            {String title = 'Rent', bool requireName = false}) =>
        matchesRecurring(
          kind: EntryKind.expense,
          amountPaise: 1500000,
          title: title,
          due: due,
          entry: entry,
          requireName: requireName,
        );

    test('same amount within five days matches', () {
      expect(matches(_entry('landlord@okaxis', 1500000, DateTime(2026, 10, 30))),
          isTrue);
      expect(matches(_entry('landlord@okaxis', 1500000, DateTime(2026, 11, 8))),
          isFalse, reason: 'too far from the due date');
    });

    test('a close amount needs the name for expenses', () {
      expect(matches(_entry('Rent Nov', 1550000, DateTime(2026, 11, 1))),
          isTrue);
      expect(matches(_entry('Shop', 1550000, DateTime(2026, 11, 1))), isFalse);
      expect(
          matches(_entry('Shop', 1500000, DateTime(2026, 11, 1)),
              requireName: true),
          isFalse);
    });

    test('closeAmount allows 10% or one rupee', () {
      expect(closeAmount(10000, 10100), isTrue);
      expect(closeAmount(100000, 110000), isTrue);
      expect(closeAmount(100000, 112000), isFalse);
    });
  });
}
