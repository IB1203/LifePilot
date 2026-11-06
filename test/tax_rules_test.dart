import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/tax_rules.dart';
import 'package:lifepilot_ai/features/tax_page.dart';
import 'package:lifepilot_ai/ui/theme.dart';

final _now = DateTime(2026, 11, 6, 12);

void main() {
  final rules = parseTaxRules(builtInTaxRules['2026-27']!);

  test('financial year runs April to March', () {
    expect(financialYearOf(_now), '2026-27');
    expect(financialYearOf(DateTime(2027, 3, 31)), '2026-27');
    expect(financialYearOf(DateTime(2027, 4, 1)), '2027-28');
    expect(financialYearOf(DateTime(1999, 4, 1)), '1999-00');
  });

  group('new regime', () {
    int tax(int salary, {int other = 0}) =>
        computeTax(rules, TaxInput(salary: salary, otherIncome: other),
                newRegime: true)
            .total;

    test('₹12.75 lakh salary is tax-free (standard deduction + rebate)', () {
      expect(tax(1275000), 0);
    });

    test('just above ₹12 lakh taxable: marginal relief', () {
      // Taxable ₹12,10,000: tax limited to the ₹10,000 above the limit,
      // plus 4% cess.
      final result =
          computeTax(rules, const TaxInput(salary: 1285000), newRegime: true);
      expect(result.taxableIncome, 1210000);
      expect(result.total, 10400);
      expect(result.steps.join('\n'), contains('marginal relief'));
    });

    test('₹15 lakh salary', () {
      // ₹14,25,000 taxable: 20,000 + 40,000 + 33,750, plus 4% cess.
      expect(tax(1500000), 97500);
    });

    test('surcharge with marginal relief just above ₹50 lakh', () {
      // Without relief: ₹10,83,000 + ₹1,08,300 surcharge. With relief the
      // extra cannot exceed the ₹10,000 above ₹50 lakh.
      final result = computeTax(rules, const TaxInput(otherIncome: 5010000),
          newRegime: true);
      expect(result.slabTax, 1083000);
      expect(result.surcharge, 7000);
      expect(result.total, 1090000 + 43600);
    });
  });

  group('old regime', () {
    test('80C is capped; slabs by age', () {
      const input =
          TaxInput(salary: 1000000, section80C: 200000, otherDeductions: 50000);
      final below60 = computeTax(rules, input, newRegime: false);
      // ₹7,50,000 taxable: 12,500 + 50,000, plus cess.
      expect(below60.taxableIncome, 750000);
      expect(below60.total, 65000);
      final senior = computeTax(
          rules,
          const TaxInput(
              salary: 1000000,
              section80C: 150000,
              otherDeductions: 50000,
              age: AgeGroup.senior),
          newRegime: false);
      expect(senior.slabTax, 60000);
    });

    test('rebate up to ₹5 lakh taxable', () {
      expect(
          computeTax(rules, const TaxInput(salary: 550000), newRegime: false)
              .total,
          0);
    });
  });

  test('GST added or taken out, with the CGST/SGST split', () {
    final added = gst(1000, 18);
    expect(added.gst, closeTo(180, 1e-9));
    expect(added.total, closeTo(1180, 1e-9));
    expect(added.cgst, closeTo(90, 1e-9));
    final included = gst(1180, 18, inclusive: true);
    expect(included.base, closeTo(1000, 1e-9));
    expect(
        rules.gstRates.map((item) => item.rate), containsAll([0, 5, 18, 40]));
  });

  group('rules files', () {
    Map<String, dynamic> copy() =>
        jsonDecode(builtInTaxRules['2026-27']!) as Map<String, dynamic>;

    test('invalid files are refused with a reason', () {
      expect(() => parseTaxRules('{not json'), throwsA(isA<FormatException>()));
      final unordered = copy();
      (unordered['newRegime']['slabs'] as List)[1]['upTo'] = 100;
      expect(
          () => parseTaxRules(jsonEncode(unordered)),
          throwsA(predicate(
              (e) => e is FormatException && e.message.contains('in order'))));
      final badRate = copy()..['cessPercent'] = 150;
      expect(() => parseTaxRules(jsonEncode(badRate)),
          throwsA(isA<FormatException>()));
    });

    test('a diff lists exactly what changes', () {
      final next = copy()
        ..['financialYear'] = '2027-28'
        ..['newRegime']['standardDeduction'] = 100000;
      expect(diffTaxRules(builtInTaxRules['2026-27']!, jsonEncode(next)), [
        'financialYear: 2026-27 → 2027-28',
        'newRegime.standardDeduction: 75000 → 100000',
      ]);
    });

    test('next year falls back to the latest rules until updated', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      expect(store.taxRulesFor('2026-27').exact, isTrue);
      final fallback = store.taxRulesFor('2027-28');
      expect(fallback.exact, isFalse);
      expect(parseTaxRules(fallback.source).financialYear, '2026-27');

      final next = copy()
        ..['financialYear'] = '2027-28'
        ..['newRegime']['standardDeduction'] = 100000;
      await store.saveTaxRules(jsonEncode(next));
      final updated = store.taxRulesFor('2027-28');
      expect(updated.custom, isTrue);
      expect(parseTaxRules(updated.source).newRegime.standardDeduction, 100000);
      expect(() => store.saveTaxRules('{}'), throwsA(isA<FormatException>()));

      final restored = LifePilotStore.inMemory(clock: () => _now);
      await restored.restoreJson(store.exportJson());
      expect(restored.taxRulesFor('2027-28').custom, isTrue);

      await store.resetTaxRules('2027-28');
      expect(store.taxRulesFor('2027-28').exact, isFalse);
    });
  });

  testWidgets('tax page compares regimes and calculates GST', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final store = LifePilotStore.inMemory(clock: () => _now);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: TaxPage(store: store),
    ));
    await tester.pumpAndSettle();
    expect(find.text('FY 2026-27 (this year)'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Salary or pension for the year'),
        '1500000');
    await tester.pumpAndSettle();
    expect(find.text('₹97,500.00'), findsOneWidget);
    expect(find.textContaining('The new regime saves'), findsOneWidget);

    final price = find.widgetWithText(TextField, 'Price before GST');
    await tester.scrollUntilVisible(price, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(price, '1000');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('₹1,180.00'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('₹1,180.00'), findsOneWidget);
    expect(find.text('CGST 9%'), findsOneWidget);
  });
}
