import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'message_attachment_backend.dart';

/// Stores message image attachments as files on disk (native platforms).
///
/// Keeps the SQLite database lightweight by moving image bytes to the
/// filesystem and persisting only the file path on the `ChatMessage` row
/// (`messages.image_path`). Files live under `<app documents>/attachments/`
/// keyed by a generated id, preserving the original file extension so the mime
/// type stays resolvable when the image is base64-encoded into an
/// OpenAI-compatible payload.
class FileAttachmentBackend implements AttachmentBackend {
  static const _attachmentDirName = 'attachments';

  Future<Directory> _getAttachmentDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(baseDir.path, _attachmentDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Future<String> saveImage({
    required String fileId,
    required Uint8List data,
    String? extension,
  }) async {
    final dir = await _getAttachmentDir();
    final ext = _sanitizeExtension(extension ?? 'jpg');
    final file = File(p.join(dir.path, '$fileId.$ext'));
    await file.writeAsBytes(data);
    return file.path;
  }

  @override
  Future<String> saveFile({
    required String fileId,
    required Uint8List data,
    String? fileName,
    String? mime,
  }) async {
    final dir = await _getAttachmentDir();
    final ext = _sanitizeExtension(_extensionFor(fileName, mime));
    // `f_` prefix keeps generic artifact files distinct from user image
    // attachments in the same directory.
    final file = File(p.join(dir.path, 'f_$fileId.$ext'));
    await file.writeAsBytes(data);
    return file.path;
  }

  @override
  Future<void> deleteIfExists(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup — a dangling file is harmless.
    }
  }

  @override
  Future<Uint8List?> readBytes(String ref) async {
    try {
      final file = File(ref);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static String _sanitizeExtension(String extension) {
    var ext = extension.trim().toLowerCase();
    if (ext.startsWith('.')) {
      ext = ext.substring(1);
    }
    final dotIndex = ext.indexOf('.');
    if (dotIndex != -1) {
      ext = ext.substring(0, dotIndex);
    }
    return ext;
  }

  static const Map<String, String> _extensionByMime = {
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'application/json': 'json',
    'text/plain': 'txt',
    'text/csv': 'csv',
    'text/markdown': 'md',
    'audio/mpeg': 'mp3',
    'audio/wav': 'wav',
    'video/mp4': 'mp4',
    'video/webm': 'webm',
  };

  static String _extensionFor(String? fileName, String? mime) {
    if (fileName != null && fileName.isNotEmpty) {
      final dotIndex = fileName.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < fileName.length - 1) {
        return fileName.substring(dotIndex + 1);
      }
    }
    if (mime != null && mime.isNotEmpty) {
      return _extensionByMime[mime.toLowerCase()] ?? 'bin';
    }
    return 'bin';
  }
}

AttachmentBackend createAttachmentBackend() => FileAttachmentBackend();