import 'dart:convert';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:uuid/uuid.dart';

class ServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final ApiProtocol protocol;

  ServerProfile({
    String? id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    required this.protocol,
  }) : id = id ?? const Uuid().v4();

  ServerProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    ApiProtocol? protocol,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      protocol: protocol ?? this.protocol,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'protocol': protocol.name,
    };
  }

  factory ServerProfile.fromMap(Map<String, dynamic> map) {
    return ServerProfile(
      id: map['id'] as String? ?? const Uuid().v4(),
      name: map['name'] as String? ?? 'Unnamed',
      baseUrl: map['baseUrl'] as String? ?? '',
      apiKey: map['apiKey'] as String?,
      protocol: ApiProtocol.values.firstWhere(
        (p) => p.name == (map['protocol'] as String?),
        orElse: () => ApiProtocol.openAi,
      ),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ServerProfile.fromJson(String source) =>
      ServerProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ServerProfile(name: $name, baseUrl: $baseUrl)';
}
