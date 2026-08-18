import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:clan_ai/domain/models/generation_params.dart';

class ChatThread {
  final String id;
  final String title;
  final String? systemPrompt;
  final String? modelId;
  final GenerationParams? customParams;
  final bool isPinned;
  final String? branchFromThreadId;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatThread({
    String? id,
    this.title = 'New Chat',
    this.systemPrompt,
    this.modelId,
    this.customParams,
    this.isPinned = false,
    this.branchFromThreadId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ChatThread copyWith({
    String? id,
    String? title,
    String? systemPrompt,
    String? modelId,
    GenerationParams? customParams,
    bool? isPinned,
    String? branchFromThreadId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatThread(
      id: id ?? this.id,
      title: title ?? this.title,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      modelId: modelId ?? this.modelId,
      customParams: customParams ?? this.customParams,
      isPinned: isPinned ?? this.isPinned,
      branchFromThreadId: branchFromThreadId ?? this.branchFromThreadId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'system_prompt': systemPrompt,
      'model_id': modelId,
      'custom_params': customParams != null ? jsonEncode(customParams!.toMap()) : null,
      'is_pinned': isPinned ? 1 : 0,
      'branch_from_thread_id': branchFromThreadId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ChatThread.fromMap(Map<String, dynamic> map) {
    GenerationParams? customParams;
    if (map['custom_params'] != null && (map['custom_params'] as String).isNotEmpty) {
      try {
        customParams = GenerationParams.fromMap(jsonDecode(map['custom_params'] as String));
      } catch (_) {}
    }

    return ChatThread(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'New Chat',
      systemPrompt: map['system_prompt'] as String?,
      modelId: map['model_id'] as String?,
      customParams: customParams,
      isPinned: (map['is_pinned'] as int?) == 1,
      branchFromThreadId: map['branch_from_thread_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
