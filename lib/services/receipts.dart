import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/local_store.dart';
import '../core/secure.dart';

/// Encrypted receipts end with this, after the original extension.
const _sealedSuffix = '.lps';

Future<Directory> _receiptFolder() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/receipts');

/// Takes or picks a receipt photo and copies it into the app's private
/// storage, encrypted with the device key when [cipher] is given, so it
/// stays available if the original is deleted. Returns the stored path, or
/// null if the user cancelled.
Future<String?> captureReceipt(
    {required bool camera, DataCipher? cipher}) async {
  final picked = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 80,
  );
  if (picked == null) return null;
  final folder = await _receiptFolder();
  await folder.create(recursive: true);
  final extension =
      picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
  final name = 'receipt-${DateTime.now().microsecondsSinceEpoch}.$extension';
  final String stored;
  if (cipher == null) {
    stored = '${folder.path}/$name';
    await File(picked.path).copy(stored);
  } else {
    stored = '${folder.path}/$name$_sealedSuffix';
    await File(stored).writeAsBytes(
        await cipher.sealBytes(await picked.readAsBytes()),
        flush: true);
  }
  // The picker leaves a plain copy in the app cache; remove it.
  try {
    await File(picked.path).delete();
  } on FileSystemException {
    // Not ours to delete on some devices (e.g. a gallery original).
  }
  return stored;
}

/// Removes a stored receipt file. Missing files are ignored.
Future<void> deleteReceiptFile(String? path) async {
  if (path == null) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // The record no longer points at it; a stray file is harmless.
  }
}

Future<Uint8List> _readReceipt(String path, DataCipher? cipher) async {
  final bytes = await File(path).readAsBytes();
  if (!path.endsWith(_sealedSuffix)) return bytes;
  if (cipher == null) throw StateError('The device key is not available.');
  return Uint8List.fromList(await cipher.openBytes(bytes));
}

Future<void> showReceipt(
        BuildContext context, String path, DataCipher? cipher) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Receipt')),
          backgroundColor: Colors.black,
          body: Center(
            child: FutureBuilder<Uint8List>(
              future: _readReceipt(path, cipher),
              builder: (context, snapshot) {
                const failed = Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('The receipt image could not be opened.',
                      style: TextStyle(color: Colors.white)),
                );
                if (snapshot.hasError) return failed;
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                return InteractiveViewer(
                  maxScale: 5,
                  child: Image.memory(
                    snapshot.data!,
                    errorBuilder: (_, __, ___) => failed,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

/// Encrypts receipt photos saved before encryption was available and points
/// their entries at the encrypted copies. Each plain file is deleted only
/// after the encrypted copy has been checked and the records saved.
Future<int> encryptPlainReceipts(LifePilotStore store) async {
  final cipher = store.dataCipher;
  if (cipher == null || store.storageError != null) return 0;
  final paths = {
    for (final entry in store.entries) entry.receiptPath,
    for (final draft in store.pending) draft.entry.receiptPath,
  }.whereType<String>().where((path) => !path.endsWith(_sealedSuffix));
  var converted = 0;
  for (final path in paths) {
    try {
      final source = File(path);
      if (!await source.exists()) continue;
      final clear = await source.readAsBytes();
      final sealed = await cipher.sealBytes(clear);
      final target = File('$path$_sealedSuffix');
      await target.writeAsBytes(sealed, flush: true);
      final check = await cipher.openBytes(await target.readAsBytes());
      if (check.length != clear.length) {
        await target.delete();
        continue;
      }
      await store.replaceReceiptPath(path, target.path);
      if (store.storageError != null) return converted;
      await source.delete();
      converted++;
    } on Object {
      // Leave this photo as it was; it is retried on the next start.
    }
  }
  return converted;
}

/// Deletes stored receipt photos that no entry or draft refers to any more,
/// for example after an entry was deleted.
Future<int> cleanOrphanReceipts(Set<String> referenced) async {
  try {
    final folder = await _receiptFolder();
    if (!await folder.exists()) return 0;
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
