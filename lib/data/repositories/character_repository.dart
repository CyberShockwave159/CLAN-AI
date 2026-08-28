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

  Future<void> deleteCharacterEmbeddings(String characterId) async {
    await _vectorStore.deleteCharacterEmbeddings(characterId);
  }

  Future<void> deleteEmbeddingsForMessages(String characterId, List<String> messageIds) async {
    await _vectorStore.deleteEmbeddingsForMessages(characterId: characterId, messageIds: messageIds);
  }
}
