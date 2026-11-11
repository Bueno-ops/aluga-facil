/* Service worker do Aluga Fácil — app shell offline com atualização automática */
const VERSAO = '16';
const CACHE = 'aluga-facil-v' + VERSAO;
const ARQUIVOS = [
  './',
  './app.html?v=' + VERSAO,
  './index.html?v=' + VERSAO,
  './instalar.html?v=' + VERSAO,
  './qrcode-instalar.png',
  './qrcode-fixo.png',
  './manifest.json?v=' + VERSAO,
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
      .then((cache) => cache.addAll(ARQUIVOS.map((url) =>
        new Request(new URL(url, self.location).href, { cache: 'reload' })
      )))
      // Assume o controle na hora: a próxima abertura já usa a versão nova.
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('message', (evento) => {
  if (evento.data && evento.data.tipo === 'PULAR_ESPERA') {
    self.skipWaiting();
  }
});

self.addEventListener('activate', (evento) => {
  evento.waitUntil((async () => {
    const chaves = await caches.keys();
    const antigas = chaves.filter((chave) => chave !== CACHE && chave.indexOf('aluga-facil-') === 0);
    await Promise.all(antigas.map((chave) => caches.delete(chave)));
    // Assume as janelas abertas; a página detecta a troca e recarrega uma única vez.
    await self.clients.claim();
  })());
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
    '<body style="font-family:system-ui,sans-serif;background:#f4f4f4;color:#212529;display:grid;place-items:center;min-height:100vh;margin:0;text-align:center">' +
    '<main style="padding:24px"><h1 style="font-size:1.2rem">Você está offline</h1>' +
    '<p style="color:#6c757d">Abra o app uma vez com internet para liberar o modo offline.</p>' +
    '<p><button onclick="location.reload()" style="border:0;border-radius:999px;padding:10px 18px;background:#183c8f;color:#fff;font-weight:700">Tentar novamente</button></p>' +
    '</main></body></html>',
    { status: 200, headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
}

/** Nas páginas principais, busca com a versão atual para furar cache de CDN/navegador. */
function urlDaRede(requisicao) {
  const url = new URL(requisicao.url);
  if (/\/$|\/index\.html$|\/app\.html$|\/instalar\.html$/.test(url.pathname)) {
    url.searchParams.set('v', VERSAO);
  }
  return url.href;
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

  // Navegação: rede primeiro (sem cache HTTP e com versão na URL); se falhar, usa o cache.
  if (requisicao.mode === 'navigate') {
    evento.respondWith((async () => {
      try {
        const resposta = await fetch(urlDaRede(requisicao), { cache: 'reload' });
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
