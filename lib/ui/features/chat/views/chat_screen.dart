import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:clan_ai/core/constants/app_theme.dart';
import 'package:clan_ai/core/constants/clan_theme_colors.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';
import 'dart:convert';

import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/ui/features/chat/view_models/chat_view_model.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/chat/views/prompt_input_bar.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/drawer/views/chat_drawer.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';
import 'package:clan_ai/ui/features/settings/views/parameter_tuning_sheet.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';
import 'package:clan_ai/ui/shared/app_header.dart';
import 'package:clan_ai/ui/shared/mixins/auto_scroll_mixin.dart';
import 'package:clan_ai/ui/shared/delete_message_handler.dart';
import 'package:clan_ai/core/utils/latency_meter.dart';

class ChatScreen extends StatefulWidget {
  final VoidCallback? themeRefresh;

  const ChatScreen({super.key, this.themeRefresh});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with AutoScrollMixin {
  final TextEditingController _quickConnectUrlController = TextEditingController();
  PingResult? _quickConnectResult;
  bool _quickConnecting = false;

  @override
  void initState() {
    super.initState();
    initAutoScroll();
  }

  @override
  void dispose() {
    _quickConnectUrlController.dispose();
    super.dispose();
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
        isRoleplay: false,
      ),
    );
  }

  Future<void> _handleDeleteMessage(int messageIndex, SettingsViewModel settingsVM) async {
    final chatVM = context.read<ChatViewModel>();
    await handleDeleteMessage(
      context: context,
      deleteFn: () => chatVM.deleteMessage(
        messageIndex: messageIndex,
        serverConfig: settingsVM.config,
        connection: settingsVM.connectionDetails,
        modelContextLength: settingsVM.getSelectedModelContextLength(),
      ),
      canUndo: chatVM.canUndo,
      undoFn: () async {
        await chatVM.undoDelete();
        scrollToBottom();
      },
      onThreadDeleted: () => scrollToBottom(false),
    );
  }

  void _setQuickConnectPreset(String url) {
    setState(() {
      _quickConnectUrlController.text = url;
      _quickConnectResult = null;
    });
  }

  Future<void> _performQuickConnect(SettingsViewModel settingsVM) async {
    final url = _quickConnectUrlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _quickConnecting = true;
      _quickConnectResult = null;
    });

    final result = await settingsVM.testConnectionAtUrl(url);

    if (mounted) {
      setState(() {
        _quickConnecting = false;
        _quickConnectResult = result;
        if (result != null && result!.isHealthy) {
          settingsVM.updateBaseUrl(url);
        }
      });
    }
  }

  MessageDebugContext? _buildDebugContext(ChatMessage message, ChatViewModel chatVM, SettingsViewModel settingsVM) {
    if (message.role != MessageRole.assistant || message.status != MessageStatus.completed) return null;

    final thread = chatVM.activeThread;
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

  @override
  Widget build(BuildContext context) {
    final chatVM = context.watch<ChatViewModel>();
    final settingsVM = context.watch<SettingsViewModel>();

    // Auto scroll down when assistant is actively streaming
    if (chatVM.isGenerating && !showScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBottom(false);
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
                    ? _buildEmptyState(context, context.clanTextPrimary, chatVM, settingsVM)
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: chatVM.messages.length,
                        itemBuilder: (context, index) {
                          final message = chatVM.messages[index];
                          return MessageBubble(
                               key: ValueKey(message.id),
                               message: message,
                               messageIndex: index,
                               debugContext: _buildDebugContext(message, chatVM, settingsVM),
                                onRegenerate: () {
                                  chatVM.regenerateMessage(
                                    messageIndex: index,
                                    serverConfig: settingsVM.config,
                                    connection: settingsVM.connectionDetails,
                                    modelContextLength: settingsVM.getSelectedModelContextLength(),
                                  );
                                },
                                onEdit: (newPrompt) {
                                  chatVM.editUserPrompt(
                                    messageIndex: index,
                                    newContent: newPrompt,
                                    serverConfig: settingsVM.config,
                                    connection: settingsVM.connectionDetails,
                                    modelContextLength: settingsVM.getSelectedModelContextLength(),
                                  );
                                },
                                onBranch: () {
                                  chatVM.branchConversation(
                                    messageIndex: index,
                                    serverConfig: settingsVM.config,
                                    connection: settingsVM.connectionDetails,
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

          // Bottom Prompt Input Bar
          PromptInputBar(
            isGenerating: chatVM.isGenerating,
            onSend: (prompt) {
              chatVM.sendMessage(
                prompt: prompt,
                serverConfig: settingsVM.config,
                connection: settingsVM.connectionDetails,
                modelContextLength: settingsVM.getSelectedModelContextLength(),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                scrollToBottom(true);
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
    Color titleColor,
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
                color: titleColor,
              ),
            ),
            const SizedBox(height: 6),
            if (settingsVM.config.healthStatus == ServerHealthStatus.offline)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (Theme.of(context).brightness == Brightness.dark ? Colors.red.shade900 : Colors.red.shade100).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade700),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Server unreachable. Verify your endpoint in Settings.',
                          style: TextStyle(
                            fontSize: 12,
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
              )
            else
              Text(
                'Connected to ${settingsVM.config.name}',
                style: TextStyle(
                  fontSize: 13,
                  color: context.clanTextMuted,
                ),
              ),
            const SizedBox(height: 28),

            // Quick Connect Card (shown when offline)
            if (settingsVM.config.healthStatus != ServerHealthStatus.connected)
              _buildQuickConnectCard(context, settingsVM),

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
                  context.clanTextPrimary,
                ),
                _buildPromptSuggestion(
                  'Write a Python script for Server-Sent Events',
                  Icons.code_rounded,
                  chatVM,
                  settingsVM,
                  context.clanTextPrimary,
                ),
                _buildPromptSuggestion(
                  r'Calculate the integral $\int x^2 e^x dx$',
                  Icons.functions_rounded,
                  chatVM,
                  settingsVM,
                  context.clanTextPrimary,
                ),
                _buildPromptSuggestion(
                  'Analyze time complexity of Dijkstra algorithm',
                  Icons.analytics_outlined,
                  chatVM,
                  settingsVM,
                  context.clanTextPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickConnectCard(BuildContext context, SettingsViewModel settingsVM) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.clanSurfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.clanBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_find_rounded, size: 20, color: context.clanTextPrimary),
              const SizedBox(width: 8),
              Text(
                'Quick Connect',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.clanTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Connect to your local LLM server',
            style: TextStyle(
              fontSize: 12,
              color: context.clanTextMuted,
            ),
          ),
          const SizedBox(height: 12),
          // Preset chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildPresetChip('llama.cpp', 'http://127.0.0.1:8080', context),
              _buildPresetChip('Android Emulator', 'http://10.0.2.2:8080', context),
              _buildPresetChip('Ollama', 'http://127.0.0.1:11434', context),
              _buildPresetChip('LM Studio', 'http://127.0.0.1:1234', context),
            ],
          ),
          const SizedBox(height: 12),
          // URL input field
          TextField(
            controller: _quickConnectUrlController,
            keyboardType: TextInputType.url,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'http://127.0.0.1:8080',
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.clanBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.accentPrimary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          // Connect button
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _quickConnecting ? null : () => _performQuickConnect(settingsVM),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _quickConnecting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : const Text(
                      'Connect / Test',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          // Result feedback
          if (_quickConnectResult != null)
            _buildQuickConnectResult(context),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String url, BuildContext context) {
    return InkWell(
      onTap: () => _setQuickConnectPreset(url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.clanSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.clanBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: context.clanTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickConnectResult(BuildContext context) {
    final result = _quickConnectResult!;
    if (result.isHealthy) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Text(
              'Connected (${result.latencyMs}ms)',
              style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 14, color: Colors.red),
                const SizedBox(width: 6),
                Text(
                  'Connection failed',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.red.shade700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              result.errorMessage ?? 'Unknown error',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildPromptSuggestion(
    String prompt,
    IconData icon,
    ChatViewModel chatVM,
    SettingsViewModel settingsVM,
    Color titleColor,
  ) {
    return InkWell(
      onTap: () {
        chatVM.sendMessage(
          prompt: prompt,
          serverConfig: settingsVM.config,
          connection: settingsVM.connectionDetails,
          modelContextLength: settingsVM.getSelectedModelContextLength(),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.clanSurfaceVariant.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.clanBorder,
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
                color: titleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
