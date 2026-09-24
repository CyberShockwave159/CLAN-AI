import 'dart:typed_data';

import 'package:sqflite_common/sqflite.dart';

import 'message_attachment_backend.dart';

/// Stores message image attachment bytes in a dedicated WASM sqlite database
/// (`clan_ai_attachments.db`) persisted in IndexedDB (web only).
///
/// Browsers have no writable filesystem, so — mirroring how the main app
/// databases persist — attachment bytes live in a small database of their own,
/// keyed by `id` (the same `$fileId.$ext` string the native backend would use
/// as a filename). This avoids touching the schema of `clan_ai.db` while
/// reusing the exact persistence mechanism the rest of the app already runs
/// on (requires `databaseFactory` to be bound to [databaseFactoryFfiWeb], done
/// in `main.dart` before any store is opened).
class SqliteAttachmentBackend implements AttachmentBackend {
  Database? _db;

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final db = await openDatabase(
      'clan_ai_attachments.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE attachments (id TEXT PRIMARY KEY, bytes BLOB NOT NULL)',
        );
      },
    );
    _db = db;
    return db;
  }

  @override
  Future<String> saveImage({
    required String fileId,
    required Uint8List data,
    String? extension,
  }) async {
    final id = '$fileId.${_sanitizeExtension(extension ?? 'jpg')}';
    final db = await _getDb();
    await db.insert(
      'attachments',
      {'id': id, 'bytes': data},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  @override
  Future<String> saveFile({
    required String fileId,
    required Uint8List data,
    String? fileName,
    String? mime,
  }) async {
    // `f_` prefix keeps generic artifact keys distinct from user image
    // attachment keys in the same table.
    final id = 'f_$fileId.${_extensionFor(fileName, mime)}';
    final db = await _getDb();
    await db.insert(
      'attachments',
      {'id': id, 'bytes': data},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  @override
  Future<void> deleteIfExists(String? ref) async {
    if (ref == null || ref.trim().isEmpty) return;
    try {
      final db = await _getDb();
      await db.delete('attachments', where: 'id = ?', whereArgs: [ref]);
    } catch (_) {
      // Best-effort cleanup — a dangling row is harmless.
    }
  }

  @override
  Future<Uint8List?> readBytes(String ref) async {
    try {
      final db = await _getDb();
      final rows = await db.query(
        'attachments',
        columns: ['bytes'],
        where: 'id = ?',
        whereArgs: [ref],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final bytes = rows.first['bytes'];
      return bytes is Uint8List ? bytes : null;
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

AttachmentBackend createAttachmentBackend() => SqliteAttachmentBackend();