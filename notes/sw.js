/* Slate for Memex — offline shell. Network-first so updates arrive; cache fallback so the
   app opens with no connection. Only the app's own files are ever cached. */
const VERSION = 'slate-v1';
const SHELL = ['./', './index.html', './notes.css', './notes.js', './manifest.webmanifest', '../assets/favicon.svg'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;           // never touch the bridge or fonts
  if (url.pathname.includes('/api/')) return;
  e.respondWith(
    fetch(req).then((res) => {
      if (res.ok) caches.open(VERSION).then((c) => c.put(req, res.clone()));
      return res;
    }).catch(() => caches.match(req, { ignoreSearch: true }).then((hit) => hit || caches.match('./index.html')))
  );
});
