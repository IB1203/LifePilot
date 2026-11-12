import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/bank_sms.dart';
import 'package:lifepilot_ai/core/debts.dart';
import 'package:lifepilot_ai/core/finance_calc.dart';
import 'package:lifepilot_ai/core/investments.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/core/money_glance.dart';
import 'package:lifepilot_ai/core/sms_import.dart';
import 'package:lifepilot_ai/core/statement_import.dart';
import 'package:lifepilot_ai/core/transaction_intelligence.dart';

final _now = DateTime(2026, 11, 12, 12);

LifePilotStore _store() => LifePilotStore.inMemory(clock: () => _now);

LedgerEntry _entry(String id, int paise,
        {EntryKind kind = EntryKind.expense,
        String title = 'Swiggy',
        String note = '',
        DateTime? at,
        TransactionClassification classification =
            TransactionClassification.other}) =>
    LedgerEntry(
      id: id,
      kind: kind,
      amountPaise: paise,
      category: 'Food',
      title: title,
      occurredAt: at ?? _now,
      note: note,
      classification: classification,
    );

void main() {
  group('account balances', () {
    test('a new entry is reflected in the balance before listeners hear',
        () async {
      final store = _store();
      final account = await store.addAccount('HDFC', AccountKind.bank,
          openingBalancePaise: 100000);
      final seen = <int>[];
      store.addListener(() => seen.add(store.accountRunningBalance(account.id)));
      await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 30000,
        category: 'Food',
        title: 'Lunch',
        occurredAt: _now,
        accountId: account.id,
      );
      expect(seen.last, 70000);
    });

    test('editing the opening balance moves the running balance', () async {
      final store = _store();
      final account = await store.addAccount('Wallet', AccountKind.cash);
      await store.updateAccount(Account(
          id: account.id,
          name: account.name,
          kind: account.kind,
          openingBalancePaise: 500000));
      expect(store.accountRunningBalance(account.id), 500000);
    });

    test('deleting an account undoes its transfers on the other side',
        () async {
      final store = _store();
      final a = await store.addAccount('A', AccountKind.bank,
          openingBalancePaise: 500000);
      final b = await store.addAccount('B', AccountKind.bank);
      await store.addTransfer(
          fromAccountId: a.id, toAccountId: b.id, amountPaise: 100000);
      expect(store.accountRunningBalance(b.id), 100000);
      await store.deleteAccount(a.id);
      expect(store.accountRunningBalance(b.id), 0);
    });

    test('merging duplicates returns the kept entry and fixes balances',
        () async {
      final store = _store();
      final account = await store.addAccount('HDFC', AccountKind.bank,
          openingBalancePaise: 100000);
      final dup = await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 20000,
          category: 'Food',
          title: 'Swiggy',
          occurredAt: _now,
          accountId: account.id);
      final keep = await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 20000,
          category: 'Food',
          title: 'Swiggy',
          occurredAt: _now,
          accountId: account.id);
      expect(store.accountRunningBalance(account.id), 60000);
      final merged = await store.mergeEntries(keep.id, [dup.id]);
      expect(merged!.id, keep.id);
      expect(store.entries.single.id, keep.id);
      expect(store.accountRunningBalance(account.id), 80000);
    });

    test('reconciliation counts transfers between accounts', () async {
      final store = _store();
      final a = await store.addAccount('A', AccountKind.bank,
          openingBalancePaise: 500000);
      final b = await store.addAccount('B', AccountKind.bank);
      await store.addTransfer(
          fromAccountId: a.id, toAccountId: b.id, amountPaise: 100000);
      final results = synchronizeAllBalances(store);
      expect(results.firstWhere((r) => r.accountId == a.id).calculatedBalance,
          400000);
    });
  });

  group('tabs work together', () {
    test('investing from an account moves money, not spending', () async {
      final store = _store();
      final account = await store.addAccount('HDFC', AccountKind.bank,
          openingBalancePaise: 10000000);
      await store.addInvestment(
        name: 'FD',
        kind: InvestmentKind.fixedDeposit,
        startDate: _now,
        investedPaise: 5000000,
        annualRatePercent: 7,
        maturityDate: DateTime(2027, 11, 12),
        fromAccountId: account.id,
      );
      expect(store.accountRunningBalance(account.id), 5000000);
      expect(
          sumEntries(store.entries,
              kind: EntryKind.expense, range: monthRange(_now)),
          0,
          reason: 'buying an investment is not spending');
    });

    test('a recurring deposit can be added with only its instalment',
        () async {
      final store = _store();
      await store.addInvestment(
        name: 'RD',
        kind: InvestmentKind.recurringDeposit,
        startDate: _now,
        installmentPaise: 500000,
        annualRatePercent: 7,
        maturityDate: DateTime(2027, 11, 12),
      );
      expect(store.investments, hasLength(1));
    });

    test('deleting a debt payment entry restores the debt', () async {
      final store = _store();
      final debt = await store.addDebt(
          name: 'Car loan',
          kind: DebtKind.loan,
          openingPaise: 1000000,
          startDate: _now);
      await store.addDebtPayment(debt.id,
          amountPaise: 100000, at: _now, recordExpense: true);
      final entry = store.entries.single;
      expect(entry.classification, TransactionClassification.debtPayment);
      await store.deleteEntry(entry.id);
      expect(store.debts.single.payments, isEmpty);
    });

    test('a credit card payment is a transfer, not a second expense',
        () async {
      final store = _store();
      final card = await store.addDebt(
          name: 'Card',
          kind: DebtKind.creditCard,
          openingPaise: 500000,
          startDate: _now);
      await store.addDebtPayment(card.id,
          amountPaise: 500000, at: _now, recordExpense: true);
      expect(
          sumEntries(store.entries,
              kind: EntryKind.expense, range: monthRange(_now)),
          0);
    });

    test('paying a bill from an account lowers that account', () async {
      final store = _store();
      final account = await store.addAccount('HDFC', AccountKind.bank,
          openingBalancePaise: 100000);
      final bill = await store.addBill(
          name: 'Internet',
          kind: BillKind.internet,
          amountPaise: 80000,
          nextDueAt: _now);
      await store.markBillPaid(bill.id, accountId: account.id);
      expect(store.accountRunningBalance(account.id), 20000);
      await store.undoLastBillPayment(bill.id);
      expect(store.accountRunningBalance(account.id), 100000);
    });

    test('an EMI already paid this month is not set aside again', () {
      final debt = Debt(
        id: 'd',
        name: 'Loan',
        kind: DebtKind.loan,
        openingPaise: 10000000,
        startDate: DateTime(2026, 1, 1),
        emiPaise: 2000000,
        payments: [
          DebtPayment(id: 'p', amountPaise: 2000000, at: DateTime(2026, 11, 5)),
        ],
      );
      expect(debtPaymentsStillDue([debt], _now), 0);
    });

    test('safe to spend never exceeds the bank balance', () {
      final safe = safeToSpend(
        entries: const [],
        budgets: const [
          SpendingBudget(category: 'Food', limitPaise: 3000000),
        ],
        bills: const [],
        rules: const [],
        now: _now,
        availablePaise: 190000,
      )!;
      expect(safe.remainingPaise, 190000);
    });
  });

  group('totals', () {
    test('a new rollover budget does not start doubled', () {
      final budget = SpendingBudget(
          category: 'Food',
          limitPaise: 500000,
          rollover: true,
          createdAt: DateTime(2026, 11, 3));
      expect(budgetStatus(budget, const [], _now).limitPaise, 500000);
    });

    test('daily and subcategory totals skip transfers', () {
      final entries = [
        _entry('a', 10000),
        _entry('t', 50000,
            classification: TransactionClassification.transfer),
      ];
      final daily = dailyExpenses(entries, monthRange(_now));
      expect(daily.fold(0, (sum, day) => sum + day.amount), 10000);
      expect(subcategoryTotals(entries, monthRange(_now), 'Food').values.single,
          10000);
    });

    test('income tagged with an expense type still counts as income', () {
      final summary = smartSummarize([
        _entry('s', 5000000,
            kind: EntryKind.income,
            title: 'Salary',
            classification: TransactionClassification.expense),
      ], monthRange(_now));
      expect(summary.income, 5000000);
      expect(summary.expenses, 0);
    });

    test('different bank references are never duplicates', () {
      final groups = findDuplicateGroups([
        _entry('a', 20000, note: 'Ref 430912345678'),
        _entry('b', 20000, note: 'Ref 430912349999'),
      ]);
      expect(groups, isEmpty);
    });

    test('plain words are not taken for a reference', () {
      final groups = findDuplicateGroups([
        _entry('a', 20000, title: 'Tea', note: 'Transaction successful'),
        _entry('b', 20000, title: 'Auto', note: 'Transaction successful'),
      ]);
      expect(groups, isEmpty);
    });

    test('payoff dates stay in a short month', () {
      expect(addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    });
  });

  group('imports', () {
    test('payee-side "credited" in bank templates is a payment', () {
      final axis = parseBankSms(
          'INR 500 credited to VPA swiggy@ybl from A/c no. XX1234 on 12-11-26 UPI Ref 430912345678',
          received: _now,
          senderHeader: 'AXISBK');
      expect(axis!.kind, EntryKind.expense);
    });

    test('refunds of failed payments and OTP footers are read', () {
      expect(
          parseBankSms(
                  'Rs.500.00 credited to your A/c XX1234 towards reversal of failed UPI txn Ref 430912345678',
                  received: _now)!
              .kind,
          EntryKind.income);
      expect(
          parseBankSms(
              'INR 500.00 spent on ICICI Bank Card XX1234 on 12-Nov-26 at AMAZON. Never share your OTP with anyone.',
              received: _now,
              senderHeader: 'ICICIB'),
          isNotNull);
      expect(
          parseBankSms('OTP for txn of Rs 500 at AMAZON is 123456.',
              received: _now),
          isNull);
      expect(
          parseBankSms(
              'Your UPI txn of Rs 500 to SWIGGY failed. Amount if debited will be refunded.',
              received: _now),
          isNull);
    });

    test('"bal" inside a merchant name is not a balance', () {
      final parsed = parseBankSms('Rs 300 spent at BALAJI STORES on card XX1234',
          received: _now);
      expect(parsed!.amountPaise, 30000);
    });

    test('a payment without a payee is not linked to a bill', () async {
      final store = _store();
      await store.addBill(
          name: 'Netflix',
          kind: BillKind.subscription,
          amountPaise: 99900,
          nextDueAt: _now);
      final import = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK',
          body: 'Rs 999.00 debited from a/c XX1234 on 12-11-26.',
          date: _now,
        ),
      ]);
      expect(import.drafts.single.billId, isNull);
    });

    test('the same SMS from the receiver and the inbox imports once',
        () async {
      final store = _store();
      const body =
          'Rs 250.00 debited from a/c XX1234 on 12-11-26 to SWIGGY. Avl Bal Rs 9,000';
      await store.applySmsImport(buildSmsImport(store, [
        (address: 'VM-HDFCBK', body: body, date: _now),
      ]));
      final again = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK',
          body: body,
          date: _now.add(const Duration(seconds: 7)),
        ),
      ]);
      expect(again.drafts, isEmpty);
      expect(store.pending.single.dedupKey, isNotNull);
    });

    test('a statement row confirms a recurring draft instead of duplicating',
        () async {
      final store = _store();
      await store.addRecurring(
        kind: EntryKind.income,
        amountPaise: 5000000,
        category: 'Salary',
        title: 'Salary',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 11, 10),
      );
      expect(store.pending.single.source, 'recurring');
      // Paid three days late and a little more than expected.
      final import = buildStatementImport(store, [
        StatementRow(
          date: DateTime(2026, 11, 13),
          narration: 'NEFT ACME CORP PVT LTD',
          kind: EntryKind.income,
          amountPaise: 5050000,
        ),
      ]);
      expect(import.drafts, isEmpty);
      expect(import.duplicates, 1);
      await store.applyStatementImport(import);
      final draft = store.pending.single;
      expect(draft.bankConfirmed, isTrue);
      expect(draft.entry.amountPaise, 5050000);
    });

    test('a bank SMS for an approved recurring payment is not drafted again',
        () async {
      final store = _store();
      await store.addRecurring(
        kind: EntryKind.expense,
        amountPaise: 2000000,
        category: 'Rent',
        title: 'Rent',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 11, 10),
      );
      await store.approvePending(store.pending.single.id);
      final import = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK',
          body: 'Rs 20,000.00 debited from a/c XX1234 on 12-11-26 to RAVI KUMAR.',
          date: _now,
        ),
      ]);
      expect(import.drafts, isEmpty);
    });

    test('a recurring rule does not draft a payment already imported',
        () async {
      final store = _store();
      await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 2000000,
        category: 'Rent',
        title: 'RAVI KUMAR',
        occurredAt: DateTime(2026, 11, 10, 12),
        source: 'statement',
      );
      await store.addRecurring(
        kind: EntryKind.expense,
        amountPaise: 2000000,
        category: 'Rent',
        title: 'Rent',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 11, 10),
      );
      expect(store.pending, isEmpty);
    });

    test('a bank balance on a confirmed recurring entry becomes the latest',
        () async {
      final store = _store();
      final account = await store.addAccount('HDFC', AccountKind.bank,
          openingBalancePaise: 1000000);
      await store.addRecurring(
        kind: EntryKind.income,
        amountPaise: 5000000,
        category: 'Salary',
        title: 'Salary',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 11, 12),
      );
      await store.applySmsImport(buildSmsImport(store, [
        (
          address: 'VM-HDFCBK',
          body:
              'Rs 50,000.00 credited to a/c XX1234 on 12-11-26 by ACME CORP SALARY. Avl Bal Rs 61,000.00',
          date: _now,
        ),
      ]));
      final draft = store.pending.single;
      expect(draft.bankConfirmed, isTrue);
      expect(draft.entry.accountId, account.id);
      await store.approvePending(draft.id);
      expect(store.accountRunningBalance(account.id), 6100000);
    });

    test('an older bank balance does not overwrite a newer one', () async {
      final store = _store();
      final account = await store.addAccount('HDFC', AccountKind.bank);
      await store.addRecurring(
        kind: EntryKind.income,
        amountPaise: 5000000,
        category: 'Salary',
        title: 'Salary',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 11, 10),
      );
      final import = buildStatementImport(store, [
        StatementRow(
          date: DateTime(2026, 11, 10),
          narration: 'NEFT ACME CORP SALARY',
          kind: EntryKind.income,
          amountPaise: 5000000,
          balancePaise: 5000000,
        ),
        StatementRow(
          date: DateTime(2026, 11, 11),
          narration: 'UPI SWIGGY',
          kind: EntryKind.expense,
          amountPaise: 50000,
          balancePaise: 4950000,
        ),
      ], accountId: account.id);
      await store.applyStatementImport(import, accountId: account.id);
      expect(store.accountRunningBalance(account.id), 4950000);
      final salary =
          store.pending.firstWhere((draft) => draft.source == 'recurring');
      await store.approvePending(salary.id);
      expect(store.accountRunningBalance(account.id), 4950000,
          reason: 'the closing balance already includes the salary');
    });

    test('approving a draft the bank balance already includes keeps it',
        () async {
      final store = _store();
      final account = await store.addAccount('HDFC', AccountKind.bank);
      await store.addRecurring(
        kind: EntryKind.expense,
        amountPaise: 2000000,
        category: 'Rent',
        title: 'Rent',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 11, 5),
        accountId: account.id,
      );
      await store.setAccountBalance(account.id, 3000000);
      await store.approvePending(store.pending.single.id);
      expect(store.accountRunningBalance(account.id), 3000000,
          reason: 'rent on the 5th is already in the balance set on the 12th');
      expect(store.accounts.single.availableBalancePaise, 3000000);
    });

    test('a zero balance still anchors the next row', () {
      expect(parseStatementBalance('0.00'), 0);
      expect(parseStatementBalance(''), isNull);
      expect(parseStatementDate('2026/10/31'), DateTime(2026, 10, 31));
    });
  });
}
