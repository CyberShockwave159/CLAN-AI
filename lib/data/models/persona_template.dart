import 'dart:convert';
import 'package:uuid/uuid.dart';

class PersonaTemplate {
  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  PersonaTemplate({
    String? id,
    required this.name,
    required this.description,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  PersonaTemplate copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PersonaTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'persona_text': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PersonaTemplate.fromMap(Map<String, dynamic> map) {
    return PersonaTemplate(
      id: map['id'] as String? ?? const Uuid().v4(),
      name: map['name'] as String? ?? 'Untitled',
      description: map['persona_text'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory PersonaTemplate.fromJson(String source) =>
      PersonaTemplate.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() => 'PersonaTemplate(name: $name, description: ${description.length} chars)';
}
