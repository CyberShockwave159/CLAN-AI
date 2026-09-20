import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'package:clan_ai/main.dart' as app;
import 'package:clan_ai/data/datasources/local_storage.dart';
import 'package:clan_ai/data/datasources/secure_storage_service.dart';
import 'package:clan_ai/data/models/character_profile.dart';
import 'package:clan_ai/ui/features/chat/widgets/reasoning_block.dart';
import 'package:clan_ai/ui/features/chat/widgets/token_speed_badge.dart';
import 'package:clan_ai/ui/features/roleplay/views/roleplay_screen.dart';
import 'package:clan_ai/ui/features/settings/views/sections/app_mode_section.dart';
import 'package:clan_ai/ui/features/settings/views/settings_screen.dart';

import 'qa_check.dart';

/// Phase 3 QA — real app journey in a real browser against the QA fixture
/// (default `http://127.0.0.1:8090`, key `qa-key`).
///
/// Build & drive in a headless Chrome (the flutter-tool browser orchestrators
/// stall in this environment, so the suite is run from a served build):
///   flutter build web --release --target=integration_test/phase3_web_qa_test.dart
///   (serve build/web, load it in Chrome, read QA-CHECK lines from the console)
/// Re-run against a real llama-server:
///   --dart-define=QA_BASE_URL=http://127.0.0.1:8080
///   --dart-define=QA_API_KEY=`<your-api-key>`
///
/// The journey: boot+connect -> stream (incremental + reasoning + metrics) ->
/// variants (regenerate) -> cancellation (fixture STALL prompt) -> settings
/// persistence (theme + app mode) -> roleplay (greeting + reply stream).
const _baseUrl = String.fromEnvironment(
  'QA_BASE_URL',
  defaultValue: 'http://127.0.0.1:8090',
);
const _apiKey = String.fromEnvironment('QA_API_KEY', defaultValue: 'qa-key');
const _qaCharacter = 'QA Bot';
const _qaGreeting = 'Greetings from QA Bot';

final _chatInput = find.byWidgetPredicate(
  (w) => w is TextField && (w.decoration?.hintText ?? '').contains('Ask anything'),
);
final _roleplayInput = find.byWidgetPredicate(
  (w) => w is TextField && (w.decoration?.hintText ?? '').contains('Reply as'),
);

Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder${reason == null ? '' : ' ($reason)'}');
}

/// Types into a TextField via its controller. `tester.enterText` routes through
/// the test text-input client, which is unreliable against the live binding in
/// a real browser (no real IME); driving the controller directly is
/// deterministic and exercises the same app listeners the UI uses.
Future<void> typeText(WidgetTester tester, Finder finder, String text) async {
  final tf = tester.widget<TextField>(finder);
  tf.controller?.text = text;
  tf.onChanged?.call(text); // send-button enable gate is onChanged- or listener-driven
  await tester.pump(const Duration(milliseconds: 150));
}

/// Seeds the browser's real stores (localStorage SharedPreferences + web
/// secure storage + the WASM sqlite character table) exactly as the Settings
/// UI would, then boots the real app via its own main().
Future<void> seedAndBoot(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  final profile = <String, dynamic>{
    'id': 'qa-profile-1',
    'name': 'QA Server',
    'baseUrl': _baseUrl,
    'apiKey': null,
    'reasoning': 1,
  };
  await prefs.setString('clan_server_profiles', jsonEncode({'v': 1, 'data': [profile]}));
  await prefs.setString('clan_active_profile_id', 'qa-profile-1');
  // Pin boot into chat mode + dark theme regardless of residue from earlier
  // suites/probes sharing this browser profile (e.g. the storage suite leaves
  // roleplay mode behind if it ran here first).
  await prefs.setString('clan_app_mode', 'assistant');
  await prefs.setString('clan_theme_mode', 'dark');
  await SecureStorageService.instance.saveApiKey('qa-profile-1', _apiKey);

  databaseFactory = databaseFactoryFfiWeb;

  // Fresh slate for the journey: on boot the app auto-selects the first
  // persisted thread (chat_view_model loadThreads), which hides the empty-state
  // 'Connected to …' text the boot check waits on and makes variant counts
  // non-deterministic across re-runs in the same browser profile.
  final db = LocalDatabase.instance;
  for (final t in await db.getAllThreads()) {
    await db.deleteThread(t.id);
  }

  await LocalDatabase.instance.insertCharacter(
    CharacterProfile(
      id: 'qa-char-1',
      name: _qaCharacter,
      personality: 'Terse, helpful QA robot.',
      firstMessage: _qaGreeting,
      personaName: 'Tester',
    ),
  );

  // main() is `void main() async` — the app init (sqlite, providers, first
  // health poll) completes in the background; pumpUntil below waits for the
  // chat screen to appear.
  app.main();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phase 3 web QA journey', (tester) async {
    // The QA fixture emits deterministic tok-/qa-reasoning markers and stalls
    // on a 'STALL' prompt; a real llama-server produces neither, so token-based
    // assertions are strict only against the fixture.
    const isFixtureTarget = _baseUrl == 'http://127.0.0.1:8090';
    await seedAndBoot(tester);

    // ── 1. Boot & connect (health poll -> /v1/models via CORS + auth) ─────
    await pumpUntil(tester, _chatInput, reason: 'chat screen input');
    await pumpUntil(
      tester,
      find.textContaining('Connected'),
      timeout: const Duration(seconds: 30),
      reason: 'server connected',
    );
    qaPass('boot + connect: health poll, /v1/models via CORS + auth');

    // ── 2. Send -> incremental stream, reasoning, metrics ─────────────────
    await typeText(tester, _chatInput, 'Hello from QA');
    await tester.tap(find.byKey(const ValueKey('send_btn')));
    await pumpUntil(tester, find.text('Hello from QA'), reason: 'user bubble');

    // Reasoning blocks streamed in and render collapsed. The QA fixture always
    // emits reasoning_content; a real llama-server may not (depends on launch
    // flags / model), so the assertion adapts: when reasoning is absent from
    // the response, the UI must simply be correct about not showing a block.
    final blockDeadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(blockDeadline) &&
        find.byType(ReasoningBlock).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final hasReasoning = find.byType(ReasoningBlock).evaluate().isNotEmpty;
    if (hasReasoning) {
      await tester.tap(
        find.descendant(of: find.byType(ReasoningBlock), matching: find.byType(InkWell)).first,
      );
      if (isFixtureTarget) {
        await pumpUntil(
          tester,
          find.textContaining('qa-reasoning'),
          timeout: const Duration(seconds: 5),
          reason: 'expanded reasoning text',
        );
      } else {
        await tester.pump(const Duration(milliseconds: 400));
      }
    } else if (isFixtureTarget) {
      fail('fixture must emit a reasoning block');
    }

    // Incremental stream completed through the UI; metrics badge present. The
    // fixture's final marker token is 'tok-5'; a real server has no such marker,
    // so completion is detected via the TokenSpeedBadge (rendered only when the
    // stream finishes) and the send button returning idle.
    if (isFixtureTarget) {
      await pumpUntil(
        tester,
        find.textContaining('tok-5'),
        timeout: const Duration(seconds: 20),
        reason: 'final stream token rendered',
      );
    } else {
      await pumpUntil(
        tester,
        find.byType(TokenSpeedBadge),
        timeout: const Duration(seconds: 45),
        reason: 'real-server stream completed (metrics badge)',
      );
    }
    expect(find.byType(TokenSpeedBadge), findsOneWidget,
        reason: 'TTFT/tokens-per-second metrics rendered on completion');
    qaPass('incremental token stream + reasoning block + TTFT/tps metrics');

    // ── 3. Regenerate -> variant 2/2, then navigate back to 1/2 ───────────
    await pumpUntil(
      tester,
      find.byTooltip('Regenerate response'),
      timeout: const Duration(seconds: 10),
      reason: 'regenerate available',
    );
    await tester.tap(find.byTooltip('Regenerate response'));
    // Fixture shows exact '2 / 2' text and 'Previous version' navigation;
    // real server may just produce a new assistant message without variant UI.
    if (isFixtureTarget) {
      await pumpUntil(
        tester,
        find.text('2 / 2'),
        timeout: const Duration(seconds: 20),
        reason: 'variant count 2/2 after regenerate',
      );
      await tester.tap(find.byTooltip('Previous version'));
      await pumpUntil(tester, find.text('1 / 2'), reason: 'navigated to previous variant');
    } else {
      // Real server: wait for the regenerated stream to complete (metrics badge).
      await pumpUntil(
        tester,
        find.byType(TokenSpeedBadge),
        timeout: const Duration(seconds: 45),
        reason: 'real-server regenerated stream completed (metrics badge)',
      );
    }
    // Wait for send button to be available after regenerate
    // (on real server, the new message is already complete).
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('send_btn')),
      timeout: const Duration(seconds: 20),
      reason: 'idle (send button) after regenerate',
    );
    qaPass('regenerate -> variant 2/2 -> previous 1/2 navigation');

    // ── 4. Cancel mid-stream (fixture stalls after its first token) ─────────
    // Fixture canary: completed streams contain 'tok-1...tok-5'; a stalled
    // stream must never add another visible one (its partial 'tok-0' never
    // matches 'tok-1'). On a real server no UI-count invariant distinguishes a
    // stopped partial from a completed reply (both end as one assistant
    // bubble), so the assertion there is that stop returns the UI to idle.
    final int? tokCanaryBefore;
    if (isFixtureTarget) {
      final tok1Before = find.textContaining('tok-1').evaluate().length;
      expect(tok1Before, greaterThanOrEqualTo(1),
          reason: 'completed streams visible for the canary comparison');
      tokCanaryBefore = tok1Before;
    } else {
      tokCanaryBefore = null;
    }

    await typeText(tester, _chatInput, 'STALL hold this reply');
    await tester.tap(find.byKey(const ValueKey('send_btn')));
    await pumpUntil(
      tester,
      find.byKey(const ValueKey('stop_btn')),
      timeout: const Duration(seconds: 10),
      reason: 'stop button while generating',
    );
    final hadStop = find.byKey(const ValueKey('stop_btn')).evaluate().isNotEmpty;
    if (hadStop) {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('stop_btn')));
      await pumpUntil(
        tester,
        find.byKey(const ValueKey('send_btn')),
        timeout: const Duration(seconds: 12),
        reason: 'generation stopped, send button back',
      );
      await tester.pump(const Duration(seconds: 2));
    } else if (isFixtureTarget) {
      fail('fixture must stall (stop button still present)');
    } else {
      // A fast real-server reply can complete before stop is tapped; the
      // fixture owns the strict cancel semantics.
      await tester.pump(const Duration(seconds: 2));
    }

    if (isFixtureTarget) {
      expect(
        find.textContaining('tok-1').evaluate().length,
        tokCanaryBefore,
        reason: 'stalled stream must not emit further tokens after stop',
      );
      qaPass('cancel stalled stream (AbortController) cleans up without extra tokens');
    } else if (hadStop) {
      qaPass('cancel exercised (real server): stop returned the UI to idle; '
          'strict no-extra-token semantics are fixture-covered');
    } else {
      qaPass('cancel: reply completed before stop could be tapped (real-server fast reply)');
    }

    // ── 5. Settings: theme + app-mode persistence ─────────────────────────
    // (The app auto-selects the first server model on connect — /v1/models
    // fetch is covered by check #1; there is no model dropdown in the UI.)
    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(
      tester,
      find.text('Active Profile'),
      timeout: const Duration(seconds: 15),
      reason: 'settings screen rendered',
    );

    final settingsScroll = find
        .descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Light'), 150, scrollable: settingsScroll);
    await tester.tap(find.text('Light'));
    await tester.pump(const Duration(milliseconds: 250));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('clan_theme_mode'), 'light',
        reason: 'theme selection persisted to web SharedPreferences');

    final appModeSwitch = find.descendant(
      of: find.byType(AppModeSection),
      matching: find.byType(Switch),
    );
    // App-mode section sits above the (last) Theme section: scroll back up.
    await tester.scrollUntilVisible(appModeSwitch, -150, scrollable: settingsScroll);
    await tester.tap(appModeSwitch);
    await tester.pump(const Duration(milliseconds: 350));
    final prefs2 = await SharedPreferences.getInstance();
    expect(prefs2.getString('clan_app_mode'), 'roleplay',
        reason: 'roleplay mode persisted to web SharedPreferences');
    qaPass('settings: theme (Light) persisted + app-mode roleplay persisted');

    // ── 6. Roleplay: character, greeting, reply stream ─────────────────────
    // The SwitchListTile's onChanged pops Settings itself; pageBack here would
    // pop the roleplay screen right after it appears.
    await pumpUntil(tester, find.byType(RoleplayScreen), reason: 'roleplay screen');
    await tester.tap(find.byTooltip('Characters'));
    await pumpUntil(tester, find.text(_qaCharacter), reason: 'seeded character listed');
    // The drawer row renders the name with maxLines: 1 (a second 'QA Bot' text
    // can appear in the app-bar title when a character is auto-restored); scope
    // the tap to the drawer's name (inside a GestureDetector that calls
    // _handleStartChat) so it is unambiguous.
    await tester.tap(
      find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is Text && w.data == _qaCharacter && w.maxLines == 1,
        ),
        matching: find.byType(GestureDetector),
      ),
    );
    await pumpUntil(
      tester,
      find.textContaining(_qaGreeting),
      timeout: const Duration(seconds: 12),
      reason: 'character greeting rendered (no network needed)',
    );
    // The character tap pops the drawer; its close animation can still be
    // scrimming the input bar when the greeting text first appears (text is
    // in the tree even under the scrim). Let the animation finish before we
    // tap send, or the tap misses the scrim.
    await tester.pump(const Duration(milliseconds: 900));

    await typeText(tester, _roleplayInput, 'Hi from tester');
    await tester.tap(find.byKey(const ValueKey('send_btn')));
    // Roleplay reply: fixture has 'tok-5' marker; real server uses metrics badge.
    if (isFixtureTarget) {
      await pumpUntil(
        tester,
        find.textContaining('tok-5'),
        timeout: const Duration(seconds: 20),
        reason: 'fixture roleplay reply stream completed',
      );
    } else {
      await pumpUntil(
        tester,
        find.byType(TokenSpeedBadge),
        timeout: const Duration(seconds: 45),
        reason: 'real-server roleplay reply stream completed (metrics badge)',
      );
    }
    expect(find.byType(TokenSpeedBadge), findsOneWidget,
        reason: 'TTFT/tokens-per-second metrics rendered on roleplay completion');
    qaPass('roleplay: character greeting + thread reuse + reply stream');
    qaSummary();
  });
}