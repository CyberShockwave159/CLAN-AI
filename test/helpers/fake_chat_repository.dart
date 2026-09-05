import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/repositories/chat_repository.dart';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class FakeChatRepository extends ChatRepository {
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
  Future<List<ChatMessage>> getMessagesForThread(String threadId) async {
    return (_threadMessages[threadId] ?? []).toList();
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
}
