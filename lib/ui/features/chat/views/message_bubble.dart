import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/widgets/markdown_body_view.dart';
import 'package:clan_ai/ui/features/chat/widgets/token_speed_badge.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final int messageIndex;
  final VoidCallback? onRegenerate;
  final Function(String newContent)? onEdit;
  final VoidCallback? onPreviousVariant;
  final VoidCallback? onNextVariant;
  final VoidCallback? onBranch;
  final VoidCallback? onDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.messageIndex,
    this.onRegenerate,
    this.onEdit,
    this.onPreviousVariant,
    this.onNextVariant,
    this.onBranch,
    this.onDelete,
  });

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Message copied to clipboard'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

 void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Prompt'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          minLines: 2,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Edit your prompt...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (controller.text.trim().isNotEmpty && onEdit != null) {
                onEdit!(controller.text.trim());
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, bool isFirstMessage) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: AppTheme.statusError,
          size: 40,
        ),
        title: isFirstMessage
            ? const Text('Delete Conversation?')
            : const Text('Delete Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFirstMessage
                  ? 'The first message will be removed and the entire conversation will be deleted. This cannot be undone.'
                  : 'The message and all messages after it will be removed. This cannot be undone.',
              style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
            ),
            if (message.content.length > 100) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${message.content.substring(0, 100)}...',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete?.call();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Role header & Avatar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isUser) ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.accentPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.smart_toy_rounded, size: 14, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  'CLAN AI',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 6),

          // Message Content Box
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isUser
                  ? (isDark ? AppTheme.darkUserBubble : AppTheme.lightUserBubble)
                  : (isDark ? AppTheme.darkAssistantBubble : AppTheme.lightAssistantBubble),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.content.isNotEmpty)
                  DynamicMarkdownView(data: message.content, isUser: isUser),

                // Streaming Cursor Animation
                if (message.status == MessageStatus.streaming)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.content.isEmpty)
                          Text(
                            'Thinking',
                            style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Container(
                          width: 8,
                          height: 15,
                          margin: const EdgeInsets.only(left: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentPrimary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Error Message Display
                if (message.status == MessageStatus.error && message.errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.statusError.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.statusError.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.statusError, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message.errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.statusError,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Token Performance Metrics (Assistant only)
          if (!isUser && message.status == MessageStatus.completed)
            TokenSpeedBadge(
              tokensPerSecond: message.tokensPerSecond,
              totalTokens: message.totalTokens,
              timeToFirstTokenMs: message.timeToFirstTokenMs,
              generationTimeSec: message.generationTimeSec,
            ),

          // Message Action Toolbar (Branch switchers, Copy, Edit, Regenerate)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branch version navigator: < 1 / 3 >
                if (message.totalVariants > 1) ...[
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: message.variantIndex > 0 ? onPreviousVariant : null,
                    tooltip: 'Previous version',
                  ),
                  Text(
                    '${message.variantIndex + 1} / ${message.totalVariants}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: message.variantIndex < message.totalVariants - 1 ? onNextVariant : null,
                    tooltip: 'Next version',
                  ),
                  const SizedBox(width: 6),
                ],

                // Copy Action
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  onPressed: () => _copyToClipboard(context),
                  tooltip: 'Copy',
                ),

                // Edit User Prompt Action
                if (isUser)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    onPressed: () => _showEditDialog(context),
                    tooltip: 'Edit prompt',
                  ),

                // Regenerate Assistant Response Action
                if (!isUser && message.status != MessageStatus.streaming)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    onPressed: onRegenerate,
                    tooltip: 'Regenerate response',
                  ),

                // Branch Conversation Action
                IconButton(
                  icon: const Icon(Icons.call_split_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  onPressed: message.status != MessageStatus.streaming ? onBranch : null,
                  tooltip: 'Branch conversation',
                ),

                // Delete Message Action
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  onPressed: message.status != MessageStatus.streaming
                      ? () => _showDeleteDialog(context, messageIndex == 0)
                      : null,
                  tooltip: 'Delete message',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
