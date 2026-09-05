import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/chat/views/prompt_input_bar.dart';
import 'package:clan_ai/ui/features/roleplay/views/roleplay_drawer.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/parameter_tuning_sheet.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';
import 'package:clan_ai/ui/shared/connection_badge.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/alternate_greeting_selector.dart';
import 'package:clan_ai/ui/shared/mixins/auto_scroll_mixin.dart';
import 'package:clan_ai/ui/shared/avatar_utils.dart';
import 'package:clan_ai/ui/shared/delete_message_handler.dart';

class RoleplayScreen extends StatefulWidget {
  const RoleplayScreen({super.key});

  @override
  State<RoleplayScreen> createState() => _RoleplayScreenState();
}

class _RoleplayScreenState extends State<RoleplayScreen> with AutoScrollMixin {
  @override
  void initState() {
    super.initState();
    initAutoScroll();
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
        isRoleplay: true,
      ),
    );
  }

  Future<void> _handleDeleteMessage(int messageIndex, SettingsViewModel settingsVM) async {
    final roleplayVM = context.read<RoleplayViewModel>();
    await handleDeleteMessage(
      context: context,
      deleteFn: () => roleplayVM.deleteMessage(
        messageIndex: messageIndex,
        serverConfig: settingsVM.config,
        connection: settingsVM.connectionDetails,
        modelContextLength: settingsVM.getSelectedModelContextLength(),
      ),
      canUndo: roleplayVM.canUndo,
      undoFn: () async {
        await roleplayVM.undoDelete();
        scrollToBottom();
      },
      onThreadDeleted: () => scrollToBottom(false),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    final activeChar = context.read<RoleplayViewModel>().activeCharacter;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (activeChar != null) ...[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AvatarUtils.getColor(activeChar.name),
              ),
              child: activeChar.avatarData != null
                  ? ClipOval(
                      child: Image.memory(
                        activeChar.avatarData!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      AvatarUtils.getInitials(activeChar.name),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              activeChar.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start your roleplay...',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
            if (context.watch<SettingsViewModel>().config.healthStatus == ServerHealthStatus.offline)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.red.shade900 : Colors.red.shade100).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade700),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Server unreachable. Verify your endpoint in Settings.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          );
                        },
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                        child: const Text('Open Settings'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleplayVM = context.watch<RoleplayViewModel>();
    final settingsVM = context.watch<SettingsViewModel>();

    // Auto scroll down when assistant is actively streaming
    if (roleplayVM.isGenerating && !showScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom(false);
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
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: roleplayVM.messages.length,
                        itemBuilder: (context, index) {
                          final message = roleplayVM.messages[index];
                          final avatar = roleplayVM.activeCharacter?.avatarData;
                          final name = roleplayVM.activeCharacter?.name;
                          return MessageBubble(
                            key: ValueKey(message.id),
                            message: message,
                            messageIndex: index,
                            isLastMessage: index == roleplayVM.messages.length - 1,
                            characterAvatar: avatar,
                            characterName: name,
                            onRegenerate: () {
                              roleplayVM.regenerateMessage(
                                messageIndex: index,
                                serverConfig: settingsVM.config,
                                connection: settingsVM.connectionDetails,
                                modelContextLength: settingsVM.getSelectedModelContextLength(),
                              );
                            },
                            onEdit: (newPrompt) {
                              roleplayVM.editUserPrompt(
                                messageIndex: index,
                                newContent: newPrompt,
                                serverConfig: settingsVM.config,
                                connection: settingsVM.connectionDetails,
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
                                connection: settingsVM.connectionDetails,
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

                if (showScrollToBottom)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
                      foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      elevation: 4,
                      onPressed: () {
                        scrollToBottom(true);
                        setState(() => showScrollToBottom = false);
                      },
                      child: const Icon(Icons.arrow_downward_rounded, size: 18),
                    ),
                  ),
              ],
            ),
          ),

            // Alternate Greeting Selector
          if (roleplayVM.activeCharacter != null &&
              roleplayVM.activeCharacter!.alternateGreetings.isNotEmpty)
            AlternateGreetingSelector(
              greetings: roleplayVM.activeCharacter!.alternateGreetings,
              onSelectGreeting: () {
                roleplayVM.startRoleplay(
                  roleplayVM.activeCharacter!,
                  serverConfig: settingsVM.config,
                  connection: settingsVM.connectionDetails,
                  modelContextLength: settingsVM.getSelectedModelContextLength(),
                );
              },
            ),

          // Bottom Prompt Input Bar
          PromptInputBar(
            isGenerating: roleplayVM.isGenerating,
            onSend: (prompt) {
              roleplayVM.sendMessage(
                prompt: prompt,
                serverConfig: settingsVM.config,
                connection: settingsVM.connectionDetails,
                modelContextLength: settingsVM.getSelectedModelContextLength(),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                scrollToBottom(true);
              });
            },
            onStop: () => roleplayVM.stopGeneration(),
            onOpenParams: () => _openParameterSheet(context),
          ),
        ],
      ),
    );
  }
}
