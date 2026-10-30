import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/features/clock_page.dart';
import 'package:lifepilot_ai/main.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 10, 29, 9, 30);

Future<LifePilotStore> _launch(WidgetTester tester,
    {LifePilotStore? store}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final appStore = store ?? LifePilotStore.inMemory(clock: () => _now);
  await tester.pumpWidget(LifePilotApp(store: appStore));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return appStore;
}

Future<void> _quickAdd(WidgetTester tester, String label) async {
  await tester.tap(find.text('Add').last);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
      of: find.byType(BottomSheet), matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dashboard shows empty states and real-time header',
      (tester) async {
    await _launch(tester);
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text("Today's overview"), findsOneWidget);
    expect(find.text('No upcoming reminders'), findsOneWidget);
    expect(find.text('₹0.00'), findsWidgets);

    final recent = find.text('No transactions recorded');
    await tester.scrollUntilVisible(recent, 300,
        scrollable: find.byType(Scrollable).first);
    expect(recent, findsOneWidget);
  });

  testWidgets('quick add records an expense that updates the dashboard',
      (tester) async {
    final store = await _launch(tester);
    await _quickAdd(tester, 'Expense');

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '250');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Transport'));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (optional)'), 'Metro');
    await tester.ensureVisible(find.text('Save expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(store.entries, hasLength(1));
    final entry = store.entries.single;
    expect(entry.amountPaise, 25000);
    expect(entry.category, 'Transport');
    expect(entry.title, 'Metro');
    expect(find.text('Expense of ₹250.00 saved'), findsOneWidget);
    expect(find.text('₹250.00'), findsWidgets);
  });

  testWidgets('invalid amount shows an inline error and keeps the input',
      (tester) async {
    final store = await _launch(tester);
    await _quickAdd(tester, 'Expense');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'), '12.345');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (optional)'),
        'Keep me');
    await tester.ensureVisible(find.text('Save expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(store.entries, isEmpty);
    expect(find.textContaining('up to 2 decimals'), findsOneWidget);
    expect(find.text('Keep me'), findsOneWidget);
  });

  testWidgets('tapping save twice creates only one task', (tester) async {
    final store = await _launch(tester);
    await _quickAdd(tester, 'Task');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task'), 'Pay rent');
    final save = find.text('Add task');
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(store.tasks, hasLength(1));
    expect(store.tasks.single.title, 'Pay rent');
  });

  testWidgets('completing a recurring task moves it to the next occurrence',
      (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addTask(
      title: 'Water plants',
      project: '',
      dueAt: DateTime(2026, 10, 29, 18),
      dueHasTime: true,
      recurrence: const Recurrence(Repeat.daily),
    );
    await _launch(tester, store: store);
    await _tapNav(tester, 'Tasks');

    expect(find.text('Water plants'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final task = store.tasks.single;
    expect(task.isDone, isFalse);
    expect(task.dueAt, DateTime(2026, 10, 30, 18));
    expect(task.completionHistory, hasLength(1));
    expect(find.text('Completed · next one scheduled'), findsOneWidget);
  });

  testWidgets('assistant saves an expense only after confirmation',
      (tester) async {
    final store = await _launch(tester);
    await _tapNav(tester, 'Assistant');

    await tester.enterText(find.byType(TextField).last, 'Add ₹250 for lunch');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Save expense?'), findsOneWidget);
    expect(store.entries, isEmpty);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(store.entries.single.amountPaise, 25000);
    expect(store.entries.single.category, 'Food');
    expect(find.textContaining('Saved expense “Lunch”'), findsOneWidget);
  });

  testWidgets('finance tabs render with recorded data', (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addEntry(
        kind: EntryKind.income,
        amountPaise: 5000000,
        category: 'Salary',
        title: 'Salary',
        occurredAt: DateTime(2026, 10, 1));
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 320000,
        category: 'Food',
        title: 'Groceries',
        occurredAt: DateTime(2026, 10, 5));
    await store.setBudget('Food', 500000);
    await store.addBill(
        name: 'Electricity',
        kind: BillKind.electricity,
        amountPaise: 150000,
        nextDueAt: DateTime(2026, 10, 30));
    await store.addGoal('Laptop', 6000000, targetDate: DateTime(2027, 4, 1));
    await _launch(tester, store: store);
    await _tapNav(tester, 'Finance');

    expect(find.text('₹46,800.00'), findsOneWidget);
    for (final tab in [
      'Activity',
      'Budgets',
      'Bills',
      'Goals',
      'Reports',
      'UPI'
    ]) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$tab tab');
      if (tab == 'Budgets') {
        expect(
            find.textContaining('₹1,800.00 left this month'), findsOneWidget);
      }
      if (tab == 'Bills') expect(find.text('Due soon'), findsOneWidget);
    }
  });

  testWidgets(
      'every screen lays out on a small phone in dark mode with large text',
      (tester) async {
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 123456789,
        category: 'Entertainment',
        title: 'A rather long description for a large purchase',
        occurredAt: DateTime(2026, 10, 28));
    await store.setBudget('Entertainment', 100000);
    await store.addTask(
      title: 'Prepare the quarterly planning presentation for the team',
      project: 'Work',
      dueAt: DateTime(2026, 10, 29, 16),
      dueHasTime: true,
      priority: TaskPriority.urgent,
      durationMinutes: 90,
      tags: ['planning', 'slides'],
      subtasks: ['Outline', 'Charts'],
      reminderOffsets: [15],
      recurrence: const Recurrence(Repeat.weekly),
    );
    await store.addBill(
        name: 'Home loan EMI',
        kind: BillKind.loan,
        amountPaise: 4500000,
        nextDueAt: DateTime(2026, 10, 27));
    await store.addGoal('Emergency fund', 30000000,
        targetDate: DateTime(2027, 6, 1), type: GoalType.emergency);
    final bank = await store.addAccount(
        'HDFC Bank salary account', AccountKind.bank,
        openingBalancePaise: 12345678);
    final cash = await store.addAccount('Cash', AccountKind.cash);
    await store.addTransfer(
        fromAccountId: bank.id, toAccountId: cash.id, amountPaise: 500000);
    await store.addRecurring(
      kind: EntryKind.expense,
      amountPaise: 2500000,
      category: 'Home',
      title: 'House rent for the apartment',
      recurrence: const Recurrence(Repeat.monthly),
      firstDate: DateTime(2026, 10, 1),
      accountId: bank.id,
    );
    await store.addHabit('Drink eight glasses of water every day',
        reminderMinutes: 20 * 60);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 3; // 360 × 740 dp
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(LifePilotApp(store: store));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Home');

    await _tapNav(tester, 'Finance');
    for (final tab in [
      'Overview',
      'Activity',
      'Budgets',
      'Bills',
      'Recurring',
      'Accounts',
      'Goals',
      'Reports',
      'UPI'
    ]) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Finance $tab');
    }
    await _tapNav(tester, 'Tasks');
    for (final tab in ['List', 'Calendar', 'Timeline', 'Habits']) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Tasks $tab');
    }
    await _tapNav(tester, 'Assistant');
    expect(tester.takeException(), isNull, reason: 'Assistant');
    await _tapNav(tester, 'More');
    expect(tester.takeException(), isNull, reason: 'More');

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Weekly review');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clock and world clock'));
    await tester.pumpAndSettle();
    for (final tab in [
      'Clock',
      'World',
      'Stopwatch',
      'Timer',
      'Focus',
      'Alarms'
    ]) {
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Clock $tab');
      if (tab == 'World') {
        // Default cities come from the time-zone database.
        expect(find.text('London'), findsOneWidget);
        expect(find.text('New York'), findsOneWidget);
      }
    }
  });

  testWidgets('stopwatch starts, records a lap, and pauses', (tester) async {
    var now = _now;
    final store = LifePilotStore.inMemory(clock: () => now);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: ClockPage(store: store, initialTab: ClockTab.stopwatch),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pump();
    now = now.add(const Duration(seconds: 12, milliseconds: 300));
    await tester.tap(find.text('Lap'));
    await tester.pump();
    now = now.add(const Duration(seconds: 3));
    await tester.tap(find.text('Pause'));
    await tester.pump();

    final state = store.clock.stopwatch;
    expect(state.isRunning, isFalse);
    expect(state.lapsMs, [12300]);
    expect(state.accumulatedMs, 15300);
    expect(find.text('00:15.3'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });
}
