import 'dart:convert';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

enum ApiProtocol {
  openAi,
  llamaNative;

  String get displayName => this == openAi ? 'OpenAI Compatible' : 'llama.cpp Native';
}

class ServerConfig {
  final String name;
  final String baseUrl;
  final String? apiKey;
  final ApiProtocol protocol;
  final String? selectedModel;
  final GenerationParams defaultParams;
  final ServerHealthStatus healthStatus;
  final int latencyMs;
  final String? systemPrompt;
  final bool confirmDeleteMessage;
  final bool reasoning;

  const ServerConfig({
    this.name = defaultServerName,
    this.baseUrl = defaultBaseUrl,
    this.apiKey,
    this.protocol = ApiProtocol.openAi,
    this.selectedModel,
    this.defaultParams = const GenerationParams(),
    this.healthStatus = ServerHealthStatus.offline,
    this.latencyMs = -1,
    this.systemPrompt = defaultSystemPrompt,
    this.confirmDeleteMessage = true,
    this.reasoning = false,
  });

  ServerConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    ApiProtocol? protocol,
    String? selectedModel,
    GenerationParams? defaultParams,
    ServerHealthStatus? healthStatus,
    int? latencyMs,
    String? systemPrompt,
    bool? confirmDeleteMessage,
    bool? reasoning,
  }) {
    return ServerConfig(
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      protocol: protocol ?? this.protocol,
      selectedModel: selectedModel ?? this.selectedModel,
      defaultParams: defaultParams ?? this.defaultParams,
      healthStatus: healthStatus ?? this.healthStatus,
      latencyMs: latencyMs ?? this.latencyMs,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      confirmDeleteMessage: confirmDeleteMessage ?? this.confirmDeleteMessage,
      reasoning: reasoning ?? this.reasoning,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'base_url': baseUrl,
      'api_key': apiKey,
      'protocol': protocol.name,
      'selected_model': selectedModel,
      'default_params': jsonEncode(defaultParams.toMap()),
      'system_prompt': systemPrompt,
      'confirm_delete_message': confirmDeleteMessage ? 1 : 0,
      'reasoning': reasoning ? 1 : 0,
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

    final protocolStr = map['protocol'] as String?;
    final savedProtocol = protocolStr != null
        ? ApiProtocol.values.firstWhere(
            (e) => e.name == protocolStr,
            orElse: () => ApiProtocol.openAi,
          )
        : ApiProtocol.openAi;

    return ServerConfig(
      name: map['name'] as String? ?? defaultServerName,
      baseUrl: map['base_url'] as String? ?? defaultBaseUrl,
      apiKey: map['api_key'] as String?,
      protocol: savedProtocol,
      selectedModel: map['selected_model'] as String?,
      defaultParams: defaultParams,
      systemPrompt: map['system_prompt'] as String? ?? defaultSystemPrompt,
      confirmDeleteMessage: (map['confirm_delete_message'] as int?) == 1,
      reasoning: (map['reasoning'] as int?) == 1,
    );
  }
}
