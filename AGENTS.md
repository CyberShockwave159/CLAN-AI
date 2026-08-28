# clan_ai — Agent Notes

## Running the project
Recommended order: `pub get` → `analyze` → `test` → `run`.
```
flutter pub get            # fetch dependencies (required after git pull)
flutter analyze            # lint + typecheck (uses flutter_lints)
flutter test               # runs all 3 test files
flutter run -d <device>    # devices: linux, macos, windows, <android-id>
```

## Architecture (what's non-standard)
- **Hybrid Clean Architecture / MVVM** with `Provider` + `ChangeNotifier`.
- **No codegen.** All JSON serialization is manual `jsonEncode`/`jsonDecode` + `toMap()`/`fromMap()`.
- **No domain layer interfaces.** `lib/domain/models/` contains only `generation_params.dart`.
- **Dependency wiring** in `lib/main.dart` via constructor injection.
- **Three root providers:** `SettingsViewModel`, `ChatViewModel`, `RoleplayViewModel`. `CharacterRepository` also exposed via `Provider`.
- **App mode toggle:** `AppMode.assistant` vs `AppMode.roleplay` stored in SharedPreferences. `_HomeScreen` routes to `ChatScreen` or `RoleplayScreen` based on mode.

## Platform channels (mobile file save)
- `lib/core/utils/file_saver.dart` — Dart side. Sends base64-encoded content via `MethodChannel` on Android/iOS; falls back to `getApplicationDocumentsDirectory()` on desktop.
- `android/app/src/main/kotlin/.../MainActivity.kt` — Android SAF via `ACTION_CREATE_DOCUMENT`. Decodes base64, writes to user-selected URI. Uses `MethodCall` from `io.flutter.plugin.common`.
- `ios/Runner/AppDelegate.swift` — iOS `UIDocumentPickerViewController(forExporting:asCopy:)`. Writes content to caches dir, presents picker, moves file on confirm.

## Entry points
- `lib/main.dart` — bootstrap, Provider scope, SQLite FFI init (**once** at startup), HTTP client singleton (lifecycle via `WidgetsBindingObserver`), theme mode loading from prefs.
- `lib/ui/features/chat/view_models/chat_view_model.dart` — assistant chat state. `loadThreads()` calls `getAssistantThreads()` which filters out roleplay threads (`characterId != null`). Undo support for message deletion.
- `lib/ui/features/roleplay/view_models/roleplay_view_model.dart` — roleplay state with RAG. `_init()` calls `loadLastChat()` which uses `getThreads()` (all threads) then filters by `characterId`. Auto-loads last active thread by `characterId`.
- `lib/ui/features/settings/view_models/settings_view_model.dart` — profiles, templates, server config, health polling, appMode. 15s health polling timer.
- `lib/data/datasources/local_storage.dart` — SQLite schema v5 (threads + messages tables) + SharedPreferences singleton. Migration guards check column existence before `ALTER TABLE`.
- `lib/data/datasources/vector_store.dart` — SQLite vector store for roleplay character memory. Separate database file from main SQLite.
- `lib/data/datasources/llama_api_service.dart` — streams completions (OpenAI `/v1/chat/completions` or llama.cpp native `/completion`). Context-fit caps `contextSize` to model capacity minus reserved output tokens.
- `lib/core/network/sse_client.dart` — SSE parser for OpenAI delta and native `{content, stop}` formats. Produces `StreamChunk` + `StreamMetrics`.
- `lib/core/network/http_client.dart` — HTTP client with `_throwForStatusCode` mapping status codes to 3 exceptions: `ContextLimitExceededException` (400 + "context"/"exceed"), `ServerOOMException` (500 + "memory"/"slot"), or generic `AppException`.

## Key models
- **`ChatThread`** (lib/data/models/chat_thread.dart) — owns messages via FK; `systemPrompt` (per-thread override), `modelId`, `customParams` (JSON), `isPinned`, `branchFromThreadId`, `characterId` (null = assistant, set = roleplay).
- **`ChatMessage`** (lib/data/models/chat_message.dart) — `parentId`, `role` (system/user/assistant), `variantIndex`, `totalVariants`, `siblingIds` for branching. Status: `idle`/`sending`/`streaming`/`completed`/`error`. Metrics: `tokensPerSecond`, `totalTokens`, `timeToFirstTokenMs`, `generationTimeSec`. `isEdited` (bool), `updatedAt` (DateTime?) for tracking edits.
- **`ServerConfig`** (lib/data/models/server_config.dart) — `id`, `name`, `baseUrl`, `apiKey`, `selectedModel`, `protocol` (openAi | llamaNative), `defaultParams`, `healthStatus`, `latencyMs`, `systemPrompt` (default: 'You are a helpful, brilliant, and honest AI assistant.'), `confirmDeleteMessage`.
- **`ServerProfile`** (lib/data/models/server_profile.dart) — `name`, `baseUrl`, `apiKey`, `protocol`. Multiple profiles; switching changes connection details only. Config (system prompt, params, model) is global.
- **`GenerationParams`** (lib/domain/models/generation_params.dart) — temperature, topP, topK, minP, repeatPenalty, presencePenalty, frequencyPenalty, maxTokens (default 4096, **0 means unlimited**), contextSize (default 4096, clamped to [128, 1000000] during streaming), stopSequences, grammar.
- **`CharacterProfile`** (lib/data/models/character_profile.dart) — `name`, `personality`, `firstMessage`, `setting`, `userPersona`, `avatarData` (PNG/JPG bytes), `isFavorite`. Stored in SharedPreferences as JSON.
- **`AppMode`** (lib/data/models/app_mode.dart) — `assistant` or `roleplay`.
- **`ApiProtocol`** (lib/data/models/server_config.dart) — `openAi` or `llamaNative`.

## Streaming flow (critical for chat changes)
1. ViewModel creates user message → persists to SQLite → creates streaming placeholder.
2. Resolves effective system prompt (`thread.systemPrompt ?? config.systemPrompt`).
3. Repository → ApiService: context-fit caps `contextSize` (modelCapacity - maxTokens or 512 if unlimited). OpenAI POSTs `/v1/chat/completions`; llamaNative POSTs `/completion` with `### User`/`### Assistant` template.
4. `SseClient.parseStream()` handles both OpenAI delta and native `{content, stop}` formats.
5. Context limit errors → `ContextLimitExceededException`.
6. **UI throttling:** `Timer.periodic(Duration(milliseconds: 20))` buffers tokens to avoid frame drops. Timer looks up message by ID each tick to handle mutations.
7. Final metrics written to SQLite on completion.

## RAG flow (roleplay only)
- `RoleplayViewModel.startRoleplay()` creates thread with initial RAG context (empty memories on first session).
- `RoleplayViewModel.sendMessage()` → `RoleplayContextBuilder.build()` → embeds user input → searches top-3 similar memories via `VectorStore.searchSimilar(characterId: ...)`.
- Retrieved memories injected into thread's `systemPrompt` before sending to API.
- After stream completes: `_embedMessageAsync()` fires and-forget — embeds user+assistant pair into vector store.
- `RoleplayViewModel.deleteThread()` calls `_characterRepository.deleteEmbeddingsForMessages(characterId, messageIds)` — only deletes embeddings for messages in the deleted thread, **not** all character embeddings.
- `RoleplayViewModel.getCachedThreadsForCharacter(characterId)` uses a cached `Future` to avoid repeated `FutureBuilder` calls in the drawer.

## Gotchas
- **Conversation branching:** Regenerate/edit truncates at parent message, creates new sibling branches. Navigation uses `variantIndex` + `siblingIds`. `ChatViewModel.branchConversation()` creates a new `ChatThread` with copied messages and `branchFromThreadId` link.
- **System prompt resolution:** Thread-level `ChatThread.systemPrompt` overrides global `ServerConfig.systemPrompt`. In roleplay, RAG context builder overwrites it per-message.
- **Health polling:** 15s timer. Fallback chain: `/props` → `/v1/models`. `ServerRepository.fetchModels()` tries `/props` first (llama.cpp), then `/v1/models` (OpenAI), deduplicates by model id.
- **Android networking:** `127.0.0.1` is device loopback. Use `10.0.2.2` for emulator, LAN IP for physical devices.
- **SQLite FFI:** `sqfliteFfiInit()` called **once** in `main.dart` via `_initSqliteFfi()`. Guard: `if (_sqfliteFfiInitialized) return;` + platform check (Linux/Windows/macOS only). Both `LocalDatabase._initDB()` and `VectorStoreDatabase._initDB()` rely on this. Calling it again triggers "You are changing sqflite default factory" warning.
- **SQLite schema v5:** Migrations check column existence before `ALTER TABLE`. Delete `clan_ai.db` if schema errors occur.
- **Profile vs config:** Profile stores connection details (`baseUrl`, `apiKey`, `protocol`). System prompt, params, model selection are global config shared across profiles.
- **Thread isolation:** `ChatViewModel.loadThreads()` → `getAssistantThreads()` filters out `characterId != null`. `RoleplayViewModel.loadLastChat()` → `getThreads()` (all threads) then filters by `characterId`, falls back to all-threads for legacy migration. `RoleplayViewModel.startRoleplay()` calls `getThreadsForCharacter(characterId)` to reuse existing threads — never creates duplicates.
- **RAG isolation:** Embeddings stored with `character_id`. Queries: `WHERE character_id = ?` — no cross-character leakage.
- **Hash embedding:** Pure Dart 256-dim vectors via char trigrams in `EmbeddingService`. <5ms, <1KB per vector. No ML dependencies.
- **Default API protocol:** `ApiProtocol.openAi` (in `ServerConfig` constructor).
- **Legacy thread fallback:** `RoleplayViewModel.loadLastChat()` tries `characterId != null` first, falls back to all threads (legacy migration for threads before character_id was added).
- **SharedPreferences CRUD race conditions:** `insertCharacter`, `updateCharacter`, `deleteCharacter`, `createProfile`, `updateProfile`, `deleteProfile`, `addTemplate`, `updateTemplate`, `deleteTemplate` all use `Mutex` to serialize read-modify-write sequences.
- **RAG delete scope:** Deleting a thread only deletes embeddings for messages in that thread, not all character embeddings. Use `VectorStore.deleteEmbeddingsForMessages()` or `CharacterRepository.deleteEmbeddingsForMessages()`.
- **Undo support:** `ChatViewModel` supports 5-second undo for user message deletions via `undoDelete()` and `canUndo` flag.
- **Theme toggle:** `main.dart` loads theme mode from SharedPreferences via `LocalDatabase.instance.loadThemeMode()`. Defaults to dark.
- **Prompt length limits:** `RoleplayPromptFormatter` caps personality (2000), setting (1000), userPersona (1000), memory (1000 per memory, max 3 memories) to prevent context overflow.
- **Export behavior:** Export is only available via context menus in the chat drawer and character drawer. The header bar export popup has been removed. `FileSaver.saveFile()` opens native save dialogs on mobile (SAF on Android, UIDocumentPicker on iOS); on desktop writes to the app documents directory.
- **Roleplay system prompt:** In roleplay mode the system prompt is fully managed by `RoleplayContextBuilder` which injects RAG context per-message. The System Prompt Customization section in Settings is hidden when `settingsVM.appMode == AppMode.roleplay` (line 622 of settings_screen.dart).
- **Roleplay identity guard:** `RoleplayPromptFormatter.buildSystemPrompt()` appends "Never speak, think, act, or write dialogue for the user — only write for your own character." to every roleplay prompt. This is the sole location for roleplay behavioral instructions.
- **Edit assistant messages (roleplay):** `MessageBubble` shows an edit icon (pencil) only for the **last** assistant message when `onEditAssistant` is provided (roleplay screen). `RoleplayViewModel.editAssistantMessage()` validates the message is completed and is the last in the list, then persists the edit to DB and re-embeds into RAG. The `isLastMessage` bool must be passed from the parent widget (computed as `index == messages.length - 1`).
- **Character deletion fix:** When deleting a character in `roleplay_drawer.dart`, the callback must `await` the delete, call `roleplayVM.deleteCharacter(id)` to clear the thread cache, then `Navigator.of(ctx).pop()` and `setState(() {})` to trigger a drawer rebuild. Without `setState`, the `FutureBuilder` snapshot is stale.

## Platform-specific
- Desktop SQLite uses `sqflite_common_ffi`. Mobile uses native sqflite.
- Default theme: **dark mode** (loadable from prefs, default `ThemeMode.dark` in `main.dart`).
- **Dart SDK:** `^3.13.0` — do not downgrade.
- HTTP timeouts: connect 10s, receive 60s.
- `analysis_options.yaml` excludes: build, android, ios, web, windows, macos, linux.
- **Accessibility:** Message bubble action toolbar icons use `Semantics` labels. Text uses `MediaQuery.textScaler.scale()`.
- **Bubble width:** Capped at 600px via `LayoutBuilder` to prevent overflow on tablets.

## Testing
3 test files. No ViewModel, Repository, or API service tests:
- `test/domain/generation_params_test.dart` — `GenerationParams` OpenAI & native payload serialization, plus `TextSanitizer` markdown/code/LaTeX segment parsing (7 segments: markdown, inlineMath, markdown, blockMath, markdown, codeBlock, markdown).
- `test/network/sse_client_test.dart` — `SseClient.parseStream()` for OpenAI deltas, llama.cpp native chunks, ping comments, multi-line data.
- `test/widget_test.dart` — renders `ConnectionBadge` with status + latency. Calls `sqfliteFfiInit()` in `setUpAll` (safe in test isolate).

Run one: `flutter test test/domain/generation_params_test.dart`.

## Code structure
```
lib/
├── main.dart                          # Bootstrap, Provider wiring, FFI init, HTTP client, theme loading
├── core/
│   ├── constants/                     # AppTheme, API endpoints
│   ├── errors/                        # AppException hierarchy (6 classes)
│   ├── network/                       # ApiHttpClient, SseClient
│   └── utils/                         # LatencyMeter, Mutex, RoleplayContextBuilder, RoleplayPromptFormatter, TextSanitizer, HashEmbedding, FileSaver, EmbeddingService
├── data/
│   ├── datasources/                   # LlamaApiService, LocalDatabase, VectorStore, EmbeddingService
│   ├── models/                        # All domain models (ChatThread, ChatMessage, ServerConfig, etc.)
│   └── repositories/                  # ChatRepository, ServerRepository, CharacterRepository, SystemPromptTemplatesRepository
├── domain/
│   └── models/                        # GenerationParams (only domain-layer model)
└── ui/
    ├── features/
    │   ├── chat/
    │   │   ├── view_models/           # ChatViewModel
    │   │   ├── views/                 # ChatScreen, MessageBubble, PromptInputBar
    │   │   └── widgets/               # MarkdownBodyView, CodeBlockView, MathView, TokenSpeedBadge
    │   ├── drawer/
    │   │   └── views/                 # ChatDrawer
    │   ├── roleplay/
    │   │   ├── view_models/           # RoleplayViewModel
    │   │   ├── views/                 # RoleplayScreen, RoleplayDrawer
    │   │   └── widgets/               # CharacterCreationWizard
    │   └── settings/
    │       ├── view_models/           # SettingsViewModel
    │       ├── views/                 # SettingsScreen, ParameterTuningSheet
    │       └── view_models/           # (shared with views)
    └── shared/                        # AppHeader, ConnectionBadge
```
