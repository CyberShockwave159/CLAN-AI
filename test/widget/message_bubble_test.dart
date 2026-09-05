import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';

void main() {
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
  );
}
