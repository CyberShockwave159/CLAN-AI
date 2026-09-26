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

Same as assistant mode, plus, per completed turn:

```
Exactly one memory write, chosen by the active backend:
  client  → onComplete hook embeds user+assistant pair into the vector store
  server  → onComplete hook POSTs the turn to /rag/ingest (fire-and-forget)

and, before streaming, the request carries RequestOptions:
  client  → (none; memories are already in the system prompt)
  server  → model: "a-prox-rag" + rag: {collection, top_k, min_score}
             + every message tagged "roleplay": true
```

Image generation reuses the same streaming path with three deviations, all
expressed as `doStreamResponse` options rather than a second implementation:

| Option | Value | Why |
|---|---|---|
| `historyOverride` | last few messages + a synthetic `/image` turn | the scene is not the whole transcript |
| `textMode` | `StreamTextMode.discard` | A-PROX's caption describes the picture request, not the reply |
| `persistOnComplete` | `false` (portraits only) | a scratch message has no thread row, and messages→threads is an enforced FK |

---

## Scene Image Generation (Roleplay Only)

```
User taps the image action on an assistant message
    │
    ├─ resolve identity reference: approved portrait → card avatar → (offer to generate one)
    │     Reference must be PNG/JPEG/WebP; anything else is transcoded or degrades to t2i
    │
    ▼
STEP 1 — draft the scene prompt  (ChatRepository.completeOnce, non-streaming, discarded)
  system: "image-prompt writer" (NOT the roleplay prompt — its identity guard
          would fight an instruction to describe the scene)
  body:   the last 3 exchanges + the appearance sheet + the visual theme
          + a final turn prefixed `/bypass`
  result: a scene description; a failure aborts before any variant is created
    │
    ▼
doCreateImageVariant(messageIndex)
  books a sibling variant seeded with the ORIGINAL text and NO imagePath
    │
    ▼
STEP 2 — generate  (streamed, textMode: discard)
  RequestOptions.sceneImage(
    style: character.visualTheme.wireValue,   → top-level "image_style"
    referenceImage: <portrait or avatar bytes> → attached as array content
                                                on the last user message
  )
  A-PROX: /image → forced agentic loop → prompt enhancer → image_generate
          → ComfyUI Qwen-Image 2.1 with `images.image_1` conditioning
    │
    ▼
Mixin captures delta.image_url → downloads → persists imagePath
    │
    ├─ image present  → new variant: original text + picture
    └─ image absent   → doRevertVariant() restores the original message
```

Notes that constrain this flow:

- **The picture is for the reader only.** `_serializeOpenAiContent` serializes
  image parts for `MessageRole.user` messages only, so an assistant image is
  never re-sent and the next reply is driven purely by the text.
- **Re-tapping the button always restarts from the identity reference**, never
  from the previous picture (hence not inheriting `imagePath`). Refining from a
  specific picture is a separate action, bound to a long press on the image.
- **Image variants never enter memory**, on either RAG backend.
- The request is **not** tagged `roleplay`: `/image` already forces a loop with
  only `image_generate` armed, and the roleplay marker would also arm
  `rag_search` for a picture request.

### Character consistency, three layers

| Layer | Mechanism | Guarantees |
|---|---|---|
| Reference conditioning | identity portrait as `image_1` | facial/structural identity — the only thing that actually locks a face |
| Appearance sheet | `characters.appearance`, pinned into the prompt | hair/eyes/build continuity, no drift |
| Visual theme | `image_style` resolved at the workflow level | a prompt rewriter cannot dilute the style |

The theme is sent **both** ways on purpose: in the prompt so the enhancer
elaborates in the right register, and as `image_style` so the workflow enforces
it after the rewrite.

---

## RAG Architecture

Roleplay memory has **two mutually exclusive backends**, selected by
`ServerConfig.serverSideRagEnabled` *and* the connected server's advertised
capability. They are never run together — that would inject the same facts
twice.

```
                      serverSideRagEnabled?  &&  ServerProfile.isAprox?
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
             CLIENT (default)                SERVER (A-PROX)
                    │                           │
   HashEmbedding.embed(user input)      POST /rag/ingest per turn
   VectorStore.searchSimilar             (fire-and-forget, after stream)
   inject into SYSTEM PROMPT                  │
                    │                    next turn sends
                    │                    model: "a-prox-rag"
                    │                    + rag: {collection, top_k, min_score}
                    │                           │
                    │                    A-PROX retrieves, injects into the
                    │                    LAST USER MESSAGE, and swaps the
                    │                    alias back to its upstream model
                    ▼                           ▼
            one prompt                    two prompts
```

| | Client | Server |
|---|---|---|
| Embeddings | `HashEmbedding`, on-device | A-PROX's ONNX BGE, CPU |
| Storage | `clan_ai_vectors.db` | SQLite vector store on the server |
| Injection point | system prompt | last user message |
| Scoping | `character_id` + thread lineage | `collection` per character **and** thread |
| Retrieval knobs | `ragTopK`, `ragMinScore` | same two, via the `rag` object |

Switching backends leaves `clan_ai_vectors.db` untouched, so toggling is
lossless. When the server backend is active the local pipeline is bypassed
entirely (`RoleplayContext.withoutMemories`), the per-message memory chip is
hidden (its `ragMemoryCount` stays null), and "Manage Memories" is hidden while
Settings keeps the local Clear buttons.

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
| `ragMinScore` | 0.0 | 0.0-1.0 | Minimum relevance threshold |
| `ragLimit` | 100 | — | Hardcoded candidate cap in the vector store query; not user-configurable |

Configuration is exposed in Settings → Generation Parameters with sliders. The
same two sliders drive both backends: the client path reads them through
`RoleplayContextBuilder.build()`, the server path through the `rag` request
object.

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

Self-gating: the chip renders when `ragMemoryCount > 0`, and that count is null
on the server backend, so no explicit hide is needed.

Assistant messages include a memory chip when `ragMemoryCount > 0`:
- Displays count of RAG memories injected into system prompt
- Tap shows `ragMemoryContents` (JSON-encoded memory strings) in expandable dialog
- `ragMemoryContents` stored as JSON list of memory content strings on `ChatMessage`

---

## SQLite Schema

### Version 16 (Latest)

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
  appearance TEXT,                        -- canonical physical description (v16)
  identity_portrait_data BLOB,            -- approved reference portrait, <=512px JPEG (v16)
  visual_theme TEXT,                      -- anime | semi-realistic | photo-realistic | NULL (v16)
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
| v14 → v15 | Added `image_url` column to messages (client-facing artifact URL, always surfaced as a tappable link under the rendered image) |
| v15 → v16 | Added `appearance`, `identity_portrait_data`, `visual_theme` columns to characters (image-consistency state) |

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
| `http_transport_io.dart` | `HttpClient()..connectionTimeout` + `IOClient` + `client.send()` | Byte-identical native path; 10s connect / 60s receive budgets. `postStream` accepts a per-call `timeout` for the response-header wait; `RequestOptions.sceneImageStreamTimeout` (10 min) covers A-PROX `/image`, which withholds headers until ComfyUI finishes (~195s) |
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
    ├── Passes artifact-only chunks straight through
    │   └── (no text + no reasoning + image_url/file_url). The transform only
    │       yields in response to text or reasoning, so such a chunk used to be
    │       dropped entirely. A-PROX `image_only` mode sends exactly this, and
    │       losing it looked like "the server returned no image".
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
    └── Provider<CharacterRepository>.value
    
ViewModels receive repositories via constructor injection.
Repositories receive datasources via constructor injection.
The shared network stack (`ApiHttpClient` → `LatencyMeter` → `LlamaApiService`) is built once in `main()` and required by `ServerRepository` and `ChatRepository` as positional initializing formals — no `??` fallbacks, so connection pooling and latency tracking can never be silently forked.
```

---

## Key Constraints & Gotchas

1. **StreamMutationMixin** is shared by ChatViewModel and RoleplayViewModel — all streaming, undo, stopGeneration, and switchVariant logic lives here
2. **Conversation branching**: Regenerate/edit operations create sibling variants that share a complete `siblingIds` array. `doSwitchVariant` loads siblings from DB via `getAllMessagesForThread()` (bypasses message deduplication), sorts by `variantIndex`, and indexes into the sorted list. Only messages with same `parentId` and `role == assistant` are considered variants. Regenerate builds the group member set (filtered by `role == assistant` and shared `parentId`) and `_syncVariantGroup` writes **both** `siblingIds` and `totalVariants` to every member, derived from the ids actually stored rather than by incrementing — a group is one consistent snapshot, so a member can never advertise a count or a sibling that disagrees with its peers. `variantGroupFields` applies the same values to a message not yet in the database. `doSwitchVariant` resolves sibling ids strictly and drops any it cannot find, then sorts the resolved list and uses `variantIndex + 1` / `variantIndex - 1`; it never substitutes the current message for a missing one, which would create a duplicate with the same `variantIndex` and make the switch a no-op. Branches are linked via `branchFromThreadId` on `ChatThread`.
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
14. **PWA**: `flutter build web --release` generates a **self-unregistering** `flutter_service_worker.js` stub (Flutter ~3.44+, `flutter#156910`) — no app-shell cache out of the box. CLAN AI ships its own `web/clan_ai_sw.js` (registered from `index.html`, copied verbatim into the build): precaches the shell, runtime-caches same-origin assets stale-while-revalidate, network-first navigations, cache keyed by app version, and never intercepts cross-origin llama.cpp traffic. Returned users always boot the newest deploy: the SW only addresses caches once the deployed `version.json` is resolved, the navigation handler awaits the re-key + stale-cache sweep *before* handing the fresh page to the browser, and the deployed version is adopted eagerly on cold start (so the stale `"null"` cache created by older SW versions is swept, never served). Build with `--no-web-resources-cdn` so CanvasKit is local (offline boot doesn't depend on the gstatic CDN). `web/sqflite_sw.js` is the sqlite **SharedWorker** and is unrelated to offline caching.
15. **Assistant content rendering** (`DynamicMarkdownView` over `TextSanitizer.parseSegments` segments): hyperlinks open in the platform browser (new tab on PWA) via `url_launcher`; raster image URLs (markdown links or bare — extension in the image set, or a `data:image/…` URL declaring a raster MIME, both handled by `TextSanitizer.embedImageLinks`) render inline as `MarkdownImageView` widgets (decode via `Image.memory` for `data:` payloads) with tap-to-lightbox, while image URLs inside code blocks stay literal code; fenced code blocks keep the full first line inside the rendered code and show only the (ellipsized) language in the header. LLM-generated **files** surface as distinct tappable objects at the end of the message: `TextSanitizer.extractFileRefs` lifts non-image artifact-extension URLs (the `TextSanitizer.artifactExtensions` allowlist — excludes code blocks and `![…]` images, deduplicated) out of the assistant markdown and `MessageBubble` merges them with the stored A-PROX `file_url` artifact (deduped by filename) into `ArtifactFileCard`s. Tapping a card saves/exports via `FileSaver.saveBytes`: stored A-PROX bytes come from `MessageAttachmentStore.readBytes`, content-derived URLs are fetched once through `MessageAttachmentStore.fetchBytes` (nothing persisted). `fetchBytes` also decodes inline base64/percent-encoded `data:` URLs without a network call, so A-PROX `inline_data_url` artifacts (image *and* file) resolve even when `/images`/`/files` is unreachable. Only assistant messages render file objects.
