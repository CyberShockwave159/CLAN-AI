import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/chat/views/prompt_input_bar.dart';
import 'package:clan_ai/ui/features/drawer/views/chat_drawer.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/parameter_tuning_sheet.dart';
import 'package:clan_ai/ui/shared/app_header.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
    final chatVM = context.read<ChatViewModel>();
    final shouldDeleteThread = await chatVM.deleteMessage(
      messageIndex: messageIndex,
      serverConfig: settingsVM.config,
      modelContextLength: settingsVM.getSelectedModelContextLength(),
    );
    if (shouldDeleteThread) {
      _scrollToBottom(false);
    } else if (chatVM.canUndo) {
      final deletedMsg = chatVM.messages.length > messageIndex
          ? null
          : null; // Already deleted, show undo for any user message deletion
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Message deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await chatVM.undoDelete();
              _scrollToBottom();
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatVM = context.watch<ChatViewModel>();
    final settingsVM = context.watch<SettingsViewModel>();

    // Auto scroll down when assistant is actively streaming
    if (chatVM.isGenerating && !_showScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(false);
      });
    }

    return Scaffold(
      appBar: const AppHeader(),
      drawer: const ChatDrawer(),
      body: Column(
        children: [
          // Chat Message Stream View
          Expanded(
            child: Stack(
              children: [
                chatVM.messages.isEmpty
                    ? _buildEmptyState(context, isDark, chatVM, settingsVM)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: chatVM.messages.length,
                        itemBuilder: (context, index) {
                          final message = chatVM.messages[index];
                          return MessageBubble(
                               key: ValueKey(message.id),
                               message: message,
                               messageIndex: index,
                               onRegenerate: () {
                                 chatVM.regenerateMessage(
                                   messageIndex: index,
                                   serverConfig: settingsVM.config,
                                   modelContextLength: settingsVM.getSelectedModelContextLength(),
                                 );
                               },
                               onEdit: (newPrompt) {
                                 chatVM.editUserPrompt(
                                   messageIndex: index,
                                   newContent: newPrompt,
                                   serverConfig: settingsVM.config,
                                   modelContextLength: settingsVM.getSelectedModelContextLength(),
                                 );
                               },
                               onBranch: () {
                                 chatVM.branchConversation(
                                   messageIndex: index,
                                   serverConfig: settingsVM.config,
                                   modelContextLength: settingsVM.getSelectedModelContextLength(),
                                 );
                               },
                              onPreviousVariant: () {
                                chatVM.switchVariant(
                                  messageIndex: index,
                                  previous: true,
                                );
                              },
                              onNextVariant: () {
                                chatVM.switchVariant(
                                  messageIndex: index,
                                  previous: false,
                                );
                              },
                              onDelete: () {
                                if (settingsVM.config.confirmDeleteMessage) {
                                  // Confirmation already shown in MessageBubble
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
            isGenerating: chatVM.isGenerating,
            onSend: (prompt) {
              chatVM.sendMessage(
                prompt: prompt,
                serverConfig: settingsVM.config,
                modelContextLength: settingsVM.getSelectedModelContextLength(),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom(true);
              });
            },
            onStop: () => chatVM.stopGeneration(),
            onOpenParams: () => _openParameterSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool isDark,
    ChatViewModel chatVM,
    SettingsViewModel settingsVM,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.accentPrimary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.bolt_rounded, color: AppTheme.accentPrimary, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'What would you like to explore?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Connected to ${settingsVM.config.name}',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              ),
            ),
            const SizedBox(height: 28),

            // Starter Prompt Cards
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildPromptSuggestion(
                  'Explain quantum computing in simple terms',
                  Icons.science_outlined,
                  chatVM,
                  settingsVM,
                  isDark,
                ),
                _buildPromptSuggestion(
                  'Write a Python script for Server-Sent Events',
                  Icons.code_rounded,
                  chatVM,
                  settingsVM,
                  isDark,
                ),
                _buildPromptSuggestion(
                  r'Calculate the integral $\int x^2 e^x dx$',
                  Icons.functions_rounded,
                  chatVM,
                  settingsVM,
                  isDark,
                ),
                _buildPromptSuggestion(
                  'Analyze time complexity of Dijkstra algorithm',
                  Icons.analytics_outlined,
                  chatVM,
                  settingsVM,
                  isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptSuggestion(
    String prompt,
    IconData icon,
    ChatViewModel chatVM,
    SettingsViewModel settingsVM,
    bool isDark,
  ) {
    return InkWell(
      onTap: () {
        chatVM.sendMessage(
          prompt: prompt,
          serverConfig: settingsVM.config,
          modelContextLength: settingsVM.getSelectedModelContextLength(),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurfaceVariant.withValues(alpha: 0.7) : AppTheme.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.accentPrimary),
            const SizedBox(width: 8),
            Text(
              prompt,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
