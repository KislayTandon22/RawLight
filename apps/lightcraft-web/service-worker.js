// Full offline local cache for iPad Add to Home Screen and standalone execution.
// Caches HTML, webmanifest, SVG icon, PNG app icons, JS runtime, worker, and WASM binary locally.
const CACHE = "lightcraft-ipad-local-v2";
const ASSETS = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./lightcraft-icon.svg",
  "./icons/lightcraft-192.png",
  "./icons/lightcraft-512.png",
  "./icons/apple-touch-icon.png",
  "./lightcraft_web.js",
  "./lightcraft_web_bg.wasm",
  "./worker.js"
];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE).then(cache => {
      return cache.addAll(ASSETS);
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys => {
      return Promise.all(
        keys.filter(key => key.startsWith("lightcraft-ipad-") && key !== CACHE).map(key => caches.delete(key))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) return;

  // HTML navigation: try network, fall back to cached shell
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).then(response => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE).then(cache => cache.put("./index.html", clone));
        }
        return response;
      }).catch(() => caches.match("./index.html"))
    );
    return;
  }

  // Assets (WASM, JS, icons): Cache-first, fall back to network and cache response
  event.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(response => {
        if (response.ok && response.type === "basic") {
          const clone = response.clone();
          caches.open(CACHE).then(cache => cache.put(request, clone));
        }
        return response;
      });
    })
  );
});
