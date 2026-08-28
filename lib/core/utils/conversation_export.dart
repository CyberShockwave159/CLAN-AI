import 'dart:convert';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';

enum ExportFormat { txt, json }

class ConversationExport {
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
}
