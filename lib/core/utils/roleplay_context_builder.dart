import 'package:clan_ai/core/utils/roleplay_prompt_formatter.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';

/// Orchestrates the RAG pipeline: embed user input → search character memory →
/// inject top-3 relevant memories into the system prompt.
///
/// This is called before each message send in roleplay mode.
class RoleplayContextBuilder {
  final VectorStore _vectorStore;

  RoleplayContextBuilder({VectorStore? vectorStore})
      : _vectorStore = vectorStore ?? VectorStore();

  /// Build the full roleplay context for a character and user input.
  Future<RoleplayContext> build({
    required String characterId,
    required String characterName,
    required String personality,
    String? setting,
    String? userPersona,
    String? characterSystemPrompt,
    String? postHistoryInstructions,
    required String userInput,
  }) async {
    // 1. Embed the user input (kept for search but not stored in result)
    final queryVector = HashEmbedding.embed(userInput);

    // 2. Search for relevant memories (strictly scoped to characterId)
    final memories = await _vectorStore.searchSimilar(
      characterId: characterId,
      queryVector: queryVector,
      topK: 3,
    );

    // 3. Extract content strings
    final memoryTexts = memories
        .map((m) => m['content'] as String)
        .toList();

    // 4. Build system prompt with retrieved memories and character overrides
    final systemPrompt = RoleplayPromptFormatter.buildSystemPrompt(
      characterName: characterName,
      personality: personality,
      setting: setting,
      userPersona: userPersona,
      retrievedMemories: memoryTexts,
      characterSystemPrompt: characterSystemPrompt,
      postHistoryInstructions: postHistoryInstructions,
    );

    return RoleplayContext(
      systemPrompt: systemPrompt,
      memories: memoryTexts,
    );
  }
}

/// The result of a RAG context build.
class RoleplayContext {
  final String systemPrompt;
  final List<String> memories;

  RoleplayContext({
    required this.systemPrompt,
    required this.memories,
  });
}
