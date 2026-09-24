# Changelog

## [v1.2.0]

### ✨ New Features

**Web (PWA) Support — Beta**

Complete portability refactor enabling a Progressive Web App build of CLAN AI. The app runs in the browser with full SQLite (WASM/IndexedDB), SSE token streaming via `fetch` + `ReadableStream`, and IndexedDB-backed image attachments — all byte-identical to native behavior.

- **Phase 0** validation spike: confirmed web compilation (dart2js), WASM sqlite persistence (IndexedDB, SharedWorker, cross-tab), incremental SSE streaming with abort, and `flutter_secure_storage` web compat
- **Phase 1** portability refactor — zero native behavioral change:
  - Web SQLite via `sqflite_common_ffi_web` (WASM, IndexedDB-backed, SharedWorker cross-tab) with a separate attachment BLOB database
  - Web HTTP transport: `web.window.fetch` + `ReadableStreamDefaultReader` feeding `SseClient.parseStream` unchanged; `AbortController` for stop-generation abort
  - `AttachmentImage` widget: `Image.file` on native, `Image.memory` (IndexedDB-backed) on web
  - Browser download for file export via `Blob` + object URL; `file_picker` bytes for web import
  - Platform guards updated to `defaultTargetPlatform` + `kIsWeb`; `dart:io` imports removed from web-impacted files
- **Phase 2** PWA layer: manifest/icons (dark `#0F1117`, `any` + `maskable`), PWA meta tags, custom service worker (precaches app shell, stale-while-revalidate runtime cache, network-first navigations, version-keyed), CI workflow (`build-web.yml` with optional manual Pages deploy)
- **Phase 3** QA: all 6 checkpoint journey tests pass against both fixture (deterministic SSE) and a real llama.cpp server (Qwen3.6-35B) in headless Chrome; 4/4 storage suite pass; PWA probes confirm CORS + auth, shared worker/IDB across tabs, offline shell reload, and key restore; `flutter analyze` 0 issues; 505 hermetic tests green; both `flutter build web --release` and `flutter build linux --release` pass
- **Findings:** (1) stop-generation doesn't abort the underlying fetch during server silence; (2) no model dropdown in Settings (intentional, removed); (3) boot auto-selects first persisted thread
- **Firefox support:** PWA works in Firefox — service workers, IndexedDB, WASM, and `fetch`/`ReadableStream` all supported. Install via browser's "Add CLAN AI" menu entry.

## [Unreleased]

### 🏗 Hardening & Infrastructure

**Dependency Injection**
- The shared network stack (`ApiHttpClient` → `LatencyMeter` → `LlamaApiService` → repositories) is created once in `main.dart` and injected through required positional constructor arguments; `??` fallbacks were removed so connection pooling and latency tracking can no longer be silently forked
- App `navigatorKey` is created in `main()` and injected into `DesktopKeyboardShortcuts` / `ClanAiApp`, replacing the mutable static global

**Database**
- Foreign-key enforcement enabled via `PRAGMA foreign_keys = ON` (messages→threads `ON DELETE CASCADE` is now live)
- Thread search is a single assistant-scoped SQL `LIKE` query (`LocalDatabase.searchThreads`) instead of a per-thread N+1 loop
- Schema v12 adds the variant columns; schema v13 adds the `image_path` column for image attachments; schema v14 adds `file_path`/`file_name`/`file_mime` for downloaded file artifacts; migrations guard with `PRAGMA table_info`

**HTTP**
- Real TCP/TLS connect timeout via `HttpClient.connectionTimeout`; resilient error-body reading with bounded extraction from `error`/`message`/`detail` shapes

**Windows Packaging**
- The NSIS installer now embeds the MSIX payload at build time (`File`), fixing installers that shipped as a small stub without the application
- `version` in `pubspec.yaml` is the single source of truth for the MSIX version (`msix_version` removed)
- Removed the unused `msix_config.yaml` (the msix tool reads `msix_config` from `pubspec.yaml` only) and the dead CI certificate-copy step
- Consolidated to one Windows workflow (`build-windows.yml`); removed the duplicate tag-triggered `release-windows.yml`

**Platform Defaults**
- Android first-run profile defaults to `http://10.0.2.2:8080` (emulator host alias) instead of loopback

### ✨ New Features

**Server Offline Warning Banner**
- Chat screen and roleplay screen display a red warning banner when server health status is `offline`
- Banner reads "Server unreachable. Verify your endpoint in Settings." with an "Open Settings" button that navigates to Settings screen
- Uses `context.watch<SettingsViewModel>()` for reactive updates — banner appears/disappears automatically as health status changes

**Keyboard Shortcuts Help Dialog**
- Press `Ctrl+/` or `F1` to open a dialog listing all keyboard shortcuts
- Dialog shows `New Chat`, `Search Threads`, `Open Settings`, `Keyboard Shortcuts Help`, and `Stop Generation` with platform-aware labels (`Cmd` on macOS, `Ctrl` on other platforms)
- Replaces the previous help button with keyboard shortcut trigger

**Avatar Storage**
- Character avatars are stored inline as BLOBs in the `characters.avatar_data` column (SQLite) — there is no file-based avatar storage (the earlier file-backed `avatar_storage_service.dart` was removed in a repo-wide dead-code sweep)

**Image Attachments**
- Attach one image per user message (chat and roleplay modes) via the attach button in the prompt input bar, with an inline preview chip before sending
- Tap an attached image in a message bubble to open a full-screen lightbox viewer
- `lib/core/utils/message_attachment_store.dart` — images are stored as files on disk with only the absolute path in `messages.image_path`; files are cleaned up automatically when their message or thread is deleted
- The OpenAI payload embeds the attachment as a base64 `image_url` content part, so it works with any OpenAI-compatible vision-capable backend (e.g. llama.cpp llama-server with a multimodal model)
- Magic-byte MIME sniffing (`mimeTypeFromBytes`) detects the true image format (PNG/JPEG/GIF/WebP) even when the file extension lies
- **File & Image Artifacts (A-PROX `/flags`)** — streamed `delta.image_url` / `delta.file_url` (and `message.image_url`/`message.file_url` on non-streaming responses) are parsed in `SseClient._processDataBlock` (object `{url,name,mime}` and bare-string forms) and forwarded through `filterReasoning` reconstructed chunks. The shared `StreamMutationMixin` (chat + roleplay) downloads each artifact bytes once into `MessageAttachmentStore` and persists the path + original name + MIME to SQLite (schema v14 `file_path`/`file_name`/`file_mime` columns, migration v13→v14). Assistant images render inline; files render as distinct, tappable document objects (see **Generated Files as Save-able Objects** below).

**Clickable Hyperlinks in Assistant Responses**
- Hyperlinks the model emits are now tappable on every platform, including the web/PWA build (`url_launcher ^6.3.1`)
- `http`/`https`/`mailto`/`tel` links open in the platform browser (a new tab on web); unsupported schemes are ignored
- Wired through `DynamicMarkdownView.onTapLink`, so both explicit `[label](url)` links and autolinked bare URLs are covered

**Native Inline Rendering of Generated Images**
- Raster image URLs the model puts in its response (markdown links or bare `http(s)` URLs ending in `.png`/`.jpeg`/`.jpg`/`.gif`/`.webp`/`.bmp`/`.avif`) now render as actual images in the chat log instead of as links; tap to open a full-screen, zoomable lightbox
- `TextSanitizer.embedImageLinks` rewrites image URLs in markdown segments (code-block and math content untouched); `MarkdownImageView` fetches them with an HTTP client (cached per URL) and falls back to the plain link on failure or the debug network layer

**Inline `data:` URL Artifacts (A-PROX `inline_data_url`)**
- A-PROX can emit `image_url` / `file_url` as base64 `data:` URLs (`[image_generation]/[file_generation].inline_data_url`) instead of served `http(s)://…/images|files/…` URLs — reachable even when `/images`/`/files` is firewalled or the server is behind no reverse proxy
- `MessageAttachmentStore.fetchBytes` now decodes base64 and percent-encoded `data:` URLs client-side (no network call), so image artifacts (`delta.image_url`), file artifacts (`delta.file_url`), and caption-lifted downloads all work with inline payloads; `fileNameFromUrl` returns null for `data:` URLs and the stored image extension is derived from the declared MIME (`data:image/png` → `.png`)
- `TextSanitizer.embedImageLinks` / `extractFirstImageUrl` promote `data:image/…` links, markdown images, and bare URLs into inline-rendered images (decoded via `Image.memory`) and native streaming attachment cards — non-image `data:` URLs (`data:text/…`) are left as plain text

**Code Block Rendering Fix**
- The first line of code stays inside the code body instead of being misread as the block's language; the header shows only the real language, ellipsized when very wide
- `TextSanitizer.parseSegments` now keeps the opening fence + language line in the code-block segment payload (the renderer strips it), and the header language label is wrapped in `Expanded` so a pathological long label can no longer push the Copy button off-screen

**Generated Files as Save-able Objects**
- Every file an assistant produces now appears as a distinct document object at the **end** of the response: `TextSanitizer.extractFileRefs` lifts non-image artifact file URLs (extensions in `TextSanitizer.artifactExtensions` — `.txt`, `.md`, `.json`, `.csv`, `.pdf`, `.py`, `.zip`, ...) out of the markdown (code blocks and inline images excluded, deduplicated), merges them with the stored A-PROX `file_url` artifact, and prunes duplicates by filename
- Each file renders as an `ArtifactFileCard` with a type-specific icon (`.txt` → generic text document, `.json` → data object, `.csv` → spreadsheet, `.pdf` → PDF, code → code, ...), the filename, MIME, and a save affordance
- Tapping a card saves/exports the file through the same `FileSaver` path used for chat export — stored A-PROX bytes are read from the attachment store; content-derived URLs are downloaded on demand (nothing persisted) — then confirms with a "Saved to <path>" snackbar
- Only assistant messages render file objects; user messages and plain web-page links are left untouched (those stay clickable hyperlinks)

**Thread Menus in Drawers**
- The "Show menu" (⋮) button now appears on every chat/thread row in both the assistant-mode drawer and the roleplay drawer, not just the active conversation
- Export/rename/delete menu actions operate on the tapped thread directly — exporting a non-active thread loads that thread's messages from the database instead of exporting the active conversation (it no longer needs to be selected first)

**PWA Update Flow**
- The web build now prompts users running an old build: `PwaUpdateChecker` polls the deployed `version.json` every 5 minutes and shows a "A new version of CLAN AI is available" snackbar with a **Reload** action as soon as a newer release is detected (web-only; immediate baseline on boot, offline boot never warns spuriously)
- Service worker (`clan_ai_sw.js`) v2: navigation and asset fetches use `cache: 'no-store'`, so the browser HTTP cache / host `Cache-Control` can never serve a stale shell; successful navigations re-key the version cache and sweep stale `clan-ai-v*` caches even when the SW script ships unchanged
- **Fix (v3): returning PWA users were being served the previous release's bundle.** The old SW opened a cache named literally `"null"` whenever it addressed the cache before resolving `version.json` (worker restarts reset the module-level cache name), and that cache — which held stale `main.dart.js`/`flutter_bootstrap.js` copies from earlier visits — was never swept because the sweep only dropped `clan-ai-v*` keys. On the first navigation after a deploy, the still-unawaited sweep raced the new page's asset requests and stale-while-revalidate served the old bundle, so fresh `index.html` booted the old UI. Now: caches are only ever opened under a resolved version name (no nameless cache is fabricated), the navigation handler awaits the re-key + sweep **before** handing the fresh page to the browser, the legacy `"null"` cache is deleted during re-keying, and the deployed version is adopted eagerly on cold start so the first asset requests of a returning session already target the current (empty) version cache
- Added a bundled `Caddyfile` (no-cache for `index.html`/`clan_ai_sw.js`/`version.json`/`manifest.json`, `max-age=86400` for hashed assets) and documented the update flow in the README
- `pubspec.yaml` version bumped to `1.3.0+1`

### 🔧 Changes

**Windows CI/CD Pipeline**
- Release workflow triggers on semantic version tags (`v*`) instead of pushes to `main`/`master`
- NSIS installed via Chocolatey (`choco install nsis`) in CI before build step
- NSIS resolved dynamically via `Get-Command makensis` with fallback to default path
- Build fails if NSIS installer is not produced (removed silent skip)
- Release title uses `${{ github.ref_name }}` directly from tag

**Desktop Keyboard Shortcuts Migration**
- `DesktopKeyboardShortcuts` migrated from deprecated `RawKeyboardListener` to `KeyboardListener` with `HardwareKeyboard.instance`
- `onKey` callback replaced with `onKeyEvent` (`KeyDownEvent` check)
- Modifier key detection now uses `HardwareKeyboard.instance.isControlPressed` / `isMetaPressed` instead of event parameters

**Local Database Cleanup**
- Removed `LocalDatabase.saveCharacters()` — character persistence now exclusively handled by `CharacterRepository` (SQLite)
- Fixed `loadServerProfiles()` — properly hydrates API keys from secure storage using `copyWith(apiKey: secureKey)` in `Future.wait`

**Stream Mutation Mixin**
- `doStopGeneration()` now always clears `isGenerating` flag (removed `&& currentCancelToken != null` guard)

**Android Network Security**
- Base config permits cleartext HTTP for all hosts (`cleartextTrafficPermitted="true"`), required because LAN LLM server IPs are user-supplied and Android's network security config cannot express private IP ranges
- Removed the redundant per-domain cleartext entries and the redundant `android:usesCleartextTraffic` manifest attribute (the network security config takes precedence on API 24+)

**Roleplay Screen Spacing**
- Reduced top margin from 28px to 12px on "Start your roleplay..." empty state text

**Chat Repository**
- `createThread()` now accepts optional `branchFromThreadId` parameter for conversation branching links

**OpenAI-Only Protocol**
- Removed the "OpenAI Compatible vs llama.cpp Native" protocol choice — all requests now use the OpenAI-compatible `/v1/chat/completions` endpoint exclusively
- Deleted the `ApiProtocol` enum and `protocol` fields on `ServerProfile`/`ServerConfig`, the native `/completion` transport (`_streamLlamaNative`, `toLlamaNativePayload`), the native endpoints (`/completion`, `/slots`, `/detokenize`, `/tokenize`), and the native SSE `{content, stop}` parse branch
- Existing saved profiles/configs with `"protocol":"llamaNative"` degrade silently to OpenAI — no migration required
- `/health` → `/props` → `/v1/models` connectivity probing retained (detection only, not message transport); images previously required the OpenAI endpoint, which is now unconditional

### 🧹 Test Cleanups
- Removed unused imports across test files (`model_roundtrips_test.dart`, `stream_mutation_mixin_test.dart`, `http_client_test.dart`, `roleplay_context_builder_test.dart`, `vector_store_test.dart`, `persona_template_view_model_test.dart`)
- Added unique IDs to messages in `chat_repository_test.dart` to avoid ID collisions
- Added `SharedPreferences.setMockInitialValues({})` and delays in `settings_view_model_test.dart`
- Added `mock_path_provider.dart` to all tests using `path_provider` platform channel
- Updated `stream_mutation_mixin_test.dart` — "no-op when no cancel token" test now expects `isGenerating` to be false
- Removed protocol/native tests after the OpenAI-only switch: native `/completion` service and SSE parsing tests, native payload serialization, protocol round-trip tests, and `protocol` args across test factories and `settings_view_model_test.dart`

## [v1.0.1] - SillyTavern Character Import

### ✨ New Features

**Reasoning/Thinking Block Support**
- Settings toggle "Show Reasoning" in Safety & Convenience section to request reasoning/thinking content from models
- API payload includes `"reasoning": true` and `"include_reasoning": true` for OpenAI protocol
- SSE parser extracts reasoning from multiple field names: `delta.reasoning`, `delta.reasoning_content`, `delta.thought`, `reasoning`, `reasoning_content`, `thought`
- Inline thinking tag processing handles ````xml`, `<thought>`, `<reasoning>` tags in both OpenAI and native formats
- `MessageBubble` renders collapsible "Thinking" block with expand/collapse animation (psychology icon + `AnimatedContainer`)
- `reasoningContent` field stored in `ChatMessage` model and SQLite `reasoning_content` column (schema v7)
- Works with OpenAI o1/o3, DeepSeek R1, Qwen, and other reasoning-capable models; requires llama.cpp v1.7.7+ for native reasoning support
- `_pendingReasoningBuffer` in `StreamMutationMixin` accumulates reasoning tokens alongside content tokens

**Secure API Key Storage**
- `flutter_secure_storage` integration for storing API keys in iOS Keychain / Android KeyStore / Linux Secret Service
- `lib/data/datasources/secure_storage_service.dart` — encapsulates `FlutterSecureStorage` with `saveApiKey`, `getApiKey`, `deleteApiKey` methods
- API keys removed from plaintext SharedPreferences; `ServerRepository` uses secure storage for profile keys via `saveProfileApiKey` / `getProfileApiKey`

**Mobile File Save (Platform Channels)**
- Conversations export opens native save dialogs on mobile (Android SAF, iOS UIDocumentPicker) so users choose the destination folder
- `lib/core/utils/file_saver.dart` — Dart-side platform channel wrapper; falls back to app documents directory on desktop
- `MainActivity.kt` — Android `ACTION_CREATE_DOCUMENT` handler; decodes base64, writes to user-selected URI
- `AppDelegate.swift` — iOS `UIDocumentPickerViewController(forExporting:asCopy:)` handler; writes to caches, presents picker, moves file on confirm

**AI Roleplay Mode**
- Toggle between assistant and roleplay modes in Settings
- Roleplay mode mirrors assistant mode UI/UX — same layout, same drawer, same chat bubbles
- Character creation wizard (4 steps: name/personality/first message, setting/world, user persona + persona template, advanced prompt settings)
- Optional character avatar upload (defaults to initials in colored circle)
- Per-character isolated chat sessions with no bleed between characters
- Auto-resumes last active roleplay session when switching back from assistant mode
- Assistant mode threads and roleplay mode sessions are strictly separated (thread `characterId` filter)

**Client-Side RAG Memory System**
- Pure Dart feature hashing embeddings (256-dim, character trigrams) — zero ML dependencies
- SQLite-backed vector store with cosine similarity search
- Per-character memory isolation: embeddings stored with `character_id` filter, no cross-character leakage
- Roleplay prompt formatter injects top-3 relevant memories into system prompt before each generation
- Non-blocking embedding save after each message completion (fire-and-forget)

**Server Connection Profiles**
- Added multi-profile server configuration for switching between networks (e.g., local LAN vs cellular/public IP)
- Profiles store `baseUrl`, `apiKey`, and `protocol` — model, hyperparameters, and system prompts remain global
- Profile selector with dropdown and clickable chip list in Settings
- Long-press a profile chip to edit; × to delete
- Tap a chip or use the dropdown to switch profiles (auto-tests the connection)
- Existing config automatically migrates to a "Default" profile on first launch

**Persistent System Prompt Templates**
- Created, edited, and deleted from Settings; stored locally and survive app restarts
- Click a template chip to apply it to the current thread and global default
- Built-in presets (Default, Code Architect, Concise Expert, Creative Writer) load as default templates
- Conversations remember their system prompt independently — switching threads loads each thread's saved prompt

**SillyTavern `.json` Character Card Import**
- Import button in roleplay drawer sidebar opens file picker filtered to `.json` files
- `lib/core/utils/silly_tavern_card_parser.dart` — Parses SillyTavern `chara_card_v2` (spec_version 2.0) JSON files
- Maps `.data.description` → personality, `.data.first_mes` → firstMessage, `.data.scenario` → setting
- `{{char}}` → replaced with character name; `{{user}}` → replaced with user persona (or "User" fallback)
- Full content preserved — personality truncation limits removed
- Auto-edit dialog (`CharacterEditDialog`) opens after import so users can review/adjust fields (including avatar selection) before starting roleplay
- Import flow: pick JSON → parse → save → auto-open edit dialog → start roleplay
- `_showEditDialog` returns `Future<CharacterProfile>`; passes `CharacterRepository` as parameter to avoid context issues

### 🔧 Changes

**Generation Parameters**
- Default `maxTokens` increased from 2048 to 4096
- `maxTokens = 0` now means unlimited (no cap on generation length)
- `contextSize` max increased to 1,000,000 tokens (was 32,768)
- Max Generation Tokens UI changed to a text input + slider (range 0–8192)
- Context Window UI changed to a text input with suffix "tokens"
- Best-effort context fit: when a model reports its context length, the app automatically caps `contextSize` to fit (reserves tokens for output)

**Export UX**
- Removed export popup from header bar; export is now only available via context menus in the chat drawer and character drawer
- `ChatViewModel.exportThread()` and `RoleplayViewModel.exportThread()` now delegate to `FileSaver.saveFile()` instead of writing to a temp directory

**Roleplay Settings**
- System Prompt Customization section in Settings is hidden when `appMode == AppMode.roleplay` (line 622 of settings_screen.dart)
- Roleplay system prompt is fully managed by the RAG context builder

### 🏗 Architecture

**SQLite Schema v8 Migration**
- Migrated Character and Persona Template storage from SharedPreferences to SQLite (`characters` and `persona_templates` tables)
- One-time migration via `_migratePreferencesToSqlite()` reads legacy SharedPreferences data on first schema v8 launch
- `CharacterRepository` and `PersonaTemplateRepository` use dedicated SQLite repositories with mutex-protected CRUD
- `SecureStorageService` now hydrates API keys on profile load via `copyWith(apiKey: secureKey)` in `loadServerProfiles()`
- Android network security config updated to permit cleartext HTTP on base-config for LAN servers (previously limited to 3 hardcoded IPs)
- Desktop keyboard shortcuts migrated from deprecated `RawKeyboardListener` to `KeyboardListener` with `HardwareKeyboard.instance`

**RAG Memory Indicators**
- `ragMemoryCount` and `ragMemoryContents` fields added to `ChatMessage` model for tracking injected memories
- `MessageBubble` displays a memory chip tap to reveal actual memory content injected into system prompt
- `CharacterMemoriesDialog` widget for per-character memory viewer and pruner (accessible via character popup menu)

**New Files**
- `lib/data/models/app_mode.dart` — AppMode enum (assistant/roleplay)
- `lib/data/models/character_profile.dart` — Character model with optional avatar
- `lib/data/models/system_prompt_template.dart` — Template model for saved system prompts
- `lib/data/models/server_profile.dart` — Profile model storing baseUrl, apiKey, protocol
- `lib/data/repositories/character_repository.dart` — CRUD for characters (SQLite `characters` table)
- `lib/data/repositories/persona_template_repository.dart` — CRUD for persona templates (SQLite `persona_templates` table)
- `lib/data/repositories/system_prompt_templates_repository.dart` — CRUD for templates (SharedPreferences)
- `lib/core/utils/hash_embedding.dart` — Pure Dart 256-dim feature hashing via char trigrams
- `lib/core/utils/file_saver.dart` — Platform channel file saver (SAF on Android, UIDocumentPicker on iOS)
- `lib/data/datasources/vector_store.dart` — SQLite vector store with cosine similarity
- `lib/core/utils/roleplay_prompt_formatter.dart` — System prompt with RAG memories
- `lib/data/datasources/secure_storage_service.dart` — Secure API key storage via `flutter_secure_storage`
- `lib/core/utils/roleplay_context_builder.dart` — RAG pipeline orchestration
- `lib/ui/features/roleplay/views/roleplay_screen.dart` — Roleplay chat screen
- `lib/ui/features/roleplay/views/roleplay_drawer.dart` — Character list sidebar
- `lib/ui/features/roleplay/widgets/character_creation_wizard.dart` — 3-step character creation
- `lib/ui/features/roleplay/view_models/roleplay_view_model.dart` — Roleplay state with RAG integration

**Modified Files**
- `pubspec.yaml` — Added `image_picker` dependency
- `lib/main.dart` — Added `_initSqliteFfi()` (called once), 3 root providers, mode-based home route
- `lib/data/models/chat_thread.dart` — Added `characterId` field
- `lib/data/models/server_config.dart` — Added `appMode`, `reasoning` fields; secure API key integration
- `lib/data/datasources/local_storage.dart` — Added appMode, characters, persona templates, vector store persistence; schema v3→v4→v5→v6→v7→v8
- `lib/ui/features/settings/view_models/settings_view_model.dart` — Added appMode state, save/load last roleplay thread ID
- `lib/ui/features/settings/views/settings_screen.dart` — Added "Roleplay Mode" toggle; hidden system prompt section in roleplay; rewrote with Server Profiles and saved templates chips
- `lib/ui/features/chat/view_models/chat_view_model.dart` — Filters out roleplay threads; uses FileSaver for export
- `lib/ui/features/roleplay/view_models/roleplay_view_model.dart` — New roleplay viewmodel with RAG; uses FileSaver for export
- `lib/ui/shared/app_header.dart` — Removed header export popup
- `lib/ui/features/drawer/views/chat_drawer.dart` — Export context menu item
- `lib/ui/features/roleplay/views/roleplay_drawer.dart` — Export context menu item
- `lib/data/repositories/server_repository.dart` — Added profile CRUD
- `lib/data/repositories/chat_repository.dart` — Added `modelContextLength` param
- `lib/data/models/generation_params.dart` — Updated defaults, 0=unlimited maxTokens
- `lib/data/datasources/llama_api_service.dart` — Added context fit logic
- `lib/ui/features/settings/views/parameter_tuning_sheet.dart` — New input UI for max tokens and context window
- `lib/ui/features/chat/views/chat_screen.dart` — Passes model context length to all streaming operations
- `lib/ui/features/drawer/views/chat_drawer.dart` — New chats inherit current global system prompt

### 🐛 Bug Fixes
- Fixed `DropdownButtonFormField` deprecated `value` parameter (changed to `initialValue`)
- Fixed `tryRead` non-existent method (changed to `read`)
- Fixed type cast error in edit dialog return type (`as Future<CharacterProfile>` → `.then((value) => value ?? character)`)
- Fixed `ScaffoldMessenger.of(context)` "deactivated widget ancestor" errors by adding `context.mounted` guards
