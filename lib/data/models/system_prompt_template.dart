import 'dart:convert';

class SystemPromptTemplate {
  final String name;
  final String content;
  final DateTime createdAt;

  SystemPromptTemplate({
    required this.name,
    required this.content,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  SystemPromptTemplate copyWith({
    String? name,
    String? content,
    DateTime? createdAt,
  }) {
    return SystemPromptTemplate(
      name: name ?? this.name,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SystemPromptTemplate.fromMap(Map<String, dynamic> map) {
    return SystemPromptTemplate(
      name: map['name'] as String,
      content: map['content'] as String,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory SystemPromptTemplate.fromJson(String source) =>
      SystemPromptTemplate.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() => 'SystemPromptTemplate(name: $name, content: $content)';
}
