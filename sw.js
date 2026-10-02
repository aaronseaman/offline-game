/* Prismfall service worker: precache the app shell, serve it offline, refresh in the background. */
const VERSION = 'prismfall-v3';
const SHELL = [
  './',
  './index.html',
  './css/style.css',
  './js/art.js',
  './js/core.js',
  './js/main.js',
  './manifest.webmanifest',
  './fonts/unbounded-latin.woff2',
  './icons/favicon.svg',
  './icons/icon-32.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll(SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // Navigations get the cached shell so the game opens instantly offline;
  // everything else is stale-while-revalidate.
  const key = req.mode === 'navigate' ? './index.html' : req;
  const fresh = fetch(req)
    .then((res) => {
      if (res && res.ok && res.type === 'basic') {
        const copy = res.clone();
        return caches.open(VERSION).then((c) => c.put(key, copy)).then(() => res);
      }
      return res;
    })
    .catch(() => null);
  event.waitUntil(fresh);
  event.respondWith(
    caches.match(key, { ignoreSearch: true }).then((cached) =>
      cached || fresh.then((res) => res || Response.error())
    )
  );
});

