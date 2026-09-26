import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/constants/api_endpoints.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/data/datasources/request_options.dart';
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
    RequestOptions options = const RequestOptions(),
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
      options: options,
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
    RequestOptions options = const RequestOptions(),
  }) async* {
    final uri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.chatCompletions);

    final List<Map<String, dynamic>> messages = [];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      final systemMessage = <String, dynamic>{
        'role': 'system',
        'content': systemPrompt.trim(),
      };
      // Mark the system message too, not just the turns: the marker describes
      // the whole request, and a request whose only message is the system
      // prompt would otherwise be unmarked.
      if (options.roleplayMode) {
        systemMessage['roleplay'] = true;
      }
      messages.add(systemMessage);
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
        // Marks the whole turn as roleplay. A-PROX reads it to restrict the
        // armed tool set to memory retrieval and image generation, so a roleplay
        // turn can never reach web search, the clock, or file writing.
        if (options.roleplayMode) {
          openAiMsg['roleplay'] = true;
        }
        messages.add(openAiMsg);
      }
    }

    // Attach an identity reference to the final user message, as array content.
    //
    // This is what makes A-PROX pick its image-to-image workflow (reference
    // conditioning) instead of text-to-image, and it has to be the *last* user
    // message: `extract_reference_image` scans backwards for one. It must also be
    // array content — that extractor only inspects `content` when it is a JSON
    // array of parts, so a plain string would be ignored.
    if (options.referenceImage != null && options.referenceImage!.isNotEmpty) {
      _attachReferenceImage(messages, options);
    }

    final payload = params.toOpenAiPayload(
      messages: messages,
      model: serverConfig.selectedModel ?? 'default',
      stream: true,
      modelOverride: options.modelOverride,
      rag: options.rag,
      extraBody: {
        // Skips A-PROX's vision-caption and synthesis turns. A first-class
        // option rather than part of `extraBody` so it cannot be set by
        // accident when only a style is meant.
        if (options.imageOnly) 'image_only': true,
        ...?options.extraBody,
      },
    );

    final streamedResponse = await _httpClient.postStream(
      uri,
      body: payload,
      apiKey: connection.apiKey,
      timeout: options.streamTimeout,
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

  /// Runs a single non-streaming completion and returns the assistant text.
  ///
  /// Used for auxiliary calls that must not appear in the conversation — the
  /// scene-image prompt draft, appearance drafting, style detection. Discarding
  /// the response keeps it out of the message history, the RAG write path, and
  /// the UI.
  ///
  /// [reasoning] and [maxTokens] override the defaults so each caller can pick
  /// the right trade-off; see [_auxiliaryMaxTokens].
  ///
  /// [timeout] overrides the shared 60s receive budget. A call that reasons for
  /// minutes must raise it: the default silently aborts a request the server
  /// completed successfully, which surfaces as a blank result with no clue why.
  /// It is a ceiling, not a cost — the call returns as soon as the server
  /// answers.
  ///
  /// Returns an empty string when the server returns no usable text.
  Future<String> completeOnce({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required String? systemPrompt,
    required List<Map<String, dynamic>> messages,
    GenerationParams? params,
    RequestOptions options = RequestOptions.none,
    bool? reasoning,
    int? maxTokens,
    Duration? timeout,
  }) async {
    // Defaults to reasoning OFF: these calls ask for a short artefact, and a
    // thinking preamble is normally pure waste. The scene-image draft overrides
    // this — see [_draftReasoning] for why it needs the reasoning channel.
    final effectiveParams = (params ?? serverConfig.defaultParams).copyWith(
      reasoning: reasoning ?? false,
    );
    final connDetails = connection ?? ServerProfile(name: 'Default', baseUrl: defaultBaseUrl);
    final cleanBase = ApiEndpoints.normalizeBaseUrl(connDetails.baseUrl);
    final uri = ApiEndpoints.buildUri(cleanBase, ApiEndpoints.chatCompletions);

    final body = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': systemPrompt.trim()},
      ...messages,
    ];

    final payload = effectiveParams.toOpenAiPayload(
      messages: body,
      model: serverConfig.selectedModel ?? 'default',
      stream: false,
      modelOverride: options.modelOverride,
      rag: options.rag,
      extraBody: options.extraBody,
    );
    // Budget precedence: an explicit per-call override, then the caller's own
    // `maxTokens`, then the auxiliary default. Overriding a caller-chosen value
    // would silently ignore the user's Generation Parameters.
    payload['max_tokens'] = maxTokens != null && maxTokens > 0
        ? maxTokens
        : (params?.maxTokens != null && params!.maxTokens > 0
            ? params.maxTokens
            : _auxiliaryMaxTokens);

    final response = await _httpClient.post(
      uri,
      body: payload,
      apiKey: connDetails.apiKey,
      timeout: timeout,
    );
    return _extractCompletionText(response);
  }

  /// Token budget for the short auxiliary calls — appearance drafting, style
  /// detection. Both want a few dozen words, so this is deliberately tight and
  /// reasoning is off.
  static const int _auxiliaryMaxTokens = 256;

  /// Pulls the assistant text out of a non-streaming chat-completions body.
  ///
  /// Tolerates both the plain-string and typed-content-array `content` shapes so
  /// a server that answers with a content array doesn't silently yield "".
  ///
  /// Falls back to `reasoning_content` when `content` is empty. With reasoning
  /// pinned off for these calls that should be unreachable, but a server that
  /// reasons anyway would otherwise turn a long chain of thought into a blank
  /// result — a failure mode that is very hard to diagnose from the outside.
  static String _extractCompletionText(dynamic response) {
    if (response is! Map) return '';
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final message = choices.first is Map ? (choices.first as Map)['message'] : null;
    if (message is! Map) return '';

    final content = _textOf(message['content']);
    if (content.isNotEmpty) return content;

    for (final field in const ['reasoning_content', 'reasoning', 'thought']) {
      final fallback = _textOf(message[field]);
      if (fallback.isNotEmpty) return fallback;
    }
    return '';
  }

  /// Normalizes a message field to trimmed text, joining typed content parts.
  static String _textOf(dynamic value) {
    if (value is String) return value.trim();
    if (value is List) {
      return value
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join('\n')
          .trim();
    }
    return '';
  }

  /// Appends an `image_url` part to the final user message in [messages],
  /// converting its content to typed parts if needed.
  ///
  /// No-ops when there is no user message to attach to, or when one already
  /// carries an image (a second reference would be ignored by A-PROX anyway, and
  /// duplicating the payload would be pure waste).
  static void _attachReferenceImage(
    List<Map<String, dynamic>> messages,
    RequestOptions options,
  ) {
    final bytes = options.referenceImage;
    if (bytes == null || bytes.isEmpty) return;

    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message['role'] != 'user') continue;
      final existing = message['content'];
      if (existing is List) {
        final hasImage = existing.any(
          (part) => part is Map && part['type'] == 'image_url',
        );
        if (hasImage) return;
      }
      final mime = MessageAttachmentStore.mimeTypeFromBytes(bytes) ??
          options.referenceImageMime ??
          'image/jpeg';
      final imagePart = {
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
      };
      if (existing is List) {
        message['content'] = [...existing, imagePart];
      } else if (existing is String && existing.isNotEmpty) {
        message['content'] = [
          {'type': 'text', 'text': existing},
          imagePart,
        ];
      } else {
        message['content'] = [imagePart];
      }
      return;
    }
  }

  /// Builds the multimodal content array for a synthetic request message that
  /// must carry both text and an image reference.
  ///
  /// A-PROX's `extract_reference_image` only inspects `content` when it is a
  /// JSON **array** of parts (`imagegen/mod.rs`), so an image-to-image request
  /// cannot be expressed as a plain string. The DB-backed
  /// [_serializeOpenAiContent] covers stored user attachments; this covers
  /// messages the app synthesizes for one-shot calls. Prefer
  /// [RequestOptions.referenceImage], which applies to the right message
  /// automatically.
  static List<Map<String, dynamic>> buildImageContentParts({
    required String text,
    required Uint8List imageBytes,
    String? mimeType,
  }) {
    // Trust the bytes over any caller-supplied label, for the same reason
    // _serializeOpenAiContent does: a mislabelled image makes the server pick
    // the wrong decoder.
    final mime = MessageAttachmentStore.mimeTypeFromBytes(imageBytes) ??
        mimeType ??
        'image/jpeg';
    return [
      {'type': 'text', 'text': text},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,${base64Encode(imageBytes)}'},
      },
    ];
  }
}
