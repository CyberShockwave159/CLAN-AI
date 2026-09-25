import 'dart:async';
import 'dart:convert';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/constants/api_endpoints.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/model_info.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class LlamaApiService {
  final ApiHttpClient _httpClient;
  final LatencyMeter _latencyMeter;

  LlamaApiService(this._httpClient, this._latencyMeter);

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
    required ServerProfile? connection,
    required List<ChatMessage> history,
    required String? systemPrompt,
    GenerationParams? params,
    CancelToken? cancelToken,
    int? modelContextLength,
  }) async* {
    var effectiveParams = params ?? serverConfig.defaultParams;

    // Apply server-level reasoning setting to params
    effectiveParams = effectiveParams.copyWith(reasoning: serverConfig.reasoning);

    final connDetails = connection ?? ServerProfile(name: 'Default', baseUrl: defaultBaseUrl);
    final cleanBase = ApiEndpoints.normalizeBaseUrl(connDetails.baseUrl);

    // OpenAI-compatible /v1/chat/completions endpoint. This is the only
    // transport: llama.cpp llama-server and every other supported backend
    // expose it, and it supports multimodal base64 `image_url` content parts.
    yield* _streamOpenAi(
      cleanBase: cleanBase,
      serverConfig: serverConfig,
      connection: connDetails,
      history: history,
      systemPrompt: systemPrompt,
      params: effectiveParams,
      cancelToken: cancelToken,
      modelContextLength: modelContextLength,
    );
  }

  Stream<StreamChunk> _streamOpenAi({
    required String cleanBase,
    required ServerConfig serverConfig,
    required ServerProfile connection,
    required List<ChatMessage> history,
    required String? systemPrompt,
    required GenerationParams params,
    CancelToken? cancelToken,
    int? modelContextLength,
  }) async* {
    final uri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.chatCompletions);

    // Build messages while tracking image token consumption for context fit.
    final List<Map<String, dynamic>> messages = [];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt.trim()});
    }

    int imageTokenCount = 0;
    for (final msg in history) {
      if (msg.role == MessageRole.user || msg.role == MessageRole.assistant) {
        final content = await _serializeOpenAiContent(msg);
        imageTokenCount += _estimateImageTokens(content);
        final Map<String, dynamic> openAiMsg = {
          'role': msg.role.value,
          'content': content,
        };
        if (msg.reasoningContent.isNotEmpty) {
          openAiMsg['reasoning'] = msg.reasoningContent;
        }
        messages.add(openAiMsg);
      }
    }

    // Context-fit with image token awareness: subtract estimated image token
    // usage from the available budget so the KV cache doesn't overflow when
    // base64 image payloads are included in the prompt.
    int adjustedContextSize = params.contextSize;
    if (modelContextLength != null && modelContextLength > 0) {
      final reservedForOutput = params.maxTokens > 0
          ? params.maxTokens
          : reservedOutputTokensDefault;
      final maxAllowed = modelContextLength - reservedForOutput - imageTokenCount;
      if (adjustedContextSize > maxAllowed) {
        adjustedContextSize = maxAllowed;
      }
      adjustedContextSize = adjustedContextSize.clamp(minContextSize, maxContextSize);
    }

    final adjustedParams = params.copyWith(contextSize: adjustedContextSize);

    final payload = adjustedParams.toOpenAiPayload(
      messages: messages,
      model: serverConfig.selectedModel ?? 'default',
      stream: true,
    );

    final streamedResponse = await _httpClient.postStream(
      uri,
      body: payload,
      apiKey: connection.apiKey,
    );

    final rawStream = SseClient.parseStream(
      streamedResponse.stream,
      cancelToken: cancelToken,
    );

    yield* SseClient.filterReasoning(
      rawStream,
      enableReasoning: serverConfig.reasoning,
    );
  }

  /// Estimates the number of tokens an image payload will consume in the KV
  /// cache.
  ///
  /// For LLaVA-style vision models (the predominant format supported by
  /// llama.cpp), images are tiled into patches processed by the vision encoder.
  /// A 1024×1024 image typically consumes ~9 000 tokens; a 2048×2048 image
  /// can consume ~30 000+. This heuristic divides the base64 data length by
  /// 30, which maps roughly to the patch-count × tokens-per-patch product
  /// for common models (LLaVA-1.5, LLaVA-Next, Qwen2-VL).
  static int _estimateImageTokens(dynamic content) {
    if (content is! List) return 0;
    int tokens = 0;
    for (final part in content) {
      if (part is Map<String, dynamic> &&
          part['type'] == 'image_url' &&
          part['image_url'] is Map<String, dynamic>) {
        final url = part['image_url']['url'] as String?;
        if (url != null) {
          final commaIndex = url.indexOf(',');
          if (commaIndex != -1) {
            final base64Data = url.substring(commaIndex + 1);
            tokens += base64Data.length ~/ 30;
          }
        }
      }
    }
    return tokens;
  }

  /// Serializes a message's content for the OpenAI-compatible chat format.
  ///
  /// Returns the plain text string when the message carries no image, or an
  /// array of typed content parts (`text` + `image_url`) when a message (user
  /// or assistant) has an image attachment. Assistant images — typically A-
  /// PROX generated artifacts — are re-attached so that image-to-image edit
  /// workflows can reference them without overloading the KV cache (see
  /// [_estimateImageTokens] for the context-fit math). The image bytes are
  /// read through the attachment store and encoded as a base64 data URI — the
  /// format accepted by llama.cpp llama-server, Ollama, LM Studio, vLLM, and
  /// OpenAI. A missing/unreadable attachment falls back to the plain text so
  /// a broken attachment never breaks the request.
  Future<dynamic> _serializeOpenAiContent(ChatMessage msg) async {
    final imagePath = msg.imagePath;
    if (imagePath == null || imagePath.trim().isEmpty) {
      return msg.content;
    }

    try {
      final bytes = await MessageAttachmentStore.instance.readBytes(imagePath);
      if (bytes == null) return msg.content;
      // Trust the file's magic bytes over the filename extension: a `png`-named
      // JPEG (or an extension-less path) would otherwise be declared with the
      // wrong mime, and some servers use the declared mime to pick a decoder.
      final mime = MessageAttachmentStore.mimeTypeFromBytes(bytes) ??
          MessageAttachmentStore.mimeTypeFor(
            MessageAttachmentStore.extensionOf(imagePath),
          );
      return [
        {'type': 'text', 'text': msg.content},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
        },
      ];
    } catch (_) {
      return msg.content;
    }
  }

  /// Submits a chat completion request asynchronously.
  ///
  /// Returns the request ID that can be used to poll for status or stream the result.
  Future<String> submitAsyncCompletion({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required List<ChatMessage> history,
    required String? systemPrompt,
    GenerationParams? params,
    String? requestId,
    int? modelContextLength,
  }) async {
    try {
      var effectiveParams = params ?? serverConfig.defaultParams;
      effectiveParams = effectiveParams.copyWith(reasoning: serverConfig.reasoning);

      final connDetails = connection ?? ServerProfile(name: 'Default', baseUrl: defaultBaseUrl);
      final cleanBase = ApiEndpoints.normalizeBaseUrl(connDetails.baseUrl);
      final uri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.chatCompletionsAsync);

      // Build payload same as streaming
      final List<Map<String, dynamic>> messages = [];
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        messages.add({'role': 'system', 'content': systemPrompt.trim()});
      }
      for (final msg in history) {
        if (msg.role == MessageRole.user || msg.role == MessageRole.assistant) {
          final content = await _serializeOpenAiContent(msg);
          final Map<String, dynamic> openAiMsg = {
            'role': msg.role.value,
            'content': content,
          };
          if (msg.reasoningContent.isNotEmpty) {
            openAiMsg['reasoning'] = msg.reasoningContent;
          }
          messages.add(openAiMsg);
        }
      }

      final payload = effectiveParams.toOpenAiPayload(
        messages: messages,
        model: serverConfig.selectedModel ?? 'default',
        stream: true,
      );

      if (requestId != null) {
        payload['request_id'] = requestId;
      }

      final response = await _httpClient.postAsync(uri, body: payload, apiKey: connDetails.apiKey);
      return response['request_id'] as String;
    } catch (e) {
      rethrow;
    }
  }

  /// Streams the result of an async request.
  Stream<StreamChunk> streamAsyncCompletion({
    required String cleanBase,
    required String requestId,
    required String? apiKey,
    CancelToken? cancelToken,
  }) async* {
    final uri = ApiEndpoints.buildUri(cleanBase, '${ApiEndpoints.chatCompletionsAsync}/$requestId/stream');
    final streamedResponse = await _httpClient.getStream(uri, apiKey: apiKey);
    final rawStream = SseClient.parseStream(streamedResponse.stream, cancelToken: cancelToken);
    yield* SseClient.filterReasoning(rawStream, enableReasoning: true);
  }

  /// Fetches the final result of a completed async request.
  Future<Map<String, dynamic>?> fetchAsyncResult({
    required String cleanBase,
    required String requestId,
    required String? apiKey,
  }) async {
    final uri = ApiEndpoints.buildUri(cleanBase, '${ApiEndpoints.chatCompletionsAsync}/$requestId/result');
    return await _httpClient.get(uri, apiKey: apiKey);
  }

  /// Cancels an async request.
  Future<void> cancelAsyncRequest({
    required String cleanBase,
    required String requestId,
    required String? apiKey,
  }) async {
    final uri = ApiEndpoints.buildUri(cleanBase, '${ApiEndpoints.chatCompletionsAsync}/$requestId');
    await _httpClient.delete(uri, apiKey: apiKey);
  }
}
