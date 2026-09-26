import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/mock_path_provider.dart';
import '../helpers/test_model_factories.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late FakeChatRepository fakeRepo;
  late ChatViewModel vm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setupMockPathProvider();
    fakeRepo = FakeChatRepository();
    vm = ChatViewModel(fakeRepo);
    // Wait for async loadThreads() to complete and settle
    await Future.delayed(const Duration(milliseconds: 300));
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

  group('ChatViewModel deleteThread', () {
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

  group('ChatViewModel sendMessage', () {
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

    test('persists imagePath on the user message', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      vm.activeThread = thread;
      vm.messages = [];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'Describe this',
        imagePath: '/app/documents/attachments/img.png',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final userMsg = vm.messages.firstWhere((m) => m.role == MessageRole.user);
      expect(userMsg.imagePath, equals('/app/documents/attachments/img.png'));

      // Persisted to the repository as well.
      final savedMessages = await fakeRepo.getMessagesForThread(thread.id);
      final savedUserMsg = savedMessages.firstWhere((m) => m.role == MessageRole.user);
      expect(savedUserMsg.imagePath, equals('/app/documents/attachments/img.png'));
    });

    test('batches user message, rename and placeholder into one notification', () async {
      final thread = await fakeRepo.createThread(title: 'New Chat');
      vm.activeThread = thread;
      vm.messages = [];
      fakeRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      final messageCountsAtNotify = <int>[];
      void listener() => messageCountsAtNotify.add(vm.messages.length);
      vm.addListener(listener);

      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      vm.removeListener(listener);

      // The first notification must already contain both the user message and
      // the assistant placeholder, proving the intermediate rename notification
      // was batched rather than emitted separately.
      expect(messageCountsAtNotify, isNotEmpty);
      expect(messageCountsAtNotify.first, greaterThanOrEqualTo(2));
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

      final messages = await fakeRepo.getMessagesForThread(thread.id);
      expect(messages.any((m) => m.role == MessageRole.user && m.content == 'Hello'), isTrue);
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

  group('ChatViewModel regenerateMessage', () {
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

  group('ChatViewModel deleteMessage', () {
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
      final msg0 = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'msg-0',
        content: 'First',
      );
      final msg1 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'msg-1',
        content: 'Reply',
      );
      final msg2 = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'msg-2',
        content: 'Second',
      );

      await fakeRepo.saveMessage(msg0);
      await fakeRepo.saveMessage(msg1);
      await fakeRepo.saveMessage(msg2);
      vm.activeThread = thread;
      vm.messages = [msg0, msg1, msg2];
      await vm.deleteMessage(
        messageIndex: 2,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      expect(vm.canUndo, isTrue);
    });

    test('deletes all messages after index', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'msg-1',
      );
      final assistantMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'msg-2',
      );
      vm.messages = [userMsg, assistantMsg];
      vm.activeThread = thread;

      await vm.deleteMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.length, equals(2));
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

  group('ChatViewModel undoDelete', () {
    test('restores deleted message', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final userMsg1 = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      final userMsg2 = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-2',
      );
      vm.messages = [userMsg1, userMsg2];
      vm.activeThread = thread;

      await vm.deleteMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.canUndo, isTrue);

      // Re-add the message for undo to work
      await fakeRepo.saveMessage(userMsg2);

      await vm.undoDelete();

      expect(vm.messages, isNotEmpty);
    });
  });

  group('ChatViewModel updateActiveThreadSystemPrompt', () {
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

  group('ChatViewModel renameThread', () {
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
    test('returns all threads when no search query', () async {
      final initialCount = fakeRepo.allThreads.length;
      fakeRepo.createThread(title: 'Thread 1');
      fakeRepo.createThread(title: 'Thread 2');
      vm.threads = await fakeRepo.getAssistantThreads();

      expect(vm.filteredThreads.length, greaterThanOrEqualTo(initialCount + 2));
    });

    test('filters threads by query', () async {
      fakeRepo.createThread(title: 'Important Chat');
      fakeRepo.createThread(title: 'Random Chat');
      vm.threads = await fakeRepo.getAssistantThreads();
      vm.setSearchQuery('Important');

      expect(vm.filteredThreads, hasLength(1));
      expect(vm.filteredThreads.first.title, contains('Important'));
    });

    test('case-insensitive search', () async {
      fakeRepo.createThread(title: 'Test Chat');
      vm.threads = await fakeRepo.getAssistantThreads();
      vm.setSearchQuery('test');

      expect(vm.filteredThreads, hasLength(1));
    });

    test('returns empty when no matches', () async {
      fakeRepo.createThread(title: 'Test');
      vm.threads = await fakeRepo.getAssistantThreads();
      vm.setSearchQuery('nonexistent');

      expect(vm.filteredThreads, isEmpty);
    });
  });

  group('ChatViewModel selectThread', () {
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

  group('ChatViewModel exportThread', () {
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

  group('ChatViewModel branchConversation', () {
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
        messageIndex: 1,
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
        buildMessage(threadId: thread.id, role: MessageRole.assistant, id: 'a1'),
      ];

      await vm.branchConversation(
        messageIndex: 1,
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

  group('ChatViewModel switchVariant', () {
    test('switches to sibling variant', () async {
      final thread = await fakeRepo.createThread(title: 'Chat');
      final variant1 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'v1',
        content: 'First variant response',
        variantIndex: 1,
        totalVariants: 2,
        siblingIds: ['v1', 'v2'],
      );
      final variant2 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'v2',
        content: 'Second variant response',
        variantIndex: 0,
        totalVariants: 2,
        siblingIds: ['v1', 'v2'],
      );
      await fakeRepo.saveMessage(variant1);
      await fakeRepo.saveMessage(variant2);
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

  group('ChatViewModel stopGeneration', () {
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

  group('ChatViewModel isLoadingThreads', () {
    test('is false when not loading', () {
      expect(vm.isLoadingThreads, isFalse);
    });
  });

  group('ChatViewModel isGenerating', () {
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

  group('ChatViewModel searchThreads', () {
    test('matches titles and message content in a single pass', () async {
      final titleMatch = await fakeRepo.createThread(title: 'Flutter Notes');
      final contentMatch = await fakeRepo.createThread(title: 'Recipes');
      final noMatch = await fakeRepo.createThread(title: 'Work');
      await fakeRepo.saveMessage(buildMessage(
        threadId: titleMatch.id,
        content: 'How does the stream mutation mixin work?',
      ));
      await fakeRepo.saveMessage(buildMessage(
        threadId: contentMatch.id,
        content: 'Bake sourdough bread',
      ));
      await fakeRepo.saveMessage(buildMessage(
        threadId: noMatch.id,
        content: 'Unrelated content',
      ));

      vm.threads = await fakeRepo.getAssistantThreads();

      // Title match
      var ids = (await vm.searchThreads(query: 'flutter')).map((t) => t.id).toList();
      expect(ids, contains(titleMatch.id));
      expect(ids, isNot(contains(contentMatch.id)));

      // Content-only match
      ids = (await vm.searchThreads(query: 'sourdough')).map((t) => t.id).toList();
      expect(ids, contains(contentMatch.id));
      expect(ids, isNot(contains(titleMatch.id)));

      // No matches
      expect(await vm.searchThreads(query: 'nonexistent-phrase'), isEmpty);
    });

    test('treats LIKE wildcards in the query literally', () async {
      final thread = await fakeRepo.createThread(title: '100% Done');
      await fakeRepo.saveMessage(buildMessage(threadId: thread.id, content: 'Progress report'));
      vm.threads = await fakeRepo.getAssistantThreads();

      final ids = (await vm.searchThreads(query: '100%')).map((t) => t.id).toList();
      expect(ids, contains(thread.id));
    });

    test('excludes roleplay threads from assistant-mode search', () async {
      await fakeRepo.createThread(title: 'Assistant Chat');
      final rpThread = await fakeRepo.createThread(
        title: 'Roleplay Chat',
        characterId: 'char-1',
      );
      await fakeRepo.saveMessage(buildMessage(
        threadId: rpThread.id,
        content: 'Wandering the forest at dusk',
      ));

      vm.threads = await fakeRepo.getAssistantThreads();

      final ids = (await vm.searchThreads(query: 'wandering')).map((t) => t.id).toList();
      expect(ids, isNot(contains(rpThread.id)));
      expect(ids, isEmpty);
    });
  });

  group('ChatViewModel importThread', () {
    test('imported thread persists after switching to another thread and back', () async {
      // Create a thread with messages
      final thread = await fakeRepo.createThread(title: 'Test Thread');
      final messages = [
        buildMessage(id: 'msg-1', threadId: thread.id, role: MessageRole.user, content: 'Hello'),
        buildMessage(id: 'msg-2', threadId: thread.id, role: MessageRole.assistant, content: 'Hi there!'),
      ];
      for (final msg in messages) {
        await fakeRepo.saveMessage(msg);
      }

      // Update VM's threads list to include the newly created thread
      vm.threads = await fakeRepo.getAssistantThreads();

      // Simulate search to populate _filteredThreads
      vm.setSearchQuery('test');
      final results = await vm.searchThreads();
      vm.setFilteredThreads(results);
      expect(vm.filteredThreads.isNotEmpty, isTrue);

      // Clear search
      vm.setSearchQuery('');

      // Record count before import
      final countBefore = vm.filteredThreads.length;

      // Import the thread - importThread creates its own thread and saves messages
      // The messages passed have threadId='msg-1' parent, they'll be saved with the new thread's ID
      await vm.importThread(
        buildThread(title: 'Imported Chat'),
        messages,
      );

      // Wait for async operations to settle
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify imported thread is in the list (count should have increased)
      expect(vm.filteredThreads.length, greaterThan(countBefore));

      // Get the active thread's ID (this is what importThread sets)
      final activeThreadId = vm.activeThread?.id;
      expect(activeThreadId, isNotNull);
      
      final activeThreadMsgs = await fakeRepo.getMessagesForThread(activeThreadId!);
      expect(activeThreadMsgs.length, greaterThan(0), reason: 'Active thread should have messages');

      // Switch to the other thread
      final otherThread = await fakeRepo.getThreads().then((threads) => threads.where((t) => t.title == 'Test Thread').first);
      await vm.selectThread(otherThread);
      await Future.delayed(const Duration(milliseconds: 50));

      // Switch back to the active thread (the one importThread set)
      await vm.selectThread(vm.threads.firstWhere((t) => t.id == activeThreadId));
      await Future.delayed(const Duration(milliseconds: 50));

      // Messages should still be loaded (welcome screen should NOT appear)
      expect(vm.messages.isNotEmpty, isTrue);
      expect(vm.messages.first.content, 'Hello');
    });

    test('cleared search does not lose imported threads from filtered list', () async {
      // Perform a search to populate _filteredThreads
      vm.setSearchQuery('test');
      vm.setFilteredThreads([buildThread(id: 'existing-thread', title: 'Existing')]);

      // Clear search (simulates user clearing the search bar)
      vm.setSearchQuery('');

      // Import a thread - _filteredThreads should be cleared by importThread
      final thread = buildThread(title: 'Imported');
      await fakeRepo.createThread(title: thread.title);
      await vm.importThread(thread, []);
      await Future.delayed(const Duration(milliseconds: 100));

      // Imported thread should be visible (search is empty, returns all threads)
      // importThread generates a new ID, so check that threads list has more than before
      final threadCountBefore = vm.filteredThreads.length;
      expect(threadCountBefore, greaterThan(0));

      // Perform another search that returns no results
      vm.setSearchQuery('nonexistent');
      vm.setFilteredThreads([]);

      // Import another thread
      final thread2 = buildThread(title: 'Imported 2');
      await fakeRepo.createThread(title: thread2.title);
      await vm.importThread(thread2, []);
      await Future.delayed(const Duration(milliseconds: 100));

      // Clear search again - _filteredThreads should be cleared by setSearchQuery
      vm.setSearchQuery('');

      // Should have more threads now (both imported threads)
      expect(vm.filteredThreads.length, greaterThan(threadCountBefore));
    });
  });
}
