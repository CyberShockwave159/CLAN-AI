import 'package:uuid/uuid.dart';

enum MessageRole {
  system,
  user,
  assistant;

  String get value => name;

  static MessageRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'system':
        return MessageRole.system;
      case 'user':
        return MessageRole.user;
      case 'assistant':
      default:
        return MessageRole.assistant;
    }
  }
}

enum MessageStatus {
  idle,
  sending,
  streaming,
  completed,
  error,
}

class ChatMessage {
  final String id;
  final String threadId;
  final String? parentId;
  final MessageRole role;
  final String content;
  final MessageStatus status;
  final double? tokensPerSecond;
  final int? totalTokens;
  final int? timeToFirstTokenMs;
  final double? generationTimeSec;
  final String? errorMessage;
  final int variantIndex;
  final int totalVariants;
  final List<String> siblingIds;
  final DateTime createdAt;
  final bool isEdited;
  final DateTime? updatedAt;
  final int? ragMemoryCount;

  ChatMessage({
    String? id,
    required this.threadId,
    this.parentId,
    required this.role,
    required this.content,
    this.status = MessageStatus.completed,
    this.tokensPerSecond,
    this.totalTokens,
    this.timeToFirstTokenMs,
    this.generationTimeSec,
    this.errorMessage,
    this.variantIndex = 0,
    this.totalVariants = 1,
    this.siblingIds = const [],
    DateTime? createdAt,
    this.isEdited = false,
    this.updatedAt,
    this.ragMemoryCount,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  ChatMessage copyWith({
    String? id,
    String? threadId,
    String? parentId,
    MessageRole? role,
    String? content,
    MessageStatus? status,
    double? tokensPerSecond,
    int? totalTokens,
    int? timeToFirstTokenMs,
    double? generationTimeSec,
    String? errorMessage,
    int? variantIndex,
    int? totalVariants,
    List<String>? siblingIds,
    DateTime? createdAt,
    bool? isEdited,
    DateTime? updatedAt,
    int? ragMemoryCount,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      threadId: threadId ?? this.threadId,
      parentId: parentId ?? this.parentId,
      role: role ?? this.role,
      content: content ?? this.content,
      status: status ?? this.status,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      totalTokens: totalTokens ?? this.totalTokens,
      timeToFirstTokenMs: timeToFirstTokenMs ?? this.timeToFirstTokenMs,
      generationTimeSec: generationTimeSec ?? this.generationTimeSec,
      errorMessage: errorMessage ?? this.errorMessage,
      variantIndex: variantIndex ?? this.variantIndex,
      totalVariants: totalVariants ?? this.totalVariants,
      siblingIds: siblingIds ?? this.siblingIds,
      createdAt: createdAt ?? this.createdAt,
      isEdited: isEdited ?? this.isEdited,
      updatedAt: updatedAt ?? this.updatedAt,
      ragMemoryCount: ragMemoryCount ?? this.ragMemoryCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'thread_id': threadId,
      'parent_id': parentId,
      'role': role.value,
      'content': content,
      'status': status.name,
      'tokens_per_second': tokensPerSecond,
      'total_tokens': totalTokens,
      'time_to_first_token_ms': timeToFirstTokenMs,
      'generation_time_sec': generationTimeSec,
      'error_message': errorMessage,
      'variant_index': variantIndex,
      'total_variants': totalVariants,
      'sibling_ids': siblingIds.join(','),
      'created_at': createdAt.toIso8601String(),
      'is_edited': isEdited ? 1 : 0,
      'updated_at': updatedAt?.toIso8601String(),
      'rag_memory_count': ragMemoryCount,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final siblingsStr = map['sibling_ids'] as String? ?? '';
    final siblingIds = siblingsStr.isNotEmpty ? siblingsStr.split(',') : <String>[];

    return ChatMessage(
      id: map['id'] as String? ?? const Uuid().v4(),
      threadId: map['thread_id'] as String,
      parentId: map['parent_id'] as String?,
      role: MessageRole.fromString(map['role'] as String? ?? 'user'),
      content: map['content'] as String? ?? '',
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.completed,
      ),
      tokensPerSecond: (map['tokens_per_second'] as num?)?.toDouble(),
      totalTokens: (map['total_tokens'] as num?)?.toInt(),
      timeToFirstTokenMs: (map['time_to_first_token_ms'] as num?)?.toInt(),
      generationTimeSec: (map['generation_time_sec'] as num?)?.toDouble(),
      errorMessage: map['error_message'] as String?,
      variantIndex: (map['variant_index'] as num?)?.toInt() ?? 0,
      totalVariants: (map['total_variants'] as num?)?.toInt() ?? 1,
      siblingIds: siblingIds,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      isEdited: (map['is_edited'] as num?)?.toInt() == 1,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
      ragMemoryCount: (map['rag_memory_count'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toOpenAiMessage() {
    return {
      'role': role.value,
      'content': content,
    };
  }
}
