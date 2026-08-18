import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';

class TokenSpeedBadge extends StatelessWidget {
  final double? tokensPerSecond;
  final int? totalTokens;
  final int? timeToFirstTokenMs;
  final double? generationTimeSec;

  const TokenSpeedBadge({
    super.key,
    this.tokensPerSecond,
    this.totalTokens,
    this.timeToFirstTokenMs,
    this.generationTimeSec,
  });

  @override
  Widget build(BuildContext context) {
    if (tokensPerSecond == null && totalTokens == null) {
      return const SizedBox.shrink();
    }

    final parts = <String>[];

    if (tokensPerSecond != null && tokensPerSecond! > 0) {
      parts.add('${tokensPerSecond!.toStringAsFixed(1)} tok/s');
    }

    if (totalTokens != null && totalTokens! > 0) {
      parts.add('$totalTokens tokens');
    }

    if (timeToFirstTokenMs != null && timeToFirstTokenMs! > 0) {
      parts.add('TTFT ${(timeToFirstTokenMs! / 1000).toStringAsFixed(2)}s');
    } else if (generationTimeSec != null && generationTimeSec! > 0) {
      parts.add('${generationTimeSec!.toStringAsFixed(1)}s');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant.withValues(alpha: 0.6) : AppTheme.lightSurfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder.withValues(alpha: 0.5) : AppTheme.lightBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed_rounded,
            size: 13,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
          const SizedBox(width: 5),
          Text(
            parts.join(' · '),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
