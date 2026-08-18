import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:clan_ai/core/constants/app_theme.dart';

class MathView extends StatelessWidget {
  final String tex;
  final bool isBlock;

  const MathView({
    super.key,
    required this.tex,
    this.isBlock = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

    try {
      final mathWidget = Math.tex(
        tex,
        mathStyle: isBlock ? MathStyle.display : MathStyle.text,
        textStyle: TextStyle(
          fontSize: isBlock ? 16 : 14,
          color: color,
        ),
        onErrorFallback: (err) => Text(
          isBlock ? '\$\$\n$tex\n\$\$' : '\$$tex\$',
          style: TextStyle(
            color: AppTheme.statusError,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      );

      if (isBlock) {
        return Container(
          width: double.infinity,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurfaceVariant.withValues(alpha: 0.5) : AppTheme.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder.withValues(alpha: 0.5) : AppTheme.lightBorder,
              width: 0.8,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: mathWidget,
          ),
        );
      }

      return mathWidget;
    } catch (_) {
      return Text(
        isBlock ? '\$\$\n$tex\n\$\$' : '\$$tex\$',
        style: TextStyle(color: color),
      );
    }
  }
}
