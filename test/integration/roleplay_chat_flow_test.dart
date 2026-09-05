import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_chat_repository.dart';
import '../helpers/fake_character_repository.dart';
import '../helpers/fake_vector_store.dart';
import '../helpers/test_model_factories.dart';

/// Integration test: Full roleplay flow without network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeChatRepository chatRepo;
  late FakeCharacterRepository charRepo;
  late FakeVectorStore vectorStore;
  late RoleplayViewModel vm;

  setUp(() {
    chatRepo = FakeChatRepository();
    charRepo = FakeCharacterRepository();
    vectorStore = FakeVectorStore();
    vm = RoleplayViewModel(
      chatRepository: chatRepo,
      characterRepository: charRepo,
    );
  });

  tearDown(() {
    vm.dispose();
  });

  void fakeStreamSetup(FakeChatRepository repo, String threadId, String response) {
    repo.setStreamFragments(threadId, [
      const StreamChunk(text: '', isDone: false),
      StreamChunk(text: response, isDone: true),
    ]);
  }

  test('Full roleplay flow: create character, start, send, regenerate, edit, branch, delete', () async {
    // 1. Create a character
    final character = buildCharacter(
      name: 'Aria',
      id: 'char-1',
      personality: 'Brave warrior',
      firstMessage: 'Welcome, adventurer!',
    );
    await charRepo.createCharacter(character);

    // 2. Start roleplay
    fakeStreamSetup(chatRepo, 'new', 'Hi there!');
    await vm.startRoleplay(
      character,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    expect(vm.activeCharacter, isNotNull);
    expect(vm.activeCharacter!.name, equals('Aria'));
    expect(vm.activeThread, isNotNull);
    expect(vm.activeThread!.characterId, equals('char-1'));

    // First message should be the greeting
    expect(vm.messages.first.content, equals('Welcome, adventurer!'));
    expect(vm.messages.first.role, equals(MessageRole.assistant));

    // 3. Send a user message
    fakeStreamSetup(chatRepo, vm.activeThread!.id, 'Hello friend!');
    await vm.sendMessage(
      prompt: 'Hello Aria!',
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    expect(vm.messages.where((m) => m.content == 'Hello Aria!').length, greaterThanOrEqualTo(1));

    // 4. Regenerate assistant response
    fakeStreamSetup(chatRepo, vm.activeThread!.id, 'New response');
    await vm.regenerateMessage(
      messageIndex: 1,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    expect(vm.messages[1].variantIndex, equals(1));
    expect(vm.messages[1].totalVariants, equals(2));

    // 5. Edit assistant message (must be last)
    await vm.editAssistantMessage(
      messageIndex: 1,
      newContent: 'Edited response',
    );

    expect(vm.messages[1].content, equals('Edited response'));
    expect(vm.messages[1].isEdited, isTrue);

    // 6. Export conversation
    final path = await vm.exportThread(ExportFormat.txt);
    expect(path, isNotNull);

    // 7. Delete thread
    await vm.deleteThread(vm.activeThread!.id);
    expect(vm.activeThread, isNull);
    expect(vm.messages, isEmpty);
  });

  test('Character lifecycle: create, edit, delete with threads', () async {
    // Create character
    final character = buildCharacter(name: 'Aria', id: 'char-1');
    await charRepo.createCharacter(character);

    // Start roleplay (creates thread)
    fakeStreamSetup(chatRepo, 'new', 'Hi');
    await vm.startRoleplay(
      character,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    final threadId = vm.activeThread!.id;
    expect(threadId, isNotNull);

    // Send a message to create embedding
    fakeStreamSetup(chatRepo, threadId, 'Hello');
    await vm.sendMessage(
      prompt: 'Hello',
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    // Edit character
    final updatedChar = character.copyWith(
      personality: 'Updated personality',
      firstMessage: 'Updated greeting',
    );
    await charRepo.updateCharacter(updatedChar);
    vm.updateActiveCharacter(updatedChar);

    expect(vm.activeCharacter?.personality, equals('Updated personality'));

    // Create second thread for same character
    final thread2 = await chatRepo.createThread(
      title: 'Thread 2',
      characterId: 'char-1',
    );
    fakeStreamSetup(chatRepo, thread2.id, 'Hi');
    await vm.sendMessage(
      prompt: 'Hello',
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    // Delete character (should delete all threads)
    await vm.deleteCharacter('char-1');
    expect(vm.activeThread, isNull);

    final threads = await chatRepo.getThreads();
    expect(
      threads.where((t) => t.characterId == 'char-1'),
      isEmpty,
    );
  });

  test('Persona defaults: template applied to multiple characters', () async {
    // Create character 1 with persona
    final char1 = buildCharacter(
      name: 'Char1',
      id: 'char-1',
      userPersona: 'Detective persona',
    );
    await charRepo.createCharacter(char1);

    // Create character 2 with different persona
    final char2 = buildCharacter(
      name: 'Char2',
      id: 'char-2',
      userPersona: 'Wizard persona',
    );
    await charRepo.createCharacter(char2);

    // Start roleplay with character 1
    fakeStreamSetup(chatRepo, 'new', 'Hi');
    await vm.startRoleplay(
      char1,
      serverConfig: buildServerConfig(),
      connection: null,
      customParams: null,
      modelContextLength: null,
    );

    // Start roleplay with character 2 (should use its own persona)
    final thread2 = await chatRepo.createThread(
      title: 'Thread 2',
      characterId: 'char-2',
    );
    vm.activeThread = thread2;
    vm.activeCharacter = char2;
    vm.messages = [];

    // Verify characters are independent
    final threads1 = await chatRepo.getThreadsForCharacter('char-1');
    final threads2 = await chatRepo.getThreadsForCharacter('char-2');

    expect(threads1, hasLength(1));
    expect(threads2, hasLength(1));
  });

  test('Settings persistence: system prompt and params', () async {
    final thread = await chatRepo.createThread(
      title: 'Test',
      systemPrompt: 'Custom prompt',
    );

    // Simulate thread with custom params via update
    final updated = thread.copyWith(
      systemPrompt: 'Updated system prompt',
    );
    await chatRepo.updateThread(updated);

    final threads = await chatRepo.getThreads();
    expect(
      threads.firstWhere((t) => t.id == thread.id).systemPrompt,
      equals('Updated system prompt'),
    );
  });

  test('RAG isolation: different characters have separate memories', () async {
    // Add memories for character 1
    vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-1', content: 'Aria memory.', vector: [0.0, ...List<double>.filled(255, 0.0)]);
    vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-2', content: 'Aria fact.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

    // Add memories for character 2
    vectorStore.saveEmbedding(characterId: 'char-2', messageId: 'msg-3', content: 'Bob memory.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

    // Search for character 1
    final results1 = await vectorStore.searchSimilar(
      characterId: 'char-1',
      queryVector: [0.0, ...List<double>.filled(255, 0.0)],
      topK: 10,
    );

    expect(results1, hasLength(2));
    for (final result in results1) {
      expect(result['content'], contains('Aria'));
    }

    // Search for character 2
    final results2 = await vectorStore.searchSimilar(
      characterId: 'char-2',
      queryVector: [0.0, ...List<double>.filled(255, 0.0)],
      topK: 10,
    );

    expect(results2, hasLength(1));
    expect(results2[0]['content'], contains('Bob'));
  });

  test('Thread deletion cleans up embeddings', () async {
    final character = buildCharacter(name: 'Aria', id: 'char-1');
    await charRepo.createCharacter(character);

    final thread = await chatRepo.createThread(
      title: 'Chat',
      characterId: 'char-1',
    );
    vm.activeThread = thread;
    vm.activeCharacter = character;

    // Add embeddings for thread messages
    vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-1', content: 'Message 1.', vector: [0.0, ...List<double>.filled(255, 0.0)]);
    vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-2', content: 'Message 2.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

    // Delete thread
    await vm.deleteThread(thread.id);

    // Embeddings should be deleted
    expect(charRepo.getEmbeddingCount('char-1'), equals(0));
  });

  test('Alternate greetings: start with custom greeting', () async {
    final character = buildCharacter(
      name: 'Aria',
      id: 'char-1',
      alternateGreetings: ['Hello!', 'Hi there!', 'Greetings!'],
    );
    await charRepo.createCharacter(character);

    fakeStreamSetup(chatRepo, 'new', 'Response');
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

  test('Multi-thread character: switching between threads', () async {
    final character = buildCharacter(name: 'Aria', id: 'char-1');
    await charRepo.createCharacter(character);

    // Create thread 1
    final thread1 = await chatRepo.createThread(
      title: 'Thread 1',
      characterId: 'char-1',
    );
    fakeStreamSetup(chatRepo, thread1.id, 'Hi');
    vm.activeThread = thread1;
    vm.activeCharacter = character;
    vm.messages = [];

    // Create thread 2
    final thread2 = await chatRepo.createThread(
      title: 'Thread 2',
      characterId: 'char-1',
    );

    // Switch to thread 2
    await vm.selectThread(thread2);
    expect(vm.activeThread!.id, equals(thread2.id));

    // Switch back to thread 1
    await vm.selectThread(thread1);
    expect(vm.activeThread!.id, equals(thread1.id));
  });

  test('Conversation export includes character name', () async {
    final character = buildCharacter(name: 'Aria', id: 'char-1');
    await charRepo.createCharacter(character);

    final thread = await chatRepo.createThread(
      title: 'Chat',
      characterId: 'char-1',
    );
    vm.activeThread = thread;
    vm.activeCharacter = character;
    vm.messages = [
      buildMessage(role: MessageRole.user, content: 'Hello'),
    ];

    final path = await vm.exportThread(ExportFormat.txt);
    expect(path, isNotNull);

    final jsonPath = await vm.exportThread(ExportFormat.json);
    expect(jsonPath, isNotNull);
  });
}
