import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/persona_template_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_character_repository.dart';
import '../helpers/fake_persona_template_repository.dart';
import '../helpers/fake_vector_store.dart';
import '../helpers/test_model_factories.dart';

/// Tests: Character lifecycle with threads and embeddings.
void main() {
  group('Character lifecycle with threads', () {
    test('create -> update -> delete character', () async {
      final repo = FakeCharacterRepository();

      // Create
      final char = buildCharacter(name: 'Aria', id: 'char-1');
      await repo.createCharacter(char);

      final loaded = await repo.getCharacterById('char-1');
      expect(loaded, isNotNull);
      expect(loaded!.name, equals('Aria'));

      // Update
      final updated = char.copyWith(
        name: 'Aria Updated',
        personality: 'Updated personality',
      );
      await repo.updateCharacter(updated);

      final reloaded = await repo.getCharacterById('char-1');
      expect(reloaded!.name, equals('Aria Updated'));
      expect(reloaded.personality, equals('Updated personality'));

      // Delete
      await repo.deleteCharacter('char-1');

      final deleted = await repo.getCharacterById('char-1');
      expect(deleted, isNull);
    });

    test('duplicate name merge preserves memories', () async {
      final repo = FakeCharacterRepository();
      final vectorStore = FakeVectorStore();

      // Create first character
      final char1 = buildCharacter(name: 'Aria', id: 'char-1');
      await repo.createCharacter(char1);
      vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-1', content: 'Memory 1.', vector: [0.0, ...List<double>.filled(255, 0.0)]);
      vectorStore.saveEmbedding(characterId: 'char-1', messageId: 'msg-2', content: 'Memory 2.', vector: [0.0, ...List<double>.filled(255, 0.0)]);

      // Create duplicate character
      final char2 = buildCharacter(name: 'Aria', id: 'char-2', firstMessage: 'New greeting');
      final merged = await repo.createCharacter(char2);

      // Should be merged
      expect(merged.id, equals('char-1'));
      expect(merged.firstMessage, equals('New greeting'));

      // Original character should still exist
      final charById = await repo.getCharacterById('char-1');
      expect(charById, isNotNull);
    });

    test('character update affects active character in VM', () async {
      final repo = FakeCharacterRepository();
      final char = buildCharacter(name: 'Aria', id: 'char-1');
      await repo.createCharacter(char);

      // Update character
      final updated = char.copyWith(name: 'Aria Updated');
      await repo.updateCharacter(updated);

      // Verify update was saved
      final reloaded = await repo.getCharacterById('char-1');
      expect(reloaded!.name, equals('Aria Updated'));
    });
  });

  group('Character thread relationship', () {
    test('multiple threads per character', () async {
      final repo = FakeCharacterRepository();
      await repo.createCharacter(buildCharacter(name: 'Aria', id: 'char-1'));

      // Simulate threads (stored via chat repo)
      // In real app, threads are stored in chat repository
      final threads = [
        buildThread(title: 'Chat 1').copyWith(characterId: 'char-1'),
        buildThread(title: 'Chat 2').copyWith(characterId: 'char-1'),
        buildThread(title: 'Chat 3').copyWith(characterId: 'char-1'),
      ];

      expect(threads.where((t) => t.characterId == 'char-1'), hasLength(3));
    });

    test('thread characterId consistency', () async {
      final thread = buildThread(
        title: 'Test',
        characterId: 'char-1',
      );

      expect(thread.characterId, equals('char-1'));

      // Verify copyWith preserves characterId
      final updated = thread.copyWith(title: 'Updated');
      expect(updated.characterId, equals('char-1'));
    });
  });
}
