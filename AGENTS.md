# clan_ai — Agent Notes

## Running the project
```
flutter analyze        # lint + typecheck (uses flutter_lints)
flutter test           # runs all 3 test files (domain/generation_params_test.dart, network/sse_client_test.dart, widget_test.dart)
flutter run            # default platform; add -d <device-id> to target
```

## Architecture (what's non-standard)
- **Hybrid Clean Architecture / MVVM** with `Provider` + `ChangeNotifier` state management.
- **No domain layer interfaces.** `lib/domain/` contains only `GenerationParams`. Repositories call datasources directly.
- **No codegen.** All JSON serialization is manual `jsonEncode`/`jsonDecode` + `toMap()`/`fromMap()`. No `build_runner`, `freezed`, or `json_serializable`.
- **Dependency wiring** happens in `lib/main.dart` via constructor injection with factory defaults.
- **Two providers** at the root: `SettingsViewModel`, `ChatViewModel`.
- **SettingsViewModel** manages: server profiles, system prompt templates, server config, models.
- **ChatViewModel** manages: thread list, active thread, messages, streaming.
- **Profile-aware config:** `ServerRepository.saveActiveConfig()` writes to the active profile; `loadActiveConfig()` merges global defaults (model, params, system prompt) with profile settings (baseUrl, apiKey, protocol).

## Entry points
- `lib/main.dart` — app bootstrap, Provider scope, SQLite FFI init for desktop.
- `lib/ui/features/chat/view_models/chat_view_model.dart` — chat state (send, stop, variants, branching).
- `lib/ui/features/settings/view_models/settings_view_model.dart` — profiles, templates, server config, health polling.
- `lib/data/datasources/local_storage.dart` — SQLite schema (threads + messages tables) + SharedPreferences for profiles/templates.
- `lib/data/datasources/llama_api_service.dart` — streams completions (OpenAI or llama.cpp native), applies best-effort context fit.
- `lib/core/network/sse_client.dart` — SSE parser, detects context errors, produces `StreamChunk` + `StreamMetrics`.

## Key domain models
- `ChatThread` — owns messages via FK; stores `systemPrompt` (per-thread override), `modelId`, `customParams` (JSON).
- `ChatMessage` — has `parentId`, `variantIndex`, `totalVariants`, `siblingIds` for conversation branching (regenerate/edit).
- `ServerConfig` — `ApiProtocol` enum: `openAi` or `llamaNative`. Also stores model, system prompt, hyperparameters.
- `ServerProfile` — lightweight wrapper storing only `baseUrl`, `apiKey`, `protocol`. Multiple profiles per user.
- `GenerationParams` — hyperparameters; `maxTokens` default is 4096, **0 means unlimited**. `contextSize` can go up to 1,000,000.
- `SystemPromptTemplate` — named, persistent prompt text. Stored in SharedPreferences.
- `ModelInfo` — fetched from server; includes `contextLength` for best-effort context fit.

## Streaming flow (critical for any chat changes)
1. `ChatViewModel.sendMessage()` creates user message → persists to SQLite → creates streaming placeholder.
2. `ChatViewModel._streamResponse()` resolves effective system prompt (`thread.systemPrompt ?? config.systemPrompt`), passes model context length.
3. `ChatRepository.streamCompletion()` → `LlamaApiService.streamChatCompletions()`:
   - **Best-effort context fit:** if `modelContextLength` is known, caps `contextSize` to fit (reserves tokens for output).
   - `openAi`: POST `/v1/chat/completions`
   - `llamaNative`: POST `/completion` with `### User`/`### Assistant` prompt template
4. `SseClient.parseStream()` handles both OpenAI delta format (`choices[0].delta.content`) and native (`{content, stop}`).
5. Detects context limit errors → throws `ContextLimitExceededException`.
6. **UI throttling:** `Timer.periodic(20ms)` buffers streamed tokens to avoid Flutter frame drops.
7. Final metrics (tokens/sec, TTFT, total tokens) written to SQLite on completion.

## Platform-specific notes
- Desktop SQLite uses `sqflite_common_ffi`. The FFI library must be initialized before any DB calls on Linux/Windows/macOS.
- Default theme is **dark mode** (`ThemeMode.dark` hardcoded in `main.dart` for OLED).
- `analysis_options.yaml` excludes `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/`, and `build/` from the analyzer.
- **Dart SDK:** `pubspec.yaml` pins `^3.13.0` — do not downgrade.

## Testing
- 3 test files: `GenerationParams` serialization, `SseClient` parsing, single widget render.
- No tests for ViewModels, Repositories, or API services.
- Tests live under `test/domain/`, `test/network/`, and `test/widget_test.dart`.

## Gotchas
- **Conversation branching:** Regenerate and edit truncate at the parent message and create new sibling branches. Variant navigation uses `variantIndex` + `siblingIds`.
- **System prompt resolution:** Thread-level `ChatThread.systemPrompt` overrides global `ServerConfig.systemPrompt`. Settings updates propagate to both the active thread (if it has a custom prompt) and the global config.
- **Profile system:** Profiles store only `baseUrl`, `apiKey`, `protocol`. Model, hyperparameters, system prompts, and model selection are global across all profiles. Switching a profile only changes connection details.
- **Health polling:** `SettingsViewModel` runs a 15s timer. Fallback chain: `/health` → `/props` → `/v1/models`.
- **Error handling:** 6 exception types (`ContextLimitExceededException`, `ServerOOMException`, `HostUnreachableException`, `NetworkException`, `RequestCancelledException`, `SseParseException`) with inline recovery suggestions.
- **Android networking:** `127.0.0.1` in default `baseUrl` is device loopback. Use `10.0.2.2` for emulator or LAN IP for physical devices.
- **Send on enter:** Input bar uses `TextInputAction.send` — Enter sends, Shift+Enter inserts a line break.
- **SQLite schema version 3:** `threads` table includes `branch_from_thread_id`. Migrations are idempotent (check column existence before `ALTER TABLE`).
- **maxTokens = 0** means unlimited in both OpenAI and llama.cpp payloads.
- **Context fit:** When a model reports its context length, the API service automatically caps `contextSize` to fit. No user action needed.
