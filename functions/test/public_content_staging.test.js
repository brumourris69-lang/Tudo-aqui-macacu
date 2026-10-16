'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { PUBLIC_COLLECTIONS } = require('../content_visibility');

class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
const { Timestamp } = require('firebase-admin/firestore');

function harness({ job, rateCount = 0 } = {}) {
  const reads = [];
  const collectionReads = [];
  const rateWrites = [];
  const env = { STAGING_BACKEND_ENABLED: 'true', STAGING_FIREBASE_PROJECT_ID: 'tudo-aqui-macacu-staging',
    GCLOUD_PROJECT: 'tudo-aqui-macacu-staging' };
  const admin = {
    app: () => ({ options: { projectId: 'tudo-aqui-macacu-staging' } }),
    firestore: () => ({
      collection(name) {
        if (name === 'job_private') throw new Error('private collection must never be read');
        if (name.endsWith('_rate_limits')) return { doc: key => ({ id: key }) };
        const query = {
          where() { return query; },
          orderBy() { return query; },
          startAfter() { return query; },
          limit() { return query; },
          async get() { collectionReads.push(name); return { size: 0, docs: [] }; },
        };
        if (name === 'jobs') return { ...query, doc: id => ({ async get() {
          reads.push([name, id]);
          return { exists: Boolean(job), data: () => job };
        } }) };
        return query;
      },
      async runTransaction(fn) {
        return fn({
          async get() { return { data: () => ({ minute: Math.floor(Date.now() / 60000), count: rateCount }) }; },
          set(ref, value) { rateWrites.push([ref, value]); },
        });
      },
    }),
  };
  const { registerStagingPublicContent } = require('../public_content');
  assert.equal(typeof registerStagingPublicContent, 'function', 'staging registrar should be exported');
  const handlers = registerStagingPublicContent({ admin, onCall: (options, handler) => ({ options, handler }),
    HttpsError, env });
  return { handlers, reads, collectionReads, rateWrites };
}

test('staging public registrar exposes only list, public content detail, and strict public job detail', () => {
  const { handlers } = harness();
  assert.deepEqual(Object.keys(handlers).sort(), ['getPublicContentDetail', 'getPublicJob', 'listPublicContent']);
  assert.equal(handlers.getPublicJob.options.enforceAppCheck, true);
  assert.equal(handlers.getPublicJob.options.region, 'southamerica-east1');
});

test('staging public list allows only establishments routes utilities and jobs', async () => {
  const { handlers, collectionReads } = harness();
  for (const collection of ['establishments', 'routes', 'utilities', 'jobs']) {
    const result = await handlers.listPublicContent.handler({ auth: { uid: 'user-1' }, app: { appId: 'staging' },
      data: { collection, limit: 1 } });
    assert.deepEqual(result, { items: [], nextCursor: null }, collection);
  }
  assert.deepEqual(collectionReads, ['establishments', 'routes', 'utilities', 'jobs']);
  for (const collection of ['events', 'news']) {
    await assert.rejects(handlers.listPublicContent.handler({ auth: { uid: 'user-1' }, app: { appId: 'staging' },
      data: { collection, limit: 1 } }), error => error.code === 'invalid-argument', collection);
  }
  assert.deepEqual(collectionReads, ['establishments', 'routes', 'utilities', 'jobs']);
  assert.ok(PUBLIC_COLLECTIONS.includes('events'));
  assert.ok(PUBLIC_COLLECTIONS.includes('news'));
});

test('staging getPublicJob requires Auth, App Check, and exactly one valid ID field', async () => {
  const { handlers } = harness({ job: { published: true, active: true, title: 'Vaga pública' } });
  const call = handlers.getPublicJob.handler;
  for (const request of [
    { auth: null, app: { appId: 'staging' }, data: { id: 'job-1' } },
    { auth: { uid: 'user-1' }, app: null, data: { id: 'job-1' } },
    { auth: { uid: 'user-1' }, app: { appId: 'staging' }, data: { id: '../private' } },
    { auth: { uid: 'user-1' }, app: { appId: 'staging' }, data: { id: 'job-1', extra: true } },
  ]) await assert.rejects(call(request));
});

test('staging getPublicJob projects only approved visible job fields and records per-user quota', async () => {
  const valid = { published: true, active: true, expiresAt: Timestamp.fromMillis(Date.now() + 60000),
    title: 'Vaga pública', description: 'Descrição', company: 'Empresa', location: 'Centro',
    contact: 'private-contact', phone: 'private-phone', whatsapp: 'private-wa', link: 'private-link',
    instagram: 'private-ig', maps: 'private-map', mapsUrl: 'private-map-url', additionalInfo: 'private-extra',
    salary: 'unapproved-salary', eventDate: 'unapproved-date', date: 'unapproved-date', unknownField: 'private-unknown' };
  const { handlers, reads, rateWrites } = harness({ job: valid });
  const result = await handlers.getPublicJob.handler({ auth: { uid: 'user-1' }, app: { appId: 'staging' }, data: { id: 'job-1' } });
  assert.equal(result.status, 'available');
  assert.equal(result.id, 'job-1');
  assert.deepEqual(result.data, { title: 'Vaga pública', description: 'Descrição', company: 'Empresa',
    location: 'Centro', published: true, active: true, expiresAt: { _publicTimestamp: [valid.expiresAt.seconds, valid.expiresAt.nanoseconds] } });
  assert.deepEqual(reads, [['jobs', 'job-1']]);
  assert.equal(rateWrites.length, 1);
});

test('staging getPublicJob hides missing, unpublished, inactive, and expired records', async () => {
  const base = { published: true, active: true };
  for (const job of [undefined, { ...base, published: false }, { ...base, active: false },
    { ...base, expiresAt: Timestamp.fromMillis(Date.now() - 1) }]) {
    const { handlers } = harness({ job });
    assert.deepEqual(await handlers.getPublicJob.handler({ auth: { uid: 'user-1' }, app: { appId: 'staging' },
      data: { id: 'job-1' } }), { status: 'unavailable' });
  }
});

test('staging getPublicJob enforces the per-user quota', async () => {
  const { handlers } = harness({ job: { published: true, active: true }, rateCount: 120 });
  await assert.rejects(handlers.getPublicJob.handler({ auth: { uid: 'user-1' }, app: { appId: 'staging' },
    data: { id: 'job-1' } }), error => error.code === 'resource-exhausted');
});

test('staging registrar fails closed for project mismatch and emulator environments', () => {
  const { registerStagingPublicContent } = require('../public_content');
  assert.equal(typeof registerStagingPublicContent, 'function');
  const admin = { app: () => ({ options: { projectId: 'tudo-aqui-macacu-staging' } }), firestore: () => ({}) };
  for (const env of [
    { STAGING_BACKEND_ENABLED: 'true', STAGING_FIREBASE_PROJECT_ID: 'other', GCLOUD_PROJECT: 'tudo-aqui-macacu-staging' },
    { STAGING_BACKEND_ENABLED: 'true', STAGING_FIREBASE_PROJECT_ID: 'tudo-aqui-macacu-staging',
      GCLOUD_PROJECT: 'tudo-aqui-macacu-staging', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' },
  ]) assert.throws(() => registerStagingPublicContent({ admin, onCall: (_, handler) => handler, HttpsError, env }));
});
