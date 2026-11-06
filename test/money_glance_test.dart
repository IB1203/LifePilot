import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/formatters.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/money_glance.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/features/money_glance_section.dart';
import 'package:lifepilot_ai/ui/theme.dart';

// The 10th of a 30-day month: 10 days elapsed, 20 to go.
final _now = DateTime(2026, 11, 10, 12);

LedgerEntry _spend(int rupees, DateTime at,
        {String category = 'Food', String? billId, String? source}) =>
    LedgerEntry(
      id: 'e$rupees$at',
      kind: EntryKind.expense,
      amountPaise: rupees * 100,
      category: category,
      title: category,
      occurredAt: at,
      billId: billId,
      source: source,
    );

LedgerEntry _income(int rupees, DateTime at) => LedgerEntry(
      id: 'i$rupees$at',
      kind: EntryKind.income,
      amountPaise: rupees * 100,
      category: 'Salary',
      title: 'Salary',
      occurredAt: at,
    );

Bill _bill(String name, int rupees, DateTime due,
        {List<BillPayment> payments = const []}) =>
    Bill(
      id: name,
      name: name,
      kind: BillKind.other,
      amountPaise: rupees * 100,
      nextDueAt: due,
      payments: payments,
    );

void main() {
  tearDown(() => MoneyFormat.hidden = false);

  group('available money and net worth', () {
    const savings = Account(
        id: 'a1',
        name: 'HDFC 1234',
        kind: AccountKind.bank,
        openingBalancePaise: 1000000);
    const card = Account(
        id: 'a2',
        name: 'Card',
        kind: AccountKind.card,
        openingBalancePaise: -300000);

    test('bank SMS balances win over recorded balances', () {
      final fromBank = availableMoney(
        bankBalances: [
          BankBalance(bank: 'HDFC Bank', paise: 2500000, at: _now),
          BankBalance(bank: 'SBI Card', paise: 9000000, at: _now, isLimit: true),
        ],
        accounts: const [savings],
        entries: const [],
        transfers: const [],
      )!;
      expect(fromBank.paise, 2500000, reason: 'card limits are not money');
      expect(fromBank.basis, contains('bank SMS'));
    });

    test('recorded balances of non-card accounts otherwise', () {
      final recorded = availableMoney(
        bankBalances: const [],
        accounts: const [savings, card],
        entries: [
          _spend(2000, _now).copyWith(accountId: 'a1'),
        ],
        transfers: const [],
      )!;
      expect(recorded.paise, 800000);
      expect(
          availableMoney(
              bankBalances: const [],
              accounts: const [],
              entries: const [],
              transfers: const []),
          isNull);
    });

    test('net worth includes card dues and goal savings', () {
      final worth = netWorth(
        accounts: const [savings, card],
        entries: const [],
        transfers: const [],
        goals: [
          SavingsGoal(
            id: 'g',
            name: 'Trip',
            targetPaise: 5000000,
            createdAt: _now,
            contributions: [
              GoalContribution(id: 'c', amountPaise: 200000, at: _now)
            ],
          ),
        ],
      )!;
      expect(worth.paise, 1000000 - 300000 + 200000);
    });
  });

  group('upcoming and forecast', () {
    test('commitments include overdue bills once and each weekly occurrence',
        () {
      final items = upcomingCommitments(
        bills: [
          _bill('Electricity', 1200, DateTime(2026, 11, 5)), // overdue
          _bill('Internet', 800, DateTime(2026, 11, 20)),
        ],
        rules: [
          RecurringEntry(
            id: 'r',
            kind: EntryKind.expense,
            amountPaise: 50000,
            category: 'Food',
            title: 'Milk',
            recurrence: const Recurrence(Repeat.weekly),
            nextDate: DateTime(2026, 11, 12),
          ),
          RecurringEntry(
            id: 's',
            kind: EntryKind.income,
            amountPaise: 5000000,
            category: 'Salary',
            title: 'Salary',
            recurrence: const Recurrence(Repeat.monthly),
            nextDate: DateTime(2026, 11, 30),
          ),
        ],
        now: _now,
        days: 14,
      );
      expect([for (final item in items) item.title], [
        'Electricity', // overdue, counted today
        'Milk', // 12 Nov
        'Milk', // 19 Nov
        'Internet', // 20 Nov
      ]);
      expect(items.first.due, DateTime(2026, 11, 10));
    });

    test('month-end forecast: day-to-day pace plus what is still due', () {
      final forecast = monthForecast(
        entries: [
          for (var day = 1; day <= 10; day++)
            _spend(300, DateTime(2026, 11, day, 9)),
          // Fixed payments are not part of the daily pace.
          _spend(15000, DateTime(2026, 11, 1), category: 'Rent', source: 'recurring'),
          // Last month does not count.
          _spend(9999, DateTime(2026, 10, 31)),
        ],
        bills: [_bill('Internet', 800, DateTime(2026, 11, 20))],
        rules: const [],
        now: _now,
      );
      expect(forecast.spentPaise, (3000 + 15000) * 100);
      expect(forecast.dailyPacePaise, 30000);
      expect(forecast.daysLeft, 20);
      expect(forecast.committedPaise, 80000);
      expect(forecast.projectedPaise, (18000 + 300 * 20 + 800) * 100);
    });

    test('budget forecast flags a category heading over its limit', () {
      final entries = [
        for (var day = 1; day <= 10; day++)
          _spend(200, DateTime(2026, 11, day, 9)),
      ];
      const budget = SpendingBudget(category: 'Food', limitPaise: 500000);
      final forecast = budgetForecast(budget, entries, _now)!;
      expect(forecast.projectedPaise, 600000);
      expect(forecast.willExceed, isTrue);
      expect(forecast.overPaise, 100000);
      expect(
          budgetForecast(
              const SpendingBudget(
                  category: 'Food',
                  limitPaise: 1,
                  period: BudgetPeriod.weekly),
              entries,
              _now),
          isNull);
    });

    test('safe to spend uses budgets when set, otherwise income', () {
      final entries = [
        _income(50000, DateTime(2026, 11, 1)),
        _spend(10000, DateTime(2026, 11, 2)),
      ];
      final fromBudgets = safeToSpendToday(
        entries: entries,
        budgets: const [SpendingBudget(category: 'Food', limitPaise: 3100000)],
        bills: const [],
        rules: const [],
        now: _now,
      )!;
      // ₹31,000 − ₹10,000 over 21 days including today.
      expect(fromBudgets.paise, 100000);
      expect(fromBudgets.basis, contains('Budgets'));

      final fromIncome = safeToSpendToday(
        entries: entries,
        budgets: const [],
        bills: [_bill('Internet', 1000, DateTime(2026, 11, 20))],
        rules: const [],
        now: _now,
      )!;
      // (₹50,000 − ₹10,000 − ₹1,000) / 21 days.
      expect(fromIncome.paise, 3900000 ~/ 21);
      expect(
          safeToSpendToday(
              entries: const [],
              budgets: const [],
              bills: const [],
              rules: const [],
              now: _now),
          isNull);
    });
  });

  test('categories compared with the same days last month', () {
    final changes = compareWithLastMonth([
      _spend(1000, DateTime(2026, 11, 3)),
      _spend(500, DateTime(2026, 10, 4)),
      _spend(9000, DateTime(2026, 10, 25)), // after day 10: not compared
      _spend(400, DateTime(2026, 11, 5), category: 'Transport'),
    ], _now);
    final food = changes.firstWhere((item) => item.category == 'Food');
    expect(food.thisMonthPaise, 100000);
    expect(food.lastMonthPaise, 50000);
    expect(food.changePercent, 100);
    final transport =
        changes.firstWhere((item) => item.category == 'Transport');
    expect(transport.changePercent, isNull);
    expect(changes.first.category, 'Food', reason: 'biggest change first');
  });

  group('health score', () {
    final threeMonths = [
      for (final month in [8, 9, 10]) ...[
        _income(50000, DateTime(2026, month, 1)),
        _spend(40000, DateTime(2026, month, 5)),
      ],
    ];

    test('averages the measurable factors and explains each', () {
      final score = healthScore(
        entries: threeMonths,
        budgets: const [],
        bills: [
          _bill('Internet', 800, DateTime(2026, 12, 1), payments: [
            BillPayment(
                id: 'p1',
                dueAt: DateTime(2026, 10, 1),
                paidAt: DateTime(2026, 10, 1, 20),
                amountPaise: 80000),
            BillPayment(
                id: 'p2',
                dueAt: DateTime(2026, 11, 1),
                paidAt: DateTime(2026, 11, 4),
                amountPaise: 80000),
          ]),
        ],
        goals: [
          SavingsGoal(
            id: 'g',
            name: 'Emergency',
            targetPaise: 12000000,
            createdAt: _now,
            type: GoalType.emergency,
            contributions: [
              GoalContribution(id: 'c', amountPaise: 6000000, at: _now)
            ],
          ),
        ],
        now: _now,
      )!;
      final byName = {for (final f in score.factors) f.name: f};
      // Kept 20% of income: full marks.
      expect(byName['Savings rate']!.score, 1.0);
      // ₹60,000 saved vs ₹40,000/month: 1.5 of 3 months.
      expect(byName['Emergency fund']!.score, closeTo(0.5, 0.001));
      expect(byName['Bills on time']!.score, 0.5);
      expect(byName.containsKey('Budgets'), isFalse);
      expect(score.value, 67);
      expect(score.label, 'Fair');
    });

    test('needs at least two measurable factors', () {
      expect(
          healthScore(
              entries: const [],
              budgets: const [],
              bills: const [],
              goals: const [],
              now: _now),
          isNull);
    });
  });

  group('hide amounts and dashboard', () {
    test('amounts are masked on screen but not when revealed', () {
      MoneyFormat.hidden = true;
      expect(formatMoney(12345), '₹••••');
      expect(formatMoney(12345, reveal: true), '₹123.45');
    });

    test('a new section appears at its default place for existing users', () {
      expect(orderedSections(['today', 'finance', 'recent']).take(3),
          ['glance', 'today', 'finance']);
      expect(orderedSections(['recent', 'glance']).first, 'recent');
    });

    testWidgets('glance shows figures and toggles hidden amounts',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addEntry(
          kind: EntryKind.income,
          amountPaise: 5000000,
          category: 'Salary',
          title: 'Salary',
          occurredAt: DateTime(2026, 11, 1));
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 300000,
          category: 'Food',
          title: 'Groceries',
          occurredAt: DateTime(2026, 11, 2));
      await tester.pumpWidget(ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: ListView(children: [
              MoneyGlanceSection(store: store, now: _now, onOpen: () {}),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Your money at a glance'), findsOneWidget);
      expect(find.text('₹3,000.00'), findsOneWidget);
      expect(find.text('Safe to spend today'), findsOneWidget);
      expect(find.text('Health score: not enough data yet'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      expect(store.settings.hideAmounts, isTrue);
      expect(find.text('₹3,000.00'), findsNothing);
      expect(find.text('₹••••'), findsWidgets);

      await tester.tap(find.text('Health score: not enough data yet'));
      await tester.pumpAndSettle();
      expect(find.text('Financial health score'), findsOneWidget);
    });
  });
}
