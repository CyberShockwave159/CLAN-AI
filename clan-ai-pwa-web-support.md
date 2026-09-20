# CLAN AI — Web / PWA Support Plan

**Status:** Planning · **Author date:** 2026-09-19 · **Target SDK:** Flutter 3.47.4 (Dart 3.13.3), installed at `/home/jstanton/flutter/flutter`

## 1. Executive summary

Adding a Progressive Web App build of CLAN AI is **feasible with a portability refactor layer**, not a configuration change. The UI, state management (Provider/ChangeNotifier), SSE *parser*, RAG, branching, and error mapping are pure Dart and web-safe. The work concentrates in three areas that currently assume a native runtime:

1. **SQLite via native FFI** (`sqflite_common_ffi` + `dart:ffi`) — likely the hard compile blocker; needs a web (WASM sqlite, IndexedDB-backed) factory behind a conditional import.
2. **HTTP / SSE streaming** (`dart:io HttpClient` + `IOClient`) — `BrowserClient` buffers whole responses, so token streaming needs a custom `fetch()` + `ReadableStream` transport. **Highest-risk item.**
3. **File I/O** (attachments on disk, `File(...)` reads/writes, `path_provider`, `dart:io` in 12 files) — needs browser-analogues: IndexedDB-backed attachment store, `Image.memory`, picker `.bytes`, anchor download.

Outside the code: browsers enforce **CORS** (users must run `llama-server --cors <origin>`) and **HTTPS / mixed-content** rules (an HTTPS-hosted app cannot fetch `http://LAN-IP` llama.cpp servers). Web data lives in the browser origin's IndexedDB — isolated from the desktop `.db` (JSON import/export is the migration bridge).

Suggested delivery: Phase 0 validation spike → Phase 1 portability refactor (native behavior unchanged, 503 tests stay green) → Phase 2 PWA layer → Phase 3 QA.

---

## 2. Current-state facts driving the plan

| Area | Today | Web impact |
|---|---|---|
| `web/` directory | **Does not exist** | `flutter create --platforms web .` required |
| `sqflite_common_ffi` | `main.dart` inits FFI once; `local_storage.dart` (schema v13) + `vector_store.dart` (v2) import it | **Compiles on web as stubs** (proven in Phase 0) but `databaseFactoryFfi` throws at runtime; fix = bind `databaseFactoryFfiWeb` from `sqflite_common_ffi_web` in the web init path |
| `http_client.dart` | `IOClient(HttpClient()..connectionTimeout)`; `postStream()` returns `http.StreamedResponse` | `dart:io` construct at runtime; XHR `BrowserClient` cannot stream — need conditional `fetch`/`ReadableStream` transport and a stream result type |
| `sse_client.dart` | Pure Dart byte stream → `StreamChunk`; reasoning filtering, `CancelToken` | **Reusable unchanged** — the web transport just feeds it the same `Stream<List<int>>` |
| `MessageAttachmentStore` | Files under `<documents>/attachments/`, path in `messages.image_path` | No filesystem; keep `image_path` column as an opaque ref, back it with IndexedDB on web. Schema unchanged. |
| `Image.file(...)` | `prompt_input_bar.dart`, `message_bubble.dart` (bubble + fullscreen) | `Image.file` unsupported at runtime; use a conditional `AttachmentImage` widget (`Image.memory` on web) |
| Import (`file_picker`) | `File(result.files.first.path!).readAsString()` in `conversation_import.dart`, `roleplay_drawer.dart` | On web `path` is null; `file_picker` provides `.bytes` — small conditional |
| Export (`file_saver.dart`) | native method channel (mobile) / write to documents dir (desktop) | Web: browser download; messaging shows "Downloaded <file>" |
| `platform_defaults.dart` | `Platform.isAndroid` **unguarded** | Runtime throw on web — switch to `defaultTargetPlatform` + `kIsWeb` guard |
| `file_saver.dart` | `Platform.isAndroid || Platform.isIOS` **unguarded** | Same — guard with `kIsWeb` first |
| `app_header.dart`, `roleplay_screen.dart`, `main.dart` | `kIsWeb || Platform.is...` short-circuited | Safe today (dart:io stub + short-circuit); prefer `defaultTargetPlatform` cleanup |
| `flutter_secure_storage` 9.2.2 | Keychain/KeyStore/Secret Service | Web impl exists (`flutter_secure_storage_web`, endorsed) but is **experimental / localStorage-backed** — verify, document weaker guarantee |
| `path_provider` | desktop documents dir | Already avoided on web via `kIsWeb` branches in the DB layer — stays that way |
| `google_fonts` | runtime font fetch | Runtime fetch from font servers; offline first-load falls back — acceptable, note in docs |
| `image_picker` | gallery capture | Web OK (`XFile.bytes`); use `image.name` for extension (`.path` is a `blob:` URL on web) |
| `DesktopKeyboardShortcuts` | `KeyboardListener`, `TargetPlatform` | Web-safe as-is |
| CI | `.github/workflows/build-windows.yml` only | Add `build-web.yml` (mirror structure) + optional Pages deploy |

Note: `dart:io` imports compile on web as runtime-throwing stubs. Guarded usage (behind `kIsWeb` short-circuits or `dart.library.io` conditionals) is safe; unguarded evaluation throws. Phase 0 confirms this for this exact dependency set.

---

## 3. Phase 0 — Validation spike ✅ COMPLETED (2026-09-19)

**Outcome: all assumptions validated; the two highest-risk items (web sqlite persistence, SSE streaming) are now de-risked and proven working in a real browser.** Scratches below were built with Flutter 3.47.4 and driven by headless Chrome 153 + DevTools Protocol (plus `python -m http.server` and a CORS-enabled SSE fixture server).

### 3.1 Findings

| # | Probe | Result |
|---|---|---|
| 1 | `flutter create --platforms web .` | ✅ Clean. Adds only `web/`, touches `.metadata` + `pubspec.lock`. Nothing else disturbed. |
| 2 | `flutter build web --release` | ✅ **Compiles on the JS (dart2js) target with zero changes.** There is **no** `dart:ffi`/native-asset compile blocker: `sqflite_common_ffi` ships web stub variants (`sqflite_ffi_web.dart`) that compile. `dart:io` compiles as runtime-throwing stubs. |
| 2a | WASM target dry run | ⚠️ `flutter_secure_storage_web` uses `dart:html`/`dart:js_util`/`package:js` → **wasm-incompatible**. v1 = JS target only (already the plan). Revisit when storage plugin matures. |
| 3 | Runtime boot | ❌ App **crashes at startup before the first frame**: `LocalDatabase._initDB('clan_ai.db')` → `openDatabase()` → the default `databaseFactory` getter **throws on web**. Root cause from source: in `sqflite_common_ffi` 2.4.3, on web `databaseFactoryFfiImpl` is an eager `throw UnsupportedError('Unsupported on the web, use sqflite_common_ffi_web')`; `sqfliteFfiInit()` is a noop on web. **Fix confirmed:** bind `databaseFactory = databaseFactoryFfiWeb` in the web init path (the existing `kIsWeb` branch in `local_storage.dart`/`vector_store.dart` then produces usable in-browser db paths). |
| 4 | SQLite on web (`sqflite_common_ffi_web` 0.4.5+4) | ✅ **Full success.** Real sqlite 3.53.4 engine in-browser via WASM; schema-v13-shaped DDL + `PRAGMA foreign_keys` work; write/read verified. **IndexedDB persistence proven twice**: `onCreate` did not re-run after reload, row count survived **across complete Chrome restarts** (same origin/port). Runs through a **SharedWorker** → cross-tab safe (plan risk retired). Constraint: `dart run sqflite_common_ffi_web:setup` downloads `web/sqlite3.wasm` (748 KB) + `web/sqflite_sw.js` (257 KB); DB identity is **origin+port scoped** (localhost:8081 ≠ localhost:8080). |
| 5 | SSE streaming (`package:web` fetch + ReadableStream) | ✅ **Incremental delivery proven**: chunks arrived at +131/+253/+503/+753 ms on a server emitting every 250 ms (in-flight, not XHR-buffered); payload integrity intact (real `data: {...}` JSON incl. `reasoning_content`). **Abort proven**: `AbortController.abort()` → next `read()` throws `AbortError`; llama.cpp-style CORS preflight (OPTIONS 204, `Authorization` allowed) works. Pattern: `web.window.fetch(web.Request(url.toJS, RequestInit(method/headers/body: String.toJS/signal))).toDart` → `web.ReadableStreamDefaultReader(resp.body!)` → `await reader.read().toDart` → `(result.value as JSUint8Array).toDart` (`Uint8List`). This byte stream feeds `SseClient.parseStream` unchanged. |
| 6 | `flutter_secure_storage` 9.2.2 on web | ✅ Bonus probe. Constructs and write/read works (no throw). Still localStorage-grade security on web — document, but **no fallback needed**. |

### 3.2 Fixed-fact revisions to earlier assumptions
- No conditional DB facade is strictly required for *compilation* — but it is still the clean way to keep `databaseFactory`/`openDatabase` imports platform-correct (avoid importing the throw-on-web factory getters into web builds; avoids dead-code/analyzer caveats). Simplest verified pattern: on web, import `sqflite_common_ffi_web/sqflite_ffi_web.dart` and set `databaseFactory = databaseFactoryFfiWeb` inside the existing `kIsWeb` init branch. `sqflite`-family API (`Database`, `openDatabase`, `rawQuery`…) is shared across both.
- The original "expected compile errors" list was wrong: nothing fails to compile on the JS target. All remaining work is runtime wiring + browser-equivalent I/O. **Re-estimate: Phase 1 down from "moderate" to a focused refactor.**

### 3.3 Phase 0 artifacts (spike repos, in `/tmp/opencode/` — throwaway)
- `sqlite-web-spike/` — sqlite persistence probe (port 8903).
- `sse-web-spike/` — SSE incremental + abort probe (ports 8901/8902).
- `sse_server.py` — CORS SSE fixture (llama.cpp-streaming-shaped).
- `cdp.js` — reusable headless-Chrome CDP driver (console/exceptions/screenshot/state).

---

## 4. Phase 1 — Portability refactor (no user-visible native change)

> ✅ **Implemented.** All gates green: `flutter analyze` clean (0 issues), 505 hermetic tests pass, `flutter build web --release` + `flutter build linux --release` build, headless-Chrome boot smoke passes (no startup exception; sqlite opens through the WASM factory; health probes fire through the web transport). Details and deltas vs the plan below.

Principle: keep every native code path byte-identical; add web variants behind Dart conditional imports; run the full 505-test suite + `flutter analyze` after each commit. Baseline correction: the "12 pre-existing analyze infos / 503 tests" noted elsewhere predate this work — the tree analyzes clean at 0 issues and the suite counts 505 tests today.

### 4.1 New deps (`pubspec.yaml`)
- `sqflite_common_ffi_web` **^1.2.0** — the Phase-0 spike's lock actually resolved **1.2.0**; the plan's earlier "0.4.5+4" label was wrong and that version is broken for this app: its `setup` tool pins release `sqlite3-2.4.6/sqlite3.wasm` (706,316 B), whose import section doesn't match the worker glue built from the current `sqlite3` package → first `openDatabase` fails at boot with `WebAssembly.instantiate(): Import #25 "env": module is not an object or function` (surfaced as `Unsupported operation: unsupported result null (null)` through `dart:js_interop`). 1.2.0's `setup` pins `sqlite3-3.6.0/sqlite3.wasm` (748,686 B) — byte-identical to the Phase-0-verified spike pair. Same `sqflite` API surface; IndexedDB persistence + shared-worker cross-tab. Requires `dart run sqflite_common_ffi_web:setup --force` after version bumps (commits `web/sqlite3.wasm` + `web/sqflite_sw.js`; ~1 MB total). **Operational rule: worker + wasm must stay a consistent pair — always re-run setup after any `sqflite*`/`sqlite3` resolution change.** Lock now: `sqflite_common_ffi_web 1.2.0`, `sqlite3 3.5.2`, `sqflite_common 2.5.13`, `sqflite_common_ffi 2.4.3` (native, unchanged).
- `sqflite_common` ^2.5.13 — promoted to a direct dependency (used by `message_attachment_backend_web.dart` for `openDatabase`/`Database`/`ConflictAlgorithm`; otherwise `depend_on_referenced_packages` fires).
- `package:web` (^1.x) — DOM bindings for fetch/ReadableStream/downloads (verified pattern in §3.1 #5). JS (dart2js) is the v1 build target; `flutter_secure_storage_web` blocks wasm until it drops `dart:html`/`dart:js_util`.
- ~~`idb_shim`~~ **dropped.** Web attachments are stored as BLOBs in a **second WASM sqlite DB** (`clan_ai_attachments.db`, table `attachments(id TEXT PRIMARY KEY, bytes BLOB)`, IndexedDB-backed) — zero new deps and one shared persistence mechanism for all web data.

### 4.2 File-by-file changes

**Spike-driven simplification:** no new DB facade is needed. `sqflite_common_ffi` compiles on web as stubs (proven), and the whole sqlite fix is *bind the web factory at startup*. This shrinks rows 1–3 from a 4-file conditional facade to a one-line switch in `main.dart` plus keeping the existing `kIsWeb` path branches.

| # | File(s) | Change |
|---|---|---|
| 1 | `lib/main.dart` | ✅ `_initSqliteFfi()`: native branch unchanged; `kIsWeb` branch sets `databaseFactory = databaseFactoryFfiWeb` (direct dep on `sqflite_common_ffi_web`). `dart:io` import dropped; desktop check via `defaultTargetPlatform`. |
| 2 | `local_storage.dart`, `vector_store.dart` | ✅ No import changes required (compile-verified). Existing `kIsWeb` `path = filePath` branches now produce real in-browser DB paths; keep. |
| 3 | (dropped — DB facade not needed) | — |
| 4 | `lib/core/network/http_transport_stub.dart` / `_io.dart` / `_web.dart` + `http_client.dart` + `streamed_api_response.dart` | ✅ **Facade + refactor.** Extracted `createHttpClient(connectTimeout)` + `streamSend(client, request) -> Future<StreamedApiResponse{statusCode, stream}>` via `export ... show` conditional (`dart.library.js_interop` → web, `dart.library.io` → io; verified `js_interop=false` on VM so native keeps the io transport). io = `HttpClient()..connectionTimeout` + `IOClient` + `client.send()` (unchanged semantics). web = `web.window.fetch(Request(url.toJS, RequestInit(method/headers: Headers/body/signal)))` → status + `ReadableStreamDefaultReader` pumping `(result.value as JSUint8Array).toDart` into a `StreamController<List<int>>`; `controller.onCancel` → `AbortController.abort()` (consumer cancel = stop-generation aborts the fetch, mirroring socket teardown). `postStream` keeps the 60s receive `.timeout`, `throwForStatusCode`, `SocketException→HostUnreachable` mapping; error bodies drained via a new `StreamedApiResponse.bodyToString()` (replaces `ByteStream.bytesToString`, which doesn't exist on a plain `Stream<List<int>>`). `.stream` member name matches `http.StreamedResponse`, so `LlamaApiService`/`SseClient` call sites are untouched. Web has no TCP connect timeout (browser-managed) — `.timeout()` guards are the only bound; documented. |
| 5 | `llama_api_service.dart` | ✅ `postStream` call site works unchanged (`.stream`); attachment bytes read via `MessageAttachmentStore.instance.readBytes(imagePath)` with `null` → plain-text fallback; `dart:io` import removed. |
| 6 | `lib/core/utils/message_attachment_store.dart` + `message_attachment_backend_{stub,io,web}.dart` | ✅ Facade over a platform backend. Same singleton API (`saveImage({fileId,data,extension})`, `deleteIfExists(ref)`, `mimeTypeFromBytes`, `extensionOf`) **plus new `readBytes(ref)`**. `io` impl = the previous file-based logic moved verbatim (`FileAttachmentBackend`); `web` impl = `SqliteAttachmentBackend` — lazy-open `clan_ai_attachments.db`, `INSERT OR REPLACE`/`DELETE`/`SELECT` BLOBs keyed by the ref string (`$fileId.$ext`), same WASM/IndexedDB persistence as the main DB. `messages.image_path` keeps holding the ref (path on native, DB key on web) → **schema unchanged**. |
| 7 | `lib/ui/shared/widgets/attachment_image.dart` | ✅ **New.** `AttachmentImage(ref, ...)` — `Image.file` on native; on web `FutureBuilder` → `MessageAttachmentStore.instance.readBytes(ref)` → `Image.memory` (FutureBuilder re-arms only when `ref` changes; keys are stable per widget). |
| 8 | `prompt_input_bar.dart` | ✅ Preview via `AttachmentImage`; extension sourced from `kIsWeb ? image.name : image.path` (web `XFile.path` is empty); `dart:io` import dropped. |
| 9 | `message_bubble.dart` | ✅ Bubble image + `_showImageFullscreen` via `AttachmentImage`. `dart:io File(...)` removed. |
| 10 | `file_saver.dart` | ✅ `kIsWeb` first → `browser_download_{stub,web}.dart` facade (`Blob` + `URL.createObjectURL` + anchor `click()`; returns the filename for snackbars). Mobile channel + desktop write paths unchanged (`defaultTargetPlatform` instead of `Platform.is*`). |
| 11 | `platform_defaults.dart` | ✅ `dart:io` dropped; `kIsWeb → defaultBaseUrl` (loopback default), else `!kIsWeb && defaultTargetPlatform == android → 10.0.2.2`. |
| 12 | `conversation_import.dart`, `roleplay_drawer.dart` | ✅ Picker guard relaxed to `path == null && bytes == null`; content from `bytes != null ? utf8.decode(bytes!) : File(path).readAsString()`. |
| 13 | `secure_storage_service.dart` | ✅ Verified in Phase 0: v9.2.2 constructs and read/writes work on web — **no code change or fallback needed**. Docs only: localStorage-grade security on web (obfuscated, not Keychain-grade). |
| 14 | `app_header.dart`, `roleplay_screen.dart` | ✅ `kIsWeb || Platform.is...` → `defaultTargetPlatform`; `dart:io` imports dropped. |
| 15 | `google_fonts` | Optional (not done): set `GoogleFonts.config.allowRuntimeFetching` so offline first-load degrades gracefully — defer to Phase 2 PWA polish when offline behavior is exercised. |

### 4.3 Verification gates (after every commit)
- ✅ `flutter analyze` — **0 issues** (baseline infos noted in AGENTS.md were resolved before this work; do not re-introduce)
- ✅ `flutter test` — **505 tests pass**, hermetic (fakes unaffected by conditional imports; `io` variants resolve on VM)
- ✅ `flutter build linux --release` — native parity proven (io transport + file backend + FFI sqlite compile and run)
- ✅ `flutter build web --release` — compiles on dart2js (wasm-dry-run warnings from `flutter_secure_storage_web` are the known v1 blockers); `web/sqlite3.wasm` + `web/sqflite_sw.js` committed
- ✅ Boot smoke in headless Chrome (reuse `/tmp/opencode/cdp.js`): **no startup exception**; `openDatabase('clan_ai.db')` + `PRAGMA foreign_keys` succeed through the WASM factory; health probes to the default base URL fire through the web fetch transport and surface server 401s cleanly. Same smoke passes on the known-good Phase-0 spike, so the empty `flt-glass-pane` in this headless config is a Chrome-renderer artifact, not an app fault.

---

## 5. Phase 2 — PWA layer

> ✅ **Implemented.** Manifest/icons (brand dark `#0F1117`, `any` + `maskable` from the 1024px app icon), PWA meta tags, `scripts/generate-web-icons.sh`, custom service worker (`web/clan_ai_sw.js` — 3.47.4's generated SW is a self-unregistering stub, see below), CI (`build-web.yml` with optional manual Pages deploy, local-CanvasKit builds), README + ARCHITECTURE updates. Gates: `flutter analyze` clean, 505 tests pass, `flutter build web --release` + `flutter build linux --release`, headless-Chrome boot + PWA probe (manifest/standalone/dark parsed from the served app, `clan_ai_sw.js` registered, sqlite SharedWorker boots).

1. **`web/` scaffold** via Phase 0 (`flutter create --platforms web .`), then customize:
   - `web/index.html`: ✅ title/description "CLAN AI", `<meta name="theme-color" content="#0F1117">`, favicon 32x32, iOS `apple-mobile-web-app-*` tags, `apple-touch-icon` (generated 180x180); default `flutter_bootstrap` loader kept.
   - `web/manifest.json`: ✅ `name`/`short_name` "CLAN AI", `id: clan-ai`, `start_url: "."` + `scope: "."` (relative — safe for root *and* project-Pages hosting), `display: "standalone"`, `theme_color`/`background_color` `#0F1117` (AppTheme.darkBg), `orientation` removed (desktop-capable), icons `any` 192/512 + `maskable` 192/512 with explicit `purpose`.
   - `web/icons/`: ✅ `scripts/generate-web-icons.sh` (ImageMagick) generates from `macos/.../app_icon_1024.png` (highest-res rendering of the logo; falls back to `msix/assets/icon100x100.png`). Maskable = source scaled to 68% (inside the 80% safe zone) composited full-bleed over `#0F1117` so the OS mask never shows transparency; 8-bit PNGs.
   - Service worker: ⚠️ **plan correction — verified against 3.47.4 build output.** Flutter no longer ships asset-precaching: the generated `flutter_service_worker.js` is a **self-unregistering stub** (31 lines; `activate` unregisters itself, no fetch handler — `flutter#156910`). Delivered instead: a small custom SW **`web/clan_ai_sw.js`** (committed, copied verbatim into `build/web/`; registered from `index.html`). It precaches the app shell, runtime-caches same-origin assets (stale-while-revalidate), network-first for navigations, keyed by app version from `version.json` (each release installs a fresh cache; `activate` drops old ones). Same-origin GET only — llama.cpp API/SSE calls stay network-only. Scoped to the app's directory so **project-Pages-safe**.
   - CanvasKit: `flutter build web` **must** use `--no-web-resources-cdn` (`UseLocalCanvasKit`), otherwise the loader fetches `canvaskit.wasm` from the gstatic CDN and offline boot fails. CI + README use this flag.
2. **Hosting & CI:**
   - ✅ `.github/workflows/build-web.yml`: checkout → Flutter 3.47.x → `pub get` → `flutter analyze` + `flutter test` (505 hermetic tests; both io/web conditional variants compiled per PR) → `flutter build web --release --no-web-resources-cdn` → upload artifact. Separate `deploy-pages` job gated to `workflow_dispatch` (manual checkbox) since project Pages serves under `/CLAN-AI/` and needs `flutter build web --release --base-href /CLAN-AI/` + matching `start_url`; recommend Cloudflare/Vercel/Netlify or local static hosting otherwise.
3. **Docs:** ✅ README — Platforms table "Web (PWA) — Beta"; "Web (PWA)" install/run section (run, build+serve, PWA install, `llama-server --cors <origin>`, HTTPS/mixed-content rules, data-isolation + JSON migration, storage quota); build targets + Getting Started + Configuration base-URL; Features + Gotchas (web CORS/data isolation/secure-storage grade/WASM pair rule). ARCHITECTURE.md — HTTP Client transport table (io/web), SQLite FFI web path + WASM pair rule, new Attachment Storage section, Key Constraints §13–14.

---

## 6. Phase 3 — QA checklist (Chrome, against a `--cors`-enabled llama-server)

**Status:** All automated gates passed. Final re-run on `2026-09-20`: `flutter analyze` 0 issues, 505/505 hermetic tests green, fixture journey 6/6 PASS, real-server journey 6/6 PASS, `flutter build web --release --no-web-resources-cdn` PASS.

Legend: ✓ verified in a real headless Chrome (real WASM sqlite/IndexedDB/localStorage + the served app or integration-test bundle); ⚠️ verified with a documented caveat / partial; **manual** = not drivable headless, recorded as a manual QA item.

- [x] **Fresh web build compiles** (`flutter build web --release` ✅, `--target=integration_test/…` bundle ✅), `flutter analyze` **0 issues**, hermetic suite green (re-run in the final gate).
- [x] **Health poll, `/props`, `/v1/models` (CORS preflight with `Authorization`)** — UI #1 (fixture), PWA probe `cors` block (health 200, models-with-key 200 `qa-fixture-8b`, no-key 401, preflight 204), and the real-server run. Fixture logged `OPTIONS` preflights + `GET /v1/models -> 200 origin=…` for every app boot.
- [x] ⚠️ **Token streaming incremental in UI; TTFT metrics; cancellation** — incremental deltas + TTFT/tps badge verified in both fixture and real-server runs; cancel verified (stop button → UI idle, no extra tokens, no extra message bubble). **Finding (recorded, not fixed):** during *server silence* stop-generation returns the UI to idle but does **not** abort the underlying fetch — `SseClient.parseStream` only observes `cancelToken` between received lines, and the web `BrowserClient` has no AbortController wiring, so the TCP/SSE connection stays open until the server's next chunk (fixture: `stall released: client did not disconnect after 90.09s`). Follow-up recommendation: wire an `AbortController`/`CancelToken` signal into `dart:html`/fetch on stop.
- [x] **Reasoning paths** — `reasoning_content` deltas + inline `…`/`<thought>` across chunk boundaries: strict assert vs the fixture (always emits); adaptive (skip-if-absent + no-block UI) against a real llama-server whose flags may not emit reasoning.
- [x] ⚠️ **Chat: regenerate → variant; edit; branch thread. Roleplay: greeting, thread reuse, identity guard, RAG memories, memory pruning** — regenerate → variant 2/2 → previous 1/2 navigation ✓ (fixture + real; web variant switcher). Edit-assistant/branch-thread covered by hermetic tests only (not re-exercised in the web journey). Roleplay greeting + thread reuse + reply stream ✓ in-browser; identity-guard prompt (sole location `RoleplayPromptFormatter.buildSystemPrompt`) + RAG trigram store + pruning dialog are Dart-layer logic verified by the hermetic suites — web UI of the pruning dialog remains a manual QA item.
- [x] ⚠️ **Image attach round-trip** — attachment bytes → `clan_ai_attachments` stores → reload renders from IndexedDB → delete cleans up (storage suite, real Chrome). **manual:** the OS file-picker dialog itself (headless Chrome can't drive it) and preview.
- [x] ⚠️ **Import/export conversations; export downloads** — export → import round trip against real web sqlite ✓ (storage suite). **manual:** the actual download dialog (FileSaver/`<a download>`) and the import file-picker.
- [x] **API key save/restore across reload (secure storage web)** — storage suite key round trip ✓; PWA probe seeded `flutter_secure_storage` with the plugin scheme and the app re-connected **200 on the online reload after an offline round trip without re-seeding** → per-profile key restore across reload ✓. Tooling note: `flutter_secure_storage` 11.2.0's web `WebOptions.publicKey` default is `'FlutterSecureStorage'` (AES-key entry + `FlutterSecureStorage.<name>` values), *not* the `flutter.` prefix used by `shared_preferences_web`.
- [x] **Theme (dark/light/custom) persists; app mode persists** — UI #5 (Light theme + roleplay mode persisted to web SharedPreferences) + storage suite prefs round trip.
- [x] ⚠️ **PWA: installable, launches standalone, offline app-shell reload, chat history persists across reload/offline** — offline shell reload served by the service worker (`swControlled: true`, app boots, canvases present) ✓; single shared worker across two tabs + identical IndexedDB (`sqflite_databases`) in both ✓; key restore + re-connect after reload ✓. **manual:** the install/standalone-launch flow (needs a user gesture / Chrome dialog; manifest + icons verified structurally in Phase 2).
- [ ] **manual — KB shortcuts (Ctrl+N/K/, , Esc, Ctrl+/), search** — implemented via `DesktopKeyboardShortcuts`; web key-event delivery is flaky headless; recorded as a manual QA item.
- [x] ⚠️ **Quota sanity; two tabs concurrently** — two tabs share one WASM sqlite worker + DB (documented single-writer assumption) ✓; **manual:** several-MB attachment quota-fill.

**Findings recorded (runtime behavior, no fixes shipped in this phase):**
1. Stop-generation does not abort the underlying fetch during server silence (SSE `cancelToken` is only observed per-line; `BrowserClient` has no AbortController wiring) — see ⚠️ above + §7.
2. There is **no model dropdown in the Settings UI** (removed as a feature — `SettingsViewModel.availableModels` feeds a debug context only; app auto-selects `availableModels.first` for chat).
3. On boot the chat VM auto-selects the **first persisted thread** (`chat_view_model.dart:106`), which hides the empty-state `'Connected to …'` text — the web QA suites must start from a cleared thread table to assert the boot connect state.

---

## 7. Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| SSE streaming on web (fetch/ReadableStream + chunk-boundary reasoning) | ~~High~~ **Resolved in Phase 0 — Low** | Incremental delivery + abort verified in a real browser (§3.1 #5); `SseClient` untouched; Phase 3 checklist remains. ⚠️ New: stop returns the UI to idle but does **not** abort the fetch during server silence (per-line `cancelToken` check; `BrowserClient` has no AbortController) — recorded in §6, follow-up recommended |
| WASM sqlite persistence (IndexedDB-backed) | ~~High~~ **Resolved in Phase 0 — Low** | Persistence across reload *and* Chrome restarts verified (§3.1 #4); schema + PRAGMAs exercised; Origin+port scoping documented; JSON export remains the backup path |
| **WASM loader/worker pair drift** (hit in Phase 1: `sqflite_common_ffi_web` 0.4.5+4 + its pinned `sqlite3-2.4.6` wasm → `Import #25 "env"` boot crash) | Med → fixed | Pair is fixed at **1.2.0 + `sqlite3-3.6.0/sqlite3.wasm`** (the Phase-0-verified set); rule: re-run `dart run sqflite_common_ffi_web:setup --force` after any `sqflite*`/`sqlite3` resolution change and re-smoke; CI web-build job only proves compile, so keep the boot smoke as the runtime gate |
| API keys on web = localStorage-grade (regional storage plugin) | Med (accept) | Works (verified); document weaker guarantee; optional future: browser Credential Management API |
| CORS / mixed content / Private Network Access block LAN servers from HTTPS pages | Ext (operational) | Users: `llama-server --cors <origin>`; serve app from localhost or HTTPS; README instructions |
| Storage quota (attachments) | Low-Med | Attachments live in a **separate** `clan_ai_attachments.db` (kept out of `clan_ai.db`); bound image size (already 2048px/85q) |
| Conditional-import drift breaks one platform | Low | CI builds both `io` (tests/analyze) and `web` (build job) |
| `flutter_secure_storage` web blocks wasm target | Low (v1 is JS-only) | Keep JS target; re-check when plugin drops `dart:html`/`dart:js_util` |
| Pages base-href path issues | Low | Prefer Cloudflare/Vercel or explicit `--base-href` |

## 8. Out of scope (v1)
- Data sync between desktop and web app (use JSON import/export).
- Advanced service worker logic beyond the app-shell cache: background sync, push notifications, font-bundling, fine-grained runtime-cache policies (v1 ships the minimal `web/clan_ai_sw.js` — see §5).
- WASM (dart2wasm) build target (JS target only; `package:web` keeps the door open).
- Multi-tab write coordination.
- PWA push notifications / background sync.