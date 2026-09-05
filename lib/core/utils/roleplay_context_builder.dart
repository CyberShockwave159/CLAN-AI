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
  /// 
  /// [ragTopK] controls how many memories to retrieve (1-10). Defaults to 3.
  /// [ragMinScore] filters memories below this similarity threshold (0.0-1.0). Defaults to 0.0.
  Future<RoleplayContext> build({
    required String characterId,
    required String characterName,
    required String personality,
    String? setting,
    String? userPersona,
    String? characterSystemPrompt,
    String? postHistoryInstructions,
    required String userInput,
    int ragTopK = 3,
    double ragMinScore = 0.0,
  }) async {
    // 1. Embed the user input (kept for search but not stored in result)
    final queryVector = HashEmbedding.embed(userInput);

    // 2. Search for relevant memories (strictly scoped to characterId)
    final memories = await _vectorStore.searchSimilar(
      characterId: characterId,
      queryVector: queryVector,
      topK: ragTopK,
    );

    // 3. Filter by minimum similarity score
    final filteredMemories = memories
        .where((m) => (m['similarity'] as double) >= ragMinScore)
        .map((m) => m['content'] as String)
        .toList();

    // 4. Build system prompt with retrieved memories and character overrides
    final systemPrompt = RoleplayPromptFormatter.buildSystemPrompt(
      characterName: characterName,
      personality: personality,
      setting: setting,
      userPersona: userPersona,
      retrievedMemories: filteredMemories,
      characterSystemPrompt: characterSystemPrompt,
      postHistoryInstructions: postHistoryInstructions,
    );

    // Build full memory info for UI display (content + similarity score)
    final fullMemoryInfo = filteredMemories.map((content) {
      final matching = memories.where((m) => m['content'] == content).toList();
      return {
        'content': content,
        'similarity': matching.isNotEmpty ? (matching.first['similarity'] as double) : 0.0,
      };
    }).toList();

    return RoleplayContext(
      systemPrompt: systemPrompt,
      memories: filteredMemories,
      memoryInfo: fullMemoryInfo,
    );
  }
}

/// The result of a RAG context build.
class RoleplayContext {
  final String systemPrompt;
  final List<String> memories;
  final List<Map<String, dynamic>> memoryInfo;

  RoleplayContext({
    required this.systemPrompt,
    required this.memories,
    this.memoryInfo = const [],
  });
}
