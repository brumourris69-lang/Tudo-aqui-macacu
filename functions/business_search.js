'use strict';

const { isDeepStrictEqual } = require('node:util');
const { publiclyVisible } = require('./content_visibility');
const INDEX = 'business_search_index';
const SOURCE = 'establishments';
const RATE = 'business_search_rate_limits';
const commerce = ['Comércio', 'Onde comer?', 'Saúde', 'Imóveis', 'Veículos', 'Pets',
  'Beleza', 'Academias', 'Educação', 'Hospedagem', 'Tecnologia'];
const services = ['Serviços', 'Profissionais'];

class SearchError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function normalize(value) {
  let result = value.toLowerCase();
  for (const [to, chars] of Object.entries({ a: 'áàâãäå', e: 'éèêë', i: 'íìîï',
    o: 'óòôõö', u: 'úùûü', c: 'ç', n: 'ñ', y: 'ýÿ' })) {
    result = result.replace(new RegExp(`[${chars}]`, 'g'), to);
  }
  return result.replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
}
function words(value) { const text = normalize(value); return text ? [...new Set(text.split(' '))] : []; }
function group(category) {
  const name = normalize(category);
  if (services.some((item) => normalize(item) === name)) return 'services';
  return commerce.some((item) => normalize(item) === name) ? 'commerce' : 'other';
}
function validId(id) {
  return typeof id === 'string' && id.trim().length > 0 && !id.includes('/') &&
    Buffer.byteLength(`establishments__${id}`) <= 1500 && !/^\.{1,2}$/.test(id);
}
function eligible(data, now, isTimestamp) {
  return publiclyVisible('establishments', data, now, isTimestamp);
}

function imageUrl(raw) {
  let value = raw.trim().replace(/&amp;/g, '&').replace(/^["']+|["']+$/g, '');
  const match = value.match(/https?:\/\/\S+/);
  if (match) value = match[0];
  value = value.replace(/[\]\)>,.;]+$/g, '');
  if (value.startsWith('http://res.cloudinary.com/')) value = value.replace('http:', 'https:');
  const marker = '/upload/';
  const pos = value.indexOf(marker);
  if (value.includes('res.cloudinary.com') && pos >= 0) {
    const start = pos + marker.length;
    if (!value.slice(start).startsWith('f_auto') && !value.slice(start).startsWith('q_auto')) {
      value = `${value.slice(0, start)}f_auto,q_auto,w_1600,c_limit/${value.slice(start)}`;
    }
  }
  try { const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) &&
    url.hostname && !url.username && !url.password ? value : ''; } catch { return ''; }
}
function buildEntry(id, data, { now, isTimestamp, authorizeImage = () => false }) {
  if (!validId(id) || !eligible(data, now, isTimestamp)) return null;
  const text = (key) => typeof data[key] === 'string' ? data[key] : '';
  const title = text('name').trim() ? text('name') : text('title');
  if (!title.trim()) return null;
  const description = (text('shortDescription').trim() ? text('shortDescription') : text('description'))
    .replace(/\s+/g, ' ').trim();
  const runes = [...description];
  const summary = runes.length <= 180 ? description : `${runes.slice(0, 179).join('')}…`;
  const cover = imageUrl(text('imageUrl')) || imageUrl(text('logoUrl'));
  const result = { id, sourceCollection: SOURCE, title, summary,
    category: text('category'), subcategory: text('subcategory'),
    imageUrl: cover && authorizeImage(cover) ? cover : '',
    type: 'establishment', destination: 'businessProfile' };
  const terms = [...new Set(words(`${title} ${result.category} ${result.subcategory} ${summary}`)
    .slice(0, 64).map((word) => word.slice(0, 24)))].sort();
  const prefixes = new Set();
  for (const term of terms) for (let n = 2; n <= term.length; n++) prefixes.add(term.slice(0, n));
  return { ...result, terms, prefixes: [...prefixes].sort(), group: group(result.category), schemaVersion: 1 };
}
function publicResult(entry) {
  const { id, sourceCollection, title, summary, category, subcategory, imageUrl, type, destination } = entry;
  return { id, sourceCollection, title, summary, category, subcategory, imageUrl, type, destination };
}
function parseRequest(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
    Object.keys(data).some((key) => !['query', 'filter', 'limit', 'cursor'].includes(key))) {
    throw new SearchError('invalid-argument', 'Pesquisa inválida.');
  }
  const { query, filter = 'all', limit = 20, cursor = null } = data;
  if (typeof query !== 'string' || query.length > 80 || !['all', 'commerce', 'services'].includes(filter) ||
    !Number.isInteger(limit) || limit < 1 || limit > 20) {
    throw new SearchError('invalid-argument', 'Pesquisa inválida.');
  }
  const terms = words(query);
  if (!terms.length || terms.length > 4 || terms.some((term) => term.length < 2 || term.length > 24)) {
    throw new SearchError('invalid-argument', 'Use 1–4 palavras de 2–24 caracteres.');
  }
  const queryKey = `${filter}:${[...terms].sort().join(' ')}`;
  if (cursor !== null && (typeof cursor !== 'object' || Array.isArray(cursor) ||
    Object.keys(cursor).length !== 2 || cursor.queryKey !== queryKey ||
    typeof cursor.lastIndexId !== 'string' || !cursor.lastIndexId.startsWith('establishments__') ||
    !validId(cursor.lastIndexId.slice('establishments__'.length)))) {
    throw new SearchError('invalid-argument', 'Cursor inválido.');
  }
  const anchor = [...terms].sort((a, b) => b.length - a.length || (a < b ? -1 : a > b ? 1 : 0))[0];
  return { terms, filter, limit, cursor, queryKey, anchor };
}
function localOnly(env = process.env) {
  return env.FUNCTIONS_EMULATOR === 'true' && /^demo-[a-z0-9-]+$/.test(env.GCLOUD_PROJECT || '') &&
    /^(127\.0\.0\.1|localhost):\d+$/.test(env.FIRESTORE_EMULATOR_HOST || '');
}
function createSearchBackend({ store, isTimestamp, now = Date.now, authorizeImage = () => false,
  requireAppCheck = true }) {
  const entry = (id, data) => buildEntry(id, data, { now: now(), isTimestamp, authorizeImage });
  async function synchronize(id) {
    if (!validId(id)) throw new SearchError('invalid-argument', 'ID inválido.');
    return store.transaction(async (tx) => {
      // Both reads precede writes. Source is read NOW, never from event payload.
      const current = await tx.source(id);
      const previous = await tx.index(id);
      const desired = entry(id, current);
      if (!desired) { if (previous) await tx.remove(id); return; }
      const comparable = previous && { ...previous };
      if (comparable) delete comparable.indexedAt;
      if (!isDeepStrictEqual(comparable, desired)) await tx.replace(id, desired);
    });
  }
  async function search(request) {
    if (!request.auth || !validId(request.auth.uid)) throw new SearchError('unauthenticated', 'Entre para pesquisar.');
    // Registered and anonymous Auth sessions can search public records only.
    if (requireAppCheck && !request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    const query = parseRequest(request.data);
    await store.admit(request.auth.uid, now());
    const results = [];
    let after = query.cursor?.lastIndexId || null;
    let scanned = 0;
    let exhausted = false;
    while (results.length < query.limit && scanned < 40 && !exhausted) {
      // Read only what could fill remaining result slots, not 40 every time.
      const count = Math.min(query.limit - results.length, 40 - scanned);
      const batch = await store.candidates({ ...query, after, count });
      if (batch.length > count) throw new Error('storage-limit');
      scanned += batch.length;
      exhausted = batch.length < count;
      if (!batch.length) break;
      after = batch[batch.length - 1].indexId;
      const matched = batch.filter((candidate) => validId(candidate.id) &&
        candidate.indexId === `establishments__${candidate.id}` && candidate.sourceCollection === SOURCE &&
        candidate.schemaVersion === 1 && Array.isArray(candidate.terms) &&
        query.terms.every((term) => candidate.terms.some((word) => typeof word === 'string' && word.startsWith(term))));
      const current = matched.length ? await store.sources(matched.map((candidate) => candidate.id)) : [];
      for (let i = 0; i < matched.length; i++) {
        const fresh = entry(matched[i].id, current[i]);
        if (fresh && (query.filter === 'all' || fresh.group === query.filter) &&
          query.terms.every((term) => fresh.terms.some((word) => word.startsWith(term)))) {
          results.push(publicResult(fresh));
        }
      }
    }
    // No extra lookahead read. Next page can be empty when exact batch ended.
    return { results, nextCursor: !exhausted && after ? { queryKey: query.queryKey, lastIndexId: after } : null };
  }
  return { synchronize, search };
}
module.exports = { INDEX, SOURCE, RATE, SearchError, normalize, words, group, validId,
  eligible, buildEntry, publicResult, parseRequest, localOnly, createSearchBackend };
