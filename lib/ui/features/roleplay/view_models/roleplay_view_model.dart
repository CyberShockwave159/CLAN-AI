import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/file_saver.dart';
import 'package:clan_ai/core/utils/roleplay_context_builder.dart';
import 'package:clan_ai/data/datasources/embedding_service.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class RoleplayViewModel extends ChangeNotifier {
  final ChatRepository _chatRepository;
  final   CharacterRepository _characterRepository;

  CharacterProfile? _activeCharacter;
  CharacterProfile? get activeCharacter => _activeCharacter;

  ChatThread? _activeThread;
  ChatThread? get activeThread => _activeThread;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  bool _isGenerating = false;
  bool get isGenerating => _isGenerating;

  CancelToken? _currentCancelToken;
  Timer? _uiThrottleTimer;
  String _pendingStreamBuffer = '';
  String _pendingReasoningBuffer = '';

  final Map<String, Future<List<ChatThread>>> _threadCache = {};

  // Undo support for message deletion
  ChatMessage? _undoneMessage;
  DateTime? _undoTimestamp;
  static const _undoTimeout = Duration(seconds: 5);

  RoleplayViewModel({
    ChatRepository? chatRepository,
    CharacterRepository? characterRepository,
  })  : _chatRepository = chatRepository ?? ChatRepository(),
        _characterRepository = characterRepository ?? CharacterRepository() {
    _init();
  }

  Future<void> _init() async {
    await loadLastChat();
  }

  Future<void> loadLastChat() async {
    try {
      final threads = await _chatRepository.getThreads();
      var roleplayThreads = threads.where((t) => t.characterId != null).toList();

      // If no threads with characterId, try all threads (legacy migration fallback)
      if (roleplayThreads.isEmpty) {
        roleplayThreads = threads;
      }

      if (roleplayThreads.isEmpty) {
        _activeThread = null;
        _activeCharacter = null;
        _messages = [];
        notifyListeners();
        return;
      }

      // Sort by updatedAt descending (most recent first)
      roleplayThreads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final lastThread = roleplayThreads.first;

      // If thread has no characterId, try to infer from first assistant message
      if (lastThread.characterId == null) {
        final messages = await _chatRepository.getMessagesForThread(lastThread.id);
        if (messages.isNotEmpty) {
          // Use first character for now (will be updated when user sends new message)
          final characters = await _characterRepository.getAllCharacters();
          if (characters.isNotEmpty) {
            _activeCharacter = characters.first;
            _activeThread = lastThread;
            _messages = messages;
            notifyListeners();
            return;
          }
        }
      } else {
        // Verify the character still exists
        final character = await _characterRepository.getCharacterById(lastThread.characterId!);
        if (character != null) {
          _activeCharacter = character;
          _activeThread = lastThread;
          _messages = await _chatRepository.getMessagesForThread(lastThread.id);
          notifyListeners();
          return;
        }
      }

      await _createNewSession();
    } catch (_) {
      await _createNewSession();
    }
  }

  Future<void> _createNewSession() async {
    final characters = await _characterRepository.getAllCharacters();
    if (characters.isEmpty) {
      _activeThread = null;
      _activeCharacter = null;
      _messages = [];
      notifyListeners();
      return;
    }

    // Use the first character as default
    final defaultCharacter = characters.first;
    _activeCharacter = defaultCharacter;
    _activeThread = null;
    _messages = [];
    notifyListeners();
  }

  /// Updates the active character if it matches the updated character's ID.
  void updateActiveCharacter(CharacterProfile updated) {
    if (_activeCharacter?.id == updated.id) {
      _activeCharacter = updated;
      notifyListeners();
    }
  }

  /// Start a roleplay session with the given character.
  /// Reuses existing thread for this character if one exists, otherwise creates a new one.
  Future<void> startRoleplay(CharacterProfile character, {
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    await _startRoleplayWithGreeting(character, character.firstMessage, serverConfig: serverConfig, customParams: customParams, modelContextLength: modelContextLength);
  }

  /// Start a new conversation with the character using an alternate greeting.
  Future<void> startRoleplayWithGreeting(CharacterProfile character, String greeting, {
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    await _startRoleplayWithGreeting(character, greeting, serverConfig: serverConfig, customParams: customParams, modelContextLength: modelContextLength);
  }

  /// Start a roleplay session with a specific greeting message.
  /// This is used for alternate greetings.
  Future<void> _startRoleplayWithGreeting(CharacterProfile character, String greeting, {
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating) {
      stopGeneration();
    }

    _activeCharacter = character;

    // Check if a thread already exists for this character
    final characterThreads = await _chatRepository.getThreadsForCharacter(character.id);
    if (characterThreads.isNotEmpty) {
      // Reuse existing thread
      characterThreads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _activeThread = characterThreads.first;
      _messages = await _chatRepository.getMessagesForThread(_activeThread!.id);
      notifyListeners();
      return;
    }

    // Build initial system prompt with RAG (empty memories on first message)
    final initialContext = await RoleplayContextBuilder().build(
      characterId: character.id,
      characterName: character.name,
      personality: character.personality,
      setting: character.setting,
      userPersona: character.userPersona,
      characterSystemPrompt: character.systemPrompt,
      postHistoryInstructions: character.postHistoryInstructions,
      userInput: '',
    );

    final newThread = await _chatRepository.createThread(
      title: character.name,
      systemPrompt: initialContext.systemPrompt,
      modelId: serverConfig.selectedModel,
    );

    // Update thread with character reference
    final threadWithCharacter = newThread.copyWith(
      characterId: character.id,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(threadWithCharacter);

    _activeThread = threadWithCharacter;
    _messages = [];

    // Set the character's greeting as the initial assistant message
    final firstAssistantId = const Uuid().v4();
    final firstAssistantMsg = ChatMessage(
      id: firstAssistantId,
      threadId: threadWithCharacter.id,
      parentId: null,
      role: MessageRole.assistant,
      content: greeting,
      status: MessageStatus.completed,
    );
    _messages.add(firstAssistantMsg);
    await _chatRepository.saveMessage(firstAssistantMsg);

    // Embed the first message for RAG memory
    _embedMessageAsync(character.id, firstAssistantId, greeting, isFirstMessage: true);

    notifyListeners();
  }

  /// Send a user message and stream the character's response.
  Future<void> sendMessage({
    required String prompt,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (prompt.trim().isEmpty || _isGenerating || _activeThread == null || _activeCharacter == null) return;

    final threadId = _activeThread!.id;
    final character = _activeCharacter!;

    // 1. Create User Message
    final userMessage = ChatMessage(
      threadId: threadId,
      role: MessageRole.user,
      content: prompt.trim(),
      status: MessageStatus.completed,
    );

    _messages.add(userMessage);
    await _chatRepository.saveMessage(userMessage);

    // Auto-update thread title if this is the first user message (similar to assistant mode)
    if (_messages.where((m) => m.role == MessageRole.user).length == 1) {
      final autoTitle = prompt.trim().length > 32
          ? '${prompt.trim().substring(0, 32)}...'
          : prompt.trim();
      final titleUpdatedThread = _activeThread!.copyWith(title: autoTitle);
      await _chatRepository.updateThread(titleUpdatedThread);
      _activeThread = titleUpdatedThread;
    }

    notifyListeners();

    // 2. Build RAG context (embed + search memories)
    final contextBuilder = RoleplayContextBuilder();
    final context = await contextBuilder.build(
      characterId: character.id,
      characterName: character.name,
      personality: character.personality,
      setting: character.setting,
      userPersona: character.userPersona,
      characterSystemPrompt: character.systemPrompt,
      postHistoryInstructions: character.postHistoryInstructions,
      userInput: prompt,
    );

    // 3. Update thread system prompt with retrieved memories
    final updatedThread = _activeThread!.copyWith(
      systemPrompt: context.systemPrompt,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedThread);

    // 4. Prepare Assistant Message Placeholder
    final assistantMessageId = const Uuid().v4();
    final ragMemoryCount = context.memories.isNotEmpty ? context.memories.length : null;
    final assistantPlaceholder = ChatMessage(
      id: assistantMessageId,
      threadId: threadId,
      parentId: userMessage.id,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      ragMemoryCount: ragMemoryCount,
    );

    _messages.add(assistantPlaceholder);
    notifyListeners();

    // 5. Stream response
    await _streamResponse(
      assistantMessageId: assistantMessageId,
      serverConfig: serverConfig,
      customParams: customParams,
      modelContextLength: modelContextLength,
      ragMemoryCount: ragMemoryCount,
    );
  }

  Future<void> regenerateMessage({
    required int messageIndex,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length) return;

    final targetMsg = _messages[messageIndex];
    if (targetMsg.role != MessageRole.assistant) return;

    final parentId = targetMsg.parentId;
    final newAssistantId = const Uuid().v4();
    final nextVariantIndex = targetMsg.totalVariants;
    final newTotalVariants = targetMsg.totalVariants + 1;

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

    _messages[messageIndex] = newAssistantMsg;
    notifyListeners();

    await _streamResponse(
      assistantMessageId: newAssistantId,
      serverConfig: serverConfig,
      customParams: customParams,
      modelContextLength: modelContextLength,
    );
  }

  Future<void> editUserPrompt({
    required int messageIndex,
    required String newContent,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length || _activeCharacter == null) return;

    final oldUserMsg = _messages[messageIndex];
    if (oldUserMsg.role != MessageRole.user) return;

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

    _messages = _messages.sublist(0, messageIndex);
    _messages.add(newUserMsg);
    notifyListeners();

    // Rebuild RAG context for the new prompt
    final contextBuilder = RoleplayContextBuilder();
    final context = await contextBuilder.build(
      characterId: _activeCharacter!.id,
      characterName: _activeCharacter!.name,
      personality: _activeCharacter!.personality,
      setting: _activeCharacter!.setting,
      userPersona: _activeCharacter!.userPersona,
      characterSystemPrompt: _activeCharacter!.systemPrompt,
      postHistoryInstructions: _activeCharacter!.postHistoryInstructions,
      userInput: newContent,
    );

    final updatedThread = _activeThread!.copyWith(
      systemPrompt: context.systemPrompt,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedThread);

    final assistantMessageId = const Uuid().v4();
    final hasOldAssistant = oldAssistantId != null;
    final ragMemoryCount = context.memories.isNotEmpty ? context.memories.length : null;

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
      ragMemoryCount: ragMemoryCount,
    );
    _messages.add(assistantPlaceholder);
    notifyListeners();

    await _streamResponse(
      assistantMessageId: assistantMessageId,
      serverConfig: serverConfig,
      customParams: customParams,
      modelContextLength: modelContextLength,
      ragMemoryCount: ragMemoryCount,
    );
  }

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

    String newTitle = '${_activeCharacter!.name} (Branch)';

    final newThread = await _chatRepository.createThread(
      title: newTitle,
      systemPrompt: _activeThread!.systemPrompt,
      modelId: _activeThread!.modelId,
    );

    final branchThreadWithLink = newThread.copyWith(
      characterId: _activeCharacter!.id,
      branchFromThreadId: _activeThread!.id,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(branchThreadWithLink);

    for (final msg in messagesToCopy) {
      final newMsg = msg.copyWith(
        id: const Uuid().v4(),
        threadId: branchThreadWithLink.id,
        createdAt: msg.createdAt.isAfter(newThread.createdAt) ? msg.createdAt : newThread.createdAt,
      );
      await _chatRepository.saveMessage(newMsg);
    }

    final updatedParent = _activeThread!.copyWith(
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedParent);

    await selectThread(branchThreadWithLink);

    if (isUserBranchPoint) {
      final lastUserMsg = messagesToCopy.last;

      // Determine rag memory count from the last assistant message in the branch point
      int? branchRagCount;
      // Try to find RAG memory count from the last assistant message in messagesToCopy
      for (int i = messagesToCopy.length - 1; i >= 0; i--) {
        final msg = messagesToCopy[i];
        if (msg.role == MessageRole.assistant && msg.ragMemoryCount != null) {
          branchRagCount = msg.ragMemoryCount;
          break;
        }
      }

      final assistantMessageId = const Uuid().v4();
      final assistantPlaceholder = ChatMessage(
        id: assistantMessageId,
        threadId: branchThreadWithLink.id,
        parentId: lastUserMsg.id,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
        ragMemoryCount: branchRagCount,
      );

      _messages.add(assistantPlaceholder);
      notifyListeners();

      await _streamResponse(
        assistantMessageId: assistantMessageId,
        serverConfig: serverConfig,
        customParams: customParams,
        modelContextLength: modelContextLength,
        ragMemoryCount: branchRagCount,
      );
    }
  }

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

  Future<void> selectThread(ChatThread thread) async {
    if (_isGenerating) {
      stopGeneration();
    }

    // Ensure character is set (for newly created branch threads)
    if (_activeCharacter == null && thread.characterId != null) {
      _activeCharacter = await _characterRepository.getCharacterById(thread.characterId!);
    }

    _activeThread = thread;
    _messages = await _chatRepository.getMessagesForThread(thread.id);
    notifyListeners();
  }

  /// Returns all roleplay threads for a character, sorted by updatedAt desc.
  /// Used by the RoleplayDrawer to display conversation branches.
  Future<List<ChatThread>> getThreadsForCharacter(String characterId) async {
    return await _chatRepository.getThreadsForCharacter(characterId);
  }

  /// Cached version of getThreadsForCharacter to avoid repeated FutureBuilder calls.
  Future<List<ChatThread>> getCachedThreadsForCharacter(String characterId) {
    if (!_threadCache.containsKey(characterId)) {
      _threadCache[characterId] = _chatRepository.getThreadsForCharacter(characterId);
    }
    return _threadCache[characterId]!;
  }

  void _clearThreadCache(String? characterId) {
    if (characterId != null) _threadCache.remove(characterId);
  }

  void deleteCharacter(String characterId) {
    _threadCache.remove(characterId);
  }

  Future<void> editAssistantMessage({
    required int messageIndex,
    required String newContent,
  }) async {
    if (_isGenerating || messageIndex < 0 || messageIndex >= _messages.length) return;

    final targetMsg = _messages[messageIndex];
    if (targetMsg.role != MessageRole.assistant || targetMsg.status != MessageStatus.completed) return;

    // Only allow editing the last message (no subsequent user messages)
    if (messageIndex != _messages.length - 1) return;

    final updated = targetMsg.copyWith(
      content: newContent.trim(),
      isEdited: true,
      updatedAt: DateTime.now(),
    );

    // Save to database
    await _chatRepository.updateMessage(updated);

    // Update in-memory list
    _messages[messageIndex] = updated;
    notifyListeners();

    // Re-embed edited content into RAG (replaces old embedding)
    if (_activeCharacter != null) {
      _embedMessageAsync(_activeCharacter!.id, updated.id, updated.content);
    }
  }

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

    final messagesToDelete = _messages.sublist(messageIndex);

    for (final msg in messagesToDelete) {
      await _chatRepository.deleteMessage(msg.id);
    }

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

    if (!isUserMessage && _messages.isNotEmpty) {
      final lastUserMsg = _messages.reversed.firstWhere(
        (m) => m.role == MessageRole.user,
        orElse: () => _messages.last,
      );

      // Rebuild RAG context for regeneration
      final contextBuilder = RoleplayContextBuilder();
      final context = await contextBuilder.build(
        characterId: _activeCharacter!.id,
        characterName: _activeCharacter!.name,
        personality: _activeCharacter!.personality,
        setting: _activeCharacter!.setting,
        userPersona: _activeCharacter!.userPersona,
        characterSystemPrompt: _activeCharacter!.systemPrompt,
        postHistoryInstructions: _activeCharacter!.postHistoryInstructions,
        userInput: lastUserMsg.content,
      );
      final ragMemoryCount = context.memories.isNotEmpty ? context.memories.length : null;

      final newAssistantId = const Uuid().v4();
      final newAssistantMsg = ChatMessage(
        id: newAssistantId,
        threadId: _activeThread!.id,
        parentId: lastUserMsg.id,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
        ragMemoryCount: ragMemoryCount,
      );

      _messages.add(newAssistantMsg);
      notifyListeners();

      await _streamResponse(
        assistantMessageId: newAssistantId,
        serverConfig: serverConfig,
        customParams: customParams,
        modelContextLength: modelContextLength,
        ragMemoryCount: ragMemoryCount,
      );
      return false;
    }

    notifyListeners();
    return false;
  }

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

  bool get canUndo {
    return _undoneMessage != null &&
        _undoTimestamp != null &&
        DateTime.now().difference(_undoTimestamp!) <= _undoTimeout;
  }

  Future<void> deleteThread(String threadId) async {
    if (_activeCharacter != null) {
      final threadMessages = await _chatRepository.getMessagesForThread(threadId);
      final messageIds = threadMessages.map((m) => m.id).toList();
      await _characterRepository.deleteEmbeddingsForMessages(_activeCharacter!.id, messageIds);
    }
    await _chatRepository.deleteThread(threadId);
    _clearThreadCache(_activeCharacter?.id);
    _activeThread = null;
    _messages = [];
    notifyListeners();
  }

  void stopGeneration() {
    if (_isGenerating && _currentCancelToken != null) {
      _currentCancelToken?.cancel();
      _isGenerating = false;
      notifyListeners();
    }
  }

  Future<void> _streamResponse({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    GenerationParams? customParams,
    int? modelContextLength,
    int? ragMemoryCount,
  }) async {
    _isGenerating = true;
    _currentCancelToken = CancelToken();
    _pendingStreamBuffer = '';
    _pendingReasoningBuffer = '';
    notifyListeners();

    final msgIndex = _messages.indexWhere((m) => m.id == assistantMessageId);
    if (msgIndex == -1) {
      _isGenerating = false;
      notifyListeners();
      return;
    }

    final historySlice = _messages.sublist(0, msgIndex);
    final effectiveSystemPrompt = _activeThread?.systemPrompt ?? serverConfig.systemPrompt;

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
      // Stopped gracefully
    } catch (e) {
      errorMessage = e.toString();
      if (e is AppException && e.recoverySuggestion != null) {
        errorMessage = '$errorMessage\n\nTip: ${e.recoverySuggestion}';
      }
    } finally {
      _uiThrottleTimer?.cancel();
      _uiThrottleTimer = null;

      if (msgIndex >= 0 && msgIndex < _messages.length) {
        final currentMsg = _messages[msgIndex];
        final finalContent = currentMsg.content + _pendingStreamBuffer;
        _pendingStreamBuffer = '';

        final completedMsg = currentMsg.copyWith(
          content: finalContent,
          reasoningContent: currentMsg.reasoningContent + _pendingReasoningBuffer,
          status: errorMessage != null ? MessageStatus.error : MessageStatus.completed,
          errorMessage: errorMessage,
          tokensPerSecond: finalMetrics?.tokensPerSecond,
          totalTokens: finalMetrics?.completionTokens,
          timeToFirstTokenMs: finalMetrics?.timeToFirstTokenMs,
          generationTimeSec: finalMetrics?.generationTimeSec,
          ragMemoryCount: ragMemoryCount,
        );

        _messages[msgIndex] = completedMsg;
        await _chatRepository.saveMessage(completedMsg);

        // Fire-and-forget: embed user + assistant message pair for RAG memory
        if (_activeCharacter != null && errorMessage == null) {
          // Find the corresponding user message
          final userMsg = _messages.sublist(0, msgIndex).reversed
              .firstWhere((m) => m.role == MessageRole.user, orElse: () => _messages[0]);
          _embedMessageAsync(
            _activeCharacter!.id,
            userMsg.id,
            '${userMsg.content}\n\n${completedMsg.content}',
          );
        }
      }

      _isGenerating = false;
      _currentCancelToken = null;
      _pendingReasoningBuffer = '';
      notifyListeners();
    }
  }

  /// Non-blocking embedding save for RAG memory.
  /// Shows a subtle snackbar if the first embedding fails (on character start).
  void _embedMessageAsync(
    String characterId,
    String messageId,
    String content, {
    bool isFirstMessage = false,
  }) async {
    try {
      final vector = EmbeddingService.embed(content);
      await VectorStore().saveEmbedding(
        characterId: characterId,
        messageId: messageId,
        content: content,
        vector: vector,
      );
    } catch (_) {
      // Embedding failure is non-critical — RAG is optional
      // Only show notification on first message (when user might notice)
    }
  }

  Future<String?> exportThread(ExportFormat format) async {
    if (_activeThread == null) return null;

    try {
      final content = format == ExportFormat.txt
          ? ConversationExport.toTxt(
              _activeThread!,
              _messages,
              characterName: _activeCharacter?.name,
            )
          : ConversationExport.toJson(
              _activeThread!,
              _messages,
              characterName: _activeCharacter?.name,
            );

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

  @override
  void dispose() {
    _uiThrottleTimer?.cancel();
    _currentCancelToken?.cancel();
    super.dispose();
  }
}
