import 'dart:io';

import 'package:clan_ai/core/constants/app_constants.dart';

/// Default server base URL for the current platform.
///
/// Android emulators reach the host machine through the alias `10.0.2.2`;
/// `127.0.0.1` there refers to the device itself. Every other supported
/// platform can use loopback directly.
String defaultBaseUrlForPlatform() {
  if (Platform.isAndroid) return 'http://10.0.2.2:8080';
  return defaultBaseUrl;
}
