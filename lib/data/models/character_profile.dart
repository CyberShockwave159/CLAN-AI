import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

class CharacterProfile {
  final String id;
  final String name;
  final String personality;
  final String firstMessage;
  final String? setting;
  final String? userPersona;
  final Uint8List? avatarData;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  CharacterProfile({
    String? id,
    required this.name,
    required this.personality,
    required this.firstMessage,
    this.setting,
    this.userPersona,
    this.avatarData,
    this.isFavorite = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  CharacterProfile copyWith({
    String? id,
    String? name,
    String? personality,
    String? firstMessage,
    String? setting,
    String? userPersona,
    Uint8List? avatarData,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CharacterProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      personality: personality ?? this.personality,
      firstMessage: firstMessage ?? this.firstMessage,
      setting: setting ?? this.setting,
      userPersona: userPersona ?? this.userPersona,
      avatarData: avatarData ?? this.avatarData,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'personality': personality,
      'first_message': firstMessage,
      'setting': setting,
      'user_persona': userPersona,
      'avatar_data': avatarData != null ? base64Encode(avatarData!) : null,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CharacterProfile.fromMap(Map<String, dynamic> map) {
    return CharacterProfile(
      id: map['id'] as String? ?? const Uuid().v4(),
      name: map['name'] as String? ?? 'Unknown',
      personality: map['personality'] as String? ?? '',
      firstMessage: map['first_message'] as String? ?? '',
      setting: map['setting'] as String?,
      userPersona: map['user_persona'] as String?,
      avatarData: map['avatar_data'] != null
          ? base64Decode(map['avatar_data'] as String)
          : null,
      isFavorite: (map['is_favorite'] as int?) == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory CharacterProfile.fromJson(Map<String, dynamic> json) => CharacterProfile.fromMap(json);
}
