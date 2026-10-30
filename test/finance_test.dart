import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/csv.dart';
import 'package:lifepilot_ai/core/finance_calc.dart';
import 'package:lifepilot_ai/core/formatters.dart';
import 'package:lifepilot_ai/core/insights.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';

LedgerEntry expense(int rupees, DateTime at,
        {String category = 'Food', String title = 'Lunch', String id = ''}) =>
    LedgerEntry(
      id: id.isEmpty ? '$rupees-${at.toIso8601String()}-$title' : id,
      kind: EntryKind.expense,
      amountPaise: rupees * 100,
      category: category,
      title: title,
      occurredAt: at,
    );

void main() {
  group('money formatting and parsing', () {
    test('formats paise with Indian digit grouping', () {
      expect(formatMoney(0), '₹0.00');
      expect(formatMoney(123456789), '₹12,34,567.89');
      expect(formatMoney(-50000), '-₹500.00');
    });

    test('parses rupee input without floating point', () {
      expect(parseRupeesToPaise('250'), 25000);
      expect(parseRupeesToPaise('1,200.5'), 120050);
      expect(parseRupeesToPaise('0.1'), 10);
      expect(parseRupeesToPaise('0'), isNull);
      expect(parseRupeesToPaise('12.345'), isNull);
      expect(parseRupeesToPaise('-5'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
    });

    test('compact amounts', () {
      expect(formatMoneyCompact(320000), '₹3.2K');
      expect(formatMoneyCompact(25000000), '₹2.5L');
    });
  });

  group('period summaries', () {
    final now = DateTime(2026, 10, 15, 12);
    final entries = [
      expense(3200, DateTime(2026, 10, 3)),
      expense(800, DateTime(2026, 10, 14), category: 'Transport'),
      expense(999, DateTime(2026, 9, 30)),
      LedgerEntry(
        id: 'salary',
        kind: EntryKind.income,
        amountPaise: 5000000,
        category: 'Salary',
        title: 'Salary',
        occurredAt: DateTime(2026, 10, 1),
      ),
    ];

    test('net recorded cash flow is income minus expenses in range', () {
      final summary = summarize(entries, monthRange(now));
      expect(summary.income, 5000000);
      expect(summary.expenses, 400000);
      expect(summary.netCashFlow, 4600000);
    });

    test('month and week ranges are half-open and Monday based', () {
      final month = monthRange(now);
      expect(month.contains(DateTime(2026, 10, 1)), isTrue);
      expect(month.contains(DateTime(2026, 11, 1)), isFalse);
      final week = weekRange(DateTime(2026, 10, 15)); // Thursday
      expect(week.start, DateTime(2026, 10, 12));
      expect(week.end, DateTime(2026, 10, 19));
      expect(monthRange(DateTime(2026, 1, 10), offset: -1).start,
          DateTime(2025, 12, 1));
    });

    test('category totals are sorted by amount', () {
      final totals = categoryTotals(entries, monthRange(now));
      expect(totals.keys.toList(), ['Food', 'Transport']);
      expect(totals['Food'], 320000);
    });

    test('daily expenses cover every day of the range', () {
      final days = dailyExpenses(entries, monthRange(now));
      expect(days.length, 31);
      expect(days[2].amount, 320000);
      expect(days[13].amount, 80000);
    });
  });

  group('budgets', () {
    final now = DateTime(2026, 10, 20);

    test('matches the specification example', () {
      const budget = SpendingBudget(category: 'Food', limitPaise: 500000);
      final status =
          budgetStatus(budget, [expense(3200, DateTime(2026, 10, 2))], now);
      expect(status.spentPaise, 320000);
      expect(status.remainingPaise, 180000);
      expect(status.utilizationPercent, 64);
      expect(status.isOver, isFalse);
      expect(status.isApproaching, isFalse);
    });

    test('weekly budgets count only this week', () {
      const budget = SpendingBudget(
          category: 'Food', limitPaise: 100000, period: BudgetPeriod.weekly);
      final status = budgetStatus(
          budget,
          [
            expense(900, DateTime(2026, 10, 19)),
            expense(500, DateTime(2026, 10, 18)),
          ],
          now);
      expect(status.spentPaise, 90000);
      expect(status.isApproaching, isTrue);
    });

    test('rollover adds only last period unspent amount', () {
      const budget =
          SpendingBudget(category: 'Food', limitPaise: 500000, rollover: true);
      final status =
          budgetStatus(budget, [expense(4000, DateTime(2026, 9, 10))], now);
      expect(status.carriedOverPaise, 100000);
      expect(status.limitPaise, 600000);
    });

    test('over budget is reported', () {
      const budget = SpendingBudget(category: 'Food', limitPaise: 100000);
      final status =
          budgetStatus(budget, [expense(1500, DateTime(2026, 10, 5))], now);
      expect(status.isOver, isTrue);
      expect(status.remainingPaise, -50000);
    });
  });

  group('savings goals', () {
    test('progress, remaining and suggested contribution', () {
      final goal = SavingsGoal(
        id: 'g',
        name: 'Laptop',
        targetPaise: 6000000,
        createdAt: DateTime(2026, 1, 1),
        targetDate: DateTime(2027, 4, 15),
        contributions: [
          GoalContribution(
              id: 'c', amountPaise: 1200000, at: DateTime(2026, 9, 1)),
        ],
      );
      expect(goal.savedPaise, 1200000);
      expect(goal.remainingPaise, 4800000);
      expect(goal.progress, closeTo(0.2, 1e-9));
      final now = DateTime(2026, 10, 15);
      expect(monthsUntil(now, goal.targetDate!), 6);
      expect(suggestedMonthlyContribution(goal, now), 800000);
    });

    test('version 1 goals keep their saved total as an opening balance', () {
      final goal = SavingsGoal.fromJson({
        'id': 'old',
        'name': 'Trip',
        'targetPaise': 100000,
        'savedPaise': 25000,
        'createdAt': '2026-01-01T00:00:00.000',
      });
      expect(goal.savedPaise, 25000);
      expect(goal.contributions.single.note, contains('before'));
    });
  });

  group('bills', () {
    test('marking paid records payment, expense and next due date', () async {
      final store =
          LifePilotStore.inMemory(clock: () => DateTime(2026, 10, 30, 10));
      final bill = await store.addBill(
        name: 'Rent',
        kind: BillKind.rent,
        amountPaise: 1500000,
        nextDueAt: DateTime(2026, 10, 31),
      );
      await store.markBillPaid(bill.id);
      final updated = store.billById(bill.id)!;
      expect(updated.nextDueAt, DateTime(2026, 11, 30));
      expect(updated.payments.single.dueAt, DateTime(2026, 10, 31));
      expect(store.entries.single.billId, bill.id);
      expect(store.entries.single.amountPaise, 1500000);

      await store.undoLastBillPayment(bill.id);
      expect(store.entries, isEmpty);
      expect(store.billById(bill.id)!.nextDueAt, DateTime(2026, 10, 31));
    });

    test('a bill past due is overdue, never automatically paid', () {
      final bill = Bill(
        id: 'b',
        name: 'Internet',
        kind: BillKind.internet,
        amountPaise: 99900,
        nextDueAt: DateTime(2026, 10, 1),
      );
      expect(isBillOverdue(bill, DateTime(2026, 10, 5)), isTrue);
      expect(bill.payments, isEmpty);
    });

    test('monthly bills on the 31st keep their anchor day', () {
      const rule = Recurrence(Repeat.monthly, anchorDay: 31);
      final feb = rule.next(DateTime(2027, 1, 31))!;
      expect(feb, DateTime(2027, 2, 28));
      expect(rule.next(feb), DateTime(2027, 3, 31));
    });
  });

  group('duplicates', () {
    test('detects same amount and title within a day', () {
      final existing = [expense(250, DateTime(2026, 10, 1, 13))];
      final candidate = expense(250, DateTime(2026, 10, 1, 14), id: 'new');
      expect(findPossibleDuplicates(existing, candidate), hasLength(1));
      final later = expense(250, DateTime(2026, 10, 3, 14), id: 'later');
      expect(findPossibleDuplicates(existing, later), isEmpty);
    });
  });

  group('csv', () {
    test('round-trips entries including quotes and commas', () {
      final entries = [
        LedgerEntry(
          id: '1',
          kind: EntryKind.expense,
          amountPaise: 123450,
          category: 'Food',
          title: 'Dinner, "special"',
          occurredAt: DateTime(2026, 10, 2, 20, 15),
          paymentMethod: 'UPI',
          merchant: 'Cafe',
          note: 'line1\nline2',
        ),
      ];
      final result = parseEntriesCsv(entriesToCsv(entries));
      expect(result.errors, isEmpty);
      final parsed = result.entries.single;
      expect(parsed.title, 'Dinner, "special"');
      expect(parsed.amountPaise, 123450);
      expect(parsed.note, 'line1\nline2');
      expect(parsed.paymentMethod, 'UPI');
      expect(parsed.occurredAt, DateTime(2026, 10, 2, 20, 15));
    });

    test('reports invalid rows and import skips duplicates', () async {
      const source = 'date,type,amount,description\n'
          '2026-10-01,expense,100,Tea\n'
          'bad,expense,100,Tea\n'
          '2026-10-01,expense,-5,Tea\n';
      final result = parseEntriesCsv(source);
      expect(result.entries, hasLength(1));
      expect(result.errors, hasLength(2));
      final store = LifePilotStore.inMemory();
      expect((await store.importEntries(result.entries)).added, 1);
      expect((await store.importEntries(result.entries)).skipped, 1);
      expect(store.entries, hasLength(1));
    });
  });

  group('insights', () {
    test('no insights without enough data', () {
      expect(
        buildInsights(
            entries: [expense(100, DateTime(2026, 10, 2))],
            budgets: const [],
            bills: const [],
            goals: const [],
            now: DateTime(2026, 10, 15)),
        isEmpty,
      );
    });

    test('category increase compares the same days of last month', () {
      final now = DateTime(2026, 10, 10, 12);
      final insights = buildInsights(
        entries: [
          expense(1000, DateTime(2026, 9, 5)),
          expense(5000, DateTime(2026, 9, 25)), // outside 1–10 Sep
          expense(3000, DateTime(2026, 10, 5)),
        ],
        budgets: const [],
        bills: const [],
        goals: const [],
        now: now,
      );
      final trend = insights.singleWhere((item) => item.id == 'trend-Food');
      expect(trend.title, contains('200%'));
      expect(trend.basis, contains('1–10'));
    });

    test('budget approaching limit and bill due soon', () {
      final now = DateTime(2026, 10, 10);
      final insights = buildInsights(
        entries: [expense(850, DateTime(2026, 10, 2))],
        budgets: const [SpendingBudget(category: 'Food', limitPaise: 100000)],
        bills: [
          Bill(
            id: 'b',
            name: 'Electricity',
            kind: BillKind.electricity,
            amountPaise: 120000,
            nextDueAt: DateTime(2026, 10, 11),
          ),
        ],
        goals: const [],
        now: now,
      );
      expect(insights.map((item) => item.id),
          containsAll(['budget-near-Food', 'bill-b']));
    });
  });
}
