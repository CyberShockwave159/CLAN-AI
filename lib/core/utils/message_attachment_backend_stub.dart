import 'message_attachment_backend.dart';

/// Stub used for platforms without a real backend (never reached on supported
/// targets — the io and web variants take precedence via conditional import).
AttachmentBackend createAttachmentBackend() =>
    throw UnsupportedError('No attachment backend for this platform');