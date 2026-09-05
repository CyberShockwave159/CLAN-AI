import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';

class FakeVectorStore extends VectorStore {
  final Map<String, List<Map<String, dynamic>>> _embeddings = {};

  Map<String, List<Map<String, dynamic>>> get allEmbeddings => _embeddings;

  @override
  Future<void> saveEmbedding({
    required String characterId,
    required String messageId,
    required String content,
    required List<double> vector,
  }) async {
    _embeddings.putIfAbsent(characterId, () => []);
    _embeddings[characterId]!.add({
      'id': messageId,
      'message_id': messageId,
      'content': content,
      'vector': HashEmbedding.encodeVector(vector),
    });
  }

  @override
  Future<List<Map<String, dynamic>>> searchSimilar({
    required String characterId,
    required List<double> queryVector,
    int topK = 3,
    int limit = 100,
  }) async {
    final charEmbeddings = _embeddings[characterId] ?? [];
    if (charEmbeddings.isEmpty) return [];

    final scored = charEmbeddings.map((row) {
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
    _embeddings[characterId] = [];
  }

  @override
  Future<void> deleteEmbeddingsForMessages({
    required String characterId,
    required List<String> messageIds,
  }) async {
    final list = _embeddings[characterId];
    if (list != null) {
      list.removeWhere((e) => messageIds.contains(e['id']));
    }
  }

  @override
  Future<void> deleteEmbedding(String embeddingId) async {
    for (final charList in _embeddings.values) {
      charList.removeWhere((e) => e['id'] == embeddingId);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAllMemories(String characterId) async {
    final charList = _embeddings[characterId] ?? [];
    return charList.map((e) {
      return {
        ...e,
        'similarity': 0.0,
      };
    }).toList();
  }

  @override
  Future<int> getEmbeddingCount(String characterId) async {
    return (_embeddings[characterId] ?? []).length;
  }

  void clear() {
    _embeddings.clear();
  }
}
