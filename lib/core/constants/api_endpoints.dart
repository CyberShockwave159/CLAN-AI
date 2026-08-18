/// API Endpoints for OpenAI-compatible and native llama.cpp servers.
class ApiEndpoints {
  // OpenAI compatible endpoints
  static const String chatCompletions = '/v1/chat/completions';
  static const String completions = '/v1/completions';
  static const String models = '/v1/models';

  // Native llama.cpp server endpoints
  static const String llamaHealth = '/health';
  static const String llamaProps = '/props';
  static const String llamaCompletion = '/completion';
  static const String llamaSlots = '/slots';
  static const String llamaDetokenize = '/detokenize';
  static const String llamaTokenize = '/tokenize';

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
