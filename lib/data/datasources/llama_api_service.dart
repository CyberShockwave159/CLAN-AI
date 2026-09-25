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

    // Best-effort context fit: cap contextSize to model's actual capacity
    int adjustedContextSize = effectiveParams.contextSize;
    if (modelContextLength != null && modelContextLength > 0) {
      // Reserve some tokens for generation output (at least 256)
      final reservedForOutput = effectiveParams.maxTokens > 0
          ? effectiveParams.maxTokens
          : reservedOutputTokensDefault;
      final maxAllowed = modelContextLength - reservedForOutput;
      if (adjustedContextSize > maxAllowed) {
        adjustedContextSize = maxAllowed;
      }
      adjustedContextSize = adjustedContextSize.clamp(minContextSize, maxContextSize);
    }

    final adjustedParams = effectiveParams.copyWith(contextSize: adjustedContextSize);

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
      params: adjustedParams,
      cancelToken: cancelToken,
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
  }) async* {
    final uri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.chatCompletions);

    final List<Map<String, dynamic>> messages = [];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt.trim()});
    }

    for (final msg in history) {
      if (msg.role == MessageRole.user || msg.role == MessageRole.assistant) {
        final Map<String, dynamic> openAiMsg = {
          'role': msg.role.value,
          'content': await _serializeOpenAiContent(msg),
        };
        if (msg.reasoningContent.isNotEmpty) {
          openAiMsg['reasoning'] = msg.reasoningContent;
        }
        messages.add(openAiMsg);
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

  /// Serializes a message's content for the OpenAI-compatible chat format.
  ///
  /// Returns the plain text string when the message carries no image, or an
  /// array of typed content parts (`text` + `image_url`) when a user message
  /// has an image attachment. The image bytes are read through the attachment
  /// store and encoded as a base64 data URI — the format accepted by llama.cpp
  /// llama-server, Ollama, LM Studio, vLLM, and OpenAI. A missing/unreadable
  /// attachment falls back to the plain text so a broken attachment never
  /// breaks the request.
  Future<dynamic> _serializeOpenAiContent(ChatMessage msg) async {
    final imagePath = msg.imagePath;
    if (msg.role != MessageRole.user ||
        imagePath == null ||
        imagePath.trim().isEmpty) {
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
}
