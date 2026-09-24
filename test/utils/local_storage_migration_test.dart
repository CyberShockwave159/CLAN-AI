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
  });
}