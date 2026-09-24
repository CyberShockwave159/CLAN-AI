import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/core/utils/text_sanitizer.dart';
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
    String? imageArtifactRef;
    String? fileArtifactRef;
    String? fileArtifactName;
    String? fileArtifactMime;
    Future<void>? imageDownload;
    Future<void>? fileDownload;

    // The image URL promoted into a native attachment this response (from a
    // `delta.image_url` or the caption-text fallback). Kept so any occurrence
    // of it in the streamed markdown can be stripped, avoiding a duplicated
    // orphaned link below the attachment card.
    String? downloadedImageUrl;

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
          // Hide an already-promoted image URL (SSE `image_url` path) from the
          // caption so no orphaned markdown/raw link remains under the card.
          if (downloadedImageUrl != null) {
            _stripImageUrlFromStream(assistantMessageId, downloadedImageUrl);
          }
          // Text-ingest fallback: the server output the image URL only inside
          // the caption (no `delta.image_url`). Detect it, strip it from the
          // text, and promote it into a native attachment.
          if (imageDownload == null && downloadedImageUrl == null) {
            final idx = messages.indexWhere((m) => m.id == assistantMessageId);
            if (idx >= 0 && idx < messages.length) {
              final url = TextSanitizer.extractFirstImageUrl(
                messages[idx].content + pendingStreamBuffer,
              );
              if (url != null) {
                downloadedImageUrl = url;
                _stripImageUrlFromStream(assistantMessageId, url);
                imageDownload = _downloadImageArtifact(
                  assistantMessageId,
                  _resolveArtifactUrl(url, connection),
                  (ref) => imageArtifactRef = ref,
                );
              }
            }
          }
        }
        if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          pendingReasoningBuffer += chunk.reasoning!;
        }
        if (chunk.metrics != null) {
          finalMetrics = chunk.metrics;
        }
        // A-PROX artifacts: capture each at most once per response. The
        // download runs in the background so it never stalls the caption
        // stream; the result is folded into the message as soon as it lands
        // (live preview) and persisted before the final save.
        if (chunk.imageUrl != null &&
            chunk.imageUrl!.isNotEmpty &&
            imageDownload == null) {
          final imageUrl = _resolveArtifactUrl(chunk.imageUrl!, connection);
          downloadedImageUrl = imageUrl;
          imageDownload = _downloadImageArtifact(
            assistantMessageId,
            imageUrl,
            (ref) => imageArtifactRef = ref,
          );
        }
        if (chunk.fileUrl != null &&
            chunk.fileUrl!.isNotEmpty &&
            fileDownload == null) {
          final url = chunk.fileUrl!;
          fileArtifactName = chunk.fileName;
          fileArtifactMime = chunk.fileMime;
          fileDownload = downloadFileArtifact(
            assistantMessageId,
            url,
            chunk.fileName,
            chunk.fileMime,
          ).then((ref) => fileArtifactRef = ref);
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

      String? resolvedImagePath;
      String? resolvedFilePath;
      if (imageDownload != null) {
        try {
          await imageDownload.timeout(const Duration(seconds: 30));
          resolvedImagePath = imageArtifactRef;
        } catch (_) {
          // Artifact download failure is non-fatal — the caption still saves.
        }
      }
      if (fileDownload != null) {
        try {
          await fileDownload.timeout(const Duration(seconds: 30));
          resolvedFilePath = fileArtifactRef;
        } catch (_) {
          // Artifact download failure is non-fatal — the caption still saves.
        }
      }

      final finalMsgIndex = messages.indexWhere((m) => m.id == assistantMessageId);
      if (finalMsgIndex >= 0 && finalMsgIndex < messages.length) {
        final currentMsg = messages[finalMsgIndex];
                var finalContent = currentMsg.content + pendingStreamBuffer;
        // Ensure no orphaned image URL survives in the saved caption when the
        // URL was only fully formed right at stream end.
        if (downloadedImageUrl != null) {
          finalContent = TextSanitizer.stripImageUrl(finalContent, downloadedImageUrl);
        }
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
          imagePath: resolvedImagePath ?? currentMsg.imagePath,
          filePath: resolvedFilePath ?? currentMsg.filePath,
          fileName: fileArtifactName ?? currentMsg.fileName,
          fileMime: fileArtifactMime ?? currentMsg.fileMime,
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

  /// Downloads an image artifact and, on success, immediately attaches its
  /// [ref] to the streaming message so the bubble renders the image live while
  /// the caption/reasoning text is still streaming. [onRef] (typically a
  /// closure capturing `imageArtifactRef`) records the ref for the final save.
  Future<void> _downloadImageArtifact(
    String messageId,
    String url,
    FutureOr<void> Function(String? ref) onRef,
  ) {
    return downloadImageArtifact(messageId, url).then((ref) {
      onRef(ref);
      if (ref == null || ref.isEmpty) return;
      final idx = messages.indexWhere((m) => m.id == messageId);
      if (idx < 0 || idx >= messages.length) return;
      final current = messages[idx];
      if (current.imagePath != null && current.imagePath!.isNotEmpty) return;
      messages[idx] = current.copyWith(imagePath: ref);
      notifyListeners();
    });
  }

  /// Resolves an artifact URL the server emitted against the active
  /// [connection]: relative paths (`/images/gen_1.png`) are joined to the
  /// connection's base URL, and loopback hostnames (`127.0.0.1`/`localhost`)
  /// are rewritten to the connection host so mobile emulators and LAN clients
  /// can reach the image. Non-absolute, already-absolute, or unknown shapes are
  /// returned unchanged.
  String _resolveArtifactUrl(String url, ServerProfile? connection) {
    if (url.isEmpty) return url;
    final base = connection?.baseUrl;
    if (base == null || base.isEmpty) return url;

    if (url.startsWith('/')) {
      final baseUri = Uri.tryParse(base);
      if (baseUri == null || baseUri.host.isEmpty) return url;
      return baseUri.resolve(url).toString();
    }

    final urlUri = Uri.tryParse(url);
    if (urlUri == null || !urlUri.hasScheme) return url;
    final host = urlUri.host;
    if (host != '127.0.0.1' && host != 'localhost' && host != '0.0.0.0') {
      return url;
    }
    final baseUri = Uri.tryParse(base);
    if (baseUri == null || baseUri.host.isEmpty) return url;
    // Preserve the image URL's own port — the serving process may listen on a
    // different port than the API base — but substitute the reachable host.
    return urlUri.replace(host: baseUri.host).toString();
  }

  /// Removes [url] (and any `![..](url)` / `[..](url)` framing) from both the
  /// already-flushed message content and the pending stream buffer, preserving
  /// the content/buffer boundary even when the URL straddles it.
  void _stripImageUrlFromStream(String assistantMessageId, String url) {
    final idx = messages.indexWhere((m) => m.id == assistantMessageId);
    if (idx < 0 || idx >= messages.length) return;
    final content = messages[idx].content;
    final buffer = pendingStreamBuffer;
    if (content.isEmpty && buffer.isEmpty) return;

    final combined = content + buffer;
    final stripped = TextSanitizer.stripImageUrl(combined, url);
    if (stripped == combined) return;

    if (buffer.isEmpty) {
      messages[idx] = messages[idx].copyWith(content: stripped);
      notifyListeners();
      return;
    }

    // Locate the span that was removed to split the stripped text back across
    // the content/buffer boundary.
    int diffAt = -1;
    for (int i = 0; i < combined.length; i++) {
      if (i >= stripped.length || combined[i] != stripped[i]) {
        diffAt = i;
        break;
      }
    }
    if (diffAt == -1) return;
    final removedLen = combined.length - stripped.length;
    final removedEnd = diffAt + removedLen;
    final overlap = removedEnd <= content.length
        ? removedLen
        : diffAt < content.length
            ? content.length - diffAt
            : 0;
    final newBoundary = content.length - overlap;
    if (newBoundary < 0 || newBoundary > stripped.length) return;
    messages[idx] = messages[idx].copyWith(
      content: stripped.substring(0, newBoundary),
    );
    pendingStreamBuffer = stripped.substring(newBoundary);
    notifyListeners();
  }

  /// Downloads an A-PROX image artifact into the attachment store and returns
  /// its local reference (or null on failure). Concrete VMs may override for
  /// hermetic tests.
  Future<String?> downloadImageArtifact(String messageId, String url) async {
    try {
      final bytes = await MessageAttachmentStore.instance.fetchBytes(url);
      return await MessageAttachmentStore.instance.saveImage(
        fileId: messageId,
        data: bytes,
        extension: MessageAttachmentStore.extensionOf(url),
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads an A-PROX file artifact into the attachment store and returns
  /// its local reference (or null on failure). Concrete VMs may override for
  /// hermetic tests.
  Future<String?> downloadFileArtifact(
    String messageId,
    String url,
    String? fileName,
    String? mime,
  ) async {
    try {
      final resolvedName = fileName ?? MessageAttachmentStore.fileNameFromUrl(url);
      final bytes = await MessageAttachmentStore.instance.fetchBytes(url);
      return await MessageAttachmentStore.instance.saveFile(
        fileId: messageId,
        data: bytes,
        fileName: resolvedName,
        mime: mime,
      );
    } catch (_) {
      return null;
    }
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
