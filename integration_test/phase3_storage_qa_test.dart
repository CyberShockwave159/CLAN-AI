import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'package:clan_ai/core/utils/conversation_export.dart';
import 'package:clan_ai/core/utils/message_attachment_store.dart';
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/datasources/secure_storage_service.dart';
import 'package:clan_ai/data/models/app_mode.dart';
import 'package:clan_ai/data/models/app_theme_mode.dart';
import 'package:clan_ai/data/models/chat_message.dart';
import 'package:clan_ai/data/models/chat_thread.dart';
import 'package:clan_ai/data/models/server_profile.dart';

import 'qa_check.dart';

/// Phase 3 QA — web persistence in a real browser (no UI).
///
/// Every check runs against the actual web runtime: the WASM sqlite databases
/// (IndexedDB-backed), localStorage-backed SharedPreferences and
/// flutter_secure_storage_web. Failure here means the browser-equivalent of a
/// desktop feature went missing on web.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Mirrors lib/main.dart's `_initSqliteFfi()` web branch so the store
    // under test uses the same WASM + SharedWorker setup the app runs on.
    databaseFactory = databaseFactoryFfiWeb;
    // Force the main DB so failures surface here, not on first app use.
    await LocalDatabase.instance.database;
  });

  testWidgets('attachment store: save -> read -> delete round trip', (tester) async {
    // 1x1 PNG (89 50 4E 47 ...) so mime detection matches too.
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    ]);
    expect(MessageAttachmentStore.mimeTypeFromBytes(png), 'image/png');

    final ref = await MessageAttachmentStore.instance.saveImage(
      fileId: 'qa-img-a',
      data: png,
      extension: 'png',
    );
    expect(ref, 'qa-img-a.png');

    final roundTrip = await MessageAttachmentStore.instance.readBytes(ref);
    expect(roundTrip, isNotNull);
    expect(roundTrip, equals(png));

    await MessageAttachmentStore.instance.deleteIfExists(ref);
    expect(await MessageAttachmentStore.instance.readBytes(ref), isNull);

    // Missing refs are safe no-ops.
    await MessageAttachmentStore.instance.deleteIfExists('qa-img-a.png');
    qaPass('attachment store save/read/delete round trip + mime sniff');
  });

  testWidgets('secure storage (API key) round trip through the real web plugin', (tester) async {
    await SecureStorageService.instance.saveApiKey('qa-sec-a', 'supp3r-s3cret');
    expect(await SecureStorageService.instance.getApiKey('qa-sec-a'), 'supp3r-s3cret');
    await SecureStorageService.instance.deleteApiKey('qa-sec-a');
    expect(await SecureStorageService.instance.getApiKey('qa-sec-a'), isNull);
    qaPass('secure storage API key round trip on web');
  });

  testWidgets('server profile + settings persist in web SharedPreferences', (tester) async {
    final db = LocalDatabase.instance;

    // App-mode + theme-mode persistence keys used by the Settings UI.
    await db.saveAppMode(AppMode.roleplay);
    expect((await db.loadAppMode()).name, 'roleplay');
    await db.saveAppThemeMode(AppThemeMode.light);
    expect((await db.loadAppThemeMode()).name, 'light');
    await db.saveAppThemeMode(AppThemeMode.dark);
    expect((await db.loadAppThemeMode()).name, 'dark');

    // Server profiles: prefs JSON + per-profile API key in secure storage.
    final profile = ServerProfile(id: 'qa-pro-1', name: 'QA Server', baseUrl: 'http://127.0.0.1:8090');
    await db.saveServerProfiles([profile]);
    await db.saveProfileApiKey(profile.id, 'qa-key');
    await db.setActiveProfileId(profile.id);

    expect(await db.getActiveProfileId(), 'qa-pro-1');
    final loaded = await db.loadServerProfiles();
    expect(loaded, hasLength(1));
    expect(loaded.first.baseUrl, 'http://127.0.0.1:8090');
    expect(loaded.first.apiKey, 'qa-key'); // resolved from secure storage

    await db.saveProfileApiKey(profile.id, null);
    expect((await db.loadServerProfiles()).first.apiKey, isNull);

    // Leave the app in default chat mode + dark theme so later suite runs in
    // the same browser profile boot into a known state.
    await db.saveAppMode(AppMode.assistant);
    await db.saveAppThemeMode(AppThemeMode.dark);
    qaPass('server profile + API key + app-mode/theme persisted on web');
  });

  testWidgets('conversation export -> import round trip against web sqlite', (tester) async {
    final db = LocalDatabase.instance;

    final thread = ChatThread(id: 'qa-thread-1', title: 'QA Round Trip');
    await db.insertThread(thread);
    final user = ChatMessage(
      id: 'qa-msg-1', threadId: thread.id, role: MessageRole.user,
      content: 'hello from the web',
    );
    final assistant = ChatMessage(
      id: 'qa-msg-2', threadId: thread.id, role: MessageRole.assistant,
      content: 'hello back', tokensPerSecond: 12.5, timeToFirstTokenMs: 321,
    );
    await db.insertMessage(user);
    await db.insertMessage(assistant);

    final stored = await db.getMessagesForThread(thread.id);
    expect(stored, hasLength(2));
    expect(stored.map((m) => m.content), containsAll(['hello from the web', 'hello back']));

    // Export the JSON, then import it back into a fresh thread id.
    final jsonStr = ConversationExport.toJson(thread, stored);
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final (importedThread, importedMessages, _) = ConversationExport.fromJson(decoded);

    expect(importedThread.title, 'QA Round Trip');
    expect(importedMessages, hasLength(2));
    expect(importedMessages.first.content, 'hello from the web');
    expect(importedMessages.last.totalTokens, isNull);

    // Persist the imported messages under a new thread -> proves the app's
    // conversation-import flow writes through the same web DB the UI reads.
    final newThread = ChatThread(id: 'qa-thread-imported', title: importedThread.title);
    await db.insertThread(newThread);
    for (final m in importedMessages) {
      await db.insertMessage(m.copyWith(threadId: newThread.id, id: 'imp-${m.id}'));
    }
    final importedBack = await db.getMessagesForThread(newThread.id);
    expect(importedBack, hasLength(2));
    expect(importedBack.first.content, 'hello from the web');
    expect(importedBack.last.content, 'hello back');

    // Cleanup so a re-run in the same profile stays deterministic.
    await db.deleteThread(thread.id);
    await db.deleteThread(newThread.id);
    qaPass('conversation export -> import round trip against web sqlite');
  });
}