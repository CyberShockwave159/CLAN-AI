import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/file_saver.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class ChatViewModel extends ChangeNotifier {
  final ChatRepository _chatRepository;

  List<ChatThread> _threads = [];
  List<ChatThread> get threads => _threads;

  ChatThread? _activeThread;
  ChatThread? get activeThread => _activeThread;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  bool _isLoadingThreads = false;
  bool get isLoadingThreads => _isLoadingThreads;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  CancelToken? _currentCancelToken;
  Timer? _uiThrottleTimer;
  String _pendingStreamBuffer = '';
  String _pendingReasoningBuffer = '';

  // Undo support for message deletion
  ChatMessage? _undoneMessage;
  DateTime? _undoTimestamp;
  static const _undoTimeout = Duration(seconds: 5);

  ChatViewModel({ChatRepository? chatRepository})
      : _chatRepository = chatRepository ?? ChatRepository() {
    loadThreads();
  }

  List<ChatThread> get filteredThreads {
    if (_searchQuery.trim().isEmpty) return _threads;
    final q = _searchQuery.toLowerCase();
    return _threads.where((t) => t.title.toLowerCase().contains(q)).toList();
  }

  Future<void> loadThreads() async {
    _isLoadingThreads = true;
    notifyListeners();

    try {
      _threads = await _chatRepository.getAssistantThreads();
      if (_threads.isNotEmpty && _activeThread == null) {
        await selectThread(_threads.first);
      } else if (_threads.isEmpty) {
        await createNewThread();
      }
    } finally {
      _isLoadingThreads = false;
      notifyListeners();
    }
  }

  Future<void> selectThread(ChatThread thread) async {
    if (_isGenerating) {
      stopGeneration();
    }
    _activeThread = thread;
    _messages = await _chatRepository.getMessagesForThread(thread.id);
    notifyListeners();
  }

  Future<void> updateActiveThreadSystemPrompt(String systemPrompt) async {
    if (_activeThread == null) return;
    _activeThread = _activeThread!.copyWith(systemPrompt: systemPrompt);
    await _chatRepository.updateThread(_activeThread!);
    notifyListeners();
  }

  Future<ChatThread> createNewThread({
    String title = 'New Chat',
    String? systemPrompt,
    String? modelId,
  }) async {
    if (_isGenerating) {
      stopGeneration();
    }
    final newThread = await _chatRepository.createThread(
      title: title,
      systemPrompt: systemPrompt,
      modelId: modelId,
    );
    _threads.insert(0, newThread);
    _activeThread = newThread;
    _messages = [];
    notifyListeners();
    return newThread;
  }

  Future<void> renameThread(String threadId, String newTitle) async {
    final index = _threads.indexWhere((t) => t.id == threadId);
    if (index != -1) {
      final updated = _threads[index].copyWith(title: newTitle, updatedAt: DateTime.now());
      _threads[index] = updated;
      if (_activeThread?.id == threadId) {
        _activeThread = updated;
      }
      await _chatRepository.updateThread(updated);
      notifyListeners();
    }
  }

  Future<void> deleteThread(String threadId) async {
    await _chatRepository.deleteThread(threadId);
    _threads.removeWhere((t) => t.id == threadId);
    if (_activeThread?.id == threadId) {
      if (_threads.isNotEmpty) {
        await selectThread(_threads.first);
      } else {
        await createNewThread();
      }
    } else {
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Deletes a message and all messages after it.
  /// If the deleted message is an AI response, generates a new replacement response.
  /// Returns true if the thread should be deleted (first message was deleted).
  Future<bool> deleteMessage({
    required int messageIndex,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length || _activeThread == null) return false;

    final deletedMsg = _messages[messageIndex];
    final isFirstMessage = messageIndex == 0;
    final isUserMessage = deletedMsg.role == MessageRole.user;

    // Determine which messages to delete: this one and all after it
    final messagesToDelete = _messages.sublist(messageIndex);

    // Delete from database
    for (final msg in messagesToDelete) {
      await _chatRepository.deleteMessage(msg.id);
    }

    // If this was the only message (or first message) in the thread, delete the whole thread
    if (isFirstMessage) {
      await deleteThread(_activeThread!.id);
      return true;
    }

    // Keep messages before the deleted one
    _messages = _messages.sublist(0, messageIndex);

    // Store for undo (only user messages, not AI responses that trigger regeneration)
    if (isUserMessage) {
      _undoneMessage = deletedMsg;
      _undoTimestamp = DateTime.now();
    }

    // If the deleted message was an AI response, generate a new one
    if (!isUserMessage && _messages.isNotEmpty) {
      // Find the last user message in the remaining history
      final lastUserMsg = _messages.reversed.firstWhere(
        (m) => m.role == MessageRole.user,
        orElse: () => _messages.last,
      );

      // Prepare new assistant message
      final newAssistantId = const Uuid().v4();
      final newAssistantMsg = ChatMessage(
        id: newAssistantId,
        threadId: _activeThread!.id,
        parentId: lastUserMsg.id,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
      );

     _messages.add(newAssistantMsg);
      notifyListeners();

      await _streamResponse(
        assistantMessageId: newAssistantId,
        serverConfig: serverConfig,
        customParams: customParams,
        modelContextLength: modelContextLength,
      );
      return false;
    }

    notifyListeners();
    return false;
  }

  /// Undo the last user message deletion.
  Future<void> undoDelete() async {
    if (_undoneMessage == null || _undoTimestamp == null) return;
    if (DateTime.now().difference(_undoTimestamp!) > _undoTimeout) {
      _undoneMessage = null;
      _undoTimestamp = null;
      return;
    }
    if (_activeThread == null) {
      _undoneMessage = null;
      _undoTimestamp = null;
      return;
    }

    await _chatRepository.saveMessage(_undoneMessage!);
    _messages = await _chatRepository.getMessagesForThread(_activeThread!.id);
    _undoneMessage = null;
    _undoTimestamp = null;
    notifyListeners();
  }

  /// Check if undo is available and not expired.
  bool get canUndo {
    return _undoneMessage != null && 
           _undoTimestamp != null && 
           DateTime.now().difference(_undoTimestamp!) <= _undoTimeout;
  }

  /// Exports the active thread to a file in the given format.
  /// Returns the path to the exported file, or null on error/cancel.
  Future<String?> exportThread(ExportFormat format) async {
    if (_activeThread == null) return null;

    try {
      final content = format == ExportFormat.txt
          ? ConversationExport.toTxt(_activeThread!, _messages)
          : ConversationExport.toJson(_activeThread!, _messages);

      final sanitizedTitle = _activeThread!.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final extension = format == ExportFormat.txt ? 'txt' : 'json';
      final filename = 'clan_ai_$sanitizedTitle.$extension';
      final mimeType = format == ExportFormat.json ? 'application/json' : 'text/plain';

      return await FileSaver.saveFile(
        filename: filename,
        content: content,
        mimeType: mimeType,
      );
    } catch (_) {
      return null;
    }
  }

  /// Sends a user message and streams the assistant response.
  Future<void> sendMessage({
    required String prompt,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (prompt.trim().isEmpty || _isGenerating) return;

    if (_activeThread == null) {
      await createNewThread();
    }

    final threadId = _activeThread!.id;

    // 1. Create and persist User Message
    final userMessage = ChatMessage(
      threadId: threadId,
      role: MessageRole.user,
      content: prompt.trim(),
      status: MessageStatus.completed,
    );

    _messages.add(userMessage);
    await _chatRepository.saveMessage(userMessage);

    // Auto-update thread title if this is the first message
    if (_messages.length == 1 || _activeThread!.title == 'New Chat') {
      final autoTitle = prompt.trim().length > 32
          ? '${prompt.trim().substring(0, 32)}...'
          : prompt.trim();
      await renameThread(threadId, autoTitle);
    }

    notifyListeners();

    // 2. Prepare Assistant Message Placeholder
    final assistantMessageId = const Uuid().v4();
    final assistantPlaceholder = ChatMessage(
      id: assistantMessageId,
      threadId: threadId,
      parentId: userMessage.id,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
    );

    _messages.add(assistantPlaceholder);
    notifyListeners();

    // 3. Initiate Streaming Generation
    await _streamResponse(
      assistantMessageId: assistantMessageId,
      serverConfig: serverConfig,
      customParams: customParams,
      modelContextLength: modelContextLength,
    );
  }

  /// Regenerates an assistant response at the given message index.
  Future<void> regenerateMessage({
    required int messageIndex,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length) return;

    final targetMsg = _messages[messageIndex];
    if (targetMsg.role != MessageRole.assistant) return;

    // Find parent user message
    final parentId = targetMsg.parentId;
    final newAssistantId = const Uuid().v4();
    final nextVariantIndex = targetMsg.totalVariants;
    final newTotalVariants = targetMsg.totalVariants + 1;

    // Update old message with new variant info before replacing it
    final updatedOldMsg = targetMsg.copyWith(
      variantIndex: targetMsg.variantIndex,
      totalVariants: newTotalVariants,
      siblingIds: [...targetMsg.siblingIds, newAssistantId],
    );
    _messages[messageIndex] = updatedOldMsg;
    await _chatRepository.saveMessage(updatedOldMsg);

    final newAssistantMsg = ChatMessage(
      id: newAssistantId,
      threadId: targetMsg.threadId,
      parentId: parentId,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      variantIndex: nextVariantIndex,
      totalVariants: newTotalVariants,
      siblingIds: [...targetMsg.siblingIds, targetMsg.id],
    );

    // Replace current visible message with new streaming message
    _messages[messageIndex] = newAssistantMsg;
    notifyListeners();

    await _streamResponse(
      assistantMessageId: newAssistantId,
      serverConfig: serverConfig,
      customParams: customParams,
      upToIndex: messageIndex,
      modelContextLength: modelContextLength,
    );
  }

  /// Edits a previous user prompt, branching the conversation.
  Future<void> editUserPrompt({
    required int messageIndex,
    required String newContent,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length) return;

    final oldUserMsg = _messages[messageIndex];
    if (oldUserMsg.role != MessageRole.user) return;

    // Handle the old assistant response (at messageIndex + 1) as a sibling variant
    String? oldAssistantId;
    final oldAssistantMsgIndex = messageIndex + 1;
    if (oldAssistantMsgIndex < _messages.length && _messages[oldAssistantMsgIndex].role == MessageRole.assistant) {
      final oldAssistantMsg = _messages[oldAssistantMsgIndex];
      oldAssistantId = oldAssistantMsg.id;
      final newAssistantId = const Uuid().v4();
      final newTotalVariants = oldAssistantMsg.totalVariants + 1;

      final updatedOldAssistant = oldAssistantMsg.copyWith(
        totalVariants: newTotalVariants,
        siblingIds: [...oldAssistantMsg.siblingIds, newAssistantId],
      );
      await _chatRepository.saveMessage(updatedOldAssistant);
    }

    final newUserMsg = oldUserMsg.copyWith(
      id: const Uuid().v4(),
      content: newContent.trim(),
      variantIndex: oldUserMsg.totalVariants,
      totalVariants: oldUserMsg.totalVariants + 1,
      siblingIds: [...oldUserMsg.siblingIds, oldUserMsg.id],
      createdAt: DateTime.now(),
    );
    await _chatRepository.saveMessage(newUserMsg);

    // Truncate messages after this point and insert new user message
    _messages = _messages.sublist(0, messageIndex);
    _messages.add(newUserMsg);
    notifyListeners();

    // Spawn new assistant response
    final assistantMessageId = const Uuid().v4();
    final hasOldAssistant = oldAssistantId != null;

    final assistantPlaceholder = ChatMessage(
      id: assistantMessageId,
      threadId: _activeThread!.id,
      parentId: newUserMsg.id,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      variantIndex: hasOldAssistant ? 1 : 0,
      totalVariants: hasOldAssistant ? 2 : 1,
      siblingIds: hasOldAssistant ? [oldAssistantId] : <String>[],
    );
    _messages.add(assistantPlaceholder);
    notifyListeners();

    await _streamResponse(
      assistantMessageId: assistantMessageId,
      serverConfig: serverConfig,
      customParams: customParams,
      modelContextLength: modelContextLength,
    );
  }

  /// Branches the conversation at the given message point.
  /// Creates a new thread with an identical message history up to (and including) the branch point.
  /// If branching from a user message, also sends it to the API to generate the next AI response.
  Future<void> branchConversation({
    required int messageIndex,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length || _activeThread == null) return;

    final branchPoint = _messages[messageIndex];
    final messagesToCopy = _messages.sublist(0, messageIndex + 1);
    final isUserBranchPoint = branchPoint.role == MessageRole.user;

    if (isUserBranchPoint) {
      if (messagesToCopy.length < 2) return;
    } else {
      if (messagesToCopy.isEmpty) return;
    }

    // Determine the new thread title
    String newTitle;
    if (_activeThread!.branchFromThreadId != null) {
      final parentThread = _threads.firstWhere(
        (t) => t.id == _activeThread!.branchFromThreadId,
        orElse: () => _activeThread!,
      );
      newTitle = '${parentThread.title} (Branch)';
    } else {
      newTitle = '${_activeThread!.title} (Branch)';
    }

    // Create new thread
    final newThread = await _chatRepository.createThread(
      title: newTitle,
      systemPrompt: _activeThread!.systemPrompt,
      modelId: _activeThread!.modelId ?? serverConfig.selectedModel,
    );

    // Copy messages to the new thread
    for (final msg in messagesToCopy) {
      final newMsg = msg.copyWith(
        id: const Uuid().v4(),
        threadId: newThread.id,
        createdAt: msg.createdAt.isAfter(newThread.createdAt) ? msg.createdAt : newThread.createdAt,
      );
      await _chatRepository.saveMessage(newMsg);
    }

    // Update the parent thread to reference the branch
    final updatedParent = _activeThread!.copyWith(
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedParent);

    // Set branchFromThreadId on the new thread
    final branchThreadWithLink = newThread.copyWith(
      branchFromThreadId: _activeThread!.id,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(branchThreadWithLink);

    // Refresh threads list (getAssistantThreads filters out roleplay threads)
    _threads = await _chatRepository.getAssistantThreads();

    // Select the new thread
    await selectThread(branchThreadWithLink);

    // If branching from a user message, send it to the API
    if (isUserBranchPoint) {
      final lastUserMsg = messagesToCopy.last;

      // Prepare Assistant Message Placeholder
      final assistantMessageId = const Uuid().v4();
      final assistantPlaceholder = ChatMessage(
        id: assistantMessageId,
        threadId: branchThreadWithLink.id,
        parentId: lastUserMsg.id,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
      );

      _messages.add(assistantPlaceholder);
      notifyListeners();

      await _streamResponse(
        assistantMessageId: assistantMessageId,
        serverConfig: serverConfig,
        customParams: customParams,
        modelContextLength: modelContextLength,
      );
    }
  }

  /// Switches the message at the given index to a different variant.
  Future<void> switchVariant({
    required int messageIndex,
    required bool previous,
  }) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;

    final currentMsg = _messages[messageIndex];
    if (currentMsg.siblingIds.isEmpty) return;

    final siblingIndex = previous ? currentMsg.variantIndex - 1 : currentMsg.variantIndex;
    if (siblingIndex < 0 || siblingIndex >= currentMsg.siblingIds.length) return;

    final siblingId = currentMsg.siblingIds[siblingIndex];
    final siblingMsg = await _chatRepository.getMessagesForThread(currentMsg.threadId).then(
      (msgs) => msgs.firstWhere((m) => m.id == siblingId, orElse: () => currentMsg),
    );

    if (siblingMsg.id != currentMsg.id) {
      _messages[messageIndex] = siblingMsg;
      notifyListeners();
    }
  }

  Future<void> _streamResponse({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? upToIndex,
    int? modelContextLength,
  }) async {
    _isGenerating = true;
    _currentCancelToken = CancelToken();
    _pendingStreamBuffer = '';
    _pendingReasoningBuffer = '';
    notifyListeners();

    final historySlice = upToIndex != null
        ? _messages.sublist(0, upToIndex)
        : _messages.sublist(0, _messages.indexWhere((m) => m.id == assistantMessageId));

    final effectiveSystemPrompt = _activeThread?.systemPrompt ?? serverConfig.systemPrompt;

    // Setup 60fps UI throttle timer (16ms) to avoid Flutter frame drops during rapid streaming
    _uiThrottleTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final currentMsgIndex = _messages.indexWhere((m) => m.id == assistantMessageId);
      if (_pendingStreamBuffer.isNotEmpty &&
          currentMsgIndex >= 0 &&
          currentMsgIndex < _messages.length) {
        final currentMsg = _messages[currentMsgIndex];
        _messages[currentMsgIndex] = currentMsg.copyWith(
          content: currentMsg.content + _pendingStreamBuffer,
        );
        _pendingStreamBuffer = '';
        notifyListeners();
      }
      if (_pendingReasoningBuffer.isNotEmpty &&
          currentMsgIndex >= 0 &&
          currentMsgIndex < _messages.length) {
        final currentMsg = _messages[currentMsgIndex];
        _messages[currentMsgIndex] = currentMsg.copyWith(
          reasoningContent: currentMsg.reasoningContent + _pendingReasoningBuffer,
        );
        _pendingReasoningBuffer = '';
        notifyListeners();
      }
    });

    StreamMetrics? finalMetrics;
    String? errorMessage;

    try {
      final stream = _chatRepository.streamCompletion(
        serverConfig: serverConfig,
        history: historySlice,
        systemPrompt: effectiveSystemPrompt,
        params: customParams ?? _activeThread?.customParams ?? serverConfig.defaultParams,
        cancelToken: _currentCancelToken,
        modelContextLength: modelContextLength,
      );

      await for (final chunk in stream) {
        if (chunk.text.isNotEmpty) {
          _pendingStreamBuffer += chunk.text;
        }
        if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          _pendingReasoningBuffer += chunk.reasoning!;
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
        errorMessage = '$errorMessage\n\n💡 Tip: ${e.recoverySuggestion}';
      }
    } finally {
      _uiThrottleTimer?.cancel();
      _uiThrottleTimer = null;

      // Flush any remaining characters in the buffer
      final finalMsgIndex = _messages.indexWhere((m) => m.id == assistantMessageId);
      if (finalMsgIndex >= 0 && finalMsgIndex < _messages.length) {
        final currentMsg = _messages[finalMsgIndex];
        final finalContent = currentMsg.content + _pendingStreamBuffer;
        _pendingStreamBuffer = '';

        final completedMsg = currentMsg.copyWith(
          content: finalContent,
          reasoningContent: currentMsg.reasoningContent + _pendingReasoningBuffer,
          status: errorMessage != null
              ? MessageStatus.error
              : MessageStatus.completed,
          errorMessage: errorMessage,
          tokensPerSecond: finalMetrics?.tokensPerSecond,
          totalTokens: finalMetrics?.completionTokens,
          timeToFirstTokenMs: finalMetrics?.timeToFirstTokenMs,
          generationTimeSec: finalMetrics?.generationTimeSec,
        );

        _messages[finalMsgIndex] = completedMsg;
        await _chatRepository.saveMessage(completedMsg);
      }

      _pendingReasoningBuffer = '';

      _isGenerating = false;
      _currentCancelToken = null;
      notifyListeners();
    }
  }

  /// Cancels active streaming generation immediately.
  void stopGeneration() {
    if (_isGenerating && _currentCancelToken != null) {
      _currentCancelToken?.cancel();
      _isGenerating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _uiThrottleTimer?.cancel();
    _currentCancelToken?.cancel();
    super.dispose();
  }
}
