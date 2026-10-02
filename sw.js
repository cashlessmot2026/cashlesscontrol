const CACHE = 'cda-v1';
self.addEventListener('install', e => { self.skipWaiting(); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
// network-first con respaldo en caché (la app sigue abriendo sin red; los datos viven en la nube)
self.addEventListener('fetch', e => {
  const r = e.request;
  if (r.method !== 'GET' || !r.url.startsWith('http')) return;
  if (r.url.includes('firestore.googleapis.com') || r.url.includes('googleapis.com/google.firestore')) return;
  e.respondWith(
    fetch(r).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put(r, copy)).catch(() => {});
      return res;
    }).catch(() => caches.match(r).then(m => m || caches.match('./index.html')))
  );
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
    if (cs.length) return cs[0].focus();
    return self.clients.openWindow('./');
  }));
});
// Web Push real (FCM / VAPID): al recibir un push muestra alerta fuerte
self.addEventListener('push', e => {
  let d = {}; try { d = e.data.json(); } catch (_) { d = { title: 'Alerta', body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Alerta', {
    body: d.body || '', vibrate: [600, 200, 600, 200, 900], requireInteraction: true, tag: d.tag || 'alerta', renotify: true
  }));
});
