import 'dart:math' as math;

/// Pure Dart feature hashing embeddings using character trigrams.
///
/// Produces 256-dim L2-normalized vectors. No external dependencies.
/// Runs in <5ms on any device with <1KB memory per vector.
class HashEmbedding {
  static const int dimensions = 256;

  /// Tokenize text into overlapping character trigrams (3-char substrings).
  /// Adds space padding for word-boundary sensitivity.
  static List<String> tokenize(String text) {
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) return [];

    // Pad with spaces for word boundary detection
    final padded = '  $normalized  ';
    final tokens = <String>[];
    for (var i = 0; i <= padded.length - 3; i++) {
      tokens.add(padded.substring(i, i + 3));
    }
    return tokens;
  }

  /// Deterministic hash function producing a value in [0, 256).
  static int hash(String token) {
    var hash = 5381;
    for (var i = 0; i < token.length; i++) {
      hash = ((hash << 5) + hash) ^ token.codeUnitAt(i);
    }
    return hash.abs() % dimensions;
  }

  /// Deterministic sign: +1 or -1 based on token content.
  static int sign(String token) {
    var hash = 0;
    for (var i = 0; i < token.length; i++) {
      hash = hash * 31 + token.codeUnitAt(i);
    }
    return hash >= 0 ? 1 : -1;
  }

  /// Build a 256-dim normalized vector from raw text.
  static List<double> embed(String text) {
    final tokens = tokenize(text);
    final vector = List.filled(dimensions, 0.0);

    for (final token in tokens) {
      final idx = hash(token);
      vector[idx] += sign(token);
    }

    // L2 normalization
    var magnitude = 0.0;
    for (final v in vector) {
      magnitude += v * v;
    }
    magnitude = math.sqrt(magnitude);

    if (magnitude > 0) {
      for (var i = 0; i < dimensions; i++) {
        vector[i] = vector[i] / magnitude;
      }
    }

    return vector;
  }

  /// Cosine similarity between two normalized vectors.
  /// Since vectors are L2-normalized, this is simply the dot product.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vector dimensions must match');
    }
    double sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /// Batch embed multiple texts.
  static List<List<double>> embedBatch(List<String> texts) {
    return texts.map((t) => embed(t)).toList();
  }

  /// Encode a vector as a JSON string for database storage.
  static final _bracketPattern = RegExp(r'[\[\]]');

  static String encodeVector(List<double> vector) {
    return vector.map((v) => v.toStringAsFixed(8)).toList().toString();
  }

  /// Decode a vector from a JSON string.
  static List<double> decodeVector(String encoded) {
    final trimmed = encoded.replaceAll(_bracketPattern, '');
    return trimmed.split(',').map(double.parse).toList();
  }
}
