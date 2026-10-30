import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/personal.dart';
import 'package:lifepilot_ai/core/recurrence.dart';
import 'package:lifepilot_ai/core/secure.dart';
import 'package:lifepilot_ai/services/report_export.dart';

void main() {
  var now = DateTime(2026, 10, 30, 10);
  late LifePilotStore store;

  setUp(() {
    now = DateTime(2026, 10, 30, 10);
    store = LifePilotStore.inMemory(clock: () => now);
  });

  group('accounts and transfers', () {
    test('balance = opening + income − expenses ± transfers', () async {
      final bank = await store.addAccount('HDFC', AccountKind.bank,
          openingBalancePaise: 1000000);
      final cash = await store.addAccount('Cash', AccountKind.cash);
      await store.addEntry(
          kind: EntryKind.income,
          amountPaise: 5000000,
          category: 'Salary',
          title: 'Salary',
          occurredAt: now,
          accountId: bank.id);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 30000,
          category: 'Food',
          title: 'Lunch',
          occurredAt: now,
          accountId: cash.id);
      await store.addTransfer(
          fromAccountId: bank.id, toAccountId: cash.id, amountPaise: 200000);
      expect(accountBalance(bank, store.entries, store.transfers), 5800000);
      expect(accountBalance(cash, store.entries, store.transfers), 170000);
      // Transfers are not income or expenses.
      expect(store.monthIncome, 5000000);
      expect(store.monthExpenses, 30000);
    });

    test('transfer to the same account is rejected', () async {
      final bank = await store.addAccount('HDFC', AccountKind.bank);
      expect(
          () => store.addTransfer(
              fromAccountId: bank.id, toAccountId: bank.id, amountPaise: 1),
          throwsArgumentError);
    });

    test('deleting an account unlinks its entries', () async {
      final cash = await store.addAccount('Cash', AccountKind.cash);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 100,
          category: 'Food',
          title: 'Tea',
          occurredAt: now,
          accountId: cash.id);
      await store.deleteAccount(cash.id);
      expect(store.entries.single.accountId, isNull);
      expect(store.entries.single.amountPaise, 100);
    });
  });

  group('recurring entries', () {
    test('due occurrences become drafts, never recorded entries', () async {
      await store.addRecurring(
        kind: EntryKind.income,
        amountPaise: 5000000,
        category: 'Salary',
        title: 'Salary',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 9, 1),
      );
      expect(store.entries, isEmpty);
      expect(store.pending.map((item) => item.entry.occurredAt.month), [9, 10]);
      expect(store.recurring.single.nextDate, DateTime(2026, 11, 1));

      // Running again prepares nothing new.
      expect(await store.prepareDueRecurring(), 0);
      now = DateTime(2026, 11, 1, 8);
      expect(await store.prepareDueRecurring(), 1);
      expect(store.pending, hasLength(3));
    });

    test('approving records the entry; dismissing does not', () async {
      await store.addRecurring(
        kind: EntryKind.expense,
        amountPaise: 1500000,
        category: 'Home',
        title: 'Rent',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime(2026, 10, 5),
      );
      final draft = store.pending.single;
      final saved = await store.approvePending(draft.id,
          edited: draft.entry.copyWith(amountPaise: 1600000));
      expect(saved.amountPaise, 1600000);
      expect(saved.source, 'recurring');
      expect(store.pending, isEmpty);
      expect(store.entries, hasLength(1));
    });

    test('a one-time rule deactivates after its draft', () async {
      await store.addRecurring(
        kind: EntryKind.expense,
        amountPaise: 100,
        category: 'Other',
        title: 'Once',
        recurrence: Recurrence.none,
        firstDate: DateTime(2026, 10, 1),
      );
      expect(store.pending, hasLength(1));
      expect(store.recurring.single.active, isFalse);
    });
  });

  group('habits', () {
    test('streak counts applicable completed days', () async {
      final habit = await store.addHabit('Walk');
      final id = habit.id;
      // Created today; backdate creation to allow history.
      await store.updateHabit(store.habits.single.copyWith());
      store.habits[0] =
          Habit(id: id, name: 'Walk', createdAt: DateTime(2026, 10, 1));
      for (final day in [27, 28, 29]) {
        await store.toggleHabit(id, day: DateTime(2026, 10, day));
      }
      expect(habitStreak(store.habits.single, now), 3,
          reason: 'today not done yet still counts to yesterday');
      await store.toggleHabit(id);
      expect(habitStreak(store.habits.single, now), 4);
      await store.toggleHabit(id); // undo today
      expect(store.habits.single.doneOn(now), isFalse);
    });

    test('weekday-only habits skip other days', () {
      // Weekdays only; 24–25 Oct 2026 is a weekend.
      final habit = Habit(
        id: 'h',
        name: 'Gym',
        createdAt: DateTime(2026, 10, 1),
        weekdays: const [1, 2, 3, 4, 5],
        checkIns: [
          DateTime(2026, 10, 23),
          DateTime(2026, 10, 26),
          DateTime(2026, 10, 27),
          DateTime(2026, 10, 28),
          DateTime(2026, 10, 29),
          DateTime(2026, 10, 30),
        ],
      );
      expect(habitStreak(habit, now), 6);
      expect(habitCompletion(habit, now, days: 7), 1.0);
    });
  });

  group('category suggestions', () {
    test('learns from past entries', () {
      final entries = [
        for (var i = 0; i < 3; i++)
          LedgerEntry(
            id: '$i',
            kind: EntryKind.expense,
            amountPaise: 100,
            category: 'Food',
            title: 'Swiggy order',
            merchant: 'Swiggy',
            occurredAt: now,
          ),
        LedgerEntry(
          id: 'x',
          kind: EntryKind.expense,
          amountPaise: 100,
          category: 'Transport',
          title: 'Uber ride',
          occurredAt: now,
        ),
      ];
      expect(suggestCategory(entries, 'Swiggy'), 'Food');
      expect(suggestCategory(entries, 'uber to office'), 'Transport');
      expect(suggestCategory(entries, 'something new'), isNull);
      expect(
          suggestCategory(entries, 'Swiggy', kind: EntryKind.income), isNull);
    });
  });

  group('bank SMS parsing', () {
    test('UPI debit', () {
      final sms = parseBankSms(
          'Rs.250.00 debited from A/c XX1234 on 29-10-26 to VPA swiggy@icici UPI Ref 123456789012. Not you? Call 1800');
      expect(sms!.kind, EntryKind.expense);
      expect(sms.amountPaise, 25000);
      expect(sms.counterparty, 'swiggy@icici');
      expect(sms.accountHint, '1234');
      expect(sms.reference, '123456789012');
    });

    test('card spend and salary credit', () {
      final spend = parseBankSms(
          'INR 1,499.00 spent on your Card ending 5678 at AMAZON PAY on 29-Oct-26. Avl Lmt INR 50,000');
      expect(spend!.kind, EntryKind.expense);
      expect(spend.amountPaise, 149900);
      expect(spend.counterparty, 'AMAZON PAY');
      expect(spend.accountHint, '5678');

      final credit = parseBankSms(
          'Your a/c no. XXXXXX4321 is credited with Rs 50,000.00 on 01-11-26 from ACME CORP. Avbl bal Rs 1,02,000');
      expect(credit!.kind, EntryKind.income);
      expect(credit.amountPaise, 5000000);
      expect(credit.counterparty, 'ACME CORP');
    });

    test('ignores OTPs, reminders, requests and failures', () {
      for (final text in [
        '123456 is your OTP for a transaction of Rs 500 at Amazon.',
        'Your electricity bill of Rs 1,200 is due on 05-11-26.',
        'Ravi has requested money Rs 300 from you on UPI.',
        'Transaction of Rs 400 failed at Flipkart.',
        'Rs 2,000 will be debited on 03-11 towards your SIP.',
        'Hello, your parcel is out for delivery.',
      ]) {
        expect(parseBankSms(text), isNull, reason: text);
      }
    });

    test('drafts are created once per message', () async {
      final entry = LedgerEntry(
        id: '',
        kind: EntryKind.expense,
        amountPaise: 100,
        category: 'Food',
        title: 'Tea',
        occurredAt: now,
      );
      final key = smsFingerprint('HDFCBK', 'body', now);
      expect(await store.addSmsDrafts([(key: key, text: 'body', entry: entry)]),
          1);
      expect(await store.addSmsDrafts([(key: key, text: 'body', entry: entry)]),
          0);
      await store.dismissPending(store.pending.single.id);
      expect(
          await store.addSmsDrafts([(key: key, text: 'body', entry: entry)]), 0,
          reason: 'dismissed messages are not offered again');
    });
  });

  group('security', () {
    test('encrypted backup round-trips and rejects a wrong password', () async {
      await store.addTask(title: 'Secret plan', project: '');
      final json = store.exportJson();
      final encrypted =
          await encryptBackup(json, 'correct horse', iterations: 2000);
      expect(encrypted, isNot(contains('Secret plan')));
      expect(isEncryptedBackup(encrypted), isTrue);
      expect(isEncryptedBackup(json), isFalse);
      expect(await decryptBackup(encrypted, 'correct horse'), json);
      await expectLater(decryptBackup(encrypted, 'wrong'),
          throwsA(isA<WrongPasswordException>()));
    });

    test('PIN is stored as a salted hash and verifies', () async {
      final first = await hashPin('2580', iterations: 1000);
      final second = await hashPin('2580', iterations: 1000);
      expect(first.hash, isNot(contains('2580')));
      expect(first.salt, isNot(second.salt));
      expect(await verifyPin('2580', first.hash, first.salt), isTrue);
      expect(await verifyPin('2581', first.hash, first.salt), isFalse);
    });

    test('a saved lock without a PIN is treated as off', () {
      final settings = AppSettings.fromJson({'lockEnabled': true});
      expect(settings.lockEnabled, isFalse);
    });
  });

  group('weekly review', () {
    test('summarises the current week from records', () async {
      final task = await store.addTask(
          title: 'Report', project: '', dueAt: DateTime(2026, 10, 29));
      await store.setTaskStatus(task.id, TaskStatus.done);
      await store.addTask(
          title: 'Next week task', project: '', dueAt: DateTime(2026, 11, 3));
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 50000,
          category: 'Food',
          title: 'Dinner',
          occurredAt: DateTime(2026, 10, 27));
      await store.addBill(
          name: 'Internet',
          kind: BillKind.internet,
          amountPaise: 99900,
          nextDueAt: DateTime(2026, 11, 4));
      final review = WeeklyReview.build(
        entries: store.entries,
        tasks: store.tasks,
        sessions: store.focusSessions,
        habits: store.habits,
        budgets: store.budgets,
        bills: store.bills,
        now: now,
      );
      expect(review.range.start, DateTime(2026, 10, 26));
      expect(review.tasksCompleted, 1);
      expect(review.summary.expenses, 50000);
      expect(review.nextWeekBills.single.name, 'Internet');
      expect(review.nextWeekTasks.single.title, 'Next week task');
      expect(review.habitRate, isNull);
    });
  });

  group('monthly report files', () {
    test('PDF and Excel are generated from records', () async {
      await store.addEntry(
          kind: EntryKind.income,
          amountPaise: 5000000,
          category: 'Salary',
          title: 'Salary',
          occurredAt: DateTime(2026, 10, 1));
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 32000,
          category: 'Food',
          title: 'Groceries',
          occurredAt: DateTime(2026, 10, 3));
      final report = MonthlyReport.from(store, DateTime(2026, 10));
      expect(report.summary.netCashFlow, 4968000);
      expect(report.entries, hasLength(2));
      final pdf = await buildReportPdf(report);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      final xlsx = buildReportXlsx(report);
      expect(xlsx.take(2), [0x50, 0x4B], reason: 'xlsx is a zip file');
      expect(report.fileStem, 'lifepilot-2026-10');
    });
  });

  group('persistence', () {
    test('new collections survive a restart; fresh install needs setup',
        () async {
      final directory = await Directory.systemTemp.createTemp('lp_v3');
      addTearDown(() => directory.delete(recursive: true));
      final fresh = await LifePilotStore.load(directory: directory);
      expect(fresh.settings.onboarded, isFalse);
      final account = await fresh.addAccount('Cash', AccountKind.cash);
      await fresh.addHabit('Read');
      await fresh.addRecurring(
        kind: EntryKind.expense,
        amountPaise: 100,
        category: 'Bills',
        title: 'Phone',
        recurrence: const Recurrence(Repeat.monthly),
        firstDate: DateTime.now().add(const Duration(days: 3)),
      );
      await fresh.updateSettings(fresh.settings
          .copyWith(onboarded: true, themeMode: AppThemeMode.dark));

      final reloaded = await LifePilotStore.load(directory: directory);
      expect(reloaded.accountById(account.id)!.name, 'Cash');
      expect(reloaded.habits.single.name, 'Read');
      expect(reloaded.recurring.single.title, 'Phone');
      expect(reloaded.settings.onboarded, isTrue);
      expect(reloaded.settings.themeMode, AppThemeMode.dark);
    });
  });
}
