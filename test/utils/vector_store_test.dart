import 'package:clan_ai/core/utils/hash_embedding.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_vector_store.dart';

void main() {
  late FakeVectorStore store;

  setUp(() {
    store = FakeVectorStore();
  });

  group('VectorStore saveEmbedding', () {
    test('inserts embedding for character', () async {
      final vector = HashEmbedding.embed('Hello');
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Hello world',
        vector: vector,
      );

      expect(store.allEmbeddings['char-1'], isNotEmpty);
      expect(store.allEmbeddings['char-1']![0]['message_id'], equals('msg-1'));
      expect(store.allEmbeddings['char-1']![0]['content'], equals('Hello world'));
    });

    test('stores multiple embeddings for same character', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Message 1',
        vector: HashEmbedding.embed('Message 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-2',
        content: 'Message 2',
        vector: HashEmbedding.embed('Message 2'),
      );

      expect(store.allEmbeddings['char-1'], hasLength(2));
    });

    test('stores embeddings for different characters separately', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Character 1',
        vector: HashEmbedding.embed('Character 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-2',
        messageId: 'msg-2',
        content: 'Character 2',
        vector: HashEmbedding.embed('Character 2'),
      );

      expect(store.allEmbeddings['char-1'], hasLength(1));
      expect(store.allEmbeddings['char-2'], hasLength(1));
    });
  });

  group('VectorStore searchSimilar', () {
    test('returns top-K most similar memories', () async {
      for (int i = 0; i < 5; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          messageId: 'msg-$i',
          content: 'Memory $i',
          vector: HashEmbedding.embed('Memory $i content'),
        );
      }

      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('Memory 3'),
        topK: 3,
      );

      expect(results, hasLength(3));
    });

    test('returns empty list when no memories exist', () async {
      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('test'),
        topK: 3,
      );
      expect(results, isEmpty);
    });

    test('results are sorted by similarity descending', () async {
      for (int i = 0; i < 5; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          messageId: 'msg-$i',
          content: 'Memory $i',
          vector: HashEmbedding.embed('Memory $i content'),
        );
      }

      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('Memory 3 content'),
        topK: 5,
      );

      for (int i = 1; i < results.length; i++) {
        expect(
          (results[i - 1]['similarity'] as double) >= (results[i]['similarity'] as double),
          isTrue,
        );
      }
    });

    test('results scoped to character only', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Only char 1 memory',
        vector: HashEmbedding.embed('Only char 1 memory'),
      );
      await store.saveEmbedding(
        characterId: 'char-2',
        messageId: 'msg-2',
        content: 'Only char 2 memory',
        vector: HashEmbedding.embed('Only char 2 memory'),
      );

      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('anything'),
        topK: 10,
      );

      expect(results, hasLength(1));
      expect(results[0]['content'], equals('Only char 1 memory'));
    });

    test('results include content and message_id', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Test content',
        vector: HashEmbedding.embed('test'),
      );

      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('test'),
        topK: 1,
      );

      expect(results[0]['content'], equals('Test content'));
      expect(results[0]['message_id'], equals('msg-1'));
      expect(results[0]['similarity'], isNotNull);
    });
  });

  group('VectorStore deleteCharacterEmbeddings', () {
    test('removes all embeddings for character', () async {
      for (int i = 0; i < 5; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          messageId: 'msg-$i',
          content: 'Memory $i',
          vector: HashEmbedding.embed('Memory $i'),
        );
      }

      await store.deleteCharacterEmbeddings('char-1');
      expect(store.allEmbeddings['char-1'], isEmpty);
      expect(store.allEmbeddings.containsKey('char-1'), isFalse);
    });

    test('does not affect other characters', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-2',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );

      await store.deleteCharacterEmbeddings('char-1');

      expect(store.allEmbeddings['char-1'], isEmpty);
      expect(store.allEmbeddings['char-2'], hasLength(1));
    });
  });

  group('VectorStore deleteEmbeddingsForMessages', () {
    test('removes specific message embeddings', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-3',
        content: 'Memory 3',
        vector: HashEmbedding.embed('Memory 3'),
      );

      await store.deleteEmbeddingsForMessages(
        characterId: 'char-1',
        messageIds: ['msg-1', 'msg-3'],
      );

      final remaining = store.allEmbeddings['char-1'] ?? [];
      expect(remaining, hasLength(1));
      expect(remaining[0]['message_id'], equals('msg-2'));
    });

    test('handles empty messageIds list', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );

      await store.deleteEmbeddingsForMessages(
        characterId: 'char-1',
        messageIds: [],
      );

      expect(store.allEmbeddings['char-1'], hasLength(1));
    });

    test('handles non-existent messageIds gracefully', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );

      await store.deleteEmbeddingsForMessages(
        characterId: 'char-1',
        messageIds: ['msg-999'],
      );

      expect(store.allEmbeddings['char-1'], hasLength(1));
    });
  });

  group('VectorStore getEmbeddingCount', () {
    test('returns correct count', () async {
      expect(await store.getEmbeddingCount('char-1'), equals(0));

      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );

      expect(await store.getEmbeddingCount('char-1'), equals(1));
    });

    test('returns 0 for non-existent character', () async {
      expect(await store.getEmbeddingCount('non-existent'), equals(0));
    });
  });

  group('VectorStore clear', () {
    test('removes all embeddings', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-2',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );

      store.clear();
      expect(store.allEmbeddings, isEmpty);
    });
  });
}
