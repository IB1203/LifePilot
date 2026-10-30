import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The Windows counterpart of Android's DeviceKey: a random 256-bit data
/// key stored in a file protected with DPAPI (CryptProtectData), so only
/// this Windows user account on this PC can unwrap it.

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(Pointer<_DataBlob>, Pointer<Void>,
    Pointer<Void>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _CryptDart = int Function(Pointer<_DataBlob>, Pointer<Void>,
    Pointer<Void>, Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

const _uiForbidden = 0x1;

Uint8List _crypt(List<int> input, {required bool protect}) {
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final function = crypt32.lookupFunction<_CryptNative, _CryptDart>(
      protect ? 'CryptProtectData' : 'CryptUnprotectData');
  final localFree =
      kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  return using((arena) {
    final data = arena<Uint8>(input.length);
    data.asTypedList(input.length).setAll(0, input);
    final blobIn = arena<_DataBlob>()
      ..ref.cbData = input.length
      ..ref.pbData = data;
    final blobOut = arena<_DataBlob>();
    final ok = function(
        blobIn, nullptr, nullptr, nullptr, nullptr, _uiForbidden, blobOut);
    if (ok == 0) {
      throw StateError(
          'Windows could not ${protect ? 'protect' : 'unprotect'} the data key.');
    }
    final result =
        Uint8List.fromList(blobOut.ref.pbData.asTypedList(blobOut.ref.cbData));
    localFree(blobOut.ref.pbData.cast());
    // Do not leave the clear key in native memory longer than needed.
    data.asTypedList(input.length).fillRange(0, input.length, 0);
    return result;
  });
}

/// Returns the data key kept in [folder], creating it on first use. Never
/// replaces an existing key file: data sealed with it would be lost.
Future<Uint8List> windowsDataKey(Directory folder) async {
  final file = File('${folder.path}/lifepilot.key');
  if (await file.exists()) {
    final key = _crypt(await file.readAsBytes(), protect: false);
    if (key.length != 32) throw StateError('The data key file is damaged.');
    return key;
  }
  await folder.create(recursive: true);
  final random = Random.secure();
  final key = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsBytes(_crypt(key, protect: true), flush: true);
  // Check the wrapped key opens before relying on it.
  final check = _crypt(await temporary.readAsBytes(), protect: false);
  if (check.length != 32 || !_same(check, key)) {
    await temporary.delete();
    throw StateError('The data key could not be stored.');
  }
  await temporary.rename(file.path);
  return key;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
