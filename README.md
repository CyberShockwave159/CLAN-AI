# clan_ai

Frontier-class cross-platform llama.cpp client. A Flutter app that connects to a local or networked llama.cpp server for real-time AI inference.

## Platforms

| Platform | Status |
|----------|--------|
| Linux (desktop) | Supported |
| macOS (desktop) | Supported |
| Windows (desktop) | Supported |
| Android | Supported |
| iOS | Supported (requires macOS to build) |
| Web | Not supported |

## Features

- Real-time streaming chat with both OpenAI-compatible and native llama.cpp endpoints
- **AI Roleplay Mode** — Toggle from Settings; mirrors assistant mode UI with per-character isolated sessions and client-side RAG memory
- **Character Creation** — 4-step wizard (personality, setting/world, user persona, advanced prompt settings) with optional avatar upload and persona template selector
- **SillyTavern Import** — Import `.json` character cards (`chara_card_v2` format) with auto-edit dialog; extracts system prompt override, post history instructions, and alternate greetings
- **Persona Templates** — Create reusable user personas in Settings; any character can select a template to pre-fill its user persona
- **Alternate Greetings** — Characters can have multiple opening messages shown as selectable chips above the prompt input
- **Character System Prompt Override** — Per-character system prompts with `{{original}}` prefix support to prepend to default prompt
- **Post History Instructions** — Additional text appended after each AI response for style reminders or state tracking
- **Client-Side RAG** — Pure Dart feature hashing embeddings (256-dim, char trigrams) with SQLite cosine similarity; zero ML dependencies
- **Conversation branching** — Regenerate and edit responses to create sibling variants
- SQLite local persistence with full thread/message history
- Automatic server health polling with fallback endpoints (`/health` → `/props` → `/v1/models`)
- Dark mode by default (OLED-optimized), configurable system prompt
- Markdown, code block, and LaTeX math rendering in responses
- Token speed and performance metrics per generation
- Export conversations to TXT or JSON via drawer context menus (native save dialogs on mobile)

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (Dart SDK ^3.13.0)
- A running llama.cpp server (with API endpoints enabled)

## Getting Started

```bash
# Clone and fetch dependencies
git clone https://github.com/CyberShockwave159/CLAN-AI.git
cd clan_ai
flutter pub get

# Run on your preferred platform
flutter run                          # defaults to connected device
flutter run -d linux                 # Linux desktop
flutter run -d macos                 # macOS desktop
flutter run -d windows               # Windows desktop
flutter run -d <android-device-id>   # Android device/emulator
```

## Configuration

On first launch, open Settings from the side drawer and configure your llama.cpp server:

1. **Base URL** — Enter your server address:
   - Desktop: `http://localhost:8080`
   - Android emulator: `http://10.0.2.2:8080`
   - Android physical device: `http://<host-lan-ip>:8080`
   - iOS simulator: `http://localhost:8080`
2. **API Protocol** — Choose "OpenAI Compatible" or "llama.cpp Native"
3. **Model** — Select a model from the auto-discovered list
4. Test the connection, then start chatting

### Roleplay Mode

Toggle "Roleplay Mode" in Settings to switch to character roleplay:

1. Open the sidebar (hamburger menu)
2. Tap "New Roleplay" to create a character manually, or "Import ST Card" to import a SillyTavern `.json` character card
3. SillyTavern cards (`chara_card_v2` spec) are automatically parsed — `{{char}}` and `{{user}}` tokens are replaced with the character name and user persona
4. Characters are listed in the sidebar; tap a character to start a session
5. Conversations persist across mode switches; the last active session auto-loads
6. RAG memory is client-side only (no embedding endpoint required on the server)

#### Persona Templates

Before creating or editing characters, you can create reusable persona templates from Settings:

1. Go to Settings → Persona Templates → "New Persona Template"
2. Give it a name (e.g., "Soldier", "Detective") and write a user persona description
3. When creating or editing a character, select the template from the dropdown to pre-fill the persona

#### Alternate Greetings

Characters can have multiple opening messages:

1. In the character creation wizard (step 2) or edit dialog, add alternate greetings (one per line)
2. When viewing a character's chat, alternate greetings appear as selectable chips above the prompt input
3. Selecting one starts a new conversation with that greeting

## Architecture

- **Hybrid Clean Architecture / MVVM** with `Provider` + `ChangeNotifier` state management
- **No codegen** — all JSON serialization is manual (`jsonEncode`/`jsonDecode` + `toMap()`/`fromMap()`)
- **Dependency wiring** in `lib/main.dart` via constructor injection
- **Four root providers**: `SettingsViewModel`, `ChatViewModel`, `RoleplayViewModel`, `PersonaTemplateViewModel`
- **SQLite** via `sqflite` (desktop uses `sqflite_common_ffi`, mobile uses native)
- **Streaming** via Server-Sent Events with 20ms UI throttling to prevent frame drops
- **Thread isolation**: `ChatThread.characterId` distinguishes assistant vs roleplay threads
- **FileSaver**: Native mobile save dialogs via platform channels (Android SAF, iOS UIDocumentPicker); desktop falls back to app documents directory
- **SillyTavern Import**: `lib/core/utils/silly_tavern_card_parser.dart` parses `chara_card_v2` JSON; extracts `system_prompt`, `post_history_instructions`, and `alternate_greetings` in addition to core fields. `lib/core/utils/st_avatar_downloader.dart` fetches avatars; auto-edit dialog for imported characters via `CharacterEditDialog` (proper StatefulWidget)
- **Character system prompt override**: If a character has a `systemPrompt`, it replaces the default prompt. Use `{{original}}` prefix to prepend to the standard prompt. `postHistoryInstructions` are appended after every AI response.
- **Persona Templates**: Global reusable user personas stored in SharedPreferences. Applied via dropdown selector in character creation, editing, and SillyTavern import dialogs. `CharacterEditDialog` uses `context.watch` for reactive template loading.
- **`{{char}}` / `{{user}}` replacement**: Parser automatically substitutes these tokens with the character name and user persona in all fields, including system prompt and post history instructions.

## Development

```bash
flutter analyze        # lint + typecheck
flutter test           # runs all 3 test files
flutter run            # launch app
```

### Testing

4 test files cover: `GenerationParams` serialization, `SseClient` parsing, a widget render, and the `CharacterEditDialog` persona template loading. No tests exist for ViewModels, Repositories, or API services.

## Gotchas

- **Conversation branching**: Regenerate and edit operations truncate at the parent message and create new sibling branches. Navigation between variants uses `variantIndex` + `siblingIds`.
- **Android networking**: `127.0.0.1` refers to the Android device's loopback, not your host machine. Use `10.0.2.2` for the Android emulator or your host's LAN IP for physical devices.
- **SQLite desktop FFI**: On Linux/Windows/macOS, `sqflite_common_ffi` is initialized **once** in `main.dart` (`_initSqliteFfi()`). Do not call `sqfliteFfiInit()` again — it will trigger a warning.
- **Database migration**: DB schema is version 5. If you encounter schema errors, clear the app's local storage or delete `clan_ai.db`.
- **Roleplay thread separation**: `ChatViewModel.loadThreads()` filters out threads with `characterId != null` (roleplay threads). `RoleplayViewModel.loadLastChat()` loads threads with `characterId != null` (or falls back for legacy threads).
- **RAG isolation**: Each character's embeddings are stored with `character_id` in the vector store. Queries are strictly `WHERE character_id = ?` — no cross-character memory leakage.
- **Export**: Chat export is only available via context menus in the chat drawer and character drawer. On mobile, tapping export opens a native save dialog (Android SAF / iOS UIDocumentPicker) so users choose the destination. On desktop, files write to the app documents directory.
- **Roleplay system prompt**: In roleplay mode the system prompt is fully managed by the RAG context builder, which respects per-character `systemPrompt` overrides and appends `postHistoryInstructions`. The System Prompt Customization section in Settings is hidden when roleplay mode is active.
- **Character fields**: `CharacterProfile` now includes `systemPrompt` (per-character system prompt override), `postHistoryInstructions` (text appended after AI responses), and `alternateGreetings` (list of alternative opening messages). All stored in SharedPreferences as JSON.
- **SillyTavern parser**: `ParsedCharacterCard` now extracts `system_prompt`, `post_history_instructions`, and `alternate_greetings` from SillyTavern `.json` files. The `system_prompt` may start with `{{original}}` to prepend to the default prompt.

## License

This project is licensed under the [MIT License](LICENSE).
