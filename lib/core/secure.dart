import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Thrown when a password or PIN does not open the data.
class WrongPasswordException implements Exception {
  const WrongPasswordException();

  @override
  String toString() => 'The password is incorrect or the file is damaged.';
}

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

Future<SecretKey> _deriveKey(String secret, List<int> salt, int iterations) =>
    Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: secret, nonce: salt);

const _backupFormat = 'lifepilot-encrypted-backup';

/// Encrypts [plaintext] with a key derived from [password] (PBKDF2-HMAC-
/// SHA256, then AES-256-GCM). The result is JSON text that records the
/// parameters needed to decrypt it.
Future<String> encryptBackup(
  String plaintext,
  String password, {
  int iterations = 120000,
}) async {
  final salt = _randomBytes(16);
  final key = await _deriveKey(password, salt, iterations);
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(plaintext),
    secretKey: key,
  );
  return jsonEncode({
    'format': _backupFormat,
    'version': 1,
    'kdf': 'pbkdf2-hmac-sha256',
    'iterations': iterations,
    'cipher': 'aes-256-gcm',
    'salt': base64Encode(salt),
    'nonce': base64Encode(box.nonce),
    'mac': base64Encode(box.mac.bytes),
    'data': base64Encode(box.cipherText),
  });
}

bool isEncryptedBackup(String source) {
  try {
    final root = jsonDecode(source);
    return root is Map && root['format'] == _backupFormat;
  } on FormatException {
    return false;
  }
}

Future<String> decryptBackup(String source, String password) async {
  final Object? root;
  try {
    root = jsonDecode(source);
  } on FormatException {
    throw const FormatException('This is not a LifePilot encrypted backup.');
  }
  if (root is! Map ||
      root['format'] != _backupFormat ||
      root['version'] != 1 ||
      root['cipher'] != 'aes-256-gcm') {
    throw const FormatException('This is not a LifePilot encrypted backup.');
  }
  final iterations = root['iterations'];
  if (iterations is! int || iterations < 1000 || iterations > 10000000) {
    throw const FormatException('The backup settings are not valid.');
  }
  final key = await _deriveKey(
      password, base64Decode(root['salt'] as String), iterations);
  try {
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(root['data'] as String),
        nonce: base64Decode(root['nonce'] as String),
        mac: Mac(base64Decode(root['mac'] as String)),
      ),
      secretKey: key,
    );
    return utf8.decode(clear);
  } on SecretBoxAuthenticationError {
    throw const WrongPasswordException();
  }
}

/// Hashes an app-lock PIN. Only the hash and salt are stored.
Future<({String hash, String salt})> hashPin(String pin,
    {int iterations = 20000}) async {
  final salt = _randomBytes(16);
  final key = await _deriveKey(pin, salt, iterations);
  return (
    hash: '$iterations:${base64Encode(await key.extractBytes())}',
    salt: base64Encode(salt),
  );
}

Future<bool> verifyPin(String pin, String hash, String salt) async {
  final parts = hash.split(':');
  if (parts.length != 2) return false;
  final iterations = int.tryParse(parts[0]);
  if (iterations == null) return false;
  final key = await _deriveKey(pin, base64Decode(salt), iterations);
  final expected = base64Decode(parts[1]);
  final actual = await key.extractBytes();
  if (expected.length != actual.length) return false;
  var difference = 0;
  for (var i = 0; i < actual.length; i++) {
    difference |= expected[i] ^ actual[i];
  }
  return difference == 0;
}

/// Encrypts data kept on this device (the records file and receipt photos)
/// with AES-256-GCM. The key comes from the platform key store and never
/// leaves the device; see `services/device_key.dart`.
class DataCipher {
  DataCipher(List<int> key)
      : assert(key.length == 32),
        _key = SecretKey(List<int>.unmodifiable(key));

  final SecretKey _key;
  final _algorithm = AesGcm.with256bits();

  static const _textFormat = 'lifepilot-sealed';

  /// Marks a sealed binary file: "LPS1", then nonce, cipher text and MAC.
  static const _magic = [0x4C, 0x50, 0x53, 0x31];
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// Whether [text] is a sealed records file rather than plain JSON.
  static bool isSealedText(String text) {
    // Cheap check first, to avoid parsing large plain files twice.
    if (!text.contains(_textFormat)) return false;
    try {
      final root = jsonDecode(text);
      return root is Map && root['format'] == _textFormat;
    } on FormatException {
      return false;
    }
  }

  static bool isSealedBytes(List<int> bytes) {
    if (bytes.length < _magic.length + _nonceLength + _macLength) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  Future<String> sealText(String plaintext) async {
    final box = await _algorithm.encrypt(utf8.encode(plaintext),
        secretKey: _key, nonce: _randomBytes(_nonceLength));
    return jsonEncode({
      'format': _textFormat,
      'version': 1,
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    });
  }

  /// Throws [WrongPasswordException] if the text was sealed with another key
  /// or has been changed.
  Future<String> openText(String sealed) async {
    final root = jsonDecode(sealed);
    if (root is! Map ||
        root['format'] != _textFormat ||
        root['version'] != 1 ||
        root['cipher'] != 'aes-256-gcm') {
      throw const FormatException('This is not a sealed LifePilot file.');
    }
    return utf8.decode(await _open(SecretBox(
      base64Decode(root['data'] as String),
      nonce: base64Decode(root['nonce'] as String),
      mac: Mac(base64Decode(root['mac'] as String)),
    )));
  }

  Future<List<int>> sealBytes(List<int> clear) async {
    final box = await _algorithm.encrypt(clear,
        secretKey: _key, nonce: _randomBytes(_nonceLength));
    return [..._magic, ...box.nonce, ...box.cipherText, ...box.mac.bytes];
  }

  Future<List<int>> openBytes(List<int> sealed) {
    if (!isSealedBytes(sealed)) {
      throw const FormatException('This is not a sealed LifePilot file.');
    }
    final start = _magic.length;
    final end = sealed.length - _macLength;
    return _open(SecretBox(
      sealed.sublist(start + _nonceLength, end),
      nonce: sealed.sublist(start, start + _nonceLength),
      mac: Mac(sealed.sublist(end)),
    ));
  }

  Future<List<int>> _open(SecretBox box) async {
    try {
      return await _algorithm.decrypt(box, secretKey: _key);
    } on SecretBoxAuthenticationError {
      throw const WrongPasswordException();
    }
  }
}

/// How long the PIN pad stays blocked after [failures] wrong PINs in a row:
/// 30 seconds after 5, 1 minute after 10, 5 minutes after 15, then 30
/// minutes after every further 5. Null when no wait is needed.
Duration? pinLockoutFor(int failures) {
  if (failures < 5 || failures % 5 != 0) return null;
  return switch (failures) {
    5 => const Duration(seconds: 30),
    10 => const Duration(minutes: 1),
    15 => const Duration(minutes: 5),
    _ => const Duration(minutes: 30),
  };
}
