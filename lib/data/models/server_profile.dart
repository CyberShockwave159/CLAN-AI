import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/constants/aprox_capabilities.dart';

class ServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final bool reasoning;

  /// Runtime-only capability tags advertised by the connected server's
  /// `/health` response (A-PROX reports `rag`, `image`, `file`). Deliberately
  /// **not** serialized: capabilities describe the server that happens to be
  /// reachable right now, not the profile, and they are re-derived by the
  /// 15-second health poll.
  final Set<String> capabilities;

  ServerProfile({
    String? id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    this.reasoning = false,
    this.capabilities = const {},
  }) : id = id ?? const Uuid().v4();

  /// True when the connected server is an A-PROX instance. A-PROX-only
  /// features (server-side RAG, scene image generation) are gated on this so
  /// they are never offered against a plain llama.cpp or OpenAI backend.
  bool get isAprox => capabilities.contains(AproxCapabilities.rag);

  /// Whether this server can generate images (A-PROX `[image_generation]`).
  bool get supportsImageGeneration => capabilities.contains(AproxCapabilities.image);

  ServerProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? reasoning,
    Set<String>? capabilities,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      reasoning: reasoning ?? this.reasoning,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'reasoning': reasoning ? 1 : 0,
    };
  }

  factory ServerProfile.fromMap(Map<String, dynamic> map) {
    return ServerProfile(
      id: map['id'] as String? ?? const Uuid().v4(),
      name: map['name'] as String? ?? 'Unnamed',
      baseUrl: map['baseUrl'] as String? ?? '',
      apiKey: map['apiKey'] as String?,
      reasoning: (map['reasoning'] as int?) == 1,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ServerProfile.fromJson(String source) =>
      ServerProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ServerProfile(name: $name, baseUrl: $baseUrl)';
}
