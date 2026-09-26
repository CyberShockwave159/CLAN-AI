import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalDatabase schema migration', () {
    setUpAll(() {
      sqfliteFfiInit();
    });

    test('migration 13 -> 14 adds file_path, file_name, file_mime columns',
        () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 13, singleInstance: false),
      );
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
          image_path TEXT
        )
      ''');
      await db.execute('INSERT INTO messages (id, thread_id, role, content, status) '
          "VALUES ('m1', 't1', 'assistant', 'Hello', 'completed')");

      await LocalDatabase.instance.runMigrationForTesting(db, 13);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final names = columns.map((c) => c['name'] as String).toList();
      expect(names, contains('file_path'));
      expect(names, contains('file_name'));
      expect(names, contains('file_mime'));

      await db.execute(
        'UPDATE messages SET file_path = ?, file_name = ?, file_mime = ? '
        'WHERE id = ?',
        ['/tmp/f_m1.pdf', 'report.pdf', 'application/pdf', 'm1'],
      );
      final row = await db.query('messages', where: 'id = ?', whereArgs: ['m1']);
      expect(row.single['file_name'], equals('report.pdf'));
      expect(row.single['file_mime'], equals('application/pdf'));

      await db.close();
    });

    test('legacy rows survive migration with null file columns', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 13, singleInstance: false),
      );
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          thread_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          status TEXT NOT NULL,
          variant_index INTEGER NOT NULL DEFAULT 0,
          total_variants INTEGER NOT NULL DEFAULT 1,
          sibling_ids TEXT,
          image_path TEXT
        )
      ''');
      await db.execute("INSERT INTO messages (id, thread_id, role, content, status) "
          "VALUES ('m2', 't1', 'user', 'hi', 'completed')");

      await LocalDatabase.instance.runMigrationForTesting(db, 13);

      final row = (await db.query('messages')).single;
      expect(row['file_path'], isNull);
      expect(row['file_name'], isNull);
      expect(row['file_mime'], isNull);
      expect(row['content'], equals('hi'));

      await db.close();
    });

    test('migration 14 -> 15 adds image_url column', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 14, singleInstance: false),
      );
      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          thread_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          status TEXT NOT NULL,
          variant_index INTEGER NOT NULL DEFAULT 0,
          total_variants INTEGER NOT NULL DEFAULT 1,
          sibling_ids TEXT,
          image_path TEXT,
          file_path TEXT,
          file_name TEXT,
          file_mime TEXT
        )
      ''');
      await db.execute("INSERT INTO messages (id, thread_id, role, content, status) "
          "VALUES ('m3', 't1', 'assistant', 'Hello', 'completed')");

      await LocalDatabase.instance.runMigrationForTesting(db, 14);

      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final names = columns.map((c) => c['name'] as String).toList();
      expect(names, contains('image_url'));

      await db.execute(
        'UPDATE messages SET image_url = ? WHERE id = ?',
        ['http://192.168.1.64:8000/images/gen_1.png', 'm3'],
      );
      final row = (await db.query('messages')).single;
      expect(row['image_url'], equals('http://192.168.1.64:8000/images/gen_1.png'));

      await db.close();
    });

    test('migration 15 -> 16 adds appearance, identity_portrait_data, visual_theme',
        () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 15, singleInstance: false),
      );
      await _createLegacyCharactersTable(db);
      await db.execute(
        "INSERT INTO characters (id, name, personality, first_message, created_at, updated_at) "
        "VALUES ('c1', 'Sarah', 'A warm-eyed archivist', 'Hello there.', '2024-01-01T00:00:00.000', '2024-01-01T00:00:00.000')",
      );

      await LocalDatabase.instance.runMigrationForTesting(db, 15);

      final columns = await db.rawQuery('PRAGMA table_info(characters)');
      final names = columns.map((c) => c['name'] as String).toList();
      expect(names, contains('appearance'));
      expect(names, contains('identity_portrait_data'));
      expect(names, contains('visual_theme'));

      // Pre-existing rows survive with the new columns NULL — a character that
      // has never been through the appearance flow must not gain a value.
      final row = (await db.query('characters')).single;
      expect(row['name'], equals('Sarah'));
      expect(row['appearance'], isNull);
      expect(row['identity_portrait_data'], isNull);
      expect(row['visual_theme'], isNull);

      await db.execute(
        'UPDATE characters SET appearance = ?, visual_theme = ? WHERE id = ?',
        ['Auburn shoulder-length hair, green eyes', 'anime', 'c1'],
      );
      final updated = (await db.query('characters')).single;
      expect(updated['appearance'], contains('Auburn'));
      expect(updated['visual_theme'], equals('anime'));

      await db.close();
    });

    test('migration 15 -> 16 preserves an existing appearance sheet', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 15, singleInstance: false),
      );
      // A database that already carries one of the new columns (e.g. a partial
      // upgrade) must not lose it — the PRAGMA guard skips existing columns.
      await _createLegacyCharactersTable(db);
      await db.execute('ALTER TABLE characters ADD COLUMN appearance TEXT');
      await db.execute(
        "INSERT INTO characters (id, name, personality, first_message, appearance, created_at, updated_at) "
        "VALUES ('c1', 'Sarah', 'archivist', 'Hi', 'Green eyes, sharp jaw', '2024-01-01T00:00:00.000', '2024-01-01T00:00:00.000')",
      );

      await LocalDatabase.instance.runMigrationForTesting(db, 15);

      final row = (await db.query('characters')).single;
      expect(row['appearance'], equals('Green eyes, sharp jaw'));
      final columns = await db.rawQuery('PRAGMA table_info(characters)');
      final names = columns.map((c) => c['name'] as String).toList();
      expect(names.where((n) => n == 'appearance'), hasLength(1));
      expect(names, contains('identity_portrait_data'));
      expect(names, contains('visual_theme'));

      await db.close();
    });
  });
}

/// The v15 `characters` table, for migration fixtures.
Future<void> _createLegacyCharactersTable(Database db) async {
  await db.execute('''
    CREATE TABLE characters (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      personality TEXT NOT NULL,
      first_message TEXT NOT NULL,
      setting TEXT,
      user_persona TEXT,
      persona_name TEXT,
      persona_description TEXT,
      avatar_data BLOB,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      system_prompt TEXT,
      post_history_instructions TEXT,
      alternate_greetings TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
}