import 'dart:convert';
import 'package:uuid/uuid.dart';

class ServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final bool reasoning;

  ServerProfile({
    String? id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    this.reasoning = false,
  }) : id = id ?? const Uuid().v4();

  ServerProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? reasoning,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      reasoning: reasoning ?? this.reasoning,
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
