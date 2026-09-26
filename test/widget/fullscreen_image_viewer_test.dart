import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/ui/shared/widgets/fullscreen_image_viewer.dart';

/// Pumps a trivial host route with a button that opens the viewer, then reports
/// whether the dialog is currently on screen.
Future<void> pumpViewerHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => FullscreenImageViewer.show(
              context,
              Container(width: 40, height: 40, color: Colors.red),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('FullscreenImageViewer', () {
    testWidgets('shows a close affordance over the image', (tester) async {
      await pumpViewerHost(tester);

      expect(find.byIcon(Icons.close), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenImageViewer), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    // The reported failure: on a phone the dialog's barrier shrinks to a few
    // points once a portrait image is scaled to fit, so "tap outside to close"
    // is not reachable and the view looks like a dead end.
    testWidgets('the close button returns the user to the underlying route',
        (tester) async {
      await pumpViewerHost(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(FullscreenImageViewer), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: 'chat route still mounted');
    });

    testWidgets('close button is exposed to assistive tech', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpViewerHost(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Close image'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('tap target meets the 44pt minimum', (tester) async {
      await pumpViewerHost(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The glyph paints at 22 so the mark stays unobtrusive, while the box it
      // is hit-tested in is a full 44pt — Apple's minimum comfortable target.
      final icon = tester.widget<Icon>(find.byIcon(Icons.close));
      expect(icon.size, 22);
      final tappable = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(InkResponse),
        ),
      );
      expect(tappable.width, greaterThanOrEqualTo(44));
      expect(tappable.height, greaterThanOrEqualTo(44));
    });

    // A drag that begins on the button must not be swallowed by the viewer's
    // pan recognizer, which is why the button sits outside the InteractiveViewer.
    testWidgets('the image stays zoomable behind the button', (tester) async {
      await pumpViewerHost(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      final closeBox = tester.getRect(find.byIcon(Icons.close));
      final viewerBox = tester.getRect(find.byType(InteractiveViewer));
      // The button overlays the viewer rather than displacing the image.
      expect(viewerBox.contains(closeBox.topLeft), isTrue);
    });
  });
}
