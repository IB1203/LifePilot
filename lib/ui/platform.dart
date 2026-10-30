import 'package:flutter/foundation.dart';

/// Running as a desktop app (Windows), where phone-only features such as
/// UPI apps, SMS and the camera are not available.
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);
