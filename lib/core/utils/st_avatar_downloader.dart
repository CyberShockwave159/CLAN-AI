import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Maximum allowed avatar size: 5MB.
const _maxAvatarSizeBytes = 5 * 1024 * 1024;

/// Downloads avatar image bytes from a URL.
///
/// Returns null on any failure (timeout, non-200 status, oversized payload,
/// or non-image content-type).
/// Avatar is optional — callers should handle null gracefully.
class StAvatarDownloader {
  final http.Client _client;

  StAvatarDownloader({http.Client? client})
      : _client = client ?? http.Client();

  /// Fetches image bytes from [url].
  ///
  /// Times out after 30 seconds. Validates content-type header and payload
  /// size. Returns null if download fails, payload exceeds 5MB, or the
  /// response is not an image.
  Future<Uint8List?> downloadAvatar(String url) async {
    try {
      final response = await _client.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != 200) {
        return null;
      }

      // Validate Content-Type header starts with "image/"
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.startsWith('image/')) {
        return null;
      }

      // Check Content-Length if available
      if (response.contentLength != null &&
          response.contentLength! > _maxAvatarSizeBytes) {
        return null;
      }

      final bytes = response.bodyBytes;

      // Enforce hard limit on actual payload size
      if (bytes.length > _maxAvatarSizeBytes) {
        return null;
      }

      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Downloads an avatar and checks if it's a valid image by verifying magic bytes.
  ///
  /// Returns the image bytes if valid, null otherwise.
  Future<Uint8List?> downloadAndValidate(String url) async {
    final bytes = await downloadAvatar(url);
    if (bytes == null || bytes.isEmpty) return null;

    // Check for common image magic bytes
    if (_isPng(bytes) || _isJpeg(bytes) || _isWebp(bytes)) {
      return bytes;
    }

    return null;
  }

  bool _isPng(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4E && bytes[3] == 0x47 &&
        bytes[4] == 0x0D && bytes[5] == 0x0A &&
        bytes[6] == 0x1A && bytes[7] == 0x0A;
  }

  bool _isJpeg(Uint8List bytes) {
    return bytes.length >= 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  }

  bool _isWebp(Uint8List bytes) {
    return bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 &&
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 &&
        bytes[10] == 0x42 && bytes[11] == 0x50;
  }
}
