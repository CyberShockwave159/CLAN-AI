/// Status of a pending async request
enum PendingRequestStatus {
  pending,
  streaming,
  completed,
  failed,
}

/// Represents a pending async request that can be resumed across app restarts.
class PendingRequest {
  final String requestId;
  final String threadId;
  final String assistantMessageId;
  final Map<String, dynamic> payload;
  final PendingRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final String serverBaseUrl;
  final String? error;

  const PendingRequest({
    required this.requestId,
    required this.threadId,
    required this.assistantMessageId,
    required this.payload,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    required this.serverBaseUrl,
    this.error,
  });

  /// Check if the request has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Check if the request is in a terminal state
  bool get isTerminal =>
      status == PendingRequestStatus.completed ||
      status == PendingRequestStatus.failed;

  /// Convert to a map for database storage
  Map<String, dynamic> toMap() {
    return {
      'request_id': requestId,
      'thread_id': threadId,
      'assistant_message_id': assistantMessageId,
      'payload': payload.toString(), // JSON string
      'status': _statusToString(status),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'expires_at': expiresAt.millisecondsSinceEpoch,
      'server_base_url': serverBaseUrl,
      'error': error,
    };
  }

  /// Create from a database map
  static PendingRequest fromMap(Map<String, dynamic> map) {
    return PendingRequest(
      requestId: map['request_id'] as String,
      threadId: map['thread_id'] as String,
      assistantMessageId: map['assistant_message_id'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      status: _stringToStatus(map['status'] as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(map['expires_at'] as int),
      serverBaseUrl: map['server_base_url'] as String,
      error: map['error'] as String?,
    );
  }

  /// Create a copy with updated fields
  PendingRequest copyWith({
    String? requestId,
    String? threadId,
    String? assistantMessageId,
    Map<String, dynamic>? payload,
    PendingRequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    String? serverBaseUrl,
    String? error,
  }) {
    return PendingRequest(
      requestId: requestId ?? this.requestId,
      threadId: threadId ?? this.threadId,
      assistantMessageId: assistantMessageId ?? this.assistantMessageId,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
      error: error ?? this.error,
    );
  }

  static String _statusToString(PendingRequestStatus status) {
    switch (status) {
      case PendingRequestStatus.pending:
        return 'pending';
      case PendingRequestStatus.streaming:
        return 'streaming';
      case PendingRequestStatus.completed:
        return 'completed';
      case PendingRequestStatus.failed:
        return 'failed';
    }
  }

  static PendingRequestStatus _stringToStatus(String status) {
    switch (status) {
      case 'pending':
        return PendingRequestStatus.pending;
      case 'streaming':
        return PendingRequestStatus.streaming;
      case 'completed':
        return PendingRequestStatus.completed;
      case 'failed':
        return PendingRequestStatus.failed;
      default:
        return PendingRequestStatus.pending;
    }
  }
}