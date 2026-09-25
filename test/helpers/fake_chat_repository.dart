import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/pending_request.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class FakeChatRepository implements ChatRepository {
  final List<ChatThread> _threads = [];
  List<ChatThread> get allThreads => _threads;
  final Map<String, List<ChatMessage>> _threadMessages = {};
  final Map<String, List<StreamChunk>> _streamFragments = {};
  final Map<String, String> _messageThreadMap = {};
  ChatMessage? _lastSavedMessage;
  ChatMessage? _lastUpdatedMessage;
  bool _shouldThrowStreamError = false;

  ChatMessage? get lastSavedMessage => _lastSavedMessage;
  ChatMessage? get lastUpdatedMessage => _lastUpdatedMessage;

  void setStreamFragments(String threadId, List<StreamChunk> fragments) {
    _streamFragments[threadId] = fragments;
  }

  void shouldThrowStreamError(bool value) {
    _shouldThrowStreamError = value;
  }

  @override
  Future<List<ChatThread>> getThreads() async => _threads.toList();

  @override
  Future<List<ChatThread>> getAssistantThreads() async =>
      _threads.where((t) => t.characterId == null).toList();

  @override
  Future<List<ChatThread>> getThreadsForCharacter(String characterId) async =>
      _threads.where((t) => t.characterId == characterId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<List<String>> getThreadLineageIds(String threadId) async {
    final lineageIds = <String>[threadId];
    var currentId = threadId;
    var depth = 0;
    const maxDepth = 20;
    while (depth < maxDepth) {
      final matches = _threads.where((t) => t.id == currentId);
      if (matches.isEmpty) break;
      final branchFrom = matches.first.branchFromThreadId;
      if (branchFrom == null) break;
      lineageIds.add(branchFrom);
      currentId = branchFrom;
      depth++;
    }
    return lineageIds;
  }

  @override
  Future<ChatThread> createThread({
    String title = 'New Chat',
    String? systemPrompt,
    String? modelId,
    GenerationParams? customParams,
    String? characterId,
    String? branchFromThreadId,
  }) async {
    final thread = ChatThread(
      title: title,
      systemPrompt: systemPrompt,
      modelId: modelId,
      customParams: customParams,
      characterId: characterId,
      branchFromThreadId: branchFromThreadId,
    );
    _threads.insert(0, thread);
    _threadMessages[thread.id] = [];
    return thread;
  }

  @override
  Future<void> updateThread(ChatThread thread) async {
    final index = _threads.indexWhere((t) => t.id == thread.id);
    if (index != -1) {
      _threads[index] = thread;
    }
  }

  @override
  Future<void> deleteThread(String threadId) async {
    _threads.removeWhere((t) => t.id == threadId);
    _threadMessages.remove(threadId);
    _messageThreadMap.removeWhere((msgId, tid) => tid == threadId);
  }

  @override
  Future<List<ChatMessage>> getAllMessagesForThread(String threadId) async {
    return (_threadMessages[threadId] ?? []).toList();
  }

  @override
  Future<List<ChatMessage>> getMessagesForThread(String threadId) async {
    return (_threadMessages[threadId] ?? []).toList();
  }

  @override
  Future<List<ChatThread>> searchThreads(String query, {String? characterId}) async {
    final q = query.toLowerCase();
    final results = <ChatThread>[];
    for (final thread in _threads) {
      if (characterId != null) {
        if (thread.characterId != characterId) continue;
      } else if (thread.characterId != null) {
        continue; // Assistant-mode search: exclude roleplay threads.
      }
      if (thread.title.toLowerCase().contains(q)) {
        results.add(thread);
        continue;
      }
      final messages = _threadMessages[thread.id] ?? const <ChatMessage>[];
      if (messages.any((m) => m.content.toLowerCase().contains(q))) {
        results.add(thread);
      }
    }
    return results;
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    _lastSavedMessage = message;
    _threadMessages.putIfAbsent(message.threadId, () => []);
    _messageThreadMap[message.id] = message.threadId;
    final existingIndex = _threadMessages[message.threadId]
        ?.indexWhere((m) => m.id == message.id);
    if (existingIndex != null && existingIndex >= 0) {
      _threadMessages[message.threadId]![existingIndex] = message;
    } else {
      _threadMessages[message.threadId]?.add(message);
    }
  }

  @override
  Future<void> updateMessage(ChatMessage message) async {
    _lastUpdatedMessage = message;
    _threadMessages.putIfAbsent(message.threadId, () => []);
    final index = _threadMessages[message.threadId]
        ?.indexWhere((m) => m.id == message.id);
    if (index != null && index >= 0) {
      _threadMessages[message.threadId]![index] = message;
    }
  }

  @override
  Future<void> deleteMessage(String id) async {
    final threadId = _messageThreadMap[id];
    if (threadId != null) {
      final list = _threadMessages[threadId];
      if (list != null) {
        list.removeWhere((m) => m.id == id);
      }
      _messageThreadMap.remove(id);
    }
  }

  @override
  Stream<StreamChunk> streamCompletion({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required List<ChatMessage> history,
    required String? systemPrompt,
    GenerationParams? params,
    CancelToken? cancelToken,
    int? modelContextLength,
  }) {
    final threadId = history.isNotEmpty
        ? history.first.threadId
        : 'unknown';
    final fragments = _streamFragments[threadId] ?? [];

    if (fragments.isEmpty && _streamFragments.isNotEmpty) {
      final first = _streamFragments.entries.first;
      if (first.value.isNotEmpty) {
        return Stream.fromIterable(first.value);
      }
    }

    if (_shouldThrowStreamError) {
      return Stream.fromIterable([
        const StreamChunk(text: 'Error response', isDone: true),
      ]);
    }

    return Stream.fromIterable(fragments);
  }

  // --- Pending Async Requests ---

  final Map<String, PendingRequest> _pendingRequests = {};

  @override
  Future<void> savePendingRequest(PendingRequest request) async {
    _pendingRequests[request.requestId] = request;
  }

  @override
  Future<PendingRequest?> getPendingRequest(String requestId) async {
    return _pendingRequests[requestId];
  }

  @override
  Future<PendingRequest?> getPendingRequestByAssistantMessageId(String assistantMessageId) async {
    try {
      return _pendingRequests.values.firstWhere(
        (r) => r.assistantMessageId == assistantMessageId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<PendingRequest>> getPendingRequestsByThread(String threadId) async {
    return _pendingRequests.values
        .where((r) => r.threadId == threadId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<PendingRequest>> getPendingRequestsByStatus(PendingRequestStatus status) async {
    return _pendingRequests.values
        .where((r) => r.status == status)
        .toList();
  }

  @override
  Future<void> deletePendingRequest(String requestId) async {
    _pendingRequests.remove(requestId);
  }

  @override
  Future<void> cleanupExpiredPendingRequests() async {
    final now = DateTime.now();
    _pendingRequests.removeWhere((_, r) => r.expiresAt.isBefore(now));
  }

  // --- Async Completion API ---

  @override
  Future<String> submitAsyncCompletion({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required List<ChatMessage> history,
    required String? systemPrompt,
    GenerationParams? params,
    String? requestId,
    int? modelContextLength,
  }) async {
    // Generate a mock request ID for testing
    return 'test-request-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Stream<StreamChunk> streamAsyncCompletion({
    required String cleanBase,
    required String requestId,
    required String? apiKey,
    CancelToken? cancelToken,
  }) {
    final threadId = _pendingRequests[requestId]?.threadId ?? 'unknown';
    final fragments = _streamFragments[threadId] ?? [];

    if (fragments.isEmpty && _streamFragments.isNotEmpty) {
      final first = _streamFragments.entries.first;
      if (first.value.isNotEmpty) {
        return Stream.fromIterable(first.value);
      }
    }

    if (_shouldThrowStreamError) {
      return Stream.fromIterable([
        const StreamChunk(text: 'Error response', isDone: true),
      ]);
    }

    return Stream.fromIterable(fragments);
  }

  @override
  Future<Map<String, dynamic>?> fetchAsyncResult({
    required String cleanBase,
    required String requestId,
    required String? apiKey,
  }) async {
    return null;
  }

  @override
  Future<void> cancelAsyncRequest({
    required String cleanBase,
    required String requestId,
    required String? apiKey,
  }) async {
    _pendingRequests.remove(requestId);
  }
}
