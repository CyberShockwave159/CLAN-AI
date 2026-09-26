import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/datasources/aprox_rag_client.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';

/// Notified whenever a character's appearance sheet is saved, so the owner can
/// mirror it into the A-PROX RAG store.
///
/// [appearance] is the new canonical text, or null when it was cleared.
typedef AppearanceSyncCallback = Future<void> Function(
  CharacterProfile character,
  String? appearance,
);

class CharacterRepository {
  final LocalDatabase _localDb;
  final VectorStore _vectorStore;

  /// Optional sink for mirroring the appearance sheet into A-PROX RAG. Set by
  /// the app so a character edit is reflected in server-side memory without this
  /// repository taking a dependency on the network stack.
  AppearanceSyncCallback? onAppearanceChanged;

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
        appearance: character.appearance ?? duplicate.appearance,
        identityPortraitData: character.identityPortraitData ?? duplicate.identityPortraitData,
        visualTheme: character.visualTheme,
      );
      await updateCharacter(merged);
      return merged;
    }

    await _localDb.insertCharacter(character);
    await _syncAppearance(character);
    return character;
  }

  Future<void> updateCharacter(CharacterProfile character) async {
    await _localDb.updateCharacter(character);
    await _syncAppearance(character);
  }

  /// Mirrors the appearance sheet into A-PROX RAG when one is configured.
  ///
  /// Best-effort by construction: the callback owns its own error handling, and
  /// a server that isn't A-PROX (or a timeout) must never block a character
  /// save. Uses a stable `source_uri`, so A-PROX replaces the previous chunks
  /// rather than accumulating a new copy on every keystroke-save.
  Future<void> _syncAppearance(CharacterProfile character) async {
    final sync = onAppearanceChanged;
    if (sync == null) return;
    try {
      await sync(character, character.appearance);
    } catch (_) {
      // Appearance mirroring is an enhancement; never fail a save over it.
    }
  }

  /// Collection holding a character's appearance sheet on the A-PROX server.
  static String visualCollection(String characterId) =>
      AproxRagClient.visualCollection(characterId);

  Future<void> deleteCharacter(String id) async {
    await _localDb.deleteCharacter(id);
    await _vectorStore.deleteCharacterEmbeddings(id);
  }

  Future<void> deleteEmbeddingsForMessages({
    required String characterId,
    required String threadId,
    required List<String> messageIds,
  }) async {
    await _vectorStore.deleteEmbeddingsForMessages(
      characterId: characterId,
      threadId: threadId,
      messageIds: messageIds,
    );
  }
}
