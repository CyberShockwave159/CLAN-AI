import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';

import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/chat/views/prompt_input_bar.dart';
import 'package:clan_ai/ui/features/roleplay/views/roleplay_drawer.dart';
import 'package:clan_ai/ui/features/roleplay/view_models/roleplay_view_model.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/parameter_tuning_sheet.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';
import 'package:clan_ai/ui/shared/connection_badge.dart';
import 'package:clan_ai/ui/features/roleplay/widgets/alternate_greeting_selector.dart';
import 'package:clan_ai/ui/shared/mixins/auto_scroll_mixin.dart';
import 'package:clan_ai/ui/shared/avatar_utils.dart';
import 'package:clan_ai/ui/shared/delete_message_handler.dart';
import 'package:clan_ai/ui/shared/widgets/desktop_keyboard_shortcuts.dart';

class RoleplayScreen extends StatefulWidget {
  final VoidCallback? themeRefresh;

  const RoleplayScreen({super.key, this.themeRefresh});

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

  MessageDebugContext? _buildDebugContext(ChatMessage message, RoleplayViewModel roleplayVM, SettingsViewModel settingsVM) {
    if (message.role != MessageRole.assistant || message.status != MessageStatus.completed) return null;

    final thread = roleplayVM.activeThread;
    final systemPrompt = thread?.systemPrompt ?? settingsVM.config.systemPrompt;
    final params = settingsVM.config.defaultParams;
    final ragMemories = message.ragMemoryContents != null && message.ragMemoryContents!.isNotEmpty
        ? List<String>.from(jsonDecode(message.ragMemoryContents!))
        : <String>[];

    return MessageDebugContext(
      model: settingsVM.config.selectedModel ?? 'unknown',
      systemPrompt: systemPrompt,
      ragMemories: ragMemories,
      temperature: params.temperature,
      topP: params.topP,
      topK: params.topK,
      contextSize: params.contextSize,
      presencePenalty: params.presencePenalty,
      frequencyPenalty: params.frequencyPenalty,
      repeatPenalty: params.repeatPenalty,
      timeToFirstTokenMs: message.timeToFirstTokenMs,
      tokensPerSecond: message.tokensPerSecond,
      totalTokens: message.totalTokens,
      generationTimeSec: message.generationTimeSec,
    );
  }

  Widget _buildEmptyState(BuildContext context, Color titleColor) {
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
                color: context.clanTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start your roleplay...',
              style: TextStyle(
                fontSize: 13,
                color: context.clanTextMuted,
              ),
            ),
            if (context.watch<SettingsViewModel>().config.healthStatus == ServerHealthStatus.offline)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (Theme.of(context).brightness == Brightness.dark ? Colors.red.shade900 : Colors.red.shade100).withValues(alpha: 0.5),
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
              color: context.clanTextPrimary,
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
          if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.keyboard_outlined, size: 20),
              onPressed: () {
                DesktopKeyboardShortcuts.showShortcutsHelpDialog();
              },
              tooltip: 'Keyboard Shortcuts (Ctrl+/)',
            ),
          ],
        ],
      ),
      drawer: const RoleplayDrawer(),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                roleplayVM.messages.isEmpty
                    ? _buildEmptyState(context, context.clanTextPrimary)
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: roleplayVM.messages.length,
                        itemBuilder: (context, index) {
                          final message = roleplayVM.messages[index];
                          final avatar = roleplayVM.activeCharacter?.avatarData;
                          final name = roleplayVM.activeCharacter?.name;
                          // In roleplay mode, the first assistant message (character greeting) should not be regeneratable
                          // until after the user has replied, since it's defined by the character card and has no prior user context.
                          final isFirstAssistantMessage = index == 0 && message.role == MessageRole.assistant;
                          return MessageBubble(
                            key: ValueKey(message.id),
                            message: message,
                            messageIndex: index,
                            isLastMessage: index == roleplayVM.messages.length - 1,
                            debugContext: _buildDebugContext(message, roleplayVM, settingsVM),
                            characterAvatar: avatar,
                            characterName: name,
                            onRegenerate: isFirstAssistantMessage
                                ? null
                                : () {
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
                      backgroundColor: context.clanSurfaceVariant,
                      foregroundColor: context.clanTextPrimary,
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

            // Alternate Greeting Selector — only shown before the user has replied
          if (roleplayVM.activeCharacter != null &&
              roleplayVM.activeCharacter!.alternateGreetings.isNotEmpty &&
              roleplayVM.messages.every((m) => m.role == MessageRole.assistant))
            AlternateGreetingSelector(
              greetings: roleplayVM.activeCharacter!.alternateGreetings,
              onSelectGreeting: (selectedGreeting) {
                roleplayVM.startRoleplayWithGreeting(
                  roleplayVM.activeCharacter!,
                  selectedGreeting,
                  serverConfig: settingsVM.config,
                  connection: settingsVM.connectionDetails,
                  modelContextLength: settingsVM.getSelectedModelContextLength(),
                );
              },
            ),

          // Bottom Prompt Input Bar
          PromptInputBar(
            isGenerating: roleplayVM.isGenerating,
            isRoleplay: true,
            personaName: roleplayVM.activeCharacter?.personaName ?? 'you',
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
