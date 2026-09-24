'use strict';

// CLAN AI — PWA service worker.
//
// Checked into web/ and copied verbatim into build/web/ by `flutter build web`.
// NOTE: Flutter 3.47's generated `flutter_service_worker.js` is a
// self-unregistering stub (no caching, no fetch handler), so the app-shell
// cache the PWA needs is provided here instead.
//
// Behaviour (v3):
//   * Precache the app shell + manifest/icons on install.
//   * Same-origin GET only. Cross-origin traffic (llama.cpp API/SSE calls,
//     fonts, CDNs) is never intercepted.
//   * Navigations are network-first (picks up redeploys immediately) with
//     cache fallback for offline reload.
//   * Static assets are stale-while-revalidate (offline-first after first use).
//   * Every network fetch uses `cache: 'no-store'`, so neither the browser HTTP
//     cache nor the host's Cache-Control max-age can serve a stale shell or
//     asset: the SW always revalidates against the server.
//   * The cache is keyed by the app version read from `version.json`. The cache
//     name is re-keyed and stale caches are swept **before** the freshly
//     fetched navigation response is handed to the page, so the bundle files
//     the new page then requests always resolve against the current (empty)
//     version cache — returning PWA users never race ahead of the sweep and
//     boot a previous release's UI. The sweep is idempotent and safe to call
//     from concurrent handlers.
//   * Caches are only ever addressed with a resolved version name. A cold
//     worker (cache name not yet known) serves assets straight from the
//     network and never fabricates a nameless cache; the legacy `"null"` cache
//     created by older SW code is deleted during re-keying.

const CACHE_PREFIX = 'clan-ai-v';

// Reads the deployed `version.json` (network, non-cached). Resolves to the
// version string, or null when the fetch fails (offline / missing file) —
// callers treat null as "must not touch any cache".
async function readRemoteVersion() {
  try {
    const response = await fetch('./version.json', { cache: 'no-store' });
    const info = await response.json();
    const version = typeof info.version === 'string' ? info.version : null;
    return version && version.length > 0 ? version : null;
  } catch (_) {
    return null;
  }
}

const PRECACHE_URLS = [
  './',
  './index.html',
  './manifest.json',
  './version.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
  './icons/apple-touch-icon.png',
];

// Active version-keyed cache name. Resolved on install, eagerly on cold start,
// and re-keyed on every successful navigation. Never null once known.
let cacheName = null;

// Returns the cache name for the deployed version and drops every other clan-ai
// cache plus the legacy "null" cache. Returns the current cache name, or null
// when the version cannot be read (offline) — callers then leave caches
// untouched. Idempotent and safe to call concurrently: concurrent sweeps
// converge on the same target and redundant deletes are harmless.
async function rekeyToDeployed(version) {
  if (version === null) {
    return cacheName;
  }
  const expected = CACHE_PREFIX + version;
  if (expected === cacheName) {
    return expected;
  }
  cacheName = expected;
  const keys = await caches.keys();
  await Promise.all(
    keys
      .filter(
        (key) =>
          key === 'null' || (key.startsWith(CACHE_PREFIX) && key !== expected)
      )
      .map((key) => caches.delete(key))
  );
  return cacheName;
}

// Eagerly adopt the deployed version's cache name on cold start so the very
// first asset request of a returning session targets the current version cache
// instead of racing the navigation's re-key, and sweep any stale release
// caches (including the legacy "null" cache) immediately. Only fills an empty
// name: if a navigation already re-keyed `cacheName` (possibly to an even
// newer deploy that started mid-session), nothing is downgraded.
readRemoteVersion().then((version) => {
  if (version !== null && cacheName === null) {
    rekeyToDeployed(version);
  }
});

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const version = await readRemoteVersion();
      cacheName = CACHE_PREFIX + (version || '0');
      const cache = await caches.open(cacheName);
      await cache.addAll(PRECACHE_URLS);
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key !== cacheName)
          .map((key) => caches.delete(key))
      );
      await self.clients.claim();
    })()
  );
});

// Best-effort offline fallback: returns the first cached response for request
// found in any clan-ai version cache (newest first), or null.
async function matchAnyCachedPage(request) {
  const keys = (await caches.keys())
    .filter((key) => key.startsWith(CACHE_PREFIX) || key === 'null')
    .sort();
  for (const key of keys.reverse()) {
    const cache = await caches.open(key);
    const cached = await cache.match(request);
    if (cached) {
      return cached;
    }
  }
  return null;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') {
    return; // POST/PUT/OPTIONS (including API calls) pass straight through.
  }
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) {
    return; // Never intercept llama.cpp / font / CDN traffic.
  }

  // Navigations: network-first, cache fallback when offline.
  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        // Probe the deployed version in parallel with the network fetch.
        const versionPromise = readRemoteVersion();
        let fresh;
        try {
          // Always hit the server: a reload right after a deploy must see the
          // newest index.html, independent of any HTTP cache the host sets.
          fresh = await fetch(request, { cache: 'no-store' });
        } catch (_) {
          fresh = null;
        }
        // Re-key + sweep BEFORE serving the fresh page: the bundle/assets it
        // requests next must resolve against the current, empty version cache.
        // This is what keeps returning installs on the newest build on their
        // very first post-deploy load.
        await rekeyToDeployed(await versionPromise);

        if (fresh) {
          if (cacheName !== null) {
            const cache = await caches.open(cacheName);
            await cache.put(request, fresh.clone());
          }
          return fresh;
        }

        // Offline: fall back to the re-keyed cache, then any older version.
        if (cacheName !== null) {
          const cache = await caches.open(cacheName);
          const cached = await cache.match(request);
          if (cached) {
            return cached;
          }
        }
        const legacy = await matchAnyCachedPage(request);
        if (legacy) {
          return legacy;
        }
        throw new Error('CLAN AI offline and no cached app shell');
      })()
    );
    return;
  }

  // Static assets: stale-while-revalidate, always revalidating on the network.
  event.respondWith(
    (async () => {
      if (cacheName === null) {
        // Cold worker before any navigation has confirmed the deployed version:
        // never open an unnamed cache — serve the freshest network copy.
        return fetch(request, { cache: 'no-store' });
      }
      const cache = await caches.open(cacheName);
      const cached = await cache.match(request);
      const network = fetch(request, { cache: 'no-store' })
        .then((response) => {
          if (response && response.ok) {
            cache.put(request, response.clone());
          }
          return response;
        })
        .catch(() => cached);
      return cached || (await network);
    })()
  );
});