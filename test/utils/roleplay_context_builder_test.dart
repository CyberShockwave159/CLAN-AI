import 'package:clan_ai/core/utils/roleplay_context_builder.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_vector_store.dart';

void main() {
  group('RoleplayContextBuilder', () {
    test('build returns system prompt with retrieved memories', () async {
      final vectorStore = FakeVectorStore();
      final builder = RoleplayContextBuilder(vectorStore: vectorStore);

      // Add some memories
      vectorStore.addEmbedding('char-1', 'msg-1', 'Aria loves swords.');
      vectorStore.addEmbedding('char-1', 'msg-2', 'Aria hates dragons.');

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

      vectorStore.addEmbedding('char-1', 'msg-1', 'Memory for character 1.');
      vectorStore.addEmbedding('char-2', 'msg-2', 'Memory for character 2.');

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

      vectorStore.addEmbedding('char-1', 'msg-1', 'Aria is brave.');

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

      vectorStore.addEmbedding('char-1', 'msg-1', 'Aria is brave.');

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
        vectorStore.addEmbedding('char-1', 'msg-$i', 'Memory $i.');
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
