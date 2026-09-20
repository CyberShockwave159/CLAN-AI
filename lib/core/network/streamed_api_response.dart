import 'dart:convert';

/// A streaming HTTP response with the status code and the response body bytes.
///
/// The original code consumed `http.StreamedResponse` directly. That type is
/// backed by an `IOClient`/`BrowserClient` depending on platform; this thin
/// wrapper lets the io and web transports (`http_transport_io` /
/// `http_transport_web`) return a platform-neutral value. The `.stream` member
/// has the same shape as `http.StreamedResponse.stream`, so callers
/// (`LlamaApiService`, `SseClient`) are unaware of the swap.
class StreamedApiResponse {
  final int statusCode;
  final Stream<List<int>> stream;

  const StreamedApiResponse(this.statusCode, this.stream);

  /// Drains the body to a string (used to surface error payloads).
  Future<String> bodyToString() async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}