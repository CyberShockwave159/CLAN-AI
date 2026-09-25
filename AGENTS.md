# clan_ai — Agent Notes

Flutter (Dart SDK ^3.13) cross-platform llama.cpp client — OpenAI-compatible endpoints (llama.cpp llama-server and any OpenAI-compatible backend). Platforms: Linux/macOS/Windows/Android/iOS/Web(PWA — Beta). Deep architecture: `ARCHITECTURE.md`. Features/setup/installer docs: `README.md`. This file only covers what an agent would otherwise get wrong.

## Commands
```
flutter pub get          # required after every git pull
flutter analyze          # lint + typecheck (flutter_lints)
flutter test             # 35 test files, 602 tests, all hermetic
flutter test test/domain/generation_params_test.dart   # single file
flutter test test/integration/   # suite subset
flutter run -d linux     # linux | macos | windows | <android-id> | chrome
```
Windows packaging: `.github/workflows/build-windows.yml` is the *only* Windows workflow — it builds on pushes/PRs to `main` and publishes a GitHub Release on `v*` tags (build → MSIX via `dart run msix:create` → NSIS). The NSIS script must **embed** the MSIX with `File`; a runtime `CopyFiles` produces a tiny installer with no payload that fails on user machines. `version` in `pubspec.yaml` is the single source of truth for the MSIX version (`msix_version` intentionally omitted); `msix_config.yaml` is **not** read by the msix tool (it only reads `pubspec.yaml`). `scripts/build-windows-installer.{bat,sh}` produce `dist/` locally.

## Architecture (what's non-standard)
- **Hybrid MVVM with `Provider` + `ChangeNotifier`; no codegen.** All JSON serialization is manual `toMap()`/`fromMap()`. No domain-layer interfaces — `lib/domain/models/` has only `generation_params.dart` (payloads, RAG params, TextSanitizer).
- **Wiring in `lib/main.dart`**: 4 `ChangeNotifierProvider`s (Settings, Chat, Roleplay, PersonaTemplate) + `Provider<CharacterRepository>`, all constructor-injected. The network stack is a single shared `ApiHttpClient` → `LatencyMeter` → `LlamaApiService` → repos; required deps are **positional initializing formals** (`ChatRepository(this._apiService, {localDb})`, `ChatViewModel(this._chatRepository)`, etc.) with **no `??` fallbacks** — don't reintroduce them, or connection pooling/latency tracking silently forks. `localDb` may still fall back to the `LocalDatabase.instance` singleton. SQLite FFI initialized **once** (`_initSqliteFfi()`, desktop only — calling `sqfliteFfiInit()` again warns "changing sqflite default factory").
- **Shared logic lives in mixins/widgets under `lib/ui/shared/`**, not in the VMs: `stream_mutation_mixin.dart` (streaming, 20ms UI throttle, 5s undo, stopGeneration, switchVariant — used by BOTH Chat and Roleplay VMs), `auto_scroll_mixin.dart` (opt-out auto-scroll), `parameter_sheet_opener.dart` (accepts `isRoleplay`), `drawer_export_menu.dart`, `desktop_keyboard_shortcuts.dart`. Any streaming/undo/branching change goes in the mixin, not the VMs.
- **Thread isolation**: `ChatThread.characterId == null` = assistant, set = roleplay. `getAssistantThreads()` filters out roleplay threads; Roleplay VMs filter in and reuse existing threads per character (`getThreadsForCharacter`) — never create duplicates.
- **Profile vs config split**: `ServerProfile` = connection details (`baseUrl`, `apiKey`, per-profile `reasoning`). `ServerConfig` = global (system prompt, params, model). `syncConfigFromProfile`/`syncProfileFromConfig` propagate connection fields both ways.
- **Settings sections** in `lib/ui/features/settings/views/sections/` are shared across modes. Model dropdown lives in the Profile section; System Prompt section is hidden in roleplay mode (Persona Templates shown instead); Theme section always last.
- **Assistant content rendering** (`DynamicMarkdownView` + `TextSanitizer`): hyperlinks open in the platform browser (new tab on PWA); raster image URLs render inline via `MarkdownImageView` (cached, tap → lightbox) — this includes `data:image/…` URLs (A-PROX `inline_data_url` artifacts), decoded via `Image.memory`; fenced code blocks show only the language in the header (first line stays in the body). Generated **files** render as distinct `ArtifactFileCard` objects at the end of the message: `TextSanitizer.extractFileRefs` lifts non-image artifact-extension URLs (`TextSanitizer.artifactExtensions`, excludes code blocks and `![…]` images, deduped) and merges the stored A-PROX `file_url` artifact (deduped by filename); tapping a card saves/exports via `FileSaver.saveBytes` (stored bytes read from the store, content URLs fetched on demand). Image/file artifact downloads all flow through `MessageAttachmentStore.fetchBytes`, which also decodes base64/percent-encoded `data:` URLs without a network call — so A-PROX `inline_data_url` works even when `/images`/`/files` is unreachable. Only assistant messages render file objects.

## Storage & schema
- `clan_ai.db` schema **v14** (`lib/data/datasources/local_storage.dart`): threads (custom_params, branch_from_thread_id, character_id), messages (is_edited, rag_memory_*, reasoning_content, variant_index/total_variants/sibling_ids, image_path, file_path, file_name, file_mime), characters, persona_templates. Message image attachments are stored as files on disk via `MessageAttachmentStore` with only the absolute file path in `messages.image_path`; the OpenAI payload embeds them as base64 `image_url` content parts. Character avatars are stored inline as `avatar_data` BLOBs. Migration guards check `PRAGMA table_info` before every `ALTER TABLE`. Schema errors → delete the `.db` files.
- **FK enforcement is on** (`PRAGMA foreign_keys = ON` in `onConfigure`) — messages→threads `ON DELETE CASCADE` is live; `deleteThread` also deletes messages explicitly. Thread search is a single assistant-scoped SQL query (`LocalDatabase.searchThreads`, LIKE wildcards escaped) — don't rebuild the old per-thread N+1 loop.
- `clan_ai_vectors.db` schema **v2** (`vector_store.dart`): `thread_id` added v1→v2. Separate DB from main SQLite. (Its self-referential FK is intentionally not enforced — don't add `PRAGMA foreign_keys` there.)
- SharedPreferences: server profiles, active profile, active config, theme mode/colors, app mode, last roleplay thread, system prompt templates. API keys: `flutter_secure_storage` (Keychain/KeyStore/Secret Service).
- **`Mutex` serializes read-modify-write only in `ServerRepository` and `SystemPromptTemplatesRepository`** (both SharedPreferences-backed) — not in SQLite-backed repos.
- Avatars are stored inline as BLOBs in `characters.avatar_data` — there is no file-based avatar storage. Message image attachments *and* A-PROX file artifacts both use on-disk storage via `MessageAttachmentStore` (only the absolute path / opaque ref lives in SQLite).

## Streaming flow (critical for chat changes)
1. VM persists user message → creates streaming placeholder → resolves effective system prompt: `thread.systemPrompt ?? config.systemPrompt`; roleplay uses RAG builder per-message; character `systemPrompt` overrides everything (`{{original}}` prefix prepends the standard prompt); `postHistoryInstructions` appended.
2. `LlamaApiService` context-fits: caps `contextSize` to model capacity minus `reservedOutputTokensDefault` (512) when maxTokens is 0. `serverConfig.reasoning` is passed into params.
3. `SseClient.parseStream()` handles OpenAI delta chunks; `filterReasoning()` extracts reasoning fields (`reasoning`/`reasoning_content`/`thought`) and inline tags (```xml, `<thought>`, `<reasoning>`).
4. Throttle timer (20ms) flushes content + reasoning buffers; looks up the message by ID each tick (handles mutations). Final metrics + `reasoningContent` saved to SQLite on completion.

## Branching / variants
Regenerate/edit truncates at the parent, creates sibling variants via `parentId`/`variantIndex`/`siblingIds`. `getMessagesForThread()` dedupes to the latest variant per group (prevents duplicates after reload); `getAllMessagesForThread()` bypasses dedup for variant navigation. Only messages with same `parentId` and `role == assistant` count as variants. Navigation: sort siblings by `variantIndex`, index into sorted list, next = `variantIndex + 1`. Branch threads link via `branchFromThreadId`.

## RAG (roleplay only)
Pure-Dart 256-dim trigram hash embeddings (`HashEmbedding`, FNV-1a, no ML deps). Stored per `character_id` + `thread_id`; `searchSimilar(threadIds:)` scopes to thread lineage (`getThreadLineageIds()` resolves ancestor chains). Embedding happens fire-and-forget in the streaming `onComplete` hook (roleplay only). Regenerate deletes the old embedding before streaming; `editAssistantMessage()` re-embeds. `CharacterMemoriesDialog` lists/prunes embeddings per character.

## Roleplay gotchas
- First assistant message (character's greeting) has regenerate disabled until the user has replied.
- Alternate greetings show as chips above input only while all messages are assistant; selecting one **always creates a new thread** (`startRoleplayWithGreeting`).
- Editing assistant messages only allowed for the **last** message — requires `onEditAssistant` + `isLastMessage` (`index == messages.length - 1`) passed from the parent.
- `RoleplayPromptFormatter.buildSystemPrompt()` appends the identity guard ("Never speak, think, act, or write dialogue for the user…") to every prompt — sole location for roleplay behavior rules.
- Character delete in roleplay drawer: `await` delete → `roleplayVM.deleteCharacter(id)` (clears thread cache) → pop → `setState`, or the `FutureBuilder` snapshot stays stale.
- Async handlers (delete/import/nav): always check `context.mounted` after `await` before using `ScaffoldMessenger`/`Navigator`.

## Imports & exports
- SillyTavern import: `file_picker` with `allowedExtensions: ['json']` → `silly_tavern_card_parser.dart` (`chara_card_v2`, replaces `{{char}}`/`{{user}}`) → save → auto-open `CharacterEditDialog` (proper StatefulWidget; takes `CharacterRepository` as param; returns `Future<CharacterProfile>` via `.then((v) => v ?? character)`) → start roleplay.
- Conversation import: `ConversationExport.fromJson()` creates threads in both modes (`importThread`). Export only via drawer context menus (header popup removed); character export bundles RAG memories.
- `FileSaver`: mobile uses platform channels (Android SAF, iOS UIDocumentPicker); desktop writes to app documents dir.

## Platform / env gotchas
- Android networking: `127.0.0.1` is device loopback — use `10.0.2.2` (emulator) or LAN IP (physical device).
- Native SQLite is bundled automatically: `sqflite_common_ffi` resolves `sqlite3` **3.x**, whose Dart build hook emits `libsqlite3` as a native asset per target (see `.dart_tool/flutter_build/*/native_assets.json`). Do **not** add `sqlite3_flutter_libs` — `0.6.0+eol` is an empty stub and `0.5.x` is the legacy sqlite3 2.x path.
- HTTP timeouts 10s connect / 60s receive: the connect phase is bounded by `HttpClient.connectionTimeout` (real TCP/TLS timeout). The `.timeout()` guards cover receive: GET health/model calls use the 10s connect budget for the whole call; `post` and the streaming `postStream` header-wait use the 60s receive budget. `send()` resolves on response *headers*, which on a busy/slow server includes slot queueing + prefill — a 10s header bound made remote servers with a healthy link falsely report "connection" failures, so keep the receive budget there. `throwForStatusCode` extracts messages from `error`/`message`/`detail`/nested shapes. Error mapping: 400 + "context"/"exceed" → `ContextLimitExceededException`; 500 + "memory"/"slot" → `ServerOOMException`; else `AppException`.
- Health polling every 15s, fallback `/health` → `/props` → `/v1/models`, model list deduped by id.
- Keyboard shortcuts (`DesktopKeyboardShortcuts`, uses `KeyboardListener`): Ctrl+N new chat, Ctrl+K thread search (`SearchDelegate` over `searchThreads()`), Ctrl+, settings, Esc stop, Ctrl+/ or F1 help. The widget sits *above* `MaterialApp`, so it receives the app's `navigatorKey` via constructor (no static global) to reach a context below the Navigator for `showDialog`/`showSearch`.
- Theme: dark default; `AppThemeMode` dark/light/custom with `CustomThemeColors` presets (warm/cool/pastel); lookup via `context.clanX` ThemeExtension.
- `analysis_options.yaml` excludes platform/build dirs. Do not downgrade Dart SDK below ^3.13.

## Testing
35 test files, 602 tests — all pass; fully hermetic (**no real SQLite or network**). Fakes in `test/helpers/`: `FakeChatRepository`, `FakeCharacterRepository` (thread-scoped embeddings), `FakeVectorStore`, `FakeServerRepository`, `FakePersonaTemplateRepository`, `FakeSystemPromptTemplatesRepository`, `test_model_factories`, `mock_path_provider`. `FakeChatRepository`/`FakeServerRepository` **`implements`** their concrete repo (not `extends`) so they don't inherit the real constructor — don't switch them back, the real constructors now require an injected `LlamaApiService`. ViewModels expose private state via setters for injection. Suites: `domain/`, `network/`, `utils/` (incl. vector_store, ST parser, conversation_export, text_sanitizer), `mixin/`, `repository/`, `view_model/`, `widget/` (message_bubble, artifact_file_card, markdown_body_view, reasoning, character_edit_dialog, alternate_greeting_selector), `integration/`, `integration_test/` (web QA journey, storage QA, smoke). `flutter analyze` is clean (0 issues).

## Async / Background Completion (A-PROX integration)
- **Async endpoints**: CLAN-AI uses A-PROX's `/v1/chat/completions/async` (submit), `/{id}/stream` (resume), `/{id}/result` (fetch), `/{id}/status` (poll), `DELETE /{id}` (cancel).
- **Persistence**: `pending_requests` table (schema v16) tracks request ID, thread, assistant message, payload, status (pending/streaming/completed/failed), TTL (1h default).
- **Resume flow**: `doStreamResponse` in `StreamMutationMixin` checks for existing `PendingRequest` by `assistantMessageId` before submitting. If found and not terminal → resumes via `streamAsyncCompletion`. If terminal → submits fresh.
- **Submit flow**: New request → `submitAsyncCompletion` → saves `PendingRequest` (status=streaming) → streams via `streamAsyncCompletion`.
- **App lifecycle**: `WidgetsBindingObserver.didChangeAppLifecycleState` in `_ClanAiAppState` scans incomplete `PendingRequest`s on `resumed`/`inactive` and reconnects.
- **Conflict resolution**: Thread edit/delete during background processing → `cancelAsyncRequest` + submit new (goes to end of queue).
- **Server requirements**: A-PROX `async` config enabled, `async_requests` table, queue worker running.
- **Tests**: `_GatedChatRepository` overrides `streamAsyncCompletion` for mid-stream state observation; `FakeChatRepository` implements all async CRUD methods.