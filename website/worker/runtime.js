// YouTube is fetched on the server so visitors need no third-party CORS proxy.
export const CHANNEL_ID = 'UCff1lMuioQfmA9xE6EA7qpQ';
export const FEED_URL = 'https://www.youtube.com/feeds/videos.xml?channel_id=' + CHANNEL_ID;
export const VIDEO_COUNT = 9;
const TTL = 10 * 60 * 1000;

function decodeXml(value) {
  return value.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (match, code) => {
      if (code.startsWith('#')) {
        const point = code[1].toLowerCase() === 'x' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
        return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff) ? String.fromCodePoint(point) : '';
      }
      return {amp: '&', lt: '<', gt: '>', quot: '"', apos: "'"}[code.toLowerCase()];
    }).trim();
}

export function parseFeed(xml) {
  if (typeof xml !== 'string' || xml.length > 2 * 1024 * 1024) throw new Error('Invalid feed');
  const seen = new Set();
  const videos = [];
  for (const entry of xml.matchAll(/<entry\b[^>]*>([\s\S]*?)<\/entry>/g)) {
    const field = tag => decodeXml(entry[1].match(new RegExp('<' + tag + '(?:\\s[^>]*)?>([\\s\\S]*?)<\\/' + tag + '>'))?.[1] || '');
    const id = field('yt:videoId');
    const title = field('title');
    const published = field('published');
    const timestamp = Date.parse(published);
    if (!/^[\w-]{11}$/.test(id) || seen.has(id) || !title || !Number.isFinite(timestamp)) continue;
    seen.add(id);
    videos.push({id, title: title.slice(0, 500), published: new Date(timestamp).toISOString()});
  }
  videos.sort((a, b) => Date.parse(b.published) - Date.parse(a.published));
  if (videos.length < VIDEO_COUNT) throw new Error('Feed contains fewer than nine videos');
  return videos.slice(0, VIDEO_COUNT);
}

export function createWorker(assets, snapshot, fetchFeed = fetch) {
  let cached = null;
  let inFlight = null;
  const json = data => new Response(JSON.stringify(data), {headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': data.stale ? 'no-store' : 'public, max-age=600',
    'x-content-type-options': 'nosniff'
  }});
  async function getLatest() {
    if (cached && Date.now() - Date.parse(cached.fetchedAt) < TTL) return cached;
    if (inFlight) return inFlight;
    inFlight = (async () => {
      const response = await fetchFeed(FEED_URL, {
        headers: {accept: 'application/atom+xml, application/xml, text/xml'},
        signal: AbortSignal.timeout(8000), cf: {cacheTtl: 600, cacheEverything: true}
      });
      if (!response.ok) throw new Error('YouTube feed unavailable');
      const xml = await response.text();
      cached = {videos: parseFeed(xml), fetchedAt: new Date().toISOString(), stale: false};
      return cached;
    })();
    try { return await inFlight; } finally { inFlight = null; }
  }
  return {
    async fetch(request, env, ctx) {
      const url = new URL(request.url);
      const path = url.pathname;
      if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', {status: 405, headers: {allow: 'GET, HEAD'}});
      if (path === '/api/latest-videos') {
        const cache = globalThis.caches?.default;
        const key = new Request(url.origin + path + '?limit=' + VIDEO_COUNT);
        const stored = cache ? await cache.match(key).catch(() => null) : null;
        let response = stored;
        if (!response) {
          try {
            response = json(await getLatest());
            if (cache) {
              const write = cache.put(key, response.clone()).catch(() => {});
              if (ctx?.waitUntil) ctx.waitUntil(write); else await write;
            }
          } catch (_) {
            response = json({...cached || snapshot, stale: true});
          }
        }
        return request.method === 'HEAD' ? new Response(null, response) : response;
      }
      const assetPath = path.endsWith('/') ? path + 'index.html' : path;
      const asset = assets[assetPath];
      if (!asset) {
        if (assets[path + '/index.html']) return Response.redirect(url.origin + path + '/' + url.search, 308);
        return new Response('Not found', {status: 404});
      }
      const headers = {
        'content-type': asset.type,
        'cache-control': assetPath.startsWith('/downloads/') ? 'public, max-age=0, must-revalidate' : 'public, max-age=300',
        'x-content-type-options': 'nosniff',
        'referrer-policy': 'strict-origin-when-cross-origin'
      };
      if (assetPath.startsWith('/downloads/')) headers['content-disposition'] = 'attachment; filename="' + assetPath.split('/').pop() + '"';
      return new Response(request.method === 'HEAD' ? null : Uint8Array.from(atob(asset.data), c => c.charCodeAt(0)), {headers});
    }
  };
}
