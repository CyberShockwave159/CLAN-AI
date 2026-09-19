import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores message image attachments as files on disk.
/// Mirrors [AvatarStorageService]: keeps the SQLite database lightweight by
/// moving image bytes to the filesystem and persisting only the file path
/// on the `ChatMessage` row (`messages.image_path`).
///
/// Files live under `<app documents>/attachments/` keyed by a generated id,
/// preserving the original file extension so the mime type stays resolvable
/// when the image is base64-encoded into an OpenAI-compatible payload.
class MessageAttachmentStore {
  static final MessageAttachmentStore instance = MessageAttachmentStore._init();
  MessageAttachmentStore._init();

  static const _attachmentDirName = 'attachments';

  static const Map<String, String> _mimeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'bmp': 'image/bmp',
    'heic': 'image/heic',
    'heif': 'image/heif',
  };

  Future<Directory> _getAttachmentDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(baseDir.path, _attachmentDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Saves [data] to disk and returns the absolute file path.
  /// The file is named by [fileId] (typically a message/variant id) with the
  /// original [extension] (without dot) preserved for mime detection.
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

  /// Deletes the attachment file at [path] if it exists. No-op for null paths.
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

  /// Resolves the mime type for [extension] (with or without leading dot),
  /// defaulting to `image/jpeg` when unknown.
  static String mimeTypeFor(String? extension) {
    final ext = _sanitizeExtension(extension ?? '');
    return _mimeByExtension[ext] ?? 'image/jpeg';
  }

  /// Detects the actual image format from [bytes]' magic bytes and returns the
  /// corresponding mime type, or `null` when the format cannot be identified.
  ///
  /// Prefer this over [mimeTypeFor] when the image bytes are already in hand:
  /// filename extensions can lie (e.g. a `.png`-named JPEG, or a path without
  /// an extension), and some servers trust the declared mime to pick a decoder.
  static String? mimeTypeFromBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      // JPEG: starts with the SOI marker FF D8 FF.
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      // PNG: 89 P N G \r \n 0x1A \n
      return 'image/png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      // GIF: "GIF87a" or "GIF89a"
      return 'image/gif';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      // BMP: "BM"
      return 'image/bmp';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      // WebP: "RIFF" .... "WEBP"
      return 'image/webp';
    }
    if (bytes.length >= 12 && _isIsoBmff(bytes)) {
      // HEIC/HEIF/AVIF are ISO-BMFF containers: <size> ftyp <brand>.
      final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
      if (brand == 'heic' || brand == 'heix' || brand == 'hevc' || brand == 'hevx') {
        return 'image/heic';
      }
      if (brand == 'mif1' || brand == 'msf1') {
        return 'image/heif';
      }
      if (brand == 'avif' || brand == 'avis') {
        return 'image/avif';
      }
    }
    return null;
  }

  static bool _isIsoBmff(Uint8List bytes) {
    // Bytes 4-7 hold the "ftyp" box type.
    return bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
  }

  /// Extracts the file extension (without dot) from a full file [path].
  /// Defaults to `jpg` for paths without an extension.
  static String extensionOf(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) return 'jpg';
    return path.substring(dotIndex + 1);
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
}