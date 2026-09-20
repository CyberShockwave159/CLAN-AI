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

1. **`web/` scaffold** via Phase 0 (`flutter create --platforms web .`), then customize:
   - `web/index.html`: title, description, `<meta name="theme-color">`, favicon, `apple-mobile-web-app-capable`; default `flutter_bootstrap` loader.
   - `web/manifest.json`: `name`/`short_name` "CLAN AI", `start_url` (see hosting), `display: "standalone"`, `theme_color` + `background_color` (brand dark), icons **192 + 512** (`any` + `maskable`).
   - `web/icons/`: generate from `msix/assets/icon100x100.png` (exists) — `scripts/generate-web-icons.sh` (ImageMagick; or committed PNGs).
   - Service worker: Flutter generates `flutter_service_worker.js` + app-shell cache on `flutter build web` automatically. It caches only same-origin app assets — external llama.cpp calls stay network-only. No custom SW needed for v1. Note: `sqflite_sw.js` (from `sqflite_common_ffi_web:setup`) is a **SharedWorker**, not a service worker — unrelated to offline caching; must be committed alongside `sqlite3.wasm`.
2. **Hosting & CI:**
   - `.github/workflows/build-web.yml`: checkout → setup Flutter 3.47.x → `pub get` → `flutter build web --release` → upload artifact. Optional job: deploy to GitHub Pages (`actions/gh-pages` or `peaceiris/actions-gh-pages`) — Pages under a repo path requires `--base-href /<repo>/` at build time and matching `start_url`. Recommend Cloudflare/Vercel/Netlify for simplicity, or serve locally (`flutter run -d chrome` / `python3 -m http.server`).
   - Add a web build job to CI so both `io` and `web` conditional variants are compiled on every PR.
3. **Docs:** README — Platforms table adds "Web (PWA) — Beta"; install/run steps; PWA install (Chrome "Install app"); llama-server flags (`--cors <origin>`, note `--api-key`/preflight handled); HTTPS/mixed-content rules; data-isolation + JSON migration note; offline scope; storage-quota note. ARCHITECTURE.md — Platforms section, storage section (sqlite web VFS, attachment store variants), streaming section (web transport).

---

## 6. Phase 3 — QA checklist (Chrome, against a `--cors`-enabled llama-server)

- [ ] Fresh web build compiles (`flutter build web --release`), `flutter analyze` clean, suite green.
- [ ] Health poll, `/props`, `/v1/models` (CORS preflight with `Authorization`).
- [ ] **Token streaming incremental** in UI; TTFT metrics; cancellation (Esc/stop) works (AbortController) and cleans up.
- [ ] Reasoning paths: `reasoning_content` chunks + inline `...` / `<thought>` tags across arbitrary chunk boundaries.
- [ ] Chat: regenerate → variant; edit; branch thread. Roleplay: greeting, thread reuse, identity guard, RAG memories (vector store), memory pruning dialog.
- [ ] Image attach round-trip: pick → preview → send → payload contains base64 data URI → photo renders → attach on reload still renders (IDB read) → delete cleans up.
- [ ] Import/export conversations; export downloads; import reads `.bytes`.
- [ ] API key save/restore across reload (secure storage web).
- [ ] Theme (dark/light/custom) persists; app mode persists.
- [ ] **PWA:** installable (manifest + icons), launches standalone, offline app-shell reload works, **chat history persists across reload/offline** (IndexedDB-backed sqlite).
- [ ] KB shortcuts (Ctrl+N/K/, , Esc, Ctrl+/), search.
- [ ] Quota sanity: several MB of attachments; two tabs open concurrently (shared IDB — accept single-writer assumption, document).

---

## 7. Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| SSE streaming on web (fetch/ReadableStream + chunk-boundary reasoning) | ~~High~~ **Resolved in Phase 0 — Low** | Incremental delivery + abort verified in a real browser (§3.1 #5); `SseClient` untouched; Phase 3 checklist remains |
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
- Custom service worker logic (offline-first beyond default app-shell cache).
- WASM (dart2wasm) build target (JS target only; `package:web` keeps the door open).
- Multi-tab write coordination.
- PWA push notifications / background sync.