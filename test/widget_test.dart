import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:clan_ai/ui/shared/connection_badge.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('ConnectionBadge renders status and latency correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionBadge(
            status: ServerHealthStatus.connected,
            latencyMs: 18,
          ),
        ),
      ),
    );

    expect(find.text('18 ms'), findsOneWidget);
  });
}
