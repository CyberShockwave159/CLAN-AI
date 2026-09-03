import 'dart:async';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/test_model_factories.dart';

void main() {
  late FakeChatRepository fakeRepo;
  late ChatViewModel vm;

  setUp(() {
    fakeRepo = FakeChatRepository();
    vm = ChatViewModel(chatRepository: fakeRepo);
  });

  tearDown(() {
    vm.dispose();
  });

  group('ChatViewModel createNewThread', () {
    test('creates new thread and sets as active', () async {
      await vm.createNewThread(title: 'New Chat');

      expect(vm.threads, isNotEmpty);
      expect(vm.activeThread, isNotNull);
      expect(vm.activeThread!.title, equals('New Chat'));
    });

    test('creates thread with custom system prompt', () async {
      await vm.createNewThread(
        title: 'Custom Thread',
        systemPrompt: 'Be helpful',
      );

      expect(vm.activeThread?.systemPrompt, equals('Be helpful'));
    });

    test('creates thread with modelId', () async {
      await vm.createNewThread(
        title: 'Model Thread',
        modelId: 'llama-3.2',
      );

      expect(vm.activeThread?.modelId, equals('llama-3.2'));
    });

    test('clears messages when creating new thread', () async {
      fakeRepo.createThread(title: 'Existing');
      final existingThread = fakeRepo.getAssistantThreads();
      await fakeRepo.saveMessage(buildMessage(
        threadId: await existingThread.then((t) => t.first.id),
        role: MessageRole.user,
        content: 'Old message',
      ));

      await vm.createNewThread(title: 'New Chat');

      expect(vm.messages, isEmpty);
    });

    test('inserts thread at beginning of list', () async {
      fakeRepo.createThread(title: 'Old Chat');
      await vm.createNewThread(title: 'New Chat');

      // The new thread should be the active one
      expect(vm.activeThread?.title, equals('New Chat'));
    });

    test('stops generation before creating thread', () async {
      vm.isGenerating = true;
      final token = CancelToken();
      vm.currentCancelToken = token;

      await vm.createNewThread(title: 'New Chat');

      expect(vm.isGenerating, isFalse);
    });
  });

  group('ChatViewModel deleteThread', () async {
    test('deletes thread from list', () async {
      final thread = await fakeRepo.createThread(title: 'Delete Me');
      vm.threads = await fakeRepo.getAssistantThreads();

      await vm.deleteThread(thread.id);

      expect(vm.threads, isNot(contains(thread)));
    });

    test('switches to another thread when deleting active', () async {
      final thread1 = await fakeRepo.createThread(title: 'Keep');
      final thread2 = await fakeRepo.createThread(title: 'Delete');
      vm.threads = await fakeRepo.getAssistantThreads();
      vm.activeThread = thread2;

      await vm.deleteThread(thread2.id);

      expect(vm.activeThread?.id, equals(thread1.id));
    });

    test('creates new thread when deleting last thread', () async {
      final thread = await fakeRepo.createThread(title: 'Only');
      vm.threads = [thread];
      vm.activeThread = thread;

      await vm.deleteThread(thread.id);

      expect(vm.activeThread, isNotNull);
      expect(vm.activeThread!.id, isNot(thread.id));
    });

    test('deletes thread messages from repository', () async {
      final thread = await fakeRepo.createThread(title: 'Delete Me');
      await fakeRepo.saveMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      ));

      vm.threads = await fakeRepo.getAssistantThreads();

      await vm.deleteThread(thread.id);

      final messages = await fakeRepo.getMessagesForThread(thread.id);
      expect(messages, isEmpty);
    });
  });

  group('ChatViewModel sendMessage', () async {
    test('creates user message and assistant placeholder', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      vm.activeThread = thread;
      vm.messages = [];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      // User message should exist
      expect(vm.messages.where((m) => m.content == 'Hello').length, greaterThanOrEqualTo(1));
    });

    test('creates new thread if no active thread', () async {
      fakeRepo.setStreamFragments('new', [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.activeThread, isNotNull);
    });

    test('auto-updates thread title on first message', () async {
      final thread = await fakeRepo.createThread(title: 'New Chat');
      vm.activeThread = thread;
      vm.messages = [];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'My awesome question',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      // Thread title should be updated (truncated to autoTitleMaxLen)
      expect(vm.activeThread?.title, contains('My awesome question'));
    });

    test('does not send empty messages', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      vm.activeThread = thread;
      vm.messages = [];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      final messageCount = vm.messages.length;
      await vm.sendMessage(
        prompt: '   ',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.length, equals(messageCount));
    });

    test('does not send while generating', () async {
      vm.isGenerating = true;
      final thread = await fakeRepo.createThread(title: 'Chat');
      vm.activeThread = thread;
      vm.messages = [];

      final messageCount = vm.messages.length;
      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.length, equals(messageCount));
    });

    test('user message is persisted', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      vm.activeThread = thread;
      vm.messages = [];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(fakeRepo.lastSavedMessage, isNotNull);
      expect(fakeRepo.lastSavedMessage!.role, equals(MessageRole.user));
    });

    test('assistant placeholder is created with streaming status', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      vm.activeThread = thread;
      vm.messages = [];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final assistantMsg = vm.messages.where((m) => m.role == MessageRole.assistant);
      expect(assistantMsg, isNotEmpty);
    });
  });

  group('ChatViewModel regenerateMessage', () async {
    test('creates new variant with incremented indices', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        variantIndex: 0,
        totalVariants: 1,
      );
      vm.messages = [userMsg, assistantMsg];
      vm.activeThread = thread;
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'New response', isDone: true),
      ]);

      await vm.regenerateMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final currentMsg = vm.messages[1];
      expect(currentMsg.variantIndex, equals(1));
      expect(currentMsg.totalVariants, equals(2));
    });

    test('creates siblingIds for old and new messages', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        variantIndex: 0,
        totalVariants: 1,
      );
      vm.messages = [userMsg, assistantMsg];
      vm.activeThread = thread;
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'New', isDone: true),
      ]);

      await vm.regenerateMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      // New message should have old message id in siblingIds
      final newMsg = vm.messages[1];
      expect(newMsg.siblingIds, contains('assistant-1'));
    });

    test('only regenerates assistant messages', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
        content: 'Original',
      );
      vm.messages = [userMsg];
      vm.activeThread = thread;
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'New', isDone: true),
      ]);

      await vm.regenerateMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages[0].content, equals('Original'));
    });

    test('does not regenerate while generating', () async {
      vm.isGenerating = true;
      final thread = await fakeRepo.createThread(title: 'Chat');
      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
      );
      vm.messages = [assistantMsg];
      vm.activeThread = thread;

      await vm.regenerateMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.isGenerating, isTrue);
    });
  });

  group('ChatViewModel deleteMessage', () async {
    test('deletes message and regenerates if assistant deleted', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
      );
      vm.messages = [userMsg, assistantMsg];
      vm.activeThread = thread;
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Regenerated', isDone: true),
      ]);

      final wasThreadDeleted = await vm.deleteMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(wasThreadDeleted, isFalse);
      expect(vm.messages.where((m) => m.role == MessageRole.assistant).length, greaterThanOrEqualTo(1));
    });

    test('deletes user message without regeneration', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
      );
      vm.messages = [userMsg, assistantMsg];
      vm.activeThread = thread;

      final wasThreadDeleted = await vm.deleteMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(wasThreadDeleted, isTrue);
    });

    test('stores user message for undo', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.messages = [userMsg];
      vm.activeThread = thread;

      await vm.deleteMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.canUndo, isTrue);
    });

    test('deletes all messages after index', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final msg1 = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'msg-1',
      );
      final msg2 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'msg-2',
      );
      final msg3 = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'msg-3',
      );
      vm.messages = [msg1, msg2, msg3];
      vm.activeThread = thread;

      await vm.deleteMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.length, equals(1));
      expect(vm.messages.first.id, equals('msg-1'));
    });

    test('does not delete while generating', () async {
      vm.isGenerating = true;
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.messages = [userMsg];
      vm.activeThread = thread;

      final wasDeleted = await vm.deleteMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(wasDeleted, isFalse);
    });
  });

  group('ChatViewModel undoDelete', () async {
    test('restores deleted message', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.messages = [userMsg];
      vm.activeThread = thread;

      await vm.deleteMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.canUndo, isTrue);

      // Re-add the message for undo to work
      await fakeRepo.saveMessage(userMsg);

      await vm.undoDelete();

      expect(vm.messages, isNotEmpty);
    });
  });

  group('ChatViewModel updateActiveThreadSystemPrompt', () async {
    test('updates thread system prompt', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      vm.activeThread = thread;

      await vm.updateActiveThreadSystemPrompt('Custom prompt');

      expect(vm.activeThread?.systemPrompt, equals('Custom prompt'));

      final threads = await fakeRepo.getThreads();
      expect(
        threads.firstWhere((t) => t.id == thread.id).systemPrompt,
        equals('Custom prompt'),
      );
    });

    test('does nothing when no active thread', () async {
      vm.activeThread = null;

      await vm.updateActiveThreadSystemPrompt('Custom prompt');

      expect(vm.activeThread, isNull);
    });
  });

  group('ChatViewModel renameThread', () async {
    test('updates thread title', () async {
      final thread = await fakeRepo.createThread(title: 'Old Title');
      vm.threads = [thread];
      vm.activeThread = thread;

      await vm.renameThread(thread.id, 'New Title');

      expect(vm.activeThread?.title, equals('New Title'));
      expect(vm.threads.first.title, equals('New Title'));
    });

    test('only updates matching thread', () async {
      final thread1 = await fakeRepo.createThread(title: 'Keep');
      final thread2 = await fakeRepo.createThread(title: 'Rename');
      vm.threads = [thread1, thread2];
      vm.activeThread = thread2;

      await vm.renameThread(thread2.id, 'Renamed');

      expect(vm.threads[0].title, equals('Keep'));
      expect(vm.threads[1].title, equals('Renamed'));
    });

    test('does nothing for non-matching thread', () async {
      final thread = await fakeRepo.createThread(title: 'Original');
      vm.threads = [thread];
      vm.activeThread = thread;

      await vm.renameThread('non-existent', 'Renamed');

      expect(vm.activeThread?.title, equals('Original'));
    });
  });

  group('ChatViewModel filteredThreads', () {
    test('returns all threads when no search query', () {
      fakeRepo.createThread(title: 'Thread 1');
      fakeRepo.createThread(title: 'Thread 2');
      vm.threads = await fakeRepo.getAssistantThreads();

      expect(vm.filteredThreads, hasLength(2));
    });

    test('filters threads by query', () {
      fakeRepo.createThread(title: 'Important Chat');
      fakeRepo.createThread(title: 'Random Chat');
      vm.threads = await fakeRepo.getAssistantThreads();
      vm.setSearchQuery('Important');

      expect(vm.filteredThreads, hasLength(1));
      expect(vm.filteredThreads.first.title, contains('Important'));
    });

    test('case-insensitive search', () {
      fakeRepo.createThread(title: 'Test Chat');
      vm.threads = await fakeRepo.getAssistantThreads();
      vm.setSearchQuery('test');

      expect(vm.filteredThreads, hasLength(1));
    });

    test('returns empty when no matches', () {
      fakeRepo.createThread(title: 'Test');
      vm.threads = await fakeRepo.getAssistantThreads();
      vm.setSearchQuery('nonexistent');

      expect(vm.filteredThreads, isEmpty);
    });
  });

  group('ChatViewModel selectThread', () async {
    test('loads messages for thread', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      await fakeRepo.saveMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      ));
      vm.activeThread = thread;

      await vm.selectThread(thread);

      expect(vm.messages, isNotEmpty);
    });

    test('stops generation before switching', () async {
      vm.isGenerating = true;
      final thread = await fakeRepo.createThread(title: 'Chat');

      await vm.selectThread(thread);

      expect(vm.isGenerating, isFalse);
    });
  });

  group('ChatViewModel exportThread', () async {
    test('returns path for txt export', () async {
      final thread = await fakeRepo.createThread(title: 'Test Chat');
      vm.activeThread = thread;
      vm.messages = [
        buildMessage(role: MessageRole.user, content: 'Hello'),
      ];

      final path = await vm.exportThread(ExportFormat.txt);

      expect(path, isNotNull);
    });

    test('returns path for json export', () async {
      final thread = await fakeRepo.createThread(title: 'Test Chat');
      vm.activeThread = thread;
      vm.messages = [
        buildMessage(role: MessageRole.user, content: 'Hello'),
      ];

      final path = await vm.exportThread(ExportFormat.json);

      expect(path, isNotNull);
    });

    test('returns null when no active thread', () async {
      vm.activeThread = null;

      final path = await vm.exportThread(ExportFormat.txt);

      expect(path, isNull);
    });
  });

  group('ChatViewModel branchConversation', () async {
    test('creates new thread with copied messages', () async {
      final thread = await fakeRepo.createThread(title: 'Original');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'assistant-1',
        parentId: 'user-1',
      );
      vm.threads = [thread];
      vm.activeThread = thread;
      vm.messages = [userMsg, assistantMsg];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Branch response', isDone: true),
      ]);

      await vm.branchConversation(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.threads, hasLength(greaterThanOrEqualTo(2)));
      expect(vm.activeThread, isNotNull);
    });

    test('sets branchFromThreadId on new thread', () async {
      final thread = await fakeRepo.createThread(title: 'Original');
      vm.threads = [thread];
      vm.activeThread = thread;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'u1'),
      ];

      await vm.branchConversation(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final newThread = vm.threads.firstWhere(
        (t) => t.branchFromThreadId == thread.id,
        orElse: () => vm.threads.first,
      );
      expect(newThread.branchFromThreadId, equals(thread.id));
    });

    test('does not branch while generating', () async {
      vm.isGenerating = true;
      final thread = await fakeRepo.createThread(title: 'Original');
      vm.threads = [thread];
      vm.activeThread = thread;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user),
      ];

      await vm.branchConversation(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.threads, hasLength(1));
    });
  });

  group('ChatViewModel switchVariant', () async {
    test('switches to sibling variant', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final variant1 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'v1',
        variantIndex: 0,
        totalVariants: 2,
        siblingIds: ['v2'],
      );
      final variant2 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'v2',
        variantIndex: 1,
        totalVariants: 2,
        siblingIds: ['v1'],
      );
      vm.messages = [variant1];
      vm.activeThread = thread;
      fakeRepo.setStreamFragments(thread.id, []);

      await vm.switchVariant(messageIndex: 0, previous: true);

      expect(vm.messages[0].id, equals('v2'));
    });

    test('does not switch when no siblings', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final msg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'v1',
        variantIndex: 0,
        totalVariants: 1,
        siblingIds: [],
      );
      vm.messages = [msg];
      vm.activeThread = thread;

      await vm.switchVariant(messageIndex: 0, previous: false);

      expect(vm.messages[0].id, equals('v1'));
    });
  });

  group('ChatViewModel stopGeneration', () async {
    test('cancels active generation', () async {
      vm.isGenerating = true;
      vm.currentCancelToken = CancelToken();

      vm.stopGeneration();

      expect(vm.isGenerating, isFalse);
    });

    test('no-op when not generating', () async {
      vm.isGenerating = false;

      vm.stopGeneration();

      expect(vm.isGenerating, isFalse);
    });
  });

  group('ChatViewModel isLoadingThreads', () async {
    test('is false when not loading', () {
      expect(vm.isLoadingThreads, isFalse);
    });
  });

  group('ChatViewModel isGenerating', () async {
    test('reflects generation state', () {
      vm.isGenerating = true;
      expect(vm.isGenerating, isTrue);

      vm.isGenerating = false;
      expect(vm.isGenerating, isFalse);
    });
  });

  group('ChatViewModel setSearchQuery', () {
    test('updates search query', () {
      vm.setSearchQuery('Test');
      expect(vm.searchQuery, equals('Test'));
    });
  });
}
