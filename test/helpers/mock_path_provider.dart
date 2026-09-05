import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registers a mock handler for the path_provider platform channel.
/// Must be called before any code that accesses [getApplicationDocumentsDirectory].
///
/// Returns the path_provider channel's method call handler future so callers
/// can clear it later if needed (e.g. in tearDown).
Future<int?> Function(MethodCall)? setupMockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '/tmp';
      }
      return null;
    },
  );
  return null;
}
