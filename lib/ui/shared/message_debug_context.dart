import 'dart:convert';

import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/ui/features/chat/views/message_bubble.dart';
import 'package:clan_ai/ui/features/settings/view_models/settings_view_model.dart';

/// Builds the debug context payload for a message bubble.
///
/// Shared by ChatScreen and RoleplayScreen, which previously duplicated this
/// builder near-verbatim. Only the active thread (and the settings VM) are
/// mode-dependent, so both screens pass their own thread here.
MessageDebugContext? buildMessageDebugContext(
  ChatMessage message,
  ChatThread? activeThread,
  SettingsViewModel settingsVM,
) {
  if (message.role != MessageRole.assistant || message.status != MessageStatus.completed) return null;

  final systemPrompt = activeThread?.systemPrompt ?? settingsVM.config.systemPrompt;
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