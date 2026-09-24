'use strict';

// CLAN AI — PWA service worker.
//
// Checked into web/ and copied verbatim into build/web/ by `flutter build web`.
// NOTE: Flutter 3.47's generated `flutter_service_worker.js` is a
// self-unregistering stub (no caching, no fetch handler), so the app-shell
// cache the PWA needs is provided here instead.
//
// Behaviour (v2):
//   * Precache the app shell + manifest/icons on install.
//   * Same-origin GET only. Cross-origin traffic (llama.cpp API/SSE calls,
//     fonts, CDNs) is never intercepted.
//   * Navigations are network-first (picks up redeploys immediately) with
//     cache fallback for offline reload.
//   * Static assets are stale-while-revalidate (offline-first after first use).
//   * Every network fetch uses `cache: 'no-store'`, so neither the browser HTTP
//     cache nor the host's Cache-Control max-age can serve a stale shell or
//     asset: the SW always revalidates against the server.
//   * The cache is keyed by the app version read from `version.json`. activate()
//     prunes old caches when the SW script itself changes; successful navigations
//     re-key and sweep stale caches when a new release is deployed behind an
//     unchanged script — no unbounded growth across releases and no waiting for
//     a script rewrite to rotate the cache.

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

async function currentCacheName() {
  const version = await readRemoteVersion();
  return CACHE_PREFIX + (version || '0');
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

let cacheName = null;

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      cacheName = await currentCacheName();
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
        keys.filter((key) => key !== cacheName).map((key) => caches.delete(key))
      );
      await self.clients.claim();
    })()
  );
});

// Re-keys the runtime cache to the freshly deployed version and drops every
// other clan-ai cache. Runs after a successful navigation so a release shipped
// without changing this script still rotates caches promptly. Safe to call
// repeatedly: a mutex guards concurrent sweeps and failures are swallowed
// (offline or a failed version.json read simply leaves caches untouched).
let sweeping = false;
async function sweepStaleCaches() {
  if (sweeping) return;
  sweeping = true;
  try {
    const version = await readRemoteVersion();
    if (version === null) {
      return;
    }
    const expected = CACHE_PREFIX + version;
    if (expected === cacheName) {
      return;
    }
    cacheName = expected;
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key.startsWith(CACHE_PREFIX) && key !== expected)
        .map((key) => caches.delete(key))
    );
  } catch (_) {
    // Best-effort: never let a sweep failure break navigation handling.
  } finally {
    sweeping = false;
  }
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
        try {
          // Always hit the server: a reload right after a deploy must see the
          // newest index.html, independent of any HTTP cache the host sets.
          const fresh = await fetch(request, { cache: 'no-store' });
          const cache = await caches.open(cacheName);
          await cache.put(request, fresh.clone());
          // Re-key + sweep when the server serves a newer release.
          sweepStaleCaches();
          return fresh;
        } catch (_) {
          const cache = await caches.open(cacheName);
          const cached = await cache.match(request);
          if (cached) {
            return cached;
          }
          throw new Error('CLAN AI offline and no cached app shell');
        }
      })()
    );
    return;
  }

  // Static assets: stale-while-revalidate, always revalidating on the network.
  event.respondWith(
    (async () => {
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