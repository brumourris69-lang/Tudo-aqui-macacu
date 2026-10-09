'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { prepareOperation, registerUserOperations } = require('../user_operations');
const samples = {
  contact: { name: '', contact: '', message: 'Contato fictício' },
  proposal: { name: 'Modelo', contact: '', details: 'Proposta' },
  review: { businessId: 'modelo', message: 'Avaliação', stars: 5 },
  metric: { action: 'business_open', target: 'modelo', targetType: 'business' },
  vote: { pollId: 'enquete', option: 'Sim' }, favorite: { id: 'modelo', name: 'Modelo' },
  unfavorite: { id: 'Modelo legado' }, device: { token: 'fake-local-token', platform: 'android' },
  removeDevice: { token: 'fake-local-token' },
};
test('user schemas require every field, reject additional fields and preserve real app contracts', () => {
  for (const [operation, payload] of Object.entries(samples)) {
    assert.deepEqual(prepareOperation({ operation, payload }), { operation, payload });
    for (const key of Object.keys(payload)) {
      const missing = { ...payload }; delete missing[key];
      assert.throws(() => prepareOperation({ operation, payload: missing }), { code: 'invalid-argument' });
    }
    for (const key of ['userId', 'role', 'createdAt', 'status', 'read', 'score', 'count']) {
      assert.throws(() => prepareOperation({ operation, payload: { ...payload, [key]: 'forged' } }), { code: 'invalid-argument' });
    }
  }
});
test('review score, identifiers, platform, actions, empty and oversized text fail closed', () => {
  for (const stars of [-1, 0, 6, 1.5, '5', null]) assert.throws(() => prepareOperation({ operation: 'review', payload: { ...samples.review, stars } }));
  for (const message of ['', '   ', 'x'.repeat(2001), 1]) assert.throws(() => prepareOperation({ operation: 'contact', payload: { ...samples.contact, message } }));
  for (const id of ['', 'a/b', '..', '.']) assert.throws(() => prepareOperation({ operation: 'favorite', payload: { id, name: 'Modelo' } }));
  assert.throws(() => prepareOperation({ operation: 'device', payload: { ...samples.device, platform: 'unknown' } }));
  assert.throws(() => prepareOperation({ operation: 'metric', payload: { ...samples.metric, action: 'set_admin' } }));
  for (const input of [null, [], { operation: '__proto__', payload: {} }, { operation: 'contact', payload: samples.contact, admin: true }]) assert.throws(() => prepareOperation(input));
});
test('local callable refuses unauthenticated/anonymous/App Check absent before storage and sanitizes outages', async () => {
  const saved = { ...process.env };
  Object.assign(process.env, { GCLOUD_PROJECT: 'demo-universal-search', FUNCTIONS_EMULATOR: 'true', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' });
  try {
    let calls = 0;
    const db = { collection: () => ({ doc: () => ({}) }), runTransaction: async () => { calls++; throw Error('private connection detail'); } };
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const { submitUserOperation } = registerUserOperations({ admin: { firestore: () => db }, onCall: (_, fn) => fn, HttpsError });
    const request = { auth: { uid: 'test', token: { firebase: { sign_in_provider: 'password' } } }, app: { appId: 'demo' }, data: { operation: 'contact', payload: samples.contact } };
    await assert.rejects(submitUserOperation({ ...request, auth: null }), { code: 'unauthenticated' });
    await assert.rejects(submitUserOperation({ ...request, auth: { uid: 'visitor', token: { firebase: { sign_in_provider: 'anonymous' } } } }), { code: 'unauthenticated' });
    await assert.rejects(submitUserOperation({ ...request, app: null }), { code: 'failed-precondition' });
    assert.equal(calls, 0);
    await assert.rejects(submitUserOperation(request), e => e.code === 'unavailable' && !e.message.includes('private'));
    assert.equal(calls, 1);
    process.env.GCLOUD_PROJECT = 'real-forbidden';
    await assert.rejects(submitUserOperation(request), { code: 'failed-precondition' });
    assert.throws(() => registerUserOperations({}), /demo emulator/);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  }
});
