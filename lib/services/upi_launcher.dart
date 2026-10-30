import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/upi.dart';

const _channel = MethodChannel('lifepilot/upi');

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class UpiApp {
  const UpiApp({required this.packageName, required this.name, this.icon});

  final String packageName;
  final String name;
  final Uint8List? icon;
}

/// Installed apps that can take a UPI payment link. Empty where the list
/// cannot be read (then the system chooser is used).
Future<List<UpiApp>> installedUpiApps() async {
  if (!_isAndroid) return const [];
  try {
    final apps = await _channel.invokeListMethod<Map<Object?, Object?>>('apps');
    return [
      for (final app in apps ?? const <Map<Object?, Object?>>[])
        UpiApp(
          packageName: app['package']! as String,
          name: app['name']! as String,
          icon: app['icon'] as Uint8List?,
        ),
    ];
  } on Object {
    return const [];
  }
}

/// Whether this phone hides other apps from LifePilot. Xiaomi, POCO and
/// Redmi phones (MIUI, HyperOS) need their "Get installed apps" permission
/// before LifePilot can list UPI apps: 'denied', 'granted' or 'unsupported'.
Future<String> upiAppListAccess() async {
  if (!_isAndroid) return 'unsupported';
  try {
    return await _channel.invokeMethod<String>('appListAccess') ??
        'unsupported';
  } on Object {
    return 'unsupported';
  }
}

/// Asks for Xiaomi's "Get installed apps" permission. Returns whether it
/// is granted.
Future<bool> requestUpiAppListAccess() async {
  if (!_isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('requestAppListAccess') ?? false;
  } on Object {
    return false;
  }
}

/// Thrown when no installed app can open the payment.
class NoUpiAppException implements Exception {
  const NoUpiAppException();
}

/// Opens [link] in the chosen UPI app (or lets Android choose) and returns
/// what the app reported when it closed. The report is the app's own claim
/// and is never treated as bank confirmation.
Future<UpiResponse> payWithUpiApp(String link, {String? packageName}) async {
  if (!_isAndroid) {
    final opened =
        await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    if (!opened) throw const NoUpiAppException();
    return const UpiResponse(status: UpiReported.unknown);
  }
  try {
    final result = await _channel.invokeMapMethod<String, Object?>('pay', {
      'uri': link,
      'package': packageName,
    });
    final ok = result?['ok'] == true;
    var response = result?['response'] as String?;
    // A few apps return separate extras instead of the response string.
    if ((response == null || !response.contains('=')) &&
        result?['status'] != null) {
      response = 'Status=${result!['status']}&txnId=${result['txnId'] ?? ''}';
    }
    return UpiResponse.parse(response, resultOk: ok);
  } on PlatformException catch (error) {
    if (error.code == 'no_app') throw const NoUpiAppException();
    rethrow;
  }
}
