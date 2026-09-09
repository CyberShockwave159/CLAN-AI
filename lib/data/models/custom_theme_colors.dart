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

  /// Warm preset — volcanic: deep charcoals, molten reds, fiery oranges.
  static const CustomThemeColors warm = CustomThemeColors(
    bg: Color(0xFF1A100E),
    surface: Color(0xFF241814),
    surfaceVariant: Color(0xFF332018),
    border: Color(0xFF5C3A28),
    textPrimary: Color(0xFFF5E0D0),
    textSecondary: Color(0xFFD4A080),
    textMuted: Color(0xFFA07060),
    userBubble: Color(0xFF4A2818),
    assistantBubble: Color(0xFF241814),
  );

  /// Cool preset — glacier: deep night skies, crisp icy blues, frost whites.
  static const CustomThemeColors cool = CustomThemeColors(
    bg: Color(0xFF0A1628),
    surface: Color(0xFF122040),
    surfaceVariant: Color(0xFF1A2C50),
    border: Color(0xFF2A4A6A),
    textPrimary: Color(0xFFE8F4FF),
    textSecondary: Color(0xFFA0C8E8),
    textMuted: Color(0xFF6AA0C0),
    userBubble: Color(0xFF1E3A5F),
    assistantBubble: Color(0xFF122040),
  );

  /// Pastel preset — light sky blues, rose pinks, cream greens.
  static const CustomThemeColors pastel = CustomThemeColors(
    bg: Color(0xFFF5F0FA),
    surface: Color(0xFFEDE5F5),
    surfaceVariant: Color(0xFFE0D5EC),
    border: Color(0xFFC8B8DC),
    textPrimary: Color(0xFF2A2040),
    textSecondary: Color(0xFF5A4A70),
    textMuted: Color(0xFF8A7A9A),
    userBubble: Color(0xFFE8D5F0),
    assistantBubble: Color(0xFFEDE5F5),
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
