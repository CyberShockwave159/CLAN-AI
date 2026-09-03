import 'dart:typed_data';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';

class FakeCharacterRepository extends CharacterRepository {
  final List<CharacterProfile> _characters = [];
  final Map<String, Map<String, List<String>>> _embeddings = {};
  CharacterProfile? _lastUpdated;

  CharacterProfile? get lastUpdated => _lastUpdated;
  List<CharacterProfile> get all => _characters;

  @override
  Future<List<CharacterProfile>> getAllCharacters() async => _characters.toList();

  @override
  Future<CharacterProfile?> getCharacterById(String id) async {
    return _characters.where((c) => c.id == id).firstOrNull;
  }

  @override
  Future<CharacterProfile> createCharacter(CharacterProfile character) async {
    final existingByName = _characters.where((c) =>
        c.name.toLowerCase().trim() == character.name.toLowerCase().trim() && c.id != character.id).toList();

    if (existingByName.isNotEmpty) {
      final duplicate = existingByName.first;
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

    _characters.add(character);
    _embeddings[character.id] = {};
    return character;
  }

  @override
  Future<void> updateCharacter(CharacterProfile character) async {
    final index = _characters.indexWhere((c) => c.id == character.id);
    if (index != -1) {
      _characters[index] = character;
    }
    _lastUpdated = character;
  }

  @override
  Future<void> deleteCharacter(String id) async {
    _characters.removeWhere((c) => c.id == id);
    _embeddings.remove(id);
  }

  @override
  Future<void> deleteEmbeddingsForMessages(String characterId, List<String> messageIds) async {
    final charEmbeddings = _embeddings[characterId];
    if (charEmbeddings != null) {
      for (final messageId in messageIds) {
        charEmbeddings.remove(messageId);
      }
    }
  }

  void addEmbedding(String characterId, String messageId, String content) {
    _embeddings.putIfAbsent(characterId, () => {});
    _embeddings[characterId]![messageId] = [content];
  }

  int getEmbeddingCount(String characterId) {
    return _embeddings[characterId]?.length ?? 0;
  }
}

extension<T> on Iterable<T> {
  T? get orNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
