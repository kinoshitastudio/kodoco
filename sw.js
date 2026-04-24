// KODOCO Service Worker — basic offline shell
// Strategy:
//   · HTML (navigation): network-first with cache fallback
//   · static / 3rd-party assets: cache-first with background refresh
const VERSION     = 'kodoco-v32-2026-04-24-unlock';
const SHELL_CACHE = `${VERSION}-shell`;
const RUNTIME     = `${VERSION}-runtime`;

const SHELL = [
  './',
  './app.html',
  './index.html',
  './favicon.svg',
  './ogp.svg',
  'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=Noto+Sans+JP:wght@300;400;500;700;900&display=swap',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(SHELL_CACHE).then((c) => c.addAll(SHELL.map((u) => new Request(u, { cache: 'reload' }))))
      .catch(() => {}) // best-effort
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((k) => !k.startsWith(VERSION)).map((k) => caches.delete(k))
    ))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Tile requests (Leaflet map tiles): just pass through, cache in runtime
  if (url.hostname.includes('tile.openstreetmap.org')) {
    event.respondWith(cacheFirst(req, RUNTIME));
    return;
  }

  // Navigation: network first, fall back to cached shell
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(SHELL_CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => caches.match(req).then((r) => r || caches.match('./app.html')))
    );
    return;
  }

  // Everything else: cache first, update in background
  event.respondWith(cacheFirst(req, RUNTIME));
});

async function cacheFirst(req, cacheName) {
  const cached = await caches.match(req);
  if (cached) {
    // refresh in background
    fetch(req).then((res) => {
      if (res && res.status === 200) {
        caches.open(cacheName).then((c) => c.put(req, res.clone())).catch(() => {});
      }
    }).catch(() => {});
    return cached;
  }
  try {
    const res = await fetch(req);
    if (res && res.status === 200 && (res.type === 'basic' || res.type === 'cors')) {
      const copy = res.clone();
      caches.open(cacheName).then((c) => c.put(req, copy)).catch(() => {});
    }
    return res;
  } catch (_) {
    return new Response('', { status: 504, statusText: 'offline' });
  }
}
