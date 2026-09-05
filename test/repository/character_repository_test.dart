import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_character_repository.dart';
import '../helpers/mock_path_provider.dart';
import '../helpers/test_model_factories.dart';

late FakeCharacterRepository repo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupMockPathProvider();
  });

  setUp(() {
    repo = FakeCharacterRepository();
  });

  group('CharacterRepository getAllCharacters', () {
    test('returns empty list when no characters', () async {
      final characters = await repo.getAllCharacters();
      expect(characters, isEmpty);
    });

    test('returns all characters', () async {
      await repo.createCharacter(buildCharacter(name: 'Char 1'));
      await repo.createCharacter(buildCharacter(name: 'Char 2'));

      final characters = await repo.getAllCharacters();
      expect(characters, hasLength(2));
    });
  });

  group('CharacterRepository getCharacterById', () {
    test('returns character by id', () async {
      final char = buildCharacter(name: 'Test', id: 'char-1');
      await repo.createCharacter(char);

      final result = await repo.getCharacterById('char-1');
      expect(result, isNotNull);
      expect(result!.name, equals('Test'));
    });

    test('returns null for non-existent character', () async {
      final result = await repo.getCharacterById('non-existent');
      expect(result, isNull);
    });
  });

  group('CharacterRepository createCharacter', () {
    test('creates new character', () async {
      final char = buildCharacter(name: 'New Character');
      await repo.createCharacter(char);

      final characters = await repo.getAllCharacters();
      expect(characters, hasLength(1));
      expect(characters.first.name, equals('New Character'));
    });

    test('merges on duplicate name', () async {
      final char1 = buildCharacter(name: 'Aria', id: 'char-1', personality: 'Warrior');
      final char2 = buildCharacter(name: 'Aria', id: 'char-2', personality: 'Mage');

      await repo.createCharacter(char1);
      final result = await repo.createCharacter(char2);

      expect(result.personality, equals('Mage'));
      final characters = await repo.getAllCharacters();
      expect(characters, hasLength(1));
    });

    test('preserves memories when merging', () async {
      final char1 = buildCharacter(
        name: 'Aria',
        id: 'char-1',
        firstMessage: 'Original greeting',
      );
      await repo.createCharacter(char1);
      repo.addEmbedding('char-1', 'msg-1', 'A memory.');

      final char2 = buildCharacter(
        name: 'Aria',
        id: 'char-2',
        firstMessage: 'New greeting',
      );
      await repo.createCharacter(char2);

      // Embeddings should still exist for char-1 (the kept character)
      expect(repo.getEmbeddingCount('char-1'), equals(1));
    });
  });

  group('CharacterRepository updateCharacter', () {
    test('updates character fields', () async {
      final char = buildCharacter(name: 'Old Name', id: 'char-1');
      await repo.createCharacter(char);

      final updated = char.copyWith(name: 'New Name', personality: 'Updated personality');
      await repo.updateCharacter(updated);

      final result = await repo.getCharacterById('char-1');
      expect(result!.name, equals('New Name'));
      expect(result.personality, equals('Updated personality'));
    });

    test('updates alternateGreetings', () async {
      final char = buildCharacter(
        name: 'Test',
        id: 'char-1',
        alternateGreetings: ['Hello'],
      );
      await repo.createCharacter(char);

      final updated = char.copyWith(alternateGreetings: ['Hi!', 'Hey!']);
      await repo.updateCharacter(updated);

      final result = await repo.getCharacterById('char-1');
      expect(result!.alternateGreetings, hasLength(2));
      expect(result.alternateGreetings, containsAll(['Hi!', 'Hey!']));
    });

    test('updates systemPrompt', () async {
      final char = buildCharacter(name: 'Test', id: 'char-1');
      await repo.createCharacter(char);

      final updated = char.copyWith(systemPrompt: 'Custom prompt');
      await repo.updateCharacter(updated);

      final result = await repo.getCharacterById('char-1');
      expect(result!.systemPrompt, equals('Custom prompt'));
    });
  });

  group('CharacterRepository deleteCharacter', () {
    test('removes character', () async {
      final char = buildCharacter(name: 'Delete Me', id: 'char-1');
      await repo.createCharacter(char);

      await repo.deleteCharacter('char-1');

      final characters = await repo.getAllCharacters();
      expect(characters, isEmpty);
    });

    test('removes character embeddings', () async {
      final char = buildCharacter(name: 'Test', id: 'char-1');
      await repo.createCharacter(char);
      repo.addEmbedding('char-1', 'msg-1', 'Memory 1');
      repo.addEmbedding('char-1', 'msg-2', 'Memory 2');

      await repo.deleteCharacter('char-1');

      expect(repo.getEmbeddingCount('char-1'), equals(0));
    });

    test('does not affect other characters', () async {
      final char1 = buildCharacter(name: 'Keep', id: 'char-1');
      final char2 = buildCharacter(name: 'Delete', id: 'char-2');
      await repo.createCharacter(char1);
      await repo.createCharacter(char2);

      await repo.deleteCharacter('char-2');

      final characters = await repo.getAllCharacters();
      expect(characters, hasLength(1));
      expect(characters.first.name, equals('Keep'));
    });
  });

  group('CharacterRepository deleteEmbeddingsForMessages', () {
    test('removes specific message embeddings', () async {
      final char = buildCharacter(name: 'Test', id: 'char-1');
      await repo.createCharacter(char);
      repo.addEmbedding('char-1', 'msg-1', 'Memory 1');
      repo.addEmbedding('char-1', 'msg-2', 'Memory 2');
      repo.addEmbedding('char-1', 'msg-3', 'Memory 3');

      await repo.deleteEmbeddingsForMessages('char-1', ['msg-1', 'msg-3']);

      expect(repo.getEmbeddingCount('char-1'), equals(1));
    });

    test('handles empty messageIds list', () async {
      final char = buildCharacter(name: 'Test', id: 'char-1');
      await repo.createCharacter(char);
      repo.addEmbedding('char-1', 'msg-1', 'Memory 1');

      await repo.deleteEmbeddingsForMessages('char-1', []);

      expect(repo.getEmbeddingCount('char-1'), equals(1));
    });
  });

  group('CharacterRepository lastUpdated', () {
    test('tracks last updated character', () async {
      final char = buildCharacter(name: 'Test', id: 'char-1');
      await repo.createCharacter(char);

      final updated = char.copyWith(name: 'Updated');
      await repo.updateCharacter(updated);

      expect(repo.lastUpdated, isNotNull);
      expect(repo.lastUpdated!.name, equals('Updated'));
    });

    test('lastUpdated is null when no updates', () async {
      expect(repo.lastUpdated, isNull);
    });
  });
}
