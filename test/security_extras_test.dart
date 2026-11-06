import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/safe_paths.dart';
import 'package:lifepilot_ai/core/tax_rules.dart';

final _now = DateTime(2026, 11, 6, 12);

/// Backups can be edited by someone else before they are restored. These
/// tests cover the ways a crafted backup could try to misuse LifePilot.
void main() {
  group('stored file paths', () {
    const folder = '/data/app/files/vault';

    test('only files LifePilot created in its own folder are touched', () {
      expect(isOwnFile('$folder/doc-1730000000.pdf.lps', folder, vaultFileName),
          isTrue);
      expect(isOwnFile('$folder/doc-1730000000.jpg', folder, vaultFileName),
          isTrue);
      // The records file, a sibling folder, traversal, and odd names.
      expect(
          isOwnFile(
              '/data/app/files/lifepilot-data.json', folder, vaultFileName),
          isFalse);
      expect(isOwnFile('$folder/../lifepilot-data.json', folder, vaultFileName),
          isFalse);
      expect(
          isOwnFile('$folder/sub/doc-1.pdf', folder, vaultFileName), isFalse);
      expect(
          isOwnFile('/data/app/files/vault2/doc-1.pdf', folder, vaultFileName),
          isFalse);
      expect(isOwnFile('$folder/notes.txt', folder, vaultFileName), isFalse);
      // Windows separators are handled the same way.
      expect(
          isOwnFile(r'C:\app\receipts\receipt-123.jpg', r'C:\app\receipts',
              receiptFileName),
          isTrue);
      expect(
          isOwnFile(r'C:\app\receipts\..\data.json', r'C:\app\receipts',
              receiptFileName),
          isFalse);
    });

    test('shared copies cannot be written outside their folder', () {
      expect(safeFileName('../../lifepilot-data.json'), 'lifepilot-data.json');
      expect(safeFileName(r'..\..\evil.pdf'), 'evil.pdf');
      expect(safeFileName('.hidden'), 'document');
      expect(safeFileName(''), 'document');
      expect(safeFileName('bill? <copy>.pdf'), 'bill_ _copy_.pdf');
    });
  });

  group('restoring a crafted backup', () {
    Future<LifePilotStore> withData() async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 100,
          category: 'Food',
          title: 'Tea',
          occurredAt: _now);
      return store;
    }

    Map<String, dynamic> backup(LifePilotStore store) =>
        jsonDecode(store.exportJson()) as Map<String, dynamic>;

    for (final (name, key, item) in [
      (
        'a debt with a negative amount',
        'debts',
        {
          'id': 'd',
          'name': 'Loan',
          'kind': 'loan',
          'openingPaise': -500,
          'startDate': '2026-01-01T00:00:00.000',
        }
      ),
      (
        'an investment with an impossible SIP day',
        'investments',
        {'id': 'i', 'name': 'Fund', 'kind': 'mutualFund', 'sipDay': 45}
      ),
      (
        'a trip that ends before it starts',
        'trips',
        {
          'id': 't',
          'name': 'Trip',
          'start': '2026-11-10T00:00:00.000',
          'end': '2026-11-01T00:00:00.000',
          'budgetPaise': 100,
        }
      ),
    ]) {
      test('$name is refused and nothing changes', () async {
        final store = await withData();
        final crafted = backup(store)..[key] = [item];
        final target = LifePilotStore.inMemory(clock: () => _now);
        await target.addEntry(
            kind: EntryKind.income,
            amountPaise: 999,
            category: 'Salary',
            title: 'Mine',
            occurredAt: _now);
        await expectLater(target.restoreJson(jsonEncode(crafted)),
            throwsA(isA<FormatException>()));
        expect(target.entries.single.title, 'Mine');
      });
    }

    test('tax rules that do not validate are dropped, not trusted', () async {
      final store = await withData();
      final crafted = backup(store)
        ..['taxRules'] = {
          '2026-27': '{"schemaVersion": 1, "financialYear": "2026-27"}',
          '2027-28':
              builtInTaxRules['2026-27']!.replaceAll('"2026-27"', '"2027-28"'),
        };
      final target = LifePilotStore.inMemory(clock: () => _now);
      await target.restoreJson(jsonEncode(crafted));
      expect(target.taxRuleOverrides.keys, ['2027-28']);
      expect(target.taxRulesFor('2026-27').custom, isFalse);
    });
  });
}
