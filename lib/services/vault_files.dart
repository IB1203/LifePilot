import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/safe_paths.dart';
import '../core/secure.dart';

/// Encrypted ends with this, after the original extension.
const _sealedSuffix = '.lps';

Future<Directory> _folder(String name) async {
  final folder =
      Directory('${(await getApplicationSupportDirectory()).path}/$name');
  await folder.create(recursive: true);
  return folder;
}

/// Saves a document into the app's private vault folder, encrypted with
/// the device key when [cipher] is available. Returns the stored path.
Future<String> storeVaultFile(
    Uint8List bytes, String fileName, DataCipher? cipher) async {
  final folder = await _folder('vault');
  final extension = fileName.contains('.') ? fileName.split('.').last : 'bin';
  final base =
      '${folder.path}/doc-${DateTime.now().microsecondsSinceEpoch}.$extension';
  if (cipher == null) {
    await File(base).writeAsBytes(bytes, flush: true);
    return base;
  }
  final path = '$base$_sealedSuffix';
  await File(path).writeAsBytes(await cipher.sealBytes(bytes), flush: true);
  return path;
}

Future<bool> _isOwnDocument(String path) async =>
    isOwnFile(path, (await _folder('vault')).path, vaultFileName);

Future<Uint8List> readVaultFile(String path, DataCipher? cipher) async {
  if (!await _isOwnDocument(path)) {
    throw StateError('Not a document stored by LifePilot.');
  }
  final bytes = await File(path).readAsBytes();
  if (!path.endsWith(_sealedSuffix)) return bytes;
  if (cipher == null) throw StateError('The device key is not available.');
  return Uint8List.fromList(await cipher.openBytes(bytes));
}

Future<void> deleteVaultFile(String? path) async {
  if (path == null || !await _isOwnDocument(path)) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // The record no longer points at it; a stray file is harmless.
  }
}

/// Deletes vault files no record points at (after "delete all data", or
/// a restore from another phone). Also clears old shared copies.
Future<int> cleanOrphanVaultFiles(Set<String> referenced) async {
  await clearSharedCopies();
  try {
    final folder = await _folder('vault');
    var removed = 0;
    await for (final item in folder.list()) {
      if (item is File && !referenced.contains(item.path)) {
        await item.delete();
        removed++;
      }
    }
    return removed;
  } on FileSystemException {
    return 0;
  }
}

/// A plain copy for sharing or opening in another app. Copies are kept in
/// one cache folder that [clearSharedCopies] empties, so decrypted
/// documents do not pile up.
Future<File> sharedCopy(Uint8List bytes, String fileName) async {
  final folder =
      Directory('${(await getTemporaryDirectory()).path}/vault-share');
  await folder.create(recursive: true);
  final file = File('${folder.path}/${safeFileName(fileName)}');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> clearSharedCopies() async {
  try {
    final folder =
        Directory('${(await getTemporaryDirectory()).path}/vault-share');
    if (await folder.exists()) await folder.delete(recursive: true);
  } on Object {
    // Best effort.
  }
}
