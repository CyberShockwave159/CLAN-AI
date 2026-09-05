import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:clan_ai/core/errors/app_exception.dart';

/// Network HTTP client configured with timeouts, error mapping, and streaming support.
class ApiHttpClient {
  final http.Client _client;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  ApiHttpClient({
    http.Client? client,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

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

  /// Sends a streaming POST request returning an [http.StreamedResponse].
  Future<http.StreamedResponse> postStream(
    Uri uri, {
    required Map<String, dynamic> body,
    String? apiKey,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(_buildHeaders(apiKey: apiKey, extraHeaders: extraHeaders))
        ..body = jsonEncode(body);

      final streamedResponse = await _client.send(request).timeout(connectTimeout);

      if (streamedResponse.statusCode >= 400) {
        final errBody = await streamedResponse.stream.bytesToString();
        throwForStatusCode(streamedResponse.statusCode, errBody, uri);
      }

      return streamedResponse;
    } on SocketException catch (e) {
      throw HostUnreachableException(host: uri.host, details: e.message);
    } on TimeoutException {
      throw NetworkException(
        message: 'Streaming connection timed out for ${uri.host}',
        details: 'Failed to establish stream connection within ${connectTimeout.inSeconds} seconds.',
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
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded.containsKey('error')) {
        final err = decoded['error'];
        errorMsg = err is Map ? err['message'] ?? err.toString() : err.toString();
      }
    } catch (_) {
      if (body.isNotEmpty) {
        errorMsg = body;
      }
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

  void close() {
    _client.close();
  }
}
