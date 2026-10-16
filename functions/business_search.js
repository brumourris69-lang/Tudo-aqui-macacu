'use strict';

const { isDeepStrictEqual } = require('node:util');
const { publiclyVisible } = require('./content_visibility');
const { projectPublic } = require('./public_content_projection');
const INDEX = 'business_search_index';
const SOURCE = 'establishments';
const ROUTES = 'routes';
const NEWS = 'news';
const EVENTS = 'events';
const JOBS = 'jobs';
const SOURCES = new Set([SOURCE, ROUTES, NEWS, EVENTS, JOBS]);
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
function validSourceCollection(collection) { return SOURCES.has(collection); }
function indexId(collection, id) { return `${collection}__${id}`; }
function parseIndexId(value) {
  if (typeof value !== 'string') return null;
  for (const collection of SOURCES) {
    const prefix = `${collection}__`;
    if (value.startsWith(prefix) && validId(value.slice(prefix.length), collection)) {
      return { sourceCollection: collection, id: value.slice(prefix.length) };
    }
  }
  return null;
}
function validId(id, collection = SOURCE) {
  if (!validSourceCollection(collection)) return false;
  return typeof id === 'string' && id.trim().length > 0 && !id.includes('/') &&
    Buffer.byteLength(indexId(collection, id)) <= 1500 && !/^\.{1,2}$/.test(id);
}
function eligible(data, now, isTimestamp, collection = SOURCE) {
  return publiclyVisible(collection, data, now, isTimestamp);
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
function buildEntry(id, data, { now, isTimestamp, authorizeImage = () => false,
  sourceCollection = SOURCE }) {
  if (!validId(id, sourceCollection) || !eligible(data, now, isTimestamp, sourceCollection)) return null;
  const text = (key) => typeof data[key] === 'string' ? data[key] : '';
  const title = text('name').trim() ? text('name') : text('title');
  if (!title.trim()) return null;
  const description = (text('shortDescription').trim() ? text('shortDescription') : text('description'))
    .replace(/\s+/g, ' ').trim();
  const runes = [...description];
  const summary = runes.length <= 180 ? description : `${runes.slice(0, 179).join('')}…`;
  const gallery = Array.isArray(data.galleryUrls) ? data.galleryUrls.find((value) => typeof value === 'string') : '';
  const cover = imageUrl(text('imageUrl')) || imageUrl(text('logoUrl')) ||
    ([ROUTES, NEWS, EVENTS].includes(sourceCollection) ? imageUrl(gallery || '') : '');
  const category = text('category').trim() ? text('category') :
    ([ROUTES, NEWS, EVENTS].includes(sourceCollection) ? text('type') : '');
  const location = [ROUTES, NEWS, EVENTS].includes(sourceCollection)
    ? (text('location').trim() ? text('location') : text('address')) :
      sourceCollection === JOBS
        ? (text('location').trim() ? text('location') : text('address')) : '';
  const company = sourceCollection === JOBS ? text('company').slice(0, 160) : '';
  const employmentType = sourceCollection === JOBS
    ? (text('employmentType').trim() ? text('employmentType') : text('type')).slice(0, 120) : '';
  const rawEventDate = sourceCollection === EVENTS
    ? (data.eventDate ?? data.date ?? data.startsAt) : null;
  const eventDate = sourceCollection !== EVENTS ? '' :
    typeof rawEventDate === 'string' ? rawEventDate.slice(0, 64) :
      isTimestamp(rawEventDate) && rawEventDate.toDate instanceof Function
        ? rawEventDate.toDate().toISOString().slice(0, 16) : '';
  const newsTerms = sourceCollection === NEWS
    ? [title.slice(0, 300), category.slice(0, 100), summary,
      location.slice(0, 160), text('additionalInfo').slice(0, 600)] : null;
  const eventTerms = sourceCollection === EVENTS
    ? [title.slice(0, 300), category.slice(0, 120), text('description').slice(0, 1000),
      location.slice(0, 160), eventDate] : null;
  const jobTerms = sourceCollection === JOBS
    ? [title.slice(0, 300), summary.slice(0, 1000), company,
      location.slice(0, 160), employmentType, category.slice(0, 120)] : null;
  const searchDescription = [summary, location, sourceCollection === NEWS ? text('additionalInfo').slice(0, 600) : '']
    .filter(Boolean).join(' ');
  const result = { id, sourceCollection, title, summary,
    category, subcategory: text('subcategory'),
    imageUrl: cover && authorizeImage(cover) ? cover : '',
    type: sourceCollection === ROUTES ? 'tourism' : sourceCollection === NEWS ? 'news' :
      sourceCollection === EVENTS ? 'events' : sourceCollection === JOBS ? 'jobs' : 'establishment',
    destination: sourceCollection === ROUTES ? 'touristSpotDetail' :
      sourceCollection === NEWS ? 'newsArticle' : sourceCollection === EVENTS ? 'eventDetail' :
        sourceCollection === JOBS ? 'jobDetail' : 'businessProfile',
    ...(sourceCollection === EVENTS ? { eventDate, location } : {}),
    ...(sourceCollection === JOBS ? { company, location, employmentType } : {}) };
  const searchable = jobTerms ? jobTerms.join(' ') : eventTerms ? eventTerms.join(' ') : newsTerms ? newsTerms.join(' ') :
    `${title} ${result.category} ${result.subcategory} ${searchDescription}`;
  const terms = [...new Set(words(searchable)
    .slice(0, 64).map((word) => word.slice(0, 24)))].sort();
  const prefixes = new Set();
  for (const term of terms) for (let n = 2; n <= term.length; n++) prefixes.add(term.slice(0, n));
  return { ...result, terms, prefixes: [...prefixes].sort(),
    group: sourceCollection === ROUTES ? 'tourism' : sourceCollection === NEWS ? 'news' :
      sourceCollection === EVENTS ? 'events' : sourceCollection === JOBS ? 'jobs' : group(result.category),
    schemaVersion: 2 };
}
function publicResult(entry) {
  const { id, sourceCollection, title, summary, category, subcategory, imageUrl, type, destination } = entry;
  return { id, sourceCollection, title, summary, category, subcategory, imageUrl, type, destination,
    ...(sourceCollection === EVENTS ? { eventDate: entry.eventDate || '', location: entry.location || '' } : {}),
    ...(sourceCollection === JOBS ? { company: entry.company || '', location: entry.location || '',
      employmentType: entry.employmentType || '' } : {}) };
}
function parseRequest(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
    Object.keys(data).some((key) => !['query', 'filter', 'limit', 'cursor'].includes(key))) {
    throw new SearchError('invalid-argument', 'Pesquisa inválida.');
  }
  const { query, filter = 'all', limit = 20, cursor = null } = data;
  if (typeof query !== 'string' || query.length > 80 || !['all', 'commerce', 'services', 'tourism', 'news', 'events', 'jobs'].includes(filter) ||
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
    !parseIndexId(cursor.lastIndexId) ||
    (filter === 'tourism' && parseIndexId(cursor.lastIndexId)?.sourceCollection !== ROUTES) ||
    (filter === 'news' && parseIndexId(cursor.lastIndexId)?.sourceCollection !== NEWS) ||
    (filter === 'events' && parseIndexId(cursor.lastIndexId)?.sourceCollection !== EVENTS) ||
    (filter === 'jobs' && parseIndexId(cursor.lastIndexId)?.sourceCollection !== JOBS) ||
    (!['all', 'tourism', 'news', 'events', 'jobs'].includes(filter) && parseIndexId(cursor.lastIndexId)?.sourceCollection !== SOURCE))) {
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
  const entry = (id, data, sourceCollection = SOURCE) => buildEntry(id, data,
    { now: now(), isTimestamp, authorizeImage, sourceCollection });
  async function synchronize(collection, id) {
    if (id === undefined) { id = collection; collection = SOURCE; }
    if (!validId(id, collection)) throw new SearchError('invalid-argument', 'ID inválido.');
    return store.transaction(async (tx) => {
      // Both reads precede writes. Source is read NOW, never from event payload.
      const current = await tx.source(collection, id);
      const previous = await tx.index(collection, id);
      const desired = entry(id, current, collection);
      if (!desired) { if (previous) await tx.remove(collection, id); return; }
      const comparable = previous && { ...previous };
      if (comparable) delete comparable.indexedAt;
      if (!isDeepStrictEqual(comparable, desired)) await tx.replace(collection, id, desired);
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
      const matched = batch.filter((candidate) => validId(candidate.id, candidate.sourceCollection) &&
        candidate.indexId === indexId(candidate.sourceCollection, candidate.id) &&
        (query.filter === 'all' || (query.filter === 'tourism'
          ? candidate.sourceCollection === ROUTES : query.filter === 'news'
            ? candidate.sourceCollection === NEWS : query.filter === 'events'
              ? candidate.sourceCollection === EVENTS : query.filter === 'jobs'
                ? candidate.sourceCollection === JOBS : candidate.sourceCollection === SOURCE)) &&
        (candidate.schemaVersion === 2 ||
          (candidate.sourceCollection === SOURCE && candidate.schemaVersion === 1)) &&
        Array.isArray(candidate.terms) &&
        query.terms.every((term) => candidate.terms.some((word) => typeof word === 'string' && word.startsWith(term))));
      const current = matched.length ? await store.sources(matched.map((candidate) => ({
        sourceCollection: candidate.sourceCollection, id: candidate.id,
      }))) : [];
      for (let i = 0; i < matched.length; i++) {
        const fresh = entry(matched[i].id, current[i], matched[i].sourceCollection);
        if (fresh && (query.filter === 'all' || fresh.group === query.filter) &&
          query.terms.every((term) => fresh.terms.some((word) => word.startsWith(term)))) {
          results.push(publicResult(fresh));
        }
      }
    }
    // No extra lookahead read. Next page can be empty when exact batch ended.
    return { results, nextCursor: !exhausted && after ? { queryKey: query.queryKey, lastIndexId: after } : null };
  }
  async function resolveTourism(request) {
    if (!request.auth || !validId(request.auth.uid)) throw new SearchError('unauthenticated', 'Sessão necessária.');
    if (requireAppCheck && !request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    if (!request.data || typeof request.data !== 'object' || Array.isArray(request.data) ||
        Object.keys(request.data).length !== 1 || !validId(request.data.id, ROUTES)) {
      throw new SearchError('invalid-argument', 'Local turístico inválido.');
    }
    await store.admit(request.auth.uid, now(), 'tourism-detail');
    const data = await store.readSource(ROUTES, request.data.id);
    const current = entry(request.data.id, data, ROUTES);
    if (!current) return null;
    const detail = projectPublic(data, isTimestamp, ROUTES);
    if (detail === null) return null;
    return { id: request.data.id, data: detail };
  }
  async function resolveNews(request) {
    if (!request.auth || !validId(request.auth.uid)) throw new SearchError('unauthenticated', 'Sessão necessária.');
    if (requireAppCheck && !request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    if (!request.data || typeof request.data !== 'object' || Array.isArray(request.data) ||
        Object.keys(request.data).length !== 1 || !validId(request.data.id, NEWS)) {
      throw new SearchError('invalid-argument', 'Notícia inválida.');
    }
    await store.admit(request.auth.uid, now(), 'news-detail');
    const data = await store.readSource(NEWS, request.data.id);
    const current = entry(request.data.id, data, NEWS);
    if (!current) return { status: 'unavailable' };
    const description = typeof data.description === 'string' ? data.description : data.shortDescription;
    const detail = { title: current.title };
    // Firestore already bounds a source document to 1 MiB. Keep the article
    // body complete instead of silently clipping published editorial content.
    if (typeof description === 'string') detail.description = description;
    for (const key of ['category', 'subcategory', 'additionalInfo']) {
      const max = key === 'additionalInfo' ? 3000 : 120;
      if (typeof data[key] === 'string') detail[key] = data[key].slice(0, max);
    }
    const images = [data.imageUrl, ...(Array.isArray(data.galleryUrls) ? data.galleryUrls : [])];
    const cover = images.find((item) => {
      if (typeof item !== 'string' || item.length > 2048) return false;
      try { const url = new URL(item); return url.protocol === 'https:' && !url.username && !url.password; }
      catch { return false; }
    });
    if (cover) detail.imageUrl = cover;
    for (const key of ['publishedAt', 'date', 'createdAt', 'updatedAt']) {
      const value = data[key];
      if (isTimestamp(value)) detail[key] = { _publicTimestamp: [value.seconds, value.nanoseconds] };
      else if (typeof value === 'string' && value.length <= 64) detail[key] = value;
    }
    return { status: 'available', id: request.data.id, data: detail };
  }
  async function resolveEvent(request) {
    if (!request.auth || !validId(request.auth.uid)) throw new SearchError('unauthenticated', 'Sessão necessária.');
    if (requireAppCheck && !request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    if (!request.data || typeof request.data !== 'object' || Array.isArray(request.data) ||
        Object.keys(request.data).length !== 1 || !validId(request.data.id, EVENTS)) {
      throw new SearchError('invalid-argument', 'Evento inválido.');
    }
    await store.admit(request.auth.uid, now(), 'event-detail');
    const data = await store.readSource(EVENTS, request.data.id);
    const current = entry(request.data.id, data, EVENTS);
    if (!current) return { status: 'unavailable' };

    const detail = { title: current.title };
    const description = typeof data.description === 'string' ? data.description : data.shortDescription;
    if (typeof description === 'string') detail.description = description;
    if (current.category) detail.category = current.category.slice(0, 120);
    if (current.location) detail.location = current.location.slice(0, 240);
    const dateValue = data.eventDate ?? data.date ?? data.startsAt;
    if (typeof dateValue === 'string') detail.eventDate = dateValue.slice(0, 120);
    else if (isTimestamp(dateValue)) {
      detail.eventDate = { _publicTimestamp: [dateValue.seconds, dateValue.nanoseconds] };
    }
    const images = [data.imageUrl, ...(Array.isArray(data.galleryUrls) ? data.galleryUrls : [])];
    const cover = images.find((item) => {
      if (typeof item !== 'string' || item.length > 2048) return false;
      try { const url = new URL(item); return url.protocol === 'https:' && !url.username && !url.password; }
      catch { return false; }
    });
    if (cover) detail.imageUrl = cover;
    return { status: 'available', id: request.data.id, data: detail };
  }
  async function resolveJob(request) {
    if (!request.auth || !validId(request.auth.uid)) throw new SearchError('unauthenticated', 'Sessão necessária.');
    if (requireAppCheck && !request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    if (!request.data || typeof request.data !== 'object' || Array.isArray(request.data) ||
        Object.keys(request.data).length !== 1 || !validId(request.data.id, JOBS)) {
      throw new SearchError('invalid-argument', 'Vaga inválida.');
    }
    await store.admit(request.auth.uid, now(), 'jobs-detail');
    const data = await store.readSource(JOBS, request.data.id);
    const current = entry(request.data.id, data, JOBS);
    if (!current) return { status: 'unavailable' };

    // The jobs schema only documents contact without a public-application
    // policy. Never return contact channels or administrative fields here.
    const detail = { title: current.title };
    const description = typeof data.description === 'string' ? data.description : data.shortDescription;
    if (typeof description === 'string') detail.description = description;
    if (current.category) detail.category = current.category.slice(0, 120);
    if (current.location) detail.location = current.location.slice(0, 240);
    if (current.company) detail.company = current.company.slice(0, 160);
    if (current.employmentType) detail.employmentType = current.employmentType.slice(0, 120);
    // Do not reinterpret applicationDeadline or updatedAt as publication date.
    return { status: 'available', id: request.data.id, data: detail };
  }
  return { synchronize, search, resolveTourism, resolveNews, resolveEvent, resolveJob };
}
module.exports = { INDEX, SOURCE, ROUTES, NEWS, EVENTS, JOBS, RATE, SearchError, normalize, words, group, validId,
  validSourceCollection, indexId, parseIndexId,
  eligible, buildEntry, publicResult, parseRequest, localOnly, createSearchBackend };
