import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/chat/views/prompt_input_bar.dart';
import 'package:clan_ai/ui/features/roleplay/views/roleplay_drawer.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/parameter_tuning_sheet.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';
import 'package:clan_ai/ui/shared/connection_badge.dart';

class RoleplayScreen extends StatefulWidget {
  const RoleplayScreen({super.key});

  @override
  State<RoleplayScreen> createState() => _RoleplayScreenState();
}

class _RoleplayScreenState extends State<RoleplayScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final isNearBottom = _scrollController.offset >= _scrollController.position.maxScrollExtent - 120;
      if (!isNearBottom && !_showScrollToBottom) {
        setState(() => _showScrollToBottom = true);
      } else if (isNearBottom && _showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
    }
  }

  void _scrollToBottom([bool animate = true]) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _openParameterSheet(BuildContext context) {
    final settingsVM = context.read<SettingsViewModel>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParameterTuningSheet(
        initialParams: settingsVM.config.defaultParams,
        onSave: (newParams) => settingsVM.updateDefaultParams(newParams),
      ),
    );
  }

  Future<void> _handleDeleteMessage(int messageIndex, SettingsViewModel settingsVM) async {
    final roleplayVM = context.read<RoleplayViewModel>();
    final shouldDeleteThread = await roleplayVM.deleteMessage(
      messageIndex: messageIndex,
      serverConfig: settingsVM.config,
      modelContextLength: settingsVM.getSelectedModelContextLength(),
    );
    if (shouldDeleteThread) {
      _scrollToBottom(false);
    }
  }

  Color _getAvatarColor(String name) {
    final colors = const [
      AppTheme.accentPrimary,
      AppTheme.accentSecondary,
      AppTheme.accentIndigo,
      AppTheme.accentCyan,
    ];
    final idx = name.codeUnitAt(0) % colors.length;
    return colors[idx];
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleplayVM = context.watch<RoleplayViewModel>();
    final settingsVM = context.watch<SettingsViewModel>();

    // Auto scroll down when assistant is actively streaming
    if (roleplayVM.isGenerating && !_showScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(false);
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, size: 22),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Characters',
          ),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            roleplayVM.activeCharacter?.name ?? 'Roleplay',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
          ),
        ),
        actions: [
          ConnectionBadge(
            status: settingsVM.config.healthStatus,
            latencyMs: settingsVM.config.latencyMs,
            onTap: () => settingsVM.testConnection(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            tooltip: 'Settings',
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: const RoleplayDrawer(),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                roleplayVM.messages.isEmpty
                    ? _buildEmptyState(context, isDark)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: roleplayVM.messages.length,
                        itemBuilder: (context, index) {
                          final message = roleplayVM.messages[index];
                          return MessageBubble(
                            key: ValueKey(message.id),
                            message: message,
                            messageIndex: index,
                            isLastMessage: index == roleplayVM.messages.length - 1,
                            onRegenerate: () {
                              roleplayVM.regenerateMessage(
                                messageIndex: index,
                                serverConfig: settingsVM.config,
                                modelContextLength: settingsVM.getSelectedModelContextLength(),
                              );
                            },
                            onEdit: (newPrompt) {
                              roleplayVM.editUserPrompt(
                                messageIndex: index,
                                newContent: newPrompt,
                                serverConfig: settingsVM.config,
                                modelContextLength: settingsVM.getSelectedModelContextLength(),
                              );
                            },
                            onEditAssistant: (newContent) {
                              roleplayVM.editAssistantMessage(
                                messageIndex: index,
                                newContent: newContent,
                              );
                            },
                            onBranch: () {
                              roleplayVM.branchConversation(
                                messageIndex: index,
                                serverConfig: settingsVM.config,
                                modelContextLength: settingsVM.getSelectedModelContextLength(),
                              );
                            },
                            onPreviousVariant: () {
                              roleplayVM.switchVariant(
                                messageIndex: index,
                                previous: true,
                              );
                            },
                            onNextVariant: () {
                              roleplayVM.switchVariant(
                                messageIndex: index,
                                previous: false,
                              );
                            },
                            onDelete: () {
                              if (settingsVM.config.confirmDeleteMessage) {
                                // Confirmation shown in MessageBubble
                              }
                              _handleDeleteMessage(index, settingsVM);
                            },
                          );
                        },
                      ),

                // Floating Scroll-to-Bottom FAB
                if (_showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                      foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      elevation: 4,
                      onPressed: () {
                        _scrollToBottom(true);
                        setState(() => _showScrollToBottom = false);
                      },
                      child: const Icon(Icons.arrow_downward_rounded, size: 18),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Prompt Input Bar
          PromptInputBar(
            isGenerating: roleplayVM.isGenerating,
            onSend: (prompt) {
              roleplayVM.sendMessage(
                prompt: prompt,
                serverConfig: settingsVM.config,
                modelContextLength: settingsVM.getSelectedModelContextLength(),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom(true);
              });
            },
            onStop: () => roleplayVM.stopGeneration(),
            onOpenParams: () => _openParameterSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Character avatar if available
          if (context.read<RoleplayViewModel>().activeCharacter != null) ...[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getAvatarColor(context.read<RoleplayViewModel>().activeCharacter!.name),
              ),
              child: context.read<RoleplayViewModel>().activeCharacter!.avatarData != null
                  ? ClipOval(
                      child: Image.memory(
                        context.read<RoleplayViewModel>().activeCharacter!.avatarData!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      _getInitials(context.read<RoleplayViewModel>().activeCharacter!.name),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              context.read<RoleplayViewModel>().activeCharacter!.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Start your roleplay...',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
