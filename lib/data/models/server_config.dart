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
  final String? selectedModel;
  final GenerationParams defaultParams;
  final ServerHealthStatus healthStatus;
  final int latencyMs;
  final String? systemPrompt;
  final bool confirmDeleteMessage;
  final bool reasoning;
  // Legacy fields — read from old SharedPreferences format but not persisted
  final String? _legacyBaseUrl;
  final String? _legacyApiKey;
  final ApiProtocol? _legacyProtocol;

  const ServerConfig({
    this.name = defaultServerName,
    this.selectedModel,
    this.defaultParams = const GenerationParams(),
    this.healthStatus = ServerHealthStatus.offline,
    this.latencyMs = -1,
    this.systemPrompt = defaultSystemPrompt,
    this.confirmDeleteMessage = true,
    this.reasoning = false,
    String? legacyBaseUrl,
    String? legacyApiKey,
    ApiProtocol? legacyProtocol,
  })  : _legacyBaseUrl = legacyBaseUrl,
        _legacyApiKey = legacyApiKey,
        _legacyProtocol = legacyProtocol;

  /// Returns the base URL from legacy storage, or the default if not set.
  String get baseUrl => _legacyBaseUrl ?? defaultBaseUrl;

  /// Returns the API key from legacy storage, or null.
  String? get apiKey => _legacyApiKey;

  /// Returns the protocol from legacy storage, or OpenAI if not set.
  ApiProtocol get protocol => _legacyProtocol ?? ApiProtocol.openAi;

  ServerConfig copyWith({
    String? name,
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
      selectedModel: selectedModel ?? this.selectedModel,
      defaultParams: defaultParams ?? this.defaultParams,
      healthStatus: healthStatus ?? this.healthStatus,
      latencyMs: latencyMs ?? this.latencyMs,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      confirmDeleteMessage: confirmDeleteMessage ?? this.confirmDeleteMessage,
      reasoning: reasoning ?? this.reasoning,
      legacyBaseUrl: _legacyBaseUrl,
      legacyApiKey: _legacyApiKey,
      legacyProtocol: _legacyProtocol,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'selected_model': selectedModel,
      'protocol': ApiProtocol.openAi.name,
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

    return ServerConfig(
      name: map['name'] as String? ?? defaultServerName,
      selectedModel: map['selected_model'] as String?,
      defaultParams: defaultParams,
      systemPrompt: map['system_prompt'] as String? ?? defaultSystemPrompt,
      confirmDeleteMessage: (map['confirm_delete_message'] as int?) == 1,
      reasoning: (map['reasoning'] as int?) == 1,
      legacyBaseUrl: map['base_url'] as String?,
      legacyApiKey: map['api_key'] as String?,
      legacyProtocol: map['protocol'] != null
          ? ApiProtocol.values.firstWhere(
              (e) => e.name == map['protocol'],
              orElse: () => ApiProtocol.openAi,
            )
          : null,
    );
  }
}
