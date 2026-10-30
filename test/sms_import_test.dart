import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/sms_import.dart';
import 'package:lifepilot_ai/core/upi.dart';
import 'package:lifepilot_ai/features/money_extras.dart';
import 'package:lifepilot_ai/features/sms_settings_page.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 10, 30, 10);

SmsMessage _sms(String address, String body, [DateTime? date]) =>
    (address: address, body: body, date: date ?? _now);

void main() {
  late LifePilotStore store;
  setUp(() => store = LifePilotStore.inMemory(clock: () => _now));

  test('a bank SMS confirms the matching UPI draft instead of duplicating it',
      () async {
    final handoff = await store.recordHandoff(
        payee: 'Swiggy', amountPaise: 25000, vpa: 'swiggy@icici');
    await store.reportHandoffResult(
        handoff.id,
        const UpiResponse(
            status: UpiReported.success, approvalRef: '430912345678'));
    final import = buildSmsImport(store, [
      _sms('VM-HDFCBK-S',
          'Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 30/10/26 Ref 430912345678'),
    ]);
    expect(import.drafts, isEmpty);
    expect(import.confirmations, hasLength(1));
    await store.applySmsImport(import);
    final draft = store.pending.single;
    expect(draft.bankConfirmed, isTrue);
    expect(
        draft.sourceText, contains('Confirmed by a bank SMS from HDFC Bank'));
    expect(draft.sourceText, isNot(contains('Not verified')));
  });

  test('already recorded transactions are skipped, new ones drafted', () async {
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 25000,
        category: 'Food',
        title: 'Swiggy',
        note: 'UPI ref 430912345678',
        occurredAt: _now);
    final import = buildSmsImport(store, [
      _sms('AX-ICICIB',
          'ICICI Bank Acct XX123 debited for Rs 250.00 on 30-Oct-26; SWIGGY credited. UPI:430912345678.'),
      _sms('AX-ICICIB',
          'ICICI Bank Acct XX123 debited for Rs 80.00 on 30-Oct-26; CHAI POINT credited. UPI:430912345999.'),
    ]);
    expect(import.duplicates, hasLength(1));
    expect(import.drafts.single.entry.title, 'CHAI POINT');
    await store.applySmsImport(import);
    // Importing the same messages again does nothing.
    final again = buildSmsImport(store, [
      _sms('AX-ICICIB',
          'ICICI Bank Acct XX123 debited for Rs 80.00 on 30-Oct-26; CHAI POINT credited. UPI:430912345999.'),
    ]);
    expect(again.isEmpty, isTrue);
  });

  test('scams are held back with a redacted snippet', () async {
    final import = buildSmsImport(store, [
      _sms('+919812345678',
          'Dear customer your SBI a/c will be blocked today. Update KYC at http://sbi-kyc.xyz Avl Bal Rs 50,000'),
      _sms('+919812345679', 'Running late, see you at 7'),
    ]);
    expect(import.drafts, isEmpty);
    expect(import.suspicious, hasLength(1));
    expect(import.suspicious.single.snippet, isNot(contains('http')));
    await store.applySmsImport(import);
    expect(store.suspiciousSms, hasLength(1));
    expect(store.seenSms, hasLength(1),
        reason: 'personal messages are not remembered');
    await store.dismissSuspicious(store.suspiciousSms.single.key);
    expect(store.suspiciousSms, isEmpty);
  });

  test('rules, refunds, warnings, message dates and redaction', () async {
    await store.addCategoryRule('zomato', 'Food');
    await store
        .updateSettings(store.settings.copyWith(largePaymentPaise: 1000000));
    final import = buildSmsImport(store, [
      _sms('JD-KOTAKB',
          'Sent Rs.640.00 from Kotak Bank AC X1234 to zomato@hdfcbank on 28-10-26.UPI Ref 430900000001. Avl Bal Rs 9,000.00'),
      _sms('VM-HDFCBK',
          'Refund of Rs 499.00 from AMAZON has been credited to your card XX5678 on 29-10-26.'),
      _sms('AD-MYCOOP',
          'Your A/c XX99 debited with INR 15,000.00 on 30-10-2026 towards UPI/430900000002/FURNITURE MART.'),
    ]);
    final food = import.drafts[0];
    expect(food.entry.category, 'Food');
    expect(food.entry.occurredAt, DateTime(2026, 10, 28, 12));
    expect(food.sourceText, isNot(contains('9,000')));
    final refund = import.drafts[1];
    expect(refund.entry.kind, EntryKind.income);
    expect(refund.entry.category, 'Refunds');
    expect(refund.entry.title, 'Refund from AMAZON');
    final unknown = import.drafts[2];
    expect(unknown.warning, contains('not a known bank sender'));
    expect(unknown.warning, contains('Large debit'));

    await store.updateSettings(store.settings
        .copyWith(extraSmsSenders: ['MYCOOP'], keepSmsText: true));
    final trusted = buildSmsImport(store, [
      _sms('AD-MYCOOP',
          'Your A/c XX99 debited with INR 150.00 on 30-10-2026 towards UPI/430900000003/TEA STALL. Avl Bal INR 10.00'),
    ]);
    expect(trusted.drafts.single.warning, isEmpty);
    expect(trusted.drafts.single.sourceText, contains('Avl Bal'));
  });

  test('forgetting SMS text keeps drafts and fingerprints', () async {
    await store.applySmsImport(buildSmsImport(store, [
      _sms('VM-HDFCBK',
          'Rs.120.00 debited from A/c XX1234 to VPA tea@ybl on 30-10-26'),
      _sms('+911234567890', 'Your a/c is blocked, click http://x.xyz now'),
    ]));
    await store.forgetSmsText();
    expect(store.pending.single.sourceText, isEmpty);
    expect(store.suspiciousSms, isEmpty);
    expect(store.seenSms, hasLength(2));
  });

  test('new lists survive backup and restore', () async {
    await store.addCategoryRule('uber', 'Transport');
    await store.applySmsImport(buildSmsImport(store, [
      _sms('+911234567890', 'Your a/c is blocked, click http://x.xyz now'),
    ]));
    final copy = LifePilotStore.inMemory(clock: () => _now);
    await copy.restoreJson(store.exportJson());
    expect(copy.categoryRules.single.category, 'Transport');
    expect(copy.suspiciousSms, hasLength(1));
  });

  testWidgets('scam messages and draft warnings are shown', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await store.applySmsImport(buildSmsImport(store, [
      _sms('+911234567890', 'Your a/c is blocked, click http://x.xyz now'),
      _sms('AD-MYCOOP',
          'Your A/c XX99 debited with INR 150.00 on 30-10-2026 towards UPI/430900000003/TEA STALL.'),
    ]));
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: RecurringTab(store: store))));
    await tester.pumpAndSettle();
    expect(find.textContaining('not a known bank sender'), findsOneWidget);
    expect(find.text('Possible scam messages (1)'), findsOneWidget);
    await tester.tap(find.text('What to do'));
    await tester.pumpAndSettle();
    expect(find.text('Lost money? Call 1930'), findsOneWidget);
  });

  testWidgets('category rules can be added in Bank SMS settings',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: SmsSettingsPage(store: store)));
    await tester.pumpAndSettle();
    final add = find.widgetWithText(TextButton, 'Add');
    await tester.scrollUntilVisible(add, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('New category rule'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zomato');
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    expect(store.categoryRules.single.contains, 'zomato');
    expect(find.text('Contains "zomato"'), findsOneWidget);
  });
}
