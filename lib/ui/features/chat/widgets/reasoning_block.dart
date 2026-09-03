import 'package:flutter/material.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/chat_message.dart';

class ReasoningBlock extends StatefulWidget {
  final String reasoningContent;
  final MessageStatus status;
  final bool isUser;

  const ReasoningBlock({
    super.key,
    required this.reasoningContent,
    required this.status,
    required this.isUser,
  });

  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasContent = widget.reasoningContent.isNotEmpty;

    return Semantics(
      button: true,
      label: _isExpanded ? 'Collapse thinking process' : 'Expand thinking process',
      child: InkWell(
        onTap: () {
          if (hasContent) {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: (isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant)
                .withValues(alpha: _isExpanded ? 0.85 : 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? AppTheme.darkBorder.withValues(alpha: 0.6)
                  : AppTheme.lightBorder.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.psychology_rounded,
                    size: 15,
                    color: widget.status == MessageStatus.streaming
                        ? AppTheme.accentPrimary
                        : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.status == MessageStatus.streaming ? 'Thinking...' : 'Thinking',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.status == MessageStatus.streaming
                          ? (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                          : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                    ),
                  ),
                  const Spacer(),
                  if (hasContent)
                    Icon(
                      _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 16,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                ],
              ),
              if (_isExpanded && hasContent) ...[
                const SizedBox(height: 6),
                Divider(
                  height: 1,
                  thickness: 0.8,
                  color: (isDark ? AppTheme.darkBorder : AppTheme.lightBorder).withValues(alpha: 0.4),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  widget.reasoningContent,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
