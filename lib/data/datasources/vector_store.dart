import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';

/// Singleton that manages the vector store SQLite database.
class VectorStoreDatabase {
  static final VectorStoreDatabase instance = VectorStoreDatabase._init();
  Database? _database;

  static const String _dbFileName = 'clan_ai_vectors.db';

  VectorStoreDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    // SQLite FFI factory is initialized once in main.dart
    // This check is a defensive guard in case _initDB is called before main()

    String path;
    if (kIsWeb) {
      path = _dbFileName;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      path = join(dbFolder.path, _dbFileName);
    }

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE embeddings (
        id TEXT PRIMARY KEY,
        character_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        content TEXT NOT NULL,
        vector TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (character_id) REFERENCES embeddings (character_id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_embeddings_character ON embeddings (character_id)');
  }
}

/// SQLite-backed vector similarity store for roleplay character memory.
///
/// Each character has its own namespace (character_id). Queries are strictly
/// scoped to a single character — no cross-character memory leakage.
class VectorStore {
  /// Save a single embedding for a character.
  Future<void> saveEmbedding({
    required String characterId,
    required String messageId,
    required String content,
    required List<double> vector,
  }) async {
    final db = await _getDb();
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final vectorJson = HashEmbedding.encodeVector(vector);

    await db.insert('embeddings', {
      'id': id,
      'character_id': characterId,
      'message_id': messageId,
      'content': content,
      'vector': vectorJson,
      'created_at': now,
    });
  }

  /// Save multiple embeddings in a single transaction.
  Future<void> batchSave({
    required String characterId,
    required List<Map<String, dynamic>> embeddings,
  }) async {
    final db = await _getDb();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final e in embeddings) {
        batch.insert('embeddings', {
          'id': e['id'] as String,
          'character_id': characterId,
          'message_id': e['message_id'] as String,
          'content': e['content'] as String,
          'vector': HashEmbedding.encodeVector(e['vector'] as List<double>),
          'created_at': e['created_at'] as String,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// Search for the top-K most similar memories for a character.
  ///
  /// Computes cosine similarity on the client side (Dart) for precision.
  /// SQL handles the character_id filter; Dart computes the similarity scores.
  ///
  /// [limit] bounds the number of recent embeddings loaded into memory before
  /// similarity scoring, preventing O(n) degradation for characters with
  /// large conversation histories. Defaults to 100 recent embeddings.
  Future<List<Map<String, dynamic>>> searchSimilar({
    required String characterId,
    required List<double> queryVector,
    int topK = defaultRagTopK,
    int limit = defaultRagLimit,
  }) async {
    final db = await _getDb();
    final results = await db.query(
      'embeddings',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    if (results.isEmpty) return [];

    // Compute cosine similarity for candidates, sort, and take top-K
    final scored = results.map((row) {
      final vector = HashEmbedding.decodeVector(row['vector'] as String);
      final similarity = HashEmbedding.cosineSimilarity(queryVector, vector);
      return {
        'id': row['id'] as String,
        'message_id': row['message_id'] as String,
        'content': row['content'] as String,
        'created_at': row['created_at'] as String,
        'similarity': similarity,
      };
    }).toList();

    scored.sort((a, b) => (b['similarity'] as double)
        .compareTo(a['similarity'] as double));

    return scored.take(topK).toList();
  }

  /// Delete all embeddings for a character.
  Future<void> deleteCharacterEmbeddings(String characterId) async {
    final db = await _getDb();
    await db.delete(
      'embeddings',
      where: 'character_id = ?',
      whereArgs: [characterId],
    );
  }

  /// Delete specific embeddings by message IDs within a character.
  Future<void> deleteEmbeddingsForMessages({
    required String characterId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    final db = await _getDb();
    final placeholders = messageIds.map((_) => '?').join(',');
    await db.delete(
      'embeddings',
      where: 'character_id = ? AND message_id IN ($placeholders)',
      whereArgs: [characterId, ...messageIds],
    );
  }

  /// Get total embedding count for a character.
  Future<int> getEmbeddingCount(String characterId) async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM embeddings WHERE character_id = ?',
      [characterId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<Database> _getDb() async {
    return VectorStoreDatabase.instance.database;
  }
}
