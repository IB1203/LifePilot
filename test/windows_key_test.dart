import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifepilot_ai/core/local_store.dart';
import 'package:lifepilot_ai/core/models.dart';
import 'package:lifepilot_ai/core/secure.dart';
import 'package:lifepilot_ai/services/windows_key.dart';

void main() {
  test('DPAPI data key is created once, reused, and opens the records',
      () async {
    final directory = await Directory.systemTemp.createTemp('lp_win');
    addTearDown(() => directory.delete(recursive: true));
    final key = await windowsDataKey(directory);
    expect(key, hasLength(32));
    final stored = await File('${directory.path}/lifepilot.key').readAsBytes();
    expect(stored.length, greaterThan(32), reason: 'stored wrapped, not raw');
    expect(await windowsDataKey(directory), key);

    final store = await LifePilotStore.load(
        directory: directory, cipher: DataCipher(key));
    await store.addEntry(
        kind: EntryKind.expense,
        amountPaise: 100,
        category: 'Food',
        title: 'Desktop tea',
        occurredAt: DateTime(2026, 10, 30));
    final raw =
        await File('${directory.path}/lifepilot.local.v1.json').readAsString();
    expect(raw, isNot(contains('Desktop tea')));
    final reloaded = await LifePilotStore.load(
        directory: directory,
        cipher: DataCipher(await windowsDataKey(directory)));
    expect(reloaded.entries.single.title, 'Desktop tea');
  }, skip: !Platform.isWindows);
}
