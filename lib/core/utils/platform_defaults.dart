import 'package:flutter/foundation.dart';

import 'package:clan_ai/core/constants/app_constants.dart';

/// Default server base URL for the current platform.
///
/// Android emulators reach the host machine through the alias `10.0.2.2`;
/// `127.0.0.1` there refers to the device itself. Every other supported
/// platform — including web, which reports the browser's host OS via
/// [defaultTargetPlatform] — can use loopback directly.
String defaultBaseUrlForPlatform() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8080';
  }
  return defaultBaseUrl;
}