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
| Web (PWA) | Beta |

## Installation

### Windows

**Option A: Self-extracting installer (Recommended)**

Download `CLAN-AI_Setup.exe` from the [GitHub Releases](https://github.com/CyberShockwave159/CLAN-AI/releases) page.

1. Double-click the installer — it installs to `%LOCALAPPDATA%\Programs\CLAN-AI\` (no admin rights needed)
2. A desktop shortcut and Start Menu entry are created automatically
3. The installer enables sideloading on first run (required for self-signed certificate)

**Option B: MSIX package**

Download `clan_ai_*.msix` from the [GitHub Releases](https://github.com/CyberShockwave159/CLAN-AI/releases) page.

1. Double-click the `.msix` file — Windows will prompt to install
2. Or via PowerShell: `Add-AppxPackage -Path clan_ai_*.msix`
3. If prompted about sideloading, enable it in **Settings → Apps → Developer Options → App Development Licenses**

**Option C: Build from source**

```powershell
# Install Flutter SDK: https://docs.flutter.dev/get-started/install/windows
git clone https://github.com/CyberShockwave159/CLAN-AI.git
cd clan_ai
flutter pub get
flutter build windows --release

# Build NSIS installer (requires NSIS: https://nsis.sourceforge.io/Download)
.\scripts\build-windows-installer.bat
```

This produces `CLAN-AI_Setup.exe` in the `dist/` directory.

**Requirements:** Windows 10 (version 1809) or later, 64-bit processor.

**Verify installer integrity:**
```powershell
certutil -hashfile CLAN-AI_Setup.exe SHA256
```
Compare with the hash in `checksums.sha256` on the release page.

### Linux (Desktop)

**From source**

```bash
# Install Flutter SDK first: https://docs.flutter.dev/get-started/install/linux
git clone https://github.com/CyberShockwave159/CLAN-AI.git
cd clan_ai
flutter pub get
flutter run -d linux
```

> Flatpak packaging is planned. No published Flatpak package is available yet.

### macOS (Desktop)

```bash
# Install Flutter SDK first: https://docs.flutter.dev/get-started/install/macos
git clone https://github.com/CyberShockwave159/CLAN-AI.git
cd clan_ai
flutter pub get
flutter run -d macos
```

You may need to ungate the app on first launch:
```bash
xattr -d com.apple.quarantine build/macos/Build/Products/Release/clan_ai.app
```

### Android

```bash
# Connect device via USB with USB debugging enabled
flutter pub get
flutter run -d <android-device-id>
```

Or build an APK:
```bash
flutter build apk --release
```

### iOS

```bash
# Requires macOS
flutter pub get
flutter run -d <ios-device-id>
```

Or build an IPA:
```bash
flutter build ios --release
```

### Web (PWA)

CLAN AI builds as a Progressive Web App — an installable, standalone app served from any static host. SQLite and RAG run in the browser (WASM, persisted to IndexedDB); SSE token streaming uses a `fetch` + `ReadableStream` transport.

**Run locally:**

```bash
flutter pub get
flutter run -d chrome            # debug with hot reload
# or build and serve the release:
flutter build web --release --no-web-resources-cdn
python3 -m http.server 8080 --directory build/web
# open http://localhost:8080
```

`--no-web-resources-cdn` bundles CanvasKit locally instead of loading it from Google's CDN — required for the offline app shell. (CI builds with the same flag.)

**Install as a PWA:** open the served app in Chrome/Edge → the install icon appears in the address bar (or **⋮ → Install app / Cast, save & share → Install**). It launches in its own standalone window. After the first successful load, the app shell (Dart code, sqlite WASM + SharedWorker, local CanvasKit) is served from CLAN AI's service worker cache (`web/clan_ai_sw.js`), so reloads work offline; chat history lives in IndexedDB and persists too. Runtime-fetched Google Fonts are cached by the browser's HTTP cache, not the service worker. Live inference still needs a reachable server.

**Connect to your llama.cpp server** — browsers enforce CORS and HTTPS/mixed-content rules:

1. Start the server with CORS enabled for the app's origin:
   ```bash
   llama-server --host 0.0.0.0 --port 8080 --cors-origins http://localhost:8080
   ```
   (Use your deployed app's origin if hosted elsewhere — e.g. `--cors-origins https://your-app.example.com`. `Authorization` headers are handled by the preflight automatically.)

2. **Mixed content:** an HTTPS-hosted app **cannot** talk to `http://<LAN-IP>:8080`. Either deploy the app on the same machine (localhost) or serve the app and server over HTTPS.

3. Set the **Base URL** in Settings to your server (e.g. `http://localhost:8080`).

**Data isolation:** web data lives in the browser origin's IndexedDB (scoped to origin **and port**), separate from the desktop `.db` files. Use **Export → JSON** on one platform and **Import** on the other to move chats, characters, and RAG memories. Attachments are stored in a second IndexedDB-backed database and count toward the browser's storage quota (typically at least a few hundred MB in Chrome; a few MB of images is comfortable).

> Opera also supports `--cors-origins`; if you use a different OpenAI-compatible backend, enable its equivalent CORS setting.

**LAN deployment with HTTPS (mkcert + Caddy):**

For multi-device LAN access with a green lock on every device:

1. **Install mkcert** (creates locally-trusted self-signed CA):
   ```bash
   curl -s https://dl.filippo.io/mkcert/latest?for=linux/amd64 | sudo chmod +x /usr/local/bin/mkcert
   sudo apt install libnss3-tools   # for trust on Linux
   mkcert -install
   ```

2. **Generate certificates** for your LAN hostnames:
   ```bash
   mkcert "*.lan" "*.local" "192.168.1.42"
   # Produces: _cert.pem and _key.pem
   ```

3. **Serve the app** with Caddy (`/etc/caddy/Caddyfile`):
   ```
   https://clan-lan {
       root * /var/www/clan-ai
       file_server
       tls /path/to/_cert.pem /path/to/_key.pem
   }
   ```
   Start: `sudo caddy run --config /etc/caddy/Caddyfile`

4. **Start llama-server** with CORS for the app's origin:
   ```bash
   llama-server --host 0.0.0.0 --port 8080 \
     --cors-origins http://clan-lan:443
   ```
   (Or if your app runs on a different port, e.g. 8082: `--cors-origins https://clan-lan:8082`.)

5. **Connect** each device on the LAN by browsing to `https://clan-lan` (or whatever hostname you configured). The mkcert CA is trusted by the OS, so no browser warnings.

For a reverse proxy setup (app + server on the same domain), Caddy can proxy both:
```
https://clan-lan {
    # App
    handle_path /app/* {
        root * /var/www/clan-ai
        file_server
    }

    # llama.cpp proxy
    handle_path /api/* {
        reverse_proxy http://127.0.0.1:8080
    }

    tls /path/to/_cert.pem /path/to/_key.pem
}
```
Set the Base URL in Settings to `https://clan-lan/api/` and point your llama-server `--cors-origins` to `https://clan-lan`.

**Firefox support:** CLAN AI works in Firefox. Service workers, IndexedDB, WASM, and `fetch`/`ReadableStream` are all supported. Debug via `about:debugging` (service workers) and DevTools → Storage (IndexedDB). Install via the browser's "Add CLAN AI" menu entry.

### Development Builds

To build any platform from source:
```bash
flutter pub get
flutter build <platform> --release
```

Supported build targets: `linux`, `macos`, `windows`, `apk` (Android), `ios`, `web`.

## Features

- Real-time streaming chat over OpenAI-compatible endpoints
- **Progressive Web App** — Installable web build (manifest + icons, standalone launch, offline app-shell). SQLite (WASM) and SSE streaming run entirely in-browser; data persists in the origin's IndexedDB.
- **Server Health Status** — Chat and roleplay screens display a red warning banner when server is unreachable, with quick link to Settings
- **Reasoning/Thinking Block View** — Toggle in Settings to request and display model reasoning/thinking as a collapsible block. Supports dedicated reasoning fields (`delta.reasoning`), inline tags (```xml, `<thought>`), and multiple field name conventions across models
- **AI Roleplay Mode** — Toggle from Settings; mirrors assistant mode UI with per-character isolated sessions and client-side RAG memory
- **Character Creation** — 4-step wizard (personality, setting/world, persona name + description, advanced prompt settings) with optional avatar upload and persona template selector
- **SillyTavern Import** — Import `.json` character cards (`chara_card_v2` format) with auto-edit dialog; extracts system prompt override, post history instructions, and alternate greetings
- **Persona Templates** — Create reusable user personas in Settings; any character can select a template to pre-fill its user persona
- **Alternate Greetings** — Characters can have multiple opening messages shown as selectable chips above the prompt input
- **Character System Prompt Override** — Per-character system prompts with `{{original}}` prefix support to prepend to default prompt
- **Post History Instructions** — Additional text appended after each AI response for style reminders or state tracking
- Client-Side RAG — Pure Dart feature hashing embeddings (256-dim, char trigrams) with SQLite cosine similarity; zero ML dependencies. Configurable Top-K (1-10) and minimum relevance threshold (0.0-1.0) in Generation Parameters sheet
- **Conversation branching** — Regenerate and edit responses create sibling variants. All variants share a complete `siblingIds` array. Navigation loads siblings from DB, sorts by `variantIndex`, and indexes into the sorted list via `ChatRepository.getAllMessagesForThread()` (bypasses message deduplication).
- **Image attachments** — Attach one image per user message (chat & roleplay). Images are stored on disk with only the absolute path in SQLite, sent as base64 `image_url` content parts over the OpenAI-compatible API (works with any vision-capable backend), tap to view in a full-screen lightbox, and auto-cleaned when messages/threads are deleted. Magic-byte sniffing detects the true format even when the file extension lies.
- SQLite local persistence with full thread/message history (schema v13)
- Automatic server health polling with fallback endpoints (`/health` → `/props` → `/v1/models`)
- Dark mode by default (OLED-optimized), configurable light and custom themes
- Custom theme presets (Warm, Cool, Pastel) with persisted user color selections
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
flutter run -d chrome                # Web (PWA) — see "Web (PWA)" below
flutter run -d <android-device-id>   # Android device/emulator
```

## Configuration

On first launch, open Settings from the side drawer and configure your llama.cpp server:

1. **Base URL** — Enter your server address:
   - Desktop: `http://localhost:8080`
   - Android emulator: `http://10.0.2.2:8080`
   - Android physical device: `http://<host-lan-ip>:8080`
   - iOS simulator: `http://localhost:8080`
   - Web: `http://localhost:8080` (server must run with `--cors-origins` for the app's origin — see [Web (PWA)](#web-pwa))
2. **Model** — Select a model from the auto-discovered list
3. Test the connection, then start chatting

### Roleplay Mode

Toggle "Roleplay Mode" in Settings to switch to character roleplay:

1. Open the sidebar (hamburger menu)
2. Tap "New Roleplay" to create a character manually, or "Import ST Card" to import a SillyTavern `.json` character card
3. SillyTavern cards (`chara_card_v2` spec) are automatically parsed — `{{char}}` and `{{user}}` tokens are replaced with the character name and user persona (or explicit Persona Name if set). The prompt input placeholder shows "Reply as \<persona name\>..." using the character's Persona Name field
4. Characters are listed in the sidebar; tap a character to start a session
5. Conversations persist across mode switches; the last active session auto-loads
6. RAG memory is client-side only (no embedding endpoint required on the server)

#### Persona Templates

Reusable user personas with three distinct fields:

1. Go to Settings → Persona Templates → "New Persona Template"
2. Fill in **Template Name** (display name for dropdown), **Persona Name** (name used when character refers to you), and **Persona Description** (full persona description)
3. When creating or editing a character, select the template from the dropdown — it populates both the Persona Name and Persona Description fields

#### Alternate Greetings

Characters can have multiple opening messages:

1. In the character creation wizard (step 2) or edit dialog, add alternate greetings (one per line)
2. When viewing a character's chat, alternate greetings appear as selectable chips above the prompt input (only visible before the user has replied — disappears after first user message)
3. Selecting one starts a new conversation branch with that greeting as the opening message (always creates a new thread, never reuses existing)

## Architecture

- **Hybrid Clean Architecture / MVVM** with `Provider` + `ChangeNotifier` state management
- **No codegen** — all JSON serialization is manual (`jsonEncode`/`jsonDecode` + `toMap()`/`fromMap()`)
- **Shared constants** in `lib/core/constants/app_constants.dart` — all magic numbers and default strings centralized
- **Shared mixin** `StreamMutationMixin` in `lib/ui/shared/mixins/stream_mutation_mixin.dart` — provides streaming, undo, switchVariant, stopGeneration logic for both ChatViewModel and RoleplayViewModel
- **Shared settings sections** in `lib/ui/features/settings/views/sections/` — `profile_section.dart`, `safety_section.dart`, `app_mode_section.dart`, `theme_section.dart`
- **ServerProfile consolidation:** `ServerConnectionDetails` removed; `ServerProfile` serves as connection details throughout
- **Dependency wiring** in `lib/main.dart` via constructor injection
- **Four root providers**: `SettingsViewModel`, `ChatViewModel`, `RoleplayViewModel`, `PersonaTemplateViewModel`
- **SQLite** via `sqflite` (desktop uses `sqflite_common_ffi`, mobile uses native, web uses `sqflite_common_ffi_web` — WASM in-browser engine persisted to IndexedDB), schema version 13 (`threads`, `messages` with `variant_index`/`total_variants`/`sibling_ids` for conversation branching and `image_path` for image attachments, `characters`, `persona_templates` tables). Web attachments live in a second `clan_ai_attachments.db` (BLOB store, same persistence).
- **Secure API keys** stored in OS Keychain/KeyStore via `SecureStorageService` (`flutter_secure_storage`); on web the plugin falls back to localStorage-grade storage (obfuscated, not vault-grade)
- **Single `CharacterRepository`** instance injected via constructor throughout the app
- **Streaming** via Server-Sent Events with 20ms UI throttling to prevent frame drops
- **Theme system**: `AppThemeMode` enum (dark/light/custom) with `CustomThemeColors` presets (Warm, Cool, Pastel). `ClanThemeColors` ThemeExtension on all `ThemeData` instances enables theme-aware color lookups (`context.clanTextPrimary`, `context.clanSurfaceVariant`, etc.). Custom theme colors persist to SharedPreferences. Settings → Theme section at bottom of settings screen.
- **Reasoning pipeline**: `SseClient.parseStream()` extracts reasoning from multiple field names (`reasoning`, `reasoning_content`, `thought`). `SseClient.filterReasoning()` processes inline thinking tags and forwards dedicated reasoning fields through a stream pipeline. The OpenAI-compatible protocol supports the `reasoning` parameter.
- **Thread isolation**: `ChatThread.characterId` distinguishes assistant vs roleplay threads
- **FileSaver**: Native mobile save dialogs via platform channels (Android SAF, iOS UIDocumentPicker); desktop falls back to app documents directory; web triggers a browser download (`Blob` + object URL)
- **SillyTavern Import**: `lib/core/utils/silly_tavern_card_parser.dart` parses `chara_card_v2` JSON; extracts `system_prompt`, `post_history_instructions`, and `alternate_greetings` in addition to core fields. Import opens an auto-edit dialog via `CharacterEditDialog` (proper StatefulWidget)
- **Memory chip**: Assistant messages display a memory chip showing count of RAG memories used. Tapping reveals the actual memory content that was injected into the system prompt. `ragMemoryContents` field stores JSON-encoded memory strings on `ChatMessage`
- **Memory management**: `lib/ui/features/roleplay/widgets/character_memories_dialog.dart` — Per-character memory viewer and pruner. List all vector embeddings for a character; delete individual memories or clear all. Accessible via character popup menu → "Manage Memories"
- **Configurable RAG**: `GenerationParams` includes `ragTopK` (1-10) and `ragMinScore` (0.0-1.0). Adjustable in Settings → Generation Parameters. `RoleplayContextBuilder` filters memories by minimum similarity score
- **Character system prompt override**: If a character has a `systemPrompt`, it replaces the default prompt. Use `{{original}}` prefix to prepend to the standard prompt. `postHistoryInstructions` are appended after every AI response.
- **Persona Templates**: Global reusable user personas stored in SQLite (persona_templates table). Applied via dropdown selector in character creation, editing, and SillyTavern import dialogs. `CharacterEditDialog` uses `context.watch` for reactive template loading.
- **`{{char}}` / `{{user}}` replacement**: Parser automatically substitutes these tokens with the character name and user persona in all fields, including system prompt and post history instructions.
- **Keyboard Shortcuts Help**: Press `Ctrl+/` or `F1` to open the ShortcutsHelpDialog showing all keyboard shortcuts. Platform-aware labels (`Cmd` on macOS, `Ctrl` on other platforms).

## Development

### Building the Windows Installer (.exe)

To create a distributable Windows installer from a Windows machine:

1. Install [NSIS](https://nsis.sourceforge.io/Download) (adds `makensis` to PATH)
2. Run the build script from the project root:

```powershell
.\scripts\build-windows-installer.bat
```

Or on Linux/macOS (produces MSIX only, NSIS is Windows-only):
```bash
./scripts/build-windows-installer.sh
```

This produces files in the `dist/` directory:
- `CLAN-AI_Setup.exe` — NSIS installer (bundles MSIX, creates Start Menu shortcut, enables sideloading)
- `clan_ai_*.msix` — MSIX package (standalone install)
- `checksums.sha256` — SHA-256 verification hashes
- `README.txt` — Installation instructions

**CI/CD:** Pushing to `main`/`master` triggers an automated Windows build in GitHub Actions. Build artifacts are uploaded as downloadable files on the [Releases](https://github.com/CyberShockwave159/CLAN-AI/releases) page. The web app is built by `.github/workflows/build-web.yml` on every push/PR (`flutter analyze` + `flutter test` + `flutter build web --release --no-web-resources-cdn`, artifact upload); a manual `workflow_dispatch` run with **deploy_pages** checked deploys it to GitHub Pages at `https://<user>.github.io/CLAN-AI/`.

```bash
flutter analyze        # lint + typecheck
flutter test           # runs all 28 test files (505 total tests)
flutter run            # launch app
```

### Testing

28 test files, 505 total tests. All tests use fake repositories (no real SQLite or network). ViewModels expose private state via setters for test injection.

**Coverage by layer:**
- **Domain** — `GenerationParams` serialization (OpenAI payloads, TextSanitizer segment parsing, reasoning flags), model roundtrip serialization (ChatThread, ChatMessage, CharacterProfile, PersonaTemplate, ServerConfig)
- **Network** — `SseClient` parsing (OpenAI deltas, ping comments, multi-line data, multi-field reasoning extraction, `filterReasoning` inline tag processing)
- **Utilities** — Roleplay prompt formatter, context builder, hash embedding, vector store, SillyTavern card parser, conversation export
- **Mixins** — StreamMutationMixin (streaming, undo, stop, switchVariant with complete siblingIds propagation and DB sorting)
- **Repositories** — ChatRepository, CharacterRepository (thread/message CRUD, favorites, embeddings, `getAllMessagesForThread` for variant navigation)
- **ViewModels** — ChatViewModel, RoleplayViewModel, SettingsViewModel, PersonaTemplateViewModel
- **Widgets** — MessageBubble (reasoning block expand/collapse), CharacterEditDialog (persona template loading), AlternateGreetingSelector
- **Integration** — Assistant chat flow, roleplay flow, character lifecycle, persona defaults, settings persistence

## Gotchas

- **Conversation branching**: Regenerate and edit operations truncate at the parent message and create new sibling branches. Navigation between variants uses `variantIndex` + `siblingIds`. All variants in a regeneration group share a complete `siblingIds` array. `doSwitchVariant` loads all siblings from DB, sorts by `variantIndex`, and indexes into the sorted list. Regenerate builds a complete `allSiblingIds` set (filtered by `role == assistant` and shared `parentId`) and assigns it to every variant. Branches are linked via `branchFromThreadId` on `ChatThread`. In roleplay mode, the first assistant message (character's greeting) has the regenerate button disabled until the user has replied.
- **Android networking**: `127.0.0.1` refers to the Android device's loopback, not your host machine. Use `10.0.2.2` for the Android emulator or your host's LAN IP for physical devices.
- **SQLite desktop FFI**: On Linux/Windows/macOS, `sqflite_common_ffi` is initialized **once** in `main.dart` (`_initSqliteFfi()`). Do not call `sqfliteFfiInit()` again — it will trigger a warning. On web the same function binds the WASM factory (`databaseFactoryFfiWeb` from `sqflite_common_ffi_web`) — native path is untouched.
- **Database migration**: DB schema is version 13 (added `image_path` to messages in v13, `variant_index`, `total_variants`, `sibling_ids` columns to messages table for conversation branching in v12, `persona_name` to `persona_templates` in v11, `persona_name`/`persona_description` to `characters` in v10). If you encounter schema errors, clear the app's local storage or delete `clan_ai.db`.
- **Reasoning block streaming**: The `ReasoningBlock` widget displays thinking/reasoning content when the "View Thinking" toggle is enabled in Settings. Models can provide reasoning via dedicated fields (`delta.reasoning`, `delta.reasoning_content`, `delta.thought`) or inline tags (```xml, `<thought>`, `<reasoning>`). The `filterReasoning` stream pipeline handles both formats. Older llama.cpp versions may not return reasoning content.
- **Roleplay thread separation**: `ChatViewModel.loadThreads()` filters out threads with `characterId != null` (roleplay threads). `RoleplayViewModel.loadLastChat()` loads threads with `characterId != null` (or falls back for legacy threads).
- **RAG isolation**: Each character's embeddings are stored with `character_id` in the vector store. Queries are strictly `WHERE character_id = ?` — no cross-character memory leakage.
- **RAG params**: `ragTopK` (default 3) controls how many memories are retrieved. `ragMinScore` (default 0.0) filters memories below this cosine similarity threshold. Both configurable in Settings → Generation Parameters. `RoleplayContextBuilder.build()` accepts these as parameters.
- **Memory chip**: Assistant messages show a chip with `ragMemoryCount` when RAG memories were injected. Tapping displays the actual memory content from `ragMemoryContents` field (JSON-encoded list). `vector_store.getAllMemories()` lists all embeddings for a character.
- **Export**: Chat export is only available via context menus in the chat drawer and character drawer. On mobile, tapping export opens a native save dialog (Android SAF / iOS UIDocumentPicker) so users choose the destination. On desktop, files write to the app documents directory. On web, export triggers a browser download (a "Downloaded <file>" snackbar confirms it).
- **Web — CORS**: Browsers enforce CORS. Run llama.cpp with `--cors-origins <app-origin>` (e.g. `llama-server --cors-origins http://localhost:8080`). An HTTPS-hosted app cannot fetch a plain `http://` LAN server (mixed content / Private Network Access) — serve the app locally or over HTTPS with the server.
- **Web — data isolation & persistence**: All web data lives in the browser origin's IndexedDB, scoped to **origin + port** (e.g. `localhost:8080` ≠ `localhost:8081`; see plan §3.1 #4). It is completely separate from desktop `.db` files — use JSON Export/Import as the migration bridge. Chat history persists across reloads and offline app-shell launches as long as you use the same origin/port.
- **Web — secure storage**: `flutter_secure_storage` works in the browser but is **localStorage-grade** security (obfuscated, not Keychain/KeyStore-grade). Consider it obfuscation, not a secure vault, on web.
- **Web — SQLite WASM pair**: `web/sqlite3.wasm` + `web/sqflite_sw.js` are a locked pair, committed in the repo. Re-run `dart run sqflite_common_ffi_web:setup --force` after any `sqflite*`/`sqlite3` resolution change, or the app crashes at boot with a WebAssembly import error. Attachments live in a separate `clan_ai_attachments.db` and count toward the browser storage quota.
- **Roleplay prompt placeholder**: The input field shows "Reply as \<persona name\>..." where \<persona name\> comes from the character's Persona Name field (falls back to "you" if unset).
- **Roleplay system prompt**: In roleplay mode the system prompt is fully managed by the RAG context builder, which respects per-character `systemPrompt` overrides and appends `postHistoryInstructions`. The System Prompt Customization section in Settings is hidden when roleplay mode is active.
- **Character fields**: `CharacterProfile` now includes `systemPrompt` (per-character system prompt override), `postHistoryInstructions` (text appended after AI responses), `alternateGreetings` (list of alternative opening messages), `personaName` (explicit name for `{{user}}` replacement), and `personaDescription` (full persona description). Stored in SQLite `characters` table (migrated from SharedPreferences in v8).
- **SillyTavern parser**: `ParsedCharacterCard` extracts `system_prompt`, `post_history_instructions`, `alternate_greetings`, `user_persona`, `persona_name`, and `persona_description` from SillyTavern `.json` files. The `system_prompt` may start with `{{original}}` to prepend to the default prompt. All truncation limits removed — full content preserved.

## License

This project is licensed under the [MIT License](LICENSE).
