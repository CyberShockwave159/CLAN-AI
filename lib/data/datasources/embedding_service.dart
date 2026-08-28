import 'package:clan_ai/core/utils/hash_embedding.dart';

/// Embedding service for the RAG memory system.
///
/// Currently uses pure Dart hash-based embeddings (no external dependencies).
/// The service layer isolates the embedding implementation so it can be
/// swapped for TFLite or ONNX later without changing callers.
class EmbeddingService {
  /// Embed a single text string into a 256-dim normalized vector.
  static List<double> embed(String text) {
    return HashEmbedding.embed(text);
  }

  /// Embed multiple text strings into a list of vectors.
  static List<List<double>> embedBatch(List<String> texts) {
    return HashEmbedding.embedBatch(texts);
  }

  /// Encode a vector for database storage.
  static String encodeVector(List<double> vector) {
    return HashEmbedding.encodeVector(vector);
  }

  /// Decode a vector from database storage.
  static List<double> decodeVector(String encoded) {
    return HashEmbedding.decodeVector(encoded);
  }
}
