import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/core/utils/file_saver.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

enum ExportFormat { txt, json }

class ConversationExport {
  /// Builds the export filename from [thread]'s title and persists [content]
  /// via [FileSaver]. Shared by the ChatViewModel and RoleplayViewModel
  /// export flows (previously duplicated in both).
  static Future<String?> saveToFile(
    ChatThread thread,
    String content,
    ExportFormat format,
  ) async {
    final sanitizedTitle = thread.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final extension = format == ExportFormat.txt ? 'txt' : 'json';
    final filename = 'clan_ai_$sanitizedTitle.$extension';
    final mimeType = format == ExportFormat.json ? 'application/json' : 'text/plain';
    return await FileSaver.saveFile(
      filename: filename,
      content: content,
      mimeType: mimeType,
    );
  }

  static String formatTimestamp(DateTime timestamp) {
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final year = timestamp.year;
    final hour = timestamp.hour > 12 ? timestamp.hour - 12 : timestamp.hour == 0 ? 12 : timestamp.hour;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final ampm = timestamp.hour >= 12 ? 'PM' : 'AM';
    return '$month/$day/$year, $hour:$minute $ampm';
  }

  static String toTxt(
    ChatThread thread,
    List<ChatMessage> messages, {
    String? characterName,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('=== ${thread.title} ===');
    buffer.writeln('Date: ${formatTimestamp(thread.createdAt)}');
    if (thread.characterId != null && characterName != null) {
      buffer.writeln('Character: $characterName');
    }
    if (thread.modelId != null) {
      buffer.writeln('Model: ${thread.modelId}');
    }
    if (thread.systemPrompt != null && thread.systemPrompt!.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('--- System Prompt ---');
      buffer.writeln(thread.systemPrompt);
    }

    buffer.writeln('');
    buffer.writeln('--- Conversation ---');
    buffer.writeln('');

    for (final msg in messages) {
      final roleLabel = msg.role == MessageRole.user
          ? '[User]'
          : (msg.role == MessageRole.system ? '[System]' : '[Assistant]');

      buffer.writeln('$roleLabel  (${formatTimestamp(msg.createdAt)})');
      buffer.writeln(msg.content);
      buffer.writeln('');
    }

    return buffer.toString();
  }

  static String toJson(
    ChatThread thread,
    List<ChatMessage> messages, {
    String? characterName,
  }) {
    final exportMap = <String, dynamic>{
      'thread': {
        'id': thread.id,
        'title': thread.title,
        'created_at': thread.createdAt.toIso8601String(),
        'updated_at': thread.updatedAt.toIso8601String(),
        'model_id': thread.modelId,
        'system_prompt': thread.systemPrompt,
        'branch_from_thread_id': thread.branchFromThreadId,
        if (thread.characterId != null) 'character_id': thread.characterId,
        if (thread.characterId != null && characterName != null) 'character_name': characterName,
        if (thread.customParams != null) 'custom_params': thread.customParams!.toMap(),
      },
      'messages': messages.map((msg) => _messageToJson(msg)).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(exportMap);
  }

  static Map<String, dynamic> _messageToJson(ChatMessage msg) {
    return {
      'id': msg.id,
      'role': msg.role.value,
      'content': msg.content,
      'status': msg.status.name,
      'created_at': msg.createdAt.toIso8601String(),
      'parent_id': msg.parentId,
      'variant_index': msg.variantIndex,
      'total_variants': msg.totalVariants,
      'sibling_ids': msg.siblingIds,
      if (msg.tokensPerSecond != null) 'tokens_per_second': msg.tokensPerSecond,
      if (msg.totalTokens != null) 'total_tokens': msg.totalTokens,
      if (msg.timeToFirstTokenMs != null) 'time_to_first_token_ms': msg.timeToFirstTokenMs,
      if (msg.generationTimeSec != null) 'generation_time_sec': msg.generationTimeSec,
      if (msg.errorMessage != null) 'error_message': msg.errorMessage,
    };
  }

  static (ChatThread, List<ChatMessage>, String?) fromJson(Map<String, dynamic> json) {
    final threadMap = json['thread'] as Map<String, dynamic>;
    final messagesList = json['messages'] as List<dynamic>;

    GenerationParams? customParams;
    if (threadMap['custom_params'] != null) {
      try {
        customParams = GenerationParams.fromMap(threadMap['custom_params'] as Map<String, dynamic>);
      } catch (_) {}
    }

    final thread = ChatThread(
      id: threadMap['id'] as String? ?? const Uuid().v4(),
      title: threadMap['title'] as String? ?? 'Imported Chat',
      systemPrompt: threadMap['system_prompt'] as String?,
      modelId: threadMap['model_id'] as String?,
      customParams: customParams,
      branchFromThreadId: threadMap['branch_from_thread_id'] as String?,
      characterId: threadMap['character_id'] as String?,
      createdAt: DateTime.tryParse((threadMap['created_at'] as String?) ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse((threadMap['updated_at'] as String?) ?? '') ?? DateTime.now(),
    );

    final messages = messagesList.map((m) {
      final map = m as Map<String, dynamic>;
      return ChatMessage(
        id: map['id'] as String? ?? const Uuid().v4(),
        threadId: thread.id,
        parentId: map['parent_id'] as String?,
        role: MessageRole.fromString(map['role'] as String? ?? 'user'),
        content: map['content'] as String? ?? '',
        status: MessageStatus.values.firstWhere(
          (e) => e.name == (map['status'] as String? ?? 'completed'),
          orElse: () => MessageStatus.completed,
        ),
        tokensPerSecond: (map['tokens_per_second'] as num?)?.toDouble(),
        totalTokens: (map['total_tokens'] as num?)?.toInt(),
        timeToFirstTokenMs: (map['time_to_first_token_ms'] as num?)?.toInt(),
        generationTimeSec: (map['generation_time_sec'] as num?)?.toDouble(),
        errorMessage: map['error_message'] as String?,
        variantIndex: (map['variant_index'] as num?)?.toInt() ?? 0,
        totalVariants: (map['total_variants'] as num?)?.toInt() ?? 1,
        siblingIds: ((map['sibling_ids'] as List<dynamic>?) ?? []).cast<String>(),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      );
    }).toList();

    final characterName = threadMap['character_name'] as String?;

    return (thread, messages, characterName);
  }
}
