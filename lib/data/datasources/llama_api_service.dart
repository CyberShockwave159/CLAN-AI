import 'dart:async';
import 'package:clan_ai/core/constants/api_endpoints.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class LlamaApiService {
  final ApiHttpClient _httpClient;
  final LatencyMeter _latencyMeter;

  LlamaApiService({
    ApiHttpClient? httpClient,
    LatencyMeter? latencyMeter,
  })  : _httpClient = httpClient ?? ApiHttpClient(),
        _latencyMeter = latencyMeter ?? LatencyMeter(httpClient: httpClient);

  /// Pings the server to check connectivity and roundtrip latency in ms.
  Future<PingResult> ping(String baseUrl, {String? apiKey}) async {
    return await _latencyMeter.ping(baseUrl, apiKey: apiKey);
  }

  /// Fetches available models from the llama.cpp / OpenAI endpoint.
  Future<List<ModelInfo>> fetchModels(String baseUrl, {String? apiKey}) async {
    final cleanBase = ApiEndpoints.normalizeBaseUrl(baseUrl);
    final List<ModelInfo> models = [];

    // 1. Try /props to get loaded llama.cpp model info
    try {
      final propsUri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.llamaProps);
      final props = await _httpClient.get(propsUri, apiKey: apiKey);
      if (props is Map<String, dynamic>) {
        models.add(ModelInfo.fromLlamaProps(props));
      }
    } catch (_) {}

    // 2. Try OpenAI compatible /v1/models
    try {
      final modelsUri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.models);
      final res = await _httpClient.get(modelsUri, apiKey: apiKey);
      if (res is Map<String, dynamic> && res.containsKey('data')) {
        final list = res['data'] as List<dynamic>;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final modelInfo = ModelInfo.fromOpenAiJson(item);
            if (!models.any((m) => m.id == modelInfo.id)) {
              models.add(modelInfo);
            }
          }
        }
      }
    } catch (_) {}

    // Default fallback model if none enumerated
    if (models.isEmpty) {
      models.add(const ModelInfo(id: 'default', name: 'llama.cpp Server Model'));
    }

    return models;
  }

  /// Streams chat completions from the server via SSE.
  Stream<StreamChunk> streamChatCompletions({
    required ServerConfig serverConfig,
    required List<ChatMessage> history,
    required String? systemPrompt,
    GenerationParams? params,
    CancelToken? cancelToken,
    int? modelContextLength,
  }) async* {
    final effectiveParams = params ?? serverConfig.defaultParams;

    // Best-effort context fit: cap contextSize to model's actual capacity
    int adjustedContextSize = effectiveParams.contextSize;
    if (modelContextLength != null && modelContextLength > 0) {
      // Reserve some tokens for generation output (at least 256)
      final reservedForOutput = effectiveParams.maxTokens > 0
          ? effectiveParams.maxTokens
          : 512;
      final maxAllowed = modelContextLength - reservedForOutput;
      if (adjustedContextSize > maxAllowed) {
        adjustedContextSize = maxAllowed;
      }
      adjustedContextSize = adjustedContextSize.clamp(128, 1000000);
    }

    final adjustedParams = effectiveParams.copyWith(contextSize: adjustedContextSize);

    final cleanBase = ApiEndpoints.normalizeBaseUrl(serverConfig.baseUrl);

    if (serverConfig.protocol == ApiProtocol.llamaNative) {
      // llama.cpp native /completion endpoint with raw prompt
      yield* _streamLlamaNative(
        cleanBase: cleanBase,
        serverConfig: serverConfig,
        history: history,
        systemPrompt: systemPrompt,
        params: adjustedParams,
        cancelToken: cancelToken,
      );
    } else {
      // OpenAI compatible /v1/chat/completions endpoint
      yield* _streamOpenAi(
        cleanBase: cleanBase,
        serverConfig: serverConfig,
        history: history,
        systemPrompt: systemPrompt,
        params: adjustedParams,
        cancelToken: cancelToken,
      );
    }
  }

  Stream<StreamChunk> _streamOpenAi({
    required String cleanBase,
    required ServerConfig serverConfig,
    required List<ChatMessage> history,
    required String? systemPrompt,
    required GenerationParams params,
    CancelToken? cancelToken,
  }) async* {
    final uri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.chatCompletions);

    final List<Map<String, dynamic>> messages = [];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt.trim()});
    }

    for (final msg in history) {
      if (msg.role == MessageRole.user || msg.role == MessageRole.assistant) {
        messages.add(msg.toOpenAiMessage());
      }
    }

    final payload = params.toOpenAiPayload(
      messages: messages,
      model: serverConfig.selectedModel ?? 'default',
      stream: true,
    );

    final streamedResponse = await _httpClient.postStream(
      uri,
      body: payload,
      apiKey: serverConfig.apiKey,
    );

    yield* SseClient.parseStream(
      streamedResponse.stream,
      cancelToken: cancelToken,
    );
  }

  Stream<StreamChunk> _streamLlamaNative({
    required String cleanBase,
    required ServerConfig serverConfig,
    required List<ChatMessage> history,
    required String? systemPrompt,
    required GenerationParams params,
    CancelToken? cancelToken,
  }) async* {
    final uri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.llamaCompletion);

    final buffer = StringBuffer();
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      buffer.writeln('### System:\n${systemPrompt.trim()}\n');
    }

    for (final msg in history) {
      if (msg.role == MessageRole.user) {
        buffer.writeln('### User:\n${msg.content}\n');
      } else if (msg.role == MessageRole.assistant) {
        buffer.writeln('### Assistant:\n${msg.content}\n');
      }
    }
    buffer.write('### Assistant:\n');

    final payload = params.toLlamaNativePayload(
      prompt: buffer.toString(),
      stream: true,
    );

    final streamedResponse = await _httpClient.postStream(
      uri,
      body: payload,
      apiKey: serverConfig.apiKey,
    );

    yield* SseClient.parseStream(
      streamedResponse.stream,
      cancelToken: cancelToken,
    );
  }
}
