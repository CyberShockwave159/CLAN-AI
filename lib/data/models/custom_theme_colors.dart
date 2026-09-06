import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';

/// Custom theme colors that can be persisted and applied as a theme preset.
class CustomThemeColors {
  final Color bg;
  final Color surface;
  final Color surfaceVariant;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color userBubble;
  final Color assistantBubble;

  const CustomThemeColors({
    required this.bg,
    required this.surface,
    required this.surfaceVariant,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.userBubble,
    required this.assistantBubble,
  });

  CustomThemeColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceVariant,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? userBubble,
    Color? assistantBubble,
  }) {
    return CustomThemeColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      userBubble: userBubble ?? this.userBubble,
      assistantBubble: assistantBubble ?? this.assistantBubble,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bg': bg.value,
      'surface': surface.value,
      'surfaceVariant': surfaceVariant.value,
      'border': border.value,
      'textPrimary': textPrimary.value,
      'textSecondary': textSecondary.value,
      'textMuted': textMuted.value,
      'userBubble': userBubble.value,
      'assistantBubble': assistantBubble.value,
    };
  }

  factory CustomThemeColors.fromMap(Map<String, dynamic> map) {
    return CustomThemeColors(
      bg: Color(map['bg'] as int),
      surface: Color(map['surface'] as int),
      surfaceVariant: Color(map['surfaceVariant'] as int),
      border: Color(map['border'] as int),
      textPrimary: Color(map['textPrimary'] as int),
      textSecondary: Color(map['textSecondary'] as int),
      textMuted: Color(map['textMuted'] as int),
      userBubble: Color(map['userBubble'] as int),
      assistantBubble: Color(map['assistantBubble'] as int),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CustomThemeColors.fromJson(String source) =>
      CustomThemeColors.fromMap(jsonDecode(source) as Map<String, dynamic>);

  // Presets

  /// Warm preset — warm browns, amber tones, cream backgrounds.
  static const CustomThemeColors warm = CustomThemeColors(
    bg: Color(0xFF1A1410),
    surface: Color(0xFF241E18),
    surfaceVariant: Color(0xFF332B22),
    border: Color(0xFF4A3F34),
    textPrimary: Color(0xFFF5E6D3),
    textSecondary: Color(0xFFC4A882),
    textMuted: Color(0xFF96826B),
    userBubble: Color(0xFF3D3228),
    assistantBubble: Color(0xFF241E18),
  );

  /// Cool preset — deep blues, slate tones, icy accents.
  static const CustomThemeColors cool = CustomThemeColors(
    bg: Color(0xFF0D1B2A),
    surface: Color(0xFF1B2838),
    surfaceVariant: Color(0xFF243447),
    border: Color(0xFF2D4A5E),
    textPrimary: Color(0xFFE0ECF5),
    textSecondary: Color(0xFF9FB4C7),
    textMuted: Color(0xFF6B8AA3),
    userBubble: Color(0xFF243447),
    assistantBubble: Color(0xFF1B2838),
  );

  /// Pastel preset — soft purples, lavenders, gentle tones.
  static const CustomThemeColors pastel = CustomThemeColors(
    bg: Color(0xFF1E1528),
    surface: Color(0xFF281E35),
    surfaceVariant: Color(0xFF352A45),
    border: Color(0xFF4A3D5C),
    textPrimary: Color(0xFFF0E8F8),
    textSecondary: Color(0xFFB8A8D0),
    textMuted: Color(0xFF8A78A8),
    userBubble: Color(0xFF352A45),
    assistantBubble: Color(0xFF281E35),
  );

  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomThemeColors &&
          runtimeType == other.runtimeType &&
          bg == other.bg &&
          surface == other.surface &&
          surfaceVariant == other.surfaceVariant &&
          border == other.border &&
          textPrimary == other.textPrimary &&
          textSecondary == other.textSecondary &&
          textMuted == other.textMuted &&
          userBubble == other.userBubble &&
          assistantBubble == other.assistantBubble;

  int get hashCode =>
      bg.hashCode ^
      surface.hashCode ^
      surfaceVariant.hashCode ^
      border.hashCode ^
      textPrimary.hashCode ^
      textSecondary.hashCode ^
      textMuted.hashCode ^
      userBubble.hashCode ^
      assistantBubble.hashCode;
}
