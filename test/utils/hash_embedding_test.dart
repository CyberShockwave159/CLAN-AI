import 'package:clan_ai/core/utils/hash_embedding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HashEmbedding embed', () {
    test('produces deterministic vector for same input', () {
      final v1 = HashEmbedding.embed('Hello world');
      final v2 = HashEmbedding.embed('Hello world');
      expect(v1, equals(v2));
    });

    test('produces different vectors for different input', () {
      final v1 = HashEmbedding.embed('Hello world');
      final v2 = HashEmbedding.embed('Goodbye world');
      expect(v1, isNot(equals(v2)));
    });

    test('produces vector of correct dimension', () {
      final vector = HashEmbedding.embed('test');
      expect(vector, hasLength(256));
    });

    test('handles empty string', () {
      final vector = HashEmbedding.embed('');
      expect(vector, hasLength(256));
    });

    test('handles unicode characters', () {
      final vector = HashEmbedding.embed('こんにちは 世界');
      expect(vector, hasLength(256));
    });

    test('handles long text', () {
      final longText = 'The quick brown fox jumps over the lazy dog. ' * 100;
      final vector = HashEmbedding.embed(longText);
      expect(vector, hasLength(256));
    });
  });

  group('HashEmbedding cosineSimilarity', () {
    test('returns 1.0 for identical vectors', () {
      final vector = HashEmbedding.embed('Hello');
      final similarity = HashEmbedding.cosineSimilarity(vector, vector);
      expect(similarity, closeTo(1.0, 0.001));
    });

    test('returns positive similarity for similar text', () {
      final v1 = HashEmbedding.embed('The cat sat on the mat');
      final v2 = HashEmbedding.embed('The cat sat on the hat');
      final similarity = HashEmbedding.cosineSimilarity(v1, v2);
      expect(similarity, greaterThan(0.0));
    });

    test('returns lower similarity for different text', () {
      final v1 = HashEmbedding.embed('The cat sat on the mat');
      final v2 = HashEmbedding.embed('The dog played in the park');
      final similarity = HashEmbedding.cosineSimilarity(v1, v2);
      expect(similarity, lessThan(
        HashEmbedding.cosineSimilarity(
          HashEmbedding.embed('The cat sat on the mat'),
          HashEmbedding.embed('The cat sat on the hat'),
        ),
      ));
    });

    test('handles zero vector gracefully', () {
      final vector = HashEmbedding.embed('test');
      final zeroVector = List<double>.filled(256, 0.0);
      final similarity = HashEmbedding.cosineSimilarity(vector, zeroVector);
      expect(similarity, equals(0.0));
    });
  });

  group('HashEmbedding encodeVector/decodeVector', () {
    test('roundtrip preserves vector', () {
      final original = HashEmbedding.embed('Hello world');
      final encoded = HashEmbedding.encodeVector(original);
      final decoded = HashEmbedding.decodeVector(encoded);

      expect(decoded, equals(original));
    });

    test('encode produces non-empty string', () {
      final vector = HashEmbedding.embed('test');
      final encoded = HashEmbedding.encodeVector(vector);
      expect(encoded.isNotEmpty, isTrue);
    });

    test('decode accepts encoded string', () {
      final vector = HashEmbedding.embed('test');
      final encoded = HashEmbedding.encodeVector(vector);
      final decoded = HashEmbedding.decodeVector(encoded);
      expect(decoded, hasLength(256));
    });
  });
}
