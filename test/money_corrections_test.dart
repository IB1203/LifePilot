import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/bank_sms.dart';
import 'package:lifepilot_ai/core/debts.dart';
import 'package:lifepilot_ai/core/finance_calc.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/core/sms_import.dart';
import 'package:lifepilot_ai/core/statement_import.dart';
import 'package:lifepilot_ai/services/statement_files.dart';

final _now = DateTime(2026, 11, 10, 12);

LifePilotStore _store() => LifePilotStore.inMemory(clock: () => _now);

LedgerEntry _entry({
  required String id,
  required EntryKind kind,
  required int paise,
  required DateTime at,
  String title = 'Coffee',
  String merchant = '',
  String note = '',
  String? accountId,
}) =>
    LedgerEntry(
      id: id,
      kind: kind,
      amountPaise: paise,
      category: 'Food',
      title: title,
      occurredAt: at,
      merchant: merchant,
      note: note,
      accountId: accountId,
    );

void main() {
  group('transfers', () {
    test('editing and deleting a transfer keeps both balances in step',
        () async {
      final store = _store();
      final from = await store.addAccount('A', AccountKind.bank,
          openingBalancePaise: 100000);
      final to =
          await store.addAccount('B', AccountKind.bank, openingBalancePaise: 0);
      final transfer = await store.addTransfer(
          fromAccountId: from.id, toAccountId: to.id, amountPaise: 30000);
      expect(store.accountRunningBalance(from.id), 70000);
      expect(store.accountRunningBalance(to.id), 30000);

      await store.updateTransfer(transfer.id,
          fromAccountId: from.id, toAccountId: to.id, amountPaise: 50000);
      expect(store.accountRunningBalance(from.id), 50000);
      expect(store.accountRunningBalance(to.id), 50000);

      await store.deleteTransfer(transfer.id);
      expect(store.accountRunningBalance(from.id), 100000);
      expect(store.accountRunningBalance(to.id), 0);
      expect(store.transfers, isEmpty);
    });

    test('transfers are not counted as income or expense', () async {
      final store = _store();
      final from = await store.addAccount('A', AccountKind.bank);
      final to = await store.addAccount('B', AccountKind.bank);
      await store.addTransfer(
          fromAccountId: from.id, toAccountId: to.id, amountPaise: 50000);
      expect(store.entries, isEmpty);
    });
  });

  group('duplicates', () {
    test('same amount, kind and description on nearby days are grouped',
        () {
      final day = DateTime(2026, 11, 2);
      final groups = findDuplicateGroups([
        _entry(
            id: 'a',
            kind: EntryKind.expense,
            paise: 45000,
            at: day,
            title: 'BIG BAZAAR'),
        _entry(
            id: 'b',
            kind: EntryKind.expense,
            paise: 45000,
            at: day.add(const Duration(days: 1)),
            title: 'Big Bazaar'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.entries.map((entry) => entry.id), ['a', 'b']);
      expect(groups.single.duplicateIds, ['b']);
    });

    test('a shared reference groups entries even when the words differ', () {
      final day = DateTime(2026, 11, 2);
      final groups = findDuplicateGroups([
        _entry(
            id: 'a',
            kind: EntryKind.expense,
            paise: 25000,
            at: day,
            title: 'UPI payment',
            note: 'Ref 430912345678'),
        _entry(
            id: 'b',
            kind: EntryKind.expense,
            paise: 25000,
            at: day,
            title: 'SWIGGY',
            note: 'UTR 430912345678'),
      ]);
      expect(groups.single.entries, hasLength(2));
    });

    test('different merchants or kinds are left alone', () {
      final day = DateTime(2026, 11, 2);
      expect(
          findDuplicateGroups([
            _entry(
                id: 'a',
                kind: EntryKind.expense,
                paise: 10000,
                at: day,
                title: 'TEA STALL'),
            _entry(
                id: 'b',
                kind: EntryKind.expense,
                paise: 10000,
                at: day,
                title: 'BUS TICKET'),
          ]),
          isEmpty);
      expect(
          findDuplicateGroups([
            _entry(
                id: 'a',
                kind: EntryKind.expense,
                paise: 10000,
                at: day,
                title: 'SALARY'),
            _entry(
                id: 'b',
                kind: EntryKind.income,
                paise: 10000,
                at: day,
                title: 'SALARY'),
          ]),
          isEmpty);
    });

    test('merging removes the copy and recalculates the balance', () async {
      final store = _store();
      final account =
          await store.addAccount('HDFC', AccountKind.bank,
              openingBalancePaise: 100000);
      final first = await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 45000,
          category: 'Food',
          title: 'BIG BAZAAR',
          occurredAt: DateTime(2026, 11, 2),
          accountId: account.id);
      final second = await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 45000,
          category: 'Food',
          title: 'BIG BAZAAR',
          occurredAt: DateTime(2026, 11, 2),
          accountId: account.id,
          note: 'From SMS');
      expect(store.accountRunningBalance(account.id), 10000);

      final kept = await store.mergeEntries(first.id, [second.id]);
      expect(kept!.id, first.id);
      expect(kept.note, 'From SMS');
      expect(store.entries, hasLength(1));
      expect(store.accountRunningBalance(account.id), 55000);
    });
  });

  group('bulk corrections', () {
    test('one correction changes every matching entry', () async {
      final store = _store();
      for (var day = 1; day <= 3; day++) {
        await store.addEntry(
            kind: EntryKind.expense,
            amountPaise: 10000,
            category: 'Food',
            title: 'Lunch',
            occurredAt: DateTime(2026, 11, day),
            paymentMethod: 'Cash');
      }
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 2000,
          category: 'Travel',
          title: 'Bus',
          occurredAt: DateTime(2026, 11, 4),
          paymentMethod: 'Cash');

      final changed = await store.bulkCorrectEntries(
        where: (entry) => entry.paymentMethod == 'Cash',
        paymentMethod: 'UPI',
      );
      expect(changed, 4);
      expect(store.entries.every((entry) => entry.paymentMethod == 'UPI'),
          isTrue);

      final recategorized = await store.bulkCorrectEntries(
        where: (entry) => entry.category == 'Food',
        category: 'Dining',
      );
      expect(recategorized, 3);
    });

    test('moving entries to an account updates balances', () async {
      final store = _store();
      final cash =
          await store.addAccount('Cash', AccountKind.cash,
              openingBalancePaise: 50000);
      final bank =
          await store.addAccount('Bank', AccountKind.bank,
              openingBalancePaise: 50000);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 10000,
          category: 'Food',
          title: 'Lunch',
          occurredAt: DateTime(2026, 11, 2),
          accountId: cash.id);
      expect(store.accountRunningBalance(cash.id), 40000);
      expect(store.accountRunningBalance(bank.id), 50000);

      await store.bulkCorrectEntries(
          where: (entry) => entry.accountId == cash.id,
          accountId: bank.id);
      expect(store.accountRunningBalance(cash.id), 50000);
      expect(store.accountRunningBalance(bank.id), 40000);
    });
  });

  group('statement direction', () {
    test('a balance change decides direction when there is no marker', () {
      const csv = '''
Date,Description,Amount,Closing Balance
01/11/2026,Opening,,10000.00
02/11/2026,ABC STORE,500.00,9500.00
03/11/2026,XYZ ENTERPRISES,2000.00,11500.00
''';
      final parsed = parseStatementTable(
          readStatementTable('statement.csv', utf8.encode(csv)));
      expect(parsed.error, isNull);
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows.first.kind, EntryKind.expense);
      expect(parsed.rows.first.directionSource,
          StatementDirectionSource.balance);
      expect(parsed.rows.last.kind, EntryKind.income);
      expect(parsed.rows.last.directionSource, StatementDirectionSource.balance);
      expect(parsed.rows.any((row) => row.needsReview), isFalse);
    });

    test('a row with nothing to decide direction is flagged for review', () {
      const csv = '''
Date,Description,Amount
02/11/2026,ABC STORE,500.00
''';
      final parsed = parseStatementTable(
          readStatementTable('statement.csv', utf8.encode(csv)));
      expect(parsed.rows.single.needsReview, isTrue);
      expect(parsed.rows.single.directionSource,
          StatementDirectionSource.review);
    });

    test('a card reverses balance-derived rows only', () {
      final row = StatementRow(
        date: DateTime(2026, 11, 2),
        narration: 'ABC STORE',
        kind: EntryKind.expense,
        amountPaise: 50000,
        directionSource: StatementDirectionSource.balance,
      );
      expect(row.forAccount(creditCard: true).kind, EntryKind.income);
      expect(row.forAccount(creditCard: false).kind, EntryKind.expense);

      final marked = StatementRow(
        date: DateTime(2026, 11, 2),
        narration: 'ABC STORE',
        kind: EntryKind.expense,
        amountPaise: 50000,
        directionSource: StatementDirectionSource.columns,
      );
      expect(marked.forAccount(creditCard: true).kind, EntryKind.expense);
    });

    test('flipping a row swaps credit and debit and clears review', () {
      final row = StatementRow(
        date: DateTime(2026, 11, 2),
        narration: 'ABC STORE',
        kind: EntryKind.expense,
        amountPaise: 50000,
        needsReview: true,
      ).flipped();
      expect(row.kind, EntryKind.income);
      expect(row.needsReview, isFalse);
    });

    test('customers get credits from statement credits, not debits', () async {
      final store = _store();
      const csv = '''
Date,Description,Amount,Closing Balance
02/11/2026,ABC STORE,500.00,9500.00
03/11/2026,XYZ ENTERPRISES,2000.00,11500.00
''';
      final rows = parseStatementTable(
              readStatementTable('statement.csv', utf8.encode(csv)))
          .rows;
      final import = buildStatementImport(store, rows);
      expect(import.creditedPaise, 200000);
      expect(import.debitedPaise, 50000);
    });
  });

  group('bank balance sync', () {
    test('a report is matched by last four digits, and older ones are ignored',
        () async {
      final store = _store();
      final account = await store.addAccount('Salary account', AccountKind.bank,
          openingBalancePaise: 100000);
      await store.updateAccount(account.copyWith(last4: '1234'));

      final newer = BankBalance(
          bank: 'HDFC Bank',
          accountHint: '1234',
          paise: 600000,
          at: DateTime(2026, 11, 2));
      final first = SmsImport()..balances[newer.key] = newer;
      await store.applySmsImport(first);
      expect(store.accountRunningBalance(account.id), 600000);
      expect(store.lastSyncedFor(account), DateTime(2026, 11, 2));

      final older = BankBalance(
          bank: 'HDFC Bank',
          accountHint: '1234',
          paise: 500000,
          at: DateTime(2026, 11, 1));
      final second = SmsImport()..balances[older.key] = older;
      await store.applySmsImport(second);
      expect(store.accountRunningBalance(account.id), 600000,
          reason: 'an out-of-order message must not undo a newer balance');
    });

    test('the user can still choose an older balance deliberately', () async {
      final store = _store();
      final account = await store.addAccount('Salary account', AccountKind.bank,
          openingBalancePaise: 100000);
      await store.updateAccount(account.copyWith(last4: '1234'));
      final newer = BankBalance(
          bank: 'HDFC Bank',
          accountHint: '1234',
          paise: 600000,
          at: DateTime(2026, 11, 2));
      final older = BankBalance(
          bank: 'HDFC Bank',
          accountHint: '1234',
          paise: 500000,
          at: DateTime(2026, 11, 1));
      await store.adjustToBankBalance(newer);
      await store.adjustToBankBalance(older);
      expect(store.accountRunningBalance(account.id), 500000);
    });

    group('statement import account linking', () {
      test('auto-creates a suggested account when none matches', () async {
        final store = _store();
        final rows = [
          StatementRow(
            date: DateTime(2026, 11, 2),
            narration: 'SWIGGY',
            kind: EntryKind.expense,
            amountPaise: 25000,
          ),
        ];
        final import = buildStatementImport(store, rows);
        await store.applyStatementImport(
          import,
          balanceLabel: 'Bank of Baroda',
          bankName: 'Bank of Baroda',
          accountHint: '2596',
        );

        expect(store.accounts, hasLength(1),
            reason: 'a suggested account should be created');
        final account = store.accounts.single;
        expect(account.bankName, 'Bank of Baroda');
        expect(account.last4, '2596');
        expect(store.pending.single.entry.accountId, account.id,
            reason: 'the draft must be linked to the account');
      });

      test('matches an existing account by bank name and hint', () async {
        final store = _store();
        final existing = await store.addAccount(
            'Bank of Baroda ••2596', AccountKind.bank,
            openingBalancePaise: 100000);
        await store.updateAccount(existing.copyWith(
            bankName: 'Bank of Baroda', accountNumberMasked: 'XXXX 2596'));
        final rows = [
          StatementRow(
            date: DateTime(2026, 11, 2),
            narration: 'SWIGGY',
            kind: EntryKind.expense,
            amountPaise: 25000,
          ),
        ];
        final import = buildStatementImport(store, rows);
        await store.applyStatementImport(
          import,
          balanceLabel: 'Bank of Baroda',
          bankName: 'Bank of Baroda',
          accountHint: '2596',
        );

        expect(store.accounts, hasLength(1),
            reason: 'the existing account should be reused, not duplicated');
        expect(store.pending.single.entry.accountId, existing.id);
      });
    });

    group('reversal', () {
      test('reversing an expense creates an offsetting income entry', () async {
        final store = _store();
        final account =
            await store.addAccount('Bank', AccountKind.bank,
                openingBalancePaise: 100000);
        final original = await store.addEntry(
            kind: EntryKind.expense,
            amountPaise: 50000,
            category: 'Food',
            title: 'Groceries',
            occurredAt: DateTime(2026, 11, 2),
            accountId: account.id);
        expect(store.accountRunningBalance(account.id), 50000);

        final reversal = await store.reverseEntry(original.id);
        expect(reversal, isNotNull);
        expect(reversal!.kind, EntryKind.income);
        expect(reversal.amountPaise, 50000);
        expect(reversal.refundLinkId, original.id);
        expect(store.accountRunningBalance(account.id), 100000,
            reason: 'the reversal restores the account balance');
        expect(store.entries, hasLength(2),
            reason: 'the original entry is preserved in history');
      });

      test('reversing an income creates an offsetting expense entry', () async {
        final store = _store();
        final account =
            await store.addAccount('Bank', AccountKind.bank,
                openingBalancePaise: 0);
        final original = await store.addEntry(
            kind: EntryKind.income,
            amountPaise: 30000,
            category: 'Salary',
            title: 'Salary',
            occurredAt: DateTime(2026, 11, 2),
            accountId: account.id);
        expect(store.accountRunningBalance(account.id), 30000);

        final reversal = await store.reverseEntry(original.id);
        expect(reversal!.kind, EntryKind.expense);
        expect(reversal.amountPaise, 30000);
        expect(store.accountRunningBalance(account.id), 0);
      });

      test('reversing a missing entry returns null', () async {
        final store = _store();
        final result = await store.reverseEntry('does-not-exist');
        expect(result, isNull);
      });
    });

    test('an untracked bank balance creates an account, not an orphan', () async {
      final store = _store();
      final balance = BankBalance(
          bank: 'Bank of Baroda',
          accountHint: '2596',
          paise: 121713,
          at: DateTime(2026, 11, 2));
      await store.applySmsImport(SmsImport()..balances[balance.key] = balance);

      expect(store.accounts, hasLength(1));
      final account = store.accounts.single;
      expect(account.bankName, 'Bank of Baroda');
      expect(account.last4, '2596');
      expect(account.availableBalancePaise, 121713);
      expect(store.accountRunningBalance(account.id), 121713,
          reason: 'Accounts must agree with the balance Home shows');

      // a newer report updates the same account rather than adding another
      final newer = BankBalance(
          bank: 'Bank of Baroda',
          accountHint: '2596',
          paise: 137936,
          at: DateTime(2026, 11, 3));
      await store.applySmsImport(SmsImport()..balances[newer.key] = newer);
      expect(store.accounts, hasLength(1));
      expect(store.accountRunningBalance(account.id), 137936);
    });

    test('an SMS transaction links to the account its balance created',
        () async {
      final store = _store();
      final import = buildSmsImport(store, [
        (
          address: 'JD-KOTAKB',
          body:
              'Sent Rs.640.00 from Kotak Bank AC X1234 to zomato@hdfcbank on 10-11-26.UPI Ref 430900000001. Avl Bal Rs 9,000.00',
          date: _now,
        ),
      ]);
      expect(import.drafts, hasLength(1));
      await store.applySmsImport(import);

      final account = store.accounts.single;
      expect(account.bankName, 'Kotak Bank');
      expect(store.pending.single.entry.accountId, account.id,
          reason: 'the draft must point at the account, not stay unlinked');

      await store.approvePending(store.pending.single.id);
      expect(store.entries.single.accountId, account.id);
    });
  });

  group('SMS parsing', () {
    test('a sender template decides direction when keywords are ambiguous',
        () {
      final template = senderTemplateFor('HDFCBK')!;
      expect(template.direction('INR 500.00 debited from abc@ybl'),
          EntryKind.expense);
      expect(template.direction('INR 500.00 credited from abc@ybl'),
          EntryKind.income);
      expect(senderTemplateFor('unknown'), isNull);
    });

    test('promotional messages are never transactions', () {
      expect(ignorableSms('Get 10% cashback on your next purchase. Offer valid.'),
          isTrue);
      expect(looksLikeTransactionSms(
              'Get 10% cashback on your next purchase. Offer valid.',
              const SmsSender(SenderKind.bank, header: 'HDFCBK')),
          isFalse);
    });

    test('an unreadable bank message is kept for review, not dropped',
        () async {
      final store = _store();
      final import = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK-S',
          body:
              'HDFC Bank: Your card XX1234 has been debited. Avl Bal Rs 4,500.00',
          date: _now,
        ),
      ]);
      expect(import.unrecognized, hasLength(1));
      expect(import.unrecognized.single.sender, 'VM-HDFCBK-S');
      expect(import.handled, contains(import.unrecognized.single.key));

      await store.applySmsImport(import);
      expect(store.unrecognizedSms, hasLength(1));
      await store.dismissUnrecognized(store.unrecognizedSms.single.key);
      expect(store.unrecognizedSms, isEmpty);
    });
  });

  group('lending', () {
    test('overdue interest-free lending is reported with the days late',
        () async {
      final store = _store();
      final debt = await store.addDebt(
        name: 'Lent to Ravi',
        kind: DebtKind.lent,
        openingPaise: 500000,
        startDate: DateTime(2026, 10, 1),
        dueAt: DateTime(2026, 10, 20),
      );
      expect(debt.owedToMe, isTrue);
      expect(debt.isInterestFreeLending, isTrue);
      final overdue = overdueLending(store.debts, _now);
      expect(overdue, hasLength(1));
      expect(overdue.single.outstandingPaise, 500000);
      expect(overdue.single.daysOverdue, 21);
    });

    test('money returned can be recorded as income', () async {
      final store = _store();
      final account =
          await store.addAccount('Bank', AccountKind.bank,
              openingBalancePaise: 0);
      final debt = await store.addDebt(
          name: 'Lent to Ravi',
          kind: DebtKind.lent,
          openingPaise: 500000,
          startDate: DateTime(2026, 10, 1),
          dueAt: DateTime(2026, 10, 20));
      await store.addDebtPayment(debt.id,
          amountPaise: 200000, recordIncome: true, accountId: account.id);
      final inflow = store.entries.single;
      expect(inflow.kind, EntryKind.income);
      expect(inflow.category, 'Loans');
      expect(store.accountRunningBalance(account.id), 200000);
    });

    test('a lending reminder is planned for the due date', () async {
      final store = _store();
      await store.addDebt(
          name: 'Lent to Ravi',
          kind: DebtKind.lent,
          openingPaise: 500000,
          startDate: DateTime(2026, 10, 1),
          dueAt: DateTime(2026, 11, 20));
      final plan = store.notificationPlan();
      expect(plan.any((item) => item.payload.startsWith('debt:')), isTrue);
    });
  });

  group('bill payment via SMS (INT-017, INT-018)', () {
    test('an expense SMS matching an unpaid bill links to the bill',
        () async {
      final store = _store();
      final bill = await store.addBill(
          name: 'Electricity',
          kind: BillKind.electricity,
          amountPaise: 150000,
          nextDueAt: DateTime(2026, 11, 15));
      final import = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK-S',
          body:
              'Your A/c XX1234 debited with INR 1,500.00 on 15-11-26 towards UPI/430900000001/ELECTRICITY.',
          date: DateTime(2026, 11, 15),
        ),
      ]);
      expect(import.drafts, hasLength(1));
      expect(import.drafts.single.billId, isNotNull);
      expect(import.drafts.single.billId, bill.id,
          reason: 'the draft must link to the matched bill');
      expect(import.drafts.single.entry.billId, bill.id);
    });

    test('approving a bill-matched draft marks the bill paid once',
        () async {
      final store = _store();
      final account = await store.addAccount('HDFC Bank', AccountKind.bank,
          openingBalancePaise: 100000);
      await store.updateAccount(account.copyWith(last4: '1234'));
      final bill = await store.addBill(
          name: 'Electricity',
          kind: BillKind.electricity,
          amountPaise: 150000,
          nextDueAt: DateTime(2026, 11, 15));
      final import = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK-S',
          body:
              'Your A/c XX1234 debited with INR 1,500.00 on 15-11-26 towards UPI/430900000001/ELECTRICITY.',
          date: DateTime(2026, 11, 15),
        ),
      ]);
      await store.applySmsImport(import);
      await store.approvePending(store.pending.single.id);

      // One expense entry recorded.
      expect(store.entries, hasLength(1));
      expect(store.entries.single.billId, bill.id);
      // Bill is marked paid.
      expect(store.bills, isNotEmpty);
      final updated = store.bills.firstWhere((b) => b.id == bill.id,
          orElse: () => throw StateError('Bill not found'));
      expect(updated.payments.isNotEmpty, isTrue);
      expect(updated.payments.last.amountPaise, 150000);
      // Account balance decreased.
      expect(store.accountRunningBalance(account.id), 100000 - 150000,
          reason: 'bill payment debits the account');
    });

    test('an SMS payment to an unknown biller does not match any bill',
        () async {
      final store = _store();
      await store.addBill(
          name: 'Electricity',
          kind: BillKind.electricity,
          amountPaise: 150000,
          nextDueAt: DateTime(2026, 11, 15));
      final import = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK-S',
          body:
              'Your A/c XX1234 debited with INR 500.00 on 15-11-26 towards UPI/430900000002/UNKNOWN MERCHANT.',
          date: DateTime(2026, 11, 15),
        ),
      ]);
      expect(import.drafts, hasLength(1));
      expect(import.drafts.single.billId, isNull,
          reason: 'no bill match for an unknown merchant');
    });
  });

  group('UPI and card double-count prevention (INT-045, INT-078, INT-080)', () {
    test('UPI debit SMS matched to manual expense is not duplicated',
        () async {
      final store = _store();
      // Manual expense recorded first.
      await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 50000,
        category: 'Food',
        title: 'Swiggy',
        occurredAt: DateTime(2026, 11, 10, 10),
        note: 'UPI ref 430912345678',
        merchant: 'Swiggy',
      );
      // Bank SMS for the same UPI payment.
      final import = buildSmsImport(store, [
        (
          address: 'VM-HDFCBK-S',
          body:
              'Your A/c XX1234 debited with INR 500.00 on 10-11-26 towards UPI/430912345678/SWIGGY.',
          date: DateTime(2026, 11, 10, 12),
        ),
      ]);
      // The SMS should be detected as a duplicate of the manual entry.
      expect(import.duplicates, hasLength(1),
          reason: 'SPI payment matching a manual expense is a duplicate');
      expect(import.drafts, isEmpty,
          reason: 'no new draft created for duplicate UPI payment');
    });

    test('credit card purchase increases outstanding, bill payment is a transfer',
        () async {
      final store = _store();
      final card = await store.addAccount('HDFC Credit Card', AccountKind.card,
          openingBalancePaise: 0);
      final bank = await store.addAccount('Savings Account', AccountKind.bank,
          openingBalancePaise: 100000);

      // Card purchase: expense recorded, card outstanding increases.
      await store.addImportedEntry(LedgerEntry(
        id: 'card-purchase',
        kind: EntryKind.expense,
        amountPaise: 50000,
        category: 'Shopping',
        title: 'Amazon purchase',
        occurredAt: DateTime(2026, 11, 5),
        accountId: card.id,
        classification: TransactionClassification.expense,
      ));
      expect(store.entries.length, 1);
      expect(store.accountRunningBalance(card.id), -50000,
          reason: 'card outstanding increases by purchase amount');

      // Card bill payment: transfer from bank to card, not a second expense.
      await store.addTransfer(
        fromAccountId: bank.id,
        toAccountId: card.id,
        amountPaise: 50000,
        at: DateTime(2026, 11, 10),
      );
      expect(store.entries.length, 1,
          reason: 'transfer is not recorded as an entry/expense');
      expect(store.transfers, hasLength(1));
      expect(store.accountRunningBalance(card.id), 0,
          reason: 'card outstanding cleared by payment');
      expect(store.accountRunningBalance(bank.id), 50000,
          reason: 'bank balance decreased by payment');

      // Summary: only one expense (the purchase), no transfer counted.
      final summary = summarize(store.entries, monthRange(DateTime(2026, 11, 10)));
      expect(summary.expenses, 50000,
          reason: 'only the card purchase counts as expense');
      expect(summary.netCashFlow, -50000);
    });
  });

  group('cross-module validation (INT-092 to INT-110)', () {
    test('changing an entry account recalculates both accounts', () async {
      final store = _store();
      final a = await store.addAccount('A', AccountKind.bank,
          openingBalancePaise: 100000);
      final b = await store.addAccount('B', AccountKind.bank,
          openingBalancePaise: 50000);
      final entry = LedgerEntry(
        id: 'move-me',
        kind: EntryKind.expense,
        amountPaise: 20000,
        category: 'Food',
        title: 'Lunch',
        occurredAt: DateTime(2026, 11, 5),
        accountId: a.id,
      );
      await store.addImportedEntry(entry);
      expect(store.accountRunningBalance(a.id), 80000);
      expect(store.accountRunningBalance(b.id), 50000);

      // Move the entry to account B.
      await store.updateEntry(entry.copyWith(accountId: b.id));
      expect(store.accountRunningBalance(a.id), 100000,
          reason: 'old account balance restored');
      expect(store.accountRunningBalance(b.id), 30000,
          reason: 'new account balance debited');
    });

    test('deleting a recurring schedule keeps historical records (INT-103)',
        () async {
      final store = _store();
      final rule = await store.addRecurring(
        kind: EntryKind.expense,
        amountPaise: 10000,
        category: 'Food',
        title: 'Lunch',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 11, 1),
      );
      // Generate a draft for the recurring entry.
      await store.prepareDueRecurring();
      expect(store.pending, hasLength(1));
      await store.approvePending(store.pending.single.id);
      expect(store.entries, hasLength(1));

      // Delete the recurring schedule.
      await store.deleteRecurring(rule.id);
      expect(store.recurring, isEmpty);

      // Historical entry remains.
      expect(store.entries, hasLength(1));
      expect(store.entries.single.title, 'Lunch');
    });
  });
}
