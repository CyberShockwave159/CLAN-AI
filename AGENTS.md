# clan_ai — Agent Notes

## Running the project
Recommended order: `pub get` → `analyze` → `test` → `run`.
```
flutter pub get            # fetch dependencies (required after git pull)
flutter analyze            # lint + typecheck (uses flutter_lints)
flutter test               # runs all 4 test files (4 widget/domain + SSE)
flutter run -d <device>    # devices: linux, macos, windows, <android-id>
```

## Architecture (what's non-standard)
- **Hybrid Clean Architecture / MVVM** with `Provider` + `ChangeNotifier`.
- **No codegen.** All JSON serialization is manual `jsonEncode`/`jsonDecode` + `toMap()`/`fromMap()`.
- **No domain layer interfaces.** `lib/domain/models/` contains only `generation_params.dart`.
- **Dependency wiring** in `lib/main.dart` via constructor injection.
- **Four root providers:** `SettingsViewModel`, `ChatViewModel`, `RoleplayViewModel`, `PersonaTemplateViewModel`. `CharacterRepository` also exposed via `Provider`.
- **App mode toggle:** `AppMode.assistant` vs `AppMode.roleplay` stored in SharedPreferences. `_HomeScreen` routes to `ChatScreen` or `RoleplayScreen` based on mode.

## Platform channels (mobile file save)
- `lib/core/utils/file_saver.dart` — Dart side. Sends base64-encoded content via `MethodChannel` on Android/iOS; falls back to `getApplicationDocumentsDirectory()` on desktop.
- `android/app/src/main/kotlin/.../MainActivity.kt` — Android SAF via `ACTION_CREATE_DOCUMENT`. Decodes base64, writes to user-selected URI. Uses `MethodCall` from `io.flutter.plugin.common`.
- `ios/Runner/AppDelegate.swift` — iOS `UIDocumentPickerViewController(forExporting:asCopy:)`. Writes content to caches dir, presents picker, moves file on confirm.
- **file_picker** — Used for JSON file selection in SillyTavern import (`type: FileType.custom, allowedExtensions: ['json']`).

## Entry points
- `lib/main.dart` — bootstrap, Provider scope (4 providers + CharacterRepository), SQLite FFI init (**once** at startup), HTTP client singleton (lifecycle via `WidgetsBindingObserver`), theme mode loading from prefs.
- `lib/ui/features/chat/view_models/chat_view_model.dart` — assistant chat state. `loadThreads()` calls `getAssistantThreads()` which filters out roleplay threads (`characterId != null`). Undo support for message deletion.
- `lib/ui/features/roleplay/view_models/roleplay_view_model.dart` — roleplay state with RAG. `_init()` calls `loadLastChat()` which uses `getThreads()` (all threads) then filters by `characterId`. Auto-loads last active thread by `characterId`. Supports `startRoleplay()` and `startRoleplayWithGreeting()` for alternate greetings.
- `lib/ui/features/settings/view_models/settings_view_model.dart` — profiles, templates, server config, health polling, appMode. 15s health polling timer.
- `lib/ui/features/roleplay/view_models/persona_template_view_model.dart` — manages persona templates CRUD. Exposes templates list and create/update/delete methods.
- `lib/data/datasources/local_storage.dart` — SQLite schema v5 (threads + messages tables) + SharedPreferences singleton. Migration guards check column existence before `ALTER TABLE`. Also manages persona templates storage via `_keyPersonaTemplates`.
- `lib/data/datasources/vector_store.dart` — SQLite vector store for roleplay character memory. Separate database file from main SQLite.
- `lib/data/datasources/llama_api_service.dart` — streams completions (OpenAI `/v1/chat/completions` or llama.cpp native `/completion`). Context-fit caps `contextSize` to model capacity minus reserved output tokens.
- `lib/core/network/sse_client.dart` — SSE parser for OpenAI delta and native `{content, stop}` formats. Produces `StreamChunk` + `StreamMetrics`.
- `lib/core/network/http_client.dart` — HTTP client with `_throwForStatusCode` mapping status codes to 3 exceptions: `ContextLimitExceededException` (400 + "context"/"exceed"), `ServerOOMException` (500 + "memory"/"slot"), or generic `AppException`.
- `lib/core/utils/silly_tavern_card_parser.dart` — Parses SillyTavern `chara_card_v2` (spec_version 2.0) JSON into `ParsedCharacterCard` DTO. Maps `.data.description` → personality, `.data.first_mes` → firstMessage, `.data.scenario` → setting. Replaces `{{char}}` with character name and `{{user}}` with user persona (or "User" as fallback) in personality, firstMessage, setting, userPersona, systemPrompt, and postHistoryInstructions. Truncates personality to 4000 chars. Also extracts `.data.system_prompt`, `.data.post_history_instructions`, `.data.alternate_greetings[]`.
- `lib/core/utils/st_avatar_downloader.dart` — Downloads avatar bytes from URL with 30s timeout. Validates image format (PNG/JPEG/WebP) via magic bytes.
- `lib/ui/features/roleplay/widgets/silly_tavern_import_dialog.dart` — Preview/edit dialog for imported characters. Shows all parsed fields (including system prompt, post history, alternate greetings) with text editors and persona template selector dropdown.
- `lib/ui/features/roleplay/widgets/character_edit_dialog.dart` — Proper StatefulWidget for editing existing characters. Uses `context.watch<PersonaTemplateViewModel>()` for template selection. `_applyTemplate()` wraps state updates in `setState` to ensure TextField updates. Returns `Future<CharacterProfile>` via `.then()`.
- `lib/ui/features/roleplay/views/roleplay_drawer.dart` — Contains `_showEditDialog(CharacterProfile, CharacterRepository)` which delegates to `CharacterEditDialog`. Import flow: pick JSON → parse → save → auto-open edit dialog → start roleplay with updated character.
- `lib/ui/features/roleplay/widgets/character_creation_wizard.dart` — 4-step wizard with persona template selector, system prompt override, post history instructions, and alternate greetings input.
- `lib/ui/features/roleplay/widgets/persona_template_dialog.dart` — Create/edit/delete persona templates dialog.
- `lib/ui/features/roleplay/widgets/alternate_greeting_selector.dart` — Displays alternate greetings as selectable chips above the chat input.
- `lib/core/utils/roleplay_context_builder.dart` — Orchestrates RAG: embeds user input → searches memories → builds system prompt. Accepts `characterSystemPrompt` and `postHistoryInstructions` for per-character prompt overrides.
- `lib/core/utils/roleplay_prompt_formatter.dart` — Compiles roleplay system prompt. Handles character system prompt override with `{{original}}` prefix support. Appends post history instructions after standard prompt.

## Key models
- **`ChatThread`** (lib/data/models/chat_thread.dart) — owns messages via FK; `systemPrompt` (per-thread override), `modelId`, `customParams` (JSON), `isPinned`, `branchFromThreadId`, `characterId` (null = assistant, set = roleplay).
- **`ChatMessage`** (lib/data/models/chat_message.dart) — `parentId`, `role` (system/user/assistant), `variantIndex`, `totalVariants`, `siblingIds` for branching. Status: `idle`/`sending`/`streaming`/`completed`/`error`. Metrics: `tokensPerSecond`, `totalTokens`, `timeToFirstTokenMs`, `generationTimeSec`. `isEdited` (bool), `updatedAt` (DateTime?) for tracking edits.
- **`ServerConfig`** (lib/data/models/server_config.dart) — `id`, `name`, `baseUrl`, `apiKey`, `selectedModel`, `protocol` (openAi | llamaNative), `defaultParams`, `healthStatus`, `latencyMs`, `systemPrompt` (default: 'You are a helpful, brilliant, and honest AI assistant.'), `confirmDeleteMessage`.
- **`ServerProfile`** (lib/data/models/server_profile.dart) — `name`, `baseUrl`, `apiKey`, `protocol`. Multiple profiles; switching changes connection details only. Config (system prompt, params, model) is global.
- **`GenerationParams`** (lib/domain/models/generation_params.dart) — temperature, topP, topK, minP, repeatPenalty, presencePenalty, frequencyPenalty, maxTokens (default 4096, **0 means unlimited**), contextSize (default 4096, clamped to [128, 1000000] during streaming), stopSequences, grammar.
- **`CharacterProfile`** (lib/data/models/character_profile.dart) — `name`, `personality`, `firstMessage`, `setting`, `userPersona`, `avatarData` (PNG/JPG bytes), `isFavorite`, `systemPrompt` (per-character system prompt override with `{{original}}` prefix support), `postHistoryInstructions` (appended after AI responses), `alternateGreetings` (list of alternative opening messages). Stored in SharedPreferences as JSON.
- **`PersonaTemplate`** (lib/data/models/persona_template.dart) — Global reusable user persona. `id`, `name`, `personaText`, `createdAt`, `updatedAt`. Stored in SharedPreferences as JSON list.
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
- **System prompt override**: If character has `systemPrompt`, `RoleplayContextBuilder` uses it to replace the standard prompt. `{{original}}` prefix inserts standard prompt before custom text. `postHistoryInstructions` are appended after the full prompt.

## Gotchas
- **Conversation branching:** Regenerate/edit truncates at parent message, creates new sibling branches. Navigation uses `variantIndex` + `siblingIds`. `ChatViewModel.branchConversation()` creates a new `ChatThread` with copied messages and `branchFromThreadId` link.
- **System prompt resolution:** Thread-level `ChatThread.systemPrompt` overrides global `ServerConfig.systemPrompt`. In roleplay, RAG context builder overwrites it per-message. Character-level `CharacterProfile.systemPrompt` takes priority — if set, it replaces the entire prompt; `{{original}}` prefix inserts standard prompt before custom text.
- **Health polling:** 15s timer. Fallback chain: `/props` → `/v1/models`. `ServerRepository.fetchModels()` tries `/props` first (llama.cpp), then `/v1/models` (OpenAI), deduplicates by model id.
- **Android networking:** `127.0.0.1` is device loopback. Use `10.0.2.2` for emulator, LAN IP for physical devices.
- **SQLite FFI:** `sqfliteFfiInit()` called **once** in `main.dart` via `_initSqliteFfi()`. Guard: `if (_sqfliteFfiInitialized) return;` + platform check (Linux/Windows/macOS only). Both `LocalDatabase._initDB()` and `VectorStoreDatabase._initDB()` rely on this. Calling it again triggers "You are changing sqflite default factory" warning.
- **SQLite schema v5:** Migrations check column existence before `ALTER TABLE`. Delete `clan_ai.db` if schema errors occur.
- **Profile vs config:** Profile stores connection details (`baseUrl`, `apiKey`, `protocol`). System prompt, params, model selection are global config shared across profiles.
- **Thread isolation:** `ChatViewModel.loadThreads()` → `getAssistantThreads()` filters out `characterId != null`. `RoleplayViewModel.loadLastChat()` → `getThreads()` (all threads) then filters by `characterId`, falls back to all-threads for legacy migration. `RoleplayViewModel.startRoleplay()` calls `getThreadsForCharacter(characterId)` to reuse existing threads — never creates duplicates.
- **RAG isolation:** Embeddings stored with `character_id`. Queries: `WHERE character_id = ?` — no cross-character leakage.
- **Hash embedding:** Pure Dart 256-dim vectors via char trigrams in `EmbeddingService`. <5ms, <1KB per vector. No ML dependencies.
- **Default API protocol:** `ApiProtocol.openAi` (in `ServerConfig` constructor).
- **SharedPreferences CRUD race conditions:** `insertCharacter`/`updateCharacter`/`deleteCharacter` in `LocalDatabase`, `createProfile`/`updateProfile`/`deleteProfile` in `ServerRepository`, `addTemplate`/`updateTemplate`/`deleteTemplate` in `SystemPromptTemplatesRepository`, and `addTemplate`/`updateTemplate`/`deleteTemplate` in `PersonaTemplateRepository` all use a `Mutex` to serialize read-modify-write on SharedPreferences.
- **Undo support:** `ChatViewModel` supports 5-second undo for user message deletions via `undoDelete()` and `canUndo` flag.
- **Theme toggle:** `main.dart` loads theme mode from SharedPreferences via `LocalDatabase.instance.loadThemeMode()`. Defaults to dark.
- **Prompt length limits:** `RoleplayPromptFormatter` caps personality (2000), setting (1000), userPersona (1000), memory (1000 per memory, max 3 memories) to prevent context overflow.
- **Export behavior:** Export is only available via context menus in the chat drawer and character drawer. The header bar export popup has been removed. `FileSaver.saveFile()` opens native save dialogs on mobile (SAF on Android, UIDocumentPicker on iOS); on desktop writes to the app documents directory.
- **Roleplay system prompt:** In roleplay mode the system prompt is fully managed by `RoleplayContextBuilder` which injects RAG context per-message. The System Prompt Customization section in Settings is hidden when `settingsVM.appMode == AppMode.roleplay` (line 622 of settings_screen.dart).
- **Roleplay identity guard:** `RoleplayPromptFormatter.buildSystemPrompt()` appends "Never speak, think, act, or write dialogue for the user — only write for your own character." to every roleplay prompt. This is the sole location for roleplay behavioral instructions.
- **Edit assistant messages (roleplay):** `MessageBubble` shows an edit icon (pencil) only for the **last** assistant message when `onEditAssistant` is provided (roleplay screen). `RoleplayViewModel.editAssistantMessage()` validates the message is completed and is the last in the list, then persists the edit to DB and re-embeds into RAG. The `isLastMessage` bool must be passed from the parent widget (computed as `index == messages.length - 1`).
- **Character deletion fix:** When deleting a character in `roleplay_drawer.dart`, the callback must `await` the delete, call `roleplayVM.deleteCharacter(id)` to clear the thread cache, then `Navigator.of(ctx).pop()` and `setState(() {})` to trigger a drawer rebuild. Without `setState`, the `FutureBuilder` snapshot is stale.
- **SillyTavern import flow:** Import button in roleplay drawer picks JSON → parses via `ParsedCharacterCard.fromJson()` → extracts `system_prompt`, `post_history_instructions`, `alternate_greetings` → creates `CharacterProfile` → saves via `CharacterRepository.createCharacter()` → auto-opens `_showEditDialog()` → returns updated character → starts roleplay. Use `file_picker` with `allowedExtensions: ['json']`.
- **`{{char}}` / `{{user}}` replacement:** Parser in `silly_tavern_card_parser.dart` replaces these tokens in personality, firstMessage, setting, userPersona, systemPrompt, and postHistoryInstructions fields. `{{user}}` falls back to "User" if userPersona is empty.
- **`_showEditDialog` returns `Future<CharacterProfile>`:** Must pass `CharacterRepository` as parameter (not use `context.read` inside the dialog). Delegates to `CharacterEditDialog` (proper `StatefulWidget` with `context.watch<PersonaTemplateViewModel>()` and `_applyTemplate()` in `setState`). Returns updated character on Save, original on Cancel. Use `.then((value) => value ?? character)` to handle nullable return.
- **Async snackbar safety:** Always check `context.mounted` before calling `ScaffoldMessenger.of(context)` in async handlers to avoid "deactivated widget ancestor" errors.
- **Alternate greetings:** `CharacterProfile.alternateGreetings` is a `List<String>`. Displayed as chips via `AlternateGreetingSelector` widget above the prompt input. Selecting one triggers `RoleplayViewModel.startRoleplayWithGreeting()` which starts a new conversation with that greeting as the first message.
- **Persona templates:** Global reusable user personas managed by `PersonaTemplateViewModel`. Created/edited in Settings → Persona Templates section. Selected via dropdown in character creation wizard, edit dialog, and SillyTavern import dialog. Template's `personaText` is copied into the character's `userPersona` field when applied.

## Platform-specific
- Desktop SQLite uses `sqflite_common_ffi`. Mobile uses native sqflite.
- Default theme: **dark mode** (loadable from prefs, default `ThemeMode.dark` in `main.dart`).
- **Dart SDK:** `^3.13.0` — do not downgrade.
- HTTP timeouts: connect 10s, receive 60s.
- `analysis_options.yaml` excludes: build, android, ios, web, windows, macos, linux.
- **Accessibility:** Message bubble action toolbar icons use `Semantics` labels. Text uses `MediaQuery.textScaler.scale()`.
- **Bubble width:** Capped at 600px via `LayoutBuilder` to prevent overflow on tablets.

## Testing
4 test files. No ViewModel, Repository, or API service tests:
- `test/domain/generation_params_test.dart` — `GenerationParams` OpenAI & native payload serialization, plus `TextSanitizer` markdown/code/LaTeX segment parsing (7 segments: markdown, inlineMath, markdown, blockMath, markdown, codeBlock, markdown).
- `test/network/sse_client_test.dart` — `SseClient.parseStream()` for OpenAI deltas, llama.cpp native chunks, ping comments, multi-line data.
- `test/widget_test.dart` — renders `ConnectionBadge` with status + latency. Calls `sqfliteFfiInit()` in `setUpAll` (safe in test isolate).
- `test/widget/character_edit_dialog_test.dart` — tests persona template loading into the character edit dialog's user persona field. Uses fake repositories for persona templates and character CRUD.

Run one: `flutter test test/domain/generation_params_test.dart`.

## Code structure
```
lib/
├── main.dart                          # Bootstrap, Provider wiring, FFI init, HTTP client, theme loading
├── core/
│   ├── constants/                     # AppTheme, API endpoints
│   ├── errors/                        # AppException hierarchy (6 classes)
│   ├── network/                       # ApiHttpClient, SseClient
│   └── utils/                         # LatencyMeter, Mutex, RoleplayContextBuilder, RoleplayPromptFormatter, TextSanitizer, HashEmbedding, FileSaver, EmbeddingService, SillyTavernCardParser, StAvatarDownloader
├── data/
│   ├── datasources/                   # LlamaApiService, LocalDatabase, VectorStore, EmbeddingService
│   ├── models/                        # All domain models (ChatThread, ChatMessage, ServerConfig, CharacterProfile, PersonaTemplate, etc.)
│   └── repositories/                  # ChatRepository, ServerRepository, CharacterRepository, SystemPromptTemplatesRepository, PersonaTemplateRepository
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
    │   │   ├── view_models/           # RoleplayViewModel, PersonaTemplateViewModel
    │   │   ├── views/                 # RoleplayScreen, RoleplayDrawer
    │   │   └── widgets/               # CharacterCreationWizard, CharacterEditDialog, SillyTavernImportDialog, PersonaTemplateDialog, AlternateGreetingSelector
    │   └── settings/
    │       ├── view_models/           # SettingsViewModel
    │       └── views/                 # SettingsScreen, ParameterTuningSheet
    └── shared/                        # AppHeader, ConnectionBadge
```
