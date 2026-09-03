import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';

class CharacterRepository {
  final LocalDatabase _localDb;
  final VectorStore _vectorStore;

  CharacterRepository({LocalDatabase? localDb, VectorStore? vectorStore})
      : _localDb = localDb ?? LocalDatabase.instance,
        _vectorStore = vectorStore ?? VectorStore();

  // --- Character CRUD ---

  Future<List<CharacterProfile>> getAllCharacters() async {
    return await _localDb.getAllCharacters();
  }

  Future<CharacterProfile?> getCharacterById(String id) async {
    return await _localDb.getCharacterById(id);
  }

  Future<CharacterProfile> createCharacter(CharacterProfile character) async {
    // Check for duplicate names and merge memories if found
    final existing = await getAllCharacters();
    final existingByName = existing.where((c) =>
        c.name.toLowerCase().trim() == character.name.toLowerCase().trim() && c.id != character.id).toList();

    if (existingByName.isNotEmpty) {
      final duplicate = existingByName.first;
      // Keep the existing character (with its memories), but update fields from new one
      final merged = duplicate.copyWith(
        personality: character.personality.isNotEmpty ? character.personality : duplicate.personality,
        firstMessage: character.firstMessage.isNotEmpty ? character.firstMessage : duplicate.firstMessage,
        setting: character.setting ?? duplicate.setting,
        userPersona: character.userPersona ?? duplicate.userPersona,
        avatarData: character.avatarData ?? duplicate.avatarData,
        systemPrompt: character.systemPrompt ?? duplicate.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions ?? duplicate.postHistoryInstructions,
        alternateGreetings: character.alternateGreetings.isNotEmpty ? character.alternateGreetings : duplicate.alternateGreetings,
      );
      await updateCharacter(merged);
      return merged;
    }

    await _localDb.insertCharacter(character);
    return character;
  }

  Future<void> updateCharacter(CharacterProfile character) async {
    await _localDb.updateCharacter(character);
  }

  Future<void> deleteCharacter(String id) async {
    await _localDb.deleteCharacter(id);
    await _vectorStore.deleteCharacterEmbeddings(id);
  }

  Future<void> deleteEmbeddingsForMessages(String characterId, List<String> messageIds) async {
    await _vectorStore.deleteEmbeddingsForMessages(characterId: characterId, messageIds: messageIds);
  }
}
