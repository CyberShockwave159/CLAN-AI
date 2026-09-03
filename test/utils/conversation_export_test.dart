import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/test_model_factories.dart';

void main() {
  group('ConversationExport toTxt', () {
    test('produces labeled output with timestamps', () {
      final thread = buildThread(title: 'Test Chat');
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
          createdAt: DateTime(2024, 1, 15, 14, 30),
        ),
        buildMessage(
          role: MessageRole.assistant,
          content: 'Hi there!',
          createdAt: DateTime(2024, 1, 15, 14, 31),
        ),
      ];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, contains('=== Test Chat ==='));
      expect(output, contains('--- Conversation ---'));
      expect(output, contains('[User]'));
      expect(output, contains('Hello'));
      expect(output, contains('[Assistant]'));
      expect(output, contains('Hi there!'));
    });

    test('includes character name for roleplay threads', () {
      final thread = buildThread(
        title: 'Aria Chat',
        characterId: 'char-1',
      );
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
        ),
      ];

      final output = ConversationExport.toTxt(thread, messages, characterName: 'Aria');

      expect(output, contains('Character: Aria'));
    });

    test('includes model metadata', () {
      final thread = buildThread(
        title: 'Test Chat',
        modelId: 'llama-3.2',
      );
      final messages = <ChatMessage>[];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, contains('Model: llama-3.2'));
    });

    test('includes system prompt in output', () {
      final thread = buildThread(
        title: 'Test Chat',
        systemPrompt: 'You are helpful.',
      );
      final messages = <ChatMessage>[];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, contains('--- System Prompt ---'));
      expect(output, contains('You are helpful.'));
    });

    test('does not include system prompt when empty', () {
      final thread = buildThread(
        title: 'Test Chat',
        systemPrompt: '',
      );
      final messages = <ChatMessage>[];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, isNot(contains('--- System Prompt ---')));
    });

    test('system prompt not included when null', () {
      final thread = buildThread(
        title: 'Test Chat',
        systemPrompt: null,
      );
      final messages = <ChatMessage>[];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, isNot(contains('--- System Prompt ---')));
    });

    test('formats role labels correctly for all roles', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(role: MessageRole.user, content: 'U'),
        buildMessage(role: MessageRole.assistant, content: 'A'),
      ];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, contains('[User]'));
      expect(output, contains('[Assistant]'));
      expect(output, isNot(contains('[System]')));
    });

    test('timestamp formatting is correct', () {
      final thread = buildThread(title: 'Test', createdAt: DateTime(2024, 3, 5, 14, 30));
      final messages = <ChatMessage>[];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, contains('03/05/2024'));
      expect(output, contains('2:30 PM'));
    });

    test('handles midnight hour as 12 AM', () {
      final thread = buildThread(title: 'Test', createdAt: DateTime(2024, 3, 5, 0, 15));
      final messages = <ChatMessage>[];

      final output = ConversationExport.toTxt(thread, messages);

      expect(output, contains('12:15 AM'));
    });

    test('handles empty message list', () {
      final thread = buildThread(title: 'Empty Chat');
      final output = ConversationExport.toTxt(thread, []);

      expect(output, contains('=== Empty Chat ==='));
      expect(output, contains('--- Conversation ---'));
    });
  });

  group('ConversationExport toJson', () {
    test('produces valid JSON with thread and messages', () {
      final thread = buildThread(title: 'Test Chat');
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
        ),
        buildMessage(
          role: MessageRole.assistant,
          content: 'Hi!',
        ),
      ];

      final output = ConversationExport.toJson(thread, messages);

      // Verify it parses as valid JSON
      expect(() => jsonDecode(output), returnsNormally);
    });

    test('JSON contains thread metadata', () {
      final thread = buildThread(title: 'Test Chat');
      final messages = <ChatMessage>[];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;

      expect(json['thread'], isNotNull);
      expect(json['thread']['title'], equals('Test Chat'));
      expect(json['messages'], isNotNull);
    });

    test('JSON contains character info for roleplay threads', () {
      final thread = buildThread(title: 'Aria Chat', characterId: 'char-1');
      final messages = <ChatMessage>[];

      final output = ConversationExport.toJson(thread, messages, characterName: 'Aria');
      final json = jsonDecode(output) as Map<String, dynamic>;

      expect(json['thread']['character_id'], equals('char-1'));
      expect(json['thread']['character_name'], equals('Aria'));
    });

    test('JSON message contains role and content', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(role: MessageRole.user, content: 'Hello'),
      ];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;
      final msg = json['messages'][0] as Map<String, dynamic>;

      expect(msg['role'], equals('user'));
      expect(msg['content'], equals('Hello'));
    });

    test('JSON message includes variant info', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
          variantIndex: 1,
          totalVariants: 2,
          siblingIds: ['sib-1'],
        ),
      ];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;
      final msg = json['messages'][0] as Map<String, dynamic>;

      expect(msg['variant_index'], equals(1));
      expect(msg['total_variants'], equals(2));
      expect(msg['sibling_ids'], contains('sib-1'));
    });

    test('JSON message includes metrics when present', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(
          role: MessageRole.assistant,
          content: 'Hello',
          tokensPerSecond: 42.5,
          totalTokens: 100,
          timeToFirstTokenMs: 500,
          generationTimeSec: 2.5,
        ),
      ];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;
      final msg = json['messages'][0] as Map<String, dynamic>;

      expect(msg['tokens_per_second'], equals(42.5));
      expect(msg['total_tokens'], equals(100));
      expect(msg['time_to_first_token_ms'], equals(500));
      expect(msg['generation_time_sec'], equals(2.5));
    });

    test('JSON message omits null metrics', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
        ),
      ];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;
      final msg = json['messages'][0] as Map<String, dynamic>;

      expect(msg.containsKey('tokens_per_second'), isFalse);
      expect(msg.containsKey('total_tokens'), isFalse);
    });

    test('JSON includes thread custom_params when present', () {
      final thread = buildThread(
        title: 'Test',
        customParams: const GenerationParams(temperature: 0.7),
      );
      final messages = <ChatMessage>[];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;

      expect(json['thread']['custom_params'], isNotNull);
      expect(json['thread']['custom_params']['temperature'], equals(0.7));
    });

    test('JSON includes branch_from_thread_id when present', () {
      final thread = buildThread(
        title: 'Test',
        branchFromThreadId: 'parent-thread',
      );
      final messages = <ChatMessage>[];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;

      expect(json['thread']['branch_from_thread_id'], equals('parent-thread'));
    });

    test('JSON message includes parent_id', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
          parentId: 'parent-1',
        ),
      ];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;
      final msg = json['messages'][0] as Map<String, dynamic>;

      expect(msg['parent_id'], equals('parent-1'));
    });

    test('JSON message includes createdAt timestamp', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
          createdAt: DateTime(2024, 1, 1),
        ),
      ];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;
      final msg = json['messages'][0] as Map<String, dynamic>;

      expect(msg['created_at'], equals('2024-01-01T00:00:00.000'));
    });

    test('JSON message includes status', () {
      final thread = buildThread(title: 'Test');
      final messages = [
        buildMessage(
          role: MessageRole.user,
          content: 'Hello',
          status: MessageStatus.completed,
        ),
      ];

      final output = ConversationExport.toJson(thread, messages);
      final json = jsonDecode(output) as Map<String, dynamic>;
      final msg = json['messages'][0] as Map<String, dynamic>;

      expect(msg['status'], equals('completed'));
    });
  });

  group('ConversationExport formatTimestamp', () {
    test('formats date and time correctly', () {
      final ts = ConversationExport.formatTimestamp(DateTime(2024, 3, 5, 14, 30));
      expect(ts, equals('03/05/2024, 2:30 PM'));
    });

    test('pads month and day with zeros', () {
      final ts = ConversationExport.formatTimestamp(DateTime(2024, 1, 5, 10, 0));
      expect(ts, equals('01/05/2024, 10:00 AM'));
    });

    test('midnight is 12 AM', () {
      final ts = ConversationExport.formatTimestamp(DateTime(2024, 1, 15, 0, 30));
      expect(ts, equals('01/15/2024, 12:30 AM'));
    });

    test('noon is 12 PM', () {
      final ts = ConversationExport.formatTimestamp(DateTime(2024, 1, 15, 12, 0));
      expect(ts, equals('01/15/2024, 12:00 PM'));
    });

    test('PM conversion works', () {
      final ts = ConversationExport.formatTimestamp(DateTime(2024, 1, 15, 13, 0));
      expect(ts, equals('01/15/2024, 1:00 PM'));
    });
  });
}
