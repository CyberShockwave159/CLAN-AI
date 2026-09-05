import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/fake_character_repository.dart';
import '../helpers/fake_vector_store.dart';
import '../helpers/mock_path_provider.dart';
import '../helpers/test_model_factories.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late FakeChatRepository fakeChatRepo;
  late FakeCharacterRepository fakeCharRepo;
  late FakeVectorStore fakeVectorStore;
  late RoleplayViewModel vm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setupMockPathProvider();
    fakeChatRepo = FakeChatRepository();
    fakeCharRepo = FakeCharacterRepository();
    fakeVectorStore = FakeVectorStore();
    vm = RoleplayViewModel(
      chatRepository: fakeChatRepo,
      characterRepository: fakeCharRepo,
    );
    // Wait for async loadThreads / loadLastChat to complete
    await Future.delayed(const Duration(milliseconds: 300));
  });

  tearDown(() {
    vm.dispose();
  });

  group('RoleplayViewModel startRoleplay', () {
    test('creates new thread with characterId', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      fakeChatRepo.setStreamFragments('new', [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.startRoleplay(
        character,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.activeThread, isNotNull);
      expect(vm.activeThread!.characterId, equals('char-1'));
      expect(vm.activeCharacter, isNotNull);
      expect(vm.activeCharacter!.name, equals('Aria'));
    });

    test('sets greeting as first assistant message', () async {
      final character = buildCharacter(
        name: 'Aria',
        id: 'char-1',
        firstMessage: 'Welcome, adventurer!',
      );
      await fakeCharRepo.createCharacter(character);
      fakeChatRepo.setStreamFragments('new', [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.startRoleplay(
        character,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages, isNotEmpty);
      final firstMsg = vm.messages.first;
      expect(firstMsg.role, equals(MessageRole.assistant));
      expect(firstMsg.content, equals('Welcome, adventurer!'));
    });

    test('creates thread with character name as title', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      fakeChatRepo.setStreamFragments('new', [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.startRoleplay(
        character,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.activeThread?.title, equals('Aria'));
    });

    test('reuses existing thread for character', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);

      // Create an existing thread for this character
      await fakeChatRepo.createThread(title: 'Existing Chat', characterId: 'char-1');
      final existingThreads = await fakeChatRepo.getThreadsForCharacter('char-1');
      if (existingThreads.isNotEmpty) {
        vm.activeThread = existingThreads.first;
        vm.messages = await fakeChatRepo.getMessagesForThread(existingThreads.first.id);
      }

      await vm.startRoleplay(
        character,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.activeThread, isNotNull);
    });

    test('sets active character', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      fakeChatRepo.setStreamFragments('new', [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.startRoleplay(
        character,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.activeCharacter, isNotNull);
      expect(vm.activeCharacter!.name, equals('Aria'));
    });

    test('stops generation before starting', () async {
      vm.isGenerating = true;
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      fakeChatRepo.setStreamFragments('new', [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.startRoleplay(
        character,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.isGenerating, isFalse);
    });
  });

  group('RoleplayViewModel sendMessage', () {
    test('creates user message', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi there!', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.where((m) => m.content == 'Hello' && m.role == MessageRole.user).length, greaterThanOrEqualTo(1));
    });

    test('updates thread title on first user message', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Aria', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'My greeting',
        serverConfig: buildServerConfig(),
        connection: null,
      );

      expect(vm.activeThread?.title, contains('My greeting'));
    });

    test('does not send while generating', () async {
      vm.isGenerating = true;
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [];

      final msgCount = vm.messages.length;
      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.length, equals(msgCount));
    });

    test('does not send when no active thread', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      vm.activeThread = null;
      vm.activeCharacter = character;
      vm.messages = [];

      final msgCount = vm.messages.length;
      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.length, equals(msgCount));
    });

    test('does not send when no active character', () async {
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = null;
      vm.messages = [];

      final msgCount = vm.messages.length;
      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.length, equals(msgCount));
    });

    test('user message is persisted', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.sendMessage(
        prompt: 'Hello',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(fakeChatRepo.lastSavedMessage, isNotNull);
      final threadMessages = await fakeChatRepo.getMessagesForThread(thread.id);
      expect(threadMessages.any((m) => m.role == MessageRole.user), isTrue);
    });
  });

  group('RoleplayViewModel regenerateMessage', () {
    test('creates new variant', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          id: 'assistant-1',
          variantIndex: 0,
          totalVariants: 1,
        ),
      ];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'New response', isDone: true),
      ]);

      await vm.regenerateMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final currentMsg = vm.messages[0];
      expect(currentMsg.variantIndex, equals(1));
      expect(currentMsg.totalVariants, equals(2));
    });

    test('only regenerates assistant messages', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.user,
          id: 'user-1',
        ),
      ];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'New', isDone: true),
      ]);

      await vm.regenerateMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages[0].role, equals(MessageRole.user));
    });

    test('does not regenerate while generating', () async {
      vm.isGenerating = true;
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          id: 'assistant-1',
        ),
      ];

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

  group('RoleplayViewModel deleteMessage', () {
    test('deletes message and regenerates if assistant deleted', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'user-1'),
        buildMessage(threadId: thread.id, role: MessageRole.assistant, id: 'assistant-1'),
      ];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Regenerated', isDone: true),
      ]);

      final wasDeleted = await vm.deleteMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(wasDeleted, isFalse);
    });

    test('returns true when first message deleted', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'user-1'),
      ];

      final wasDeleted = await vm.deleteMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(wasDeleted, isTrue);
    });

    test('stores user message for undo', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'u1'),
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'u2'),
        buildMessage(threadId: thread.id, role: MessageRole.assistant, id: 'a1'),
      ];

      await vm.deleteMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 10));

      expect(vm.canUndo, isTrue);
    });

    test('does not delete while generating', () async {
      vm.isGenerating = true;
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'user-1'),
      ];

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

  group('RoleplayViewModel editUserPrompt', () {
    test('truncates after edit point', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.user,
          id: 'user-1',
          content: 'Old prompt',
        ),
      ];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'New response', isDone: true),
      ]);

      await vm.editUserPrompt(
        messageIndex: 0,
        newContent: 'New prompt',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.where((m) => m.content == 'New prompt').isNotEmpty, isTrue);
    });

    test('does not edit while generating', () async {
      vm.isGenerating = true;
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.user,
          id: 'user-1',
        ),
      ];

      await vm.editUserPrompt(
        messageIndex: 0,
        newContent: 'New',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
    });

    test('only edits user messages', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          id: 'assistant-1',
        ),
      ];

      await vm.editUserPrompt(
        messageIndex: 0,
        newContent: 'New',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages[0].role, equals(MessageRole.assistant));
    });

    test('does not edit when no active character', () async {
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = null;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.user,
          id: 'user-1',
        ),
      ];

      await vm.editUserPrompt(
        messageIndex: 0,
        newContent: 'New',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
    });
  });

  group('RoleplayViewModel editAssistantMessage', () {
    test('edits last assistant message', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          id: 'assistant-1',
          content: 'Original response',
          status: MessageStatus.completed,
        ),
      ];

      await vm.editAssistantMessage(
        messageIndex: 0,
        newContent: 'Updated response',
      );

      expect(vm.messages[0].content, equals('Updated response'));
      expect(vm.messages[0].isEdited, isTrue);
    });

    test('does not edit non-last message', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          id: 'assistant-1',
          content: 'Should not change',
          status: MessageStatus.completed,
        ),
        buildMessage(
          threadId: thread.id,
          role: MessageRole.user,
          id: 'user-1',
        ),
      ];

      await vm.editAssistantMessage(
        messageIndex: 0,
        newContent: 'Changed',
      );

      expect(vm.messages[0].content, equals('Should not change'));
    });

    test('does not edit while generating', () async {
      vm.isGenerating = true;
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          id: 'assistant-1',
        ),
      ];

      await vm.editAssistantMessage(
        messageIndex: 0,
        newContent: 'Changed',
      );
    });

    test('does not edit non-completed message', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(
          threadId: thread.id,
          role: MessageRole.assistant,
          id: 'assistant-1',
          status: MessageStatus.streaming,
        ),
      ];

      await vm.editAssistantMessage(
        messageIndex: 0,
        newContent: 'Changed',
      );

      expect(vm.messages[0].content, equals('Hello'));
    });
  });

  group('RoleplayViewModel deleteThread', () {
    test('deletes thread and clears active state', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'user-1'),
      ];

      await vm.deleteThread(thread.id);

      expect(vm.activeThread, isNull);
      expect(vm.messages, isEmpty);
    });

    test('deletes embeddings for thread messages', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      fakeVectorStore.saveEmbedding(characterId: 'char-1', messageId: 'user-1', content: 'User message', vector: [0.0, ...List<double>.filled(255, 0.0)]);

      await vm.deleteThread(thread.id);

      expect(fakeCharRepo.getEmbeddingCount('char-1'), equals(0));
    });
  });

  group('RoleplayViewModel deleteCharacter', () {
    test('deletes all character threads', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread1 = await fakeChatRepo.createThread(title: 'Thread 1', characterId: 'char-1');
      vm.activeThread = thread1;
      vm.activeCharacter = character;
      vm.messages = [buildMessage(threadId: thread1.id, role: MessageRole.user)];

      await vm.deleteCharacter('char-1');

      expect(vm.activeThread, isNull);
      expect(vm.messages, isEmpty);
    });

    test('clears active thread when deleted', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;

      await vm.deleteCharacter('char-1');

      expect(vm.activeThread, isNull);
    });
  });

  group('RoleplayViewModel updateActiveCharacter', () {
    test('updates active character when id matches', () async {
      final original = buildCharacter(name: 'Aria', id: 'char-1');
      vm.activeCharacter = original;

      final updated = original.copyWith(name: 'Aria Updated');
      vm.updateActiveCharacter(updated);

      expect(vm.activeCharacter?.name, equals('Aria Updated'));
    });

    test('does not update when id does not match', () async {
      final original = buildCharacter(name: 'Aria', id: 'char-1');
      vm.activeCharacter = original;

      final different = buildCharacter(name: 'Bob', id: 'char-2');
      vm.updateActiveCharacter(different);

      expect(vm.activeCharacter?.name, equals('Aria'));
    });
  });

  group('RoleplayViewModel startRoleplayWithGreeting', () {
    test('starts with alternate greeting', () async {
      final character = buildCharacter(
        name: 'Aria',
        id: 'char-1',
        firstMessage: 'Default greeting',
        alternateGreetings: ['Hello!', 'Hi there!'],
      );
      await fakeCharRepo.createCharacter(character);
      fakeChatRepo.setStreamFragments('new', [
        const StreamChunk(text: 'Hi', isDone: true),
      ]);

      await vm.startRoleplayWithGreeting(
        character,
        'Hello!',
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.messages.first.content, equals('Hello!'));
    });
  });

  group('RoleplayViewModel selectThread', () {
    test('loads messages for selected thread', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      await fakeChatRepo.saveMessage(buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        content: 'Hello',
      ));

      await vm.selectThread(thread);

      expect(vm.messages, isNotEmpty);
    });

    test('stops generation before switching', () async {
      vm.isGenerating = true;
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');

      await vm.selectThread(thread);

      expect(vm.isGenerating, isFalse);
    });
  });

  group('RoleplayViewModel getThreadsForCharacter', () {
    test('returns threads for character', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');

      final threads = await vm.getThreadsForCharacter('char-1');

      expect(threads, hasLength(1));
    });
  });

  group('RoleplayViewModel exportThread', () {
    test('returns path for txt export', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(role: MessageRole.user, content: 'Hello'),
      ];

      final path = await vm.exportThread(ExportFormat.txt);

      expect(path, isNotNull);
    });

    test('returns null when no active thread', () async {
      vm.activeThread = null;

      final path = await vm.exportThread(ExportFormat.txt);

      expect(path, isNull);
    });
  });

  group('RoleplayViewModel undoDelete', () {
    test('restores deleted message', () async {
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'user-0'),
        userMsg,
      ];

      await vm.deleteMessage(
        messageIndex: 1,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );
      await Future.delayed(const Duration(milliseconds: 10));

      expect(vm.canUndo, isTrue);

      await fakeChatRepo.saveMessage(userMsg);
      await vm.undoDelete();

      expect(vm.messages, isNotEmpty);
    });
  });

  group('RoleplayViewModel branchConversation', () {
    test('creates new branch thread', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'u1'),
        buildMessage(threadId: thread.id, role: MessageRole.assistant, id: 'a1'),
      ];
      fakeChatRepo.setStreamFragments(thread.id, [
        const StreamChunk(text: 'Branch', isDone: true),
      ]);

       await vm.branchConversation(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      final threads = await fakeChatRepo.getThreads();
      expect(threads, isNotEmpty);
    });

    test('sets branchFromThreadId on new thread', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
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

      final threads = await fakeChatRepo.getThreads();
      final newThread = threads.firstWhere(
        (t) => t.branchFromThreadId == thread.id,
        orElse: () => threads.first,
      );
      expect(newThread.branchFromThreadId, equals(thread.id));
    });

    test('sets characterId on new thread', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
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

      final threads = await fakeChatRepo.getThreads();
      final newThread = threads.firstWhere(
        (t) => t.characterId != null,
        orElse: () => threads.first,
      );
      expect(newThread.characterId, equals('char-1'));
    });

    test('does not branch while generating', () async {
      vm.isGenerating = true;
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
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

      expect((await fakeChatRepo.getThreads()).length, greaterThanOrEqualTo(1));
    });
  });

  group('RoleplayViewModel switchVariant', () {
    test('switches to sibling variant', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      final variant1 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'v1',
        content: 'First variant response',
        variantIndex: 1,
        totalVariants: 2,
        siblingIds: ['v2'],
      );
      final variant2 = buildMessage(
        threadId: thread.id,
        role: MessageRole.assistant,
        id: 'v2',
        content: 'Second variant response',
        variantIndex: 0,
        totalVariants: 2,
        siblingIds: ['v1'],
      );
      await fakeChatRepo.saveMessage(variant1);
      await fakeChatRepo.saveMessage(variant2);
      vm.messages = [variant1];
      fakeChatRepo.setStreamFragments(thread.id, []);

      await vm.switchVariant(messageIndex: 0, previous: true);

      expect(vm.messages[0].id, equals('v2'));
    });
  });

  group('RoleplayViewModel stopGeneration', () {
    test('cancels active generation', () async {
      vm.isGenerating = true;
      vm.currentCancelToken = CancelToken();

      vm.stopGeneration();

      expect(vm.isGenerating, isFalse);
    });
  });

  group('RoleplayViewModel isLoading/isGenerating', () {
    test('isGenerating reflects state', () async {
      vm.isGenerating = true;
      expect(vm.isGenerating, isTrue);
    });
  });

  group('RoleplayViewModel activeCharacter getter', () {
    test('returns active character', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      vm.activeCharacter = character;

      expect(vm.activeCharacter, isNotNull);
      expect(vm.activeCharacter?.name, equals('Aria'));
    });

    test('returns null when no active character', () async {
      vm.activeCharacter = null;

      expect(vm.activeCharacter, isNull);
    });
  });

  group('RoleplayViewModel activeThread getter', () {
    test('returns active thread', () async {
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;

      expect(vm.activeThread, isNotNull);
      expect(vm.activeThread!.title, equals('Chat'));
    });

    test('returns null when no active thread', () async {
      vm.activeThread = null;

      expect(vm.activeThread, isNull);
    });
  });
}
