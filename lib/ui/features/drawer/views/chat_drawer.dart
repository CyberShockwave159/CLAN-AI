import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';

class ChatDrawer extends StatefulWidget {
  const ChatDrawer({super.key});

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  final Set<String> _expandedLineage = {};

  void _toggleLineage(String threadId) {
    setState(() {
      if (_expandedLineage.contains(threadId)) {
        _expandedLineage.remove(threadId);
      } else {
        _expandedLineage.add(threadId);
      }
    });
  }

  Widget _buildLineageChain(BuildContext context, ChatThread thread, bool isDark) {
    final lineageFuture = LocalDatabase.instance.getThreadLineage(thread.id);

    return FutureBuilder<List<ChatThread>>(
      future: lineageFuture,
      builder: (ctx, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final lineage = snapshot.data!;
        final needsEllipsis = lineage.length > 3;
        final displayed = needsEllipsis ? lineage.sublist(0, 3) : lineage;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...displayed.reversed.map((parentThread) {
                return Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            context.read<ChatViewModel>().selectThread(parentThread);
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            parentThread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (needsEllipsis)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    '...',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, ChatThread thread, ChatViewModel chatVM) {
    final controller = TextEditingController(text: thread.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter title...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                chatVM.renameThread(thread.id, controller.text.trim());
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, ChatThread thread, ChatViewModel chatVM) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: Text('Are you sure you want to delete "${thread.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.statusError),
            onPressed: () {
              chatVM.deleteThread(thread.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatVM = context.watch<ChatViewModel>();
    final settingsVM = context.watch<SettingsViewModel>();

    return Drawer(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with "New Chat" Action
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('New Chat', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(
                          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                        ),
                      ),
                      onPressed: () async {
                        final settingsVM = context.read<SettingsViewModel>();
                        chatVM.createNewThread(systemPrompt: settingsVM.config.systemPrompt);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (val) => chatVM.setSearchQuery(val),
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Thread List
            Expanded(
              child: chatVM.filteredThreads.isEmpty
                  ? Center(
                      child: Text(
                        chatVM.searchQuery.isEmpty ? 'No chats yet' : 'No matching chats',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                       itemCount: chatVM.filteredThreads.length,
                       padding: const EdgeInsets.symmetric(horizontal: 8),
                       itemBuilder: (context, index) {
                         final thread = chatVM.filteredThreads[index];
                         final isActive = thread.id == chatVM.activeThread?.id;
                         final hasBranchParent = thread.branchFromThreadId != null;

                        return Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? (isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isActive
                                    ? Border.all(color: AppTheme.accentPrimary.withValues(alpha: 0.4), width: 1)
                                    : null,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: Column(
                                  children: [
                                    ListTile(
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                      leading: hasBranchParent
                                          ? GestureDetector(
                                              onTap: () => _toggleLineage(thread.id),
                                              child: Icon(
                                                _expandedLineage.contains(thread.id)
                                                     ? Icons.keyboard_arrow_down_rounded
                                                     : Icons.chevron_right_rounded,
                                                size: 16,
                                                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                              ),
                                            )
                                          : Icon(
                                              Icons.chat_bubble_outline_rounded,
                                              size: 18,
                                              color: isActive
                                                  ? AppTheme.accentPrimary
                                                  : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                                            ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              thread.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                              ),
                                            ),
                                          ),
                                          if (hasBranchParent) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.call_split_rounded,
                                              size: 14,
                                              color: isDark ? AppTheme.accentPrimary : AppTheme.darkBorder,
                                            ),
                                          ],
                                        ],
                                      ),
                                      onTap: () {
                                        chatVM.selectThread(thread);
                                        Navigator.of(context).pop();
                                      },
                                      trailing: isActive
                                          ? PopupMenuButton<String>(
                                              icon: Icon(
                                                Icons.more_vert_rounded,
                                                size: 18,
                                                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                              ),
                                              onSelected: (action) {
                                                if (action == 'rename') {
                                                  _showRenameDialog(context, thread, chatVM);
                                                } else if (action == 'delete') {
                                                  _showDeleteDialog(context, thread, chatVM);
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                const PopupMenuItem(
                                                  value: 'rename',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.edit_outlined, size: 18),
                                                      SizedBox(width: 8),
                                                      Text('Rename'),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.statusError),
                                                      SizedBox(width: 8),
                                                      Text('Delete', style: TextStyle(color: AppTheme.statusError)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            )
                                          : null,
                                    ),
                                    if (_expandedLineage.contains(thread.id) && thread.branchFromThreadId != null)
                                      _buildLineageChain(context, thread, isDark),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1, indent: 8, endIndent: 8),
                          ],
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // Footer with Settings Action
            ListTile(
              leading: const Icon(Icons.settings_outlined, size: 20),
              title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(
                settingsVM.config.name,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
