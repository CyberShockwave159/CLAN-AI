import 'dart:typed_data';

/// Provides `createAttachmentBackend()`, which returns the platform-appropriate
/// backend (io = files on disk, web = WASM sqlite, stub = unsupported).
export 'message_attachment_backend_stub.dart'
    if (dart.library.js_interop) 'message_attachment_backend_web.dart'
    if (dart.library.io) 'message_attachment_backend_io.dart'
    show createAttachmentBackend;

/// Storage-agnostic store for message image attachment bytes.
///
/// Native platforms persist attachments as files under
/// `docs/attachments/` and hand `messages.image_path` an absolute file path.
/// Web has no filesystem, so the web backend stores the same binary bytes in a
/// dedicated WASM sqlite database (`clan_ai_attachments.db`, IndexedDB-backed)
/// and the "ref" returned by [saveImage] is the logical key `$fileId.$ext`.
/// Callers never need to know which backend is active.
abstract interface class AttachmentBackend {
  /// Saves [data] and returns an opaque reference string that can later be
  /// passed to [readBytes] / [deleteIfExists].
  Future<String> saveImage({
    required String fileId,
    required Uint8List data,
    String? extension,
  });

  /// Best-effort deletion. No-op for null/blank references.
  Future<void> deleteIfExists(String? ref);

  /// Reads the bytes for [ref], or `null` when missing/unreadable.
  Future<Uint8List?> readBytes(String ref);
}