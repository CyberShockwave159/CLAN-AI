import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

/// Shared streaming and mutation logic for ChatViewModel and RoleplayViewModel.
/// Eliminates ~150 lines of near-identical code between the two VMs.
mixin StreamMutationMixin on ChangeNotifier {
  // --- Provided by concrete VM ---
  Timer? get uiThrottleTimer; set uiThrottleTimer(Timer? v);
  String get pendingStreamBuffer; set pendingStreamBuffer(String v);
  String get pendingReasoningBuffer; set pendingReasoningBuffer(String v);
  List<ChatMessage> get messages; set messages(List<ChatMessage> v);
  ChatThread? get activeThread;
  bool get isGenerating; set isGenerating(bool v);
  CancelToken? get currentCancelToken; set currentCancelToken(CancelToken? v);
  ChatRepository get chatRepository;

  // Undo state
  ChatMessage? _undoneMessage;
  DateTime? _undoTimestamp;

  // --- Shared streaming logic ---

  /// Streams a response for the given assistant message ID.
  /// Concrete VMs call this from their _streamResponse methods.
  Future<void> doStreamResponse({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? upToIndex,
    int? modelContextLength,
    Future<void> Function(String assistantMessageId)? onComplete,
  }) async {
    isGenerating = true;
    currentCancelToken = CancelToken();
    pendingStreamBuffer = '';
    pendingReasoningBuffer = '';
    notifyListeners();

    final msgIndex = messages.indexWhere((m) => m.id == assistantMessageId);
    if (msgIndex == -1) {
      isGenerating = false;
      notifyListeners();
      return;
    }

    final historySlice = _messagesSublist(upToIndex, assistantMessageId);
    final effectiveSystemPrompt = activeThread?.systemPrompt ?? serverConfig.systemPrompt;

        uiThrottleTimer = Timer.periodic(uiThrottleInterval, (_) {
            final currentMsgIndex = messages.indexWhere((m) => m.id == assistantMessageId);
            if (pendingStreamBuffer.isNotEmpty &&
          currentMsgIndex >= 0 &&
          currentMsgIndex < messages.length) {
        final currentMsg = messages[currentMsgIndex];
        messages[currentMsgIndex] = currentMsg.copyWith(
          content: currentMsg.content + pendingStreamBuffer,
        );
        pendingStreamBuffer = '';
        notifyListeners();
      }
      if (pendingReasoningBuffer.isNotEmpty &&
          currentMsgIndex >= 0 &&
          currentMsgIndex < messages.length) {
        final currentMsg = messages[currentMsgIndex];
        messages[currentMsgIndex] = currentMsg.copyWith(
          reasoningContent: currentMsg.reasoningContent + pendingReasoningBuffer,
        );
        pendingReasoningBuffer = '';
        notifyListeners();
      }
    });

    StreamMetrics? finalMetrics;
    String? errorMessage;

    try {
      final stream = chatRepository.streamCompletion(
        serverConfig: serverConfig,
        connection: connection,
        history: historySlice,
        systemPrompt: effectiveSystemPrompt,
        params: customParams ?? activeThread?.customParams ?? serverConfig.defaultParams,
        cancelToken: currentCancelToken,
        modelContextLength: modelContextLength,
      );

      await for (final chunk in stream) {
        if (chunk.text.isNotEmpty) {
          pendingStreamBuffer += chunk.text;
        }
        if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          pendingReasoningBuffer += chunk.reasoning!;
        }
        if (chunk.metrics != null) {
          finalMetrics = chunk.metrics;
        }
      }
    } on RequestCancelledException {
      // Stopped gracefully by user
    } catch (e) {
      errorMessage = e.toString();
      if (e is AppException && e.recoverySuggestion != null) {
        errorMessage = '$errorMessage\n\nTip: ${e.recoverySuggestion}';
      }
    } finally {
            uiThrottleTimer?.cancel();
      uiThrottleTimer = null;

      final finalMsgIndex = messages.indexWhere((m) => m.id == assistantMessageId);
      if (finalMsgIndex >= 0 && finalMsgIndex < messages.length) {
        final currentMsg = messages[finalMsgIndex];
                final finalContent = currentMsg.content + pendingStreamBuffer;
        pendingStreamBuffer = '';

        final completedMsg = currentMsg.copyWith(
          content: finalContent,
          reasoningContent: currentMsg.reasoningContent + pendingReasoningBuffer,
          status: errorMessage != null ? MessageStatus.error : MessageStatus.completed,
          errorMessage: errorMessage,
          tokensPerSecond: finalMetrics?.tokensPerSecond,
          totalTokens: finalMetrics?.completionTokens,
          timeToFirstTokenMs: finalMetrics?.timeToFirstTokenMs,
          generationTimeSec: finalMetrics?.generationTimeSec,
        );

        messages[finalMsgIndex] = completedMsg;
        await chatRepository.saveMessage(completedMsg);
      }

      pendingReasoningBuffer = '';
      if (onComplete != null) {
        await onComplete(assistantMessageId);
      }

      isGenerating = false;
      currentCancelToken = null;
      notifyListeners();
          }
  }

  List<ChatMessage> _messagesSublist(int? upToIndex, String assistantMessageId) {
    return upToIndex != null
        ? messages.sublist(0, upToIndex)
        : messages.sublist(0, messages.indexWhere((m) => m.id == assistantMessageId));
  }

  // --- Shared mutation methods ---

  Future<void> doUndoDelete() async {
    if (_undoneMessage == null || _undoTimestamp == null) return;
    if (DateTime.now().difference(_undoTimestamp!) > undoTimeoutDuration) {
      _undoneMessage = null;
      _undoTimestamp = null;
      return;
    }
    if (activeThread == null) {
      _undoneMessage = null;
      _undoTimestamp = null;
      return;
    }

    await chatRepository.saveMessage(_undoneMessage!);
    messages = await chatRepository.getMessagesForThread(activeThread!.id);
    _undoneMessage = null;
    _undoTimestamp = null;
    notifyListeners();
  }

  bool get canUndo =>
      _undoneMessage != null &&
      _undoTimestamp != null &&
      DateTime.now().difference(_undoTimestamp!) <= undoTimeoutDuration;

  void doStopGeneration() {
    if (isGenerating && currentCancelToken != null) {
      currentCancelToken?.cancel();
      isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> doSwitchVariant({
    required int messageIndex,
    required bool previous,
  }) async {
    if (messageIndex < 0 || messageIndex >= messages.length) return;

    final currentMsg = messages[messageIndex];
    if (currentMsg.siblingIds.isEmpty) return;

    final siblingIndex = previous ? currentMsg.variantIndex - 1 : currentMsg.variantIndex;
    if (siblingIndex < 0 || siblingIndex >= currentMsg.siblingIds.length) return;

    final siblingId = currentMsg.siblingIds[siblingIndex];
    final siblingMsg = await chatRepository.getMessagesForThread(currentMsg.threadId).then(
      (msgs) => msgs.firstWhere((m) => m.id == siblingId, orElse: () => currentMsg),
    );

    if (siblingMsg.id != currentMsg.id) {
      messages[messageIndex] = siblingMsg;
      notifyListeners();
    }
  }

  /// Store message for undo support.
  void storeUndoMessage(ChatMessage message) {
    _undoneMessage = message;
    _undoTimestamp = DateTime.now();
  }
}
