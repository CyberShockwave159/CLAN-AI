'use strict';

// CLAN AI — PWA service worker.
//
// Checked into web/ and copied verbatim into build/web/ by `flutter build web`.
// NOTE: Flutter 3.47's generated `flutter_service_worker.js` is a
// self-unregistering stub (no caching, no fetch handler), so the app-shell
// cache the PWA needs is provided here instead.
//
// Behaviour (v1):
//   * Precache the app shell + manifest/icons on install.
//   * Same-origin GET only. Cross-origin traffic (llama.cpp API/SSE calls,
//     fonts, CDNs) is never intercepted.
//   * Navigations are network-first (picks up redeploys immediately) with
//     cache fallback for offline reload.
//   * Static assets are stale-while-revalidate (offline-first after first use).
//   * The cache is keyed by the app version read from `version.json`, so each
//     release installs a fresh cache and activate() drops the previous one —
//     no unbounded growth across releases.

const CACHE_PREFIX = 'clan-ai-v';

async function currentCacheName() {
  try {
    const response = await fetch('./version.json', { cache: 'no-store' });
    const info = await response.json();
    const version = typeof info.version === 'string' ? info.version : '0';
    return CACHE_PREFIX + version;
  } catch (_) {
    return CACHE_PREFIX + '0';
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
        const cache = await caches.open(cacheName);
        try {
          const fresh = await fetch(request);
          await cache.put(request, fresh.clone());
          return fresh;
        } catch (_) {
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

  // Static assets: stale-while-revalidate.
  event.respondWith(
    (async () => {
      const cache = await caches.open(cacheName);
      const cached = await cache.match(request);
      const network = fetch(request)
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