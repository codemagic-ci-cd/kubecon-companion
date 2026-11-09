/* KubeCon Companion offline service worker.
 *
 * - App shell is precached on install.
 * - Navigations: network first, cached index.html when offline.
 * - App code and data (.js, .mjs, .wasm, .json): network first with a 4 s
 *   timeout, cached copy when offline or slow, so fixes reach people at once.
 * - Images and fonts: stale-while-revalidate.
 * Bump CACHE_VERSION to drop old caches.
 */
const CACHE_VERSION = 'v3';
const CACHE = `kubecon-companion-${CACHE_VERSION}`;
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/assets/data/sessions.json',
  'assets/assets/data/venue.json',
  'assets/assets/data/happenings.json',
  'assets/assets/data/info.json',
  'assets/assets/data/rooms_raw.json',
];
const NEVER_CACHE = ['sw.js', 'flutter_service_worker.js', 'version.json'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      // Individually, so one missing file doesn't fail the install.
      Promise.all(SHELL.map((u) => cache.add(u).catch(() => undefined)))
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((k) => k.startsWith('kubecon-companion-') && k !== CACHE)
        .map((k) => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

self.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.type !== 'cache-urls' || !Array.isArray(data.urls)) return;
  event.waitUntil(caches.open(CACHE).then((cache) => Promise.all(
    data.urls
      .filter((u) => typeof u === 'string' && u.startsWith(self.location.origin))
      .filter((u) => !NEVER_CACHE.some((n) => new URL(u).pathname.endsWith(n)))
      .map((u) => cache.match(u).then((hit) => hit || cache.add(u).catch(() => undefined)))
  )));
});

function isGoogleFont(url) {
  return url.hostname === 'fonts.gstatic.com' || url.hostname === 'fonts.googleapis.com';
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;
  if (!sameOrigin && !isGoogleFont(url)) return;
  if (sameOrigin && NEVER_CACHE.some((n) => url.pathname.endsWith(n))) return;

  if (req.mode === 'navigate') {
    // Only the app shell (/ or /index.html) is cached as index.html; other pages
    // such as /get/ are cached under their own URL.
    const isShell = /\/(index\.html)?$/.test(url.pathname) && !/\/get\//.test(url.pathname);
    event.respondWith(
      fetch(req).then((res) => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(isShell ? 'index.html' : req, copy));
        }
        return res;
      }).catch(() => (isShell
        ? caches.match('index.html', { ignoreSearch: true }).then((r) => r || caches.match('./'))
        : caches.match(req, { ignoreSearch: true })))
    );
    return;
  }

  if (sameOrigin && /\.(m?js|wasm|json)$/.test(url.pathname)) {
    event.respondWith(caches.open(CACHE).then((cache) => {
      const network = fetch(req).then((res) => {
        if (res && res.ok) cache.put(req, res.clone());
        return res;
      });
      const timeout = new Promise((resolve) => setTimeout(resolve, 4000));
      const fallback = () => cache.match(req, { ignoreSearch: true });
      return Promise.race([network, timeout.then(fallback)])
        .then((res) => res || network)
        .catch(() => fallback().then((r) => r || Response.error()));
    }));
    return;
  }

  event.respondWith(
    caches.open(CACHE).then((cache) =>
      cache.match(req, { ignoreSearch: sameOrigin }).then((cached) => {
        const network = fetch(req).then((res) => {
          if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone());
          return res;
        }).catch(() => cached || Response.error());
        return cached || network;
      })
    )
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then((list) => {
      for (const c of list) { if ('focus' in c) return c.focus(); }
      return self.clients.openWindow('./?tab=now');
    }));
});
