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
| `models/` | Plain data classes with `toMap()`/`fromMap()` serialization (ChatThread, ChatMessage, CharacterProfile, ServerConfig, ServerProfile, GenerationParams) |
| `repositories/` | Data access orchestration (ChatRepository, CharacterRepository, ServerRepository) — aggregate datasources, apply business rules |
| `datasources/` | Raw data access (LocalDatabase, VectorStore, LlamaApiService) — SQLite, HTTP streams, secure storage |

**Key constraint:** Models are framework-agnostic. Serialization is manual — no codegen.

### Domain Layer (`lib/domain/`)

| Layer | Responsibility |
|-------|---------------|
| `models/` | Business logic models (GenerationParams) — temperature, topP, repeatPenalty, context-fit logic, token/JSON serialization |
| `errors/` | Exception hierarchy (AppException, ContextLimitExceededException, ServerOOMException) — error classification for UI handling |

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
   b. OpenAI: POST /v1/chat/completions (with reasoning flags if enabled)
   c. Native: POST /completion with ### User / ### Assistant template
6. SseClient.parseStream() receives chunks:
   a. OpenAI: delta.content format
   b. Native: {content, stop} format
   c. Reasoning: delta.reasoning, delta.reasoning_content, delta.thought
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

### Version 8 (Latest)

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
  FOREIGN KEY (thread_id) REFERENCES threads (id) ON DELETE CASCADE
);

-- Characters table: roleplay characters
CREATE TABLE characters (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  personality TEXT NOT NULL,
  first_message TEXT NOT NULL,
  setting TEXT,                          -- world/scenario description
  user_persona TEXT,                     -- user character description
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

### SSE Client

```
Server stream → SseClient.parseStream()
    │
    ├── OpenAI format: {"delta": {"content": "..."}}
    ├── Native format: {"content": "...", "stop": true}
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
```

### SQLite FFI

```
main.dart → _initSqliteFfi()  (once, on Linux/Windows/macOS)
    │
    ├── Desktop: sqflite_common_ffi (FFI bridge to SQLite)
    ├── Android/iOS: Native sqflite (bundled SQLite)
    └── Web: Not supported (SQLite FFI requires native)
```

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
2. **SQLite FFI** must be initialized once — calling again triggers "You are changing sqflite default factory" warning
3. **Thread isolation**: `characterId` null = assistant, non-null = roleplay — ChatViewModel filters by null, RoleplayViewModel filters by non-null
4. **RAG isolation**: Embeddings stored with `character_id` — queries use `WHERE character_id = ?` — no cross-character leakage
5. **Hash embedding**: Pure Dart 256-dim vectors via FNV-1a hash — deterministic, <5ms per vector, <1KB per vector
6. **RAG config**: `ragTopK` (1-10) and `ragMinScore` (0.0-1.0) control memory retrieval. Default: topK=3, minScore=0.0. Passed through `GenerationParams` → `RoleplayViewModel` → `RoleplayContextBuilder.build()`. Filtered by minimum cosine similarity in `RoleplayContextBuilder`.
7. **Memory chip**: `ChatMessage.ragMemoryCount` shows count of injected memories. `ChatMessage.ragMemoryContents` stores JSON-encoded memory content strings. Displayed in MessageBubble as clickable chip.
8. **Memory management**: `VectorStore.getAllMemories()` returns all embeddings for a character. `VectorStore.deleteEmbedding(id)` removes a single embedding. Accessed via `CharacterMemoriesDialog` from RoleplayDrawer character menu.
6. **SharedPreferences** still used for: server profiles, system prompt templates, theme mode, app mode, last roleplay thread ID
7. **SQLite** used for: threads, messages, characters, persona templates, embeddings
8. **Secure storage** used for: API keys (per profile)
