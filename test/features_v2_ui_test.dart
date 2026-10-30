import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/assistant_engine.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/core/secure.dart';
import 'package:lifepilot_ai/features/money_extras.dart';
import 'package:lifepilot_ai/main.dart';
import 'package:lifepilot_ai/services/home_widget_service.dart';

final _now = DateTime(2026, 10, 30, 10); // Friday

Future<void> _pumpApp(WidgetTester tester, LifePilotStore store) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(LifePilotApp(store: store));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  group('assistant: new commands', () {
    late LifePilotStore store;
    late AssistantEngine engine;

    setUp(() {
      store = LifePilotStore.inMemory(clock: () => _now);
      engine = AssistantEngine(store);
    });

    test('adds a monthly bill due on a day of the month', () async {
      final proposal = engine
          .handle('Add electricity bill 1200 due on 5th')
          .proposal as AddBillAction;
      expect(proposal.kind, BillKind.electricity);
      expect(proposal.amountPaise, 120000);
      expect(proposal.dueAt, DateTime(2026, 11, 5));
      expect(proposal.recurrence.repeat, Repeat.monthly);
      expect(proposal.name, 'Electricity bill');
      await engine.execute(proposal);
      expect(store.bills.single.nextDueAt, DateTime(2026, 11, 5));
    });

    test('bill without amount asks for details', () {
      final reply = engine.handle('Add internet bill');
      expect(reply.isQuestion, isTrue);
      expect(reply.proposal, isNull);
    });

    test('contributes to a named goal', () async {
      await store.addGoal('Emergency fund', 10000000);
      final proposal = engine.handle('Add 2000 to my emergency fund').proposal
          as GoalContributionAction;
      expect(proposal.amountPaise, 200000);
      await engine.execute(proposal);
      expect(store.goals.single.savedPaise, 200000);
      // Without a matching goal, "add … for lunch" is still an expense.
      expect(
          engine.handle('Add 250 for lunch').proposal, isA<AddEntryAction>());
    });

    test('starts a timer and a focus session', () async {
      final timer =
          engine.handle('Start a 10 minute timer').proposal as StartTimerAction;
      expect(timer.minutes, 10);
      final result = await engine.execute(timer);
      expect(store.clock.timer.endsAt, _now.add(const Duration(minutes: 10)));
      expect(result, contains('Timer started'));
      final focus = engine.handle('Start focus').proposal as StartTimerAction;
      expect(focus.focus, isTrue);
      await engine.execute(focus);
      expect(store.clock.focus.isRunning, isTrue);
    });

    test('marks a task done and checks in a habit', () async {
      await store.addTask(title: 'Submit expense report', project: '');
      await store.addHabit('Walk');
      final task = engine.handle('Mark expense report as done').proposal
          as CompleteItemAction;
      expect(task.isHabit, isFalse);
      await engine.execute(task);
      expect(store.tasks.single.isDone, isTrue);
      final habit =
          engine.handle('Check in walk').proposal as CompleteItemAction;
      expect(habit.isHabit, isTrue);
      final result = await engine.execute(habit);
      expect(store.habits.single.doneOn(_now), isTrue);
      expect(result, contains('streak'));
    });

    test('ambiguous completion asks which one', () async {
      await store.addTask(title: 'Call bank', project: '');
      await store.addTask(title: 'Call bank manager', project: '');
      final reply = engine.handle('Mark call bank done');
      expect(reply.isQuestion, isTrue);
    });

    test('deleting the last expense needs a destructive confirmation',
        () async {
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 100,
          category: 'Food',
          title: 'Tea',
          occurredAt: _now);
      final proposal =
          engine.handle('Delete my last expense').proposal as DeleteEntryAction;
      expect(proposal.destructive, isTrue);
      expect(store.entries, hasLength(1), reason: 'not deleted before confirm');
      await engine.execute(proposal);
      expect(store.entries, isEmpty);
    });

    test('weekly summary', () {
      expect(engine.handle('How was my week?').text, contains('This week'));
    });
  });

  group('sms drafts', () {
    test('parsed messages become drafts with learned categories', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 30000,
          category: 'Food',
          title: 'Swiggy',
          merchant: 'swiggy@icici',
          occurredAt: _now.subtract(const Duration(days: 3)));
      final drafts = draftsFromSms(store, [
        (
          address: 'HDFCBK',
          body:
              'Rs.250.00 debited from A/c XX1234 on 29-10-26 to VPA swiggy@icici UPI Ref 123456789012',
          date: _now,
        ),
        (address: 'HDFCBK', body: 'Your OTP is 123456', date: _now),
      ]);
      expect(drafts, hasLength(1));
      final entry = drafts.single.entry;
      expect(entry.amountPaise, 25000);
      expect(entry.category, 'Food');
      expect(entry.paymentMethod, 'UPI');
      expect(entry.source, 'sms');
    });
  });

  group('home widget', () {
    test('summarises the day and hides money when locked', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addTask(
          title: 'Pay rent', project: '', dueAt: DateTime(2026, 10, 30));
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 50000,
          category: 'Food',
          title: 'Dinner',
          occurredAt: _now);
      var content = widgetContent(store);
      expect(content.date, 'Friday, 30 Oct');
      expect(content.tasks, '1 due today');
      expect(content.money, contains('₹500.00'));
      final pin = await hashPin('1234', iterations: 1000);
      await store.updateSettings(store.settings
          .copyWith(lockEnabled: true, pinHash: pin.hash, pinSalt: pin.salt));
      content = widgetContent(store);
      expect(content.money, isNot(contains('₹')));
    });
  });

  testWidgets('onboarding creates only what the user entered', (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.updateSettings(store.settings.copyWith(onboarded: false));
    await _pumpApp(tester, store);
    expect(find.text('Welcome to LifePilot'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Monthly salary (optional)'), '50000');
    await tester.enterText(find.widgetWithText(TextField, 'Food'), '6000');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(store.settings.onboarded, isTrue);
    expect(store.recurring.single.amountPaise, 5000000);
    expect(store.entries, isEmpty, reason: 'salary is a rule, not an entry');
    expect(store.budgets.single.category, 'Food');
    expect(store.accounts.map((a) => a.kind),
        containsAll([AccountKind.cash, AccountKind.bank]));
    expect(find.text('Good morning'), findsOneWidget);
  });

  testWidgets('app lock blocks the app until the PIN is entered',
      (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    final pin = await hashPin('2580', iterations: 1000);
    await store.updateSettings(store.settings.copyWith(
      lockEnabled: true,
      pinHash: pin.hash,
      pinSalt: pin.salt,
      lockUseBiometrics: false,
    ));
    await _pumpApp(tester, store);
    expect(find.text('LifePilot is locked'), findsOneWidget);
    expect(find.text('Good morning'), findsNothing);

    for (final digit in ['1', '1', '1', '1']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('LifePilot is locked'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.backspace_outlined));
    }
    await tester.pump();
    for (final digit in ['2', '5', '8', '0']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('LifePilot is locked'), findsNothing);
    expect(find.text('Good morning'), findsOneWidget);
  });

  testWidgets('habit check-in from the Habits tab', (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addHabit('Read 20 pages');
    await _pumpApp(tester, store);
    await _tapNav(tester, 'Tasks');
    await tester.tap(find.widgetWithText(Tab, 'Habits'));
    await tester.pumpAndSettle();
    expect(find.text('Today · 0 of 1 done'), findsOneWidget);
    await tester.tap(find.byTooltip('Mark done today'));
    await tester.pumpAndSettle();
    expect(store.habits.single.doneOn(_now), isTrue);
    expect(find.text('Today · 1 of 1 done'), findsOneWidget);
  });

  testWidgets('recurring draft is approved from Finance', (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addRecurring(
      kind: EntryKind.expense,
      amountPaise: 1500000,
      category: 'Home',
      title: 'Rent',
      recurrence: const Recurrence(Repeat.monthly),
      firstDate: DateTime(2026, 10, 5),
    );
    await _pumpApp(tester, store);
    expect(find.text('1 transaction to review'), findsOneWidget);
    await _tapNav(tester, 'Finance');
    await tester.tap(find.text('1 draft is waiting for review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(store.entries.single.title, 'Rent');
    expect(store.pending, isEmpty);
  });

  testWidgets('theme mode and accent are applied', (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.updateSettings(store.settings
        .copyWith(themeMode: AppThemeMode.dark, accentColor: accentChoices[3]));
    await _pumpApp(tester, store);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme!.colorScheme.brightness, Brightness.dark);
  });
}
