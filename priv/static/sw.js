// DocShare does not use a service worker. This no-op exists so requests for
// /sw.js (e.g. from a previously registered worker or a browser extension)
// don't 404, and so any stale worker unregisters itself and clears caches.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
      await self.registration.unregister();
      const clients = await self.clients.matchAll();
      clients.forEach((client) => client.navigate(client.url));
    })()
  );
});
