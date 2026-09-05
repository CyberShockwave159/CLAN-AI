import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/test_model_factories.dart';

void main() {
  late FakeChatRepository repo;

  setUp(() {
    repo = FakeChatRepository();
  });

  group('ChatRepository getAssistantThreads', () {
    test('returns threads without characterId', () async {
      await repo.createThread(title: 'Assistant Chat');
      final roleplay = await repo.createThread(title: 'Roleplay Chat');
      await repo.updateThread(roleplay.copyWith(characterId: 'char-1'));
      await repo.createThread(title: 'Another Assistant Chat');

      final threads = await repo.getAssistantThreads();
      expect(threads, hasLength(2));
      for (final thread in threads) {
        expect(thread.characterId, isNull);
      }
    });

    test('filters out roleplay threads', () async {
      final roleplay = await repo.createThread(title: 'Roleplay');
      await repo.updateThread(roleplay.copyWith(characterId: 'char-1'));

      final threads = await repo.getAssistantThreads();
      expect(threads, isNot(contains(roleplay)));
    });
  });

  group('ChatRepository getThreadsForCharacter', () {
    test('returns only threads for the specified character', () async {
      final t1 = await repo.createThread(title: 'Thread 1'); await repo.updateThread(t1.copyWith(characterId: 'char-1'));
      final t2 = await repo.createThread(title: 'Thread 2'); await repo.updateThread(t2.copyWith(characterId: 'char-1'));
      await repo.createThread(title: 'Thread 3');

      final threads = await repo.getThreadsForCharacter('char-1');

      expect(threads, hasLength(2));
      for (final thread in threads) {
        expect(thread.characterId, equals('char-1'));
      }
    });

    test('returns empty list for character with no threads', () async {
      final threads = await repo.getThreadsForCharacter('non-existent');
      expect(threads, isEmpty);
    });

    test('sorts by updatedAt descending', () async {
      final thread1 = await repo.createThread(title: 'Old');
      await repo.updateThread(thread1.copyWith(
        characterId: 'char-1',
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ));
      final thread2 = await repo.createThread(title: 'New');
      await repo.updateThread(thread2.copyWith(characterId: 'char-1'));

      final threads = await repo.getThreadsForCharacter('char-1');

      expect(threads[0].id, equals(thread2.id));
      expect(threads[1].id, equals(thread1.id));
    });
  });

  group('ChatRepository createThread', () {
    test('creates thread with default title', () async {
      final thread = await repo.createThread();

      expect(thread.title, equals('New Chat'));
      expect(thread.id, isNotNull);
      expect(thread.id.isNotEmpty, isTrue);
    });

    test('creates thread with custom title', () async {
      final thread = await repo.createThread(title: 'My Chat');

      expect(thread.title, equals('My Chat'));
    });

    test('creates thread with system prompt', () async {
      final thread = await repo.createThread(
        title: 'Thread',
        systemPrompt: 'Be helpful',
      );

      expect(thread.systemPrompt, equals('Be helpful'));
    });

    test('creates thread with modelId', () async {
      final thread = await repo.createThread(
        title: 'Thread',
        modelId: 'llama-3.2',
      );

      expect(thread.modelId, equals('llama-3.2'));
    });

    test('creates thread with custom params', () async {
      final params = const GenerationParams(temperature: 0.7);
      final thread = await repo.createThread(
        title: 'Thread',
        customParams: params,
      );

      expect(thread.customParams, isNotNull);
      expect(thread.customParams!.temperature, equals(0.7));
    });

    test('thread has auto-generated UUID', () async {
      final thread = await repo.createThread();

      expect(thread.id, isNotNull);
      expect(thread.id.length, greaterThan(10));
    });
  });

  group('ChatRepository updateThread', () {
    test('updates thread title', () async {
      final thread = await repo.createThread(title: 'Old Title');
      final updated = thread.copyWith(title: 'New Title');
      await repo.updateThread(updated);

      final threads = await repo.getThreads();
      expect(threads.firstWhere((t) => t.id == thread.id).title, equals('New Title'));
    });

    test('updates thread system prompt', () async {
      final thread = await repo.createThread(title: 'Thread');
      final updated = thread.copyWith(systemPrompt: 'New prompt');
      await repo.updateThread(updated);

      final threads = await repo.getThreads();
      expect(
        threads.firstWhere((t) => t.id == thread.id).systemPrompt,
        equals('New prompt'),
      );
    });
  });

  group('ChatRepository deleteThread', () {
    test('removes thread from list', () async {
      final thread = await repo.createThread(title: 'Delete Me');
      await repo.deleteThread(thread.id);

      final threads = await repo.getThreads();
      expect(threads, isNot(contains(thread)));
    });

    test('removes thread messages', () async {
      final thread = await repo.createThread(title: 'Delete Me');
      await repo.saveMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      ));
      await repo.deleteThread(thread.id);

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages, isEmpty);
    });
  });

  group('ChatRepository saveMessage', () {
    test('persists message to thread', () async {
      final thread = await repo.createThread(title: 'Thread');
      final message = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      );
      await repo.saveMessage(message);

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages, hasLength(1));
      expect(messages.first.content, equals('Hello'));
    });

    test('updates existing message', () async {
      final thread = await repo.createThread(title: 'Thread');
      final message = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Original',
      );
      await repo.saveMessage(message);

      final updated = message.copyWith(content: 'Updated');
      await repo.saveMessage(updated);

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages.first.content, equals('Updated'));
    });
  });

  group('ChatRepository updateMessage', () {
    test('updates message in repository', () async {
      final thread = await repo.createThread(title: 'Thread');
      final message = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Original',
      );
      await repo.saveMessage(message);

      final updated = message.copyWith(content: 'Updated');
      await repo.updateMessage(updated);

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages.first.content, equals('Updated'));
    });

    test('updates message isEdited flag', () async {
      final thread = await repo.createThread(title: 'Thread');
      final message = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      );
      await repo.saveMessage(message);

      final updated = message.copyWith(isEdited: true);
      await repo.updateMessage(updated);

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages.first.isEdited, isTrue);
    });
  });

  group('ChatRepository deleteMessage', () {
    test('removes message from thread', () async {
      final thread = await repo.createThread(title: 'Thread');
      final message = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Delete me',
      );
      await repo.saveMessage(message);

      await repo.deleteMessage(message.id);

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages, isEmpty);
    });

    test('removes only the specified message', () async {
      final thread = await repo.createThread(title: 'Thread');
      final msg1 = buildMessage(
        id: 'msg-1',
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Keep me 1',
      );
      final msg2 = buildMessage(
        id: 'msg-2',
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Delete me',
      );
      final msg3 = buildMessage(
        id: 'msg-3',
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Keep me 2',
      );
      await repo.saveMessage(msg1);
      await repo.saveMessage(msg2);
      await repo.saveMessage(msg3);

      await repo.deleteMessage(msg2.id);

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages, hasLength(2));
      expect(messages.where((m) => m.content == 'Keep me 1').length, equals(1));
      expect(messages.where((m) => m.content == 'Keep me 2').length, equals(1));
    });
  });

  group('ChatRepository getMessagesForThread', () {
    test('returns messages for thread', () async {
      final thread = await repo.createThread(title: 'Thread');
      await repo.saveMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      ));

      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages, hasLength(1));
    });

    test('returns empty list for thread with no messages', () async {
      final thread = await repo.createThread(title: 'Empty');
      final messages = await repo.getMessagesForThread(thread.id);
      expect(messages, isEmpty);
    });

    test('returns messages for correct thread only', () async {
      final thread1 = await repo.createThread(title: 'Thread 1');
      final thread2 = await repo.createThread(title: 'Thread 2');
      await repo.saveMessage(buildMessage(
        threadId: thread1.id,
        role: MessageRole.user,
        content: 'Thread 1 message',
      ));
      await repo.saveMessage(buildMessage(
        threadId: thread2.id,
        role: MessageRole.user,
        content: 'Thread 2 message',
      ));

      final msgs1 = await repo.getMessagesForThread(thread1.id);
      final msgs2 = await repo.getMessagesForThread(thread2.id);

      expect(msgs1.first.content, equals('Thread 1 message'));
      expect(msgs2.first.content, equals('Thread 2 message'));
    });
  });

  group('ChatRepository streamCompletion', () {
    test('returns stream chunks from repository', () async {
      final thread = await repo.createThread(title: 'Thread');
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hello', isDone: false),
        const StreamChunk(text: ' world', isDone: true),
      ]);

      final chunks = await repo
          .streamCompletion(
            serverConfig: buildServerConfig(),
            connection: null,
            history: [],
            systemPrompt: 'Test',
            params: null,
            cancelToken: null,
            modelContextLength: null,
          )
          .toList();

      expect(chunks, hasLength(2));
      expect(chunks[0].text, equals('Hello'));
      expect(chunks[1].text, equals(' world'));
    });

    test('returns empty stream when no fragments', () async {
      final chunks = await repo
          .streamCompletion(
            serverConfig: buildServerConfig(),
            connection: null,
            history: [],
            systemPrompt: 'Test',
            params: null,
            cancelToken: null,
            modelContextLength: null,
          )
          .toList();

      expect(chunks, isEmpty);
    });

    test('streamCompletion uses first message threadId', () async {
      final thread = await repo.createThread(title: 'Thread');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      );
      repo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      final chunks = await repo
          .streamCompletion(
            serverConfig: buildServerConfig(),
            connection: null,
            history: [userMsg],
            systemPrompt: 'Test',
            params: null,
            cancelToken: null,
            modelContextLength: null,
          )
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks[0].text, equals('Hi'));
    });
  });

  group('ChatRepository getThreads', () {
    test('returns all threads', () async {
      await repo.createThread(title: 'Thread 1');
      final t2 = await repo.createThread(title: 'Thread 2'); await repo.updateThread(t2.copyWith(characterId: 'char-1'));
      await repo.createThread(title: 'Thread 3');

      final threads = await repo.getThreads();

      expect(threads, hasLength(3));
    });

    test('returns empty list when no threads', () async {
      final threads = await repo.getThreads();
      expect(threads, isEmpty);
    });
  });
}
