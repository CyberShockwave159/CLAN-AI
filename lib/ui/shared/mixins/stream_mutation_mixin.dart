import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
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
    if (isGenerating) {
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

    final allSiblings = await chatRepository.getAllMessagesForThread(currentMsg.threadId);
    final mapped = currentMsg.siblingIds.map((id) => allSiblings.firstWhere(
      (m) => m.id == id,
      orElse: () => currentMsg,
    )).toList();
    final sortedSiblings = mapped..sort((a, b) => a.variantIndex.compareTo(b.variantIndex));

    final siblingIndex = previous ? currentMsg.variantIndex - 1 : currentMsg.variantIndex + 1;
    if (siblingIndex < 0 || siblingIndex >= sortedSiblings.length) return;

    final siblingMsg = sortedSiblings[siblingIndex];
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

  // --- Shared message mutation flows (used by both VMs) ---

  /// Shared core of `editUserPrompt` for ChatViewModel and RoleplayViewModel.
  ///
  /// Persists the branch bookkeeping for the edited user prompt (and the old
  /// assistant reply at `messageIndex + 1`), saves the new user message,
  /// truncates the conversation at [messageIndex], and appends it.
  ///
  /// Returns the ids each VM needs to build its streaming placeholder, or
  /// null when the edit is a no-op (generating, out of range, non-user role).
  Future<({String? oldAssistantId, ChatMessage newUserMessage})?> doEditUserPrompt({
    required int messageIndex,
    required String newContent,
  }) async {
    if (isGenerating || messageIndex < 0 || messageIndex >= messages.length) return null;

    final oldUserMsg = messages[messageIndex];
    if (oldUserMsg.role != MessageRole.user) return null;

    // Handle the old assistant response (at messageIndex + 1) as a sibling variant
    String? oldAssistantId;
    final oldAssistantMsgIndex = messageIndex + 1;
    if (oldAssistantMsgIndex < messages.length && messages[oldAssistantMsgIndex].role == MessageRole.assistant) {
      final oldAssistantMsg = messages[oldAssistantMsgIndex];
      oldAssistantId = oldAssistantMsg.id;
      final newAssistantId = const Uuid().v4();
      final newTotalVariants = oldAssistantMsg.totalVariants + 1;

      final updatedOldAssistant = oldAssistantMsg.copyWith(
        totalVariants: newTotalVariants,
        siblingIds: [...oldAssistantMsg.siblingIds, newAssistantId],
      );
      await chatRepository.saveMessage(updatedOldAssistant);
    }

    final newUserMsg = oldUserMsg.copyWith(
      id: const Uuid().v4(),
      content: newContent.trim(),
      variantIndex: oldUserMsg.totalVariants,
      totalVariants: oldUserMsg.totalVariants + 1,
      siblingIds: [...oldUserMsg.siblingIds, oldUserMsg.id],
      createdAt: DateTime.now(),
    );
    await chatRepository.saveMessage(newUserMsg);

    // Truncate messages after this point and insert new user message
    messages = messages.sublist(0, messageIndex);
    messages.add(newUserMsg);
    notifyListeners();

    return (oldAssistantId: oldAssistantId, newUserMessage: newUserMsg);
  }

  /// Shared core of `regenerateMessage` for both VMs.
  ///
  /// Computes the sibling-variant bookkeeping, marks the old assistant message
  /// as a variant, and swaps in a new streaming assistant message.
  ///
  /// Returns the new message id (for the caller to stream) together with the
  /// replaced message id (used by the roleplay VM's RAG cleanup), or null when
  /// regeneration is a no-op (generating, out of range, non-assistant role).
  Future<({String newAssistantId, String oldMessageId})?> doRegenerateMessage({
    required int messageIndex,
  }) async {
    if (isGenerating || messageIndex < 0 || messageIndex >= messages.length) return null;

    final targetMsg = messages[messageIndex];
    if (targetMsg.role != MessageRole.assistant) return null;

    // Find parent user message
    final parentId = targetMsg.parentId;
    final newAssistantId = const Uuid().v4();
    final nextVariantIndex = targetMsg.totalVariants;
    final newTotalVariants = targetMsg.totalVariants + 1;

    final existingSiblings = await chatRepository.getAllMessagesForThread(targetMsg.threadId);
    final variantSiblings = existingSiblings.where((m) => m.role == MessageRole.assistant && m.parentId == targetMsg.parentId);
    final allSiblingIds = {...variantSiblings.map((m) => m.id), targetMsg.id, newAssistantId};
    final completeSiblingList = allSiblingIds.toList()..sort();

    final updatedOldMsg = targetMsg.copyWith(
      variantIndex: targetMsg.variantIndex,
      totalVariants: newTotalVariants,
      siblingIds: completeSiblingList,
    );
    messages[messageIndex] = updatedOldMsg;
    await chatRepository.saveMessage(updatedOldMsg);

    for (final siblingMsg in existingSiblings) {
      if (siblingMsg.id != targetMsg.id) {
        await chatRepository.saveMessage(siblingMsg.copyWith(
          siblingIds: completeSiblingList,
        ));
      }
    }

    final newAssistantMsg = ChatMessage(
      id: newAssistantId,
      threadId: targetMsg.threadId,
      parentId: parentId,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      variantIndex: nextVariantIndex,
      totalVariants: newTotalVariants,
      siblingIds: completeSiblingList,
    );

    // Replace current visible message with new streaming message
    messages[messageIndex] = newAssistantMsg;
    notifyListeners();

    return (newAssistantId: newAssistantId, oldMessageId: targetMsg.id);
  }

  /// Shared head of `deleteMessage` for both VMs: guard, per-message database
  /// deletion with image-file cleanup, first-message thread-deletion
  /// detection, history truncation, and undo storage.
  ///
  /// Returns null when the guard blocks the deletion (caller returns false).
  /// When [threadToDelete] is non-null the caller must delete that thread and
  /// return the "thread deleted" result. The caller is responsible for the
  /// mode-specific regeneration tail (RAG rebuild in roleplay mode).
  Future<({String? threadToDelete, bool isUserMessage})?> doDeleteMessageHead({
    required int messageIndex,
  }) async {
    if (isGenerating || messageIndex < 0 || messageIndex >= messages.length || activeThread == null) return null;

    final deletedMsg = messages[messageIndex];
    final isFirstMessage = messageIndex == 0;
    final isUserMessage = deletedMsg.role == MessageRole.user;

    // Determine which messages to delete: this one and all after it
    final messagesToDelete = messages.sublist(messageIndex);

    // Delete from database (and remove any image attachment files from disk)
    for (final msg in messagesToDelete) {
      await chatRepository.deleteMessage(msg.id);
      await MessageAttachmentStore.instance.deleteIfExists(msg.imagePath);
    }

    // If this was the only message (or first message) in the thread, delete the whole thread
    if (isFirstMessage) {
      return (threadToDelete: activeThread!.id, isUserMessage: isUserMessage);
    }

    // Keep messages before the deleted one
    messages = messages.sublist(0, messageIndex);

    // Store for undo (only user messages, not AI responses that trigger regeneration)
    if (isUserMessage) {
      storeUndoMessage(deletedMsg);
    }

    return (threadToDelete: null, isUserMessage: isUserMessage);
  }

  @override
  void dispose() {
    uiThrottleTimer?.cancel();
    currentCancelToken?.cancel();
    super.dispose();
  }
}
