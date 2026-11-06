import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/finance_calc.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/spending_habits.dart';
import 'package:lifepilot_ai/core/vault.dart';
import 'package:lifepilot_ai/features/spending_habits_section.dart';
import 'package:lifepilot_ai/features/vault_page.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 11, 10, 12);

LedgerEntry _spend(int rupees, DateTime at,
        {String category = 'Food',
        String subcategory = '',
        String? source,
        String? billId}) =>
    LedgerEntry(
      id: '$rupees$at$category$subcategory',
      kind: EntryKind.expense,
      amountPaise: rupees * 100,
      category: category,
      title: category,
      subcategory: subcategory,
      occurredAt: at,
      source: source,
      billId: billId,
    );

void main() {
  group('subcategories', () {
    test('saved, suggested by use, and totalled', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      for (final (sub, rupees) in [
        ('Restaurants', 500),
        ('Restaurants', 300),
        ('Groceries', 900),
        ('', 100),
      ]) {
        await store.addEntry(
            kind: EntryKind.expense,
            amountPaise: rupees * 100,
            category: 'Food',
            title: 'Food',
            subcategory: sub,
            occurredAt: DateTime(2026, 11, 5));
      }
      expect(store.subcategoriesOf('Food'), ['Restaurants', 'Groceries']);
      expect(subcategoryTotals(store.entries, monthRange(_now), 'Food'),
          {'Groceries': 90000, 'Restaurants': 80000, 'Other': 10000});
      final restored = LifePilotStore.inMemory(clock: () => _now);
      await restored.restoreJson(store.exportJson());
      expect(restored.entries.first.subcategory, 'Restaurants');
    });
  });

  group('spending habits', () {
    test('no-spend days ignore bills, recurring payments and EMIs', () {
      final entries = [
        _spend(100, DateTime(2026, 11, 2)),
        _spend(100, DateTime(2026, 11, 5)),
        _spend(100, DateTime(2026, 11, 9)),
        _spend(15000, DateTime(2026, 11, 7), source: 'recurring'),
        _spend(800, DateTime(2026, 11, 8), billId: 'internet'),
        _spend(5000, DateTime(2026, 11, 6), category: 'Loans'),
      ];
      final stats = noSpendStats(entries, _now);
      expect(stats.noSpendDays, 7);
      expect(stats.daysSoFar, 10);
      expect(stats.bestStreak, 3, reason: '6, 7 and 8 November');
      expect(stats.currentStreak, 1, reason: 'today so far');
      final spentToday = noSpendStats(
          [...entries, _spend(50, DateTime(2026, 11, 10, 9))], _now);
      expect(spentToday.currentStreak, 0, reason: 'yesterday had spending');
    });

    test('heatmap levels are relative to the month', () {
      final heat = monthHeatmap([
        _spend(100, DateTime(2026, 11, 1)),
        _spend(200, DateTime(2026, 11, 2)),
        _spend(300, DateTime(2026, 11, 3)),
        _spend(400, DateTime(2026, 11, 4)),
      ], _now);
      expect(heat.level[DateTime(2026, 11, 1)], 1);
      expect(heat.level[DateTime(2026, 11, 4)], 4);
      expect(heat.totals[DateTime(2026, 11, 5)], isNull);
    });

    test('a trip counts every expense in its dates', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      final trip = await store.addTrip(
          name: 'Goa',
          start: DateTime(2026, 11, 8),
          end: DateTime(2026, 11, 12),
          budgetPaise: 1000000);
      final status = tripStatus(
          trip,
          [
            _spend(3000, DateTime(2026, 11, 8, 10), category: 'Travel'),
            _spend(1000, DateTime(2026, 11, 12, 22)),
            _spend(500, DateTime(2026, 11, 13)),
          ],
          _now);
      expect(trip.days, 5);
      expect(status.spentPaise, 400000);
      expect(status.daysLeft, 3);
      expect(status.perDayPaise, 200000);
      expect(status.byCategory.keys.first, 'Travel');
      final restored = LifePilotStore.inMemory(clock: () => _now);
      await restored.restoreJson(store.exportJson());
      expect(restored.trips.single.name, 'Goa');
    });
  });

  group('documents and warranties', () {
    test('warranty end, days left and what is ending soon', () {
      expect(warrantyEnd(DateTime(2026, 1, 15), 12), DateTime(2027, 1, 14));
      expect(daysUntil(DateTime(2026, 11, 25), _now), 15);
      final items = [
        VaultItem(
            id: 'tv',
            title: 'TV',
            kind: VaultKind.warranty,
            createdAt: _now,
            expiryDate: DateTime(2026, 11, 25)),
        VaultItem(
            id: 'policy',
            title: 'Health policy',
            kind: VaultKind.insurance,
            createdAt: _now,
            expiryDate: DateTime(2027, 6, 1)),
        VaultItem(
            id: 'old',
            title: 'Old phone',
            kind: VaultKind.warranty,
            createdAt: _now,
            expiryDate: DateTime(2026, 11, 1)),
      ];
      expect(expiringSoon(items, _now).map((item) => item.id), ['old', 'tv']);
      final reminders = expiryReminders(items, _now);
      expect([
        for (final item in reminders) item.at
      ], [
        DateTime(2026, 11, 18, 9),
        DateTime(2026, 11, 25, 9),
      ]);
    });

    test('store keeps records, schedules reminders, backs up', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      final item = await store.addVaultItem(
        title: 'Washing machine',
        kind: VaultKind.warranty,
        filePath: '/vault/doc-1.pdf.lps',
        fileName: 'warranty.pdf',
        purchaseDate: DateTime(2025, 11, 26),
        expiryDate: warrantyEnd(DateTime(2025, 11, 26), 12),
      );
      expect(item.isImage, isFalse);
      expect(
          store
              .notificationPlan()
              .where((p) => p.payload == 'vault:${item.id}'),
          hasLength(2));
      final restored = LifePilotStore.inMemory(clock: () => _now);
      await restored.restoreJson(store.exportJson());
      expect(restored.vault.single.fileName, 'warranty.pdf');
      expect(await store.deleteVaultItem(item.id), '/vault/doc-1.pdf.lps');
      expect(store.vault, isEmpty);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, LifePilotStore store, Widget child) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(ListenableBuilder(
        listenable: store,
        builder: (context, _) => MaterialApp(
          theme: buildTheme(Brightness.light),
          home: child,
        ),
      ));
    }

    testWidgets('budgets extras: challenge, heatmap and a trip',
        (tester) async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 20000,
          category: 'Food',
          title: 'Lunch',
          occurredAt: DateTime(2026, 11, 3));
      await store.addTrip(
          name: 'Goa',
          start: DateTime(2026, 11, 8),
          end: DateTime(2026, 11, 12),
          budgetPaise: 1000000);
      await pump(
          tester,
          store,
          Scaffold(
              body: ListView(children: [SpendingHabitsSection(store: store)])));
      await tester.pumpAndSettle();
      expect(
          find.text('9 of 10 days with no everyday spending'), findsOneWidget);
      expect(find.text('Spending in November 2026'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Goa'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Goa'), findsOneWidget);
    });

    testWidgets('vault lists documents and what is ending soon',
        (tester) async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addVaultItem(
          title: 'TV',
          kind: VaultKind.warranty,
          expiryDate: DateTime(2026, 11, 25));
      await pump(tester, store, VaultPage(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Ending soon'), findsOneWidget);
      expect(find.text('TV'), findsNWidgets(2));
      await tester.tap(find.text('TV').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
