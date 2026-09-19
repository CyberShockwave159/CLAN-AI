import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/file_saver.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/core/utils/roleplay_context_builder.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/shared/mixins/stream_mutation_mixin.dart';

class RoleplayViewModel extends ChangeNotifier with StreamMutationMixin {
  final ChatRepository _chatRepository;
  final CharacterRepository _characterRepository;

  CharacterProfile? _activeCharacter;
  // ignore: unnecessary_getters_setters
  CharacterProfile? get activeCharacter => _activeCharacter;
  set activeCharacter(CharacterProfile? v) => _activeCharacter = v;

  ChatThread? _activeThread;
  @override
  ChatThread? get activeThread => _activeThread;
  set activeThread(ChatThread? v) => _activeThread = v;

  List<ChatMessage> _messages = [];

  bool _isGenerating = false;

  @override
  bool get isGenerating => _isGenerating;
  @override
  set isGenerating(bool v) => _isGenerating = v;

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

  RoleplayViewModel(this._chatRepository, this._characterRepository) {
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
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    await _startRoleplayWithGreeting(character, character.firstMessage, serverConfig: serverConfig, connection: connection, customParams: customParams, modelContextLength: modelContextLength);
  }

  /// Start a new conversation with the character using an alternate greeting.
  Future<void> startRoleplayWithGreeting(CharacterProfile character, String greeting, {
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    await _startRoleplayWithGreeting(character, greeting, serverConfig: serverConfig, connection: connection, customParams: customParams, modelContextLength: modelContextLength);
  }

  /// Start a roleplay session with a specific greeting message.
  /// This is used for alternate greetings — always creates a new thread
  /// so each alternate opening starts a fresh branch conversation.
  Future<void> _startRoleplayWithGreeting(CharacterProfile character, String greeting, {
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating) {
      stopGeneration();
    }

    _activeCharacter = character;

    // Build initial system prompt with RAG (empty memories on first message)
    final initialContext = await RoleplayContextBuilder().build(
      characterId: character.id,
      characterName: character.name,
      personality: character.personality,
      setting: character.setting,
      userPersona: character.userPersona,
      personaName: character.personaName,
      characterSystemPrompt: character.systemPrompt,
      postHistoryInstructions: character.postHistoryInstructions,
      userInput: '',
      ragTopK: customParams?.ragTopK ?? 3,
      ragMinScore: customParams?.ragMinScore ?? 0.0,
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
    _embedMessageAsync(character.id, threadWithCharacter.id, firstAssistantId, greeting, isFirstMessage: true);

    notifyListeners();
  }

  /// Send a user message and stream the character's response.
  Future<void> sendMessage({
    required String prompt,
    String? imagePath,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
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
      imagePath: imagePath,
    );

    _messages.add(userMessage);
    await _chatRepository.saveMessage(userMessage);

    // Auto-update thread title if this is the first user message (similar to assistant mode)
    if (_messages.where((m) => m.role == MessageRole.user).length == 1) {
      final autoTitle = prompt.trim().length > autoTitleMaxLen
          ? '${prompt.trim().substring(0, autoTitleMaxLen)}...'
          : prompt.trim();
      final titleUpdatedThread = _activeThread!.copyWith(title: autoTitle);
      await _chatRepository.updateThread(titleUpdatedThread);
      _activeThread = titleUpdatedThread;
    }

    notifyListeners();

    // 2. Resolve thread lineage for RAG memory scoping
    final threadIds = await _chatRepository.getThreadLineageIds(threadId);

    // 3. Build RAG context (embed + search memories)
    final contextBuilder = RoleplayContextBuilder();
    final context = await contextBuilder.build(
      characterId: character.id,
      characterName: character.name,
      personality: character.personality,
      setting: character.setting,
      userPersona: character.userPersona,
      personaName: character.personaName,
      characterSystemPrompt: character.systemPrompt,
      postHistoryInstructions: character.postHistoryInstructions,
      userInput: prompt,
      ragTopK: customParams?.ragTopK ?? 3,
      ragMinScore: customParams?.ragMinScore ?? 0.0,
      threadIds: threadIds,
    );

    // 4. Update thread system prompt with retrieved memories
    final updatedThread = _activeThread!.copyWith(
      systemPrompt: context.systemPrompt,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedThread);

    // 4. Prepare Assistant Message Placeholder
    final assistantMessageId = const Uuid().v4();
    final ragMemoryCount = context.memories.isNotEmpty ? context.memories.length : null;
    final ragMemoryContents = context.memoryInfo.isNotEmpty
        ? jsonEncode(context.memoryInfo.map((m) => m['content'] as String).toList())
        : null;
    final assistantPlaceholder = ChatMessage(
      id: assistantMessageId,
      threadId: threadId,
      parentId: userMessage.id,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      ragMemoryCount: ragMemoryCount,
      ragMemoryContents: ragMemoryContents,
    );

    _messages.add(assistantPlaceholder);
    notifyListeners();

    // 5. Stream response
    await _streamResponse(
      assistantMessageId: assistantMessageId,
      serverConfig: serverConfig,
      connection: connection,
      customParams: customParams,
      modelContextLength: modelContextLength,
      ragMemoryCount: ragMemoryCount,
    );
  }

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

    final parentId = targetMsg.parentId;
    final newAssistantId = const Uuid().v4();
    final nextVariantIndex = targetMsg.totalVariants;
    final newTotalVariants = targetMsg.totalVariants + 1;

    final existingSiblings = await _chatRepository.getAllMessagesForThread(targetMsg.threadId);
    final variantSiblings = existingSiblings.where((m) => m.role == MessageRole.assistant && m.parentId == targetMsg.parentId);
    final allSiblingIds = {...variantSiblings.map((m) => m.id), targetMsg.id, newAssistantId};
    final completeSiblingList = allSiblingIds.toList()..sort();

    final updatedOldMsg = targetMsg.copyWith(
      variantIndex: targetMsg.variantIndex,
      totalVariants: newTotalVariants,
      siblingIds: completeSiblingList,
    );
    _messages[messageIndex] = updatedOldMsg;
    await _chatRepository.saveMessage(updatedOldMsg);

    for (final siblingMsg in existingSiblings) {
      if (siblingMsg.id != targetMsg.id) {
        await _chatRepository.saveMessage(siblingMsg.copyWith(
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

    _messages[messageIndex] = newAssistantMsg;
    notifyListeners();

    await _streamResponse(
      assistantMessageId: newAssistantId,
      serverConfig: serverConfig,
      connection: connection,
      customParams: customParams,
      modelContextLength: modelContextLength,
    );

    // Delete old assistant message's RAG embedding (replaced by regenerated response)
    if (_activeCharacter != null && _activeThread != null) {
      try {
        await _characterRepository.deleteEmbeddingsForMessages(
          characterId: _activeCharacter!.id,
          threadId: _activeThread!.id,
          messageIds: [targetMsg.id],
        );
      } catch (_) {}
    }
  }

  Future<void> editUserPrompt({
    required int messageIndex,
    required String newContent,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
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
      personaName: _activeCharacter!.personaName,
      characterSystemPrompt: _activeCharacter!.systemPrompt,
      postHistoryInstructions: _activeCharacter!.postHistoryInstructions,
      userInput: newContent,
      ragTopK: customParams?.ragTopK ?? 3,
      ragMinScore: customParams?.ragMinScore ?? 0.0,
    );

    final updatedThread = _activeThread!.copyWith(
      systemPrompt: context.systemPrompt,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedThread);

    final assistantMessageId = const Uuid().v4();
    final hasOldAssistant = oldAssistantId != null;
    final ragMemoryCount = context.memories.isNotEmpty ? context.memories.length : null;
    final ragMemoryContents = context.memoryInfo.isNotEmpty
        ? jsonEncode(context.memoryInfo.map((m) => m['content'] as String).toList())
        : null;

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
      ragMemoryContents: ragMemoryContents,
    );
    _messages.add(assistantPlaceholder);
    notifyListeners();

    await _streamResponse(
      assistantMessageId: assistantMessageId,
      serverConfig: serverConfig,
      connection: connection,
      customParams: customParams,
      modelContextLength: modelContextLength,
      ragMemoryCount: ragMemoryCount,
    );
  }

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

    String newTitle = '${_activeCharacter!.name} (Branch)';

    final newThread = await _chatRepository.createThread(
      title: newTitle,
      systemPrompt: _activeThread!.systemPrompt,
      modelId: _activeThread!.modelId,
      characterId: _activeCharacter!.id,
      branchFromThreadId: _activeThread!.id,
    );

    final branchThreadWithLink = newThread.copyWith(
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
        connection: connection,
        customParams: customParams,
        modelContextLength: modelContextLength,
        ragMemoryCount: branchRagCount,
      );
    }
  }

  /// Switches the message at the given index to a different variant.
  Future<void> switchVariant({
    required int messageIndex,
    required bool previous,
  }) => doSwitchVariant(messageIndex: messageIndex, previous: previous);

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

  Future<void> deleteCharacter(String characterId) async {
    final characterThreads = await _chatRepository.getThreadsForCharacter(characterId);
    for (final thread in characterThreads) {
      if (_activeThread?.id == thread.id) {
        _activeThread = null;
        _messages = [];
      }
      await _chatRepository.deleteThread(thread.id);
    }
    notifyListeners();
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
      _embedMessageAsync(_activeCharacter!.id, _activeThread!.id, updated.id, updated.content);
    }
  }

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

    final messagesToDelete = _messages.sublist(messageIndex);

    for (final msg in messagesToDelete) {
      await _chatRepository.deleteMessage(msg.id);
      await MessageAttachmentStore.instance.deleteIfExists(msg.imagePath);
    }

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
        personaName: _activeCharacter!.personaName,
        characterSystemPrompt: _activeCharacter!.systemPrompt,
        postHistoryInstructions: _activeCharacter!.postHistoryInstructions,
        userInput: lastUserMsg.content,
        ragTopK: customParams?.ragTopK ?? 3,
        ragMinScore: customParams?.ragMinScore ?? 0.0,
      );
      final ragMemoryCount = context.memories.isNotEmpty ? context.memories.length : null;
      final ragMemoryContents = context.memoryInfo.isNotEmpty
          ? jsonEncode(context.memoryInfo.map((m) => m['content'] as String).toList())
          : null;

      final newAssistantId = const Uuid().v4();
      final newAssistantMsg = ChatMessage(
        id: newAssistantId,
        threadId: _activeThread!.id,
        parentId: lastUserMsg.id,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
        ragMemoryCount: ragMemoryCount,
        ragMemoryContents: ragMemoryContents,
      );

      _messages.add(newAssistantMsg);
      notifyListeners();

      await _streamResponse(
        assistantMessageId: newAssistantId,
        serverConfig: serverConfig,
        connection: connection,
        customParams: customParams,
        modelContextLength: modelContextLength,
        ragMemoryCount: ragMemoryCount,
      );
      return false;
    }

    notifyListeners();
    return false;
  }

  Future<void> undoDelete() => doUndoDelete();

  /// Delegates to mixin but adds RAG embedding post-stream hook.
  Future<void> _streamResponse({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? modelContextLength,
    int? ragMemoryCount,
  }) async {
    Future<void> onEmbed(String _) async {
      if (_activeCharacter == null || _activeThread == null) return;
      final msgIndex = messages.indexWhere((m) => m.id == assistantMessageId);
      if (msgIndex <= 0) return;
      try {
        final currentMsg = messages[msgIndex];
        if (currentMsg.status == MessageStatus.completed) {
          final userMsg = messages.sublist(0, msgIndex).reversed
              .firstWhere((m) => m.role == MessageRole.user, orElse: () => messages[0]);
          _embedMessageAsync(
            _activeCharacter!.id,
            _activeThread!.id,
            userMsg.id,
            '${userMsg.content}\n\n${currentMsg.content}',
          );
        }
      } catch (_) {}
    }

    await doStreamResponse(
      assistantMessageId: assistantMessageId,
      serverConfig: serverConfig,
      connection: connection,
      customParams: customParams,
      modelContextLength: modelContextLength,
      onComplete: onEmbed,
    );
  }

  Future<void> deleteThread(String threadId) async {
    if (_activeCharacter != null) {
      final threadMessages = await _chatRepository.getMessagesForThread(threadId);
      final messageIds = threadMessages.map((m) => m.id).toList();
      await _characterRepository.deleteEmbeddingsForMessages(
        characterId: _activeCharacter!.id,
        threadId: threadId,
        messageIds: messageIds,
      );
      for (final msg in threadMessages) {
        await MessageAttachmentStore.instance.deleteIfExists(msg.imagePath);
      }
    }
    await _chatRepository.deleteThread(threadId);
    _activeThread = null;
    _activeCharacter = null;
    _messages = [];
    notifyListeners();
  }

  void stopGeneration() => doStopGeneration();

  /// Non-blocking embedding save for RAG memory.
  /// Shows a subtle snackbar if the first embedding fails (on character start).
  void _embedMessageAsync(
    String characterId,
    String threadId,
    String messageId,
    String content, {
    bool isFirstMessage = false,
  }) async {
    try {
      final vector = HashEmbedding.embed(content);
      await VectorStore().saveEmbedding(
        characterId: characterId,
        threadId: threadId,
        messageId: messageId,
        content: content,
        vector: vector,
      );
    } catch (_) {
      // Embedding failure is non-critical — RAG is optional
      // Only show notification on first message (when user might notice)
    }
  }

  Future<String?> exportCharacterWithRAG(CharacterProfile character) async {

    try {
      final memories = await VectorStore().getAllMemories(character.id);
      final exportData = {
        'character': {
          'name': character.name,
          'personality': character.personality,
          'first_message': character.firstMessage,
          'setting': character.setting,
          'user_persona': character.userPersona,
          'persona_name': character.personaName,
          'persona_description': character.personaDescription,
          'system_prompt': character.systemPrompt,
          'post_history_instructions': character.postHistoryInstructions,
          'alternate_greetings': character.alternateGreetings,
          'created_at': character.createdAt.toIso8601String(),
          'updated_at': character.updatedAt.toIso8601String(),
        },
        'rag_memories': memories.map((m) => {
          'id': m['id'],
          'message_id': m['message_id'],
          'content': m['content'],
          'created_at': m['created_at'],
        }).toList(),
        'export_info': {
          'version': '1.0',
          'exported_at': DateTime.now().toIso8601String(),
          'app': 'CLAN AI',
        },
      };

      final jsonContent = jsonEncode(exportData);
      final sanitizedName = character.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final filename = 'clan_ai_character_${sanitizedName}_with_rag.json';

      return await FileSaver.saveFile(
        filename: filename,
        content: jsonContent,
        mimeType: 'application/json',
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> exportThread(ExportFormat format, {ChatThread? thread, String? characterName}) async {
    final target = thread ?? _activeThread;
    if (target == null) return null;

    try {
      final messageList = target.id == _activeThread?.id
          ? _messages
          : await _chatRepository.getMessagesForThread(target.id);

      final resolvedCharacterName = characterName ?? _activeCharacter?.name;
      final content = format == ExportFormat.txt
          ? ConversationExport.toTxt(
              target,
              messageList,
              characterName: resolvedCharacterName,
            )
          : ConversationExport.toJson(
              target,
              messageList,
              characterName: resolvedCharacterName,
            );

      final sanitizedTitle = target.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
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

  /// Imports a thread from parsed JSON export data.
  /// Creates a new thread with the imported data, associates it with the given character,
  /// saves it to the database, and sets it as the active thread.
  Future<void> importThread(ChatThread thread, List<ChatMessage> messages, String characterId) async {
    if (_isGenerating) {
      stopGeneration();
    }

    // Generate new IDs to avoid conflicts
    final newThread = thread.copyWith(
      id: const Uuid().v4(),
      characterId: characterId,
      updatedAt: DateTime.now(),
    );

    // Save thread to database
    await _chatRepository.createThread(
      title: newThread.title,
      systemPrompt: newThread.systemPrompt,
      modelId: newThread.modelId,
      customParams: newThread.customParams,
      characterId: characterId,
    );

    // Get the saved thread (will have new ID from DB)
    final savedThread = await _chatRepository.getThreadsForCharacter(characterId).then((threads) => threads.firstWhere(
          (t) => t.id == newThread.id,
          orElse: () => newThread,
        ));

    // Save all messages with new thread ID
    for (final msg in messages) {
      final newMsg = msg.copyWith(
        id: const Uuid().v4(),
        threadId: savedThread.id,
      );
      _messages.add(newMsg);
      await _chatRepository.saveMessage(newMsg);
    }

    // Select the thread as active
    await selectThread(savedThread);
    notifyListeners();
  }

  @override
  void dispose() {
    uiThrottleTimer?.cancel();
    currentCancelToken?.cancel();
    super.dispose();
  }
}
