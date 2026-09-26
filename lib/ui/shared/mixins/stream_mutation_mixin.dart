import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/core/utils/text_sanitizer.dart';
import 'package:clan_ai/data/datasources/request_options.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

/// How a streamed response's *text* is treated.
///
/// Artifacts (images, files) and metrics are captured either way; this only
/// governs whether the model's words become the message body.
enum StreamTextMode {
  /// Accumulate deltas into the message content. The normal chat path.
  append,

  /// Ignore deltas entirely and leave the message's seeded content alone.
  ///
  /// Used by the scene-image flow, where A-PROX's prompt enhancer streams a
  /// caption describing the picture it just made. That caption describes the
  /// *request*, not the roleplay reply, so folding it into the message would
  /// replace the character's dialogue with a picture description. The image
  /// artifact still flows through the normal capture path.
  discard,
}

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
  ///
  /// [options] carries A-PROX-specific request fields (routing alias, rag
  /// object, roleplay marker, image style). Inert by default.
  ///
  /// [textMode] defaults to [StreamTextMode.append]. [StreamTextMode.discard]
  /// keeps the message's seeded content and ignores streamed text, which the
  /// scene-image flow uses so A-PROX's picture caption never overwrites the
  /// character's dialogue.
  ///
  /// [historyOverride] replaces the message slice that would otherwise be
  /// derived from the in-memory list. The scene-image flow needs this: its
  /// request carries a short hand-built context plus a synthetic `/image` turn
  /// rather than the thread's real history, and the full history would push the
  /// conversation further from the scene being illustrated.
  ///
  /// [persistOnComplete] writes the finished message to the database. Set false
  /// for a scratch message that must not outlive the request (a generated
  /// reference portrait, for instance) — such a message has no thread row, and
  /// messages→threads is an enforced foreign key.
  ///
  /// [onArtifactResolved] receives the local path of an image artifact once it
  /// has been downloaded and stored, whether or not the message is persisted.
  Future<void> doStreamResponse({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? upToIndex,
    int? modelContextLength,
    Future<void> Function(String assistantMessageId)? onComplete,
    RequestOptions options = RequestOptions.none,
    StreamTextMode textMode = StreamTextMode.append,
    List<ChatMessage>? historyOverride,
    String? systemPromptOverride,
    bool persistOnComplete = true,
    void Function(String? imagePath)? onArtifactResolved,
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

    final historySlice =
        historyOverride ?? _messagesSublist(upToIndex, assistantMessageId);
    final effectiveSystemPrompt =
        systemPromptOverride ?? activeThread?.systemPrompt ?? serverConfig.systemPrompt;

        uiThrottleTimer = Timer.periodic(uiThrottleInterval, (_) {
            final currentMsgIndex = messages.indexWhere((m) => m.id == assistantMessageId);
            if (pendingStreamBuffer.isNotEmpty &&
          currentMsgIndex >= 0 &&
          currentMsgIndex < messages.length) {
        final currentMsg = messages[currentMsgIndex];
        if (textMode == StreamTextMode.append) {
          messages[currentMsgIndex] = currentMsg.copyWith(
            content: currentMsg.content + pendingStreamBuffer,
          );
        }
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
        options: options,
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
        } catch (e) {
          // Non-fatal: the caption/reasoning still saves. Logged, because a
          // dropped image is otherwise indistinguishable from "the server never
          // sent one" and gets reported as exactly that.
          debugPrint('Image artifact did not attach in time: $e');
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
                var finalContent = textMode == StreamTextMode.append
            ? currentMsg.content + pendingStreamBuffer
            : currentMsg.content;
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
          imageUrl: downloadedImageUrl ?? currentMsg.imageUrl,
          filePath: resolvedFilePath ?? currentMsg.filePath,
          fileName: fileArtifactName ?? currentMsg.fileName,
          fileMime: fileArtifactMime ?? currentMsg.fileMime,
        );

        messages[finalMsgIndex] = completedMsg;
        if (persistOnComplete) {
          await chatRepository.saveMessage(completedMsg);
        }
      }

      if (onArtifactResolved != null) {
        onArtifactResolved(resolvedImagePath);
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
      if (current.imagePath != null &&
          current.imagePath!.isNotEmpty &&
          current.imageUrl != null &&
          current.imageUrl!.isNotEmpty) {
        return;
      }
      messages[idx] = current.copyWith(
        imagePath: current.imagePath ?? ref,
        imageUrl: current.imageUrl ?? url,
      );
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
  ///
  /// Accepts both served `http(s)` URLs and base64 `data:` URLs
  /// (`[image_generation].inline_data_url`): the extension for the stored file
  /// is derived from the artifact URL, so an inline PNG keeps its `.png`.
  Future<String?> downloadImageArtifact(String messageId, String url) async {
    try {
      final bytes = await MessageAttachmentStore.instance.fetchBytes(url);
      return await MessageAttachmentStore.instance.saveImage(
        fileId: messageId,
        data: bytes,
        extension: MessageAttachmentStore.extensionForUrl(url),
      );
    } catch (e) {
      // Deliberately not swallowed. A failure here leaves `imagePath` null, and
      // the roleplay image flow then reports "the server returned no image" and
      // discards the variant — a message that points at a network or disk
      // problem, not at the server having failed to generate anything. That
      // misdiagnosis cost a full debugging cycle once already.
      debugPrint('Image artifact download failed for $url: $e');
      rethrow;
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

  /// Recomputes a variant group's membership and persists it consistently.
  ///
  /// Every member is written with the same complete `siblingIds` list *and* the
  /// same `totalVariants`, derived from [memberIds] rather than by incrementing.
  ///
  /// Deriving it is what makes the group self-healing. Two bugs came from
  /// incrementing and only partially updating members:
  ///
  /// * Siblings were given the new `siblingIds` but kept their old
  ///   `totalVariants`, so an older variant displayed "1 / 2" while the group
  ///   held three. The navigator's count and its next-button enabled state both
  ///   read that field, so the UI advertised navigation it could not perform.
  /// * Reverting a variant deleted the row but left the original still listing
  ///   the deleted id, producing a permanently unreachable "next" — the `prev`
  ///   arrow worked, `next` silently did nothing.
  ///
  /// [memberIds] is authoritative: a member not yet written to the database (the
  /// freshly created placeholder, or a message held only in memory) still counts
  /// toward the total, and its corrected fields are returned so the caller can
  /// apply them in memory.
  ///
  /// Returns the members that were found and corrected, newest fields included.
  Future<List<ChatMessage>> _syncVariantGroup({
    required String threadId,
    required Set<String> memberIds,
  }) async {
    if (memberIds.isEmpty) return const [];
    final total = memberIds.length;
    final siblingIds = memberIds.toList()..sort();

    final all = await chatRepository.getAllMessagesForThread(threadId);
    final updated = <ChatMessage>[];
    for (final member in all) {
      if (!memberIds.contains(member.id)) continue;
      if (member.role != MessageRole.assistant) continue;
      final fixed = member.copyWith(
        totalVariants: total,
        siblingIds: siblingIds,
      );
      if (fixed.totalVariants == member.totalVariants &&
          _sameIds(fixed.siblingIds, member.siblingIds)) {
        continue;
      }
      await chatRepository.saveMessage(fixed);
      updated.add(fixed);
    }
    return updated;
  }

  /// The group fields implied by [memberIds], for applying to a message that is
  /// not (yet) in the database.
  ({int totalVariants, List<String> siblingIds}) variantGroupFields(
    Set<String> memberIds,
  ) {
    return (
      totalVariants: memberIds.length,
      siblingIds: memberIds.toList()..sort(),
    );
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> doSwitchVariant({
    required int messageIndex,
    required bool previous,
  }) async {
    if (messageIndex < 0 || messageIndex >= messages.length) return;

    final currentMsg = messages[messageIndex];
    if (currentMsg.siblingIds.isEmpty) return;

    final allSiblings = await chatRepository.getAllMessagesForThread(currentMsg.threadId);
    // Resolve strictly: an id with no row (a variant that was deleted, or one
    // belonging to another thread) is dropped, never substituted with the
    // current message. Substituting produced a duplicate with the same
    // variantIndex, so the target index landed on the message already displayed
    // and the switch became a silent no-op while the button still looked live.
    final byId = {for (final m in allSiblings) m.id: m};
    final mapped = currentMsg.siblingIds
        .map((id) => byId[id])
        .whereType<ChatMessage>()
        .toList()
      ..sort((a, b) => a.variantIndex.compareTo(b.variantIndex));
    if (mapped.length < 2) return;

    final target = previous
        ? currentMsg.variantIndex - 1
        : currentMsg.variantIndex + 1;
    if (target < 0 || target >= mapped.length) return;

    final siblingMsg = mapped[target];
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

    final existingSiblings = await chatRepository.getAllMessagesForThread(targetMsg.threadId);
    final variantSiblings = existingSiblings.where(
      (m) => m.role == MessageRole.assistant && m.parentId == parentId,
    );
    final memberIds = {
      ...variantSiblings.map((m) => m.id),
      targetMsg.id,
      newAssistantId,
    };

    // Persist the placeholder first so the group sync sees it, then normalise
    // every member's sibling list and count from what is actually stored.
    await chatRepository.saveMessage(ChatMessage(
      id: newAssistantId,
      threadId: targetMsg.threadId,
      parentId: parentId,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      variantIndex: nextVariantIndex,
      siblingIds: memberIds.toList()..sort(),
    ));
    final group = variantGroupFields(memberIds);
    await _syncVariantGroup(
      threadId: targetMsg.threadId,
      memberIds: memberIds,
    );

    final newAssistantMsg = ChatMessage(
      id: newAssistantId,
      threadId: targetMsg.threadId,
      parentId: parentId,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      variantIndex: nextVariantIndex,
      totalVariants: group.totalVariants,
      siblingIds: group.siblingIds,
    );

    // Replace current visible message with new streaming message
    messages[messageIndex] = newAssistantMsg;
    notifyListeners();

    return (newAssistantId: newAssistantId, oldMessageId: targetMsg.id);
  }

  /// Creates a sibling variant of an assistant message that **keeps the original
  /// text** and streams an artifact into it.
  ///
  /// Same variant bookkeeping as [doRegenerateMessage], but the new message is
  /// seeded with the target's content instead of an empty string, and any image
  /// the source already carried is deliberately *not* copied.
  ///
  /// Used by the roleplay scene-image flow: tapping "Generate image" produces a
  /// new variant holding the identical dialogue plus a freshly generated picture,
  /// so the user can flip between "text only" and "text + picture" with the
  /// existing variant arrows, exactly as they can with regenerations. Not
  /// inheriting the old image is what makes each tap a fresh generation from the
  /// identity reference rather than a re-edit of the previous picture.
  ///
  /// Returns the new message id and the id of the message it replaced, or null
  /// when the guard blocks the action.
  Future<({String newAssistantId, String oldMessageId})?> doCreateImageVariant({
    required int messageIndex,
  }) async {
    if (isGenerating || messageIndex < 0 || messageIndex >= messages.length) return null;

    final targetMsg = messages[messageIndex];
    if (targetMsg.role != MessageRole.assistant) return null;

    final newAssistantId = const Uuid().v4();
    final nextVariantIndex = targetMsg.totalVariants;

    final existingSiblings = await chatRepository.getAllMessagesForThread(targetMsg.threadId);
    final variantSiblings = existingSiblings.where(
      (m) => m.role == MessageRole.assistant && m.parentId == targetMsg.parentId,
    );
    final memberIds = {
      ...variantSiblings.map((m) => m.id),
      targetMsg.id,
      newAssistantId,
    };

    // Persist the placeholder first so the group sync sees it, then normalise
    // every member's sibling list and count from what is actually stored.
    await chatRepository.saveMessage(ChatMessage(
      id: newAssistantId,
      threadId: targetMsg.threadId,
      parentId: targetMsg.parentId,
      role: MessageRole.assistant,
      content: targetMsg.content,
      status: MessageStatus.streaming,
      variantIndex: nextVariantIndex,
      siblingIds: memberIds.toList()..sort(),
    ));
    final group = variantGroupFields(memberIds);
    await _syncVariantGroup(
      threadId: targetMsg.threadId,
      memberIds: memberIds,
    );

    final newAssistantMsg = ChatMessage(
      id: newAssistantId,
      threadId: targetMsg.threadId,
      parentId: targetMsg.parentId,
      role: MessageRole.assistant,
      content: targetMsg.content,
      status: MessageStatus.streaming,
      variantIndex: nextVariantIndex,
      totalVariants: group.totalVariants,
      siblingIds: group.siblingIds,
    );

    messages[messageIndex] = newAssistantMsg;
    notifyListeners();

    return (newAssistantId: newAssistantId, oldMessageId: targetMsg.id);
  }

  /// Reverts a failed [doCreateImageVariant], restoring the original message.
  ///
  /// Called when a generation produces no image: leaving the empty placeholder
  /// (or worse, a caption-only message) behind would strand a variant the user
  /// has to navigate away from.
  ///
  /// The variant group is re-synced after the delete. Restoring the original
  /// with the bookkeeping it had *before* the placeholder existed is not enough:
  /// the original's own copy in the database already listed the placeholder as a
  /// sibling, so restoring it verbatim left a group advertising a variant that no
  /// longer existed — a live-looking "next" arrow that did nothing, with the user
  /// stranded on the old reply.
  Future<void> doRevertVariant({
    required int messageIndex,
    required String newAssistantId,
    required String oldMessageId,
  }) async {
    final idx = messages.indexWhere((m) => m.id == newAssistantId);
    if (idx == -1) return;
    // Only revert if our placeholder is still the one on screen; the user may
    // have navigated to another variant while the request was in flight.
    if (idx != messageIndex) return;
    final threadId = messages[idx].threadId;
    final parentId = messages[idx].parentId;

    await chatRepository.deleteMessage(newAssistantId);

    final remaining = (await chatRepository.getAllMessagesForThread(threadId))
        .where((m) => m.role == MessageRole.assistant && m.parentId == parentId)
        .map((m) => m.id)
        .toSet();

    ChatMessage? original;
    for (final msg in await chatRepository.getAllMessagesForThread(threadId)) {
      if (msg.id == oldMessageId) {
        original = msg;
        break;
      }
    }
    if (original == null) {
      // The original is gone too (deleted mid-flight); drop the placeholder.
      messages.removeAt(idx);
      notifyListeners();
      return;
    }

    // Recompute the surviving group from what is actually stored, so the
    // restored message no longer advertises the deleted placeholder.
    final fields = variantGroupFields(remaining);
    await _syncVariantGroup(
      threadId: threadId,
      memberIds: remaining,
    );
    final finalMessage = original.copyWith(
      totalVariants: fields.totalVariants,
      siblingIds: fields.siblingIds,
    );
    if (idx < messages.length) {
      messages[idx] = finalMessage;
    }
    notifyListeners();
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
