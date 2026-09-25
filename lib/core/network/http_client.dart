import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/network/http_transport.dart';
import 'package:clan_ai/core/network/streamed_api_response.dart';

/// Network HTTP client configured with timeouts, error mapping, and streaming support.
class ApiHttpClient {
  final http.Client _client;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  ApiHttpClient({
    http.Client? client,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 60),
  }) : _client = client ?? createHttpClient(connectTimeout);

  Map<String, String> _buildHeaders({String? apiKey, Map<String, String>? extraHeaders}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
    };
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  /// Sends a GET request and parses the JSON response.
  Future<dynamic> get(
    Uri uri, {
    String? apiKey,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final response = await _client
          .get(
            uri,
            headers: _buildHeaders(apiKey: apiKey, extraHeaders: extraHeaders),
          )
          .timeout(connectTimeout);

      return _handleResponse(response, uri);
    } on SocketException catch (e) {
      throw HostUnreachableException(host: uri.host, details: e.message);
    } on TimeoutException {
      throw NetworkException(
        message: 'Connection timed out while connecting to ${uri.host}:${uri.port}',
        details: 'The server did not respond within ${connectTimeout.inSeconds} seconds.',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw NetworkException(message: 'Request failed', details: e.toString());
    }
  }

  /// Sends a POST request with a JSON payload and parses the JSON response.
  Future<dynamic> post(
    Uri uri, {
    required Map<String, dynamic> body,
    String? apiKey,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final response = await _client
          .post(
            uri,
            headers: _buildHeaders(apiKey: apiKey, extraHeaders: extraHeaders),
            body: jsonEncode(body),
          )
          .timeout(receiveTimeout);

      return _handleResponse(response, uri);
    } on SocketException catch (e) {
      throw HostUnreachableException(host: uri.host, details: e.message);
    } on TimeoutException {
      throw NetworkException(
        message: 'Request timed out for ${uri.host}',
        details: 'No response received within ${receiveTimeout.inSeconds} seconds.',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw NetworkException(message: 'Request failed', details: e.toString());
    }
  }

  /// Sends a streaming POST request returning a [StreamedApiResponse].
  ///
  /// The response resolves once the response *headers* arrive, so the guard
  /// below uses [receiveTimeout], not [connectTimeout]: the TCP/TLS connect
  /// phase is already hard-bounded by the underlying transport
  /// ([createHttpClient] on io; the browser fetch on web), while waiting for
  /// the server's response — which on a busy or slow server includes slot
  /// queueing and prompt prefill before the first byte — is part of receiving.
  /// Bounding the header wait with the tight 10s connect budget made remote
  /// servers with a healthy link (low ping, prior exchanges fine) falsely
  /// report a "connection" failure whenever first-token time crept past 10
  /// seconds.
  Future<StreamedApiResponse> postStream(
    Uri uri, {
    required Map<String, dynamic> body,
    String? apiKey,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(_buildHeaders(apiKey: apiKey, extraHeaders: extraHeaders))
        ..body = jsonEncode(body);

      final streamedResponse = await streamSend(_client, request).timeout(receiveTimeout);

      if (streamedResponse.statusCode >= 400) {
        // bytesToString() already drains the response stream to completion
        // (releasing the connection) before we throw. Guard the read anyway:
        // if it fails, still surface the HTTP status instead of masking it
        // with a body-read error.
        String errBody = '';
        try {
          errBody = await streamedResponse.bodyToString();
        } catch (_) {}
        throwForStatusCode(streamedResponse.statusCode, errBody, uri);
      }

      return streamedResponse;
    } on SocketException catch (e) {
      throw HostUnreachableException(host: uri.host, details: e.message);
    } on TimeoutException {
      throw NetworkException(
        message: 'Streaming request timed out for ${uri.host}',
        details: 'No response received within ${receiveTimeout.inSeconds} seconds.',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw NetworkException(message: 'Stream initiation failed', details: e.toString());
    }
  }

  dynamic _handleResponse(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (e) {
        return response.body;
      }
    }

    throwForStatusCode(response.statusCode, response.body, uri);
  }

  void throwForStatusCode(int statusCode, String body, Uri uri) {
    String errorMsg = 'HTTP $statusCode error from ${uri.host}';
    final trimmed = body.trim();
    if (trimmed.isNotEmpty) {
      String? extracted;
      try {
        extracted = _extractErrorMessage(jsonDecode(trimmed));
      } catch (_) {
        // Not JSON — a plain-text body is already human-readable.
        extracted = trimmed;
      }
      if (extracted != null && extracted.isNotEmpty) {
        errorMsg = extracted;
      }
      // Recognized JSON without a usable message keeps the generic HTTP text
      // rather than dumping a raw JSON blob at the user.
    }

    if (statusCode == 400 &&
        (errorMsg.toLowerCase().contains('context') || errorMsg.toLowerCase().contains('exceed'))) {
      throw ContextLimitExceededException(message: errorMsg, details: 'HTTP $statusCode');
    }
    if (statusCode == 500 &&
        (errorMsg.toLowerCase().contains('memory') || errorMsg.toLowerCase().contains('slot'))) {
      throw ServerOOMException(message: errorMsg, details: 'HTTP $statusCode');
    }

    throw AppException(
      message: errorMsg,
      statusCode: statusCode,
      details: 'Endpoint: ${uri.path}',
    );
  }

  /// Extracts a human-readable message from the common API error shapes:
  /// `{"error": "..."}`, `{"error": {"message": "..."}}`, `{"message": ...}`,
  /// `{"detail": ...}` (FastAPI/vLLM), nested variants, and lists of errors.
  ///
  /// Returns null when the shape is recognized as JSON but contains no message.
  static String? _extractErrorMessage(dynamic decoded, [int depth = 0]) {
    if (depth > 4) return null;
    if (decoded is String) {
      final text = decoded.trim();
      return text.isEmpty ? null : text;
    }
    if (decoded is Map) {
      for (final key in _messageKeys) {
        if (decoded.containsKey(key)) {
          final extracted = _extractErrorMessage(decoded[key], depth + 1);
          if (extracted != null) return extracted;
        }
      }
      return null;
    }
    if (decoded is List) {
      for (final item in decoded) {
        final extracted = _extractErrorMessage(item, depth + 1);
        if (extracted != null) return extracted;
      }
      return null;
    }
    return null;
  }

  static const List<String> _messageKeys = ['message', 'detail', 'error', 'msg', 'reason'];

  void close() {
    _client.close();
  }
}
