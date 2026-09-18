import 'dart:async';
import 'package:clan_ai/core/network/sse_client.dart';
import 'package:clan_ai/data/datasources/llama_api_service.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class ChatRepository {
  final LocalDatabase _localDb;
  final LlamaApiService _apiService;

  ChatRepository({
    LocalDatabase? localDb,
    LlamaApiService? apiService,
  })  : _localDb = localDb ?? LocalDatabase.instance,
        _apiService = apiService ?? LlamaApiService();

  // --- Thread Methods ---

  Future<List<ChatThread>> getThreads() async {
    return await _localDb.getAllThreads();
  }

  /// Returns only assistant-mode threads (characterId == null).
  /// Use this instead of getThreads() in assistant-mode contexts to
  /// prevent roleplay threads from leaking into the assistant UI.
  Future<List<ChatThread>> getAssistantThreads() async {
    return (await _localDb.getAllThreads())
        .where((t) => t.characterId == null)
        .toList();
  }

  /// Returns all threads belonging to a specific character, sorted by
  /// updated_at descending (most recent first).
  Future<List<ChatThread>> getThreadsForCharacter(String characterId) async {
    final threads = await _localDb.getAllThreads();
    return threads
        .where((t) => t.characterId == characterId)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

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
    await _localDb.insertThread(thread);
    return thread;
  }

  Future<void> updateThread(ChatThread thread) async {
    await _localDb.updateThread(thread);
  }

  Future<void> deleteThread(String threadId) async {
    await _localDb.deleteThread(threadId);
  }

  /// Searches assistant-mode threads (character_id IS NULL) by title or
  /// message content in a single SQL query — no per-thread message loads.
  Future<List<ChatThread>> searchThreads(String query) async {
    return await _localDb.searchThreads(query);
  }

  /// Returns a list of thread IDs representing the current thread and all
  /// its ancestor threads (up the branch chain). Used for RAG memory scoping.
  Future<List<String>> getThreadLineageIds(String threadId) async {
    final lineageIds = <String>[threadId];
    var currentId = threadId;
    var depth = 0;
    const maxDepth = 20;

    while (depth < maxDepth) {
      final thread = await _localDb.getThreadById(currentId);
      if (thread == null || thread.branchFromThreadId == null) break;
      lineageIds.add(thread.branchFromThreadId!);
      currentId = thread.branchFromThreadId!;
      depth++;
    }

    return lineageIds;
  }

  // --- Message Methods ---

  Future<List<ChatMessage>> getAllMessagesForThread(String threadId) async {
    return await _localDb.getMessagesForThread(threadId);
  }

  Future<List<ChatMessage>> getMessagesForThread(String threadId) async {
    final messages = await _localDb.getMessagesForThread(threadId);
    return _deduplicateVariantMessages(messages);
  }

  List<ChatMessage> _deduplicateVariantMessages(List<ChatMessage> messages) {
    final grouped = <String, List<ChatMessage>>{};
    for (final msg in messages) {
      String key;
      if (msg.role == MessageRole.user) {
        key = 'user_${msg.id}';
      } else {
        key = '${msg.role.name}_${msg.parentId ?? "_null_"}';
      }
      grouped.putIfAbsent(key, () => []).add(msg);
    }
    final deduplicated = <ChatMessage>[];
    for (final group in grouped.values) {
      group.sort((a, b) => a.variantIndex.compareTo(b.variantIndex));
      deduplicated.add(group.last);
    }
    return deduplicated;
  }

  Future<void> saveMessage(ChatMessage message) async {
    await _localDb.insertMessage(message);
  }

  Future<void> updateMessage(ChatMessage message) async {
    await _localDb.updateMessage(message);
  }

  Future<void> deleteMessage(String id) async {
    await _localDb.deleteMessage(id);
  }

  // --- Streaming Generation ---

  Stream<StreamChunk> streamCompletion({
    required ServerConfig serverConfig,
    required ServerProfile? connection,
    required List<ChatMessage> history,
    required String? systemPrompt,
    GenerationParams? params,
    CancelToken? cancelToken,
    int? modelContextLength,
  }) {
    return _apiService.streamChatCompletions(
      serverConfig: serverConfig,
      connection: connection,
      history: history,
      systemPrompt: systemPrompt,
      params: params,
      cancelToken: cancelToken,
      modelContextLength: modelContextLength,
    );
  }
}
