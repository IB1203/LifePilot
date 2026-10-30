import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/secure.dart';
import 'package:lifepilot_ai/features/more_page.dart';
import 'package:lifepilot_ai/main.dart';

final _now = DateTime(2026, 10, 30, 10);

DataCipher _cipher([int fill = 7]) => DataCipher(List<int>.filled(32, fill));

Future<Directory> _tempDir() async {
  final directory = await Directory.systemTemp.createTemp('lp_security');
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

File _dataFile(Directory directory) =>
    File('${directory.path}/lifepilot.local.v1.json');

Future<void> _addLunch(LifePilotStore store) => store.addEntry(
    kind: EntryKind.expense,
    amountPaise: 25000,
    category: 'Food',
    title: 'Secret lunch',
    occurredAt: _now);

void main() {
  group('DataCipher', () {
    test('round-trips text and bytes', () async {
      final cipher = _cipher();
      final sealed = await cipher.sealText('hello ₹');
      expect(DataCipher.isSealedText(sealed), isTrue);
      expect(sealed, isNot(contains('hello')));
      expect(await cipher.openText(sealed), 'hello ₹');

      final bytes = await cipher.sealBytes([1, 2, 3, 250]);
      expect(DataCipher.isSealedBytes(bytes), isTrue);
      expect(await cipher.openBytes(bytes), [1, 2, 3, 250]);
    });

    test('rejects another key and tampered data', () async {
      final sealed = await _cipher().sealBytes([1, 2, 3]);
      await expectLater(
          _cipher(8).openBytes(sealed), throwsA(isA<WrongPasswordException>()));
      final tampered = [...sealed]..[20] ^= 1;
      await expectLater(_cipher().openBytes(tampered),
          throwsA(isA<WrongPasswordException>()));
      expect(DataCipher.isSealedText('{"format":"lifepilot-backup"}'), isFalse);
    });

    test('lockout grows with repeated failures', () {
      expect(pinLockoutFor(4), isNull);
      expect(pinLockoutFor(5), const Duration(seconds: 30));
      expect(pinLockoutFor(7), isNull);
      expect(pinLockoutFor(10), const Duration(minutes: 1));
      expect(pinLockoutFor(15), const Duration(minutes: 5));
      expect(pinLockoutFor(20), const Duration(minutes: 30));
      expect(pinLockoutFor(35), const Duration(minutes: 30));
    });
  });

  group('encrypted records file', () {
    test('is written encrypted and reads back with the same key', () async {
      final directory = await _tempDir();
      final store =
          await LifePilotStore.load(directory: directory, cipher: _cipher());
      expect(store.encryptedAtRest, isTrue);
      await _addLunch(store);

      final raw = await _dataFile(directory).readAsString();
      expect(DataCipher.isSealedText(raw), isTrue);
      expect(raw, isNot(contains('Secret lunch')));

      final reloaded =
          await LifePilotStore.load(directory: directory, cipher: _cipher());
      expect(reloaded.entries.single.title, 'Secret lunch');
      expect(reloaded.storageError, isNull);
    });

    test('is left untouched without the key or with the wrong key', () async {
      final directory = await _tempDir();
      final store =
          await LifePilotStore.load(directory: directory, cipher: _cipher());
      await _addLunch(store);
      final before = await _dataFile(directory).readAsString();

      for (final cipher in [null, _cipher(9)]) {
        final locked =
            await LifePilotStore.load(directory: directory, cipher: cipher);
        expect(locked.storageError, isNotNull);
        expect(locked.entries, isEmpty);
        await _addLunch(locked);
        expect(await _dataFile(directory).readAsString(), before,
            reason: 'nothing may overwrite records it could not read');
      }
    });

    test('a plain file and its upgrade copies are encrypted in place',
        () async {
      final directory = await _tempDir();
      final plain = await LifePilotStore.load(directory: directory);
      expect(plain.encryptedAtRest, isFalse);
      await _addLunch(plain);
      final oldCopy =
          File('${directory.path}/lifepilot.local.v1.v2.backup.json');
      await oldCopy.writeAsString(plain.exportJson());

      final upgraded =
          await LifePilotStore.load(directory: directory, cipher: _cipher());
      expect(upgraded.encryptionUpgraded, isTrue);
      expect(upgraded.entries.single.title, 'Secret lunch');
      for (final file in [_dataFile(directory), oldCopy]) {
        final raw = await file.readAsString();
        expect(DataCipher.isSealedText(raw), isTrue, reason: file.path);
        expect(raw, isNot(contains('Secret lunch')));
      }
      expect(await _cipher().openText(await oldCopy.readAsString()),
          contains('Secret lunch'));
      expect(directory.listSync().where((item) => item.path.endsWith('.tmp')),
          isEmpty);
    });
  });

  group('settings and records', () {
    test('wrong PINs and the lockout survive a restart', () async {
      final directory = await _tempDir();
      final store =
          await LifePilotStore.load(directory: directory, cipher: _cipher());
      DateTime? until;
      for (var i = 0; i < 5; i++) {
        until = await store.recordPinFailure();
      }
      expect(until, isNotNull);
      final reloaded =
          await LifePilotStore.load(directory: directory, cipher: _cipher());
      expect(reloaded.settings.pinFailures, 5);
      expect(reloaded.settings.pinLockedUntil, until);
      await reloaded.clearPinFailures();
      expect(reloaded.settings.pinFailures, 0);
      expect(reloaded.settings.pinLockedUntil, isNull);
    });

    test('new security settings round-trip and drive the secure screen', () {
      const settings = AppSettings(
          lockEnabled: true, confirmSensitive: false, allowScreenshots: true);
      final copy = AppSettings.fromJson(settings.toJson());
      expect(copy.confirmSensitive, isFalse);
      expect(copy.allowScreenshots, isTrue);
      expect(const AppSettings().confirmSensitive, isTrue);
      expect(const AppSettings(lockEnabled: true).secureScreen, isTrue);
      expect(copy.secureScreen, isFalse);
      expect(const AppSettings().secureScreen, isFalse);
    });

    test('receipt paths are repointed on entries and drafts', () async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      await store.addEntry(
          kind: EntryKind.expense,
          amountPaise: 100,
          category: 'Food',
          title: 'Tea',
          occurredAt: _now,
          receiptPath: '/r/a.jpg');
      await store.replaceReceiptPath('/r/a.jpg', '/r/a.jpg.lps');
      expect(store.entries.single.receiptPath, '/r/a.jpg.lps');
    });
  });

  group('lock screen', () {
    Future<LifePilotStore> lockedStore(LockScope scope) async {
      final store = LifePilotStore.inMemory(clock: () => _now);
      final pin = await hashPin('2580', iterations: 1000);
      await store.updateSettings(store.settings.copyWith(
        lockEnabled: true,
        pinHash: pin.hash,
        pinSalt: pin.salt,
        lockUseBiometrics: false,
        lockScope: scope,
      ));
      return store;
    }

    Future<void> pump(WidgetTester tester, LifePilotStore store) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(LifePilotApp(store: store));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, String digits) async {
      for (final digit in digits.split('')) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }

    testWidgets('five wrong PINs block the pad and are remembered',
        (tester) async {
      final store = await lockedStore(LockScope.app);
      await pump(tester, store);
      for (var i = 0; i < 5; i++) {
        await enter(tester, '111111');
      }
      expect(store.settings.pinFailures, 5);
      expect(store.settings.pinLockedUntil, isNotNull);
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      // While blocked, even the right PIN does nothing.
      await enter(tester, '2580');
      expect(find.text('LifePilot is locked'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('deleting all data asks for the PIN first', (tester) async {
      final store = await lockedStore(LockScope.finance);
      await _addLunch(store);
      await pump(tester, store);
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text('More')));
      await tester.pumpAndSettle();
      final delete = find.text('Delete all local data');
      final moreList = find.descendant(
          of: find.byType(MorePage), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(delete, 300, scrollable: moreList.first);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm it\'s you'), findsOneWidget);
      expect(store.entries, hasLength(1), reason: 'nothing deleted yet');

      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(store.entries, hasLength(1), reason: 'cancelled');

      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      await enter(tester, '2580');
      expect(store.entries, isEmpty);
    });
  });
}
