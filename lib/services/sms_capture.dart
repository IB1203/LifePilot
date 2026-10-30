import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/local_store.dart';
import '../core/sms_import.dart';

const _channel = MethodChannel('lifepilot/sms');

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool? _appliedCapture;
bool? _appliedHide;

/// Turns the Android SMS receiver on or off to match the settings. It only
/// runs while capture is on and SMS permission is granted. Amounts are
/// kept out of the notification while the app lock is on.
Future<void> syncSmsCapture(LifePilotStore store) async {
  if (!_isAndroid) return;
  final settings = store.settings;
  var enabled = settings.smsCapture;
  if (enabled) {
    try {
      enabled = await Permission.sms.isGranted;
    } on Object {
      enabled = false;
    }
  }
  final hide = settings.lockEnabled;
  if (_appliedCapture == enabled && _appliedHide == hide) return;
  try {
    await _channel.invokeMethod<void>(
        'setCapture', {'enabled': enabled, 'hideAmounts': hide});
    _appliedCapture = enabled;
    _appliedHide = hide;
  } on Object {
    // Retried on the next sync.
  }
}

/// Imports messages the receiver captured while LifePilot was closed.
/// Queue files are deleted only after the import has been saved. Returns
/// the import, or null if there was nothing to read.
Future<SmsImport?> drainCapturedSms(LifePilotStore store) async {
  if (!_isAndroid) return null;
  final cipher = store.dataCipher;
  if (cipher == null || store.storageError != null) return null;
  final List<Map<Object?, Object?>> files;
  try {
    files = await _channel.invokeListMethod<Map<Object?, Object?>>('pending') ??
        const [];
  } on Object {
    return null;
  }
  if (files.isEmpty) return null;
  final messages = <SmsMessage>[];
  final done = <String>[];
  for (final file in files) {
    final name = file['name']! as String;
    try {
      final clear = await cipher.openBytes(file['bytes']! as Uint8List);
      final json = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      messages.add((
        address: json['address'] as String? ?? '',
        body: json['body'] as String? ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      ));
      done.add(name);
    } on Object {
      // Unreadable (e.g. sealed with a key from before a reinstall): drop it.
      done.add(name);
    }
  }
  final import = buildSmsImport(store, messages);
  await store.applySmsImport(import);
  if (store.storageError != null) return import;
  try {
    await _channel.invokeMethod<void>('remove', {'names': done});
  } on Object {
    // Left in the queue; fingerprints stop them being imported twice.
  }
  return import;
}

/// Where a notification tap asked to go, if the app was opened from one.
Future<String?> takeLaunchTarget() async {
  if (!_isAndroid) return null;
  try {
    return await _channel.invokeMethod<String>('launchTarget');
  } on Object {
    return null;
  }
}
