import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:clan_ai/core/utils/file_saver.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileSaver Export Tests', () {
    group('Desktop fallback', () {
      test('saveFile writes to documents directory on desktop', () async {
        final testContent = 'Hello, this is test content for export.';
        final filename = 'test_export.txt';

        // Use a temp directory for testing
        final dir = await Directory.systemTemp.createTemp('file_saver_test');
        final testFile = File('${dir.path}/$filename');
        await testFile.writeAsString(testContent);

        expect(await testFile.exists(), isTrue);
        expect(await testFile.readAsString(), equals(testContent));

        await testFile.delete();
        await dir.delete();
      });

      test('saveFile handles JSON content type', () async {
        final testContent = '{"key": "value", "nested": {"a": 1}}';
        final filename = 'test_export.json';

        final dir = await Directory.systemTemp.createTemp('file_saver_test');
        final testFile = File('${dir.path}/$filename');
        await testFile.writeAsString(testContent);

        expect(await testFile.exists(), isTrue);
        expect(await testFile.readAsString(), equals(testContent));

        await testFile.delete();
        await dir.delete();
      });

      test('saveFile handles special characters in filename', () async {
        final testContent = 'Content';
        final filename = 'test_special_chars.txt';

        final dir = await Directory.systemTemp.createTemp('file_saver_test');
        final testFile = File('${dir.path}/$filename');
        await testFile.writeAsString(testContent);

        expect(await testFile.exists(), isTrue);

        await testFile.delete();
        await dir.delete();
      });
    });

    group('Conversation export helpers', () {
      test('toTxt produces valid text output', () {
        final thread = ChatThread(
          id: 'test-thread-id',
          title: 'Test Conversation',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        );
        final messages = <ChatMessage>[
          ChatMessage(
            id: 'msg1',
            threadId: 'test-thread-id',
            role: MessageRole.user,
            content: 'Hello AI',
            createdAt: DateTime(2024, 1, 1),
          ),
          ChatMessage(
            id: 'msg2',
            threadId: 'test-thread-id',
            role: MessageRole.assistant,
            content: 'Hello! How can I help?',
            createdAt: DateTime(2024, 1, 1),
          ),
        ];

        final txt = ConversationExport.toTxt(thread, messages);
        expect(txt, isNotEmpty);
        expect(txt, contains('Hello AI'));
        expect(txt, contains('Hello! How can I help?'));
      });

      test('toTxt includes thread title', () {
        final thread = ChatThread(
          id: 'test-thread-id',
          title: 'My Test Thread',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        );
        final messages = <ChatMessage>[
          ChatMessage(
            id: 'msg1',
            threadId: 'test-thread-id',
            role: MessageRole.user,
            content: 'Test',
            createdAt: DateTime(2024, 1, 1),
          ),
        ];

        final txt = ConversationExport.toTxt(thread, messages);
        expect(txt, contains('My Test Thread'));
      });

      test('toTxt handles empty messages', () {
        final thread = ChatThread(
          id: 'test-thread-id',
          title: 'Test Thread',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        );
        final messages = <ChatMessage>[];

        final txt = ConversationExport.toTxt(thread, messages);
        expect(txt, isNotEmpty);
      });

      test('toJson produces valid JSON output', () async {
        final thread = ChatThread(
          id: 'test-thread-id',
          title: 'Test Thread',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        );
        final messages = <ChatMessage>[
          ChatMessage(
            id: 'msg1',
            threadId: 'test-thread-id',
            role: MessageRole.user,
            content: 'Hello',
            createdAt: DateTime(2024, 1, 1),
          ),
        ];

        final json = ConversationExport.toJson(thread, messages);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded.containsKey('thread'), isTrue);
        expect(decoded['thread']['id'], equals('test-thread-id'));
      });

      test('toJson includes thread metadata', () async {
        final thread = ChatThread(
          id: 'test-thread-id',
          title: 'My Thread',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        );
        final messages = <ChatMessage>[];

        final json = ConversationExport.toJson(thread, messages);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['thread']['title'], equals('My Thread'));
      });
    });
  });
}
