import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Service for storing character avatars as files on disk.
/// Keeps SQLite database lightweight by moving large avatar blobs to the filesystem.
class AvatarStorageService {
  static final AvatarStorageService instance = AvatarStorageService._init();
  AvatarStorageService._init();

  static const _avatarDirName = 'avatars';
  static const _maxInlineSize = 500 * 1024; // 500KB

  Future<String> _getAvatarDir() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory('${baseDir.path}/$_avatarDirName');
    if (!await avatarDir.exists()) {
      await avatarDir.create(recursive: true);
    }
    return avatarDir.path;
  }

  /// Returns true if the avatar data is large enough to warrant file storage.
  bool shouldUseFileStorage(Uint8List data) {
    return data.length > _maxInlineSize;
  }

  /// Saves avatar bytes to disk and optionally returns them for inline storage fallback.
  /// Returns the bytes for inline storage if file storage is not needed.
  /// Returns null if file storage was used (caller should use [getAvatarBytes] instead).
  Future<Uint8List?> saveAvatar(String characterId, Uint8List data) async {
    if (!shouldUseFileStorage(data)) {
      // Small enough to keep inline in SQLite
      return data;
    }

    final avatarDir = await _getAvatarDir();
    final file = File('$avatarDir/$characterId.png');
    await file.writeAsBytes(data);
    // Return null to indicate file storage was used
    return null;
  }

  /// Gets avatar bytes for a character.
  /// Tries file storage first, falls back to returning null if not found.
  Future<Uint8List?> getAvatarBytes(String characterId) async {
    final avatarDir = await _getAvatarDir();
    final file = File('$avatarDir/$characterId.png');
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// Deletes avatar file for a character.
  Future<void> deleteAvatar(String characterId) async {
    final avatarDir = await _getAvatarDir();
    final file = File('$avatarDir/$characterId.png');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Clears all avatar files.
  Future<void> clearAllAvatars() async {
    final avatarDir = await _getAvatarDir();
    final dir = Directory(avatarDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
