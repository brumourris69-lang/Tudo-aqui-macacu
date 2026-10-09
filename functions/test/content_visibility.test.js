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
    for (const change of [{ published: false }, { active: false }, { active: null },
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
  assert.equal(publiclyVisible('events', { published: true, startsAt: timestamp(999999) }, 0, isTimestamp), true);
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
