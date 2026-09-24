# CLAN AI — Architecture

## Overview

CLAN AI is a cross-platform Flutter application built on a **Hybrid Clean Architecture / MVVM** pattern with `Provider` + `ChangeNotifier` for state management. The app connects to local or networked llama.cpp servers and OpenAI-compatible endpoints for real-time streaming inference.

## Layer Responsibilities

### Presentation Layer (`lib/ui/`)

| Layer | Responsibility |
|-------|---------------|
| `views/` | Screens (ChatScreen, RoleplayScreen, SettingsScreen, RoleplayDrawer) — read ViewModel state, dispatch user actions |
| `view_models/` | Business logic containers (ChatViewModel, RoleplayViewModel, SettingsViewModel, PersonaTemplateViewModel) — extend ChangeNotifier, hold mutable app state |
| `widgets/` | Reusable components (MessageBubble, ParameterTuningSheet, CharacterCreationWizard) — pure UI, no state ownership |
| `shared/` | Cross-cutting concerns (StreamMutationMixin, AppHeader, ConnectionBadge, AutoScrollMixin) |

**Key constraint:** ViewModels do NOT reference repositories directly. Repository access flows through `Provider` injection at the `main.dart` level.

### Data Layer (`lib/data/`)

| Layer | Responsibility |
|-------|---------------|
| `models/` | Plain data classes with `toMap()`/`fromMap()` serialization (ChatThread, ChatMessage, CharacterProfile, ServerConfig, ServerProfile, GenerationParams, ModelInfo, SystemPromptTemplate) |
| `repositories/` | Data access orchestration (ChatRepository, CharacterRepository, ServerRepository) — aggregate datasources, apply business rules |
| `datasources/` | Raw data access (LocalDatabase, VectorStore, LlamaApiService) — SQLite, HTTP streams, secure storage |

**Key constraint:** Models are framework-agnostic. Serialization is manual — no codegen.

### Domain Layer (`lib/domain/`)

| Layer | Responsibility |
|-------|---------------|
| `models/` | Business logic models (GenerationParams) — temperature, topP, repeatPenalty, context-fit logic, token/JSON serialization |
| `errors/` | Exception hierarchy (AppException, ContextLimitExceededException, ServerOOMException) — error classification for UI handling |

**Note:** `ModelInfo` lives in `lib/data/models/` (data layer) — it represents API response metadata from `/v1/models` and `/props` endpoints.

### Core Layer (`lib/core/`)

| Layer | Responsibility |
|-------|---------------|
| `utils/` | Cross-cutting utilities (Mutex, LatencyMeter, RoleplayContextBuilder, RoleplayPromptFormatter, HashEmbedding, FileSaver, TextSanitizer) |
| `network/` | HTTP and SSE transport (ApiHttpClient, SseClient) — streaming protocol handling |
| `constants/` | App-wide constants (AppTheme, API endpoints, default values) |

---

## MVVM Flow

```
User Action
    │
    ▼
Widget (e.g., MessageBubble)
    │  Provider.of<ChatViewModel>(context, listen: false)
    ▼
ViewModel (ChatViewModel)
    │  Constructor injection
    ▼
Repository (ChatRepository)
    │  Datasource calls
    ▼
Datasource (LocalDatabase / LlamaApiService)
    │
    ▼
ChangeNotifier.notifyListeners() ──▶ UI rebuild
```

---

## Streaming Flow

### Assistant Mode (ChatViewModel)

```
1. User sends message
2. ViewModel creates ChatMessage (status: "sending")
3. Persists message to SQLite
4. Resolves effective system prompt: thread.systemPrompt ?? config.systemPrompt
5. Repository → ApiService:
   a. Context-fit: contextSize = modelCapacity - reservedOutputTokens (if maxTokens=0)
   b. OpenAI-compatible: POST /v1/chat/completions (with reasoning flags if enabled)
6. SseClient.parseStream() receives chunks:
   a. OpenAI: delta.content format
   b. Reasoning: delta.reasoning, delta.reasoning_content, delta.thought
7. SseClient.filterReasoning() processes inline tags (```xml, <thought>, <reasoning>)
8. StreamMutationMixin throttle (20ms interval):
   a. Accumulates _pendingStreamBuffer → content
   b. Accumulates _pendingReasoningBuffer → reasoningContent
   c. Updates message in ViewModel state
9. On stream complete:
   a. Writes final metrics (tokensPerSecond, totalTokens, generationTimeSec)
   b. Saves reasoningContent to SQLite
   c. Runs onComplete hook (if provided)
```

### Roleplay Mode (RoleplayViewModel)

Same as assistant mode, plus:

```
Before streaming:
  RAG ContextBuilder embeds user input → searches vector store → injects top-K memories into system prompt

After streaming:
  onComplete hook embeds user+assistant pair into vector store (fire-and-forget)
```

---

## RAG Architecture

### Vector Store

```
┌─────────────────────────────────────────────────────┐
│  VectorStoreDatabase (SQLite-backed)                │
│                                                     │
│  Table: embeddings                                  │
│    - id (TEXT PRIMARY KEY)                          │
│    - character_id (TEXT)                            │
│    - message_id (TEXT)                              │
│    - embedding (REAL[256])                          │
│    - content (TEXT)                                 │
│                                                     │
│  Index: idx_embeddings_character_id                  │
└─────────────────────────────────────────────────────┘
```

### Hash Embedding

```
Input text → character trigrams → 256-dim feature vector → cosine similarity search

Algorithm:
1. Generate all 3-character substrings (trigrams)
2. Hash each trigram to [0, 255] via FNV-1a hash
3. Accumulate into 256-dim vector (normalized)

Properties:
- Deterministic (same text → same vector)
- <5ms per embedding
- <1KB per vector
- No ML dependencies (pure Dart)
```

### Context Building Pipeline

```
User input → HashEmbedding.embed(input)
    │
    ▼
VectorStore.searchSimilar(characterId, queryVector, topK=ragTopK)
    │
    ▼
Retrieve top-K memories → filter by similarity threshold (ragMinScore)
    │
    ▼
RoleplayContextBuilder.injectMemories(systemPrompt, memories)
    │
    ▼
Final system prompt includes RAG memories → sent to API
```

### RAG Configuration

RAG behavior is configurable via `GenerationParams`:

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `ragTopK` | 3 | 1-10 | Number of memories to retrieve |
| `ragMinScore` | 0.0 | 0.0-1.0 | Minimum cosine similarity threshold |
| `ragLimit` | 100 | — | Maximum number of memories returned by the vector store query |

Configuration is exposed in Settings → Generation Parameters with sliders. Values are passed through `RoleplayViewModel` to `RoleplayContextBuilder.build()`.

### Memory Management

```
User taps "Manage Memories" in character popup menu
    │
    ▼
CharacterMemoriesDialog opens
    │
    ├── Lists all embeddings (via VectorStore.getAllMemories)
    ├── Delete individual: VectorStore.deleteEmbedding(id)
    └── Clear all: VectorStore.deleteCharacterEmbeddings(characterId)
```

### Memory Chip Display

Assistant messages include a memory chip when `ragMemoryCount > 0`:
- Displays count of RAG memories injected into system prompt
- Tap shows `ragMemoryContents` (JSON-encoded memory strings) in expandable dialog
- `ragMemoryContents` stored as JSON list of memory content strings on `ChatMessage`

---

## SQLite Schema

### Version 14 (Latest)

```sql
-- Thread table: conversation containers
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  system_prompt TEXT,                    -- thread-level system prompt override
  model_id TEXT,                         -- selected model identifier
  custom_params TEXT,                    -- JSON generation parameters
  is_pinned INTEGER NOT NULL DEFAULT 0,  -- pinning state
  branch_from_thread_id TEXT,            -- lineage for branching conversations
  character_id TEXT,                     -- null=assistant, set=roleplay character
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Messages table: conversation turns
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  parent_id TEXT,                        -- for branching/regeneration
  role TEXT NOT NULL,                    -- system, user, assistant
  content TEXT NOT NULL,
  status TEXT NOT NULL,                  -- idle, sending, streaming, completed, error
  tokens_per_second REAL,                -- performance metrics
  total_tokens INTEGER,
  time_to_first_token_ms INTEGER,
  generation_time_sec REAL,
  error_message TEXT,
  variant_index INTEGER NOT NULL DEFAULT 0,
  total_variants INTEGER NOT NULL DEFAULT 1,
  sibling_ids TEXT,                      -- JSON array of sibling message IDs
  created_at TEXT NOT NULL,
  is_edited INTEGER NOT NULL DEFAULT 0,  -- message edit tracking
  updated_at TEXT,
  rag_memory_count INTEGER DEFAULT NULL, -- count of RAG memories injected
  reasoning_content TEXT NOT NULL DEFAULT "",  -- thinking block storage
  image_path TEXT,                       -- absolute path to image attachment file (user msgs)
  file_path TEXT,                        -- absolute path to file artifact file (from image_url/file_url artifacts)
  file_name TEXT,                        -- original filename of the file artifact
  file_mime TEXT,                        -- MIME type of the file artifact
  FOREIGN KEY (thread_id) REFERENCES threads (id) ON DELETE CASCADE
);

-- Characters table: roleplay characters
CREATE TABLE characters (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  personality TEXT NOT NULL,
  first_message TEXT NOT NULL,
  setting TEXT,                          -- world/scenario description
  user_persona TEXT,                     -- deprecated, use persona_description
  persona_name TEXT,                     -- name used when character refers to user
  persona_description TEXT,              -- full persona description
  avatar_data BLOB,                      -- PNG/JPEG/WebP image bytes
  is_favorite INTEGER NOT NULL DEFAULT 0,
  system_prompt TEXT,                    -- per-character system prompt override
  post_history_instructions TEXT,        -- text appended after AI responses
  alternate_greetings TEXT,              -- JSON array of alternate opening messages
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Persona templates table: reusable user personas
CREATE TABLE persona_templates (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  persona_name TEXT NOT NULL,
  persona_text TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

### Migration Path

| Version | Change |
|---------|--------|
| v1 → v2 | Added `custom_params` column to threads |
| v2 → v3 | Added `branch_from_thread_id` column to threads |
| v3 → v4 | Added `character_id` column to threads (assistant/roleplay separation) |
| v4 → v5 | Added `is_edited` and `updated_at` columns to messages |
| v5 → v6 | Added `rag_memory_count` column to messages |
| v6 → v7 | Added `reasoning_content` column to messages (thinking blocks) |
| v7 → v8 | Created `characters` and `persona_templates` tables; migrated data from SharedPreferences |
| v8 → v9 | Added `rag_memory_contents` column to messages (JSON-encoded memory content strings) |
| v9 → v10 | Added `persona_name` and `persona_description` columns to characters |
| v10 → v11 | Added `persona_name` column to persona_templates; auto-derives from `persona_text` for existing templates |
| v11 → v12 | Added `variant_index`, `total_variants`, `sibling_ids` columns to messages for conversation branching |
| v12 → v13 | Added `image_path` column to messages (absolute path to attached image file, user messages only) |
| v13 → v14 | Added `file_path`, `file_name`, `file_mime` columns to messages (downloaded file artifacts from `image_url`/`file_url` SSE deltas) |

---

## Network Architecture

### HTTP Client

```
ApiHttpClient
    │
    ├── ContextLimitExceededException (status 400 + "context"/"exceed")
    ├── ServerOOMException (status 500 + "memory"/"slot")
    └── AppException (all other errors)
```

The underlying transport is a conditional-import facade (`export ... show` on `dart.library.io` / `dart.library.js_interop` — the VM resolves the io variant so native behavior is unchanged):

| Variant | Implementation | Notes |
|---|---|---|
| `http_transport_io.dart` | `HttpClient()..connectionTimeout` + `IOClient` + `client.send()` | Byte-identical native path; 10s connect / 60s receive budgets |
| `http_transport_web.dart` | `web.window.fetch` + `ReadableStreamDefaultReader` | XHR `BrowserClient` buffers whole responses, so token streaming needs incremental `read()`; consumer cancel aborts the fetch (`AbortController`), mirroring socket teardown. No TCP connect timeout in browsers — the existing `.timeout()` guards are the only bound. |

`postStream()` returns a `StreamedApiResponse { statusCode, stream, bodyToString() }` — the `.stream` member matches `http.StreamedResponse`, so `LlamaApiService` and `SseClient.parseStream()` call sites are untouched.

### SSE Client

```
Server stream → SseClient.parseStream()
    │
    ├── OpenAI format: {"choices": [{"delta": {"content": "..."}}]}
    ├── reasoning delta fields: reasoning / reasoning_content / thought
    └── Comments: ": ping" (ignored)
    │
    ▼
SseClient.filterReasoning()
    │
    ├── Processes inline tags: ```xml, <thought>, <reasoning>
    ├── Forwards dedicated fields: reasoning, reasoning_content, thought
    └── Produces StreamChunk + StreamMetrics
```

### Server Discovery & Health

```
Health polling (15s interval):
  1. GET /health
  2. GET /props (llama.cpp)
  3. GET /v1/models (OpenAI)
  
Model list:
  1. Try /props first (llama.cpp native)
  2. Fallback to /v1/models (OpenAI)
  3. Deduplicate by model id
```

---

## Platform Channels

### File Saver (Mobile Export)

```
Dart: FileSaver.saveFile(content, filename, format)
    │
    ├── Android: MethodChannel → MainActivity.kt
    │   └── ACTION_CREATE_DOCUMENT (SAF)
    │   └── Decodes base64, writes to user URI
    │
    ├── iOS: MethodChannel → AppDelegate.swift
    │   └── UIDocumentPickerViewController(forExporting:asCopy:)
    │   └── Writes to caches, presents picker, moves on confirm
    │
    └── Desktop: Falls back to app documents directory
    └── Web: Browser download (Blob + object URL + anchor click)
```

### Attachment Storage

Message image attachments are stored through a conditional-import facade (`message_attachment_backend_{io,web,stub}.dart`) behind `MessageAttachmentStore`: the SQLite `messages.image_path` column holds an opaque ref (an absolute path on native, a DB key on web) — **schema unchanged**.

| Variant | Storage | Notes |
|---|---|---|
| `io` (`FileAttachmentBackend`) | Files under `<documents>/attachments/` | Previous on-disk behavior, moved verbatim |
| `web` (`SqliteAttachmentBackend`) | BLOBs in `clan_ai_attachments.db` (`id` TEXT PK, `bytes` BLOB, IndexedDB-backed) | Lazy-open, `INSERT OR REPLACE`/`DELETE`/`SELECT` keyed by `$fileId.$ext` |

`AttachmentImage` is a stateful widget that renders `Image.file` on native and `Image.memory` (loaded via `store.readBytes(ref)`) on web; the read future is cached per `ref` so rebuilds do not re-query.

### SQLite FFI

```
main.dart → _initSqliteFfi()  (once, at startup)
    │
    ├── Desktop (Linux/Windows/macOS): sqflite_common_ffi (FFI bridge to SQLite)
    ├── Android/iOS: Native sqflite (bundled SQLite)
    └── Web: databaseFactoryFfiWeb (sqflite_common_ffi_web)
        └── sqlite3 compiled to WASM (web/sqlite3.wasm), driven from a
            SharedWorker (web/sqflite_sw.js), persisted to the origin's IndexedDB
```

Web specifics:

- `web/sqlite3.wasm` (748,686 B) and `web/sqflite_sw.js` are a **locked pair** committed in the repo (`dart run sqflite_common_ffi_web:setup --force` regenerates both). Any `sqflite*`/`sqlite3` resolution change requires re-running setup, or boot fails with a WebAssembly import error (`Import #25 "env"` → `Unsupported operation: unsupported result null`).
- DB identity is scoped to **origin + port**; in-browser paths from `local_storage.dart`/`vector_store.dart` produce real IndexedDB-backed databases.
- `clan_ai_attachments.db` (attachment BLOB store) is a separate WASM sqlite DB — one shared persistence mechanism for all web data, kept out of the main DB to bound quota pressure.

---

## Dependency Injection

```
main.dart
    │
    ├── Provider<SettingsViewModel>
    ├── Provider<ChatViewModel>
    ├── Provider<RoleplayViewModel>
    ├── Provider<PersonaTemplateViewModel>
    └── Provider<CharacterRepository> (via ProxyProvider)
    
ViewModels receive repositories via constructor injection.
Repositories receive datasources via constructor injection.
All optional — defaults to production instances.
```

---

## Key Constraints & Gotchas

1. **StreamMutationMixin** is shared by ChatViewModel and RoleplayViewModel — all streaming, undo, stopGeneration, and switchVariant logic lives here
2. **Conversation branching**: Regenerate/edit operations create sibling variants that share a complete `siblingIds` array. `doSwitchVariant` loads siblings from DB via `getAllMessagesForThread()` (bypasses message deduplication), sorts by `variantIndex`, and indexes into the sorted list. Only messages with same `parentId` and `role == assistant` are considered variants. Regenerate builds `allSiblingIds` set (filtered by `role == assistant` and shared `parentId`) and assigns it to every variant in the group. Navigation uses `variantIndex + 1` for next, `variantIndex - 1` for previous. Branches are linked via `branchFromThreadId` on `ChatThread`.
3. **SQLite init** must happen once — `_initSqliteFfi()` (FFI on desktop, `databaseFactoryFfiWeb` on web). Calling the FFI init again triggers "You are changing sqflite default factory" warning
4. **Thread isolation**: `characterId` null = assistant, non-null = roleplay — ChatViewModel filters by null, RoleplayViewModel filters by non-null
5. **RAG isolation**: Embeddings stored with `character_id` — queries use `WHERE character_id = ?` — no cross-character leakage
6. **Hash embedding**: Pure Dart 256-dim vectors via FNV-1a hash — deterministic, <5ms per vector, <1KB per vector
7. **RAG config**: `ragTopK` (1-10) and `ragMinScore` (0.0-1.0) control memory retrieval. Default: topK=3, minScore=0.0. Passed through `GenerationParams` → `RoleplayViewModel` → `RoleplayContextBuilder.build()`. Filtered by minimum cosine similarity in `RoleplayContextBuilder`.
8. **Memory chip**: `ChatMessage.ragMemoryCount` shows count of injected memories. `ChatMessage.ragMemoryContents` stores JSON-encoded memory content strings. Displayed in MessageBubble as clickable chip.
9. **Memory management**: `VectorStore.getAllMemories()` returns all embeddings for a character. `VectorStore.deleteEmbedding(id)` removes a single embedding. Accessed via `CharacterMemoriesDialog` from RoleplayDrawer character menu.
10. **SharedPreferences** still used for: server profiles (`clan_server_profiles`), active profile ID (`clan_active_profile_id`), active server config (`clan_active_server_config`), theme mode (`clan_theme_mode`), custom theme colors (`clan_custom_theme_colors`), app mode (`clan_app_mode`), last roleplay thread ID (`clan_last_roleplay_thread_id`), system prompt templates (`clan_system_prompt_templates`). Characters and persona templates were migrated from SharedPreferences to SQLite in v7→v8 and are no longer stored there.
11. **SQLite** used for: threads, messages, characters, persona templates, embeddings (separate database file). On web every DB is WASM + IndexedDB-backed (`clan_ai.db`, `clan_ai_vectors.db`, `clan_ai_attachments.db`) and scoped to origin + port
12. **Secure storage** used for: API keys (per profile, via `flutter_secure_storage`) — Keychain/KeyStore/Secret Service on native, localStorage-grade (obfuscated) on web
13. **Web transport** is the only streaming variance: `http_transport_web.dart` pumps a `ReadableStream` into `SseClient.parseStream` unchanged; consumer cancel aborts the fetch (stop-generation works); browsers impose CORS + mixed-content rules, so llama.cpp needs `--cors-origins <origin>`
14. **PWA**: `flutter build web --release` generates a **self-unregistering** `flutter_service_worker.js` stub (Flutter ~3.44+, `flutter#156910`) — no app-shell cache out of the box. CLAN AI ships its own `web/clan_ai_sw.js` (registered from `index.html`, copied verbatim into the build): precaches the shell, runtime-caches same-origin assets stale-while-revalidate, network-first navigations, cache keyed by app version, and never intercepts cross-origin llama.cpp traffic. Build with `--no-web-resources-cdn` so CanvasKit is local (offline boot doesn't depend on the gstatic CDN). `web/sqflite_sw.js` is the sqlite **SharedWorker** and is unrelated to offline caching.
