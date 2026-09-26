/// API Endpoints for OpenAI-compatible servers.
class ApiEndpoints {
  // OpenAI compatible endpoints
  static const String chatCompletions = '/v1/chat/completions';
  static const String completions = '/v1/completions';
  static const String models = '/v1/models';

  // llama.cpp health/props endpoints — used only for connectivity probing
  static const String llamaHealth = '/health';
  static const String llamaProps = '/props';

  // A-PROX direct RAG store access. These bypass the LLM entirely, so A-PROX's
  // RAG can be used as a memory backend (see AproxRagClient). Absent on plain
  // llama.cpp / OpenAI backends — every call is capability-gated and
  // best-effort.
  static const String ragIngest = '/rag/ingest';
  static const String ragQuery = '/rag/query';
  static const String ragCollectionCount = '/rag/collections';

  /// Normalizes and cleans a base URL string.
  /// Removes trailing slashes and ensures standard protocol.
  static String normalizeBaseUrl(String rawUrl) {
    String url = rawUrl.trim();
    if (url.isEmpty) return 'http://localhost:8080';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Builds a complete URL given a base URL and an endpoint path.
  static Uri buildUri(String baseUrl, String endpointPath, [Map<String, dynamic>? queryParams]) {
    final cleanBase = normalizeBaseUrl(baseUrl);
    final uri = Uri.parse('$cleanBase$endpointPath');
    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())));
    }
    return uri;
  }
}
