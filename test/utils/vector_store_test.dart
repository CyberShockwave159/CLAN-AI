import 'package:clan_ai/core/utils/hash_embedding.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/fake_vector_store.dart';

void main() {
  late FakeVectorStore store;

  setUp(() {
    store = FakeVectorStore();
  });

  group('VectorStore searchSimilar with threadIds', () {
    test('returns top-K most similar memories for specified threads', () async {
      for (int i = 0; i < 5; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          threadId: 'thread-1',
          messageId: 'msg-$i',
          content: 'Memory $i',
          vector: HashEmbedding.embed('Memory $i content'),
        );
      }

      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('Memory 3'),
        threadIds: ['thread-1'],
        topK: 3,
      );

      expect(results, hasLength(3));
    });

    test('returns empty list when no memories exist', () async {
      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('test'),
        threadIds: [],
        topK: 3,
      );
      expect(results, isEmpty);
    });

    test('results are sorted by similarity descending', () async {
      for (int i = 0; i < 5; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          threadId: 'thread-1',
          messageId: 'msg-$i',
          content: 'Memory $i',
          vector: HashEmbedding.embed('Memory $i content'),
        );
      }

      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('Memory 3 content'),
        threadIds: ['thread-1'],
        topK: 5,
      );

      for (int i = 1; i < results.length; i++) {
        expect(
          (results[i - 1]['similarity'] as double) >= (results[i]['similarity'] as double),
          isTrue,
        );
      }
    });

    test('results scoped to specified threadIds only', () async {
      for (int i = 0; i < 3; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          threadId: 'thread-1',
          messageId: 'msg-$i',
          content: 'Thread 1 memory $i',
          vector: HashEmbedding.embed('Thread 1 memory $i'),
        );
        await store.saveEmbedding(
          characterId: 'char-1',
          threadId: 'thread-2',
          messageId: 'msg-t2-$i',
          content: 'Thread 2 memory $i',
          vector: HashEmbedding.embed('Thread 2 memory $i'),
        );
      }

      // Search only thread-1
      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('Thread 1'),
        threadIds: ['thread-1'],
        topK: 10,
      );

      expect(results.every((r) => r['content'].toString().startsWith('Thread 1')), isTrue);
      expect(results.every((r) => !r['content'].toString().startsWith('Thread 2')), isTrue);

      // Search only thread-2
      final results2 = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('Thread 2'),
        threadIds: ['thread-2'],
        topK: 10,
      );

      expect(results2.every((r) => r['content'].toString().startsWith('Thread 2')), isTrue);
      expect(results2.every((r) => !r['content'].toString().startsWith('Thread 1')), isTrue);
    });

    test('searches across multiple threadIds', () async {
      for (int i = 0; i < 3; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          threadId: 'thread-1',
          messageId: 'msg-$i',
          content: 'Thread 1 memory $i',
          vector: HashEmbedding.embed('Thread 1 memory $i'),
        );
        await store.saveEmbedding(
          characterId: 'char-1',
          threadId: 'thread-2',
          messageId: 'msg-t2-$i',
          content: 'Thread 2 memory $i',
          vector: HashEmbedding.embed('Thread 2 memory $i'),
        );
      }

      // Search across both threads
      final results = await store.searchSimilar(
        characterId: 'char-1',
        queryVector: HashEmbedding.embed('memory'),
        threadIds: ['thread-1', 'thread-2'],
        topK: 10,
      );

      expect(results, hasLength(6));
    });
  });

  group('VectorStore deleteCharacterEmbeddings', () {
    test('removes all embeddings for character', () async {
      for (int i = 0; i < 5; i++) {
        await store.saveEmbedding(
          characterId: 'char-1',
          threadId: 'thread-1',
          messageId: 'msg-$i',
          content: 'Memory $i',
          vector: HashEmbedding.embed('Memory $i'),
        );
      }

      await store.deleteCharacterEmbeddings('char-1');
      expect(store.allEmbeddings['char-1'], isEmpty);
    });

    test('does not affect other characters', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-2',
        threadId: 'thread-1',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );

      await store.deleteCharacterEmbeddings('char-1');

      expect(store.allEmbeddings['char-1'], isEmpty);
      expect(store.allEmbeddings['char-2']?['thread-1'], hasLength(1));
    });
  });

  group('VectorStore deleteEmbeddingsForMessages', () {
    test('removes specific message embeddings', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-3',
        content: 'Memory 3',
        vector: HashEmbedding.embed('Memory 3'),
      );

      await store.deleteEmbeddingsForMessages(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageIds: ['msg-1', 'msg-3'],
      );

      final remaining = store.allEmbeddings['char-1']?['thread-1'] ?? [];
      expect(remaining, hasLength(1));
      expect(remaining[0]['message_id'], equals('msg-2'));
    });

    test('handles empty messageIds list', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );

      await store.deleteEmbeddingsForMessages(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageIds: [],
      );

      expect(store.allEmbeddings['char-1']?['thread-1'], hasLength(1));
    });

    test('handles non-existent messageIds gracefully', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );

      await store.deleteEmbeddingsForMessages(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageIds: ['msg-999'],
      );

      expect(store.allEmbeddings['char-1']?['thread-1'], hasLength(1));
    });

    test('only deletes from specified thread', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-2',
        messageId: 'msg-1',
        content: 'Memory 1 copy',
        vector: HashEmbedding.embed('Memory 1 copy'),
      );

      await store.deleteEmbeddingsForMessages(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageIds: ['msg-1'],
      );

      expect(store.allEmbeddings['char-1']?['thread-1'], isEmpty);
      expect(store.allEmbeddings['char-1']?['thread-2'], hasLength(1));
    });
  });

  group('VectorStore getEmbeddingCount', () {
    test('returns correct count', () async {
      expect(await store.getEmbeddingCount('char-1'), equals(0));

      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );

      expect(await store.getEmbeddingCount('char-1'), equals(2));
    });

    test('counts across all threads for character', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-2',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );

      expect(await store.getEmbeddingCount('char-1'), equals(2));
    });

    test('returns 0 for non-existent character', () async {
      expect(await store.getEmbeddingCount('non-existent'), equals(0));
    });
  });

  group('VectorStore getAllMemories', () {
    test('returns all memories for character', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-2',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );

      final memories = await store.getAllMemories('char-1');
      expect(memories, hasLength(2));
    });
  });

  group('VectorStore deleteEmbedding', () {
    test('removes single embedding by id', () async {
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-1',
        content: 'Memory 1',
        vector: HashEmbedding.embed('Memory 1'),
      );
      await store.saveEmbedding(
        characterId: 'char-1',
        threadId: 'thread-1',
        messageId: 'msg-2',
        content: 'Memory 2',
        vector: HashEmbedding.embed('Memory 2'),
      );

      final embeddingId = store.allEmbeddings['char-1']?['thread-1']?[0]['id'] as String?;
      if (embeddingId != null) {
        await store.deleteEmbedding(embeddingId);
      }

      expect(store.allEmbeddings['char-1']?['thread-1'], hasLength(1));
    });
  });
}
