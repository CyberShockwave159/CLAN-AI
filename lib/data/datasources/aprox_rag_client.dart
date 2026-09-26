import 'dart:async';
import 'package:clan_ai/core/constants/api_endpoints.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:flutter/foundation.dart';

/// A single chunk returned by A-PROX's `/rag/query`.
class RagHit {
  final String content;
  final String sourceUri;
  final String collection;
  final double score;

  const RagHit({
    required this.content,
    required this.sourceUri,
    required this.collection,
    required this.score,
  });

  factory RagHit.fromMap(Map<String, dynamic> map) {
    return RagHit(
      content: map['content'] as String? ?? '',
      sourceUri: map['source_uri'] as String? ?? '',
      collection: map['collection'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Client for A-PROX's direct RAG store endpoints (`/rag/ingest`, `/rag/query`,
/// `/rag/collections/{name}/count`).
///
/// These bypass the LLM entirely, so A-PROX's RAG can act as CLAN-AI's roleplay
/// memory backend without paying a generation per write, and without A-PROX's
/// own `RAGIngestion` route hardcoding the shared `default` collection.
///
/// **Every method is best-effort.** Memory is an enhancement: a server that
/// isn't A-PROX, a 404 from an unpatched build, or a timeout must never fail a
/// reply. Failures are logged via [debugPrint] and reported as `null`/`0`.
class AproxRagClient {
  final ApiHttpClient _httpClient;

  AproxRagClient(this._httpClient);

  /// Collection holding a roleplay thread's conversation memories.
  ///
  /// Scoped per character *and* per thread on purpose. A-PROX searches every
  /// collection when no filter is supplied, so a shared namespace would let one
  /// character's memories (or the user's indexed documents) surface in another's
  /// roleplay.
  static String threadCollection({
    required String characterId,
    required String threadId,
  }) {
    return 'clan_${characterId}_$threadId';
  }

  /// Collection holding a character's canonical appearance sheet.
  static String visualCollection(String characterId) => 'clan_${characterId}_visual';

  /// Stable `source_uri` for a character's appearance sheet.
  ///
  /// Stable is the point: A-PROX deletes the previous chunks for a
  /// `(collection, source_uri)` pair before ingesting, so re-saving the sheet
  /// replaces it instead of accumulating near-duplicate versions.
  static String visualSourceUri(String characterId) => 'clan/$characterId/visual';

  /// Stable `source_uri` for one conversation turn.
  static String turnSourceUri({
    required String characterId,
    required String threadId,
    required String messageId,
  }) {
    return 'clan/$characterId/$threadId/$messageId';
  }

  /// Stores [content] in [collection], replacing any prior chunk with the same
  /// [sourceUri]. Returns the number of chunks written, or null on failure.
  Future<int?> ingest({
    required ServerProfile? connection,
    required String collection,
    required String content,
    required String sourceUri,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    final uri = _uriFor(connection, ApiEndpoints.ragIngest);
    if (uri == null) return null;

    try {
      final response = await _httpClient.post(
        uri,
        body: {
          'collection': collection,
          'source_uri': sourceUri,
          'content': trimmed,
        },
        apiKey: connection?.apiKey,
      );
      if (response is Map && response['chunks'] is num) {
        return (response['chunks'] as num).toInt();
      }
      return null;
    } catch (e) {
      _logFailure('ingest', e);
      return null;
    }
  }

  /// Hybrid-searches [collection] (or every collection when null).
  ///
  /// Only used for the appearance sheet — the conversation path retrieves via
  /// A-PROX's own `a-prox-rag` route so the model never sees raw citations twice.
  /// Returns null on failure.
  Future<List<RagHit>?> query({
    required ServerProfile? connection,
    required String query,
    String? collection,
    int topK = 3,
    double minScore = 0.0,
  }) async {
    if (query.trim().isEmpty) return null;

    final uri = _uriFor(connection, ApiEndpoints.ragQuery);
    if (uri == null) return null;

    try {
      final response = await _httpClient.post(
        uri,
        body: {
          'query': query.trim(),
          // Null-aware element: omitted entirely when no collection filter is
          // given, which is what makes A-PROX search every collection.
          'collection': ?collection,
          'top_k': topK,
          'min_score': minScore,
        },
        apiKey: connection?.apiKey,
      );
      if (response is! Map) return null;
      final results = response['results'];
      if (results is! List) return const [];
      return results
          .whereType<Map>()
          .map((e) => RagHit.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      _logFailure('query', e);
      return null;
    }
  }

  /// Number of chunks stored in [collection]. Returns 0 when the collection is
  /// absent, which is how callers detect that a thread needs backfilling.
  Future<int> collectionCount({
    required ServerProfile? connection,
    required String collection,
  }) async {
    final uri = _uriFor(
      connection,
      '${ApiEndpoints.ragCollectionCount}/${Uri.encodeComponent(collection)}/count',
    );
    if (uri == null) return 0;

    try {
      final response = await _httpClient.get(uri, apiKey: connection?.apiKey);
      if (response is Map && response['chunks'] is num) {
        return (response['chunks'] as num).toInt();
      }
      return 0;
    } catch (e) {
      _logFailure('collectionCount', e);
      return 0;
    }
  }

  /// True when [connection] advertises the A-PROX RAG capability. Checked before
  /// any call so the app never fires requests at a plain llama.cpp server.
  static bool isAvailable(ServerProfile? connection) => connection?.isAprox ?? false;

  Uri? _uriFor(ServerProfile? connection, String path) {
    if (connection == null || connection.baseUrl.trim().isEmpty) return null;
    return ApiEndpoints.buildUri(connection.baseUrl, path);
  }

  void _logFailure(String operation, Object error) {
    debugPrint('[AproxRagClient] $operation failed (ignored): $error');
  }
}
