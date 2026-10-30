import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/assistant_engine.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';

void main() {
  // Thursday 29 October 2026, 10:00.
  final now = DateTime(2026, 10, 29, 10);
  late LifePilotStore store;
  late AssistantEngine engine;

  setUp(() {
    store = LifePilotStore.inMemory(clock: () => now);
    engine = AssistantEngine(store);
  });

  group('date and amount parsing', () {
    test('relative days, weekdays and times', () {
      final when = parseWhen('pay the Electricity bill tomorrow at 7 PM', now);
      expect(when.resolve(now), DateTime(2026, 10, 30, 19));
      expect(when.rest, 'pay the Electricity bill');
      expect(parseWhen('on friday', now).date, DateTime(2026, 10, 30));
      expect(parseWhen('next thursday', now).date, DateTime(2026, 11, 5));
      expect(parseWhen('at 18:30', now).resolve(now),
          DateTime(2026, 10, 29, 18, 30));
      expect(parseWhen('5 nov', now).date, DateTime(2026, 11, 5));
      expect(parseWhen('in 2 hours', now).resolve(now),
          DateTime(2026, 10, 29, 12));
      expect(parseWhen('at 7', now).ambiguousHour, isTrue);
    });

    test('a time earlier today without a date means tomorrow', () {
      expect(parseWhen('at 8 am', now).resolve(now), DateTime(2026, 10, 30, 8));
    });

    test('amounts with and without currency markers', () {
      expect(parseAmount('Add ₹250 for lunch'), 25000);
      expect(parseAmount('rs. 1,200.50 groceries'), 120050);
      expect(parseAmount('paid 300 rupees'), 30000);
      expect(parseAmount('meeting at 7 pm'), isNull);
      expect(parseAmount('spent 120 on tea'), 12000);
    });
  });

  group('transactions', () {
    test('Add ₹250 for lunch proposes a food expense and saves on confirm',
        () async {
      final reply = engine.handle('Add ₹250 for lunch.');
      final proposal = reply.proposal as AddEntryAction;
      expect(proposal.kind, EntryKind.expense);
      expect(proposal.amountPaise, 25000);
      expect(proposal.category, 'Food');
      expect(proposal.title, 'Lunch');
      expect(store.entries, isEmpty, reason: 'nothing saved before confirm');

      final result = await engine.execute(proposal);
      expect(store.entries.single.amountPaise, 25000);
      expect(result, contains('Saved expense'));
      expect(result, contains('₹250.00'));
    });

    test('income is detected', () {
      final proposal =
          engine.handle('Received 50,000 salary').proposal as AddEntryAction;
      expect(proposal.kind, EntryKind.income);
      expect(proposal.category, 'Salary');
    });

    test('missing amount asks a question, then accepts the answer', () {
      final question = engine.handle('I paid for groceries');
      expect(question.isQuestion, isTrue);
      expect(question.proposal, isNull);
      final answer = engine.handle('450');
      expect((answer.proposal as AddEntryAction).amountPaise, 45000);
    });

    test('warns about a possible duplicate', () async {
      await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 25000,
        category: 'Food',
        title: 'Lunch',
        occurredAt: now.subtract(const Duration(hours: 1)),
      );
      final proposal =
          engine.handle('Add ₹250 for lunch').proposal as AddEntryAction;
      expect(proposal.duplicateWarning, isNotNull);
    });

    test('future-dated transactions are refused', () {
      final reply = engine.handle('spent 500 on dinner tomorrow');
      expect(reply.proposal, isNull);
      expect(reply.text, contains('future'));
    });
  });

  group('tasks and reminders', () {
    test('Create a task to finish my project report tomorrow', () async {
      final reply =
          engine.handle('Create a task to finish my project report tomorrow');
      final proposal = reply.proposal as AddTaskAction;
      expect(proposal.title, 'Finish my project report');
      expect(proposal.dueAt, DateTime(2026, 10, 30));
      expect(proposal.dueHasTime, isFalse);
      await engine.execute(proposal);
      expect(store.tasks.single.title, 'Finish my project report');
    });

    test('Remind me to pay my electricity bill tomorrow at 7 PM', () async {
      final proposal = engine
          .handle('Remind me to pay my electricity bill tomorrow at 7 PM.')
          .proposal as AddTaskAction;
      expect(proposal.title, 'Pay my electricity bill');
      expect(proposal.dueAt, DateTime(2026, 10, 30, 19));
      expect(proposal.remind, isTrue);
      final result = await engine.execute(proposal);
      final task = store.tasks.single;
      expect(task.reminderOffsets, [0]);
      expect(task.dueHasTime, isTrue);
      expect(result, contains('notification is scheduled'));
    });

    test('reminder without a time asks when', () {
      final question = engine.handle('Remind me to call mom');
      expect(question.isQuestion, isTrue);
      final proposal =
          engine.handle('tomorrow at 9 am').proposal as AddTaskAction;
      expect(proposal.title, 'Call mom');
      expect(proposal.dueAt, DateTime(2026, 10, 30, 9));
    });

    test('ambiguous hour asks for AM or PM', () {
      final question =
          engine.handle('Remind me to take medicine tomorrow at 7');
      expect(question.text, contains('7 AM or 7 PM'));
      final proposal = engine.handle('pm').proposal as AddTaskAction;
      expect(proposal.dueAt, DateTime(2026, 10, 30, 19));
    });

    test('cancel drops a pending question', () {
      engine.handle('Remind me to call mom');
      expect(engine.handle('cancel').text, contains('dropped'));
    });

    test('overdue tasks and plan my day use real records', () async {
      expect(engine.handle('Show my overdue tasks').text,
          'You have no overdue tasks.');
      await store.addTask(
          title: 'Submit form', project: '', dueAt: DateTime(2026, 10, 27));
      await store.addTask(
          title: 'Write notes', project: '', priority: TaskPriority.high);
      expect(
          engine.handle('Show my overdue tasks').text, contains('Submit form'));
      final plan = engine.handle('Plan my day using my pending tasks').text;
      expect(plan, contains('Submit form'));
      expect(plan, contains('Write notes'));
      expect(plan, contains('not saved'));
    });
  });

  group('finance questions', () {
    setUp(() async {
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 320000,
          category: 'Food',
          title: 'Groceries',
          occurredAt: DateTime(2026, 10, 5));
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 100000,
          category: 'Food',
          title: 'Groceries',
          occurredAt: DateTime(2026, 9, 5));
      await store.setBudget('Food', 500000);
    });

    test('expenses this month', () {
      final text = engine.handle('Show my expenses this month').text;
      expect(text, contains('₹3,200.00'));
      expect(text, contains('October 2026'));
    });

    test('food budget remaining', () {
      final text = engine.handle('How much of my food budget remains?').text;
      expect(text, contains('₹1,800.00 remains'));
      expect(text, contains('64% used'));
    });

    test('compare with last month uses the same period', () {
      final text = engine.handle('Compare my expenses with last month').text;
      expect(text, contains('₹3,200.00'));
      expect(text, contains('₹1,000.00'));
      expect(text, contains('₹2,200.00 more than'));
    });

    test('upcoming bills', () async {
      expect(
          engine.handle('Show my upcoming bills').text, contains('No bills'));
      await store.addBill(
          name: 'Electricity',
          kind: BillKind.electricity,
          amountPaise: 150000,
          nextDueAt: DateTime(2026, 11, 2));
      expect(engine.handle('Show my upcoming bills').text,
          contains('Electricity: ₹1,500.00 due'));
    });

    test('never fabricates when there is no data', () {
      final empty = AssistantEngine(LifePilotStore.inMemory(clock: () => now));
      expect(empty.handle('Show my expenses this month').text,
          startsWith('No expenses recorded'));
      expect(empty.handle('Compare my expenses with last month').text,
          contains('no expenses recorded'));
    });
  });
}
