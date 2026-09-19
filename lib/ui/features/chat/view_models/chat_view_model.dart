import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
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
  // ignore: unnecessary_getters_setters
  List<ChatThread> get threads => _threads;
  set threads(List<ChatThread> v) => _threads = v;

  ChatThread? _activeThread;
  @override
  ChatThread? get activeThread => _activeThread;
  set activeThread(ChatThread? v) => _activeThread = v;

  List<ChatMessage> _messages = [];

  bool _isLoadingThreads = false;
  bool get isLoadingThreads => _isLoadingThreads;

  bool _isGenerating = false;

  @override
  bool get isGenerating => _isGenerating;
  @override
  set isGenerating(bool v) => _isGenerating = v;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  CancelToken? _currentCancelToken;
  Timer? _uiThrottleTimer;
  String _pendingStreamBuffer = '';
  String _pendingReasoningBuffer = '';

  @override
  Timer? get uiThrottleTimer => _uiThrottleTimer;
  @override
  set uiThrottleTimer(Timer? v) => _uiThrottleTimer = v;

  @override
  String get pendingStreamBuffer => _pendingStreamBuffer;
  @override
  set pendingStreamBuffer(String v) => _pendingStreamBuffer = v;

  @override
  String get pendingReasoningBuffer => _pendingReasoningBuffer;
  @override
  set pendingReasoningBuffer(String v) => _pendingReasoningBuffer = v;

  @override
  CancelToken? get currentCancelToken => _currentCancelToken;
  @override
  set currentCancelToken(CancelToken? v) => _currentCancelToken = v;

  @override
  ChatRepository get chatRepository => _chatRepository;

  @override
  List<ChatMessage> get messages => _messages;
  @override
  set messages(List<ChatMessage> v) => _messages = v;

  ChatViewModel(this._chatRepository) {
    loadThreads();
  }

  List<ChatThread> _filteredThreads = [];

  List<ChatThread> get filteredThreads {
    if (_searchQuery.trim().isEmpty) return _threads;
    if (_filteredThreads.isNotEmpty) return _filteredThreads;
    final q = _searchQuery.toLowerCase();
    return _threads.where((t) => t.title.toLowerCase().contains(q)).toList();
  }

  Future<List<ChatThread>> searchThreads({String? query}) async {
    final effectiveQuery = (query ?? _searchQuery).trim();
    if (effectiveQuery.isEmpty) return _threads;
    // Single SQL query in the database layer. The old implementation looped
    // every thread and loaded its full message list (N+1 queries on the UI
    // isolate) just to test a substring match.
    return await _chatRepository.searchThreads(effectiveQuery);
  }

  Future<void> loadThreads() async {
    _isLoadingThreads = true;
    notifyListeners();

    try {
      _threads = await _chatRepository.getAssistantThreads();
      _filteredThreads.clear();
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
    _filteredThreads.clear();
    _activeThread = newThread;
    _messages = [];
    notifyListeners();
    return newThread;
  }

  Future<void> renameThread(String threadId, String newTitle, {bool notify = true}) async {
    final index = _threads.indexWhere((t) => t.id == threadId);
    final ChatThread? base =
        index != -1 ? _threads[index] : (_activeThread?.id == threadId ? _activeThread : null);
    if (base == null) return;

    final updated = base.copyWith(title: newTitle, updatedAt: DateTime.now());
    _updateThreadInState(updated);
    await _chatRepository.updateThread(updated);
    if (notify) notifyListeners();
  }

  /// Applies [updated] to the in-memory thread list and active thread.
  /// The caller decides when to notify (see [renameThread]).
  void _updateThreadInState(ChatThread updated) {
    final index = _threads.indexWhere((t) => t.id == updated.id);
    if (index != -1) {
      _threads[index] = updated;
      _filteredThreads.clear();
    }
    if (_activeThread?.id == updated.id) {
      _activeThread = updated;
    }
  }

  Future<void> deleteThread(String threadId) async {
    // Clean up image attachment files before the thread's message rows vanish.
    final threadMessages = await _chatRepository.getAllMessagesForThread(threadId);
    for (final msg in threadMessages) {
      await MessageAttachmentStore.instance.deleteIfExists(msg.imagePath);
    }
    await _chatRepository.deleteThread(threadId);
    _threads.removeWhere((t) => t.id == threadId);
    _filteredThreads.clear();
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
    if (query.trim().isEmpty) {
      _filteredThreads.clear();
    }
    notifyListeners();
  }

  void setFilteredThreads(List<ChatThread> threads) {
    _filteredThreads = threads;
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
    final result = await doDeleteMessageHead(messageIndex: messageIndex);
    if (result == null) return false;

    if (result.threadToDelete != null) {
      await deleteThread(result.threadToDelete!);
      return true;
    }

    // If the deleted message was an AI response, generate a new one
    if (!result.isUserMessage && _messages.isNotEmpty) {
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

  /// Exports a thread to a file in the given format.
  /// Defaults to the active thread when no [thread] is given, so conversations
  /// can be exported from the drawer without selecting them first.
  /// Returns the path to the exported file, or null on error/cancel.
  Future<String?> exportThread(ExportFormat format, {ChatThread? thread}) async {
    final target = thread ?? _activeThread;
    if (target == null) return null;

    try {
      final messageList = target.id == _activeThread?.id
          ? _messages
          : await _chatRepository.getMessagesForThread(target.id);

      final content = format == ExportFormat.txt
          ? ConversationExport.toTxt(target, messageList)
          : ConversationExport.toJson(target, messageList);

      return await ConversationExport.saveToFile(target, content, format);
    } catch (_) {
      return null;
    }
  }

  /// Imports a thread from parsed JSON export data.
  /// Creates a new thread with the imported data, saves it to the database,
  /// and sets it as the active thread.
  Future<void> importThread(ChatThread thread, List<ChatMessage> messages) async {
    if (_isGenerating) {
      stopGeneration();
    }

    // Generate new IDs to avoid conflicts
    final newThread = thread.copyWith(
      id: const Uuid().v4(),
      title: thread.title,
      createdAt: thread.createdAt,
      updatedAt: DateTime.now(),
    );

    // Save thread to database and use the returned thread object
    final savedThread = await _chatRepository.createThread(
      title: newThread.title,
      systemPrompt: newThread.systemPrompt,
      modelId: newThread.modelId,
      customParams: newThread.customParams,
      characterId: null,
    );

    // Save all messages with new thread ID
    for (final msg in messages) {
      final newMsg = msg.copyWith(
        id: const Uuid().v4(),
        threadId: savedThread.id,
      );
      _messages.add(newMsg);
      await _chatRepository.saveMessage(newMsg);
    }

    // Reload threads and set as active
    _threads = await _chatRepository.getAssistantThreads();
    _filteredThreads.clear();
    _activeThread = savedThread;
    _messages = await _chatRepository.getMessagesForThread(savedThread.id);
    notifyListeners();
  }

  /// Sends a user message and streams the assistant response.
  Future<void> sendMessage({
    required String prompt,
    String? imagePath,
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
      imagePath: imagePath,
    );

    _messages.add(userMessage);
    await _chatRepository.saveMessage(userMessage);

    // Auto-update thread title if this is the first message
    if (_messages.length == 1 || _activeThread!.title == 'New Chat') {
      final autoTitle = prompt.trim().length > autoTitleMaxLen
          ? '${prompt.trim().substring(0, autoTitleMaxLen)}...'
          : prompt.trim();
      // Batched: the single notifyListeners() below reflects the rename too.
      await renameThread(threadId, autoTitle, notify: false);
    }

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

    // One notification for user message + title rename + placeholder.
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
    final result = await doRegenerateMessage(messageIndex: messageIndex);
    if (result == null) return;

    await _streamResponse(
      assistantMessageId: result.newAssistantId,
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
    final result = await doEditUserPrompt(messageIndex: messageIndex, newContent: newContent);
    if (result == null) return;

    // Spawn new assistant response
    final assistantMessageId = const Uuid().v4();
    final hasOldAssistant = result.oldAssistantId != null;

    final assistantPlaceholder = ChatMessage(
      id: assistantMessageId,
      threadId: _activeThread!.id,
      parentId: result.newUserMessage.id,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      variantIndex: hasOldAssistant ? 1 : 0,
      totalVariants: hasOldAssistant ? 2 : 1,
      siblingIds: hasOldAssistant ? [result.oldAssistantId!] : <String>[],
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
        if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length || _activeThread == null) {
    return;
  }
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
      branchFromThreadId: _activeThread!.id,
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
    final refreshed = await _chatRepository.getAssistantThreads();
    _threads = refreshed;

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
}
