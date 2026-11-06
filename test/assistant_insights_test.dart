import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/assistant_engine.dart';
import 'package:lifepilot_ai/core/assistant_insights.dart';
import 'package:lifepilot_ai/core/debts.dart';
import 'package:lifepilot_ai/core/investments.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';

final _now = DateTime(2026, 11, 10, 12);

void main() {
  late LifePilotStore store;
  late AssistantEngine engine;

  setUp(() async {
    store = LifePilotStore.inMemory(clock: () => _now);
    engine = AssistantEngine(store);
    await store.addAccount('Savings', AccountKind.bank,
        openingBalancePaise: 20000000);
    for (final month in [8, 9, 10]) {
      await store.addEntry(
          kind: EntryKind.income,
          amountPaise: 5000000,
          category: 'Salary',
          title: 'Salary',
          occurredAt: DateTime(2026, month, 1));
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 3000000,
          category: 'Home',
          title: 'Rent and groceries',
          occurredAt: DateTime(2026, month, 3));
    }
    await store.addBill(
        name: 'Internet',
        kind: BillKind.internet,
        amountPaise: 120000,
        nextDueAt: DateTime(2026, 11, 20));
  });

  String ask(String text) {
    final reply = engine.handle(text);
    expect(reply.proposal, isNull, reason: 'a question records nothing');
    return reply.text;
  }

  test('amounts in questions: 50k, 1.5 lakh, ₹2,500', () {
    expect(questionAmount('can i afford 50k'), 5000000);
    expect(questionAmount('a 1.5 lakh bike'), 15000000);
    expect(questionAmount('₹2,500 shoes'), 250000);
    expect(questionAmount('nothing'), isNull);
  });

  group('can I afford it', () {
    test('affordable: shows the working', () {
      final answer = ask('Can I buy a phone for 50000?');
      expect(answer, startsWith('Yes'));
      // ₹2,00,000 − ₹1,200 due − ₹30,000 cushion.
      expect(answer, contains('free to spend: ₹1,68,800.00'));
      expect(answer, contains('not financial advice'));
    });

    test('too much: says how long saving would take', () {
      final answer = ask('Can I afford 2 lakh?');
      expect(answer, startsWith('Not comfortably'));
      // ₹31,200 short, saving ₹20,000 a month.
      expect(answer, contains('in about 2 month(s)'));
    });

    test('a cost is needed; no balance or income means no verdict', () {
      expect(ask('Can I afford it?'), contains('How much does it cost'));
      final empty = AssistantEngine(LifePilotStore.inMemory(clock: () => _now));
      expect(empty.handle('Can I afford 500?').text,
          contains('cannot tell yet'));
    });
  });

  test('statements are still recorded, not answered', () {
    final reply = engine.handle('Paid 500 for loan EMI');
    expect(reply.proposal, isA<AddEntryAction>());
  });

  test('where can I cut back: rising categories and subscriptions', () async {
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 400000,
        category: 'Food',
        title: 'Restaurants',
        occurredAt: DateTime(2026, 11, 4));
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 100000,
        category: 'Food',
        title: 'Restaurants',
        occurredAt: DateTime(2026, 10, 4));
    await store.addRecurring(
      kind: EntryKind.expense,
      amountPaise: 64900,
      category: 'Entertainment',
      title: 'Netflix',
      recurrence: const Recurrence(Repeat.monthly),
      firstDate: DateTime(2026, 11, 25),
    );
    final answer = ask('Where can I cut back?');
    expect(answer, contains('Food: ₹4,000.00 so far vs ₹1,000.00'));
    expect(answer, contains('Subscriptions: ₹649.00 a month'));
  });

  test('unusual transactions: much bigger than usual for the category',
      () async {
    for (var day = 1; day <= 5; day++) {
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 20000,
          category: 'Transport',
          title: 'Auto',
          occurredAt: DateTime(2026, 9, day));
    }
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 250000,
        category: 'Transport',
        title: 'Airport cab',
        occurredAt: DateTime(2026, 11, 8));
    final answer = ask('Any unusual transactions?');
    expect(answer, contains('“Airport cab” ₹2,500.00'));
    expect(answer, contains('12.5×'));
  });

  test('forecast, net worth, debts, investments, health', () async {
    expect(ask('What will I spend by month end?'),
        contains('By the end of November 2026'));

    await store.addDebt(
      name: 'Bike loan',
      kind: DebtKind.loan,
      openingPaise: 6000000,
      startDate: DateTime(2026, 11, 1),
      annualRatePercent: 9,
      emiPaise: 500000,
    );
    final debts = ask('How are my debts?');
    expect(debts, contains('You owe ₹60,000.00'));
    expect(debts, contains('Bike loan'));

    await store.addInvestment(
      name: 'Index fund',
      kind: InvestmentKind.mutualFund,
      startDate: DateTime(2025, 11, 10),
      investedPaise: 5000000,
      valuePaise: 6000000,
    );
    expect(ask('How are my investments?'),
        contains('Invested ₹50,000.00, now worth ₹60,000.00'));

    // ₹2,00,000 account + ₹60,000 investments − ₹60,000 loan.
    expect(ask('What is my net worth?'), contains('Net worth: ₹2,00,000.00'));
    expect(ask('What is my financial health score?'),
        contains('Financial health:'));
  });

  test('existing questions keep working', () {
    expect(engine.handle('Show my upcoming bills').text, contains('Internet'));
    expect(engine.handle('help').text, contains('Can I afford'));
  });
}
