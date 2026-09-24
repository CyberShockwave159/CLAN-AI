import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/chat/widgets/artifact_file_card.dart';
import 'package:clan_ai/ui/shared/widgets/attachment_image.dart';
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

  group('MessageBubble', () {
    testWidgets('renders user message correctly', (tester) async {
      final message = buildUserMessage();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('renders assistant message correctly', (tester) async {
      final message = buildAssistantMessage();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.text('Assistant response'), findsOneWidget);
    });

    testWidgets('shows streaming indicator', (tester) async {
      final message = buildAssistantMessage(status: MessageStatus.streaming);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      // Streaming indicator should be visible
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('shows error state', (tester) async {
      final message = buildAssistantMessage(
        status: MessageStatus.error,
        errorMessage: 'Connection failed',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.text('Assistant response'), findsOneWidget);
    });

    testWidgets('displays token speed badge when metrics available', (tester) async {
      final message = buildAssistantMessage(
        tokensPerSecond: 42.5,
        totalTokens: 100,
        timeToFirstTokenMs: 500,
        generationTimeSec: 2.5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.text('Assistant response'), findsOneWidget);
    });

    testWidgets('shows variant navigation when siblings exist', (tester) async {
      final message = buildAssistantMessage(
        variantIndex: 0,
        totalVariants: 2,
        siblingIds: ['sibling-1'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.text('Assistant response'), findsOneWidget);
    });

    testWidgets('renders edited message indicator', (tester) async {
      final message = buildAssistantMessage(isEdited: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.text('Assistant response'), findsOneWidget);
    });

    testWidgets('renders markdown content', (tester) async {
      final message = buildAssistantMessage(
        content: '**Bold text** and *italic text*',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('renders code blocks', (tester) async {
      final message = buildAssistantMessage(
        content: '```\ncode block\n```',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              messageIndex: 0,
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('renders a stored A-PROX file artifact as a save-able object', (tester) async {
      final message = buildAssistantMessage(
        content: 'Here is the result.',
        filePath: '/tmp/attachments/f_assistant-1.txt',
        fileName: 'result.txt',
        fileMime: 'text/plain',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, messageIndex: 0),
          ),
        ),
      );

      expect(find.text('Here is the result.'), findsOneWidget);
      expect(find.byType(ArtifactFileCard), findsOneWidget);
      expect(find.text('result.txt'), findsOneWidget);
      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    });

    testWidgets('renders file URLs from markdown as save-able objects', (tester) async {
      final message = buildAssistantMessage(content: 'Grab [result](http://host/out.txt)');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, messageIndex: 0),
          ),
        ),
      );

      expect(find.byType(ArtifactFileCard), findsOneWidget);
      expect(find.text('out.txt'), findsOneWidget);
    });

    testWidgets('does not render file objects for user messages', (tester) async {
      final message = buildUserMessage(content: 'here is http://host/out.txt for you');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, messageIndex: 0),
          ),
        ),
      );

      expect(find.byType(ArtifactFileCard), findsNothing);
    });

    testWidgets('does not duplicate a file already stored as an A-PROX artifact', (tester) async {
      final message = buildAssistantMessage(
        content: 'Result: [download](http://host/result.txt)',
        filePath: '/tmp/attachments/f_assistant-1.txt',
        fileName: 'result.txt',
        fileMime: 'text/plain',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, messageIndex: 0),
          ),
        ),
      );

      expect(find.byType(ArtifactFileCard), findsOneWidget);
    });

    testWidgets('renders an assistant image attachment natively without external launch', (tester) async {
      final message = buildAssistantMessage(
        content: 'Here is the generated image.',
        imagePath: '/tmp/attachments/a_assistant-1.png',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: message, messageIndex: 0),
          ),
        ),
      );

      // Identical bubble treatment to user attachments: a thumbnail that opens
      // the in-app fullscreen lightbox (no external browser redirect).
      expect(find.byType(AttachmentImage), findsOneWidget);
      expect(fakeLauncher.launched, isEmpty);

      await tester.tap(find.byType(AttachmentImage));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(fakeLauncher.launched, isEmpty);
    });
  });
}

ChatMessage buildUserMessage({
  MessageStatus status = MessageStatus.completed,
  String content = 'Hello world',
}) {
  return ChatMessage(
    id: 'user-1',
    threadId: 'thread-1',
    role: MessageRole.user,
    content: content,
    status: status,
  );
}

ChatMessage buildAssistantMessage({
  MessageStatus status = MessageStatus.completed,
  String content = 'Assistant response',
  double? tokensPerSecond,
  int? totalTokens,
  int? timeToFirstTokenMs,
  double? generationTimeSec,
  String? errorMessage,
  int variantIndex = 0,
  int totalVariants = 1,
  List<String> siblingIds = const [],
  bool isEdited = false,
  String reasoningContent = '',
  String? filePath,
  String? fileName,
  String? fileMime,
  String? imagePath,
}) {
  return ChatMessage(
    id: 'assistant-1',
    threadId: 'thread-1',
    role: MessageRole.assistant,
    content: content,
    status: status,
    tokensPerSecond: tokensPerSecond,
    totalTokens: totalTokens,
    timeToFirstTokenMs: timeToFirstTokenMs,
    generationTimeSec: generationTimeSec,
    errorMessage: errorMessage,
    variantIndex: variantIndex,
    totalVariants: totalVariants,
    siblingIds: siblingIds,
    isEdited: isEdited,
    reasoningContent: reasoningContent,
    filePath: filePath,
    fileName: fileName,
    fileMime: fileMime,
    imagePath: imagePath,
  );
}
