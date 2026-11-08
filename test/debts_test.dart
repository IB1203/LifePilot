import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/debts.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/money_glance.dart';
import 'package:lifepilot_ai/features/debts_tab.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 11, 10, 12);

Debt _debt(String name, int rupees,
        {double rate = 0,
        int emiRupees = 0,
        DebtKind kind = DebtKind.loan,
        List<DebtPayment> payments = const []}) =>
    Debt(
      id: name,
      name: name,
      kind: kind,
      openingPaise: rupees * 100,
      startDate: DateTime(2026, 1, 1),
      annualRatePercent: rate,
      emiPaise: emiRupees * 100,
      payments: payments,
    );

void main() {
  group('interest and EMI', () {
    test('EMI formula matches the standard loan EMI', () {
      // ₹10 lakh at 10% for 12 months: ₹87,915.89.
      expect(emiFor(100000000, 10, 12), 8791589);
      expect(emiFor(120000, 0, 12), 10000);
    });

    test('payments pay interest since the last payment, then principal', () {
      final status = debtStatus(_debt('Car', 100000, rate: 12, payments: [
        DebtPayment(id: '2', amountPaise: 1000000, at: DateTime(2026, 3, 2)),
        DebtPayment(id: '1', amountPaise: 1000000, at: DateTime(2026, 1, 31)),
      ]), asOf: DateTime(2026, 3, 2));
      // 30 days at 12% on ₹1,00,000 is ₹986.30; then ₹897.40 on the rest.
      expect(status.interestPaidPaise, 98630 + 89740);
      expect(status.principalPaidPaise, 2000000 - 188370);
      expect(status.outstandingPaise, 8188370);
    });

    test('a payment smaller than the interest leaves the rest owed', () {
      final status = debtStatus(_debt('Car', 100000, rate: 12, payments: [
        DebtPayment(id: '1', amountPaise: 50000, at: DateTime(2026, 1, 31)),
      ]), asOf: DateTime(2026, 1, 31));
      expect(status.principalPaidPaise, 0);
      expect(status.outstandingPaise, 10000000 + 98630 - 50000);
    });

    test('payoff: months, interest to go, and loans that never close', () {
      final plan = payoff(100000000, 10, 8791589, _now)!;
      expect(plan.months, 12);
      expect(plan.interestPaise, closeTo(5499065, 2));
      expect(plan.closesOn, DateTime(2027, 11, 10));
      expect(payoff(120000, 0, 10000, _now)!.interestPaise, 0);
      // 24% on ₹1 lakh is ₹2,000 a month; ₹1,000 never catches up.
      expect(payoff(10000000, 24, 100000, _now), isNull);
    });

    test('credit card minimum due: 5% of the balance, at least ₹200', () {
      final card = _debt('Card', 10000, kind: DebtKind.creditCard);
      expect(monthlyPaymentFor(card, 1000000), 50000);
      expect(monthlyPaymentFor(card, 100000), 20000);
      expect(monthlyPaymentFor(card, 10000), 10000);
      expect(monthlyPaymentFor(_debt('Friend', 500), 50000), 0);
    });
  });

  group('debt-free planner', () {
    final debts = [
      _debt('Phone EMI', 30000, emiRupees: 1000),
      _debt('Card', 50000,
          rate: 24, emiRupees: 2000, kind: DebtKind.creditCard),
      _debt('Lent to Ravi', 9000, kind: DebtKind.lent),
    ];

    test('snowball clears the smallest first, avalanche the costliest', () {
      final snowball =
          debtFreePlan(debts, PayoffStrategy.snowball, extraPaise: 300000)!;
      final avalanche =
          debtFreePlan(debts, PayoffStrategy.avalanche, extraPaise: 300000)!;
      expect(snowball.order, ['Phone EMI', 'Card']);
      expect(avalanche.order, ['Card', 'Phone EMI']);
      expect(avalanche.interestPaise, lessThan(snowball.interestPaise));
      expect(avalanche.months, lessThanOrEqualTo(snowball.months));
    });

    test('paying extra is faster; too little never finishes', () {
      final base = debtFreePlan(debts, PayoffStrategy.avalanche)!;
      final extra =
          debtFreePlan(debts, PayoffStrategy.avalanche, extraPaise: 300000)!;
      expect(extra.months, lessThan(base.months));
      expect(extra.interestPaise, lessThan(base.interestPaise));
      expect(
          debtFreePlan([_debt('Card', 50000, rate: 24, emiRupees: 500)],
              PayoffStrategy.avalanche),
          isNull);
      expect(debtFreePlan(const [], PayoffStrategy.snowball)!.months, 0);
    });
  });

  test('totals, net worth and the debt part of the health score', () {
    final totals = debtTotals([
      _debt('Phone EMI', 30000, emiRupees: 1000),
      _debt('Lent to Ravi', 9000, kind: DebtKind.lent),
      _debt('Old', 5000, emiRupees: 500).copyWith(closed: true),
    ]);
    expect(totals.owedPaise, 3000000);
    expect(totals.lentPaise, 900000);
    expect(totals.monthlyPaise, 100000);

    final worth = netWorth(
      accounts: const [],
      entries: const [],
      transfers: const [],
      goals: const [],
      debtsPaise: totals.owedPaise,
      lentPaise: totals.lentPaise,
    )!;
    expect(worth.paise, 900000 - 3000000);

    final entries = [
      for (final month in [8, 9, 10]) ...[
        LedgerEntry(
            id: 'i$month',
            kind: EntryKind.income,
            amountPaise: 5000000,
            category: 'Salary',
            title: 'Salary',
            occurredAt: DateTime(2026, month, 1)),
        LedgerEntry(
            id: 'e$month',
            kind: EntryKind.expense,
            amountPaise: 4000000,
            category: 'Food',
            title: 'Food',
            occurredAt: DateTime(2026, month, 2)),
      ],
    ];
    final score = healthScore(
      entries: entries,
      budgets: const [],
      bills: const [],
      goals: const [],
      now: _now,
      monthlyDebtPaise: 2000000,
    )!;
    final factor =
        score.factors.firstWhere((item) => item.name == 'Debt payments');
    // 40% of income: two thirds of the way from 60% to 30%.
    expect(factor.score, closeTo(2 / 3, 0.001));
  });

  group('store', () {
    test('payments can be recorded as expenses and close the debt', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      final debt = await store.addDebt(
        name: 'Phone',
        kind: DebtKind.loan,
        openingPaise: 200000,
        startDate: DateTime(2026, 10, 1),
        emiPaise: 100000,
      );
      await store.addDebtPayment(debt.id,
          amountPaise: 100000, recordExpense: true);
      expect(store.entries.single.category, 'Loans');
      expect(store.entries.single.title, 'Phone EMI');
      final closed = await store.addDebtPayment(debt.id, amountPaise: 100000);
      expect(closed.closed, isTrue);
      expect(store.entries, hasLength(1));

      final copy = LifePilotStore.inMemory(clock: () => _now);
      await copy.restoreJson(store.exportJson());
      expect(copy.debts.single.payments, hasLength(2));
      expect(copy.debts.single.closed, isTrue);
    });

    test('splitting a bill records my share and lends the rest', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.splitBill(
        title: 'Dinner',
        totalPaise: 100000,
        people: ['Asha', ' Ravi ', ''],
        category: 'Food',
      );
      expect(store.entries.single.amountPaise, 33334);
      expect(store.debts, hasLength(2));
      expect(store.debts.map((debt) => debt.counterparty), ['Asha', 'Ravi']);
      expect(store.debts.every((debt) => debt.openingPaise == 33333), isTrue);
      expect(store.debts.every((debt) => debt.owedToMe), isTrue);
    });
  });

  testWidgets('debts tab shows the planner and records a payment',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addDebt(
      name: 'Bike loan',
      kind: DebtKind.loan,
      openingPaise: 6000000,
      startDate: DateTime(2026, 11, 1),
      annualRatePercent: 9,
      emiPaise: 500000,
    );
    await tester.pumpWidget(ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: DebtsTab(store: store)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Bike loan'), findsOneWidget);
    expect(find.textContaining('clears it in'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Debt-free planner'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Debt-free planner'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Record payment'), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save payment'));
    await tester.pumpAndSettle();
    expect(store.debts.single.payments.single.amountPaise, 500000);
    expect(store.entries.single.category, 'Loans');
  });
}
