import 'package:clan_ai/core/utils/roleplay_context_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_vector_store.dart';

void main() {
  group('RoleplayContextBuilder', () {
    test('build returns system prompt with retrieved memories', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      // Add some memories
      vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-1', content: 'Aria loves swords.', vector: [0.0, ...List<double>.filled(255, 0.0)]);
      vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-2', content: 'Aria hates dragons.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Brave warrior',
        userInput: 'What do you like?',
      );

      expect(context.systemPrompt, isNotEmpty);
      expect(context.systemPrompt, contains('Aria'));
      expect(context.systemPrompt, contains('Brave warrior'));
      expect(context.memories, isNotEmpty);
      expect(context.memories, contains('Aria loves swords.'));
      expect(context.memories, contains('Aria hates dragons.'));
    });

    test('build scopes memories to characterId', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-1', content: 'Memory for character 1.', vector: [0.0, ...List<double>.filled(255, 0.0)]);
      vectorStore.saveEmbedding(characterId: 'char-2', messageId: 'msg-2', content: 'Memory for character 2.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Warrior',
        userInput: 'Hello',
      );

      expect(context.memories, contains('Memory for character 1.'));
      expect(context.memories, isNot(contains('Memory for character 2.')));
    });

    test('build returns empty memories when none exist', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Warrior',
        userInput: 'Hello',
      );

      expect(context.systemPrompt, isNotEmpty);
      expect(context.memories, isEmpty);
    });

    test('build uses characterSystemPrompt override', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-1', content: 'Aria is brave.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Warrior',
        characterSystemPrompt: 'You are a merchant.',
        userInput: 'Hello',
      );

      expect(context.systemPrompt, contains('You are a merchant'));
      expect(context.memories, contains('Aria is brave.'));
    });

    test('build supports {{original}} prefix in characterSystemPrompt', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-1', content: 'Aria is brave.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Warrior',
        characterSystemPrompt: '{{original}}\n\nSpeak like a pirate.',
        postHistoryInstructions: 'Stay in character.',
        userInput: 'Hello',
      );

      expect(context.systemPrompt, contains('roleplaying as "Aria"'));
      expect(context.systemPrompt, contains('Speak like a pirate'));
      expect(context.systemPrompt, contains('Stay in character.'));
    });

    test('build includes postHistoryInstructions', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Warrior',
        postHistoryInstructions: 'Always respond in first person.',
        userInput: 'Hello',
      );

      expect(context.systemPrompt, contains('Always respond in first person.'));
    });

    test('build limits memories to top 3', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      for (int i = 0; i < 10; i++) {
        vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-$i', content: 'Memory $i.', vector: [0.0, ...List<double>.filled(255, 0.0)]);
      }

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Warrior',
        userInput: 'Hello',
      );

      expect(context.memories.length, lessThanOrEqualTo(3));
    });

    test('build with empty userPersona omits user persona section', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      final context = await builder.build(
        characterId: 'char-1',
        characterName: 'Aria',
        personality: 'Warrior',
        userInput: 'Hello',
      );

      expect(context.systemPrompt, isNotEmpty);
    });
  });
}
