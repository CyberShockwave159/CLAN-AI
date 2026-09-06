import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/custom_theme_colors.dart';

/// Theme extension that provides theme-aware color lookups.
/// Added to all themes so widgets can access colors via
/// `Theme.of(context).extension<ClanThemeColors>()`.
class ClanThemeColors extends ThemeExtension<ClanThemeColors> {
  final Color bg;
  final Color surface;
  final Color surfaceVariant;
  final Color card;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color userBubble;
  final Color assistantBubble;

  const ClanThemeColors({
    required this.bg,
    required this.surface,
    required this.surfaceVariant,
    required this.card,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.userBubble,
    required this.assistantBubble,
  });

  @override
  ThemeExtension<ClanThemeColors> copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceVariant,
    Color? card,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? userBubble,
    Color? assistantBubble,
  }) {
    return ClanThemeColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      card: card ?? this.card,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      userBubble: userBubble ?? this.userBubble,
      assistantBubble: assistantBubble ?? this.assistantBubble,
    );
  }

  @override
  ThemeExtension<ClanThemeColors> lerp(ThemeExtension<ClanThemeColors>? other, double t) {
    if (other is! ClanThemeColors) return this;
    return ClanThemeColors(
      bg: Color.lerp(bg, other.bg, t) ?? bg,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t) ?? surfaceVariant,
      card: Color.lerp(card, other.card, t) ?? card,
      border: Color.lerp(border, other.border, t) ?? border,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      userBubble: Color.lerp(userBubble, other.userBubble, t) ?? userBubble,
      assistantBubble: Color.lerp(assistantBubble, other.assistantBubble, t) ?? assistantBubble,
    );
  }

  const ClanThemeColors.dark()
    : bg = AppTheme.darkBg,
      surface = AppTheme.darkSurface,
      surfaceVariant = AppTheme.darkSurfaceVariant,
      card = AppTheme.darkCard,
      border = AppTheme.darkBorder,
      textPrimary = AppTheme.darkTextPrimary,
      textSecondary = AppTheme.darkTextSecondary,
      textMuted = AppTheme.darkTextMuted,
      userBubble = AppTheme.darkUserBubble,
      assistantBubble = AppTheme.darkAssistantBubble;

  const ClanThemeColors.light()
    : bg = AppTheme.lightBg,
      surface = AppTheme.lightSurface,
      surfaceVariant = AppTheme.lightSurfaceVariant,
      card = AppTheme.lightCard,
      border = AppTheme.lightBorder,
      textPrimary = AppTheme.lightTextPrimary,
      textSecondary = AppTheme.lightTextSecondary,
      textMuted = AppTheme.lightTextMuted,
      userBubble = AppTheme.lightUserBubble,
      assistantBubble = AppTheme.lightAssistantBubble;

  factory ClanThemeColors.fromCustom(CustomThemeColors colors) {
    return ClanThemeColors(
      bg: colors.bg,
      surface: colors.surface,
      surfaceVariant: colors.surfaceVariant,
      card: colors.surface,
      border: colors.border,
      textPrimary: colors.textPrimary,
      textSecondary: colors.textSecondary,
      textMuted: colors.textMuted,
      userBubble: colors.userBubble,
      assistantBubble: colors.assistantBubble,
    );
  }
}

/// Extension on BuildContext for convenient theme color access.
extension ClanThemeColorsExtension on BuildContext {
  ClanThemeColors? get clanTheme => Theme.of(this).extension<ClanThemeColors>();
  Color get clanBg => clanTheme?.bg ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkBg : AppTheme.lightBg);
  Color get clanSurface => clanTheme?.surface ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkSurface : AppTheme.lightSurface);
  Color get clanSurfaceVariant => clanTheme?.surfaceVariant ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant);
  Color get clanCard => clanTheme?.card ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkCard : AppTheme.lightCard);
  Color get clanBorder => clanTheme?.border ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkBorder : AppTheme.lightBorder);
  Color get clanTextPrimary => clanTheme?.textPrimary ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary);
  Color get clanTextSecondary => clanTheme?.textSecondary ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary);
  Color get clanTextMuted => clanTheme?.textMuted ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted);
  Color get clanUserBubble => clanTheme?.userBubble ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkUserBubble : AppTheme.lightUserBubble);
  Color get clanAssistantBubble => clanTheme?.assistantBubble ?? (Theme.of(this).brightness == Brightness.dark ? AppTheme.darkAssistantBubble : AppTheme.lightAssistantBubble);
}
