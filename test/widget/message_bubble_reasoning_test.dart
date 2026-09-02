import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';

void main() {
  group('MessageBubble Reasoning Block Tests', () {
    testWidgets('Renders Thinking block for assistant message and toggles on tap', (tester) async {
      final message = ChatMessage(
        threadId: 't1',
        role: MessageRole.assistant,
        content: 'Final Answer',
        reasoningContent: 'Step 1: Analyzed data.\nStep 2: Computed result.',
        status: MessageStatus.completed,
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

      // Verify thinking header is visible
      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('Final Answer'), findsOneWidget);

      // Initially collapsed, detailed reasoning text is not rendered
      expect(find.textContaining('Step 1: Analyzed data.'), findsNothing);

      // Tap to expand
      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();

      // Now reasoning content is visible
      expect(find.textContaining('Step 1: Analyzed data.'), findsOneWidget);

      // Tap again to collapse
      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Step 1: Analyzed data.'), findsNothing);
    });

    testWidgets('Renders Thinking... while streaming and allows live expansion', (tester) async {
      final streamingMessage = ChatMessage(
        threadId: 't1',
        role: MessageRole.assistant,
        content: '',
        reasoningContent: 'Pondering the solution...',
        status: MessageStatus.streaming,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: streamingMessage,
              messageIndex: 0,
            ),
          ),
        ),
      );

      // Verify "Thinking..." is shown
      expect(find.text('Thinking...'), findsOneWidget);

      // Tap to expand while streaming
      await tester.tap(find.text('Thinking...'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pondering the solution...'), findsOneWidget);
    });
  });
}
