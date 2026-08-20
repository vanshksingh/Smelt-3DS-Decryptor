// Smelt Next - Dev / Network First Service Worker
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  // Always fetch latest from network
  event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
});
