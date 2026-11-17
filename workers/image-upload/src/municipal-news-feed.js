const sourceUrl = 'https://www.prefeituracachoeiras.com/blog-feed.xml';
const sourceProfile = 'https://www.prefeituracachoeiras.com/noticias';
const maxItems = 10;
const maxFeedBytes = 2_000_000;

async function readBoundedText(response) {
  const declared = response.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > maxFeedBytes)) {
    throw new Error('RSS too large');
  }
  if (!response.body) return '';
  const reader = response.body.getReader();
  const chunks = [];
  let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maxFeedBytes) {
        await reader.cancel();
        throw new Error('RSS too large');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
}

function decodeXml(value) {
  return value.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCodePoint(parseInt(code, 16)))
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .trim();
}

function xmlTag(xml, tag) {
  const match = xml.match(new RegExp('<' + tag + '(?:\\s[^>]*)?>([\\s\\S]*?)</' + tag + '\\s*>', 'i'));
  return match ? decodeXml(match[1]) : '';
}

function allowedUrl(value, host) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname === host &&
      !url.username && !url.password;
  } catch {
    return false;
  }
}

function parseItem(xml) {
  const title = xmlTag(xml, 'title').replace(/\s+/g, ' ').slice(0, 180);
  const rawDescription = xmlTag(xml, 'description');
  const description = rawDescription.replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ').trim().slice(0, 260);
  const permalink = xmlTag(xml, 'link');
  const id = xmlTag(xml, 'guid') || permalink;
  const timestamp = xmlTag(xml, 'pubDate');
  const imageMatch = xml.match(/<enclosure\b[^>]*\burl=(["'])(.*?)\1[^>]*>/i);
  const imageUrl = imageMatch ? decodeXml(imageMatch[2]) : '';
  const publishedAt = Date.parse(timestamp);
  if (!title || !id || !allowedUrl(permalink, 'www.prefeituracachoeiras.com') ||
      (imageUrl && !allowedUrl(imageUrl, 'static.wixstatic.com'))) return null;
  return {
    id: id.slice(0, 180),
    title,
    caption: description,
    imageUrl,
    permalink,
    timestamp: Number.isFinite(publishedAt) ? new Date(publishedAt).toISOString() : '',
  };
}

function parseFeed(xml) {
  if (typeof xml !== 'string' || xml.length > maxFeedBytes ||
      !/<rss\b/i.test(xml) || /<!DOCTYPE|<!ENTITY/i.test(xml)) {
    throw new Error('Invalid RSS');
  }
  const posts = [];
  for (const match of xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item\s*>/gi)) {
    const item = parseItem(match[1]);
    if (item) posts.push(item);
    if (posts.length === maxItems) break;
  }
  return {
    source: 'Prefeitura de Cachoeiras de Macacu',
    profileUrl: sourceProfile,
    posts,
  };
}

export { parseFeed };

export function createMunicipalNewsHandler({
  fetchFeed = fetch,
  now = () => Date.now(),
} = {}) {
  let cached = null;
  let expiresAt = 0;
  return async (request, env) => {
    const url = new URL(request.url);
    if (url.pathname !== '/v1/city-news' || url.search || url.hash) {
      return Response.json({ error: 'not-found' }, { status: 404 });
    }
    if (request.method !== 'GET') {
      return Response.json({ error: 'method-not-allowed' }, { status: 405 });
    }
    if (request.headers.has('origin')) {
      return Response.json({ error: 'permission-denied' }, { status: 403 });
    }
    if (!env.UPLOAD_RATE_LIMITER) {
      return Response.json({ error: 'feed-not-configured' }, {
        status: 503, headers: { 'Cache-Control': 'no-store' },
      });
    }
    if (cached && expiresAt > now()) {
      return Response.json(cached, {
        headers: { 'Cache-Control': 'public, max-age=300', 'X-Content-Type-Options': 'nosniff' },
      });
    }
    const ip = request.headers.get('cf-connecting-ip');
    if (!ip || ip.length > 64) {
      return Response.json({ error: 'unavailable' }, { status: 503 });
    }
    const rate = await env.UPLOAD_RATE_LIMITER.limit({ key: 'city-news:' + ip });
    if (!rate.success) {
      return Response.json({ error: 'rate-limited' }, {
        status: 429, headers: { 'Cache-Control': 'no-store' },
      });
    }
    try {
      const response = await fetchFeed(sourceUrl, {
        method: 'GET',
        headers: { Accept: 'application/rss+xml, application/xml, text/xml' },
        redirect: 'error',
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) throw new Error('RSS unavailable');
      const body = await readBoundedText(response);
      const payload = parseFeed(body);
      cached = payload;
      expiresAt = now() + 5 * 60 * 1000;
      return Response.json(payload, {
        headers: { 'Cache-Control': 'public, max-age=300', 'X-Content-Type-Options': 'nosniff' },
      });
    } catch (_) {
      return Response.json({ error: 'feed-unavailable' }, {
        status: 502, headers: { 'Cache-Control': 'no-store' },
      });
    }
  };
}
