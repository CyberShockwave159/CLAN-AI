import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:clan_ai/core/utils/mutex.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/data/models/server_config.dart';
import 'package:clan_ai/data/models/server_profile.dart';
import 'package:clan_ai/data/models/system_prompt_template.dart';
import 'package:clan_ai/data/models/persona_template.dart';
import 'package:clan_ai/data/models/app_mode.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static final _mutex = Mutex();
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
    // SQLite FFI factory is initialized once in main.dart
    // This check is a defensive guard in case _initDB is called before main()

    String path;
    if (kIsWeb) {
      path = filePath;
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      path = join(dbFolder.path, filePath);
    }

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final columns = await db.rawQuery("PRAGMA table_info(threads)");
      final hasColumn = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'custom_params');
      if (!hasColumn) {
        await db.execute('ALTER TABLE threads ADD COLUMN custom_params TEXT');
      }
    }
    if (oldVersion < 3) {
      final columns = await db.rawQuery("PRAGMA table_info(threads)");
      final hasColumn = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'branch_from_thread_id');
      if (!hasColumn) {
        await db.execute('ALTER TABLE threads ADD COLUMN branch_from_thread_id TEXT');
      }
    }
    if (oldVersion < 4) {
      final columns = await db.rawQuery("PRAGMA table_info(threads)");
      final hasColumn = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'character_id');
      if (!hasColumn) {
        await db.execute('ALTER TABLE threads ADD COLUMN character_id TEXT');
      }
    }
    if (oldVersion < 5) {
      final columns = await db.rawQuery("PRAGMA table_info(messages)");
      final hasIsEdited = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'is_edited');
      if (!hasIsEdited) {
        await db.execute('ALTER TABLE messages ADD COLUMN is_edited INTEGER NOT NULL DEFAULT 0');
      }
      final hasUpdatedAt = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'updated_at');
      if (!hasUpdatedAt) {
        await db.execute('ALTER TABLE messages ADD COLUMN updated_at TEXT');
      }
    }
    if (oldVersion < 6) {
      final columns = await db.rawQuery("PRAGMA table_info(messages)");
      final hasRagMemoryCount = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'rag_memory_count');
      if (!hasRagMemoryCount) {
        await db.execute('ALTER TABLE messages ADD COLUMN rag_memory_count INTEGER DEFAULT NULL');
      }
    }
    if (oldVersion < 7) {
      final columns = await db.rawQuery("PRAGMA table_info(messages)");
      final hasReasoningContent = (columns as List<dynamic>)
          .any((col) => (col as Map<String, dynamic>)['name'] == 'reasoning_content');
      if (!hasReasoningContent) {
        await db.execute('ALTER TABLE messages ADD COLUMN reasoning_content TEXT NOT NULL DEFAULT ""');
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
        character_id TEXT,
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
        is_edited INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        rag_memory_count INTEGER DEFAULT NULL,
        reasoning_content TEXT NOT NULL DEFAULT "",
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

  // --- Character Database Operations ---

  Future<List<CharacterProfile>> getAllCharacters() async {
    final p = await prefs;
    final jsonStr = p.getString(_keyCharacters);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        return jsonList
            .map((e) => CharacterProfile.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<CharacterProfile?> getCharacterById(String id) async {
    final characters = await getAllCharacters();
    for (final c in characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> insertCharacter(CharacterProfile character) async {
    return _mutex.run(() async {
      final p = await prefs;
      final profiles = await getAllCharacters();
      profiles.add(character);
      await p.setString(_keyCharacters, jsonEncode(profiles.map((c) => c.toMap()).toList()));
    });
  }

  Future<void> updateCharacter(CharacterProfile character) async {
    return _mutex.run(() async {
      final p = await prefs;
      final profiles = await getAllCharacters();
      final index = profiles.indexWhere((c) => c.id == character.id);
      if (index != -1) {
        profiles[index] = character;
        await p.setString(_keyCharacters, jsonEncode(profiles.map((c) => c.toMap()).toList()));
      }
    });
  }

  Future<void> deleteCharacter(String id) async {
    return _mutex.run(() async {
      final p = await prefs;
      final profiles = await getAllCharacters();
      profiles.removeWhere((c) => c.id == id);
      await p.setString(_keyCharacters, jsonEncode(profiles.map((c) => c.toMap()).toList()));
    });
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
  static const String _keyAppMode = 'clan_app_mode';
  static const String _keyCharacters = 'clan_characters';
  static const String _keyLastRoleplayThread = 'clan_last_roleplay_thread_id';

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

  // --- App Mode Persistence ---

  Future<void> saveAppMode(AppMode mode) async {
    final p = await prefs;
    await p.setString(_keyAppMode, mode.name);
  }

  Future<AppMode> loadAppMode() async {
    final p = await prefs;
    final modeStr = p.getString(_keyAppMode);
    if (modeStr != null && modeStr.isNotEmpty) {
      try {
        return AppMode.values.firstWhere((m) => m.name == modeStr);
      } catch (_) {}
    }
    return AppMode.assistant;
  }

  // --- Last Roleplay Thread Persistence ---

  Future<void> saveLastRoleplayThreadId(String? threadId) async {
    final p = await prefs;
    if (threadId != null) {
      await p.setString(_keyLastRoleplayThread, threadId);
    } else {
      await p.remove(_keyLastRoleplayThread);
    }
  }

  Future<String?> loadLastRoleplayThreadId() async {
    final p = await prefs;
    return p.getString(_keyLastRoleplayThread);
  }

  // --- Character Persistence ---

  Future<void> saveCharacters(List<CharacterProfile> characters) async {
    final p = await prefs;
    await p.setString(_keyCharacters, jsonEncode(characters.map((c) => c.toMap()).toList()));
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

  // --- Persona Template Persistence ---

  static const String _keyPersonaTemplates = 'clan_persona_templates';

  Future<List<PersonaTemplate>> loadPersonaTemplates() async {
    final p = await prefs;
    final jsonStr = p.getString(_keyPersonaTemplates);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr) as List<dynamic>;
        return jsonList
            .map((e) => PersonaTemplate.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> savePersonaTemplates(List<PersonaTemplate> templates) async {
    final p = await prefs;
    await p.setString(_keyPersonaTemplates, jsonEncode(templates.map((t) => t.toMap()).toList()));
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
