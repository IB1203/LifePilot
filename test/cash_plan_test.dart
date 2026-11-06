import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/cash_plan.dart';
import 'package:lifepilot_ai/core/insights.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/features/plan_tab.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 11, 10, 12);

Bill _bill(String name, int rupees, DateTime due,
        {BillKind kind = BillKind.other,
        Recurrence recurrence = const Recurrence(Repeat.monthly),
        List<BillPayment> payments = const []}) =>
    Bill(
      id: name,
      name: name,
      kind: kind,
      amountPaise: rupees * 100,
      nextDueAt: due,
      recurrence: recurrence,
      payments: payments,
    );

RecurringEntry _rule(String title, int rupees, DateTime next,
        {EntryKind kind = EntryKind.expense,
        String category = 'Bills',
        Repeat repeat = Repeat.monthly}) =>
    RecurringEntry(
      id: title,
      kind: kind,
      amountPaise: rupees * 100,
      category: category,
      title: title,
      recurrence: Recurrence(repeat),
      nextDate: next,
    );

LedgerEntry _spend(int rupees, DateTime at,
        {String title = 'Food', String? source}) =>
    LedgerEntry(
      id: '$title$at',
      kind: EntryKind.expense,
      amountPaise: rupees * 100,
      category: 'Food',
      title: title,
      occurredAt: at,
      source: source,
    );

void main() {
  test('money calendar lists bills, recurring items and goal dates', () {
    final events = moneyEvents(
      bills: [_bill('Internet', 800, DateTime(2026, 11, 20))],
      rules: [
        _rule('Salary', 50000, DateTime(2026, 11, 30),
            kind: EntryKind.income, category: 'Salary'),
        _rule('Milk', 500, DateTime(2026, 11, 3), repeat: Repeat.weekly),
      ],
      goals: [
        SavingsGoal(
            id: 'g',
            name: 'Laptop',
            targetPaise: 6000000,
            createdAt: _now,
            targetDate: DateTime(2026, 11, 25)),
      ],
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
    );
    expect([for (final event in events) '${event.day.day} ${event.title}'], [
      '3 Milk',
      '10 Milk',
      '17 Milk',
      '20 Internet',
      '24 Milk',
      '25 Laptop target',
      '30 Salary',
    ]);
    expect(events.last.flowPaise, 5000000);
    expect(events[3].flowPaise, -80000);
    expect(events[5].flowPaise, 0);
  });

  group('cash-flow forecast', () {
    test('balance moves with scheduled items and usual spending', () {
      final forecast = forecastCash(
        startPaise: 1000000,
        entries: [
          // ₹3,000 of day-to-day spending in the last 30 days: ₹100/day.
          for (var day = 1; day <= 30; day++)
            _spend(100, DateTime(2026, 10, 11).add(Duration(days: day - 1))),
          // Recurring payments are not counted in the daily figure.
          _spend(15000, DateTime(2026, 11, 1), source: 'recurring'),
        ],
        bills: [_bill('Rent', 15000, DateTime(2026, 11, 15))],
        rules: [
          _rule('Salary', 50000, DateTime(2026, 11, 30),
              kind: EntryKind.income, category: 'Salary'),
        ],
        now: _now,
        days: 30,
      );
      expect(forecast.dailySpendPaise, 10000);
      expect(forecast.balances.first, 1000000 - 10000);
      // 15 Nov is index 5: six days of spending and the rent.
      expect(forecast.balances[5], 1000000 - 60000 - 1500000);
      expect(forecast.shortfallDay, DateTime(2026, 11, 15));
      expect(forecast.lowestDay, DateTime(2026, 11, 29));
      // 30 Nov: salary arrives.
      expect(forecast.balances[20],
          1000000 - 210000 - 1500000 + 5000000);
    });

    test('without a known balance it shows the change from today', () {
      final forecast = forecastCash(
        startPaise: null,
        entries: const [],
        bills: [_bill('Old bill', 500, DateTime(2026, 11, 1))],
        rules: const [],
        now: _now,
        days: 3,
      );
      expect(forecast.startKnown, isFalse);
      expect(forecast.balances, [-50000, -50000, -50000],
          reason: 'an overdue bill is taken today');
    });
  });

  group('subscriptions and price increases', () {
    test('subscription bills and look-alike recurring expenses', () {
      final items = subscriptions([
        _bill('Spotify', 119, DateTime(2026, 11, 20),
            kind: BillKind.subscription),
        _bill('Electricity', 1200, DateTime(2026, 11, 20)),
        _bill('Prime', 1499, DateTime(2027, 2, 1),
            recurrence: const Recurrence(Repeat.yearly)),
      ], [
        _rule('Netflix', 649, DateTime(2026, 12, 5), category: 'Entertainment'),
        _rule('Rent', 15000, DateTime(2026, 12, 1)),
      ]);
      expect([for (final item in items) item.name],
          ['Netflix', 'Prime', 'Spotify']);
      expect(items[1].monthlyPaise, 149900 ~/ 12);
      expect(items.first.yearlyPaise, 64900 * 12);
    });

    test('a bill or recurring payment that went up is reported', () {
      final bills = [
        _bill('Internet', 899, DateTime(2026, 12, 1), payments: [
          BillPayment(
              id: '1',
              dueAt: DateTime(2026, 10, 1),
              paidAt: DateTime(2026, 10, 1),
              amountPaise: 79900),
          BillPayment(
              id: '2',
              dueAt: DateTime(2026, 11, 1),
              paidAt: DateTime(2026, 11, 1),
              amountPaise: 89900),
        ]),
      ];
      final rules = [_rule('Netflix', 699, DateTime(2026, 12, 5))];
      final entries = [
        _spend(649, DateTime(2026, 10, 5), title: 'Netflix', source: 'recurring'),
        _spend(699, DateTime(2026, 11, 5), title: 'Netflix', source: 'recurring'),
        // Same title but typed in by hand: not a recurring payment.
        _spend(999, DateTime(2026, 11, 6), title: 'Netflix'),
      ];
      final changes = priceIncreases(
          bills: bills, rules: rules, entries: entries, now: _now);
      expect([for (final c in changes) '${c.name} ${c.percent}%'],
          ['Netflix 8%', 'Internet 13%']);

      final insights = buildInsights(
        entries: entries,
        budgets: const [],
        bills: bills,
        goals: const [],
        now: _now,
        rules: rules,
      );
      expect(insights.map((item) => item.title),
          containsAll(['Netflix went up 8%', 'Internet went up 13%']));
    });

    test('decreases and old changes are not reported', () {
      final entries = [
        _spend(699, DateTime(2026, 6, 5), title: 'Gym', source: 'recurring'),
        _spend(649, DateTime(2026, 7, 5), title: 'Gym', source: 'recurring'),
      ];
      expect(
          priceIncreases(
              bills: const [],
              rules: [_rule('Gym', 649, DateTime(2026, 12, 5))],
              entries: entries,
              now: _now),
          isEmpty);
    });
  });

  group('salary plan', () {
    test('splits recurring income into commitments, goals, fund, spending',
        () {
      final plan = salaryPlan(
        entries: [
          for (final month in [8, 9, 10])
            _spend(20000, DateTime(2026, month, 10)),
        ],
        rules: [
          _rule('Salary', 60000, DateTime(2026, 11, 30),
              kind: EntryKind.income, category: 'Salary'),
          _rule('Rent', 15000, DateTime(2026, 12, 1)),
        ],
        bills: [
          _bill('Insurance', 12000, DateTime(2027, 3, 1),
              recurrence: const Recurrence(Repeat.yearly)),
        ],
        budgets: const [],
        goals: [
          SavingsGoal(
            id: 'g',
            name: 'Laptop',
            targetPaise: 6000000,
            createdAt: _now,
            targetDate: DateTime(2027, 9, 10),
          ),
        ],
        now: _now,
      )!;
      expect(plan.incomePaise, 6000000);
      expect(plan.incomeBasis, contains('Salary'));
      final lines = {for (final line in plan.lines) line.label: line.amountPaise};
      expect(lines['Bills and recurring payments'], 1500000 + 100000);
      expect(lines['Savings goals'], 600000);
      expect(lines['Emergency fund'], 600000);
      expect(lines['Day-to-day spending'], 2000000);
      expect(plan.leftPaise, 6000000 - 1600000 - 600000 - 600000 - 2000000);
    });

    test('no income known: no plan', () {
      expect(
          salaryPlan(
              entries: const [],
              rules: const [],
              bills: const [],
              budgets: const [],
              goals: const [],
              now: _now),
          isNull);
    });
  });

  testWidgets('plan tab shows forecast, calendar, plan and subscriptions',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addRecurring(
      kind: EntryKind.income,
      amountPaise: 6000000,
      category: 'Salary',
      title: 'Salary',
      recurrence: const Recurrence(Repeat.monthly),
      firstDate: DateTime(2026, 11, 30),
    );
    await store.addRecurring(
      kind: EntryKind.expense,
      amountPaise: 64900,
      category: 'Entertainment',
      title: 'Netflix',
      recurrence: const Recurrence(Repeat.monthly),
      firstDate: DateTime(2026, 11, 12),
    );
    await tester.pumpWidget(ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: PlanTab(store: store)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Cash flow, next 60 days'), findsOneWidget);
    expect(find.text('Money calendar'), findsOneWidget);
    expect(find.text('Nothing scheduled on 10 Nov 2026.'), findsOneWidget);
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.text('Recurring payment'), findsOneWidget);
    await tester.ensureVisible(find.text('30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Expected income'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Expected income'), findsOneWidget);

    final subs = find.text('Subscriptions');
    await tester.scrollUntilVisible(subs, 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Salary plan'), findsOneWidget);
    expect(find.text('Per month'), findsOneWidget);
  });
}
