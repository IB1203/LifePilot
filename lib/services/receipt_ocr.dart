import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Reads the text in a receipt photo with Google ML Kit, on the phone. The
/// image never leaves the device. Returns null where ML Kit is unavailable
/// (desktop) or recognition fails.
Future<String?> readReceiptText(String imagePath) async {
  if (!(Platform.isAndroid || Platform.isIOS)) return null;
  final recognizer = TextRecognizer();
  try {
    final result =
        await recognizer.processImage(InputImage.fromFilePath(imagePath));
    return result.text.trim().isEmpty ? null : result.text;
  } on Object {
    return null;
  } finally {
    await recognizer.close();
  }
}
