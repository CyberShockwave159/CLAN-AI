import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/text_sanitizer.dart';
import 'package:clan_ai/ui/features/chat/widgets/code_block_view.dart';
import 'package:clan_ai/ui/features/chat/widgets/math_view.dart';

class DynamicMarkdownView extends StatelessWidget {
  final String data;
  final bool isUser;

  const DynamicMarkdownView({
    super.key,
    required this.data,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    final segments = TextSanitizer.parseSegments(data);

    final markdownStyle = MarkdownStyleSheet(
      p: TextStyle(
        fontSize: 15,
        height: 1.55,
        color: textColor,
      ),
      h1: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: textColor,
      ),
      h2: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: textColor,
      ),
      h3: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: textColor,
      ),
      blockquote: TextStyle(
        fontSize: 14.5,
        fontStyle: FontStyle.italic,
        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isDark ? AppTheme.accentPrimary.withValues(alpha: 0.6) : AppTheme.accentPrimary,
            width: 3,
          ),
        ),
      ),
      code: TextStyle(
        fontSize: 13.5,
        fontFamily: 'monospace',
        backgroundColor: isDark ? const Color(0xFF222634) : const Color(0xFFE2E8F0),
        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
      ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF141720) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      listBullet: TextStyle(
        fontSize: 15,
        color: isDark ? AppTheme.accentPrimary : AppTheme.accentPrimary,
      ),
      tableBorder: TableBorder.all(
        color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        width: 1,
        borderRadius: BorderRadius.circular(8),
      ),
      tableHead: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      tableBody: TextStyle(
        fontSize: 13.5,
        color: textColor,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((segment) {
        switch (segment.type) {
          case SegmentType.codeBlock:
            // Extract language and pure code from ```lang\ncode```
            final raw = segment.content;
            final firstNewline = raw.indexOf('\n');
            String lang = '';
            String code = raw;

            if (firstNewline != -1) {
              lang = raw.substring(3, firstNewline).trim();
              final lastFence = raw.lastIndexOf('```');
              if (lastFence > firstNewline) {
                code = raw.substring(firstNewline + 1, lastFence);
              } else {
                code = raw.substring(firstNewline + 1);
              }
            }
            return CodeBlockView(code: code, language: lang);

          case SegmentType.blockMath:
            return MathView(tex: segment.content, isBlock: true);

          case SegmentType.inlineMath:
            return MathView(tex: segment.content, isBlock: false);

          case SegmentType.markdown:
            return MarkdownBody(
              data: segment.content,
              styleSheet: markdownStyle,
              selectable: true,
            );
        }
      }).toList(),
    );
  }
}
