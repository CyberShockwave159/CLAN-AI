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
            errorMessage: e.toString(),
          );
        }
      }
    }
  }
}
