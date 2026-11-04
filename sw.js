/* Service worker do Aluga Fácil — app shell offline */
const CACHE = 'aluga-facil-v11';
const ARQUIVOS = [
  './',
  './app.html',
  './index.html',
  './instalar.html',
  './qrcode-instalar.png',
  './qrcode-fixo.png',
  './manifest.json',
  './icon.svg',
  './icon-48.png',
  './icon-72.png',
  './icon-96.png',
  './icon-128.png',
  './icon-144.png',
  './icon-152.png',
  './icon-192.png',
  './icon-256.png',
  './icon-384.png',
  './icon-512.png',
  './icon-maskable-192.png',
  './icon-maskable-512.png'
];

self.addEventListener('install', (evento) => {
  evento.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(ARQUIVOS))
  );
});

// A nova versão só entra quando o usuário toca em "Atualizar" (ou na próxima abertura).
self.addEventListener('message', (evento) => {
  if (evento.data && evento.data.tipo === 'PULAR_ESPERA') {
    self.skipWaiting();
  }
});

self.addEventListener('activate', (evento) => {
  evento.waitUntil(
    caches.keys()
      .then((chaves) => Promise.all(chaves.filter((chave) => chave !== CACHE).map((chave) => caches.delete(chave))))
      .then(() => self.clients.claim())
  );
});

/** Busca o app no cache, aceitando variações de query string. */
function appEmCache() {
  return caches.match('./app.html', { ignoreSearch: true })
    .then((resposta) => resposta || caches.match('./index.html', { ignoreSearch: true }))
    .then((resposta) => resposta || caches.match('./', { ignoreSearch: true }));
}

/** Página de aviso usada apenas se nem o cache existir. */
function paginaOffline() {
  return new Response(
    '<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>Aluga Fácil — offline</title></head>' +
    '<body style="font-family:system-ui,sans-serif;background:#f4f6f8;color:#0f172a;display:grid;place-items:center;min-height:100vh;margin:0;text-align:center">' +
    '<main style="padding:24px"><h1 style="font-size:1.2rem">Você está offline</h1>' +
    '<p style="color:#5d6b80">Abra o app uma vez com internet para liberar o modo offline.</p>' +
    '<p><button onclick="location.reload()" style="border:0;border-radius:999px;padding:10px 18px;background:#0f766e;color:#fff;font-weight:700">Tentar novamente</button></p>' +
    '</main></body></html>',
    { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
}

self.addEventListener('fetch', (evento) => {
  const requisicao = evento.request;
  if (requisicao.method !== 'GET') return;

  let url;
  try {
    url = new URL(requisicao.url);
  } catch (erro) {
    return;
  }
  if (url.origin !== self.location.origin) return;

  // Navegação: rede primeiro; se falhar OU vier erro (ex.: 502 de proxy), usa o app em cache.
  if (requisicao.mode === 'navigate') {
    evento.respondWith((async () => {
      try {
        const resposta = await fetch(requisicao);
        if (!resposta || !resposta.ok) throw new Error('HTTP ' + (resposta ? resposta.status : 'sem resposta'));
        const copia = resposta.clone();
        caches.open(CACHE).then((cache) => cache.put(requisicao, copia)).catch(() => {});
        return resposta;
      } catch (erro) {
        const emCache = await caches.match(requisicao, { ignoreSearch: true }).catch(() => null);
        if (emCache) return emCache;
        const app = await appEmCache().catch(() => null);
        return app || paginaOffline();
      }
    })());
    return;
  }

  // Arquivos locais: cache primeiro, atualizando em segundo plano.
  evento.respondWith((async () => {
    const emCache = await caches.match(requisicao, { ignoreSearch: true }).catch(() => null);
    const daRede = fetch(requisicao)
      .then((resposta) => {
        if (resposta && resposta.ok) {
          const copia = resposta.clone();
          caches.open(CACHE).then((cache) => cache.put(requisicao, copia)).catch(() => {});
        }
        return resposta;
      })
      .catch(() => emCache);
    return emCache || daRede || paginaOffline();
  })());
});
