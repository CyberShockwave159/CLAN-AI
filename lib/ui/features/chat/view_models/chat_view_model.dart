import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/file_saver.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/shared/mixins/stream_mutation_mixin.dart';

class ChatViewModel extends ChangeNotifier with StreamMutationMixin {
  final ChatRepository _chatRepository;

  List<ChatThread> _threads = [];
  List<ChatThread> get threads => _threads;
  set threads(List<ChatThread> v) => _threads = v;

  ChatThread? _activeThread;
  ChatThread? get activeThread => _activeThread;
  set activeThread(ChatThread? v) => _activeThread = v;

  List<ChatMessage> _messages = [];

  bool _isLoadingThreads = false;
  bool get isLoadingThreads => _isLoadingThreads;

  bool _isGenerating = false;

  @override
  bool get isGenerating => _isGenerating;
  set isGenerating(bool v) => _isGenerating = v;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  CancelToken? _currentCancelToken;
  Timer? _uiThrottleTimer;
  String _pendingStreamBuffer = '';
  String _pendingReasoningBuffer = '';

  @override
  Timer? get uiThrottleTimer => _uiThrottleTimer;
  set uiThrottleTimer(Timer? v) => _uiThrottleTimer = v;

  @override
  String get pendingStreamBuffer => _pendingStreamBuffer;
  set pendingStreamBuffer(String v) => _pendingStreamBuffer = v;

  @override
  String get pendingReasoningBuffer => _pendingReasoningBuffer;
  set pendingReasoningBuffer(String v) => _pendingReasoningBuffer = v;

  @override
  CancelToken? get currentCancelToken => _currentCancelToken;
  set currentCancelToken(CancelToken? v) => _currentCancelToken = v;

  @override
  ChatRepository get chatRepository => _chatRepository;

  @override
  List<ChatMessage> get messages => _messages;
  set messages(List<ChatMessage> v) => _messages = v;

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
    required ServerProfile? connection,
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
      storeUndoMessage(deletedMsg);
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
        connection: connection,
        customParams: customParams,
        modelContextLength: modelContextLength,
      );
      return false;
    }

    notifyListeners();
    return false;
  }

  /// Undo the last user message deletion.
  Future<void> undoDelete() => doUndoDelete();

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
    required ServerProfile? connection,
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
      final autoTitle = prompt.trim().length > autoTitleMaxLen
          ? '${prompt.trim().substring(0, autoTitleMaxLen)}...'
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
      connection: connection,
      customParams: customParams,
      modelContextLength: modelContextLength,
    );
  }

  /// Regenerates an assistant response at the given message index.
  Future<void> regenerateMessage({
    required int messageIndex,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
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
      connection: connection,
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
    required ServerProfile? connection,
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
      connection: connection,
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
    required ServerProfile? connection,
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
        connection: connection,
        customParams: customParams,
        modelContextLength: modelContextLength,
      );
    }
  }

  /// Switches the message at the given index to a different variant.
  Future<void> switchVariant({
    required int messageIndex,
    required bool previous,
  }) => doSwitchVariant(messageIndex: messageIndex, previous: previous);

  /// Delegates streaming to StreamMutationMixin.
  /// ChatViewModel uses it without post-stream hooks.
  Future<void> _streamResponse({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? upToIndex,
    int? modelContextLength,
  }) => _doStream(
    assistantMessageId: assistantMessageId,
    serverConfig: serverConfig,
    connection: connection,
    customParams: customParams,
    upToIndex: upToIndex,
    modelContextLength: modelContextLength,
  );

  Future<void> _doStream({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? upToIndex,
    int? modelContextLength,
  }) => doStreamResponse(
    assistantMessageId: assistantMessageId,
    serverConfig: serverConfig,
    connection: connection,
    customParams: customParams,
    upToIndex: upToIndex,
    modelContextLength: modelContextLength,
  );

  /// Cancels active streaming generation immediately.
  void stopGeneration() => doStopGeneration();

  @override
  void dispose() {
    uiThrottleTimer?.cancel();
    currentCancelToken?.cancel();
    super.dispose();
  }
}
