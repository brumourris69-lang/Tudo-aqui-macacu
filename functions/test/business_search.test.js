'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('../business_search');
const { createFirestoreStore } = require('../business_search_firestore');
const parity = require('./fixtures/business_search_parity.json');

class Stamp { constructor(ms) { this.ms = ms; this.seconds = Math.floor(ms / 1000); this.nanoseconds = (ms % 1000) * 1e6; } toMillis() { return this.ms; } toDate() { return new Date(this.ms); } }
const now = Date.UTC(2026, 9, 8);
const options = { now, isTimestamp: (value) => value instanceof Stamp, authorizeImage: () => false };
const doc = (extra = {}) => ({ published: true, name: 'Elétrica Vieira', category: 'Serviços',
  subcategory: 'Eletricista', description: 'Manutenção residencial', ...extra });
const request = (extra = {}) => ({ auth: { uid: 'user', token: { firebase: { sign_in_provider: 'google.com' } } },
  app: { appId: 'demo-app' }, data: { query: 'eletrica', ...extra } });

test('Node matches shared Dart normalization category and projection fixtures', () => {
  for (const sample of parity.normalization) assert.equal(core.normalize(sample.input), sample.expected);
  for (const [category, expected] of Object.entries(parity.categories)) assert.equal(core.group(category), expected);
  const sample = parity.projection;
  const result = core.buildEntry(sample.id, sample.data, options);
  assert.deepEqual(core.publicResult(result), sample.expected);
  assert.deepEqual(result.terms, sample.terms);
});

function memory() {
  const sources = new Map(); const index = new Map();
  const metrics = { indexReads: 0, sourceReads: 0, writes: 0, admissions: 0, admissionScopes: [] };
  let queue = Promise.resolve();
  const store = {
    sourcesMap: sources, indexMap: index, metrics,
    transaction(body) {
      const work = queue.then(() => body({
        source: async (collection, id) => sources.get(core.indexId(collection, id)) || null,
        index: async (collection, id) => index.get(core.indexId(collection, id)) || null,
        replace: async (collection, id, entry) => { metrics.writes++; index.set(core.indexId(collection, id), { ...entry, indexedAt: now }); },
        remove: async (collection, id) => { metrics.writes++; index.delete(core.indexId(collection, id)); },
      })); queue = work.catch(() => {}); return work;
    },
    async candidates({ anchor, filter, after, count }) {
      const found = [...index.entries()].map(([indexId, entry]) => ({ ...entry, indexId }))
        .filter((entry) => entry.prefixes.includes(anchor) && (filter === 'all' ||
          (filter === 'tourism' ? entry.type === 'tourism' : entry.group === filter)) &&
          (!after || entry.indexId > after)).sort((a, b) => a.indexId < b.indexId ? -1 : 1).slice(0, count);
      metrics.indexReads += found.length; return found;
    },
    async sources(items) { metrics.sourceReads += items.length; return items.map(({ sourceCollection, id }) => sources.get(core.indexId(sourceCollection, id)) || null); },
    async readSource(collection, id) { return sources.get(core.indexId(collection, id)) || null; },
    async admit(_uid, _time, scope = 'search') { metrics.admissions++; metrics.admissionScopes.push(scope); },
  };
  const backend = core.createSearchBackend({ store, isTimestamp: options.isTimestamp, now: () => now });
  return { store, backend, async add(id, data = doc()) { sources.set(core.indexId(core.SOURCE, id), data); await backend.synchronize(id); },
    async addFrom(collection, id, data) { sources.set(core.indexId(collection, id), data); await backend.synchronize(collection, id); } };
}

test('normalization accents combining marks punctuation and shared category policy', () => {
  assert.equal(core.normalize(' ÁGUA — Elétrica\t VIEIRA '), 'agua eletrica vieira');
  assert.equal(core.normalize('E\u0301letrica'), 'eletrica');
  assert.deepEqual(core.words('Elétrica elétrica Vieira'), ['eletrica', 'vieira']);
  for (const category of ['Comércio', 'Onde comer?', 'Tecnologia', 'Saúde', 'Hospedagem']) assert.equal(core.group(category), 'commerce');
  assert.equal(core.group('Profissionais'), 'services'); assert.equal(core.group('desconhecido'), 'other');
});
test('allowlisted projection original ID optional absence unicode summary and images fail closed', () => {
  const entry = core.buildEntry('OriginalID', doc({ adminEmail: 'secret', phone: 'secret', open: false,
    imageUrl: 'https://example.com/a.png', description: '😀'.repeat(181) }), options);
  assert.equal(entry.id, 'OriginalID'); assert.equal(entry.imageUrl, '');
  assert.equal([...entry.summary].length, 180); assert.ok(!JSON.stringify(entry).includes('secret'));
  assert.deepEqual(Object.keys(core.publicResult(entry)), ['id', 'sourceCollection', 'title', 'summary',
    'category', 'subcategory', 'imageUrl', 'type', 'destination']);
  assert.equal(core.buildEntry('id', { published: true, title: 'Nome' }, options).category, '');
  assert.equal(core.buildEntry('id', { published: true }, options), null);
  const image = core.buildEntry('id', doc({ imageUrl: 'http://res.cloudinary.com/demo/image/upload/test.png' }),
    { ...options, authorizeImage: () => true });
  assert.equal(image.imageUrl, 'https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_1600,c_limit/test.png');
});
test('create edit category change repeated events suppress redundant writes', async () => {
  const m = memory(); await m.add('one'); assert.equal(m.store.metrics.writes, 1);
  await m.backend.synchronize('one'); assert.equal(m.store.metrics.writes, 1);
  m.store.sourcesMap.set('establishments__one', doc({ name: 'Padaria Nova', category: 'Onde comer?' }));
  await m.backend.synchronize('one');
  assert.equal(m.store.indexMap.get('establishments__one').group, 'commerce');
  assert.ok(!m.store.indexMap.get('establishments__one').prefixes.includes('eletrica'));
  assert.equal(m.store.metrics.writes, 2);
});
test('unpublish deactivate delete expiry invalid state removes projection', async () => {
  const m = memory();
  for (const change of [{ published: false }, { active: false }, { expiresAt: new Stamp(now) },
    { expiresAt: null }, { active: 'true' }, { published: 'true' }]) {
    await m.add('one'); m.store.sourcesMap.set('establishments__one', doc(change));
    await m.backend.synchronize('one'); assert.equal(m.store.indexMap.size, 0);
  }
  await m.add('one'); m.store.sourcesMap.delete('establishments__one');
  await m.backend.synchronize('one'); await m.backend.synchronize('one');
  assert.equal(m.store.indexMap.size, 0);
});
test('concurrent repeated and late events always converge to current state', async () => {
  const m = memory(); await m.add('one');
  m.store.sourcesMap.set('establishments__one', doc({ name: 'Último nome' }));
  await Promise.all([m.backend.synchronize('one'), m.backend.synchronize('one'), m.backend.synchronize('one')]);
  assert.equal(m.store.indexMap.get('establishments__one').title, 'Último nome');
  assert.equal(m.store.metrics.writes, 2);
  m.store.sourcesMap.delete('establishments__one'); await m.backend.synchronize('one'); // old event after delete
  assert.equal(m.store.indexMap.size, 0);
});
test('accents prefixes multiple words filters and deterministic cursor identity', async () => {
  const m = memory(); await m.add('a'); await m.add('b', doc({ category: 'Tecnologia' }));
  const all = await m.backend.search(request({ query: 'ELÉTRICA vie' })); assert.equal(all.results.length, 2);
  assert.equal((await m.backend.search(request({ filter: 'services' }))).results[0].id, 'a');
  assert.equal((await m.backend.search(request({ filter: 'commerce' }))).results[0].id, 'b');
  assert.equal(core.parseRequest({ query: 'vieira silvaa' }).anchor, core.parseRequest({ query: 'silvaa vieira' }).anchor);
});
test('routes build a bounded public projection with title category description and location terms', () => {
  const route = core.buildEntry('route-1', { published: true, active: true,
    title: 'Cachoeira Véu de Noiva', category: 'Cachoeiras', description: 'Queda natural',
    location: 'Bacia do Rio Macacu', maps: 'https://maps.invalid', ownerEmail: 'private@example.invalid' },
  { ...options, sourceCollection: core.ROUTES });
  assert.equal(route.indexId, undefined);
  assert.equal(route.sourceCollection, 'routes'); assert.equal(route.type, 'tourism');
  assert.equal(route.destination, 'touristSpotDetail');
  assert.ok(route.terms.includes('macacu')); assert.ok(route.prefixes.includes('cach'));
  assert.ok(!JSON.stringify(route).includes('ownerEmail'));
  assert.equal(core.buildEntry('draft', { title: 'Privado' }, { ...options, sourceCollection: core.ROUTES }), null);
});
test('demo tourism detail reuses the allowlisted route projection', async () => {
  const m = memory();
  await m.addFrom('routes', 'route-safe', { published: true, active: true,
    title: 'Trilha fictícia', type: 'Trilhas', description: 'Descrição pública',
    maps: 'https://maps.example/trilha', link: 'javascript:alert(1)',
    galleryUrls: ['https://images.example/1.jpg', 'http://images.example/2.jpg',
      'https://user:secret@images.example/3.jpg', 'https://images.example/4.jpg'],
    phone: 'PRIVATE-PHONE', contact: 'PRIVATE-CONTACT', internalNote: 'PRIVATE-NOTE' });
  const response = await m.backend.resolveTourism({ auth: { uid: 'visitor' },
    app: { appId: 'demo-app' }, data: { id: 'route-safe' } });
  assert.deepEqual(response, { id: 'route-safe', data: {
    published: true, active: true, title: 'Trilha fictícia', type: 'Trilhas', description: 'Descrição pública',
    maps: 'https://maps.example/trilha', galleryUrls: ['https://images.example/1.jpg', 'https://images.example/4.jpg'],
  } });
  assert.equal(JSON.stringify(response).includes('PRIVATE-'), false);
});
test('news index uses public fields, bounded terms and news identity', () => {
  const news = core.buildEntry('same-id', { published: true, active: true,
    title: 'Últimas notícias de Macacu', category: 'Cidade', description: 'Ação pública',
    location: 'Cachoeiras de Macacu', additionalInfo: 'Serviço e comunidade',
    imageUrl: 'https://images.invalid/news.jpg', targetEmail: 'private@example.invalid',
    adminNotes: 'private' }, { ...options, sourceCollection: core.NEWS });
  assert.equal(news.sourceCollection, 'news');
  assert.equal(news.type, 'news'); assert.equal(news.group, 'news');
  assert.equal(news.destination, 'newsArticle');
  assert.ok(news.terms.includes('ultimas')); assert.ok(news.terms.includes('comunidade'));
  assert.ok(news.prefixes.includes('cachoeiras'));
  assert.equal(news.imageUrl, '');
  assert.equal(core.parseIndexId('news__same-id').sourceCollection, 'news');
  assert.equal(core.parseIndexId('establishments__same-id').sourceCollection, 'establishments');
  assert.ok(!JSON.stringify(core.publicResult(news)).includes('private'));
  assert.equal(core.buildEntry('draft', { published: false, title: 'Rascunho' },
    { ...options, sourceCollection: core.NEWS }), null);
});
test('events projection indexes public title, date and place without confusing event date with expiry', () => {
  const event = core.buildEntry('same-id', { published: true, active: true,
    title: 'Festival Fictício Macacu', category: 'Cultura', description: 'Música e feira comunitária',
    eventDate: '15/08/2020 às 18h', location: 'Praça Central Macacu',
    imageUrl: 'https://images.invalid/evento.jpg', galleryUrls: ['https://images.invalid/extra.jpg'],
    contact: 'private@example.invalid', phone: 'private', ownerEmail: 'private@example.invalid',
    privateNotes: 'DO_NOT_INDEX' }, { ...options, sourceCollection: core.EVENTS });
  assert.equal(event.sourceCollection, 'events'); assert.equal(event.type, 'events');
  assert.equal(event.group, 'events'); assert.equal(event.destination, 'eventDetail');
  assert.equal(event.eventDate, '15/08/2020 às 18h'); assert.equal(event.location, 'Praça Central Macacu');
  assert.ok(event.prefixes.includes('festival')); assert.ok(event.prefixes.includes('comunitaria'));
  assert.ok(event.prefixes.includes('central')); assert.ok(event.prefixes.includes('2020'));
  assert.equal(event.imageUrl, '');
  const result = core.publicResult(event);
  assert.equal(result.eventDate, event.eventDate); assert.equal(result.location, event.location);
  assert.ok(!JSON.stringify(result).includes('private'));
  assert.ok(!JSON.stringify(event).includes('DO_NOT_INDEX'));
  assert.equal(core.parseIndexId('events__same-id').sourceCollection, 'events');
  assert.equal(core.buildEntry('hidden', { published: false, title: 'Evento oculto' },
    { ...options, sourceCollection: core.EVENTS }), null);
  assert.equal(core.buildEntry('past-event', { published: true, title: 'Evento passado',
    eventDate: '01/01/2020' }, { ...options, sourceCollection: core.EVENTS }).title, 'Evento passado');
  assert.equal(core.buildEntry('timestamp-event', { published: true, title: 'Evento com data',
    eventDate: new Stamp(Date.UTC(2026, 9, 25, 19)) }, { ...options, sourceCollection: core.EVENTS }).eventDate,
  '2026-10-25T19:00');
});
test('event search supports accents, events filter, Todos, pagination and source revalidation', async () => {
  const m = memory();
  await m.addFrom(core.EVENTS, 'same-id', { published: true, title: 'Feira de Ação Macacu',
    category: 'Cultura', description: 'Feira comunitária', location: 'Praça Central' });
  await m.addFrom(core.SOURCE, 'same-id', doc({ name: 'Feira de Ação Macacu' }));
  await m.addFrom(core.EVENTS, 'event-2', { published: true, title: 'Feira de Ação Macacu',
    category: 'Cultura', eventDate: '25/09/2026 às 19h', location: 'Centro' });
  const event = await m.backend.search(request({ query: 'acao', filter: 'events', limit: 1 }));
  assert.equal(event.results[0].sourceCollection, 'events');
  assert.equal(event.results[0].destination, 'eventDetail');
  assert.equal(event.results[0].eventDate, '25/09/2026 às 19h');
  assert.equal(event.results[0].location, 'Centro');
  const next = await m.backend.search(request({ query: 'ação', filter: 'events', limit: 1, cursor: event.nextCursor }));
  assert.equal(next.results[0].id, 'same-id');
  assert.equal(next.results[0].sourceCollection, 'events');
  const all = await m.backend.search(request({ query: 'acao macacu', filter: 'all', limit: 20 }));
  assert.equal(all.results.filter(row => row.sourceCollection === 'events').length, 2);
  assert.equal(all.results.filter(row => row.sourceCollection === 'establishments').length, 1);
  assert.notEqual(all.results.find(row => row.sourceCollection === 'events').id,
    all.results.find(row => row.sourceCollection === 'establishments').id);
  for (const [id, changes] of [['draft', { published: false }], ['inactive', { active: false }],
    ['expired', { expiresAt: new Stamp(now) }]]) {
    const sourceId = `event-${id}`;
    const source = { published: true, title: `Festival Revalidacao ${id}`, eventDate: '01/01/2000' };
    await m.addFrom(core.EVENTS, sourceId, source);
    m.store.sourcesMap.set(`events__${sourceId}`, { ...source, ...changes });
    const page = await m.backend.search(request({ query: 'festival revalidacao', filter: 'events' }));
    assert.ok(!page.results.some(row => row.id === sourceId), id);
    await m.backend.synchronize(core.EVENTS, sourceId);
    assert.equal(m.store.indexMap.has(`events__${sourceId}`), false);
  }
  m.store.sourcesMap.set('events__event-2', { published: true, title: 'Nome atualizado' });
  const staleEventSearch = await m.backend.search(request({ query: 'feira', filter: 'events' }));
  assert.deepEqual(staleEventSearch.results.map((row) => row.id), ['same-id']);
  m.store.sourcesMap.delete('events__same-id');
  const deletedEventSearch = await m.backend.search(request({ query: 'feira', filter: 'events' }));
  assert.equal(deletedEventSearch.results.length, 0);
});
test('event cursor accepts only event identities for the event filter', () => {
  assert.equal(core.parseIndexId('events__id').sourceCollection, core.EVENTS);
  assert.equal(core.parseRequest({ query: 'festival', filter: 'events',
    cursor: { queryKey: 'events:festival', lastIndexId: 'events__id' } }).filter, 'events');
  assert.throws(() => core.parseRequest({ query: 'festival', filter: 'events',
    cursor: { queryKey: 'events:festival', lastIndexId: 'news__id' } }), error => error.code === 'invalid-argument');
});
test('event detail requires Auth/App Check, revalidates and returns only public event fields', async () => {
  const m = memory();
  const source = { published: true, active: true, title: 'Evento Público',
    description: 'Descrição completa do evento', category: 'Cultura',
    eventDate: new Stamp(now + 86400000), location: 'Praça Central',
    imageUrl: 'https://images.example.invalid/event.jpg',
    galleryUrls: ['https://images.example.invalid/gallery.jpg'],
    expiresAt: new Stamp(now + 86400000 * 10), ownerEmail: 'private@example.invalid',
    phone: 'private', privateNotes: 'DO_NOT_RETURN', admin: true };
  await m.addFrom(core.EVENTS, 'event-id', source);
  const request = { auth: { uid: 'visitor' }, app: { appId: 'demo-app' }, data: { id: 'event-id' } };
  const resolved = await m.backend.resolveEvent(request);
  assert.equal(m.store.metrics.admissionScopes.at(-1), 'event-detail');
  assert.equal(resolved.status, 'available');
  assert.equal(resolved.id, 'event-id');
  assert.equal(resolved.data.title, source.title);
  assert.equal(resolved.data.description, source.description);
  assert.equal(resolved.data.category, 'Cultura');
  assert.equal(resolved.data.location, 'Praça Central');
  assert.deepEqual(resolved.data.eventDate, {
    _publicTimestamp: [Math.floor((now + 86400000) / 1000), ((now + 86400000) % 1000) * 1e6],
  });
  assert.equal(resolved.data.imageUrl, source.imageUrl);
  assert.equal(JSON.stringify(resolved).includes('private@example.invalid'), false);
  assert.equal(JSON.stringify(resolved).includes('DO_NOT_RETURN'), false);
  assert.equal(resolved.data.phone, undefined);
  assert.equal(resolved.data.expiresAt, undefined);
  assert.equal(resolved.data.admin, undefined);
  await assert.rejects(m.backend.resolveEvent({ ...request, auth: null }), error => error.code === 'unauthenticated');
  await assert.rejects(m.backend.resolveEvent({ ...request, app: null }), error => error.code === 'failed-precondition');
  await assert.rejects(m.backend.resolveEvent({ ...request, data: { id: '../private' } }), error => error.code === 'invalid-argument');
  await assert.rejects(m.backend.resolveEvent({ ...request, data: { id: 'event-id', collection: 'users' } }), error => error.code === 'invalid-argument');
  m.store.sourcesMap.set('events__event-id', { ...source, published: false });
  assert.deepEqual(await m.backend.resolveEvent(request), { status: 'unavailable' });
  m.store.sourcesMap.set('events__event-id', { ...source, active: false });
  assert.deepEqual(await m.backend.resolveEvent(request), { status: 'unavailable' });
  m.store.sourcesMap.set('events__event-id', { ...source, expiresAt: new Stamp(now) });
  assert.deepEqual(await m.backend.resolveEvent(request), { status: 'unavailable' });
  m.store.sourcesMap.delete('events__event-id');
  assert.deepEqual(await m.backend.resolveEvent(request), { status: 'unavailable' });
});
test('job detail requires Auth/App Check, revalidates and excludes contact and private fields', async () => {
  const m = memory();
  const source = { published: true, title: 'Vaga pública de exemplo',
    description: 'Descrição completa e pública.', category: 'Tecnologia',
    location: 'Centro', company: 'Empresa Exemplo', employmentType: 'CLT',
    contact: 'private@example.invalid', whatsapp: '5511999999999', phone: 'secret-phone',
    link: 'https://example.invalid/apply', privateNotes: 'DO_NOT_RETURN',
    applicationDeadline: new Stamp(now - 86400000), updatedAt: new Stamp(now),
    adminEmail: 'private@example.invalid' };
  await m.addFrom(core.JOBS, 'job-public', source);
  const req = { auth: { uid: 'visitor' }, app: { appId: 'demo-app' }, data: { id: 'job-public' } };
  const resolved = await m.backend.resolveJob(req);
  assert.equal(m.store.metrics.admissionScopes.at(-1), 'jobs-detail');
  assert.equal(resolved.status, 'available');
  assert.equal(resolved.id, 'job-public');
  assert.equal(resolved.data.title, source.title);
  assert.equal(resolved.data.description, source.description);
  assert.equal(resolved.data.category, 'Tecnologia');
  assert.equal(resolved.data.location, 'Centro');
  assert.equal(resolved.data.company, 'Empresa Exemplo');
  assert.equal(resolved.data.employmentType, 'CLT');
  assert.equal(JSON.stringify(resolved).includes('contact'), false);
  for (const secret of ['private@example.invalid', '5511999999999', 'secret-phone',
    'example.invalid/apply', 'DO_NOT_RETURN', 'applicationDeadline', 'adminEmail']) {
    assert.equal(JSON.stringify(resolved).includes(secret), false);
  }
  await assert.rejects(m.backend.resolveJob({ ...req, auth: null }), error => error.code === 'unauthenticated');
  await assert.rejects(m.backend.resolveJob({ ...req, app: null }), error => error.code === 'failed-precondition');
  await assert.rejects(m.backend.resolveJob({ ...req, data: { id: '../private' } }), error => error.code === 'invalid-argument');
  await assert.rejects(m.backend.resolveJob({ ...req, data: { id: 'job-public', collection: 'users' } }), error => error.code === 'invalid-argument');
  for (const change of [{ published: false }, { active: false }, { expiresAt: new Stamp(now) }]) {
    m.store.sourcesMap.set('jobs__job-public', { ...source, ...change });
    assert.deepEqual(await m.backend.resolveJob(req), { status: 'unavailable' });
  }
  m.store.sourcesMap.delete('jobs__job-public');
  assert.deepEqual(await m.backend.resolveJob(req), { status: 'unavailable' });
  const optional = { published: true, title: 'Vaga sem opcionais', description: 'Resumo.' };
  await m.addFrom(core.JOBS, 'job-optional', optional);
  assert.deepEqual((await m.backend.resolveJob({ ...req, data: { id: 'job-optional' } })).data,
    { title: 'Vaga sem opcionais', description: 'Resumo.' });
});
test('news search shares unified pagination and revalidates publication, activity and expiry', async () => {
  const m = memory();
  await m.add('same-id', doc({ name: 'Notícia Macacu' }));
  await m.addFrom(core.NEWS, 'same-id', { published: true, title: 'Notícia Macacu',
    category: 'Cidade', description: 'Atualização pública', location: 'Macacu' });
  await m.addFrom(core.NEWS, 'news-2', { published: true, title: 'Notícia Macacu',
    category: 'Cidade', description: 'Outra atualização' });
  const all = await m.backend.search(request({ query: 'noticia', limit: 2 }));
  assert.equal(all.results.length, 2);
  const news = await m.backend.search(request({ query: 'notícia', filter: 'news', limit: 1 }));
  assert.equal(news.results[0].sourceCollection, 'news');
  assert.equal(news.results[0].id, 'news-2');
  const next = await m.backend.search(request({ query: 'noticia', filter: 'news', limit: 1,
    cursor: news.nextCursor }));
  assert.deepEqual(next.results.map((row) => row.id), ['same-id']);
  const end = await m.backend.search(request({ query: 'noticia', filter: 'news', limit: 1,
    cursor: next.nextCursor }));
  assert.deepEqual(end.results, []); assert.equal(end.nextCursor, null);
  for (const [id, change] of [['draft', { published: false }], ['inactive', { active: false }],
    ['expired', { expiresAt: new Stamp(now) }]]) {
    const staleId = `stale-${id}`;
    const original = { published: true, title: `Notícia Revalidação ${staleId}` };
    await m.addFrom(core.NEWS, staleId, original);
    m.store.sourcesMap.set(`news__${staleId}`, { ...original, ...change });
    const page = await m.backend.search(request({ query: 'noticia revalidacao', filter: 'news' }));
    assert.ok(!page.results.some((row) => row.id === id));
    assert.ok(!page.results.some((row) => row.id === staleId));
    await m.backend.synchronize(core.NEWS, staleId);
    assert.equal(m.store.indexMap.has(`news__${staleId}`), false);
  }
  m.store.sourcesMap.set('news__news-2', { published: true, title: 'Título atualizado' });
  assert.ok(!(await m.backend.search(request({ query: 'noticia', filter: 'news' })))
    .results.some((row) => row.id === 'news-2'));
  m.store.sourcesMap.delete('news__same-id');
  await m.backend.synchronize(core.NEWS, 'same-id');
  assert.equal(m.store.indexMap.has('news__same-id'), false);
});

test('jobs index public fields, searches accents and prefixes, paginates in Todos and fails closed', async () => {
  const m = memory();
  const job = (title, extra = {}) => ({ published: true, title,
    description: 'Oportunidade fictícia para teste', company: 'Empresa Exemplo',
    location: 'Cachoeiras de Macacu', employmentType: 'CLT', category: 'Administrativo',
    contact: 'private@example.invalid', candidateEmail: 'private@example.invalid',
    applicationDeadline: new Stamp(now - 86400000), ...extra });
  await m.add('same-job-id', doc({ name: 'Trabalho Fictício' }));
  await m.addFrom(core.JOBS, 'same-job-id', job('Trabalho Fictício Auxiliar Administrativo'));
  await m.addFrom(core.JOBS, 'job-2', job('Trabalho Fictício Auxiliar Administrativo Noturno', { active: true }));
  assert.equal(m.store.indexMap.get('jobs__same-job-id').sourceCollection, 'jobs');
  assert.equal(m.store.indexMap.get('jobs__same-job-id').type, 'jobs');
  assert.equal(m.store.indexMap.get('jobs__same-job-id').destination, 'jobDetail');
  const indexed = JSON.stringify(m.store.indexMap.get('jobs__same-job-id'));
  assert.equal(indexed.includes('private@example.invalid'), false);
  assert.equal(indexed.includes('applicationDeadline'), false);

  const first = await m.backend.search(request({ query: 'auxi', filter: 'jobs', limit: 1 }));
  assert.equal(first.results.length, 1);
  assert.equal(first.results[0].sourceCollection, 'jobs');
  assert.equal(first.results[0].company, 'Empresa Exemplo');
  assert.equal(first.results[0].location, 'Cachoeiras de Macacu');
  assert.equal(first.results[0].employmentType, 'CLT');
  assert.equal(JSON.stringify(first.results[0]).includes('private@example.invalid'), false);
  assert.equal((await m.backend.search(request({ query: 'private', filter: 'jobs' }))).results.length, 0);
  const second = await m.backend.search(request({ query: 'auxi', filter: 'jobs', limit: 1,
    cursor: first.nextCursor }));
  assert.equal(second.results.length, 1);
  assert.notEqual(first.results[0].id, second.results[0].id);
  const all = await m.backend.search(request({ query: 'trabalho ficticio', filter: 'all' }));
  assert.equal(all.results.filter((row) => row.sourceCollection === 'establishments').length, 1);
  assert.equal(all.results.filter((row) => row.sourceCollection === 'jobs').length, 2);
  const allFirst = await m.backend.search(request({ query: 'trabalho ficticio', filter: 'all', limit: 1 }));
  assert.equal(allFirst.results[0].sourceCollection, 'establishments');
  const allSecond = await m.backend.search(request({ query: 'trabalho ficticio', filter: 'all', limit: 1,
    cursor: allFirst.nextCursor }));
  assert.equal(allSecond.results[0].sourceCollection, 'jobs');
  const allThird = await m.backend.search(request({ query: 'trabalho ficticio', filter: 'all', limit: 1,
    cursor: allSecond.nextCursor }));
  assert.equal(allThird.results[0].id, allFirst.results[0].id);
  assert.notEqual(allFirst.results[0].sourceCollection, allThird.results[0].sourceCollection);

  const accentJob = job('Técnico de Manutenção');
  await m.addFrom(core.JOBS, 'job-accent', accentJob);
  assert.equal((await m.backend.search(request({ query: 'tecnico', filter: 'jobs' }))).results[0].id,
    'job-accent');
  assert.equal((await m.backend.search(request({ query: 'técnico', filter: 'jobs' }))).results[0].id,
    'job-accent');
  assert.equal((await m.backend.search(request({ query: 'manu', filter: 'jobs' }))).results[0].id,
    'job-accent');

  for (const [id, change] of [['draft', { published: false }], ['inactive', { active: false }],
    ['expired', { expiresAt: new Stamp(now) }]]) {
    const sourceId = `job-${id}`;
    const original = job(`Vaga Revalidacao ${id}`);
    await m.addFrom(core.JOBS, sourceId, original);
    m.store.sourcesMap.set(`jobs__${sourceId}`, { ...original, ...change });
    assert.ok(!(await m.backend.search(request({ query: 'vaga revalidacao', filter: 'jobs' })))
      .results.some((row) => row.id === sourceId));
    await m.backend.synchronize(core.JOBS, sourceId);
    assert.equal(m.store.indexMap.has(`jobs__${sourceId}`), false);
  }
  m.store.sourcesMap.set('jobs__job-2', job('Coordenador Atualizado'));
  await m.backend.synchronize(core.JOBS, 'job-2');
  assert.equal(m.store.indexMap.get('jobs__job-2').title, 'Coordenador Atualizado');
  m.store.sourcesMap.delete('jobs__job-2');
  await m.backend.synchronize(core.JOBS, 'job-2');
  assert.equal(m.store.indexMap.has('jobs__job-2'), false);
});
test('news detail requires Auth/App Check and revalidates current public source fields', async () => {
  const m = memory();
  const source = { published: true, active: true, title: 'Notícia Pública',
    description: 'Conteúdo completo '.repeat(4000), category: 'Cidade',
    imageUrl: 'https://images.example.invalid/news.jpg', publishedAt: new Stamp(now),
    additionalInfo: 'Detalhes públicos', targetEmail: 'private@example.invalid',
    ownerEmail: 'private@example.invalid', privateNotes: 'DO_NOT_RETURN', admin: true };
  await m.addFrom('news', 'article-id', source);
  const request = { auth: { uid: 'visitor' }, app: { appId: 'demo-app' }, data: { id: 'article-id' } };
  const resolved = await m.backend.resolveNews(request);
  assert.equal(resolved.status, 'available'); assert.equal(resolved.id, 'article-id');
  assert.equal(resolved.data.description, source.description);
  assert.equal(resolved.data.category, 'Cidade'); assert.equal(resolved.data.imageUrl, source.imageUrl);
  assert.deepEqual(resolved.data.publishedAt, {
    _publicTimestamp: [Math.floor(now / 1000), (now % 1000) * 1e6],
  });
  assert.equal(JSON.stringify(resolved).includes('private@example.invalid'), false);
  assert.equal(JSON.stringify(resolved).includes('DO_NOT_RETURN'), false);
  assert.equal(resolved.data.admin, undefined);
  await assert.rejects(m.backend.resolveNews({ ...request, auth: null }), error => error.code === 'unauthenticated');
  await assert.rejects(m.backend.resolveNews({ ...request, app: null }), error => error.code === 'failed-precondition');
  await assert.rejects(m.backend.resolveNews({ ...request, data: { id: '../private' } }), error => error.code === 'invalid-argument');
  await assert.rejects(m.backend.resolveNews({ ...request, data: { id: 'article-id', collection: 'users' } }), error => error.code === 'invalid-argument');
  m.store.sourcesMap.set('news__article-id', { ...source, published: false });
  assert.deepEqual(await m.backend.resolveNews(request), { status: 'unavailable' });
  m.store.sourcesMap.set('news__article-id', { ...source, active: false });
  assert.deepEqual(await m.backend.resolveNews(request), { status: 'unavailable' });
  m.store.sourcesMap.set('news__article-id', { ...source, expiresAt: new Stamp(now) });
  assert.deepEqual(await m.backend.resolveNews(request), { status: 'unavailable' });
  m.store.sourcesMap.delete('news__article-id');
  assert.deepEqual(await m.backend.resolveNews(request), { status: 'unavailable' });
});
test('unified cursor paginates establishments and routes without skips or duplicates', async () => {
  const m = memory();
  await m.add('same-id', doc({ name: 'Caminho Macacu' }));
  await m.addFrom('routes', 'same-id', { published: true, title: 'Caminho Macacu',
    category: 'Trilhas', description: 'Rota local', location: 'Macacu' });
  await m.add('business-2', doc({ name: 'Caminho Macacu' }));
  await m.addFrom('routes', 'route-2', { published: true, title: 'Caminho Macacu',
    category: 'Trilhas', description: 'Outra rota', location: 'Macacu' });
  const seen = []; let cursor = null;
  do {
    const page = await m.backend.search(request({ query: 'caminho', limit: 2, cursor }));
    seen.push(...page.results.map((row) => row.identity ?? `${row.sourceCollection}:${row.id}`));
    cursor = page.nextCursor;
  } while (cursor);
  assert.deepEqual(seen, ['establishments:business-2', 'establishments:same-id', 'routes:route-2', 'routes:same-id']);
  assert.equal(new Set(seen).size, 4);
  assert.equal((await m.backend.search(request({ query: 'caminho', filter: 'tourism' }))).results.length, 2);
});
test('stale index cannot leak unpublished inactive expired deleted or changed record', async () => {
  const m = memory();
  for (const change of [{ published: false }, { active: false }, { expiresAt: new Stamp(now) },
    { name: 'Outro nome' }, { category: 'Tecnologia' }]) {
    await m.add('a'); m.store.sourcesMap.set('establishments__a', doc(change));
    assert.equal((await m.backend.search(request({ filter: 'services' }))).results.length, 0);
  }
  await m.add('a'); m.store.sourcesMap.delete('establishments__a');
  assert.equal((await m.backend.search(request())).results.length, 0);
});
test('stale tourism index revalidates removed, unpublished, inactive, expired, and changed source', async () => {
  const m = memory(); const source = { published: true, title: 'Cachoeira Macacu', category: 'Cachoeiras' };
  for (const [id, change] of [['draft', { published: false }], ['inactive', { active: false }],
    ['expired', { expiresAt: new Stamp(now) }], ['renamed', { title: 'Outro lugar', category: 'Praias' }]]) {
    await m.addFrom('routes', id, source); m.store.sourcesMap.set(`routes__${id}`, { ...source, ...change });
    const currentResults = await m.backend.search(request({ query: 'cachoeira', filter: 'tourism' }));
    assert.equal(currentResults.results.length, 0);
  }
  await m.addFrom('routes', 'removed', source); m.store.sourcesMap.delete('routes__removed');
  assert.equal((await m.backend.search(request({ query: 'cachoeira', filter: 'tourism' }))).results.length, 0);
});
test('tourism detail resolution requires Auth and App Check and projects current public fields only', async () => {
  const m = memory();
  await m.addFrom('routes', 'route', { published: true, title: 'Cachoeira Pública',
    description: 'Descrição', location: 'Macacu', maps: 'https://maps.example.invalid',
    additionalInfo: 'Informação', ownerEmail: 'private@example.invalid', privateNotes: 'secret' });
  const request = { auth: { uid: 'visitor' }, app: { appId: 'demo-app' }, data: { id: 'route' } };
  const resolved = await m.backend.resolveTourism(request);
  assert.equal(resolved.id, 'route'); assert.equal(resolved.data.additionalInfo, 'Informação');
  assert.equal(resolved.data.ownerEmail, undefined); assert.equal(resolved.data.privateNotes, undefined);
  await assert.rejects(m.backend.resolveTourism({ ...request, auth: null }), (error) => error.code === 'unauthenticated');
  await assert.rejects(m.backend.resolveTourism({ ...request, app: null }), (error) => error.code === 'failed-precondition');
  await assert.rejects(m.backend.resolveTourism({ ...request, data: { id: 'route', collection: 'users' } }),
    (error) => error.code === 'invalid-argument');
  m.store.sourcesMap.set('routes__route', { published: true, title: 'Cachoeira Pública', active: false });
  assert.equal(await m.backend.resolveTourism(request), null);
});
test('publication expiry is checked at request time even without a source write', async () => {
  const m = memory(); await m.add('a', doc({ expiresAt: new Stamp(now + 1000) }));
  const later = core.createSearchBackend({ store: m.store, isTimestamp: options.isTimestamp, now: () => now + 2000 });
  assert.equal((await later.search(request())).results.length, 0);
  await later.synchronize('a'); assert.equal(m.store.indexMap.size, 0);
});
test('pagination preserves IDs with bounded remaining-slot batches', async () => {
  const m = memory(); for (const id of ['a', 'b', 'c']) await m.add(id);
  const first = await m.backend.search(request({ limit: 2 }));
  const second = await m.backend.search(request({ limit: 2, cursor: first.nextCursor }));
  assert.deepEqual([...first.results, ...second.results].map((result) => result.id), ['a', 'b', 'c']);
  assert.equal(second.nextCursor, null);
  assert.equal(m.store.metrics.indexReads, 3); assert.equal(m.store.metrics.sourceReads, 3);
});
test('typical five-result query uses five origins, not forty', async () => {
  const m = memory(); for (let n = 0; n < 20; n++) await m.add(`id${n}`);
  await m.backend.search(request({ limit: 5 }));
  assert.equal(m.store.metrics.sourceReads, 5); assert.equal(m.store.metrics.indexReads, 5);
});
test('additional indexed words reject candidates before paid source revalidation', async () => {
  const m = memory(); for (let n = 0; n < 40; n++) await m.add(`id${n}`, doc({ name: 'Eletricista Alpha' }));
  await m.backend.search(request({ query: 'eletricista zzz' }));
  assert.equal(m.store.metrics.indexReads, 40); assert.equal(m.store.metrics.sourceReads, 0);
});
test('worst case capped at forty origins and empty page can continue', async () => {
  const m = memory(); for (let n = 0; n < 45; n++) { await m.add(`id${String(n).padStart(2, '0')}`); }
  for (const source of m.store.sourcesMap.values()) source.published = false;
  const result = await m.backend.search(request());
  assert.equal(m.store.metrics.indexReads, 40); assert.equal(m.store.metrics.sourceReads, 40);
  assert.equal(result.results.length, 0); assert.ok(result.nextCursor);
  const next = await m.backend.search(request({ cursor: result.nextCursor }));
  assert.equal(next.nextCursor, null); assert.equal(m.store.metrics.sourceReads, 45);
});
test('no auth and missing App Check rejected before storage', async () => {
  const m = memory();
  for (const rejected of [{ ...request(), auth: null }, { ...request(), app: null }]) {
    await assert.rejects(m.backend.search(rejected), core.SearchError);
  }
  assert.equal(m.store.metrics.admissions, 0); assert.equal(m.store.metrics.indexReads, 0);
});
test('anonymous Auth can search public records with App Check', async () => {
  const m = memory(); await m.add('visitor-business');
  const r = await m.backend.search({ ...request(), auth: {
    uid: 'visitor', token: { firebase: { sign_in_provider: 'anonymous' } },
  } });
  assert.equal(r.results[0].id, 'visitor-business');
});
test('query limits arbitrary collections and malformed cursors are rejected', async () => {
  const m = memory();
  for (const extra of [{ query: '' }, { query: 'a' }, { query: 'a'.repeat(81) }, { query: 'aa bb cc dd ee' },
    { limit: 21 }, { limit: 0 }, { limit: 1.5 }, { filter: 'users' }, { collection: 'users' },
    { cursor: { queryKey: 'all:eletrica', lastIndexId: 'establishments__../bad' } },
    { filter: 'tourism', cursor: { queryKey: 'tourism:eletrica', lastIndexId: 'establishments__valid' } },
    { filter: 'news', cursor: { queryKey: 'news:eletrica', lastIndexId: 'routes__valid' } },
    { filter: 'jobs', cursor: { queryKey: 'jobs:eletrica', lastIndexId: 'events__valid' } },
    { filter: 'commerce', cursor: { queryKey: 'commerce:eletrica', lastIndexId: 'routes__valid' } }]) {
    await assert.rejects(m.backend.search(request(extra)), (error) => error.code === 'invalid-argument');
  }
  assert.equal(m.store.metrics.admissions, 0);
});
test('real adapter rate transaction throttles duplicate queries before index reads', async () => {
  const state = new Map(); let reads = 0; let writes = 0;
  const db = { collection: (name) => ({ doc: (id) => ({ key: `${name}/${id}` }) }),
    runTransaction: (body) => body({ get: async (ref) => { reads++; return { data: () => state.get(ref.key) }; },
      set: (ref, data) => { writes++; state.set(ref.key, data); } }) };
  const store = createFirestoreStore(db, { Timestamp: { fromMillis: (ms) => new Stamp(ms) } });
  await store.admit('user', now);
  await assert.rejects(store.admit('user', now + 100), (error) => error.code === 'resource-exhausted');
  for (let n = 1; n < 30; n++) await store.admit('user', now + n * 400);
  await assert.rejects(store.admit('user', now + 20000), (error) => error.code === 'resource-exhausted');
  assert.equal(writes, 30); assert.equal(reads, 32);
  assert.ok(![...state.keys()][0].endsWith('/user'));

  await store.admit('user', now, 'event-detail');
  await assert.rejects(store.admit('user', now + 100, 'event-detail'),
    (error) => error.code === 'resource-exhausted');
  for (let n = 1; n < 60; n++) await store.admit('user', now + n * 250, 'event-detail');
  await assert.rejects(store.admit('user', now + 20000, 'event-detail'),
    (error) => error.code === 'resource-exhausted');
  assert.equal(state.size, 2, 'detail quota has its own UID hash scope.');
  await store.admit('user', now, 'jobs-detail');
  await assert.rejects(store.admit('user', now + 100, 'jobs-detail'),
    (error) => error.code === 'resource-exhausted');
  assert.equal(state.size, 3, 'job detail quota is isolated from other operations.');
});
test('production gate rejects real projects nonloopback host and absent emulator', () => {
  const demo = { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-search', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' };
  assert.equal(core.localOnly(demo), true);
  assert.equal(core.localOnly({ ...demo, GCLOUD_PROJECT: 'tudo-aqui-macacu' }), false);
  assert.equal(core.localOnly({ ...demo, FIRESTORE_EMULATOR_HOST: 'remote:8080' }), false);
  assert.equal(core.localOnly({}), false);
});

test('Firestore adapter uses array index paginated projection and batched point reads', async () => {
  const calls = [];
  const chain = {};
  for (const method of ['where', 'orderBy', 'startAfter', 'limit', 'select']) {
    chain[method] = (...args) => { calls.push([method, ...args]); return chain; };
  }
  chain.get = async () => ({ docs: [{ id: 'establishments__one', data: () => ({ id: 'one' }) }] });
  const db = { collection: (name) => {
    calls.push(['collection', name]); return name === core.INDEX ? chain : { doc: (id) => ({ id }) };
  }, getAll: async (...refs) => refs.map((ref) => ({ data: () => ({ name: ref.id }) })) };
  const store = createFirestoreStore(db, { FieldPath: { documentId: () => '__name__' } });
  await store.candidates({ anchor: 'ele', filter: 'services', after: 'establishments__a', count: 5 });
  assert.deepEqual(calls.slice(0, 6), [['collection', core.INDEX], ['where', 'prefixes', 'array-contains', 'ele'],
    ['where', 'group', '==', 'services'], ['orderBy', '__name__'], ['startAfter', 'establishments__a'], ['limit', 5]]);
  assert.equal(calls[6][0], 'select');
  calls.length = 0;
  await store.candidates({ anchor: 'ca', filter: 'tourism', after: 'establishments__z', count: 3 });
  assert.deepEqual(calls.slice(0, 6), [['collection', core.INDEX], ['where', 'prefixes', 'array-contains', 'ca'],
    ['where', 'type', '==', 'tourism'], ['orderBy', '__name__'], ['startAfter', 'establishments__z'], ['limit', 3]]);
  calls.length = 0;
  await store.candidates({ anchor: 'no', filter: 'news', after: 'news__z', count: 3 });
  assert.deepEqual(calls.slice(0, 6), [['collection', core.INDEX], ['where', 'prefixes', 'array-contains', 'no'],
    ['where', 'type', '==', 'news'], ['orderBy', '__name__'], ['startAfter', 'news__z'], ['limit', 3]]);
  calls.length = 0;
  await store.candidates({ anchor: 'ev', filter: 'events', after: 'events__z', count: 3 });
  assert.deepEqual(calls.slice(0, 6), [['collection', core.INDEX], ['where', 'prefixes', 'array-contains', 'ev'],
    ['where', 'type', '==', 'events'], ['orderBy', '__name__'], ['startAfter', 'events__z'], ['limit', 3]]);
  calls.length = 0;
  await store.candidates({ anchor: 'jo', filter: 'jobs', after: 'jobs__z', count: 3 });
  assert.deepEqual(calls.slice(0, 6), [['collection', core.INDEX], ['where', 'prefixes', 'array-contains', 'jo'],
    ['where', 'type', '==', 'jobs'], ['orderBy', '__name__'], ['startAfter', 'jobs__z'], ['limit', 3]]);
  assert.deepEqual(await store.sources([{ sourceCollection: 'establishments', id: 'one' },
    { sourceCollection: 'routes', id: 'two' }]), [{ name: 'one' }, { name: 'two' }]);
});

test('transaction retry rebuilds from latest source and replaces whole projection', async () => {
  let version = doc(); let writes = 0; let pending;
  const db = { collection: (name) => ({ doc: (id) => ({ name, id }) }),
    async runTransaction(body) {
      const tx = { get: async (ref) => ({ data: () => ref.name === core.SOURCE ? version : null }),
        set: (_ref, data) => { pending = data; }, delete: () => {} };
      await body(tx); // pretend SDK detects source conflict and discards first writes
      version = doc({ name: 'Estado atual' });
      await body(tx); writes++; return undefined;
    } };
  const backend = core.createSearchBackend({ store: createFirestoreStore(db, {
    FieldValue: { serverTimestamp: () => 'SERVER_TIME' } }), isTimestamp: options.isTimestamp, now: () => now });
  await backend.synchronize('one');
  assert.equal(pending.title, 'Estado atual'); assert.equal(writes, 1);
});

test('callable wrapper enforces App Check local gate and sanitized errors', async () => {
  const keys = ['FUNCTIONS_EMULATOR', 'GCLOUD_PROJECT', 'FIRESTORE_EMULATOR_HOST'];
  const saved = keys.map((key) => process.env[key]);
  try {
    process.env.FUNCTIONS_EMULATOR = 'true'; process.env.GCLOUD_PROJECT = 'demo-universal-search';
    process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
    const firestore = () => ({ collection: () => ({ doc: () => ({}) }),
      runTransaction: async () => { throw new Error('private SDK credential details'); } });
    firestore.Timestamp = Stamp;
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const capture = (settings, handler) => ({ settings, handler });
    const { registerLocalSearch } = require('../business_search_functions');
    const handlers = registerLocalSearch({ admin: { firestore }, onCall: capture, HttpsError, onDocumentWritten: capture });
    assert.equal(handlers.searchBusinesses.settings.enforceAppCheck, true);
    assert.equal(handlers.syncBusinessSearchIndex.settings.document, 'establishments/{id}');
    assert.equal(handlers.syncTourismSearchIndex.settings.document, 'routes/{id}');
    assert.equal(handlers.syncNewsSearchIndex.settings.document, 'news/{id}');
    assert.equal(handlers.syncEventsSearchIndex.settings.document, 'events/{id}');
    assert.equal(handlers.syncJobsSearchIndex.settings.document, 'jobs/{id}');
    assert.equal(handlers.getSearchNewsArticle.settings.enforceAppCheck, true);
    assert.equal(handlers.getSearchEvent.settings.enforceAppCheck, true);
    assert.equal(handlers.getSearchJob.settings.enforceAppCheck, true);
    assert.equal(handlers.getPublicJob.settings.enforceAppCheck, true);
    assert.equal(handlers.getPublicJob.settings.region, 'southamerica-east1');
    await assert.rejects(handlers.getPublicJob.handler({ ...request(), auth: null }),
      (error) => error.code === 'unauthenticated');
    await assert.rejects(handlers.getPublicJob.handler({ ...request(), app: null }),
      (error) => error.code === 'failed-precondition');
    await assert.rejects(handlers.getPublicJob.handler({ ...request(), data: { id: '../private' } }),
      (error) => error.code === 'invalid-argument');
    await assert.rejects(handlers.getPublicJob.handler({ ...request(), data: { id: 'job-1' } }),
      (error) => error.code === 'unavailable' && !error.message.includes('credential'));
    assert.equal(handlers.getSearchJob.settings.enforceAppCheck, true);
    await assert.rejects(handlers.searchBusinesses.handler({ ...request(), auth: null }), (error) => error.code === 'unauthenticated');
    await assert.rejects(handlers.searchBusinesses.handler(request()), (error) => error.code === 'unavailable' && !error.message.includes('credential'));
    process.env.GCLOUD_PROJECT = 'tudo-aqui-macacu';
    await assert.rejects(handlers.searchBusinesses.handler(request()), (error) => error.code === 'failed-precondition');
    await assert.rejects(handlers.getPublicJob.handler(request()), (error) => error.code === 'failed-precondition');
    assert.throws(() => registerLocalSearch({}), /demo local/);
  } finally {
    keys.forEach((key, n) => { if (saved[n] === undefined) delete process.env[key]; else process.env[key] = saved[n]; });
  }
});

test('getPublicJob is demo-only, always enforces App Check, and reuses the public job projection', async () => {
  const keys = ['FUNCTIONS_EMULATOR', 'GCLOUD_PROJECT', 'FIRESTORE_EMULATOR_HOST',
    'LOCAL_SEARCH_REQUIRE_APP_CHECK'];
  const saved = keys.map((key) => process.env[key]);
  try {
    process.env.FUNCTIONS_EMULATOR = 'true';
    process.env.GCLOUD_PROJECT = 'demo-universal-search';
    process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087';
    // The demo override must not weaken the dedicated public detail callable.
    process.env.LOCAL_SEARCH_REQUIRE_APP_CHECK = 'false';
    const reads = [];
    const writes = [];
    let source = { published: true, active: true, title: 'Vaga pública',
      description: 'Descrição pública', category: 'Serviços', location: 'Centro',
      company: 'Empresa Exemplo', employmentType: 'CLT',
      contact: 'private-contact', phone: 'private-phone', whatsapp: 'private-whatsapp',
      link: 'private-link', instagram: 'private-instagram', maps: 'private-maps',
      mapsUrl: 'private-maps-url', additionalInfo: 'private-extra', salary: 'private-salary',
      eventDate: 'private-event-date', date: 'private-date', internalNote: 'private-unknown' };
    const firestore = () => ({
      collection: (collection) => ({ doc: (id) => ({
        get: async () => {
          reads.push([collection, id]);
          const value = collection === 'jobs' && id === 'job-public' ? source : undefined;
          return { data: () => value };
        },
      }) }),
      runTransaction: async (body) => body({
        get: async () => ({ data: () => undefined }),
        set: (_ref, value) => writes.push(value),
      }),
    });
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const capture = (settings, handler) => ({ settings, handler });
    const { registerLocalSearch } = require('../business_search_functions');
    const handlers = registerLocalSearch({ admin: { firestore }, onCall: capture, HttpsError,
      onDocumentWritten: capture });
    const callable = handlers.getPublicJob;
    assert.equal(callable.settings.enforceAppCheck, true);
    await assert.rejects(callable.handler({ auth: { uid: 'user-1' }, data: { id: 'job-public' } }),
      (error) => error.code === 'failed-precondition');
    await assert.rejects(callable.handler({ app: { appId: 'demo-app' }, data: { id: 'job-public' } }),
      (error) => error.code === 'unauthenticated');
    await assert.rejects(callable.handler({ auth: { uid: 'user-1' }, app: { appId: 'demo-app' },
      data: { id: '../private' } }), (error) => error.code === 'invalid-argument');

    const response = await callable.handler({ auth: { uid: 'user-1' }, app: { appId: 'demo-app' },
      data: { id: 'job-public' } });
    assert.deepEqual(response, { status: 'available', id: 'job-public', data: {
      title: 'Vaga pública', description: 'Descrição pública', category: 'Serviços',
      location: 'Centro', company: 'Empresa Exemplo', employmentType: 'CLT',
    } });
    assert.deepEqual(reads, [['jobs', 'job-public']]);
    assert.equal(writes.length, 1, 'the per-user quota is recorded');
    for (const secret of ['private-contact', 'private-phone', 'private-whatsapp', 'private-link',
      'private-instagram', 'private-maps', 'private-maps-url', 'private-extra', 'private-salary',
      'private-event-date', 'private-date', 'private-unknown']) {
      assert.equal(JSON.stringify(response).includes(secret), false);
    }
    const { Timestamp } = require('firebase-admin/firestore');
    const publicSource = source;
    for (const change of [{ published: false }, { active: false },
      { expiresAt: Timestamp.fromMillis(Date.now() - 1000) }]) {
      source = { ...publicSource, ...change };
      assert.deepEqual(await callable.handler({ auth: { uid: 'user-1' }, app: { appId: 'demo-app' },
        data: { id: 'job-public' } }), { status: 'unavailable' });
    }
    const unavailable = await callable.handler({ auth: { uid: 'user-1' }, app: { appId: 'demo-app' },
      data: { id: 'missing-job' } });
    assert.deepEqual(unavailable, { status: 'unavailable' });
    assert.equal(reads.some(([collection]) => collection === 'job_private'), false);

    process.env.GCLOUD_PROJECT = 'demo-other-project';
    const otherDemoHandlers = registerLocalSearch({ admin: { firestore }, onCall: capture,
      HttpsError, onDocumentWritten: capture });
    assert.equal(otherDemoHandlers.getPublicJob, undefined,
      'the new endpoint is registered only for the explicitly authorized demo project');

    process.env.GCLOUD_PROJECT = 'tudo-aqui-macacu';
    await assert.rejects(callable.handler({ auth: { uid: 'user-1' }, app: { appId: 'demo-app' },
      data: { id: 'job-public' } }), (error) => error.code === 'failed-precondition');
  } finally {
    keys.forEach((key, n) => { if (saved[n] === undefined) delete process.env[key]; else process.env[key] = saved[n]; });
  }
});

test('normal entrypoint preserves normal exports and never exposes demo-only search callables', () => {
  const fs = require('node:fs'); const vm = require('node:vm'); const path = require('node:path');
  const exported = {};
  const fakeRequire = (name) => {
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (_options, handler) => handler };
    if (name === 'firebase-functions/logger') return {};
    if (name === 'firebase-admin') return { initializeApp() {} };
    if (name === 'firebase-admin/firestore') return require('firebase-admin/firestore');
    if (name === 'firebase-functions/v2/https') return { onCall: (_options, handler) => handler, HttpsError: Error };
    if (name === 'firebase-functions/params') return { defineSecret: () => ({}), defineString: () => ({}) };
    if (name === './business_search') return { localOnly: () => core.localOnly({}) };
    if (name === './secure_staging_environment') return { stagingBackendAllowed: () => false, stagingProjectContext: () => false };
    if (name === './secure_backend_environment') return { secureBackendAllowed: () => true };
    if (name === './public_content') return { registerPublicContent: () => ({ listPublicContent() {}, getPublicContentDetail() {} }) };
    if (name === './user_operations') return { registerUserOperations: () => ({ submitUserOperation() {} }) };
    if (name === './admin_job_management') return { registerAdminJobManagement: () => ({ manageAdminJob() {} }) };
    if (name === './home_image_upload') return require('../home_image_upload');
    if (name === './notification_delivery') return require('../notification_delivery');
    if (name === './admin_authorization') return require('../admin_authorization');
    throw new Error(`Unexpected production import: ${name}`);
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8'),
    { require: fakeRequire, exports: exported, process: { env: {} } });
  assert.deepEqual(Object.keys(exported).sort(), [
    'deliverPushNotification', 'getPublicContentDetail', 'listPublicContent', 'manageAdminJob', 'submitUserOperation', 'uploadHomeImage',
  ]);
  assert.equal(exported.getPublicJob, undefined);
  assert.equal(exported.getSearchJob, undefined);
});
