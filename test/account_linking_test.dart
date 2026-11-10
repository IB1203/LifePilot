import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/features/money_extras.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 11, 10, 12);

void main() {
  testWidgets('an unlinked entry can be linked to an account from Accounts',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = LifePilotStore.inMemory(clock: () => _now);
    final bank = await store.addAccount('HDFC Bank', AccountKind.bank,
        openingBalancePaise: 100000);
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 25000,
        category: 'Food',
        title: 'Swiggy',
        occurredAt: DateTime(2026, 11, 2));
    expect(store.entries.single.accountId, isNull);

    await tester.pumpWidget(ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: AccountsTab(store: store)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('not linked to an account'), findsOneWidget);
    await tester.tap(find.textContaining('not linked to an account'));
    await tester.pumpAndSettle();
    expect(find.text('Link entries to an account'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.link).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('HDFC Bank').last);
    await tester.pumpAndSettle();

    expect(store.entries.single.accountId, bank.id);
    expect(store.accountRunningBalance(bank.id), 100000 - 25000,
        reason: 'linking moves the entry into the account balance');
  });
}
