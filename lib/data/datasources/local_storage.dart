import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;
  SharedPreferences? _prefs;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('clan_ai.db');
    return _database!;
  }

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path;
    if (kIsWeb) {
      path = filePath;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      path = join(dbFolder.path, filePath);
    }

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      final columns = await db.rawQuery("PRAGMA table_info(threads)");
      final hasColumn = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'branch_from_thread_id');
      if (!hasColumn) {
        await db.execute('ALTER TABLE threads ADD COLUMN branch_from_thread_id TEXT');
      }
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // Threads table
    await db.execute('''
      CREATE TABLE threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        system_prompt TEXT,
        model_id TEXT,
        custom_params TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        branch_from_thread_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        parent_id TEXT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        status TEXT NOT NULL,
        tokens_per_second REAL,
        total_tokens INTEGER,
        time_to_first_token_ms INTEGER,
        generation_time_sec REAL,
        error_message TEXT,
        variant_index INTEGER NOT NULL DEFAULT 0,
        total_variants INTEGER NOT NULL DEFAULT 1,
        sibling_ids TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (thread_id) REFERENCES threads (id) ON DELETE CASCADE
      )
    ''');

    // Index for fast thread message retrieval
    await db.execute('CREATE INDEX idx_messages_thread_id ON messages (thread_id)');
  }

  // --- Thread Database Operations ---

  Future<void> insertThread(ChatThread thread) async {
    final db = await database;
    await db.insert('threads', thread.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateThread(ChatThread thread) async {
    final db = await database;
    await db.update(
      'threads',
      thread.toMap(),
      where: 'id = ?',
      whereArgs: [thread.id],
    );
  }

  Future<void> deleteThread(String threadId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'thread_id = ?', whereArgs: [threadId]);
      await txn.delete('threads', where: 'id = ?', whereArgs: [threadId]);
    });
  }

  Future<List<ChatThread>> getAllThreads() async {
    final db = await database;
    final result = await db.query('threads', orderBy: 'is_pinned DESC, updated_at DESC');
    return result.map((json) => ChatThread.fromMap(json)).toList();
  }

  Future<ChatThread?> getThreadById(String id) async {
    final db = await database;
    final result = await db.query('threads', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isNotEmpty) {
      return ChatThread.fromMap(result.first);
    }
    return null;
  }

  // --- Message Database Operations ---

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert('messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMessage(ChatMessage message) async {
    final db = await database;
    await db.update(
      'messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  Future<void> deleteMessage(String id) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChatMessage>> getMessagesForThread(String threadId) async {
    final db = await database;
    final result = await db.query(
      'messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
    return result.map((json) => ChatMessage.fromMap(json)).toList();
  }

  // --- Thread Lineage ---

  Future<List<ChatThread>> getThreadLineage(String threadId, {int maxDepth = 3}) async {
    final lineage = <ChatThread>[];
    var currentId = threadId;
    var depth = 0;

    while (depth < maxDepth) {
      final parent = await getThreadById(currentId);
      if (parent == null || parent.branchFromThreadId == null) break;
      lineage.add(parent);
      currentId = parent.branchFromThreadId!;
      depth++;
    }

    return lineage;
  }

  Future<List<ChatThread>> getThreadDescendants(String threadId) async {
    final db = await database;
    final result = await db.query('threads', where: 'branch_from_thread_id = ?', whereArgs: [threadId]);
    return result.map((json) => ChatThread.fromMap(json)).toList();
  }

  // --- Server Profile & Settings Persistence ---

  static const String _keyActiveServer = 'clan_active_server_config';
  static const String _keyThemeMode = 'clan_theme_mode';

  Future<void> saveActiveServerConfig(ServerConfig config) async {
    final p = await prefs;
    await p.setString(_keyActiveServer, jsonEncode(config.toMap()));
  }

  Future<ServerConfig> loadActiveServerConfig() async {
    final p = await prefs;
    final jsonStr = p.getString(_keyActiveServer);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        return ServerConfig.fromMap(jsonDecode(jsonStr));
      } catch (_) {}
    }
    return const ServerConfig();
  }

  Future<void> saveThemeMode(String mode) async {
    final p = await prefs;
    await p.setString(_keyThemeMode, mode);
  }

  Future<String> loadThemeMode() async {
    final p = await prefs;
    return p.getString(_keyThemeMode) ?? 'dark';
  }

  // --- System Prompt Template Persistence ---

  static const String _keySystemPromptTemplates = 'clan_system_prompt_templates';
  static const List<Map<String, String>> _defaultTemplates = [
    {'name': 'Default', 'content': 'You are a helpful, brilliant, and honest AI assistant.'},
    {'name': 'Code Architect', 'content': 'You are an elite software architect and senior engineer. Write clean, modular, and optimized code with complete explanations.'},
    {'name': 'Concise Expert', 'content': 'You are a concise expert. Answer directly and precisely without conversational filler.'},
    {'name': 'Creative Writer', 'content': 'You are a creative writer with rich vocabulary and engaging prose.'},
  ];

  Future<List<SystemPromptTemplate>> loadSystemPromptTemplates() async {
    final p = await prefs;
    final jsonStr = p.getString(_keySystemPromptTemplates);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        return jsonList
            .map((e) => SystemPromptTemplate.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    // Return defaults
    return _defaultTemplates
        .map((e) => SystemPromptTemplate(
              name: e['name']!,
              content: e['content']!,
            ))
        .toList();
  }

  Future<void> saveSystemPromptTemplates(List<SystemPromptTemplate> templates) async {
    final p = await prefs;
    await p.setString(
        _keySystemPromptTemplates, jsonEncode(templates.map((t) => t.toMap()).toList()));
  }

  // --- Server Profile Persistence ---

  static const String _keyServerProfiles = 'clan_server_profiles';
  static const String _keyActiveProfileId = 'clan_active_profile_id';

  Future<List<ServerProfile>> loadServerProfiles() async {
    final p = await prefs;
    final jsonStr = p.getString(_keyServerProfiles);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        return jsonList
            .map((e) => ServerProfile.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> saveServerProfiles(List<ServerProfile> profiles) async {
    final p = await prefs;
    await p.setString(
        _keyServerProfiles, jsonEncode(profiles.map((p) => p.toMap()).toList()));
  }

  Future<void> setActiveProfileId(String profileId) async {
    final p = await prefs;
    await p.setString(_keyActiveProfileId, profileId);
  }

  Future<String?> getActiveProfileId() async {
    final p = await prefs;
    return p.getString(_keyActiveProfileId);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
