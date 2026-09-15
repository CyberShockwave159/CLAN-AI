import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';

class FakeVectorStore extends VectorStore {
  final Map<String, Map<String, List<Map<String, dynamic>>>> _embeddings = {};

  Map<String, Map<String, List<Map<String, dynamic>>>> get allEmbeddings => _embeddings;

  @override
  Future<void> saveEmbedding({
    required String characterId,
    required String threadId,
    required String messageId,
    required String content,
    required List<double> vector,
  }) async {
    _embeddings.putIfAbsent(characterId, () => {});
    _embeddings[characterId]!.putIfAbsent(threadId, () => []);
    _embeddings[characterId]![threadId]!.add({
      'id': messageId,
      'message_id': messageId,
      'thread_id': threadId,
      'content': content,
      'vector': HashEmbedding.encodeVector(vector),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> searchSimilar({
    required String characterId,
    required List<double> queryVector,
    required List<String> threadIds,
    int topK = 3,
    int limit = 100,
  }) async {
    final charEmbeddings = _embeddings[characterId];
    if (charEmbeddings == null) return [];

    final allEntries = <Map<String, dynamic>>[];
    if (threadIds.isEmpty) {
      // Search all threads for this character
      allEntries.addAll(charEmbeddings.values.expand((e) => e));
    } else {
      // Search only specified threads
      for (final threadId in threadIds) {
        final threadEntries = charEmbeddings[threadId];
        if (threadEntries != null) {
          allEntries.addAll(threadEntries);
        }
      }
    }

    if (allEntries.isEmpty) return [];

    // Apply limit on recent entries
    final limited = allEntries.take(limit).toList();

    final scored = limited.map((row) {
      final vector = HashEmbedding.decodeVector(row['vector'] as String);
      final similarity = HashEmbedding.cosineSimilarity(queryVector, vector);
      return {
        ...row,
        'similarity': similarity,
      };
    }).toList();

    scored.sort((a, b) => (b['similarity'] as double)
        .compareTo(a['similarity'] as double));

    return scored.take(topK).toList();
  }

  @override
  Future<void> deleteCharacterEmbeddings(String characterId) async {
    _embeddings[characterId] = {};
  }

  @override
  Future<void> deleteEmbeddingsForMessages({
    required String characterId,
    required String threadId,
    required List<String> messageIds,
  }) async {
    final charEmbeddings = _embeddings[characterId];
    if (charEmbeddings != null) {
      final threadEntries = charEmbeddings[threadId];
      if (threadEntries != null) {
        threadEntries.removeWhere((e) => messageIds.contains(e['id']));
      }
    }
  }

  @override
  Future<void> deleteEmbedding(String embeddingId) async {
    for (final charList in _embeddings.values) {
      for (final threadList in charList.values) {
        threadList.removeWhere((e) => e['id'] == embeddingId);
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAllMemories(String characterId) async {
    final charEmbeddings = _embeddings[characterId];
    if (charEmbeddings == null) return [];
    return charEmbeddings.values.expand((e) => e).map((e) {
      return {
        ...e,
        'similarity': 0.0,
      };
    }).toList();
  }

  @override
  Future<int> getEmbeddingCount(String characterId) async {
    final charEmbeddings = _embeddings[characterId];
    if (charEmbeddings == null) return 0;
    int count = 0;
    for (final threadEntries in charEmbeddings.values) {
      count += threadEntries.length;
    }
    return count;
  }

  void clear() {
    _embeddings.clear();
  }
}
