import 'dart:convert';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

enum ApiProtocol {
  openAi,
  llamaNative;

  String get displayName => this == openAi ? 'OpenAI Compatible' : 'llama.cpp Native';
}

class ServerConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final String? selectedModel;
  final ApiProtocol protocol;
  final GenerationParams defaultParams;
  final ServerHealthStatus healthStatus;
  final int latencyMs;
  final String? systemPrompt;
  final bool confirmDeleteMessage;

  const ServerConfig({
    this.id = 'default',
    this.name = 'Local llama.cpp',
    this.baseUrl = 'http://127.0.0.1:8080',
    this.apiKey,
    this.selectedModel,
    this.protocol = ApiProtocol.openAi,
    this.defaultParams = const GenerationParams(),
    this.healthStatus = ServerHealthStatus.offline,
    this.latencyMs = -1,
    this.systemPrompt = 'You are a helpful, brilliant, and honest AI assistant.',
    this.confirmDeleteMessage = true,
  });

  ServerConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    ApiProtocol? protocol,
    GenerationParams? defaultParams,
    ServerHealthStatus? healthStatus,
    int? latencyMs,
    String? systemPrompt,
    bool? confirmDeleteMessage,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      protocol: protocol ?? this.protocol,
      defaultParams: defaultParams ?? this.defaultParams,
      healthStatus: healthStatus ?? this.healthStatus,
      latencyMs: latencyMs ?? this.latencyMs,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      confirmDeleteMessage: confirmDeleteMessage ?? this.confirmDeleteMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'api_key': apiKey,
      'selected_model': selectedModel,
      'protocol': protocol.name,
      'default_params': jsonEncode(defaultParams.toMap()),
      'system_prompt': systemPrompt,
      'confirm_delete_message': confirmDeleteMessage ? 1 : 0,
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
      id: map['id'] as String? ?? 'default',
      name: map['name'] as String? ?? 'Local llama.cpp',
      baseUrl: map['base_url'] as String? ?? 'http://127.0.0.1:8080',
      apiKey: map['api_key'] as String?,
      selectedModel: map['selected_model'] as String?,
      protocol: ApiProtocol.values.firstWhere(
        (e) => e.name == map['protocol'],
        orElse: () => ApiProtocol.openAi,
      ),
      defaultParams: defaultParams,
      systemPrompt: map['system_prompt'] as String? ?? 'You are a helpful, brilliant, and honest AI assistant.',
      confirmDeleteMessage: (map['confirm_delete_message'] as int?) == 1,
    );
  }
}
