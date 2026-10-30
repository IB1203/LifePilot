import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/secure.dart';

const _channel = MethodChannel('lifepilot/security');

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Loads the device key that encrypts LifePilot's private files. Returns
/// null where there is no platform key store (tests, desktop); throws if
/// Android cannot provide it, so the caller does not mistake that for "no
/// encryption needed".
Future<DataCipher?> loadDeviceCipher() async {
  if (!_isAndroid) return null;
  final key = await _channel.invokeMethod<Uint8List>('dataKey');
  if (key == null || key.length != 32) {
    throw StateError('The device key is not available.');
  }
  return DataCipher(key);
}

bool? _secureApplied;

/// Hides the app from screenshots, screen recording and the recent-apps
/// preview (Android FLAG_SECURE).
Future<void> setSecureScreen(bool secure) async {
  if (!_isAndroid || _secureApplied == secure) return;
  try {
    await _channel.invokeMethod<void>('setSecure', secure);
    _secureApplied = secure;
  } on Object {
    // Not fatal; the setting is retried on the next change.
  }
}

Timer? _clipboardTimer;
String? _pendingClear;

/// Copies [text] marked as sensitive (hidden from Android 13+'s clipboard
/// preview) and clears it after [clearAfter] if it is still there.
Future<void> copySensitive(String text,
    {Duration clearAfter = const Duration(minutes: 1)}) async {
  var copied = false;
  if (_isAndroid) {
    try {
      await _channel.invokeMethod<void>('copySensitive', text);
      copied = true;
    } on Object {
      copied = false;
    }
  }
  if (!copied) await Clipboard.setData(ClipboardData(text: text));
  _pendingClear = text;
  _clipboardTimer?.cancel();
  _clipboardTimer = Timer(clearAfter, flushClipboardClear);
}

/// Clears text copied with [copySensitive] once its time is up. Android
/// does not let apps in the background read the clipboard, so this is
/// retried when the app returns to the foreground.
Future<void> flushClipboardClear() async {
  final text = _pendingClear;
  if (text == null || (_clipboardTimer?.isActive ?? false)) return;
  if (await clearClipboardIf(text) != null) _pendingClear = null;
}

/// Empties the clipboard if it still holds [text], for example after
/// pasted bank messages or a backup have been imported. Returns whether
/// it was cleared, or null if the clipboard could not be read.
Future<bool?> clearClipboardIf(String text) async {
  try {
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current == null) return null;
    if (current.text != text) return false;
    await Clipboard.setData(const ClipboardData(text: ''));
    return true;
  } on Object {
    return null;
  }
}
