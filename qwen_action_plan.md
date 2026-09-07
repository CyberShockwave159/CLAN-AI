# CLAN-AI Development & Hardening Action Plan

This document contains prioritized, actionable technical specifications tailored for execution by an automated coding agent (e.g., Qwen 3.6 / OpenCode). Each task includes exact file locations, context, proposed changes, and verification criteria.

---

## Architecture & Codebase Context Summary
- **Framework:** Flutter 3.27+ (Dart 3.6+)
- **Architecture:** Hybrid Clean Architecture / MVVM with `Provider` + `ChangeNotifier`.
- **Database:** SQLite schema v9 (`LocalDatabase`) + `VectorStore` (embeddings in separate SQLite file) + `SharedPreferences` (server profiles, prompt templates, app settings).
- **Core State:** `SettingsViewModel`, `ChatViewModel`, `RoleplayViewModel`, `PersonaTemplateViewModel`.
- **Testing:** `flutter test` (all 28 test suites must pass without regressions).

---

## Phase 1: CI/CD & Security Hardening (Priority: Critical)

### Task 1.1: Fix Tagged Release Workflow Trigger
- **Target File:** `.github/workflows/build-windows.yml`
- **Issue:** The `on.push` trigger only triggers on `branches: [main, master]`. When release tags (e.g. `v1.0.6`) are pushed, the workflow never triggers, causing GitHub Releases to remain empty with no built installer assets (`.exe` / `.msix`).
- **Required Changes:**
  Add `tags: ['v*']` to the `on.push` triggers in `.github/workflows/build-windows.yml`.
  ```yaml
  on:
    push:
      branches: [main, master]
      tags: ['v*']
      paths-ignore:
        - '**.md'
        - 'docs/**'
    pull_request:
      branches: [main, master]
    workflow_dispatch:
  ```
- **Verification:**
  - Validate YAML syntax.
  - Pushing a tag like `v1.0.6` matches the `startsWith(github.ref, 'refs/tags/')` condition and triggers the Windows build + MSIX + NSIS installer + release asset upload.

---

### Task 1.2: Restrict Android Cleartext Traffic Policy
- **Target File:** `android/app/src/main/res/xml/network_security_config.xml`
- **Issue:** Currently, `<base-config cleartextTrafficPermitted="true">` allows unencrypted HTTP traffic to any external domain on the internet.
- **Required Changes:**
  - Set `base-config cleartextTrafficPermitted="false"`.
  - Whitelist cleartext HTTP only for `localhost`, `127.0.0.1`, `10.0.2.2` (Android emulator loopback), and local LAN IP ranges (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`).
- **Example Implementation:**
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <network-security-config>
      <!-- Base config: force HTTPS for public web & remote APIs -->
      <base-config cleartextTrafficPermitted="false">
          <trust-anchors>
              <certificates src="system" />
              <certificates src="user" />
          </trust-anchors>
      </base-config>

      <!-- Cleartext permitted only for local / LAN servers -->
      <domain-config cleartextTrafficPermitted="true">
          <domain includeSubdomains="true">localhost</domain>
          <domain includeSubdomains="true">127.0.0.1</domain>
          <domain includeSubdomains="true">10.0.2.2</domain>
      </domain-config>

      <debug-overrides>
          <trust-anchors>
              <certificates src="user" />
          </trust-anchors>
      </debug-overrides>
  </network-security-config>
  ```
- **Verification:**
  - Local endpoint testing: Android build compiles with valid XML resource.

---

## Phase 2: First-Run & Empty-State Experience (Priority: High)

### Task 2.1: Guided Inline Server Setup Card on Empty State
- **Target File:** `lib/ui/features/chat/views/chat_screen.dart` (`_buildEmptyState` method)
- **Issue:** First-time users or users with an offline server are presented with generic prompt suggestions and a small warning bar. They must manually find the Settings drawer and figure out the Base URL configuration.
- **Required Changes:**
  1. When `chatVM.messages.isEmpty` and `settingsVM.config.healthStatus != ServerHealthStatus.connected`:
     - Render an attractive "Quick Connect" card in place of or above the prompt chips.
     - Include preset quick-select buttons for common local configurations:
       - `llama.cpp Default`: `http://127.0.0.1:8080`
       - `Android Emulator`: `http://10.0.2.2:8080`
       - `Ollama`: `http://127.0.0.1:11434`
       - `LM Studio`: `http://127.0.0.1:1234`
     - Provide an inline text input field pre-filled with the current base URL and a primary "Connect / Test" button.
     - Display immediate visual feedback (latency ms badge if connected, clear error explanation if failing).
  2. Maintain standard starter prompt chips when the server status is `ServerHealthStatus.connected`.
- **Verification:**
  - Launch app with offline server → Quick connect card displays.
  - Selecting preset chip updates URL field.
  - Clicking "Connect / Test" pings server and updates status dynamically.

---

## Phase 3: Diagnostics & Power-User Tools (Priority: Medium)

### Task 3.1: Differentiated Connection Diagnostics
- **Target Files:**
  - `lib/core/utils/latency_meter.dart`
  - `lib/ui/features/settings/view_models/settings_view_model.dart`
  - `lib/ui/features/settings/views/settings_screen.dart`
- **Issue:** All connection failures return a raw exception string (e.g. `ClientException with SocketException: Connection refused (OS Error: Connection refused, errno = 111)`), which is confusing to regular users.
- **Required Changes:**
  Parse error types in `LatencyMeter.ping()` or `SettingsViewModel.testConnection()` to produce user-friendly guidance:
  - `SocketException` / `Connection refused`: *"Connection refused. Ensure your LLM server (e.g. llama.cpp) is running on this port."*
  - `TimeoutException`: *"Connection timed out. Check the IP address and firewall settings."*
  - `HandshakeException` / SSL errors: *"SSL/TLS certificate error. Use http:// for local servers or check HTTPS certificates."*
  - HTTP 401 / 403: *"Authentication failed. Please verify your API key in Settings."*
  - HTTP 404: *"Endpoint not found. Check if the server protocol (OpenAI vs native llama.cpp) is correct."*
- **Verification:**
  - Unit tests in `test/core/utils/latency_meter_test.dart` (or new test) verifying error mapping.

### Task 3.2: Desktop Keyboard Shortcut Discoverability
- **Target File:** `lib/ui/shared/app_header.dart`
- **Issue:** Keyboard shortcuts (`Ctrl+N`, `Ctrl+K`, `Ctrl+,`, `Ctrl+/`, `Escape`) are implemented in `desktop_keyboard_shortcuts.dart` but have low discoverability.
- **Required Changes:**
  - On desktop platforms (`Platform.isLinux || Platform.isWindows || Platform.isMacOS || kIsWeb`), add an `IconButton(icon: Icon(Icons.keyboard_outlined), tooltip: 'Keyboard Shortcuts (Ctrl+/)')` to `AppHeader` action buttons.
  - Clicking the icon opens `ShortcutsHelpDialog(context)`.
- **Verification:**
  - Desktop header displays keyboard button. Clicking displays shortcuts help modal.

### Task 3.3: "Copy Full Generation Context" Debug Action
- **Target Files:**
  - `lib/ui/features/chat/views/message_bubble.dart`
  - `lib/ui/shared/widgets/drawer_export_menu.dart` (or message options menu)
- **Issue:** Power users and prompt engineers cannot easily inspect the exact compiled payload sent to the LLM (resolved system prompt + RAG injected memories + model parameters).
- **Required Changes:**
  - Add a *"Copy Debug Context"* action to the message context menu for assistant messages or within thread export options.
  - Copies formatted JSON/Markdown containing:
    ```json
    {
      "model": "...",
      "systemPrompt": "...",
      "ragMemories": ["..."],
      "params": { "temperature": 0.7, "contextSize": 4096 },
      "metrics": { "tokensPerSecond": 42.1, "totalTokens": 380, "generationTimeSec": 9.0 }
    }
    ```
- **Verification:**
  - Triggering the action copies valid formatted debug context to the clipboard and shows a snackbar confirmation.

---

## Phase 4: Documentation Accuracy Pass (Priority: Low / Cleanup)

### Task 4.1: Documentation Consistency Sweep
- **Target Files:**
  - `README.md`
  - `AGENTS.md`
  - `ARCHITECTURE.md`
- **Required Changes:**
  1. `README.md`:
     - Clarify Flatpak status: change `flatpak install io.github.cybershockwave159.clan_ai` to note that the Flathub package submission is in progress / provide building instructions until approved.
  2. `AGENTS.md` & `ARCHITECTURE.md`:
     - Update test count metrics to match the current test suite (`flutter test`).
     - Clarify storage split: Characters and Persona Templates are in SQLite (schema v9); Server Profiles and System Prompt Templates are stored in SharedPreferences.
- **Verification:**
  - Verify markdown links and consistency across documentation files.

---

## Execution Checklist for Coding Agent

```bash
# 1. Fetch dependencies and verify baseline
flutter pub get
flutter analyze
flutter test

# 2. Implement Task 1.1 (GitHub Workflow) & Task 1.2 (Network Security Config)
# 3. Implement Task 2.1 (Empty State Quick Connect)
# 4. Implement Task 3.1, 3.2, 3.3 (Diagnostics, Shortcuts Button, Debug Context)
# 5. Implement Task 4.1 (Docs update)

# 6. Final Validation
flutter analyze
flutter test
```
