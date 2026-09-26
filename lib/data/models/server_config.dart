import 'dart:convert';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class ServerConfig {
  final String name;
  final String baseUrl;
  final String? apiKey;
  final String? selectedModel;
  final GenerationParams defaultParams;
  final ServerHealthStatus healthStatus;
  final int latencyMs;
  final String? systemPrompt;
  final bool confirmDeleteMessage;
  final bool reasoning;

  /// When true, roleplay memory is handled by the A-PROX server instead of the
  /// client-side vector store: retrieval happens through A-PROX's `a-prox-rag`
  /// route, and completed turns are pushed into a per-thread A-PROX collection.
  ///
  /// The two backends are mutually exclusive — turning this on bypasses the
  /// client RAG pipeline entirely rather than running both (double-retrieval
  /// would inject the same facts twice). Locally stored embeddings are left
  /// untouched, so flipping back is lossless. Only meaningful against an
  /// A-PROX server; the UI hides it otherwise.
  final bool serverSideRagEnabled;

  const ServerConfig({
    this.name = defaultServerName,
    this.baseUrl = defaultBaseUrl,
    this.apiKey,
    this.selectedModel,
    this.defaultParams = const GenerationParams(),
    this.healthStatus = ServerHealthStatus.offline,
    this.latencyMs = -1,
    this.systemPrompt = defaultSystemPrompt,
    this.confirmDeleteMessage = true,
    this.reasoning = false,
    this.serverSideRagEnabled = false,
  });

  ServerConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    GenerationParams? defaultParams,
    ServerHealthStatus? healthStatus,
    int? latencyMs,
    String? systemPrompt,
    bool? confirmDeleteMessage,
    bool? reasoning,
    bool? serverSideRagEnabled,
  }) {
    return ServerConfig(
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      defaultParams: defaultParams ?? this.defaultParams,
      healthStatus: healthStatus ?? this.healthStatus,
      latencyMs: latencyMs ?? this.latencyMs,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      confirmDeleteMessage: confirmDeleteMessage ?? this.confirmDeleteMessage,
      reasoning: reasoning ?? this.reasoning,
      serverSideRagEnabled: serverSideRagEnabled ?? this.serverSideRagEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'base_url': baseUrl,
      'api_key': apiKey,
      'selected_model': selectedModel,
      'default_params': jsonEncode(defaultParams.toMap()),
      'system_prompt': systemPrompt,
      'confirm_delete_message': confirmDeleteMessage ? 1 : 0,
      'reasoning': reasoning ? 1 : 0,
      'server_side_rag_enabled': serverSideRagEnabled ? 1 : 0,
    };
  }

  factory ServerConfig.fromMap(Map<String, dynamic> map) {
    GenerationParams defaultParams = const GenerationParams();
    if (map['default_params'] != null) {
      try {
        final decoded = map['default_params'] is String
            ? jsonDecode(map['default_params'] as String)
            : map['default_params'] as Map<String, dynamic>;
        defaultParams = GenerationParams.fromMap(decoded);
      } catch (_) {}
    }

    return ServerConfig(
      name: map['name'] as String? ?? defaultServerName,
      baseUrl: map['base_url'] as String? ?? defaultBaseUrl,
      apiKey: map['api_key'] as String?,
      selectedModel: map['selected_model'] as String?,
      defaultParams: defaultParams,
      systemPrompt: map['system_prompt'] as String? ?? defaultSystemPrompt,
      confirmDeleteMessage: (map['confirm_delete_message'] as int?) == 1,
      reasoning: (map['reasoning'] as int?) == 1,
      serverSideRagEnabled: (map['server_side_rag_enabled'] as int?) == 1,
    );
  }
}
