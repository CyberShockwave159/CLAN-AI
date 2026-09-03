import 'dart:async';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/fake_character_repository.dart';
import '../helpers/fake_vector_store.dart';
import '../helpers/test_model_factories.dart';

void main() {
  late FakeChatRepository fakeChatRepo;
  late FakeCharacterRepository fakeCharRepo;
  late FakeVectorStore fakeVectorStore;
  late RoleplayViewModel vm;

  setUp(() {
    fakeChatRepo = FakeChatRepository();
    fakeCharRepo = FakeCharacterRepository();
    fakeVectorStore = FakeVectorStore();
    vm = RoleplayViewModel(
      chatRepository: fakeChatRepo,
      characterRepository: fakeCharRepo,
    );
  });

  tearDown(() {
    vm.dispose();
  });

  group('RoleplayViewModel startRoleplay', () async {
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

  group('RoleplayViewModel sendMessage', () async {
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
        customParams: null,
        modelContextLength: null,
      });

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
      expect(fakeChatRepo.lastSavedMessage!.role, equals(MessageRole.user));
    });
  });

  group('RoleplayViewModel regenerateMessage', () async {
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

  group('RoleplayViewModel deleteMessage', () async {
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
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'user-1'),
      ];

      await vm.deleteMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

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

  group('RoleplayViewModel editUserPrompt', () async {
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

  group('RoleplayViewModel editAssistantMessage', () async {
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

      expect(vm.messages[0].content, equals(''));
    });
  });

  group('RoleplayViewModel deleteThread', () async {
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
      fakeVectorStore.addEmbedding('char-1', 'user-1', 'User message');

      await vm.deleteThread(thread.id);

      expect(fakeCharRepo.getEmbeddingCount('char-1'), equals(0));
    });
  });

  group('RoleplayViewModel deleteCharacter', () async {
    test('deletes all character threads', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread1 = await fakeChatRepo.createThread(title: 'Thread 1', characterId: 'char-1');
      final thread2 = await fakeChatRepo.createThread(title: 'Thread 2', characterId: 'char-1');
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

  group('RoleplayViewModel updateActiveCharacter', () async {
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

  group('RoleplayViewModel startRoleplayWithGreeting', () async {
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

  group('RoleplayViewModel selectThread', () async {
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

  group('RoleplayViewModel getThreadsForCharacter', () async {
    test('returns threads for character', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');

      final threads = await vm.getThreadsForCharacter('char-1');

      expect(threads, hasLength(1));
    });
  });

  group('RoleplayViewModel exportThread', () async {
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

  group('RoleplayViewModel undoDelete', () async {
    test('restores deleted message', () async {
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      final userMsg = buildMessage(
        threadId: thread.id,
        role: MessageRole.user,
        id: 'user-1',
      );
      vm.messages = [userMsg];

      await vm.deleteMessage(
        messageIndex: 0,
        serverConfig: buildServerConfig(),
        connection: null,
        customParams: null,
        modelContextLength: null,
      );

      expect(vm.canUndo, isTrue);

      await fakeChatRepo.saveMessage(userMsg);
      await vm.undoDelete();

      expect(vm.messages, isNotEmpty);
    });
  });

  group('RoleplayViewModel branchConversation', () async {
    test('creates new branch thread', () async {
      final character = buildCharacter(name: 'Aria', id: 'char-1');
      await fakeCharRepo.createCharacter(character);
      final thread = await fakeChatRepo.createThread(title: 'Chat', characterId: 'char-1');
      vm.activeThread = thread;
      vm.activeCharacter = character;
      vm.messages = [
        buildMessage(threadId: thread.id, role: MessageRole.user, id: 'u1'),
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

      expect(vm.threads, isNotEmpty);
    });

    test('sets branchFromThreadId on new thread', () async {
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

      final newThread = vm.threads.firstWhere(
        (t) => t.branchFromThreadId == thread.id,
        orElse: () => vm.threads.first,
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

      final newThread = vm.threads.firstWhere(
        (t) => t.characterId != null,
        orElse: () => vm.threads.first,
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

      expect(vm.threads, hasLength(1));
    });
  });

  group('RoleplayViewModel switchVariant', () async {
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
      fakeChatRepo.setStreamFragments(thread.id, []);

      await vm.switchVariant(messageIndex: 0, previous: true);

      expect(vm.messages[0].id, equals('v2'));
    });
  });

  group('RoleplayViewModel stopGeneration', () async {
    test('cancels active generation', () async {
      vm.isGenerating = true;
      vm.currentCancelToken = CancelToken();

      vm.stopGeneration();

      expect(vm.isGenerating, isFalse);
    });
  });

  group('RoleplayViewModel isLoading/isGenerating', () async {
    test('isGenerating reflects state', () async {
      vm.isGenerating = true;
      expect(vm.isGenerating, isTrue);
    });
  });

  group('RoleplayViewModel activeCharacter getter', () async {
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

  group('RoleplayViewModel activeThread getter', () async {
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
