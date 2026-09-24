import 'dart:typed_data';

import 'package:clan_ai/core/errors/app_exception.dart';
import 'package:clan_ai/core/utils/message_attachment_backend.dart';
import 'package:http/http.dart' as http;

/// Persists message image attachment bytes and resolves their mime types.
///
/// The storage mechanism is platform-dependent ([AttachmentBackend]): native
/// platforms keep the SQLite database lightweight by moving image bytes to the
/// filesystem (`<app documents>/attachments/`) and persisting only the file
/// path on the `ChatMessage` row (`messages.image_path`); web stores the same
/// bytes in a dedicated WASM sqlite database. The reference string returned by
/// [saveImage] is opaque to callers.
class MessageAttachmentStore {
  static final MessageAttachmentStore instance = MessageAttachmentStore._init();
  MessageAttachmentStore._init();

  final AttachmentBackend _backend = createAttachmentBackend();

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

  /// Reverse of [_mimeByExtension], used to recover an on-disk extension from
  /// the MIME type a `data:` URL declares (`image/png` → `png`).
  static const Map<String, String> _extensionByMime = {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/bmp': 'bmp',
    'image/heic': 'heic',
    'image/heif': 'heif',
    'image/avif': 'avif',
  };

  /// Saves [data] and returns an opaque reference that can later be passed to
  /// [readBytes] / [deleteIfExists]. The reference is derived from [fileId]
  /// (typically a message/variant id) with the original [extension] (without
  /// dot) preserved for mime detection.
  Future<String> saveImage({
    required String fileId,
    required Uint8List data,
    String? extension,
  }) {
    return _backend.saveImage(
      fileId: fileId,
      data: data,
      extension: extension,
    );
  }

  /// Saves generic artifact [data] (any file type) into the store and returns
  /// its opaque reference (absolute file path on native, logical key on web).
  /// [fileName] / [mime] (when known) drive the on-disk extension.
  Future<String> saveFile({
    required String fileId,
    required Uint8List data,
    String? fileName,
    String? mime,
  }) {
    return _backend.saveFile(
      fileId: fileId,
      data: data,
      fileName: fileName,
      mime: mime,
    );
  }

  /// Fetches raw bytes from an HTTP(S) [url], or decodes an inline `data:`
  /// URL (base64 or percent-encoded payload) without any network request.
  ///
  /// A-PROX can emit artifacts as base64 `data:` URIs
  /// (`[image_generation]/[file_generation].inline_data_url`), which must be
  /// decoded client-side instead of fetched. Pass through untouched otherwise.
  ///
  /// [client] is injectable for hermetic tests (e.g. `MockClient` from
  /// `package:http/testing`); when omitted a fresh client is used and closed
  /// before returning. Throws on non-200 responses / network failure.
  Future<Uint8List> fetchBytes(String url, {http.Client? client}) async {
    final inlineBytes = dataUrlBytes(url);
    if (inlineBytes != null) return inlineBytes;

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw AppException(
          message: 'Artifact download failed',
          details: 'HTTP ${response.statusCode} for $url',
        );
      }
      return response.bodyBytes;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Decodes a `data:` URL (`data:<mime>[;base64],<payload>`) into raw bytes,
  /// or `null` when [url] is not a data URL. Handles both base64 and
  /// percent-encoded payloads; an unparseable data URL also yields `null`.
  static Uint8List? dataUrlBytes(String url) {
    if (!url.toLowerCase().startsWith('data:')) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'data') return null;
    final data = uri.data;
    if (data == null) return null;
    try {
      return data.contentAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// The declared MIME type of a `data:` URL (e.g. `image/png`, `text/plain`),
  /// or `null` when [url] is not a data URL.
  static String? dataUrlMime(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'data') return null;
    return uri.data?.mimeType;
  }

  /// Downloads an A-PROX artifact from [url] into the store and returns an
  /// opaque reference to the stored bytes. [fileName] / [mime] from the server
  /// metadata are forwarded to the backend for extension resolution.
  ///
  /// [client] is injectable for hermetic tests.
  Future<String> downloadArtifact({
    required String fileId,
    required String url,
    String? fileName,
    String? mime,
    http.Client? client,
  }) async {
    final bytes = await fetchBytes(url, client: client);
    return saveFile(
      fileId: fileId,
      data: bytes,
      fileName: fileName ?? fileNameFromUrl(url),
      mime: mime,
    );
  }

  /// Extracts the file name from a URL (the path segment after the last `/`),
  /// or null when the URL has none. Returns null for `data:` URLs — they have
  /// no path, and their payload must not leak into a file name.
  static String? fileNameFromUrl(String url) {
    if (url.toLowerCase().startsWith('data:')) return null;
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.isEmpty) return null;
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return null;
      final last = segments.last;
      return last.isNotEmpty ? last : null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the attachment at [ref] if it exists. No-op for null refs.
  Future<void> deleteIfExists(String? ref) => _backend.deleteIfExists(ref);

  /// Reads the bytes for an attachment [ref], or `null` when missing or
  /// unreadable (a broken attachment never breaks a request).
  Future<Uint8List?> readBytes(String ref) => _backend.readBytes(ref);

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

  /// Resolves a sensible image file extension for [url]: the MIME type a
  /// `data:` URL declares (so `data:image/png;base64,…` saves as `.png`), or
  /// [extensionOf] for a path-based URL.
  static String extensionForUrl(String url) {
    if (url.toLowerCase().startsWith('data:')) {
      final mime = dataUrlMime(url)?.toLowerCase();
      if (mime != null) {
        final ext = _extensionByMime[mime];
        if (ext != null) return ext;
      }
    }
    return extensionOf(url);
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