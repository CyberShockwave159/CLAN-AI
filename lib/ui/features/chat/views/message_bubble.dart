import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/widgets/markdown_body_view.dart';
import 'package:clan_ai/ui/features/chat/widgets/token_speed_badge.dart';
import 'package:clan_ai/ui/features/chat/widgets/reasoning_block.dart';
import 'package:clan_ai/ui/shared/avatar_utils.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final int messageIndex;
  final bool isLastMessage;
  final VoidCallback? onRegenerate;
  final Function(String newContent)? onEdit;
  final VoidCallback? onPreviousVariant;
  final VoidCallback? onNextVariant;
  final VoidCallback? onBranch;
  final VoidCallback? onDelete;
  final Function(String newContent)? onEditAssistant;
  final Uint8List? characterAvatar;
  final String? characterName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.messageIndex,
    this.isLastMessage = false,
    this.onRegenerate,
    this.onEdit,
    this.onPreviousVariant,
    this.onNextVariant,
    this.onBranch,
    this.onDelete,
    this.onEditAssistant,
    this.characterAvatar,
    this.characterName,
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

  Color _getAvatarColor(String name) => AvatarUtils.getColor(name);

  String _getInitials(String name) => AvatarUtils.getInitials(name);

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

  void _showEditAssistantDialog(BuildContext context) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Response'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          minLines: 2,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Edit the assistant response...',
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
              if (controller.text.trim().isNotEmpty && onEditAssistant != null) {
                onEditAssistant!(controller.text.trim());
              }
            },
            child: const Text('Save'),
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
            if (message.content.length > messagePreviewLen) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${message.content.substring(0, messagePreviewLen)}...',
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

  void _showMemoriesDialog(BuildContext context, List<String> memories) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('RAG Memories Used'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: memories.length,
            itemBuilder: (ctx, index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Memory ${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      memories[index],
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textScaler = MediaQuery.of(context).textScaler;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: defaultBubblePadding, vertical: 8),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Role header & Avatar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isUser) ...[
                if (characterAvatar != null)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: MemoryImage(characterAvatar!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else if (characterName != null)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _getAvatarColor(characterName!),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _getInitials(characterName!),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
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
                  characterName ?? 'CLAN AI',
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
          LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth > maxBubbleWidth ? maxBubbleWidth : constraints.maxWidth * 0.88;
              return Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
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
                    if (message.reasoningContent.isNotEmpty && !isUser)
                      ReasoningBlock(
                        reasoningContent: message.reasoningContent,
                        status: message.status,
                        isUser: isUser,
                      ),

                    if (message.content.isNotEmpty)
                      DynamicMarkdownView(data: message.content, isUser: isUser),

                    // Streaming Cursor Animation
                    if (message.status == MessageStatus.streaming)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (message.content.isEmpty && message.reasoningContent.isEmpty)
                              Text(
                                'Thinking',
                                style: TextStyle(
                                  fontSize: textScaler.scale(14),
                                  fontStyle: FontStyle.italic,
                                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                ),
                              ),
                            if (message.content.isEmpty && message.reasoningContent.isEmpty)
                              const SizedBox(width: 4),
                            if (message.content.isNotEmpty || message.reasoningContent.isEmpty)
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
              );
            },
          ),

          // Token Performance Metrics (Assistant only)
          if (!isUser && message.status == MessageStatus.completed) ...[
            if (message.ragMemoryCount != null && message.ragMemoryCount! > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () {
                    if (message.ragMemoryContents != null && message.ragMemoryContents!.isNotEmpty) {
                      final memories = List<String>.from(jsonDecode(message.ragMemoryContents!));
                      _showMemoriesDialog(context, memories);
                    }
                  },
                  child: Tooltip(
                    message: 'Tap to view ${message.ragMemoryCount} memory${message.ragMemoryCount! == 1 ? '' : 's'} retrieved via RAG',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.memory_rounded,
                          size: 12,
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${message.ragMemoryCount}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            TokenSpeedBadge(
              tokensPerSecond: message.tokensPerSecond,
              totalTokens: message.totalTokens,
              timeToFirstTokenMs: message.timeToFirstTokenMs,
              generationTimeSec: message.generationTimeSec,
            ),
          ],

          // Message Action Toolbar (Branch switchers, Copy, Edit, Regenerate)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branch version navigator: < 1 / 3 >
                if (message.totalVariants > 1) ...[
                  Semantics(
                    label: 'Previous version',
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: message.variantIndex > 0 ? onPreviousVariant : null,
                      tooltip: 'Previous version',
                    ),
                  ),
                  Text(
                    '${message.variantIndex + 1} / ${message.totalVariants}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                  Semantics(
                    label: 'Next version',
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: message.variantIndex < message.totalVariants - 1 ? onNextVariant : null,
                      tooltip: 'Next version',
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Copy Action
                Semantics(
                  label: 'Copy message',
                  child: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    onPressed: () => _copyToClipboard(context),
                    tooltip: 'Copy',
                  ),
                ),

                // Edit User Prompt Action
                if (isUser)
                  Semantics(
                    label: 'Edit prompt',
                    child: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      onPressed: () => _showEditDialog(context),
                      tooltip: 'Edit prompt',
                    ),
                  ),

                  // Regenerate Assistant Response Action
                  if (!isUser && message.status != MessageStatus.streaming)
                    Semantics(
                      label: 'Regenerate response',
                      child: IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        onPressed: onRegenerate,
                        tooltip: 'Regenerate response',
                      ),
                    ),

                // Edit Assistant Response Action (last message only)
                if (!isUser &&
                    message.status != MessageStatus.streaming &&
                    isLastMessage &&
                    onEditAssistant != null)
                  Semantics(
                    label: 'Edit response',
                    child: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      onPressed: () => _showEditAssistantDialog(context),
                      tooltip: 'Edit response',
                    ),
                  ),

                // Branch Conversation Action
                Semantics(
                  label: 'Branch conversation',
                  child: IconButton(
                    icon: const Icon(Icons.call_split_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    onPressed: message.status != MessageStatus.streaming ? onBranch : null,
                    tooltip: 'Branch conversation',
                  ),
                ),

                // Delete Message Action
                Semantics(
                  label: 'Delete message',
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    onPressed: message.status != MessageStatus.streaming
                        ? () => _showDeleteDialog(context, messageIndex == 0)
                        : null,
                    tooltip: 'Delete message',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
