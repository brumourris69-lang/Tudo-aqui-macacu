'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { notificationTarget, loadTargetDevices, sendPushBatch } = require('../notification_delivery');

test('new UID recipient takes precedence; legacy email and public remain compatible', () => {
  assert.deepEqual(notificationTarget({ targetUid: 'recipient', targetEmail: 'old@example.invalid' }),
    { targetUid: 'recipient', targetEmail: '' });
  assert.deepEqual(notificationTarget({ targetEmail: ' TEST@example.invalid ' }),
    { targetUid: '', targetEmail: 'test@example.invalid' });
  assert.deepEqual(notificationTarget({ targetEmail: '' }), { targetUid: '', targetEmail: '' });
  assert.deepEqual(notificationTarget({}), { targetUid: '', targetEmail: '' });
});
test('invalid explicitly private targets cannot become broadcasts', () => {
  for (const targetUid of ['', null, {}, 'a/b', 'x'.repeat(129)]) {
    assert.throws(() => notificationTarget({ targetUid }));
  }
  assert.throws(() => notificationTarget({ targetEmail: {} }));
});
test('UID lookup reads only that user devices, never the broadcast collection', async () => {
  const calls = [];
  const query = { where: () => query, get: async () => ({ docs: ['device'] }) };
  const db = { collection: (name) => { calls.push(name); return {
    doc: uid => { calls.push(uid); return { collection: name => { calls.push(name); return query; } }; },
  }; }, collectionGroup: () => assert.fail('private target broadcast') };
  assert.deepEqual(await loadTargetDevices(db, notificationTarget({ targetUid: 'recipient' })), ['device']);
  assert.deepEqual(calls, ['users', 'recipient', 'devices']);
});
test('missing or ambiguous legacy account cannot become broadcast', async () => {
  for (const docs of [[], [{}, {}]]) {
    const q = { where: () => q, limit: () => q, get: async () => ({ docs }) };
    const db = { collection: () => q, collectionGroup: () => assert.fail('broadcast') };
    assert.deepEqual(await loadTargetDevices(db, notificationTarget({ targetEmail: 'old@example.invalid' })), []);
  }
});
test('production transport retains exact request; demo transport cannot call FCM', async () => {
  const keys = ['FUNCTIONS_EMULATOR', 'GCLOUD_PROJECT', 'FIRESTORE_EMULATOR_HOST'];
  const saved = keys.map(k => process.env[k]);
  try {
    delete process.env.FUNCTIONS_EMULATOR;
    const request = { tokens: ['local-token'], notification: { title: 'test', body: 'test' }, data: { link: 'https://example.invalid' } };
    const output = { successCount: 1 };
    assert.equal(await sendPushBatch({ sendEachForMulticast: async r => { assert.equal(r, request); return output; } }, request), output);
    process.env.FUNCTIONS_EMULATOR = 'true'; process.env.GCLOUD_PROJECT = 'demo-universal-search';
    process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087';
    assert.equal((await sendPushBatch({ sendEachForMulticast: () => assert.fail('external FCM') }, request)).successCount, 1);
    process.env.GCLOUD_PROJECT = 'real-project';
    await assert.rejects(sendPushBatch({}, request));
  } finally { keys.forEach((k, i) => { if (saved[i] === undefined) delete process.env[k]; else process.env[k] = saved[i]; }); }
});
