/* PDF Converter Web —— Service Worker
 *
 * 策略：
 * - 导航请求（页面）：网络优先，断网时回退缓存的壳页面
 * - /static/* 静态资源：缓存优先（命中即离线可用），未命中回源并写入缓存
 * - /api/* 与非 GET 请求：一律直通网络（转换必须联网，不缓存）
 * - 版本化缓存名：更新 SW 后 activate 阶段自动清理旧缓存
 */
const CACHE = 'pdfconv-v1';
const SHELL = ['/', '/static/icons/icon-192.png', '/static/icons/icon-512.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE)
      .then((c) => c.addAll(SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;                 // 提交任务等 POST 直通
  const url = new URL(req.url);
  if (url.pathname.startsWith('/api/')) return;     // API 一律直通网络

  // 页面导航：网络优先，断网回退缓存的壳
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((resp) => {
          const copy = resp.clone();
          caches.open(CACHE).then((c) => c.put('/', copy));
          return resp;
        })
        .catch(() => caches.match('/'))
    );
    return;
  }

  // 静态资源：缓存优先
  if (url.pathname.startsWith('/static/') || url.pathname === '/manifest.webmanifest') {
    e.respondWith(
      caches.match(req).then(
        (hit) =>
          hit ||
          fetch(req).then((resp) => {
            const copy = resp.clone();
            caches.open(CACHE).then((c) => c.put(req, copy));
            return resp;
          })
      )
    );
  }
});
