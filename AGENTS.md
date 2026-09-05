# clan_ai — Agent Notes

## Running the project
Recommended order: `pub get` → `analyze` → `test` → `run`.
```
flutter pub get            # fetch dependencies (required after git pull)
flutter analyze            # lint + typecheck (uses flutter_lints)
flutter test               # runs all 28 test files (~150+ tests across all layers, includes reasoning)
flutter run -d <device>    # devices: linux, macos, windows, <android-id>
```

## Architecture (what's non-standard)
- **Hybrid Clean Architecture / MVVM** with `Provider` + `ChangeNotifier`.
- **No codegen.** All JSON serialization is manual `jsonEncode`/`jsonDecode` + `toMap()`/`fromMap()`.
- **No domain layer interfaces.** `lib/domain/models/` contains only `generation_params.dart`.
- **Shared constants** in `lib/core/constants/app_constants.dart` — all magic numbers and default strings centralized.
- **Shared mixin** `StreamMutationMixin` in `lib/ui/shared/mixins/stream_mutation_mixin.dart` — provides shared streaming, undo, switchVariant, stopGeneration logic for both ChatViewModel and RoleplayViewModel.
- **Shared widgets** in `lib/ui/shared/widgets/` — `parameter_sheet_opener.dart`, `drawer_export_menu.dart`, `auto_scroll_mixin.dart`, `delete_message_handler.dart`, `desktop_keyboard_shortcuts.dart`.
- **Shared settings sections** in `lib/ui/features/settings/views/sections/` — `profile_section.dart`, `safety_section.dart`, `app_mode_section.dart`.
- **Dependency wiring** in `lib/main.dart` via constructor injection.
- **Four root providers:** `SettingsViewModel`, `ChatViewModel`, `RoleplayViewModel`, `PersonaTemplateViewModel`. `CharacterRepository` also exposed via `Provider`.
- **ServerProfile consolidation:** `ServerConnectionDetails` removed; `ServerProfile` serves as connection details throughout. All method signatures using `ServerConnectionDetails?` now use `ServerProfile?`. `ServerConfig` now stores `baseUrl`, `apiKey`, `protocol` as direct constructor fields (no legacy getters). `SettingsViewModel.updateUrl/ApiKey/Protocol` writes to both profile and global config, persisted via `_saveConfig()`.
- **App mode toggle:** `AppMode.assistant` vs `AppMode.roleplay` stored in SharedPreferences. `_HomeScreen` routes to `ChatScreen` or `RoleplayScreen` based on mode.

## Platform channels (mobile file save)
- `lib/core/utils/file_saver.dart` — Dart side. Sends base64-encoded content via `MethodChannel` on Android/iOS; falls back to `getApplicationDocumentsDirectory()` on desktop.
- `android/app/src/main/kotlin/.../MainActivity.kt` — Android SAF via `ACTION_CREATE_DOCUMENT`. Decodes base64, writes to user-selected URI. Uses `MethodCall` from `io.flutter.plugin.common`.
- `ios/Runner/AppDelegate.swift` — iOS `UIDocumentPickerViewController(forExporting:asCopy:)`. Writes content to caches dir, presents picker, moves file on confirm.
- **file_picker** — Used for JSON file selection in SillyTavern import (`type: FileType.custom, allowedExtensions: ['json']`).

## Entry points
- `lib/main.dart` — bootstrap, Provider scope (4 providers + CharacterRepository), SQLite FFI init (**once** at startup), HTTP client singleton (lifecycle via `WidgetsBindingObserver`), theme mode loading from prefs.
- `lib/ui/features/chat/view_models/chat_view_model.dart` — assistant chat state. `loadThreads()` calls `getAssistantThreads()` which filters out roleplay threads (`characterId != null`). Undo support for message deletion. Thread search via `searchThreads()` filters by title + message content. `setFilteredThreads()` for async search results.
- `lib/ui/features/roleplay/view_models/roleplay_view_model.dart` — roleplay state with RAG. `_init()` calls `loadLastChat()` which uses `getThreads()` (all threads) then filters by `characterId`. Auto-loads last active thread by `characterId`. Supports `startRoleplay()` and `startRoleplayWithGreeting()` for alternate greetings. `exportCharacterWithRAG()` exports character card bundled with vector memories as JSON.
- `lib/ui/features/settings/view_models/settings_view_model.dart` — profiles, templates, server config, health polling, appMode. 15s health polling timer.
- `lib/ui/features/roleplay/view_models/persona_template_view_model.dart` — manages persona templates CRUD. Exposes templates list and create/update/delete methods.
- `lib/data/datasources/local_storage.dart` — SQLite schema v8 (threads, messages, characters, persona_templates tables) + SharedPreferences singleton for legacy config. Migration guards check column existence before `ALTER TABLE`. Characters and persona templates migrated from SharedPreferences to SQLite on v8 upgrade.
 - `lib/data/datasources/vector_store.dart` — SQLite vector store for roleplay character memory. Separate database file from main SQLite. Methods: `saveEmbedding`, `searchSimilar` (configurable topK/limit), `deleteCharacterEmbeddings`, `deleteEmbeddingsForMessages`, `deleteEmbedding` (single), `getAllMemories`, `getEmbeddingCount`.
- `lib/data/datasources/secure_storage_service.dart` — Encapsulates `flutter_secure_storage` for secure API key storage (iOS Keychain / Android KeyStore / Linux Secret Service). Methods: `saveApiKey`, `getApiKey`, `deleteApiKey`.
- `lib/data/datasources/llama_api_service.dart` — streams completions (OpenAI `/v1/chat/completions` or llama.cpp native `/completion`). Context-fit caps `contextSize` to model capacity minus reserved output tokens. Passes `serverConfig.reasoning` through to params for reasoning-capable models.
- `lib/core/network/sse_client.dart` — SSE parser for OpenAI delta and native `{content, stop}` formats. Produces `StreamChunk` + `StreamMetrics`. Extracts reasoning from multiple field names (`reasoning`, `reasoning_content`, `thought`). `filterReasoning()` stream pipeline processes inline thinking tags and forwards dedicated reasoning fields.
- `lib/core/network/http_client.dart` — HTTP client with `_throwForStatusCode` mapping status codes to 3 exceptions: `ContextLimitExceededException` (400 + "context"/"exceed"), `ServerOOMException` (500 + "memory"/"slot"), or generic `AppException`.
- `lib/core/utils/silly_tavern_card_parser.dart` — Parses SillyTavern `chara_card_v2` (spec_version 2.0) JSON into `ParsedCharacterCard` DTO. Maps `.data.description` → personality, `.data.first_mes` → firstMessage, `.data.scenario` → setting. Replaces `{{char}}` with character name and `{{user}}` with user persona (or "User" as fallback) in personality, firstMessage, setting, userPersona, systemPrompt, and postHistoryInstructions. Truncates personality to 4000 chars. Also extracts `.data.system_prompt`, `.data.post_history_instructions`, `.data.alternate_greetings[]`.
- `lib/core/utils/st_avatar_downloader.dart` — Downloads avatar bytes from URL with 30s timeout. Validates image format (PNG/JPEG/WebP) via magic bytes.
- `lib/ui/features/roleplay/widgets/silly_tavern_import_dialog.dart` — Preview/edit dialog for imported characters. Shows all parsed fields (including system prompt, post history, alternate greetings) with text editors and persona template selector dropdown.
- `lib/ui/features/roleplay/widgets/character_edit_dialog.dart` — Proper StatefulWidget for editing existing characters. Uses `context.watch<PersonaTemplateViewModel>()` for template selection. `_applyTemplate()` wraps state updates in `setState` to ensure TextField updates. Returns `Future<CharacterProfile>` via `.then()`.
- `lib/ui/features/roleplay/views/roleplay_drawer.dart` — Contains `_showEditDialog(CharacterProfile, CharacterRepository)` which delegates to `CharacterEditDialog`. Import flow: pick JSON → parse → save → auto-open edit dialog → start roleplay with updated character. Character export with RAG memories via `exportCharacterWithRAG()`.
- `lib/ui/shared/widgets/desktop_keyboard_shortcuts.dart` — Wraps root app in `RawKeyboardListener`. Handles Ctrl+N/Cmd+N (New Chat), Ctrl+K/Cmd+K (Thread Search with `showSearch`/`SearchDelegate`), Ctrl+, (Settings), Escape (Stop generation).
- `lib/ui/features/roleplay/widgets/character_creation_wizard.dart` — 4-step wizard with persona template selector, system prompt override, post history instructions, and alternate greetings input.
 - `lib/ui/features/roleplay/widgets/persona_template_dialog.dart` — Create/edit/delete persona templates dialog.
 - `lib/ui/features/roleplay/widgets/character_memories_dialog.dart` — Per-character memory viewer and pruner. Lists all vector embeddings for a character; allows deleting individual memories or clearing all.
- `lib/ui/features/roleplay/widgets/alternate_greeting_selector.dart` — Displays alternate greetings as selectable chips above the chat input.
- `lib/core/utils/roleplay_context_builder.dart` — Orchestrates RAG: embeds user input → searches memories → builds system prompt. Accepts `characterSystemPrompt` and `postHistoryInstructions` for per-character prompt overrides.
- `lib/core/utils/roleplay_prompt_formatter.dart` — Compiles roleplay system prompt. Handles character system prompt override with `{{original}}` prefix support. Appends post history instructions after standard prompt.

## Key models
- **`ChatThread`** (lib/data/models/chat_thread.dart) — owns messages via FK; `systemPrompt` (per-thread override), `modelId`, `customParams` (JSON), `isPinned`, `branchFromThreadId`, `characterId` (null = assistant, set = roleplay).
 - **`ChatMessage`** (lib/data/models/chat_message.dart) — `parentId`, `role` (system/user/assistant), `variantIndex`, `totalVariants`, `siblingIds` for branching. Status: `idle`/`sending`/`streaming`/`completed`/`error`. Metrics: `tokensPerSecond`, `totalTokens`, `timeToFirstTokenMs`, `generationTimeSec`. `isEdited` (bool), `updatedAt` (DateTime?) for tracking edits. `reasoningContent` (String) — stores the model's reasoning/thinking block when the "View Thinking" toggle is enabled. `ragMemoryCount` (int) — count of RAG memories injected into this message's system prompt. `ragMemoryContents` (String?) — JSON-encoded list of actual memory content strings for display.
- **`ServerConfig`** (lib/data/models/server_config.dart) — `id`, `name`, `baseUrl`, `apiKey`, `selectedModel`, `protocol` (openAi | llamaNative), `defaultParams`, `healthStatus`, `latencyMs`, `systemPrompt` (default: 'You are a helpful, brilliant, and honest AI assistant.'), `confirmDeleteMessage`, `reasoning` (bool — whether to request reasoning content from the API).
- **`ServerProfile`** (lib/data/models/server_profile.dart) — `name`, `baseUrl`, `apiKey`, `protocol`. Multiple profiles; switching changes connection details only. Config (system prompt, params, model) is global.
- **`GenerationParams`** (lib/domain/models/generation_params.dart) — temperature, topP, topK, minP, repeatPenalty, presencePenalty, frequencyPenalty, maxTokens (default 4096, **0 means unlimited**), contextSize (default 4096, clamped to [128, 1000000] during streaming), stopSequences, grammar, `reasoning` (bool — when true, includes `reasoning: true` and `include_reasoning: true` in OpenAI payload), `ragTopK` (int — configurable RAG memory count, default 3), `ragMinScore` (double — configurable RAG similarity threshold, default 0.0).
- **`CharacterProfile`** (lib/data/models/character_profile.dart) — `name`, `personality`, `firstMessage`, `setting`, `userPersona`, `avatarData` (PNG/JPG bytes), `isFavorite`, `systemPrompt` (per-character system prompt override with `{{original}}` prefix support), `postHistoryInstructions` (appended after AI responses), `alternateGreetings` (list of alternative opening messages). Stored in SQLite `characters` table (migrated from SharedPreferences in v8).
- **`PersonaTemplate`** (lib/data/models/persona_template.dart) — Global reusable user persona. `id`, `name`, `personaText`, `createdAt`, `updatedAt`. Stored in SQLite `persona_templates` table (migrated from SharedPreferences in v8).
- **`AppMode`** (lib/data/models/app_mode.dart) — `assistant` or `roleplay`.
- **`ApiProtocol`** (lib/data/models/server_config.dart) — `openAi` or `llamaNative`.

## Streaming flow (critical for chat changes)
1. ViewModel creates user message → persists to SQLite → creates streaming placeholder.
2. Resolves effective system prompt (`thread.systemPrompt ?? config.systemPrompt`).
3. Repository → ApiService: context-fit caps `contextSize` (modelCapacity - `reservedOutputTokensDefault` if unlimited). OpenAI POSTs `/v1/chat/completions`; llamaNative POSTs `/completion` with `### User`/`### Assistant` template. If `serverConfig.reasoning` is true, sends `reasoning: true` in payload.
4. `SseClient.parseStream()` handles both OpenAI delta and native `{content, stop}` formats. Extracts reasoning from multiple field names (`reasoning`, `reasoning_content`, `thought`).
5. `SseClient.filterReasoning()` stream pipeline processes inline thinking tags (```xml, `<thought>`, `<reasoning>`) and forwards dedicated reasoning fields. Applied to both OpenAI and native streams.
6. Context limit errors → `ContextLimitExceededException`.
7. **UI throttling:** `uiThrottleInterval` (20ms) buffers both `content` and `reasoningContent` tokens to avoid frame drops. Timer looks up message by ID each tick to handle mutations. Implemented via `StreamMutationMixin`.
8. Final metrics and `reasoningContent` written to SQLite on completion.

## RAG flow (roleplay only)
- `RoleplayViewModel.startRoleplay()` creates thread with initial RAG context (empty memories on first session).
- `RoleplayViewModel.sendMessage()` → `RoleplayContextBuilder.build()` → embeds user input → searches top-K similar memories via `VectorStore.searchSimilar(characterId: ...)` where topK defaults to `defaultRagTopK` (3).
- Retrieved memories injected into thread's `systemPrompt` before sending to API.
- After stream completes: `onComplete` hook in `StreamMutationMixin` fires `_embedMessageAsync()` — embeds user+assistant pair into vector store.
- `RoleplayViewModel.deleteThread()` calls `_characterRepository.deleteEmbeddingsForMessages(characterId, messageIds)` — only deletes embeddings for messages in the deleted thread, **not** all character embeddings.
- **System prompt override**: If character has `systemPrompt`, `RoleplayContextBuilder` uses it to replace the standard prompt. `{{original}}` prefix inserts standard prompt before custom text. `postHistoryInstructions` are appended after the full prompt.

## Reasoning/Thinking Block Feature
- **Settings toggle**: "Show Reasoning" in Settings → Safety & Convenience section. Stored in `ServerConfig.reasoning`. Persists via `toggleReasoning(bool)` in `SettingsViewModel`.
- **API request**: When enabled, `GenerationParams.toOpenAiPayload()` adds `"reasoning": true` and `"include_reasoning": true`. Native payload also includes `reasoning: true`.
- **SSE parsing**: `SseClient.parseStream()` extracts reasoning from multiple field names: `delta.reasoning`, `delta.reasoning_content`, `delta.thought`, top-level `reasoning`, etc. Both OpenAI and native formats.
- **Inline tag processing**: `SseClient.filterReasoning()` processes inline thinking tags (```xml, `<thought>`, `<reasoning>`) in the text stream. Handles partial tags mid-stream. Forwards dedicated reasoning fields when `enableReasoning` is true.
- **ViewModel accumulation**: Both `ChatViewModel` and `RoleplayViewModel` maintain `_pendingReasoningBuffer` alongside `_pendingStreamBuffer` via `StreamMutationMixin`. Throttle timer flushes both independently. On completion, saves `reasoningContent` to message via `copyWith(reasoningContent: ...)`.
- **UI display**: `_ReasoningBlock` widget in `MessageBubble` renders collapsible thinking block. Shows "Thinking" header with psychology icon. Tap to expand/collapse. Uses `AnimatedContainer`, `SelectableText`, and `Semantics` for smooth UX. Shows "Thinking..." while streaming.
- **Reasoning model support**: Works with OpenAI o1/o3, DeepSeek R1, Qwen, and other reasoning-capable models. Requires llama.cpp v1.7.7+ for native reasoning support.

## Gotchas
- **ServerConfig sync:** `ServerRepository.syncConfigFromProfile()` and `syncProfileFromConfig()` propagate `baseUrl`, `apiKey`, `protocol` between profile and global config. `SettingsViewModel.updateUrl/ApiKey/Protocol` updates both and calls `_saveConfig()`. Health check only notifies listeners when values actually change.
- **Settings screen:** Sections use numbered headers (1-7). System Prompt section hidden in roleplay mode; Persona Templates section shown instead. Model dropdown removed — handled via ProfileSection.
- **Parameter tuning sheet:** Uses `SettingsViewModel.getSelectedModelContextLength()` to set default context size to model max. `_buildSlider` renders parameter description subtitles. Context Window slider caps input to model's max context length.
- **StreamMutationMixin:** `ChatViewModel` and `RoleplayViewModel` both mix in `StreamMutationMixin` which provides `_streamResponse`, `undoDelete`, `canUndo`, `stopGeneration`, `switchVariant`, and `storeUndoMessage`. The mixin's `doStreamResponse` is called from each VM's `_streamResponse` with an optional `onComplete` hook (used by RoleplayViewModel for RAG embedding).
- **Conversation branching:** Regenerate/edit truncates at parent message, creates new sibling branches. Navigation uses `variantIndex` + `siblingIds`. `ChatViewModel.branchConversation()` creates a new `ChatThread` with copied messages and `branchFromThreadId` link.
- **System prompt resolution:** Thread-level `ChatThread.systemPrompt` overrides global `ServerConfig.systemPrompt`. In roleplay, RAG context builder overwrites it per-message. Character-level `CharacterProfile.systemPrompt` takes priority — if set, it replaces the entire prompt; `{{original}}` prefix inserts standard prompt before custom text.
- **Health polling:** 15s timer. Fallback chain: `/props` → `/v1/models`. `ServerRepository.fetchModels()` tries `/props` first (llama.cpp), then `/v1/models` (OpenAI), deduplicates by model id.
- **Android networking:** `127.0.0.1` is device loopback. Use `10.0.2.2` for emulator, LAN IP for physical devices.
- **SQLite FFI:** `sqfliteFfiInit()` called **once** in `main.dart` via `_initSqliteFfi()`. Guard: `if (_sqfliteFfiInitialized) return;` + platform check (Linux/Windows/macOS only). Both `LocalDatabase._initDB()` and `VectorStoreDatabase._initDB()` rely on this. Calling it again triggers "You are changing sqflite default factory" warning.
- **SQLite schema v8:** Migrations check column existence before `ALTER TABLE`. Schema evolution: v1→v2 (custom_params), v2→v3 (branch_from_thread_id), v3→v4 (character_id), v4→v5 (is_edited, updated_at), v5→v6 (rag_memory_count), v6→v7 (reasoning_content), v7→v8 (characters + persona_templates tables with SharedPreferences migration). Delete `clan_ai.db` if schema errors occur.
- **Profile vs config:** Profile stores connection details (`baseUrl`, `apiKey`, `protocol`). System prompt, params, model selection are global config shared across profiles.
- **Thread isolation:** `ChatViewModel.loadThreads()` → `getAssistantThreads()` filters out `characterId != null`. `RoleplayViewModel.loadLastChat()` → `getThreads()` (all threads) then filters by `characterId`, falls back to all-threads for legacy migration. `RoleplayViewModel.startRoleplay()` calls `getThreadsForCharacter(characterId)` to reuse existing threads — never creates duplicates.
- **Thread search:** `ChatViewModel.searchThreads()` searches both thread titles and message content for matches. `ChatDrawer` uses `setFilteredThreads()` to update the displayed list. `RoleplayDrawer` searches character names and thread titles within expanded characters.
- **RAG isolation:** Embeddings stored with `character_id`. Queries: `WHERE character_id = ?` — no cross-character leakage.
- **Hash embedding:** Pure Dart 256-dim vectors via char trigrams in `HashEmbedding`. <5ms, <1KB per vector. No ML dependencies.
- **Default API protocol:** `ApiProtocol.openAi` (in `ServerConfig` constructor).
- **Default params:** `reservedOutputTokensDefault` (512), `minContextSize` (128), `maxContextSize` (1000000), `defaultRagTopK` (3), `defaultRagLimit` (100) — all in `app_constants.dart`.
- **CRUD race conditions:** `insertCharacter`/`updateCharacter`/`deleteCharacter` in `LocalDatabase` (SQLite), `createProfile`/`updateProfile`/`deleteProfile` in `ServerRepository`, `addTemplate`/`updateTemplate`/`deleteTemplate` in `SystemPromptTemplatesRepository`, and `addTemplate`/`updateTemplate`/`deleteTemplate` in `PersonaTemplateRepository` (SQLite) all use a `Mutex` to serialize read-modify-write. Server profiles and system prompt templates still use SharedPreferences.
- **Undo support:** `ChatViewModel` and `RoleplayViewModel` support 5-second undo for user message deletions via `undoDelete()` and `canUndo` flag (provided by `StreamMutationMixin`).
- **Theme toggle:** `main.dart` loads theme mode from SharedPreferences via `LocalDatabase.instance.loadThemeMode()`. Defaults to dark.
- **Prompt length limits:** `RoleplayPromptFormatter` caps personality (2000), setting (1000), userPersona (1000), memory (1000 per memory, max 3 memories) to prevent context overflow.
- **Export behavior:** Export is only available via context menus in the chat drawer and character drawer. The header bar export popup has been removed. `FileSaver.saveFile()` opens native save dialogs on mobile (SAF on Android, UIDocumentPicker on iOS); on desktop writes to the app documents directory. Character export with RAG memories via `RoleplayViewModel.exportCharacterWithRAG()`.
- **Roleplay system prompt:** In roleplay mode the system prompt is fully managed by `RoleplayContextBuilder` which injects RAG context per-message. The System Prompt Customization section in Settings is hidden when `settingsVM.appMode == AppMode.roleplay`.
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
- Desktop keyboard shortcuts via `DesktopKeyboardShortcuts` widget (Ctrl+N/Cmd+N, Ctrl+K/Cmd+K, Ctrl+,, Escape).
- Default theme: **dark mode** (loadable from prefs, default `ThemeMode.dark` in `main.dart`).
- **Dart SDK:** `^3.13.0` — do not downgrade.
- HTTP timeouts: connect 10s, receive 60s.
- `analysis_options.yaml` excludes: build, android, ios, web, windows, macos, linux.
- **Accessibility:** Message bubble action toolbar icons use `Semantics` labels. Text uses `MediaQuery.textScaler.scale()`.
- **Bubble width:** Capped at 600px via `LayoutBuilder` to prevent overflow on tablets.

## Testing
28 test files across 8 layers, ~150+ tests. All tests use fake repositories (no real SQLite or network). ViewModels expose private state via setters for test injection.

### Test structure
- **Test helpers** (`test/helpers/`) — `FakeChatRepository`, `FakeCharacterRepository`, `FakeVectorStore`, `FakeServerRepository`, `FakePersonaTemplateRepository`, `test_model_factories.dart`.
 - **Domain** (`test/domain/`) — `generation_params_test.dart` (OpenAI & native payloads, TextSanitizer segment parsing, reasoning flags, configurable RAG params ragTopK/ragMinScore), `models/model_roundtrips_test.dart` (ChatThread, ChatMessage, CharacterProfile, PersonaTemplate, ServerConfig serialization roundtrips).
 - **Network** (`test/network/`) — `sse_client_test.dart` (OpenAI deltas, llama.cpp native chunks, ping comments, multi-line data, multi-field reasoning extraction, `filterReasoning` inline tag processing), `http_client_test.dart` (ContextLimitExceededException, ServerOOMException, AppException error classification, recovery suggestions).
 - **Utils** (`test/utils/`) — `roleplay_prompt_formatter_test.dart`, `roleplay_context_builder_test.dart`, `hash_embedding_test.dart`, `vector_store_test.dart` (save, search, delete, getAllMemories, deleteEmbedding), `silly_tavern_card_parser_test.dart`, `conversation_export_test.dart`, `file_saver_test.dart` (desktop fallback, ConversationExport toTxt/json).
- **Mixin** (`test/mixin/`) — `stream_mutation_mixin_test.dart` (streaming, undo, stop, switchVariant).
- **Repositories** (`test/repository/`) — `chat_repository_test.dart`, `character_repository_test.dart` (thread CRUD, message operations, favorites, embeddings).
- **ViewModels** (`test/view_model/`) — `chat_view_model_test.dart`, `roleplay_view_model_test.dart`, `settings_view_model_test.dart`, `persona_template_view_model_test.dart`.
- **Widgets** (`test/widget/`) — `message_bubble_test.dart`, `message_bubble_reasoning_test.dart`, `character_edit_dialog_test.dart`, `alternate_greeting_selector_test.dart`.
- **Integration** (`test/integration/`) — `assistant_chat_flow_test.dart`, `roleplay_chat_flow_test.dart`, `character_lifecycle_test.dart`, `persona_defaults_test.dart`, `settings_persistence_test.dart`.

### Running tests
```bash
flutter test                          # all tests
flutter test test/domain/             # domain layer only
flutter test test/view_model/         # view model tests only
flutter test test/integration/        # integration tests only
flutter test test/widget/             # widget tests only
flutter test test/domain/generation_params_test.dart   # single file
```

## Code structure
```
lib/
├── main.dart                          # Bootstrap, Provider wiring, FFI init, HTTP client, theme loading
├── core/
│   ├── constants/                     # AppTheme, API endpoints, shared constants (app_constants.dart)
│   ├── errors/                        # AppException hierarchy (6 classes)
│   ├── network/                       # ApiHttpClient, SseClient
│   └── utils/                         # LatencyMeter, Mutex, RoleplayContextBuilder, RoleplayPromptFormatter, TextSanitizer, HashEmbedding, FileSaver, EmbeddingService, SillyTavernCardParser, StAvatarDownloader
├── data/
│   ├── datasources/                   # LlamaApiService, LocalDatabase, VectorStore
│   ├── models/                        # All domain models (ChatThread, ChatMessage, ServerConfig, ServerProfile, CharacterProfile, PersonaTemplate, etc.)
│   └── repositories/                  # ChatRepository, ServerRepository, CharacterRepository, SystemPromptTemplatesRepository, PersonaTemplateRepository
├── domain/
│   └── models/                        # GenerationParams (only domain-layer model)
└── ui/
    ├── features/
    │   ├── chat/
    │   │   ├── view_models/           # ChatViewModel (mixins StreamMutationMixin)
    │   │   ├── views/                 # ChatScreen, MessageBubble, PromptInputBar, _ReasoningBlock
    │   │   └── widgets/               # MarkdownBodyView, CodeBlockView, MathView, TokenSpeedBadge
    │   ├── drawer/
    │   │   └── views/                 # ChatDrawer
    │   ├── roleplay/
    │   │   ├── view_models/           # RoleplayViewModel (mixins StreamMutationMixin), PersonaTemplateViewModel
    │   │   ├── views/                 # RoleplayScreen, RoleplayDrawer
    │   │   └── widgets/               # CharacterCreationWizard, CharacterEditDialog, SillyTavernImportDialog, PersonaTemplateDialog, AlternateGreetingSelector
    │   └── settings/
    │       ├── view_models/           # SettingsViewModel
    │       └── views/                 # SettingsScreen, ParameterTuningSheet, sections/ (profile_section, safety_section, app_mode_section)
    └── shared/                        # AppHeader, ConnectionBadge, mixins/ (stream_mutation_mixin), widgets/ (parameter_sheet_opener, drawer_export_menu, auto_scroll_mixin, delete_message_handler), avatar_utils
## Tests
```
test/
├── domain/                          # generation_params_test.dart, models/model_roundtrips_test.dart
├── helpers/                         # Fake repos and model factories
├── integration/                     # assistant_chat_flow_test.dart, roleplay_chat_flow_test.dart, etc.
├── mixin/                           # stream_mutation_mixin_test.dart
├── network/                         # sse_client_test.dart
├── repository/                      # chat_repository_test.dart, character_repository_test.dart
├── utils/                           # roleplay_prompt_formatter_test.dart, vector_store_test.dart, etc.
├── view_model/                      # chat_view_model_test.dart, roleplay_view_model_test.dart, etc.
└── widget/                          # message_bubble_test.dart, character_edit_dialog_test.dart, etc.
```
```
