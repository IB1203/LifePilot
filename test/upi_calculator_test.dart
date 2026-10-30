import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/calculator.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/upi.dart';
import 'package:lifepilot_ai/features/calculator_page.dart';
import 'package:lifepilot_ai/features/upi_page.dart';

final _now = DateTime(2026, 10, 30, 10);

Payee _payee(String name, String vpa) =>
    Payee(id: vpa, name: name, vpa: vpa, createdAt: _now);

void main() {
  group('UPI QR parsing', () {
    test('reads a merchant QR and passes its fields on unchanged', () {
      final request = UpiRequest.parse(
          'upi://pay?pa=cafe.blr@okaxis&pn=Blue%20Tokai%20Cafe&mc=5814&tr=ORD123&am=249.00&cu=INR&tn=Order+42&sign=abc');
      expect(request.vpa, 'cafe.blr@okaxis');
      expect(request.name, 'Blue Tokai Cafe');
      expect(request.amountPaise, 24900);
      expect(request.note, 'Order 42');
      expect(request.isMerchant, isTrue);
      expect(request.isSigned, isTrue);
      expect(request.amountFixed, isTrue);
      final link = request.toLink(amountPaise: 1);
      expect(
          link,
          startsWith(
              'upi://pay?pa=cafe.blr@okaxis&pn=Blue%20Tokai%20Cafe&mc=5814&tr=ORD123&am=249.00&cu=INR'));
      expect(link, contains('sign=abc'));
      expect(link, contains('tn=Order%2042'));
      expect(link, isNot(contains('+')));
    });

    test('a personal QR without an amount takes the typed amount', () {
      final request = UpiRequest.parse('UPI://pay?pa=Ravi.K@ybl&pn=Ravi');
      expect(request.amountPaise, isNull);
      expect(request.amountFixed, isFalse);
      final link = request.toLink(amountPaise: 15050, note: 'Dinner');
      expect(link, contains('am=150.50'));
      expect(link, contains('tn=Dinner'));
    });

    test('rejects codes that are not safe one-time payments', () {
      for (final (code, reason) in [
        ('https://example.com', 'not UPI'),
        ('upi://mandate?pa=a@b&am=100', 'mandate'),
        ('upi://pay?pn=NoId', 'no UPI ID'),
        ('upi://pay?pa=bad id@x', 'invalid UPI ID'),
        ('upi://pay?pa=a1@okicici&cu=USD', 'foreign currency'),
        ('upi://pay?pa=a1@okicici&am=-5', 'negative amount'),
        ('upi://pay?pa=a1@okicici&am=abc', 'bad amount'),
        ('upi://pay?pa=a1@okicici&pa=evil@ybl', 'repeated field'),
      ]) {
        expect(() => UpiRequest.parse(code), throwsFormatException,
            reason: reason);
      }
    });

    test('validates typed UPI IDs', () {
      expect(validateVpa('ravi@ybl'), isNull);
      expect(validateVpa('9876543210@paytm'), isNull);
      expect(validateVpa(''), isNotNull);
      expect(validateVpa('ravi'), isNotNull);
      expect(validateVpa('ra vi@ybl'), isNotNull);
      expect(validateVpa('ravi@1bank'), isNotNull);
    });
  });

  group('UPI warnings', () {
    final saved = [
      _payee('Swiggy', 'swiggy@icici'),
      _payee('Amma', 'amma.home@okhdfcbank'),
    ];

    List<UpiWarning> check(UpiRequest request, {int? amount}) =>
        upiWarnings(request,
            amountPaise: amount, payees: saved, largePaymentPaise: 1000000);

    test('flags look-alike UPI IDs and reused names', () {
      final lookAlike = check(const UpiRequest(vpa: 'swiqgy@icici'));
      expect(lookAlike.any((w) => w.risk == UpiRisk.danger), isTrue);
      final homoglyph = check(const UpiRequest(vpa: 'arnma.home@okhdfcbank'));
      expect(homoglyph.any((w) => w.risk == UpiRisk.danger), isTrue);
      final reusedName =
          check(const UpiRequest(vpa: 'amma1990@ybl', name: 'Amma'));
      expect(reusedName.first.message, contains('different UPI ID'));
    });

    test('known payees get no first-payment warning; large amounts do', () {
      expect(check(const UpiRequest(vpa: 'Swiggy@ICICI')), isEmpty);
      final large =
          check(const UpiRequest(vpa: 'swiggy@icici'), amount: 2500000);
      expect(large.single.message, contains('Large payment'));
      final stranger = check(const UpiRequest(vpa: 'shop.kumar@ybl'));
      expect(stranger.single.risk, UpiRisk.caution);
    });
  });

  group('UPI app responses', () {
    test('reads success, failure, cancellation and missing results', () {
      final success = UpiResponse.parse(
          'txnId=AXB123&responseCode=00&Status=SUCCESS&txnRef=ORD1&ApprovalRefNo=430912',
          resultOk: true);
      expect(success.status, UpiReported.success);
      expect(success.reference, '430912');
      expect(
          UpiResponse.parse('Status=FAILURE&responseCode=ZM', resultOk: true)
              .status,
          UpiReported.failure);
      expect(UpiResponse.parse('status=submitted', resultOk: true).status,
          UpiReported.submitted);
      expect(UpiResponse.parse(null, resultOk: false).status,
          UpiReported.cancelled);
      expect(UpiResponse.parse('', resultOk: true).status, UpiReported.unknown);
    });

    test('a reported success becomes one unverified draft; failure none',
        () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 100,
          category: 'Food',
          title: 'Earlier',
          merchant: 'swiggy@icici',
          occurredAt: _now.subtract(const Duration(days: 2)));
      final handoff = await store.recordHandoff(
          payee: 'Swiggy', amountPaise: 45000, vpa: 'swiggy@icici');
      const success =
          UpiResponse(status: UpiReported.success, approvalRef: '430912');
      final draft = await store.reportHandoffResult(handoff.id, success);
      expect(draft, isNotNull);
      expect(draft!.source, 'upi');
      expect(draft.entry.amountPaise, 45000);
      expect(draft.entry.category, 'Food', reason: 'learned from the payee');
      expect(draft.sourceText, contains('Not verified'));
      expect(store.entries, hasLength(1), reason: 'nothing recorded yet');
      expect(await store.reportHandoffResult(handoff.id, success), isNull);
      expect(store.handoffs.first.status, 'success');

      final failed = await store.recordHandoff(
          payee: 'Shop', amountPaise: 100, vpa: 'shop@ybl');
      expect(
          await store.reportHandoffResult(
              failed.id, const UpiResponse(status: UpiReported.failure)),
          isNull);
      expect(store.pending, hasLength(1));
    });

    test('payees and handoff details survive backup and restore', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.savePayee('Ravi', 'ravi@ybl');
      await store.savePayee('Ravi K', 'RAVI@ybl');
      expect(store.payees.single.name, 'Ravi K');
      await store.notePayeePaid('ravi@ybl');
      final handoff = await store.recordHandoff(
          payee: 'Ravi', amountPaise: 500, vpa: 'ravi@ybl', appName: 'PhonePe');
      await store.reportHandoffResult(handoff.id,
          const UpiResponse(status: UpiReported.failure, transactionId: 'T9'));
      final copy = LifePilotStore.inMemory(clock: () => _now);
      await copy.restoreJson(store.exportJson());
      expect(copy.payees.single.timesPaid, 1);
      expect(copy.handoffs.single.appName, 'PhonePe');
      expect(copy.handoffs.single.status, 'failure');
      expect(copy.handoffs.single.bankReference, 'T9');
    });
  });

  group('calculator', () {
    test('evaluates arithmetic with precedence and brackets', () {
      expect(evaluateExpression('2+3×4'), 14);
      expect(evaluateExpression('(2+3)×4'), 20);
      expect(evaluateExpression('10÷4'), 2.5);
      expect(evaluateExpression('−5+2'), -3);
      expect(evaluateExpression('2*3/4'), 1.5);
    });

    test('percentages work like a phone calculator', () {
      expect(evaluateExpression('1200+18%'), closeTo(1416, 1e-9));
      expect(evaluateExpression('200−10%'), closeTo(180, 1e-9));
      expect(evaluateExpression('50%'), 0.5);
      expect(evaluateExpression('200×10%'), closeTo(20, 1e-9));
    });

    test('incomplete or invalid input gives no result', () {
      expect(evaluateExpression(''), isNull);
      expect(evaluateExpression('5+'), isNull);
      expect(evaluateExpression('10÷0'), isNull);
      expect(evaluateExpression('(2+3'), isNull);
      expect(evaluateExpression('2..3'), isNull);
    });

    test('results are shown without float noise', () {
      expect(formatCalculatorResult(evaluateExpression('0.1+0.2')!), '0.3');
      expect(formatCalculatorResult(1416), '1416');
      expect(formatCalculatorResult(2.5), '2.5');
    });

    testWidgets('keypad builds an expression and shows the result',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final store = LifePilotStore.inMemory(clock: () => _now);
      await tester.pumpWidget(MaterialApp(home: CalculatorPage(store: store)));
      for (final key in ['1', '2', '0', '0', '+', '1', '8', '%']) {
        await tester.tap(find.text(key));
        await tester.pump();
      }
      expect(find.text('= 1416'), findsOneWidget);
      await tester.tap(find.text('='));
      await tester.pump();
      expect(
          tester.widget<Text>(find.byKey(const Key('calculator-input'))).data,
          '1416');
    });
  });

  testWidgets('a scanned payment is reviewed, handed off and drafted',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    String? launched;
    const channel = MethodChannel('lifepilot/upi');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'apps') return <Object?>[];
      launched = (call.arguments as Map)['uri'] as String;
      return {
        'ok': true,
        'response': 'txnId=AXB1&Status=SUCCESS&ApprovalRefNo=777',
      };
    });
    final store = LifePilotStore.inMemory(clock: () => _now);
    await store.savePayee('Swiggy', 'swiggy@icici');
    final request =
        UpiRequest.parse('upi://pay?pa=swiqgy@icici&pn=Swiggy&am=300&cu=INR');
    await tester.pumpWidget(
        MaterialApp(home: UpiReviewPage(store: store, request: request)));
    await tester.pumpAndSettle();

    expect(find.text('₹300.00'), findsWidgets);
    expect(find.textContaining('different UPI ID'), findsOneWidget);
    final pay = find.textContaining('Pay ₹300.00');
    await tester.scrollUntilVisible(pay, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.tap(pay);
    await tester.pumpAndSettle();
    expect(find.text('This payee needs a closer look'), findsOneWidget);
    await tester.tap(find.text('Pay anyway'));
    await tester.pumpAndSettle();

    expect(launched, startsWith('upi://pay?pa=swiqgy@icici'));
    expect(find.text('UPI app reported success'), findsOneWidget);
    expect(store.handoffs.single.bankReference, '777');
    expect(store.pending.single.source, 'upi');
    expect(store.entries, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('without a UPI app nothing is recorded', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('lifepilot/upi');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'apps') return <Object?>[];
      throw PlatformException(code: 'no_app');
    });
    final store = LifePilotStore.inMemory(clock: () => _now);
    await tester.pumpWidget(MaterialApp(
        home: UpiReviewPage(
            store: store,
            request: UpiRequest.parse(
                'upi://pay?pa=teststore@okaxis&pn=Test&am=1.00'))));
    await tester.pumpAndSettle();
    final pay = find.textContaining('Pay ₹1.00');
    await tester.scrollUntilVisible(pay, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.tap(pay);
    await tester.pumpAndSettle();
    expect(find.textContaining('No UPI app'), findsOneWidget);
    expect(store.handoffs, isEmpty);
    expect(store.payees, isEmpty);

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('hidden apps: allow reveals them, Other UPI app is default',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var granted = false;
    Object? payPackage = 'unset';
    const channel = MethodChannel('lifepilot/upi');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      switch (call.method) {
        case 'apps':
          return granted
              ? [
                  {'package': 'com.phonepe.app', 'name': 'PhonePe'},
                  {'package': 'com.flipkart.upi', 'name': 'Flipkart'},
                ]
              : [
                  {'package': 'com.flipkart.upi', 'name': 'Flipkart'},
                ];
        case 'appListAccess':
          return granted ? 'granted' : 'denied';
        case 'requestAppListAccess':
          granted = true;
          return true;
        case 'pay':
          payPackage = (call.arguments as Map)['package'];
          return {'ok': false, 'response': null};
      }
      return null;
    });
    final store = LifePilotStore.inMemory(clock: () => _now);
    await tester.pumpWidget(MaterialApp(
        home: UpiReviewPage(
            store: store,
            request: UpiRequest.parse('upi://pay?pa=shop@ybl&am=10'))));
    await tester.pumpAndSettle();

    expect(find.text('Show all your UPI apps'), findsOneWidget);
    expect(find.text('PhonePe'), findsNothing);
    final otherChip = find.widgetWithText(ChoiceChip, 'Other UPI app');
    await tester.scrollUntilVisible(otherChip, 200,
        scrollable: find.byType(Scrollable).first);
    final other = tester.widget<ChoiceChip>(otherChip);
    expect(other.selected, isTrue, reason: 'no app is forced');

    await tester.ensureVisible(find.text('Allow'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(find.text('PhonePe'), findsOneWidget);
    expect(find.text('Show all your UPI apps'), findsNothing);

    final pay = find.textContaining('Pay ₹10.00');
    await tester.scrollUntilVisible(pay, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.tap(pay);
    await tester.pumpAndSettle();
    expect(payPackage, isNull, reason: 'Android picker shows every app');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
}
