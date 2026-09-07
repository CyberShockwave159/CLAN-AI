import 'dart:async';
import 'package:clan_ai/core/constants/api_endpoints.dart';
import 'package:clan_ai/core/network/http_client.dart';

/// Health status enum for llama.cpp server
enum ServerHealthStatus {
  connected,
  connecting,
  degraded,
  offline,
}

/// Ping result with latency and server props
class PingResult {
  final ServerHealthStatus status;
  final int latencyMs;
  final String? errorMessage;
  final Map<String, dynamic>? serverProps;

  const PingResult({
    required this.status,
    required this.latencyMs,
    this.errorMessage,
    this.serverProps,
  });

  bool get isHealthy => status == ServerHealthStatus.connected;

  /// Parses a raw error string into a user-friendly diagnostic message.
  static String parseError(String rawError) {
    final lower = rawError.toLowerCase();

    // Connection refused
    if (lower.contains('connection refused') || lower.contains('socketexception')) {
      return 'Connection refused. Ensure your LLM server (e.g. llama.cpp) is running on this port.';
    }

    // Timeout
    if (lower.contains('timed out') || lower.contains('timeoutexception') || lower.contains('timedout')) {
      return 'Connection timed out. Check the IP address and firewall settings.';
    }

    // SSL/TLS
    if (lower.contains('handshake') || lower.contains('ssl') || lower.contains('tls') || lower.contains('certificate')) {
      return 'SSL/TLS certificate error. Use http:// for local servers or check HTTPS certificates.';
    }

    // HTTP 401 / 403
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'Authentication failed. Please verify your API key in Settings.';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Authentication failed. Please verify your API key in Settings.';
    }

    // HTTP 404
    if (lower.contains('404')) {
      return 'Endpoint not found. Check if the server protocol (OpenAI vs native llama.cpp) is correct.';
    }

    // Context limit errors from the API
    if (lower.contains('context') && (lower.contains('exceed') || lower.contains('too long') || lower.contains('max'))) {
      return 'Context window exceeded. Try a smaller context size or clear the conversation.';
    }

    // OOM errors
    if (lower.contains('out of memory') || lower.contains('oom')) {
      return 'Server out of memory. Try a smaller model or free up system resources.';
    }

    // Generic fallback
    return rawError;
  }
}

/// Latency meter to measure real-time ping to llama.cpp servers
class LatencyMeter {
  final ApiHttpClient _httpClient;

  LatencyMeter({ApiHttpClient? httpClient}) : _httpClient = httpClient ?? ApiHttpClient();

  /// Pings the server using `/health`, `/props`, or `/v1/models` and returns the round-trip latency.
  Future<PingResult> ping(String baseUrl, {String? apiKey}) async {
    final cleanBase = ApiEndpoints.normalizeBaseUrl(baseUrl);
    final stopwatch = Stopwatch()..start();

    // Priority 1: Check native llama.cpp /health endpoint
    try {
      final healthUri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.llamaHealth);
      final response = await _httpClient.get(healthUri, apiKey: apiKey);
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds;
      return PingResult(
        status: ServerHealthStatus.connected,
        latencyMs: latency,
        serverProps: response is Map<String, dynamic> ? response : null,
      );
    } catch (_) {
      // Fallback 1: Try /props (native llama.cpp properties)
      try {
        stopwatch.reset();
        stopwatch.start();
        final propsUri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.llamaProps);
        final response = await _httpClient.get(propsUri, apiKey: apiKey);
        stopwatch.stop();

        final latency = stopwatch.elapsedMilliseconds;
        return PingResult(
          status: ServerHealthStatus.connected,
          latencyMs: latency,
          serverProps: response is Map<String, dynamic> ? response : null,
        );
      } catch (_) {
        // Fallback 2: Try OpenAI /v1/models endpoint
        try {
          stopwatch.reset();
          stopwatch.start();
          final modelsUri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.models);
          await _httpClient.get(modelsUri, apiKey: apiKey);
          stopwatch.stop();

          final latency = stopwatch.elapsedMilliseconds;
          return PingResult(
            status: ServerHealthStatus.connected,
            latencyMs: latency,
          );
        } catch (e) {
          stopwatch.stop();
          return PingResult(
            status: ServerHealthStatus.offline,
            latencyMs: -1,
            errorMessage: PingResult.parseError(e.toString()),
          );
        }
      }
    }
  }
}
