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
- Conversation branching — regenerate and edit responses to create sibling variants
- SQLite local persistence with full thread/message history
- Automatic server health polling with fallback endpoints (`/health` → `/props` → `/v1/models`)
- Dark mode by default (OLED-optimized), configurable system prompt
- Markdown, code block, and LaTeX math rendering in responses
- Token speed and performance metrics per generation

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) (Dart SDK ^3.13.0)
- A running llama.cpp server (with API endpoints enabled)

## Getting Started

```bash
# Clone and fetch dependencies
git clone https://github.com/cybershockwave159/CLAN-AI.git
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

## Architecture

- **Hybrid Clean Architecture / MVVM** with `Provider` + `ChangeNotifier` state management
- **No codegen** — all JSON serialization is manual (`jsonEncode`/`jsonDecode` + `toMap()`/`fromMap()`)
- **Dependency wiring** in `lib/main.dart` via constructor injection
- **Two root providers**: `SettingsViewModel`, `ChatViewModel`
- **SQLite** via `sqflite` (desktop uses `sqflite_common_ffi`, mobile uses native)
- **Streaming** via Server-Sent Events with 20ms UI throttling to prevent frame drops

## Development

```bash
flutter analyze        # lint + typecheck
flutter test           # runs all 3 test files
flutter run            # launch app
```

### Testing

3 test files cover: `GenerationParams` serialization, `SseClient` parsing, and a widget render. No tests exist for ViewModels, Repositories, or API services.

## Gotchas

- **Conversation branching**: Regenerate and edit operations truncate at the parent message and create new sibling branches. Navigation between variants uses `variantIndex` + `siblingIds`.
- **Android networking**: `127.0.0.1` refers to the Android device's loopback, not your host machine. Use `10.0.2.2` for the Android emulator or your host's LAN IP for physical devices.
- **SQLite desktop FFI**: On Linux/Windows/macOS, `sqflite_common_ffi` must be initialized before any database calls. Handled automatically in `LocalDatabase`.
- **Database migration**: DB schema is version 3. If you encounter schema errors, clear the app's local storage or delete `clan_ai.db`.

## License

This project is licensed under the [MIT License](LICENSE).
