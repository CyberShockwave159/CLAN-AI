import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/core/network/http_client.dart';
import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/file_saver.dart';
import 'package:clan_ai/core/utils/identity_reference.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/core/utils/roleplay_context_builder.dart';
import 'package:clan_ai/core/utils/hash_embedding.dart';
import 'package:clan_ai/data/datasources/aprox_rag_client.dart';
import 'package:clan_ai/data/datasources/request_options.dart';
import 'package:clan_ai/data/datasources/vector_store.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/character_repository.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/core/constants/app_constants.dart';
import 'package:clan_ai/core/constants/aprox_capabilities.dart';
import 'package:clan_ai/domain/models/generation_params.dart';
import 'package:clan_ai/ui/features/roleplay/services/scene_image_generator.dart';
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

  /// Client for A-PROX's RAG store. Lazily constructed so tests that never
  /// touch server-side memory don't need a live HTTP client.
  AproxRagClient? _ragClient;

  /// Threads already backfilled into the server store this session. Without
  /// this, every `selectThread` would re-check the collection count.
  final Set<String> _backfilledThreadIds = {};

  RoleplayViewModel(this._chatRepository, this._characterRepository) {
    _init();
  }

  /// The A-PROX RAG client, created on first use.
  ///
  /// Injected in tests via [ragClientOverride] so the memory path stays
  /// hermetic.
  AproxRagClient get ragClient =>
      _ragClient ??= AproxRagClient(ApiHttpClient());

  /// Test seam: replaces the lazily-created RAG client.
  set ragClientOverride(AproxRagClient client) => _ragClient = client;

  // --- Memory backend selection -------------------------------------------

  /// Whether roleplay memory is handled by the A-PROX server rather than the
  /// client-side vector store.
  ///
  /// Requires *both* the user setting and a server that actually advertises the
  /// capability. Against a plain llama.cpp or OpenAI backend the setting is
  /// inert, so roleplay silently keeps its local RAG instead of sending an
  /// `a-prox-rag` model alias the backend would reject.
  bool isServerRagActive({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
  }) {
    return serverConfig.serverSideRagEnabled &&
        AproxRagClient.isAvailable(connection);
  }

  /// A-PROX collection holding this thread's conversation memories.
  String? _serverRagCollection(ServerProfile? connection) {
    final character = _activeCharacter;
    final thread = _activeThread;
    if (character == null || thread == null) return null;
    if (!AproxRagClient.isAvailable(connection)) return null;
    return AproxRagClient.threadCollection(
      characterId: character.id,
      threadId: thread.id,
    );
  }

  /// Builds the request options for a roleplay turn.
  ///
  /// Returns [RequestOptions.none] when the client RAG backend is in use, so
  /// non-A-PROX requests are byte-for-byte unchanged.
  RequestOptions _requestOptions({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required GenerationParams? customParams,
  }) {
    if (!isServerRagActive(serverConfig: serverConfig, connection: connection)) {
      return RequestOptions.none;
    }
    final collection = _serverRagCollection(connection);
    if (collection == null) return RequestOptions.none;
    final params = customParams ?? serverConfig.defaultParams;
    return RequestOptions.serverSideRag(
      collection: collection,
      topK: params.ragTopK,
      minScore: params.ragMinScore,
    );
  }

  /// Builds the RAG context for a turn, honouring the active memory backend.
  ///
  /// One place for the backend decision, so [sendMessage], [editUserPrompt] and
  /// [deleteMessage] can't drift apart. [userInput] is the query for the local
  /// vector search; [threadIds] scopes that search to the thread lineage (an
  /// empty list searches every thread the character has, which is only
  /// appropriate when there is no lineage to scope to).
  Future<RoleplayContext> _buildRagContext({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required String userInput,
    required GenerationParams? customParams,
    List<String> threadIds = const [],
  }) async {
    final character = _activeCharacter;
    if (character == null) {
      return RoleplayContext.withoutMemories(
        characterName: 'Character',
        personality: '',
      );
    }
    if (isServerRagActive(serverConfig: serverConfig, connection: connection)) {
      return RoleplayContext.withoutMemories(
        characterName: character.name,
        personality: character.personality,
        setting: character.setting,
        userPersona: character.userPersona,
        personaName: character.personaName,
        characterSystemPrompt: character.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions,
      );
    }
    return RoleplayContextBuilder().build(
      characterId: character.id,
      characterName: character.name,
      personality: character.personality,
      setting: character.setting,
      userPersona: character.userPersona,
      personaName: character.personaName,
      characterSystemPrompt: character.systemPrompt,
      postHistoryInstructions: character.postHistoryInstructions,
      userInput: userInput,
      ragTopK: customParams?.ragTopK ?? 3,
      ragMinScore: customParams?.ragMinScore ?? 0.0,
      threadIds: threadIds,
    );
  }

  /// Persists [context]'s system prompt onto the active thread and returns the
  /// RAG provenance to stamp on the assistant placeholder (nulls on the server
  /// backend, which injects its own context at request time).
  (String systemPrompt, int? memoryCount, String? memoryContents) _applyRagContext(
    RoleplayContext context,
  ) {
    final memoryContents = context.memoryInfo.isNotEmpty
        ? jsonEncode(context.memoryInfo.map((m) => m['content'] as String).toList())
        : null;
    return (
      context.systemPrompt,
      context.memories.isNotEmpty ? context.memories.length : null,
      memoryContents,
    );
  }

  /// Sends one conversation turn into the A-PROX RAG store so it can be recalled
  /// on a later turn.
  ///
  /// Fire-and-forget by design: A-PROX embeds on the CPU, and the reply has
  /// already been delivered by the time this runs. Failures are swallowed by
  /// [AproxRagClient] — a memory write must never surface as an error.
  Future<void> _ingestTurnToServer({
    required ServerProfile? connection,
    required String userText,
    required String assistantText,
    required String assistantMessageId,
  }) async {
    final collection = _serverRagCollection(connection);
    if (collection == null) return;
    final character = _activeCharacter;
    final thread = _activeThread;
    if (character == null || thread == null) return;
    if (userText.trim().isEmpty || assistantText.trim().isEmpty) return;

    await ragClient.ingest(
      connection: connection,
      collection: collection,
      sourceUri: AproxRagClient.turnSourceUri(
        characterId: character.id,
        threadId: thread.id,
        messageId: assistantMessageId,
      ),
      content: _formatTurnDocument(
        characterName: character.name,
        threadTitle: thread.title,
        userText: userText,
        assistantText: assistantText,
      ),
    );
  }

  /// Renders one turn as a self-contained document.
  ///
  /// The character and thread headers matter: A-PROX embeds the whole chunk and
  /// retrieves by similarity, so "who said this" and "where" have to be in the
  /// text, not just implied by the collection name.
  static String _formatTurnDocument({
    required String characterName,
    required String threadTitle,
    required String userText,
    required String assistantText,
  }) {
    return '[Character: $characterName | Thread: $threadTitle]\n'
        'User: $userText\n'
        '$characterName: $assistantText';
  }

  /// Pushes a thread's existing history into the server store, once.
  ///
  /// Needed because switching an established roleplay to server-side memory
  /// leaves A-PROX with an empty collection — without this the character would
  /// appear to forget everything until new turns accumulated. Batched to keep
  /// each request's document a sensible size.
  Future<void> _backfillThreadToServer({required ServerProfile? connection}) async {
    final collection = _serverRagCollection(connection);
    final character = _activeCharacter;
    final thread = _activeThread;
    if (collection == null || character == null || thread == null) return;
    if (_backfilledThreadIds.contains(collection)) return;
    // Mark before the awaits so concurrent sends can't both start a backfill.
    _backfilledThreadIds.add(collection);

    try {
      final existing = await ragClient.collectionCount(
        connection: connection,
        collection: collection,
      );
      if (existing > 0) return; // Already has memories; nothing to migrate.

      final history = await _chatRepository.getAllMessagesForThread(thread.id);
      final turns = <({String user, String assistant, String id})>[];
      for (var i = 0; i < history.length; i++) {
        if (history[i].role != MessageRole.user) continue;
        // The assistant reply may be missing mid-generation or after a delete.
        final reply = history.skip(i + 1).firstWhere(
          (m) => m.role == MessageRole.assistant,
          orElse: () => history[i],
        );
        if (reply.id == history[i].id) continue;
        if (reply.content.trim().isEmpty) continue;
        turns.add((user: history[i].content, assistant: reply.content, id: reply.id));
      }
      if (turns.isEmpty) return;

      const batchSize = 5;
      for (var start = 0; start < turns.length; start += batchSize) {
        final batch = turns.skip(start).take(batchSize).toList();
        final document = batch
            .map((t) => '[Character: ${character.name} | Thread: ${thread.title}]\n'
                'User: ${t.user}\n${character.name}: ${t.assistant}')
            .join('\n\n');
        await ragClient.ingest(
          connection: connection,
          collection: collection,
          sourceUri: AproxRagClient.turnSourceUri(
            characterId: character.id,
            threadId: thread.id,
            messageId: 'backfill-$start',
          ),
          content: document,
        );
      }
    } catch (_) {
      // Best-effort: a failed backfill just means the thread starts with less
      // server-side history. The turn-level ingestion path still works.
    }
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
  /// Reuses the most recently updated existing thread for this character if
  /// one exists, otherwise creates a new one.
  Future<void> startRoleplay(CharacterProfile character, {
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? modelContextLength,
  }) async {
    if (_isGenerating) {
      stopGeneration();
    }

    _activeCharacter = character;

    // Reuse the most recently updated thread for this character if one exists
    final characterThreads = await _chatRepository.getThreadsForCharacter(character.id);
    if (characterThreads.isNotEmpty) {
      _activeThread = characterThreads.first;
      _messages = await _chatRepository.getMessagesForThread(_activeThread!.id);
      notifyListeners();
      return;
    }

    await _startRoleplayWithGreeting(
      character,
      character.firstMessage,
      serverConfig: serverConfig,
      connection: connection,
      customParams: customParams,
      modelContextLength: modelContextLength,
    );
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

    // Build the initial system prompt. The greeting is a fixed line from the
    // character card with nothing to retrieve, so the RAG search is skipped
    // entirely — on either backend.
    final useServerRag = isServerRagActive(
      serverConfig: serverConfig,
      connection: connection,
    );
    final initialContext = await _buildRagContext(
      serverConfig: serverConfig,
      connection: connection,
      userInput: '',
      customParams: customParams,
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

    // Remember the opening line. On the server backend this seeds the thread's
    // collection so the greeting is part of what later turns can retrieve.
    if (useServerRag) {
      unawaited(_ingestTurnToServer(
        connection: connection,
        userText: '(opening line)',
        assistantText: greeting,
        assistantMessageId: firstAssistantId,
      ));
    } else {
      _embedMessageAsync(character.id, threadWithCharacter.id, firstAssistantId, greeting);
    }

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

    final useServerRag = isServerRagActive(
      serverConfig: serverConfig,
      connection: connection,
    );

    // One-time backfill: a thread that predates the switch has no server-side
    // memories, so push its existing history once before the first retrieval.
    if (useServerRag) {
      unawaited(_backfillThreadToServer(connection: connection));
    }

    // 2. Resolve thread lineage for RAG memory scoping
    final threadIds = await _chatRepository.getThreadLineageIds(threadId);

    // 3. Build RAG context (local search, or nothing when A-PROX retrieves).
    final context = await _buildRagContext(
      serverConfig: serverConfig,
      connection: connection,
      userInput: prompt,
      customParams: customParams,
      threadIds: threadIds,
    );

    // 4. Update thread system prompt with retrieved memories
    final (systemPrompt, ragMemoryCount, ragMemoryContents) = _applyRagContext(context);
    final updatedThread = _activeThread!.copyWith(
      systemPrompt: systemPrompt,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedThread);

    // 4. Prepare Assistant Message Placeholder
    final assistantMessageId = const Uuid().v4();
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
      userTurnText: prompt,
    );
  }

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
      modelContextLength: modelContextLength,
    );

    // Delete old assistant message's RAG embedding (replaced by regenerated
    // response). Only meaningful for the local backend — the A-PROX store is
    // append-only per turn, and the old turn's document stays addressable by
    // its own source_uri.
    if (!isServerRagActive(serverConfig: serverConfig, connection: connection) &&
        _activeCharacter != null &&
        _activeThread != null) {
      try {
        await _characterRepository.deleteEmbeddingsForMessages(
          characterId: _activeCharacter!.id,
          threadId: _activeThread!.id,
          messageIds: [result.oldMessageId],
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
    if (_activeCharacter == null) return;

    final result = await doEditUserPrompt(messageIndex: messageIndex, newContent: newContent);
    if (result == null) return;

    // Rebuild RAG context for the new prompt
    final context = await _buildRagContext(
      serverConfig: serverConfig,
      connection: connection,
      userInput: newContent,
      customParams: customParams,
      threadIds: await _chatRepository.getThreadLineageIds(_activeThread!.id),
    );

    final (systemPrompt, ragMemoryCount, ragMemoryContents) = _applyRagContext(context);
    final updatedThread = _activeThread!.copyWith(
      systemPrompt: systemPrompt,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.updateThread(updatedThread);

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
      userTurnText: newContent,
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
    required ServerConfig serverConfig,
    required ServerProfile? connection,
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

    // Re-embed edited content into RAG (replaces old embedding). Only for the
    // local backend; the A-PROX store keeps the original turn document, which
    // is the correct behaviour — the user corrected their *screen copy*, not
    // what the character said.
    if (_activeCharacter != null &&
        !isServerRagActive(serverConfig: serverConfig, connection: connection)) {
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
    final result = await doDeleteMessageHead(messageIndex: messageIndex);
    if (result == null) return false;

    if (result.threadToDelete != null) {
      await deleteThread(result.threadToDelete!);
      return true;
    }

    if (!result.isUserMessage && _messages.isNotEmpty) {
      final lastUserMsg = _messages.reversed.firstWhere(
        (m) => m.role == MessageRole.user,
        orElse: () => _messages.last,
      );

      // Rebuild RAG context for regeneration
      final context = await _buildRagContext(
        serverConfig: serverConfig,
        connection: connection,
        userInput: lastUserMsg.content,
        customParams: customParams,
        threadIds: await _chatRepository.getThreadLineageIds(_activeThread!.id),
      );
      final (systemPrompt, ragMemoryCount, ragMemoryContents) = _applyRagContext(context);
      final updatedThread = _activeThread!.copyWith(
        systemPrompt: systemPrompt,
        updatedAt: DateTime.now(),
      );
      await _chatRepository.updateThread(updatedThread);

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

  /// Delegates to mixin but adds the memory write that follows a completed turn.
  ///
  /// Exactly one memory backend runs per turn — they are mutually exclusive, so
  /// this hook either writes a local embedding or pushes the turn to the A-PROX
  /// store, never both.
  ///
  /// [userTurnText] is the prompt that produced this reply. Pass null when the
  /// turn isn't a normal conversation exchange (regenerate, delete-and-redo,
  /// branch continuation) — those still write memory, but the user side is
  /// recovered from the message list.
  Future<void> _streamResponse({
    required String assistantMessageId,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    int? modelContextLength,
    int? ragMemoryCount,
    String? userTurnText,
    RequestOptions? optionsOverride,
  }) async {
    final useServerRag = isServerRagActive(
      serverConfig: serverConfig,
      connection: connection,
    );

    Future<void> onComplete(String _) async {
      if (_activeCharacter == null || _activeThread == null) return;
      final msgIndex = messages.indexWhere((m) => m.id == assistantMessageId);
      if (msgIndex < 0) return;
      try {
        final currentMsg = messages[msgIndex];
        if (currentMsg.status != MessageStatus.completed) return;
        if (currentMsg.content.trim().isEmpty) return;

        // The user turn this reply answers. Falls back to the nearest preceding
        // user message for regenerate/delete/branch paths.
        final resolvedUserText = userTurnText ??
            messages.sublist(0, msgIndex).reversed
                .firstWhere((m) => m.role == MessageRole.user, orElse: () => messages[0])
                .content;

        if (useServerRag) {
          // Fire-and-forget: the reply is already delivered; A-PROX embeds on
          // the CPU and this must not delay the UI.
          unawaited(_ingestTurnToServer(
            connection: connection,
            userText: resolvedUserText,
            assistantText: currentMsg.content,
            assistantMessageId: assistantMessageId,
          ));
        } else {
          _embedMessageAsync(
            _activeCharacter!.id,
            _activeThread!.id,
            messages.sublist(0, msgIndex).reversed
                .firstWhere((m) => m.role == MessageRole.user, orElse: () => messages[0])
                .id,
            '$resolvedUserText\n\n${currentMsg.content}',
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
      onComplete: onComplete,
      options: optionsOverride ??
          _requestOptions(
            serverConfig: serverConfig,
            connection: connection,
            customParams: customParams,
          ),
    );
  }

  Future<void> deleteThread(String threadId) async {
    if (_activeCharacter != null) {
      final threadMessages = await _chatRepository.getMessagesForThread(threadId);
      // Local embeddings only. The A-PROX store has no per-message delete
      // endpoint, and deleting a thread's memories isn't required for
      // correctness — the collection is keyed by thread id and simply stops
      // being retrieved.
      await _characterRepository.deleteEmbeddingsForMessages(
        characterId: _activeCharacter!.id,
        threadId: threadId,
        messageIds: threadMessages.map((m) => m.id).toList(),
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

  /// Fire-and-forget local embedding write.
  ///
  /// Only called on the client RAG backend — the A-PROX path goes through
  /// [_ingestTurnToServer]. Failures are swallowed: RAG is an enhancement and
  /// must never surface as an error or interrupt a reply.
  void _embedMessageAsync(
    String characterId,
    String threadId,
    String messageId,
    String content,
  ) async {
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

      return await ConversationExport.saveToFile(target, content, format);
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

  // --- Scene image generation ----------------------------------------------

  /// System prompt for the `/image` request itself.
  ///
  /// A-PROX appends its own image-generator prompt when the flag forces the
  /// pipeline, so this only needs to stop the roleplay character sheet from
  /// fighting the picture — the model must not object to being drawn.
  static const String _imageRequestSystemPrompt =
      'You are assisting with an image generation request. Produce the image '
      'prompt as instructed and do not roleplay.';

  /// Generates a reference portrait for [character], stores it as the character's
  /// identity reference, and returns the attachment-store path of the image.
  ///
  /// A bust shot, not a scene: reference conditioning preserves facial identity
  /// far better from a tight portrait than from a wide composition. Runs as a
  /// one-shot request (no variant, nothing persisted as a message) and writes
  /// straight to `characters.identity_portrait_data`.
  ///
  /// Returns null when the server can't generate images or the request produced
  /// nothing — the caller offers to continue without a reference.
  Future<String?> generateIdentityPortrait({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    CharacterProfile? character,
  }) async {
    final target = character ?? _activeCharacter;
    if (target == null) return null;
    if (!(connection?.supportsImageGeneration ?? false)) return null;

    final path = await _runOneShotImage(
      serverConfig: serverConfig,
      connection: connection,
      prompt: PortraitPrompt.build(
        characterName: target.name,
        theme: target.visualTheme,
        appearance: target.appearance,
      ),
      theme: target.visualTheme,
    );
    if (path == null) return null;

    // Persist the approved portrait. `copyWith` treats a null argument as
    // "unchanged", so this only ever adds a reference, never clears one.
    final bytes = await MessageAttachmentStore.instance.readBytes(path);
    if (bytes != null) {
      final updated = target.copyWith(identityPortraitData: bytes);
      await _characterRepository.updateCharacter(updated);
      updateActiveCharacter(updated);
    }
    return path;
  }

  /// Runs a single `/image` request outside the conversation and returns the
  /// attachment-store path of the image it produced.
  ///
  /// Implemented as a throwaway one-message stream rather than a saved message,
  /// so a portrait never becomes part of the roleplay transcript. The scratch
  /// message is never written to the database (it has no thread row, and
  /// messages→threads is a live foreign key).
  Future<String?> _runOneShotImage({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required String prompt,
    required VisualTheme theme,
  }) async {
    final scratchThreadId = const Uuid().v4();
    final scratch = ChatMessage(
      id: const Uuid().v4(),
      threadId: scratchThreadId,
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
    );
    // The synthetic `/image` turn is the only history entry, so the enhancer
    // sees the instruction and nothing else.
    final history = [
      ChatMessage(
        threadId: scratchThreadId,
        role: MessageRole.user,
        content: '/image $prompt',
        status: MessageStatus.completed,
      ),
    ];

    String? imagePath;
    await doStreamResponse(
      assistantMessageId: scratch.id,
      serverConfig: serverConfig,
      connection: connection,
      options: RequestOptions.sceneImage(style: theme.wireValue),
      textMode: StreamTextMode.discard,
      historyOverride: history,
      systemPromptOverride: _imageRequestSystemPrompt,
      persistOnComplete: false,
      onArtifactResolved: (path) => imagePath = path,
    );
    return imagePath;
  }

  /// Generates an image of the scene described by the assistant message at
  /// [messageIndex], as a new sibling variant of that message.
  ///
  /// The variant keeps the original dialogue verbatim and gains the picture, so
  /// the existing variant arrows flip between "text only" and "text + picture"
  /// exactly as they do for regenerations. A-PROX's caption is discarded: it
  /// describes the picture request, not the roleplay reply.
  ///
  /// [refineFrom] overrides the character's own identity reference with an image
  /// the user picked from a previous generation.
  Future<SceneImageResult> generateImageForMessage({
    required int messageIndex,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    IdentityReference? refineFrom,
  }) async {
    if (!(connection?.supportsImageGeneration ?? false)) {
      return const SceneImageResult(SceneImageOutcome.unsupported);
    }
    if (_isGenerating) {
      return const SceneImageResult(SceneImageOutcome.busy);
    }
    // Step 1 runs before any streaming starts, so `isGenerating` is still false
    // during it — without this guard a double tap would run two prompt drafts
    // and create two variants.
    if (_imageGenerationInFlight) {
      return const SceneImageResult(SceneImageOutcome.busy);
    }
    _imageGenerationInFlight = true;
    try {
      return await _runImageGeneration(
        messageIndex: messageIndex,
        serverConfig: serverConfig,
        connection: connection,
        customParams: customParams,
        refineFrom: refineFrom,
      );
    } finally {
      _imageGenerationInFlight = false;
    }
  }

  /// Whether a scene-image generation is in progress, including its step-1
  /// prompt draft (which does not set `isGenerating`).
  bool _imageGenerationInFlight = false;

  Future<SceneImageResult> _runImageGeneration({
    required int messageIndex,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
    IdentityReference? refineFrom,
  }) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) {
      return const SceneImageResult(
        SceneImageOutcome.failed,
        message: 'Message not found.',
      );
    }
    final character = _activeCharacter;
    final target = _messages[messageIndex];
    if (character == null || target.role != MessageRole.assistant) {
      return const SceneImageResult(
        SceneImageOutcome.failed,
        message: 'Not a character reply.',
      );
    }

    // 1. Resolve the identity reference.
    final reference =
        refineFrom ?? IdentityReferenceResolver.forCharacter(character);

    // 2. Step 1 — draft a scene prompt from the last few exchanges.
    final appearance = await _retrieveAppearanceSheet(
      connection: connection,
      character: character,
      query: target.content,
    );
    final draft = await _draftScenePrompt(
      targetIndex: messageIndex,
      appearance: appearance,
      theme: character.visualTheme,
      serverConfig: serverConfig,
      connection: connection,
      customParams: customParams,
    );
    // A failure here means nothing was spent on a picture, so it is reported
    // with the specific cause. "Try again" on its own left no way to tell a
    // transport failure from an empty model response.
    if (draft == null) {
      return const SceneImageResult(
        SceneImageOutcome.failed,
        message: 'Image prompt request failed — the server did not answer.',
      );
    }
    if (draft.isEmpty) {
      return const SceneImageResult(
        SceneImageOutcome.failed,
        message: 'The model returned an empty image prompt.',
      );
    }

    // 3. Create the variant that will carry the image, then stream into it.
    final variant = await doCreateImageVariant(messageIndex: messageIndex);
    if (variant == null) {
      return const SceneImageResult(SceneImageOutcome.busy);
    }

    final history = SceneImagePrompts.buildSceneHistory(
      messages: _messages.sublist(0, messageIndex + 1),
      targetIndex: messageIndex,
      imagePrompt: SceneImagePrompts.imageCommand(
        characterName: character.name,
        draftedPrompt: draft,
        theme: character.visualTheme,
        appearance: appearance,
      ),
    );

    // No roleplay marker: `/image` already forces a loop with only
    // `image_generate` armed, and arming `rag_search` too would let the enhancer
    // pull unrelated memories into a picture.
    await doStreamResponse(
      assistantMessageId: variant.newAssistantId,
      serverConfig: serverConfig,
      connection: connection,
      customParams: customParams,
      options: RequestOptions.sceneImage(
        style: character.visualTheme.wireValue,
        referenceImage: reference?.bytes,
      ),
      textMode: StreamTextMode.discard,
      historyOverride: history,
      systemPromptOverride: _imageRequestSystemPrompt,
    );

    // 4. Validate. An image-less placeholder would strand a useless variant, so
    //    put the original back.
    final finalIndex =
        _messages.indexWhere((m) => m.id == variant.newAssistantId);
    final produced =
        finalIndex >= 0 && (_messages[finalIndex].imagePath?.isNotEmpty ?? false);
    if (!produced) {
      final errored = _messages
          .any((m) => m.id == variant.newAssistantId &&
              m.status == MessageStatus.error);
      await doRevertVariant(
        messageIndex: messageIndex,
        newAssistantId: variant.newAssistantId,
        oldMessageId: variant.oldMessageId,
      );
      return SceneImageResult(
        SceneImageOutcome.noImage,
        message: errored
            ? 'Image generation failed. Check the server logs.'
            : 'The server returned no image.',
      );
    }

    notifyListeners();
    return const SceneImageResult(SceneImageOutcome.generated);
  }

  /// Retrieves a character's appearance sheet from the A-PROX RAG store.
  ///
  /// Best-effort: returns the locally stored sheet when the server isn't A-PROX
  /// or the call fails. The scene is still generable without it — the sheet only
  /// sharpens consistency.
  Future<String?> _retrieveAppearanceSheet({
    required ServerProfile? connection,
    required CharacterProfile character,
    required String query,
  }) async {
    if (!character.hasAppearance) return null;
    if (!AproxRagClient.isAvailable(connection)) return character.appearance;
    final hits = await ragClient.query(
      connection: connection,
      query: '$query\n${character.appearance}',
      collection: AproxRagClient.visualCollection(character.id),
      topK: 2,
    );
    if (hits == null || hits.isEmpty) return character.appearance;
    final retrieved =
        hits.map((h) => h.content.trim()).where((c) => c.isNotEmpty).join('\n');
    return retrieved.isEmpty ? character.appearance : retrieved;
  }

  /// Step 1 of the scene-image flow: drafts the image prompt.
  ///
  /// Returns null when the auxiliary call fails. Uses the `/bypass` instruction
  /// (see [SceneImagePrompts]) so a draft mentioning "draw" can't accidentally
  /// trigger a second, wasted image generation.
  Future<String?> _draftScenePrompt({
    required int targetIndex,
    required String? appearance,
    required VisualTheme theme,
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    GenerationParams? customParams,
  }) async {
    final target = _messages[targetIndex];
    final start = targetIndex - SceneImagePrompts.sceneContextMessageCount + 1;
    final from = start < 0 ? 0 : start;
    final context = _messages
        .sublist(from, targetIndex + 1)
        .where((m) =>
            (m.role == MessageRole.user || m.role == MessageRole.assistant) &&
            m.status == MessageStatus.completed &&
            m.content.trim().isNotEmpty)
        .map((m) => <String, dynamic>{
              'role': m.role.value,
              'content': m.content,
            })
        .toList();

    if (context.isEmpty) {
      final trimmed = target.content.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final instruction = StringBuffer(SceneImagePrompts.promptWriterInstruction);
    if (appearance != null && appearance.trim().isNotEmpty) {
      instruction.write('\n\nCanonical appearance (preserve exactly):\n'
          '${appearance.trim()}');
    }
    if (theme.isSet) {
      instruction.write('\n\nVisual style: ${theme.label}.');
    }

    try {
      final draft = await _chatRepository.completeOnce(
        serverConfig: serverConfig,
        connection: connection,
        systemPrompt: SceneImagePrompts.promptWriterSystemPrompt,
        messages: [
          ...context,
          {'role': 'user', 'content': instruction.toString()},
        ],
        params: customParams,
        // Reasoning ON, unlike every other auxiliary call. With it off, a
        // reasoning model has no scratchpad and narrates a "Here's a thinking
        // process: …" preamble into `content`, which then has to share the token
        // budget with the prompt itself and gets truncated mid-sentence — a poor
        // instruction to hand a prompt rewriter. Letting it reason keeps the
        // preamble in `reasoning_content` and leaves `content` holding just the
        // prompt.
        reasoning: true,
        maxTokens: SceneImagePrompts.draftMaxTokens,
        // Reasoning at 35B takes well past the shared 60s receive budget; a
        // request the server already answered was being aborted client-side and
        // reported as an empty result.
        timeout: SceneImagePrompts.draftTimeout,
      );
      return draft.trim();
    } catch (_) {
      return null;
    }
  }
}
