/// Custom exceptions for network, llama.cpp server, and streaming errors.
class AppException implements Exception {
  final String message;
  final String? details;
  final int? statusCode;
  final bool isRetryable;
  final String? recoverySuggestion;

  const AppException({
    required this.message,
    this.details,
    this.statusCode,
    this.isRetryable = false,
    this.recoverySuggestion,
  });

  @override
  String toString() {
    if (details != null && details!.isNotEmpty) {
      return '$message: $details';
    }
    return message;
  }
}

class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.details,
    super.statusCode,
    super.isRetryable = true,
    super.recoverySuggestion = 'Check your Wi-Fi, IP address, port, and server firewall settings.',
  });
}

class HostUnreachableException extends NetworkException {
  const HostUnreachableException({
    required String host,
    super.details,
  }) : super(
          message: 'Unable to reach host ($host)',
          isRetryable: true,
          recoverySuggestion:
              'Verify that your llama.cpp server is running, listening on 0.0.0.0 (not just 127.0.0.1 if on mobile/LAN), and that the port is accessible.',
        );
}

class ContextLimitExceededException extends AppException {
  final int? requestedTokens;
  final int? maxContextTokens;

  const ContextLimitExceededException({
    required super.message,
    this.requestedTokens,
    this.maxContextTokens,
    super.details,
  }) : super(
          statusCode: 400,
          isRetryable: false,
          recoverySuggestion:
              'The prompt exceeds the server\'s context window. Try starting a new conversation thread or reducing the message history.',
        );
}

class ServerOOMException extends AppException {
  const ServerOOMException({
    super.message = 'Server Out of Memory / Slot Exhaustion',
    super.details,
  }) : super(
          statusCode: 500,
          isRetryable: true,
          recoverySuggestion:
              'The llama.cpp server ran out of VRAM/RAM or slots. Try reducing context size or unloading large models.',
        );
}

class RequestCancelledException extends AppException {
  const RequestCancelledException({
    super.message = 'Generation stopped by user',
  }) : super(isRetryable: false);
}
