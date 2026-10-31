'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { PUBLIC_COLLECTIONS, publiclyVisible } = require('../content_visibility');
const { projectPublic } = require('../public_content');
const timestamp = ms => ({ seconds: Math.floor(ms / 1000), nanoseconds: 0, toMillis: () => ms });
const isTimestamp = value => !!value && typeof value.toMillis === 'function';
test('each public collection excludes unpublished inactive expired and malformed optional values', () => {
  for (const collection of PUBLIC_COLLECTIONS) {
    const base = { published: true, active: true, targetEmail: '' };
    assert.equal(publiclyVisible(collection, base, 1000, isTimestamp), true, collection);
    assert.equal(publiclyVisible(collection, { ...base, deleted: false }, 1000, isTimestamp), true, collection);
    for (const change of [{ published: false }, { active: false }, { active: null },
      { deleted: true }, { deleted: null }, { deleted: 'false' }, { deletedAt: timestamp(0) },
      { deletedAt: null }, { deleted: false, deletedAt: timestamp(0) },
      { expiresAt: timestamp(1000) }, { expiresAt: timestamp(999) }, { expiresAt: null }, { expiresAt: 'future' }]) {
      assert.equal(publiclyVisible(collection, { ...base, ...change }, 1000, isTimestamp), false, collection);
    }
    assert.equal(publiclyVisible(collection, { ...base, expiresAt: timestamp(1001) }, 1000, isTimestamp), true);
  }
});
test('legacy defaults are collection-specific, Business.open and future event date are not publication flags', () => {
  assert.equal(publiclyVisible('establishments', { published: true, open: false }, 0, isTimestamp), true);
  assert.equal(publiclyVisible('establishments', {}, 0, isTimestamp), false);
  assert.equal(publiclyVisible('utilities', { active: true }, 0, isTimestamp), true);
  assert.equal(publiclyVisible('utilities', { published: true }, 0, isTimestamp), false);
  assert.equal(publiclyVisible('utilities', { active: true, published: false }, 0, isTimestamp), false);
  assert.equal(publiclyVisible('events', { published: true, active: true,
    startsAt: timestamp(999999) }, 0, isTimestamp), true);
  assert.equal(publiclyVisible('events', { published: true, startsAt: timestamp(999999) }, 0, isTimestamp), false);
  assert.equal(publiclyVisible('notifications', { published: true, targetEmail: 'private@example.invalid' }, 0, isTimestamp), false);
  assert.equal(publiclyVisible('notifications', { published: true }, 0, isTimestamp), false);
  assert.equal(publiclyVisible('users', { published: true }, 0, isTimestamp), false);
});
test('backend projection excludes recipient/private/admin fields, serializes actual public timestamps', () => {
  const data = projectPublic({ title: 'Público', expiresAt: timestamp(5000),
    ownerEmail: 'private@example.invalid', privateNotes: 'private', targetEmail: 'private@example.invalid',
    role: 'admin', accessToken: 'fake-test', profile: { secret: 'fake' } }, isTimestamp);
  assert.deepEqual(data, { title: 'Público', expiresAt: { _publicTimestamp: [5, 0] } });
});
test('event public projection includes approved event details and excludes private fields', () => {
  const data = projectPublic({
    title: 'Evento fictício', category: 'Cultura', description: 'Descrição pública',
    eventDate: timestamp(1792954800000), endDate: timestamp(1793127600000), startTime: '19:30', endTime: '22:00',
    location: 'Praça Central', address: 'Rua de teste, 10',
    maps: 'https://maps.example.invalid/evento', organizer: 'Associação de teste',
    registrationUrl: 'https://events.example.invalid/inscricao',
    imageUrl: 'https://images.example.invalid/capa.jpg',
    galleryUrls: ['https://images.example.invalid/1.jpg', 'http://images.example.invalid/2.jpg'],
    published: true, active: true, ownerEmail: 'private@example.invalid', privateNotes: 'PRIVATE-SENTINEL',
  }, isTimestamp, 'events');

  assert.deepEqual(data, {
    title: 'Evento fictício', category: 'Cultura', description: 'Descrição pública',
    eventDate: { _publicTimestamp: [1792954800, 0] },
    endDate: { _publicTimestamp: [1793127600, 0] }, startTime: '19:30', endTime: '22:00',
    location: 'Praça Central', address: 'Rua de teste, 10',
    maps: 'https://maps.example.invalid/evento', organizer: 'Associação de teste',
    registrationUrl: 'https://events.example.invalid/inscricao',
    imageUrl: 'https://images.example.invalid/capa.jpg',
    galleryUrls: ['https://images.example.invalid/1.jpg'], published: true, active: true,
  });
  assert.equal(JSON.stringify(data).includes('PRIVATE-SENTINEL'), false);
  assert.equal(JSON.stringify(data).includes('private@example.invalid'), false);
});
test('jobs projection returns only approved listing fields and never aliases contact data', () => {
  const data = projectPublic({
    title: 'Vaga pública de exemplo', description: 'Descrição da vaga.',
    shortDescription: 'Resumo público.', category: 'Tecnologia', subcategory: 'Suporte',
    location: 'Centro', address: 'Centro de teste', company: 'Empresa Exemplo',
    salary: 'A combinar', eventDate: '2026-01-01', date: '2026-01-01',
    employmentType: 'CLT', type: 'CLT',
    imageUrl: 'https://example.invalid/vaga.png', published: true, active: true,
    expiresAt: timestamp(5000), contact: 'ADMIN-CONTACT', phone: 'ADMIN-PHONE',
    whatsapp: 'ADMIN-WHATSAPP', link: 'ADMIN-LINK', url: 'ADMIN-URL',
    maps: 'ADMIN-MAPS', mapsUrl: 'ADMIN-MAPS-URL', instagram: 'ADMIN-INSTAGRAM',
    additionalInfo: 'ADMIN-ADDITIONAL-INFO', destination: 'ADMIN-DESTINATION',
    email: 'ADMIN-EMAIL', privateNotes: 'ADMIN-NOTES', applicationContact: {
      value: 'UNAPPROVED-CANDIDATE-CONTACT', approved: false,
    },
  }, isTimestamp, 'jobs');

  assert.deepEqual(data, {
    title: 'Vaga pública de exemplo', description: 'Descrição da vaga.',
    shortDescription: 'Resumo público.', category: 'Tecnologia', subcategory: 'Suporte',
    location: 'Centro', address: 'Centro de teste', company: 'Empresa Exemplo',
    employmentType: 'CLT', type: 'CLT',
    imageUrl: 'https://example.invalid/vaga.png', published: true, active: true,
    expiresAt: { _publicTimestamp: [5, 0] },
  });
  for (const field of ['salary', 'eventDate', 'date', 'contact', 'phone', 'whatsapp', 'link',
    'instagram', 'maps', 'mapsUrl', 'additionalInfo']) {
    assert.equal(Object.hasOwn(data, field), false, `${field} must not be projected for jobs`);
  }
  for (const privateValue of ['ADMIN-CONTACT', 'ADMIN-PHONE', 'ADMIN-WHATSAPP', 'ADMIN-LINK',
    'ADMIN-URL', 'ADMIN-MAPS', 'ADMIN-MAPS-URL', 'ADMIN-INSTAGRAM', 'ADMIN-ADDITIONAL-INFO',
    'ADMIN-DESTINATION', 'ADMIN-EMAIL', 'ADMIN-NOTES', 'UNAPPROVED-CANDIDATE-CONTACT']) {
    assert.equal(JSON.stringify(data).includes(privateValue), false, privateValue);
  }
});
test('non-job public projection preserves approved contact and navigation fields', () => {
  const data = projectPublic({ title: 'Telefone útil', contact: '(22) 0000-0000',
    phone: '(22) 0000-0000', whatsapp: 'https://wa.me/552200000000',
    link: 'https://example.invalid/info' }, isTimestamp, 'useful_phones');
  assert.deepEqual(data, { title: 'Telefone útil', contact: '(22) 0000-0000',
    phone: '(22) 0000-0000', whatsapp: 'https://wa.me/552200000000',
    link: 'https://example.invalid/info' });
});
test('target collection projections use separate allowlists and omit unapproved business contacts', () => {
  const { projectPublic } = require('../public_content_projection');
  const business = projectPublic({
    name: 'Comércio fictício', category: 'Comércio', description: 'Descrição',
    maps: 'https://maps.example/route', phone: '+55 (22) 99999-0000',
    whatsapp: 'https://wa.me/5522999990000', instagram: '@loja.ficticia',
    publicContactApproved: false, ownerEmail: 'private@example.invalid',
  }, isTimestamp, 'establishments');
  assert.deepEqual(business, {
    name: 'Comércio fictício', category: 'Comércio', description: 'Descrição',
    maps: 'https://maps.example/route',
  });
  assert.equal(Object.hasOwn(business, 'publicContactApproved'), false);

  const approved = projectPublic({ name: 'Comércio fictício', publicContactApproved: true,
    phone: '+55 (22) 99999-0000', whatsapp: 'https://wa.me/5522999990000',
    instagram: '@loja.ficticia', contact: 'must-remain-private', internalNote: 'private' },
  isTimestamp, 'establishments');
  assert.deepEqual(approved, { name: 'Comércio fictício', phone: '+55 (22) 99999-0000',
    whatsapp: 'https://wa.me/5522999990000', instagram: '@loja.ficticia' });
});
test('business contact approval does not publish malformed contact channels', () => {
  const { projectPublic } = require('../public_content_projection');
  const data = projectPublic({ name: 'Comércio fictício', publicContactApproved: true,
    phone: 'javascript:alert(1)', whatsapp: 'https://wa.me/invalid',
    instagram: 'https://evil.example/profile' }, isTimestamp, 'establishments');
  assert.deepEqual(data, { name: 'Comércio fictício' });
});
test('routes projection bounds gallery and accepts only safe typed map and HTTPS destinations', () => {
  const { projectPublic } = require('../public_content_projection');
  const data = projectPublic({ title: 'Trilha fictícia', type: 'Trilhas',
    iconKey: 'turismo', order: 2,
    maps: 'geo:-22.4,-42.6?q=trilha', mapsUrl: 'https://maps.example/rota',
    link: 'https://turismo.example/rota',
    galleryUrls: ['https://images.example/1.jpg', 'http://images.example/2.jpg',
      'https://user:password@images.example/3.jpg', 'https://images.example/4.jpg'],
    additionalInfo: 'Informação aprovada', privateNote: 'private' }, isTimestamp, 'routes');
  assert.deepEqual(data, { title: 'Trilha fictícia', type: 'Trilhas',
    iconKey: 'turismo', order: 2,
    maps: 'geo:-22.4,-42.6?q=trilha', mapsUrl: 'https://maps.example/rota',
    link: 'https://turismo.example/rota', galleryUrls: ['https://images.example/1.jpg', 'https://images.example/4.jpg'],
    additionalInfo: 'Informação aprovada' });
});
test('utilities require an explicitly typed valid destination and never fall back to legacy link', () => {
  const { projectPublic } = require('../public_content_projection');
  assert.equal(projectPublic({ name: 'Telefone', link: 'https://legacy.example' },
    isTimestamp, 'utilities'), null);
  assert.equal(projectPublic({ name: 'Destino inválido', destinationType: 'phone',
    destination: 'https://evil.example' }, isTimestamp, 'utilities'), null);
  assert.deepEqual(projectPublic({ name: 'Transporte', iconKey: 'bus', description: 'Horários',
    category: 'Transporte', order: 1, destinationType: 'internal', destination: 'transport',
    active: true, published: true, link: 'https://ignored.example', privateNote: 'private' },
  isTimestamp, 'utilities'), { name: 'Transporte', iconKey: 'bus', description: 'Horários',
    category: 'Transporte', order: 1, destinationType: 'internal', destination: 'transport',
    active: true, published: true });
});
test('utilities accept only values matching their declared destination type', () => {
  const { projectPublic } = require('../public_content_projection');
  const valid = [
    ['url', 'https://service.example/info'],
    ['phone', '+55 (22) 99999-0000'],
    ['whatsapp', 'https://wa.me/5522999990000'],
    ['map', 'geo:-22.4,-42.6?q=local'],
    ['internal', 'water'],
    ['internal', 'energy'],
  ];
  for (const [destinationType, destination] of valid) {
    assert.equal(projectPublic({ name: 'Destino', destinationType, destination }, isTimestamp,
      'utilities').destination, destination);
  }
  const invalid = [
    ['url', 'http://service.example/info'], ['phone', '123'],
    ['whatsapp', 'https://evil.example/5522999990000'], ['map', 'javascript:alert(1)'],
    ['internal', 'adminPanel'], ['unknown', 'https://service.example'],
  ];
  for (const [destinationType, destination] of invalid) {
    assert.equal(projectPublic({ name: 'Destino', destinationType, destination }, isTimestamp,
      'utilities'), null, `${destinationType} must reject a mismatched or unsafe value`);
  }
});
test('getPublicContentDetail permits App Check visitors and validates ID visibility quota and projection', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    const reads = [];
    const rateWrites = [];
    let rateCount = 0;
    let source = { name: 'Comércio fictício', published: true, active: true,
      phone: '+55 (22) 99999-0000', publicContactApproved: false,
      privateNote: 'PRIVATE-SENTINEL' };
    let readFailure = false;
    const db = {
      collection(name) {
        return { doc: id => ({ id,
          async get() {
            reads.push([name, id]);
            if (readFailure) throw new Error('private Firestore diagnostic');
          return { exists: (['establishments', 'routes', 'utilities'].includes(name) && id === 'shop-1') ||
                (name === 'events' && id === 'event-1') ||
                (name === 'jobs' && id === 'job-1'),
              data: () => source };
          },
        }) };
      },
      async runTransaction(operation) {
        return operation({
          async get() { return { data: () => ({ minute: Math.floor(Date.now() / 60000), count: rateCount }) }; },
          set(ref, value) { rateWrites.push([ref, value]); },
        });
      },
    };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const onCall = (settings, handler) => ({ settings, handler });
    const { getPublicContentDetail } = require('../public_content').registerPublicContent({
      admin: { firestore: () => db }, onCall, HttpsError,
    });
    assert.equal(getPublicContentDetail.settings.enforceAppCheck, true);
    const valid = { auth: { uid: 'fictional-user' }, app: { appId: 'demo-app' },
      rawRequest: { ip: '192.0.2.10' },
      data: { collection: 'establishments', id: 'shop-1' } };
    await assert.rejects(getPublicContentDetail.handler({ ...valid, app: null }),
      error => error.code === 'failed-precondition');
    for (const data of [
      { collection: 'job_private', id: 'job-1' },
      { collection: 'users', id: 'user-1' }, { collection: 'routes', id: '../bad' },
      { collection: 'utilities', id: 'one', extra: true }, { collection: 'routes' },
    ]) {
      await assert.rejects(getPublicContentDetail.handler({ ...valid, data }),
        error => error.code === 'invalid-argument');
    }
    assert.deepEqual(reads, [], 'missing App Check and invalid calls must not read source documents');
    const response = await getPublicContentDetail.handler(valid);
    assert.deepEqual(response, { status: 'available', id: 'shop-1', data: {
      name: 'Comércio fictício', published: true, active: true,
    } });
    assert.deepEqual(reads, [['establishments', 'shop-1']]);
    assert.equal(rateWrites.length, 1);
    assert.equal(JSON.stringify(response).includes('PRIVATE-SENTINEL'), false);
    assert.equal(JSON.stringify(response).includes('+55'), false);

    const visitor = await getPublicContentDetail.handler({ ...valid, auth: null, rawRequest: {} });
    assert.deepEqual(visitor, response, 'a visitor with valid App Check receives the same safe public detail');
    assert.equal(rateWrites.at(-1)[0].id, require('node:crypto').createHash('sha256')
      .update('visitor:demo-app:shared').digest('hex'));

    source = { title: 'Vaga pública', description: 'Descrição pública', category: 'Serviços',
      company: 'Empresa Exemplo', published: true, active: true,
      contact: 'PRIVATE-CONTACT', phone: 'PRIVATE-PHONE', whatsapp: 'PRIVATE-WHATSAPP',
      link: 'PRIVATE-LINK', instagram: 'PRIVATE-INSTAGRAM', maps: 'PRIVATE-MAPS',
      mapsUrl: 'PRIVATE-MAPS-URL', additionalInfo: 'PRIVATE-ADDITIONAL-INFO',
      salary: 'PRIVATE-SALARY', eventDate: 'PRIVATE-EVENT-DATE', date: 'PRIVATE-DATE',
      unknown: 'PRIVATE-UNKNOWN' };
    const jobResponse = await getPublicContentDetail.handler({ ...valid,
      data: { collection: 'jobs', id: 'job-1' } });
    assert.deepEqual(jobResponse, { status: 'available', id: 'job-1', data: {
      title: 'Vaga pública', description: 'Descrição pública', category: 'Serviços',
      company: 'Empresa Exemplo', published: true, active: true,
    } });
    for (const secret of ['PRIVATE-CONTACT', 'PRIVATE-PHONE', 'PRIVATE-WHATSAPP',
      'PRIVATE-LINK', 'PRIVATE-INSTAGRAM', 'PRIVATE-MAPS', 'PRIVATE-MAPS-URL',
      'PRIVATE-ADDITIONAL-INFO', 'PRIVATE-SALARY', 'PRIVATE-EVENT-DATE',
      'PRIVATE-DATE', 'PRIVATE-UNKNOWN']) {
      assert.equal(JSON.stringify(jobResponse).includes(secret), false);
    }
    assert.deepEqual(reads.at(-1), ['jobs', 'job-1']);

    source = {
      title: 'Festival fictício', description: 'Evento público sintético',
      category: 'Cultura', eventDate: require('firebase-admin/firestore').Timestamp.fromMillis(2000000000000),
      startTime: '19:30', endTime: '22:00', organizer: 'Organização de teste',
      maps: 'https://maps.example.invalid/evento',
      registrationUrl: 'https://eventos.example.invalid/inscricao',
      contactUrl: 'https://eventos.example.invalid/contato',
      imageUrl: 'https://images.example.invalid/evento.jpg',
      galleryUrls: ['https://images.example.invalid/galeria.jpg'],
      published: true, active: true, privateNote: 'PRIVATE-EVENT-NOTE',
    };
    const eventResponse = await getPublicContentDetail.handler({ ...valid,
      data: { collection: 'events', id: 'event-1' } });
    assert.equal(eventResponse.status, 'available');
    assert.equal(eventResponse.data.title, 'Festival fictício');
    assert.equal(eventResponse.data.startTime, '19:30');
    assert.equal(eventResponse.data.endTime, '22:00');
    assert.equal(eventResponse.data.organizer, 'Organização de teste');
    assert.equal(eventResponse.data.registrationUrl, 'https://eventos.example.invalid/inscricao');
    assert.equal(eventResponse.data.contactUrl, 'https://eventos.example.invalid/contato');
    assert.equal(JSON.stringify(eventResponse).includes('PRIVATE-EVENT-NOTE'), false);
    for (const change of [{ published: false }, { active: false }, { active: undefined }, { deleted: true },
      { deleted: 'invalid' }, { deletedAt: new Date() }]) {
      source = { ...source, ...change };
      assert.deepEqual(await getPublicContentDetail.handler({ ...valid,
        data: { collection: 'events', id: 'event-1' } }), { status: 'unavailable' });
    }

    for (const change of [{ published: false }, { active: false },
      { expiresAt: require('firebase-admin/firestore').Timestamp.fromMillis(Date.now() - 1000) }]) {
      source = { name: 'Comércio fictício', published: true, active: true, ...change };
      assert.deepEqual(await getPublicContentDetail.handler(valid),
        { status: 'unavailable' });
    }
    source = undefined;
    assert.deepEqual(await getPublicContentDetail.handler(valid), { status: 'unavailable' });
    source = { name: 'Transporte', destinationType: 'internal', destination: 'transport',
      active: true, published: true };
    assert.deepEqual(await getPublicContentDetail.handler({ ...valid,
      data: { collection: 'utilities', id: 'shop-1' } }), {
      status: 'available', id: 'shop-1', data: { name: 'Transporte', destinationType: 'internal',
        destination: 'transport', active: true, published: true },
    });
    source = { name: 'Transporte', link: 'https://legacy.example', active: true, published: true };
    assert.deepEqual(await getPublicContentDetail.handler({ ...valid,
      data: { collection: 'utilities', id: 'shop-1' } }), { status: 'unavailable' });
    readFailure = true;
    await assert.rejects(getPublicContentDetail.handler(valid),
      error => error.code === 'unavailable' && !error.message.includes('private Firestore diagnostic'));
    rateCount = 120;
    await assert.rejects(getPublicContentDetail.handler(valid), error => error.code === 'resource-exhausted');
    await assert.rejects(getPublicContentDetail.handler({ ...valid, auth: null }),
      error => error.code === 'resource-exhausted');
    assert.equal(reads.some(([collection]) => collection === 'job_private'), false);

    delete process.env.FUNCTIONS_EMULATOR;
    delete process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
    delete process.env.SECURE_BACKEND_ENABLED;
    process.env.GCLOUD_PROJECT = 'tudo-aqui-macacu';
    assert.throws(() => require('../public_content').registerPublicContent({
      admin: { firestore: () => db }, onCall, HttpsError,
    }), /authorized backend configuration/);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});

test('public detail response remains under the shared UTF-8 size ceiling', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    const source = { title: 'T'.repeat(140), description: 'D'.repeat(3000), shortDescription: 'S'.repeat(1000),
      category: 'C'.repeat(120), location: 'L'.repeat(240), address: 'A'.repeat(240),
      eventDate: '2026-11-20T19:00:00Z', endDate: '2026-11-20T23:00:00Z',
      startTime: '19:00', endTime: '23:00', organizer: 'O'.repeat(160),
      registrationUrl: 'https://events.example/' + 'r'.repeat(1900),
      contactUrl: 'https://events.example/' + 'c'.repeat(1900),
      maps: 'https://maps.example/' + 'm'.repeat(1900),
      link: 'https://events.example/' + 'l'.repeat(1900),
      imageUrl: 'https://img.example/' + 'i'.repeat(1900),
      galleryUrls: Array(20).fill('https://img.example/' + 'g'.repeat(1900)),
      published: true, active: true };
    const db = {
      collection: name => name === 'public_content_detail_rate_limits'
        ? { doc: () => ({}) }
        : { doc: () => ({ async get() { return { exists: true, data: () => source }; } }) },
      runTransaction: operation => operation({ get: async () => ({ data: () => undefined }), set() {} }),
    };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const { registerPublicContent, PUBLIC_RESPONSE_MAX_BYTES } = require('../public_content');
    const { getPublicContentDetail } = registerPublicContent({
      admin: { firestore: () => db }, onCall: (_options, handler) => handler, HttpsError,
    });
    const result = await getPublicContentDetail({ auth: null, app: { appId: 'demo-app' },
      rawRequest: { ip: '192.0.2.11' }, data: { collection: 'events', id: 'event-1' } });
    assert.equal(result.status, 'available');
    assert.ok(Buffer.byteLength(JSON.stringify(result), 'utf8') <= PUBLIC_RESPONSE_MAX_BYTES);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});
test('listPublicContent applies the jobs projection while retaining vacancy listing fields', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    const source = { title: 'Vaga pública', description: 'Descrição pública.', company: 'Empresa Exemplo',
      location: 'Centro', employmentType: 'CLT', published: true, active: true,
      salary: 'Dado não aprovado', eventDate: '2026-01-01', date: '2026-01-01',
      contact: 'ADMIN-CONTACT', phone: 'ADMIN-PHONE', whatsapp: 'ADMIN-WHATSAPP', link: 'ADMIN-LINK',
      instagram: 'ADMIN-INSTAGRAM', maps: 'ADMIN-MAPS', mapsUrl: 'ADMIN-MAPS-URL',
      additionalInfo: 'ADMIN-ADDITIONAL-INFO' };
    const query = { where() { return this; }, orderBy() { return this; }, startAfter() { return this; },
      limit() { return this; }, async get() { return { docs: [{ id: 'job-public', data: () => source }], size: 1 }; } };
    const db = { collection(name) {
      if (name === 'public_content_rate_limits') return { doc: () => ({}) };
      assert.equal(name, 'jobs'); return query;
    }, runTransaction: async operation => operation({
      get: async () => ({ data: () => undefined }), set: () => {},
    }) };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const { listPublicContent } = require('../public_content').registerPublicContent({
      admin: { firestore: () => db }, onCall: (_options, handler) => handler, HttpsError,
    });
    const result = await listPublicContent({ auth: { uid: 'fictional-visitor' }, app: { appId: 'demo-app' },
      data: { collection: 'jobs', limit: 1 } });
    assert.deepEqual(result.items[0].data, { title: 'Vaga pública', description: 'Descrição pública.',
      company: 'Empresa Exemplo', location: 'Centro', employmentType: 'CLT', published: true, active: true });
    assert.equal(JSON.stringify(result.items[0].data).includes('ADMIN-'), false);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});
test('public utility listing omits legacy documents without a valid typed destination', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    const docs = [
      { id: 'legacy-utility', data: () => ({ name: 'Legado', active: true,
        published: true, link: 'https://legacy.example' }) },
      { id: 'safe-utility', data: () => ({ name: 'Transporte', active: true,
        published: true, destinationType: 'internal', destination: 'transport' }) },
    ];
    const query = { where() { return this; }, orderBy() { return this; }, startAfter() { return this; },
      limit() { return this; }, async get() { return { docs, size: docs.length }; } };
    const db = { collection(name) {
      if (name === 'public_content_rate_limits') return { doc: () => ({}) };
      assert.equal(name, 'utilities'); return query;
    }, runTransaction: async operation => operation({
      get: async () => ({ data: () => undefined }), set: () => {},
    }) };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const { listPublicContent } = require('../public_content').registerPublicContent({
      admin: { firestore: () => db }, onCall: (_options, handler) => handler, HttpsError,
    });
    const result = await listPublicContent({ auth: { uid: 'fictional-user' }, app: { appId: 'demo-app' },
      data: { collection: 'utilities', limit: 10 } });
    assert.deepEqual(result.items, [{ id: 'safe-utility', data: { name: 'Transporte',
      active: true, published: true, destinationType: 'internal', destination: 'transport' } }]);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});
test('local backend bounds source scans, throttles and sanitizes failures without falling back', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    let reads = 0, count = 0, failed = false, rateCount = 0;
    const query = {
      where() { return this; }, orderBy() { return this; }, startAfter() { return this; },
      limit(n) { assert.ok(n <= 40); count = n; return this; },
      async get() {
        if (failed) throw Error('private SDK diagnostic');
        const docs = Array.from({ length: count }, (_, i) => ({ id: `id-${String(reads + i).padStart(3, '0')}`, data: () => ({ published: true, active: false }) }));
        reads += count; return { docs, size: docs.length };
      },
    };
    const db = { collection: name => name === 'public_content_rate_limits' ? { doc: () => ({}) } : query,
      runTransaction: async fn => fn({ get: async () => ({ data: () => ({ minute: Math.floor(Date.now() / 60000), count: rateCount }) }), set: () => {} }) };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const { listPublicContent } = require('../public_content').registerPublicContent({
      admin: { firestore: () => db }, onCall: (_options, handler) => handler, HttpsError,
    });
    const request = { auth: { uid: 'fictional-visitor', token: { firebase: { sign_in_provider: 'anonymous' } } },
      app: { appId: 'demo-app' }, data: { collection: 'news', limit: 40 } };
    const result = await listPublicContent(request);
    assert.equal(reads, 80); assert.deepEqual(result.items, []); assert.equal(typeof result.nextCursor, 'string');
    rateCount = 120;
    await assert.rejects(listPublicContent(request), { code: 'resource-exhausted' }); assert.equal(reads, 80);
    rateCount = 0; failed = true;
    await assert.rejects(listPublicContent(request), error => error.code === 'unavailable' && !error.message.includes('private SDK'));
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});

test('public listing accepts App Check visitors and enforces network or shared-app quotas', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    let reads = 0;
    let rateCount = 0;
    const query = { where() { return this; }, orderBy() { return this; }, startAfter() { return this; },
      limit() { return this; }, async get() {
        reads++;
        return { size: 1, docs: [{ id: 'public-1', data: () => ({ title: 'Público', published: true,
          privateNote: 'PRIVATE-SENTINEL' }) }] };
      } };
    const rateIds = [];
    const db = { collection: name => name === 'public_content_rate_limits'
      ? { doc: id => { rateIds.push(id); return { id }; } } : query,
    runTransaction: operation => operation({ get: async () => ({ data: () => ({
      minute: Math.floor(Date.now() / 60000), count: rateCount,
    }) }), set() {} }) };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const { listPublicContent } = require('../public_content').registerPublicContent({
      admin: { firestore: () => db }, onCall: (_options, handler) => handler, HttpsError,
    });
    const request = { auth: null, app: { appId: 'demo-app' }, rawRequest: { ip: '198.51.100.8' },
      data: { collection: 'news', limit: 1 } };
    const result = await listPublicContent(request);
    assert.equal(reads, 1);
    assert.equal(result.items[0].id, 'public-1');
    assert.equal(JSON.stringify(result).includes('PRIVATE-SENTINEL'), false);
    assert.equal(rateIds[0], require('node:crypto').createHash('sha256')
      .update('visitor:demo-app:198.51.100.8').digest('hex'));
    await assert.rejects(listPublicContent({ ...request, app: null }), { code: 'failed-precondition' });
    const sharedBucketResponse = await listPublicContent({ ...request, rawRequest: {} });
    assert.equal(sharedBucketResponse.items[0].id, 'public-1');
    assert.equal(rateIds[1], require('node:crypto').createHash('sha256')
      .update('visitor:demo-app:shared').digest('hex'));
    await assert.rejects(listPublicContent({ ...request, data: { collection: 'users', limit: 1 } }),
      { code: 'invalid-argument' });
    rateCount = 120;
    await assert.rejects(listPublicContent(request), { code: 'resource-exhausted' });
    assert.equal(reads, 2, 'quota and invalid calls are rejected before source collection reads');
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});

test('public listing paginates before exceeding its UTF-8 response size ceiling', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    const fields = ['title', 'name', 'description', 'shortDescription', 'category', 'subcategory',
      'location', 'address', 'link', 'url', 'maps', 'mapsUrl', 'whatsapp', 'phone', 'instagram'];
    const docs = Array.from({ length: 8 }, (_, index) => ({ id: `large-${index}`,
      data: () => Object.fromEntries([...fields.map(field => [field, `${index}-${field}-`.padEnd(4096, 'x')]),
        ['published', true]]) }));
    let cursor = null;
    let requestedLimit = 0;
    const query = { where() { return this; }, orderBy() { return this; }, startAfter(value) { cursor = value; return this; },
      limit(value) { requestedLimit = value; return this; }, async get() {
        const remaining = docs.filter(doc => !cursor || doc.id > cursor).slice(0, requestedLimit);
        return { size: remaining.length, docs: remaining };
      } };
    const db = { collection: name => name === 'public_content_rate_limits' ? { doc: () => ({}) } : query,
      runTransaction: operation => operation({
      get: async () => ({ data: () => undefined }), set() {},
    }) };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const { registerPublicContent, PUBLIC_RESPONSE_MAX_BYTES } = require('../public_content');
    const list = registerPublicContent({ admin: { firestore: () => db },
      onCall: (_options, handler) => handler, HttpsError }).listPublicContent;
    const invoke = cursorValue => list({ auth: null, app: { appId: 'demo-app' },
      rawRequest: { ip: '203.0.113.7' }, data: { collection: 'news', limit: 8,
        ...(cursorValue ? { cursor: cursorValue } : {}) } });
    const first = await invoke(null);
    assert.ok(Buffer.byteLength(JSON.stringify(first)) <= PUBLIC_RESPONSE_MAX_BYTES);
    assert.ok(first.items.length > 0 && first.items.length < docs.length);
    assert.equal(first.nextCursor, first.items.at(-1).id);
    const second = await invoke(first.nextCursor);
    assert.ok(Buffer.byteLength(JSON.stringify(second)) <= PUBLIC_RESPONSE_MAX_BYTES);
    const ids = [...first.items, ...second.items].map(item => item.id);
    assert.deepEqual(ids, docs.map(doc => doc.id), 'size pagination must not skip or duplicate a public item');
    assert.equal(second.nextCursor, null);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});
