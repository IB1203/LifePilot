import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/cash_plan.dart';
import 'package:lifepilot_ai/core/investments.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/money_glance.dart';
import 'package:lifepilot_ai/features/investments_tab.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 11, 10, 12);

void main() {
  group('deposits', () {
    test('FD grows with quarterly compounding', () {
      // ₹1 lakh at 7% for a year: (1 + 0.07/4)^4.
      expect(fdValue(10000000, 7, DateTime(2026, 1, 1), DateTime(2027, 1, 1)),
          10718590);
      expect(fdValue(10000000, 7, DateTime(2026, 1, 1), DateTime(2026, 7, 2)),
          10352078);
      expect(fdValue(10000000, 7, DateTime(2026, 1, 1), DateTime(2025, 1, 1)),
          10000000);
    });

    test('RD: each monthly instalment grows from its own date', () {
      final start = DateTime(2026, 1, 1);
      final maturity = DateTime(2027, 1, 1);
      expect(rdInstallments(start, maturity, maturity), hasLength(12));
      expect(rdValue(500000, 6, start, maturity, maturity), 6198418);
      final rd = Investment(
        id: 'rd',
        name: 'Post office RD',
        kind: InvestmentKind.recurringDeposit,
        annualRatePercent: 6,
        startDate: start,
        maturityDate: maturity,
        installmentPaise: 500000,
      );
      expect(maturityValue(rd), 6198418);
      // By 10 Nov 2026, eleven instalments are in.
      expect(investedPaise(rd, _now), 11 * 500000);
    });

    test('a matured FD stops growing', () {
      final fd = Investment(
        id: 'fd',
        name: 'SBI FD',
        kind: InvestmentKind.fixedDeposit,
        annualRatePercent: 7,
        startDate: DateTime(2025, 1, 1),
        maturityDate: DateTime(2026, 1, 1),
        flows: [
          InvestmentFlow(
              id: '1', amountPaise: 10000000, at: DateTime(2025, 1, 1)),
        ],
      );
      expect(currentValue(fd, _now)!.paise, maturityValue(fd));
      expect(currentValue(fd, _now)!.basis, contains('7.0%'));
    });
  });

  group('returns and portfolio', () {
    test('XIRR of +10% over exactly a year is 10%', () {
      final rate = xirr([
        InvestmentFlow(id: '1', amountPaise: 10000000, at: DateTime(2025, 1, 1)),
      ], 11000000, DateTime(2026, 1, 1));
      expect(rate, closeTo(0.10, 0.0005));
      expect(
          xirr([
            InvestmentFlow(id: '1', amountPaise: 100, at: DateTime(2026, 11, 8)),
          ], 120, _now),
          isNull,
          reason: 'under a week of history');
    });

    test('totals, gain and allocation; values without a date say so', () {
      final book = portfolio([
        Investment(
          id: 'mf',
          name: 'Index fund',
          kind: InvestmentKind.mutualFund,
          flows: [
            InvestmentFlow(
                id: '1', amountPaise: 5000000, at: DateTime(2025, 11, 10)),
          ],
          valuePaise: 6000000,
          valueAsOf: DateTime(2026, 11, 1),
        ),
        Investment(
          id: 'gold',
          name: 'Gold coins',
          kind: InvestmentKind.gold,
          flows: [
            InvestmentFlow(
                id: '1', amountPaise: 2000000, at: DateTime(2024, 1, 1)),
          ],
        ),
        const Investment(
            id: 'old', name: 'Sold', kind: InvestmentKind.stock, closed: true),
      ], _now);
      expect(book.lines, hasLength(2));
      expect(book.investedPaise, 7000000);
      // Gold has no value yet: counted at cost.
      expect(book.valuePaise, 8000000);
      expect(book.gainPaise, 1000000);
      expect(book.allocation.first.kind, InvestmentKind.mutualFund);
      expect(book.lines.first.value!.basis, contains('1 Nov 2026'));
      expect(book.lines.first.xirr, closeTo(0.2, 0.001));
      expect(book.lines.last.gainPaise, isNull);
    });
  });

  group('SIPs and reminders', () {
    const fund = Investment(
      id: 'mf',
      name: 'Index fund',
      kind: InvestmentKind.mutualFund,
      sipPaise: 500000,
      sipDay: 31,
    );

    test('SIP dates fall on the last day in short months', () {
      final dates =
          sipDates([fund], DateTime(2026, 11, 1), DateTime(2027, 1, 31));
      expect([for (final item in dates) item.day], [
        DateTime(2026, 11, 30),
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 31),
      ]);
      final events = moneyEvents(
        bills: const [],
        rules: const [],
        goals: const [],
        investments: [fund],
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 30),
      );
      expect(events.single.title, 'SIP · Index fund');
      expect(events.single.flowPaise, -500000);
    });

    test('maturity reminders a week before and on the day', () {
      final fd = Investment(
        id: 'fd',
        name: 'SBI FD',
        kind: InvestmentKind.fixedDeposit,
        annualRatePercent: 7,
        startDate: DateTime(2025, 11, 25),
        maturityDate: DateTime(2026, 11, 25),
        flows: [
          InvestmentFlow(
              id: '1', amountPaise: 10000000, at: DateTime(2025, 11, 25)),
        ],
      );
      final reminders = maturityReminders([fd], _now);
      expect([for (final item in reminders) item.at], [
        DateTime(2026, 11, 18, 9),
        DateTime(2026, 11, 25, 9),
      ]);
      expect(reminders.last.body, startsWith('Matures today · about'));
    });
  });

  group('store', () {
    test('money in and out moves the entered value; reminders scheduled',
        () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      final fund = await store.addInvestment(
        name: 'Index fund',
        kind: InvestmentKind.mutualFund,
        startDate: DateTime(2025, 11, 10),
        investedPaise: 5000000,
        valuePaise: 6000000,
      );
      await store.addInvestmentFlow(fund.id, 1000000);
      expect(store.investments.single.valuePaise, 7000000);
      await store.addInvestmentFlow(fund.id, -500000);
      expect(store.investments.single.valuePaise, 6500000);
      await store.setInvestmentValue(fund.id, 6600000);
      expect(store.investments.single.valueAsOf, _now);

      await store.addInvestment(
        name: 'SBI FD',
        kind: InvestmentKind.fixedDeposit,
        startDate: DateTime(2025, 11, 25),
        investedPaise: 10000000,
        annualRatePercent: 7,
        maturityDate: DateTime(2026, 11, 25),
      );
      expect(
          store
              .notificationPlan()
              .where((item) => item.payload.startsWith('investment:')),
          hasLength(2));

      final copy = LifePilotStore.inMemory(clock: () => _now);
      await copy.restoreJson(store.exportJson());
      expect(copy.investments, hasLength(2));
      expect(copy.investments.first.flows, hasLength(3));

      final worth = netWorth(
        accounts: const [],
        entries: const [],
        transfers: const [],
        goals: const [],
        investmentsPaise: portfolio(store.investments, _now).valuePaise,
      )!;
      expect(worth.basis, contains('investments'));
    });
  });

  testWidgets('investments tab shows totals, holdings and SIPs',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addInvestment(
      name: 'Index fund',
      kind: InvestmentKind.mutualFund,
      startDate: DateTime(2025, 11, 10),
      investedPaise: 5000000,
      valuePaise: 6000000,
      sipPaise: 500000,
      sipDay: 15,
    );
    await tester.pumpWidget(ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: InvestmentsTab(store: store)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Index fund'), findsWidgets);
    expect(find.text('Gain'), findsOneWidget);
    expect(find.textContaining('(XIRR)'), findsOneWidget);
    await tester.tap(find.byTooltip('Investment options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update value'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '65000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.investments.single.valuePaise, 6500000);
    await tester.scrollUntilVisible(find.text('SIPs in the next 30 days'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('SIPs in the next 30 days'), findsOneWidget);
  });
}
