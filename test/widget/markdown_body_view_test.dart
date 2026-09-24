import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/ui/features/chat/widgets/code_block_view.dart';
import 'package:clan_ai/ui/features/chat/widgets/markdown_body_view.dart';
import 'package:clan_ai/ui/features/chat/widgets/markdown_image_view.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }
}

void main() {
  final fakeLauncher = _FakeUrlLauncher();

  setUp(() {
    fakeLauncher.launched.clear();
    UrlLauncherPlatform.instance = fakeLauncher;
  });

  Widget wrap(String data) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DynamicMarkdownView(data: data),
        ),
      ),
    );
  }

  testWidgets('renders a generated image markdown link natively', (tester) async {
    await tester.pumpWidget(wrap('Here is your image:\n\n![generated](http://host/gen_1.png)'));
    await tester.pump();

    expect(find.text('Here is your image:'), findsOneWidget);
    expect(find.byType(MarkdownImageView), findsOneWidget);
  });

  testWidgets('renders a bare generated-image URL natively', (tester) async {
    const url = 'http://127.0.0.1:8000/images/gen_1.png';
    await tester.pumpWidget(wrap('image: $url'));
    await tester.pump();

    // Converted into a native inline image, not a standalone link.
    expect(find.byType(MarkdownImageView), findsOneWidget);
    // The URL only surfaces inside the image widget itself (error fallback
    // chip when the network image cannot load in a hermetic test).
    expect(
      find.descendant(
        of: find.byType(MarkdownImageView),
        matching: find.text(url),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(MarkdownImageView),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps image URLs inside code blocks as code', (tester) async {
    await tester.pumpWidget(wrap('```\nhttp://host/gen_1.png\n```'));
    await tester.pump();

    expect(find.byType(MarkdownImageView), findsNothing);
  });

  testWidgets('long first line stays in the code body; header keeps language and copy button', (tester) async {
    const longFirstLine =
        'def very_long_function_name_without_any_spacing_that_is_visibly_long(arg_a, arg_b):';
    await tester.pumpWidget(wrap('```python\n$longFirstLine\n    return 1\n```'));
    await tester.pump();

    // The header shows the actual language, not a slice of the first line.
    expect(find.descendant(
      of: find.byType(CodeBlockView),
      matching: find.text('python'),
    ), findsOneWidget);

    // The full first line renders inside the code body.
    expect(
      find.descendant(
        of: find.byType(CodeBlockView),
        matching: find.textContaining('very_long_function_name_without_any_spacing_that_is_visibly_long', findRichText: true),
      ),
      findsOneWidget,
    );

    // The copy button still renders (any header overflow would fail the pump).
    expect(find.text('Copy'), findsOneWidget);
    // And it is laid out within the code block's bounds.
    final codeBlock = tester.getRect(find.byType(CodeBlockView));
    expect(codeBlock.contains(tester.getCenter(find.text('Copy'))), isTrue);
  });

  testWidgets('hyperlinks open in the platform browser on tap', (tester) async {
    await tester.pumpWidget(wrap('[OpenAI](https://openai.com)'));
    await tester.pump();

    expect(find.byType(MarkdownImageView), findsNothing);
    await tester.tap(find.textContaining('OpenAI'));
    await tester.pump();

    expect(fakeLauncher.launched, contains('https://openai.com'));
  });

  testWidgets('autolinked bare non-image URLs open on tap', (tester) async {
    await tester.pumpWidget(wrap('visit https://llama.readthedocs.io now'));
    await tester.pump();

    await tester.tap(find.textContaining('https://llama.readthedocs.io'));
    await tester.pump();

    expect(fakeLauncher.launched, contains('https://llama.readthedocs.io'));
  });

  testWidgets('does not launch for non-http schemes', (tester) async {
    await tester.pumpWidget(wrap('see [local](file:///etc/hosts) here'));
    await tester.pump();

    await tester.tap(find.textContaining('local'));
    await tester.pump();

    expect(fakeLauncher.launched, isEmpty);
  });
}