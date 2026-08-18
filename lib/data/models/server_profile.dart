import 'dart:convert';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:uuid/uuid.dart';

class ServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final ApiProtocol protocol;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServerProfile({
    String? id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    required this.protocol,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ServerProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    ApiProtocol? protocol,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      protocol: protocol ?? this.protocol,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'protocol': protocol.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ServerProfile.fromMap(Map<String, dynamic> map) {
    return ServerProfile(
      id: map['id'] as String,
      name: map['name'] as String? ?? 'Unnamed',
      baseUrl: map['baseUrl'] as String? ?? '',
      apiKey: map['apiKey'] as String?,
      protocol: ApiProtocol.values.firstWhere(
        (p) => p.name == (map['protocol'] as String?),
        orElse: () => ApiProtocol.openAi,
      ),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ServerProfile.fromJson(String source) =>
      ServerProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ServerProfile(name: $name, baseUrl: $baseUrl)';
}
