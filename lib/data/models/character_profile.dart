import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/constants/aprox_capabilities.dart';

class CharacterProfile {
  final String id;
  final String name;
  final String personality;
  final String firstMessage;
  final String? setting;
  final String? userPersona;
  final String? personaName;
  final String? personaDescription;
  final Uint8List? avatarData;
  final bool isFavorite;
  final String? systemPrompt;
  final String? postHistoryInstructions;
  final List<String> alternateGreetings;

  /// Canonical physical description of the character, used to keep generated
  /// scene images consistent across generations.
  ///
  /// Appearance only, deliberately: wardrobe and setting change with the scene,
  /// so pinning them would fight the story. Free-text (editable in
  /// CharacterEditDialog, LLM-drafted once with a review step) and mirrored into
  /// the A-PROX RAG store so it can be retrieved alongside conversation
  /// memories.
  final String? appearance;

  /// Approved reference portrait for image generation, stored inline as a
  /// downscaled JPEG.
  ///
  /// Attached to scene-image requests as an `image_url` content part so A-PROX
  /// runs its image-to-image path. That path is Qwen-Image-Edit-style reference
  /// conditioning (the reference is fed to the text encoder, not used as a
  /// latent init), which is what preserves a character's face across scenes.
  /// Distinct from [avatarData], which is the character's card avatar.
  final Uint8List? identityPortraitData;

  /// Visual style this character is rendered in, or [VisualTheme.none] when the
  /// user hasn't chosen one (in which case no style directive is sent).
  final VisualTheme visualTheme;

  final DateTime createdAt;
  final DateTime updatedAt;

  CharacterProfile({
    String? id,
    required this.name,
    required this.personality,
    required this.firstMessage,
    this.setting,
    this.userPersona,
    this.personaName,
    this.personaDescription,
    this.avatarData,
    this.isFavorite = false,
    this.systemPrompt,
    this.postHistoryInstructions,
    List<String>? alternateGreetings,
    this.appearance,
    this.identityPortraitData,
    this.visualTheme = VisualTheme.none,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        alternateGreetings = alternateGreetings ?? [];

  /// Whether this character has a description of its physical appearance, used
  /// to decide whether the one-time LLM draft is worth offering.
  bool get hasAppearance =>
      appearance != null && appearance!.trim().isNotEmpty;

  /// Whether an identity reference image is available for scene generation.
  bool get hasIdentityReference =>
      (identityPortraitData != null && identityPortraitData!.isNotEmpty) ||
      (avatarData != null && avatarData!.isNotEmpty);

  /// True when the character needs a reference portrait generated before scene
  /// images can keep a consistent face.
  bool get needsIdentityPortrait =>
      (identityPortraitData == null || identityPortraitData!.isEmpty) &&
      (avatarData == null || avatarData!.isEmpty);

  CharacterProfile copyWith({
    String? id,
    String? name,
    String? personality,
    String? firstMessage,
    String? setting,
    String? userPersona,
    String? personaName,
    String? personaDescription,
    Uint8List? avatarData,
    bool? isFavorite,
    String? systemPrompt,
    String? postHistoryInstructions,
    List<String>? alternateGreetings,
    String? appearance,
    Uint8List? identityPortraitData,
    VisualTheme? visualTheme,
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
      personaName: personaName ?? this.personaName,
      personaDescription: personaDescription ?? this.personaDescription,
      avatarData: avatarData ?? this.avatarData,
      isFavorite: isFavorite ?? this.isFavorite,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      postHistoryInstructions: postHistoryInstructions ?? this.postHistoryInstructions,
      alternateGreetings: alternateGreetings ?? this.alternateGreetings,
      appearance: appearance ?? this.appearance,
      identityPortraitData: identityPortraitData ?? this.identityPortraitData,
      visualTheme: visualTheme ?? this.visualTheme,
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
      'persona_name': personaName,
      'persona_description': personaDescription,
      'avatar_data': avatarData != null ? base64Encode(avatarData!) : null,
      'is_favorite': isFavorite ? 1 : 0,
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistoryInstructions,
      'alternate_greetings': jsonEncode(alternateGreetings),
      'appearance': appearance,
      'identity_portrait_data': identityPortraitData != null
          ? base64Encode(identityPortraitData!)
          : null,
      'visual_theme': visualTheme.wireValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CharacterProfile.fromMap(Map<String, dynamic> map) {
    List<String> altGreetings = [];
    final greetingsJson = map['alternate_greetings'] as String?;
    if (greetingsJson != null && greetingsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(greetingsJson) as List<dynamic>;
        altGreetings = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    return CharacterProfile(
      id: map['id'] as String? ?? const Uuid().v4(),
      name: map['name'] as String? ?? 'Unknown',
      personality: map['personality'] as String? ?? '',
      firstMessage: map['first_message'] as String? ?? '',
      setting: map['setting'] as String?,
      userPersona: map['user_persona'] as String?,
      personaName: map['persona_name'] as String?,
      personaDescription: map['persona_description'] as String?,
      avatarData: _decodeBytes(map['avatar_data']),
      isFavorite: (map['is_favorite'] as int?) == 1,
      systemPrompt: map['system_prompt'] as String?,
      postHistoryInstructions: map['post_history_instructions'] as String?,
      alternateGreetings: altGreetings,
      appearance: map['appearance'] as String?,
      identityPortraitData: _decodeBytes(map['identity_portrait_data']),
      visualTheme: VisualTheme.fromWire(map['visual_theme'] as String?),
      // Tolerate missing or non-string timestamps: one malformed row must not
      // take down the whole character list.
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
    );
  }

  /// Parses a stored ISO-8601 timestamp, falling back to now.
  static DateTime _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return DateTime.now();
    return DateTime.tryParse(value) ?? DateTime.now();
  }

  /// Accepts either a raw BLOB (from SQLite) or a base64 string (from JSON
  /// export), mirroring how `avatar_data` has always been read.
  static Uint8List? _decodeBytes(dynamic value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is String) {
      if (value.isEmpty) return null;
      try {
        return base64Decode(value);
      } catch (_) {
        return null;
      }
    }
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  Map<String, dynamic> toJson() => toMap();

  factory CharacterProfile.fromJson(Map<String, dynamic> json) => CharacterProfile.fromMap(json);
}
