'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { localOnly } = require('../business_search');
const { changeAdminClaim } = require('../admin_claim_management');
assert.equal(localOnly(), true);
assert.equal(process.env.GCLOUD_PROJECT, 'demo-universal-search');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
const admin = require('firebase-admin');
const { Timestamp } = require('firebase-admin/firestore');
admin.initializeApp({ projectId: 'demo-universal-search' });
const db = admin.firestore(), auth = admin.auth(), created = [];
const tag = `writes-${Date.now()}`;
const root = 'http://127.0.0.1:8087/v1/projects/demo-universal-search/databases/(default)/documents';
const authRoot = 'http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1';
const headers = token => ({ 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) });
const enc = v => Buffer.from(JSON.stringify(v)).toString('base64url');
const app = `${enc({ alg: 'none' })}.${enc({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 3600 })}.`;
let passed = 0;
async function test(name, fn) { await fn(); passed++; console.log('PASS', name); }
async function account(name, anonymous = false) {
  const email = `${tag}-${name}@example.invalid`;
  const r = await fetch(`${authRoot}/accounts:signUp?key=demo-key`, { method: 'POST', headers: headers(),
    body: JSON.stringify(anonymous ? { returnSecureToken: true } : { email, password: 'LocalOnly123!', returnSecureToken: true }) });
  assert.equal(r.status, 200); const user = await r.json(); created.push(user.localId); return { ...user, email };
}
async function login(user) {
  const r = await fetch(`${authRoot}/accounts:signInWithPassword?key=demo-key`, { method: 'POST', headers: headers(),
    body: JSON.stringify({ email: user.email, password: 'LocalOnly123!', returnSecureToken: true }) });
  assert.equal(r.status, 200); return (await r.json()).idToken;
}
function field(v) {
  if (v instanceof Timestamp) return { timestampValue: v.toDate().toISOString() };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (v === null) return { nullValue: null };
  throw Error('Unsupported test field');
}
async function write(doc, data, token, timestamps = []) {
  const r = await fetch(`${root}:commit`, { method: 'POST', headers: headers(token), body: JSON.stringify({ writes: [{
    update: { name: `projects/demo-universal-search/databases/(default)/documents/${doc}`,
      fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, field(v)])) },
    ...(timestamps.length ? { updateTransforms: timestamps.map(fieldPath => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })) } : {}),
  }] }) });
  return r.status;
}
async function read(doc, token) { return (await fetch(`${root}/${doc}`, { headers: headers(token) })).status; }
async function call(operation, payload, token, appToken = app) {
  const r = await fetch('http://127.0.0.1:5007/demo-universal-search/southamerica-east1/submitUserOperation', {
    method: 'POST', headers: { ...headers(token), ...(appToken ? { 'X-Firebase-AppCheck': appToken } : {}) },
    body: JSON.stringify({ data: { operation, payload } }) });
  return { status: r.status, body: await r.json() };
}
const digest = v => crypto.createHash('sha256').update(v).digest('hex');
async function main() {
  const rules = await fetch('http://127.0.0.1:8087/emulator/v1/projects/demo-universal-search:securityRules', {
    method: 'PUT', headers: headers(), body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules',
      content: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') }] } }) });
  assert.equal(rules.status, 200);
  const user = await account('user'), other = await account('other'), visitor = await account('visitor', true), operator = await account('admin');
  const mutate = action => changeAdminClaim({ auth, db, uid: operator.localId, action, operator: 'user-security-test',
    reason: 'demo-only', apply: true, confirmation: `demo-universal-search:${operator.localId}:${action}` });
  await mutate('grant'); const adminToken = await login(operator);
  const profile = { displayName: 'Modelo', email: user.email, photoUrl: '', role: 'user' };
  await test('Profile create binds UID/email, exact fields and server timestamps; legitimate update allowed', async () => {
    assert.equal(await write(`users/${user.localId}`, profile, user.idToken, ['createdAt', 'updatedAt']), 200);
    const saved = (await db.doc(`users/${user.localId}`).get()).data();
    assert.equal(await write(`users/${user.localId}`, { ...saved, displayName: 'Nome atualizado' }, user.idToken, ['updatedAt']), 200);
    assert.equal(await write(`users/${user.localId}`, saved, other.idToken, ['updatedAt']), 403);
    assert.equal(await write(`users/${visitor.localId}`, { ...profile, email: '' }, visitor.idToken, ['createdAt', 'updatedAt']), 403);
  });
  await test('affectedKeys blocks additions, removals, role/createdAt changes, oversized and wrong types', async () => {
    const saved = (await db.doc(`users/${user.localId}`).get()).data();
    for (const data of [{ ...saved, admin: true }, { ...saved, privateExtra: 'forged' }, { ...saved, role: 'admin' },
      { ...saved, displayName: 'x'.repeat(121) }, { ...saved, photoUrl: 12 }, { ...saved, email: other.email },
      { ...saved, createdAt: Timestamp.fromMillis(0) }]) assert.equal(await write(`users/${user.localId}`, data, user.idToken, ['updatedAt']), 403);
    for (const key of ['role', 'createdAt', 'email', 'displayName', 'photoUrl']) {
      const removed = { ...saved }; delete removed[key];
      assert.equal(await write(`users/${user.localId}`, removed, user.idToken, ['updatedAt']), 403, key);
    }
    const noUpdatedAt = { ...saved }; delete noUpdatedAt.updatedAt;
    assert.equal(await write(`users/${user.localId}`, noUpdatedAt, user.idToken), 403);
  });
  await test('Legacy profile unknown fields are frozen, missing createdAt can be repaired explicitly', async () => {
    await db.doc(`users/${user.localId}`).set({ ...profile, legacyField: 'preserve' });
    assert.equal(await write(`users/${user.localId}`, { ...profile, legacyField: 'preserve' }, user.idToken, ['createdAt', 'updatedAt']), 200);
    const saved = (await db.doc(`users/${user.localId}`).get()).data();
    const removed = { ...saved }; delete removed.legacyField;
    assert.equal(await write(`users/${user.localId}`, removed, user.idToken, ['updatedAt']), 403);
  });
  const contact = { name: '', contact: '', message: `Contato ${tag}` };
  await test('Callable rejects unauthenticated, anonymous, invalid token, missing/invalid App Check', async () => {
    for (const token of [undefined, visitor.idToken, 'invalid-token']) assert.notEqual((await call('contact', contact, token)).status, 200);
    for (const token of [null, 'invalid-app']) assert.notEqual((await call('contact', contact, user.idToken, token)).status, 200);
  });
  await test('Direct writes cannot bypass validation, quotas or overwrite authors; private operational docs denied', async () => {
    for (const token of [user.idToken, other.idToken, visitor.idToken, adminToken, undefined]) {
      for (const doc of [`contact_messages/${tag}`, `business_proposals/${tag}`, `reviews/${tag}`, `metrics/${tag}`,
        `users/${user.localId}/favorites/${tag}`, `users/${user.localId}/devices/${tag}`, `polls/${tag}/votes/${user.localId}`]) {
        assert.equal(await write(doc, { arbitrary: 'forged' }, token), 403, doc);
      }
    }
    for (const collection of ['user_operation_limits', 'user_operation_dedup']) {
      assert.equal(await write(`${collection}/${tag}`, { arbitrary: true }, user.idToken), 403);
      assert.equal(await read(`${collection}/${tag}`, adminToken), 403);
    }
  });
  let contactId, proposalId, reviewId;
  await test('Contact derives author/email/read/date on server and duplicate request returns same ID', async () => {
    const first = await call('contact', contact, user.idToken); assert.equal(first.status, 200, JSON.stringify(first.body));
    contactId = first.body.result.id;
    const again = await call('contact', contact, user.idToken); assert.equal(again.body.result.id, contactId); assert.equal(again.body.result.duplicate, true);
    const data = (await db.doc(`contact_messages/${contactId}`).get()).data();
    assert.equal(data.userId, user.localId); assert.equal(data.email, user.email); assert.equal(data.read, false); assert.ok(data.createdAt instanceof Timestamp);
    assert.equal(await read(`contact_messages/${contactId}`, user.idToken), 403);
    assert.equal(await read(`contact_messages/${contactId}`, adminToken), 200);
  });
  await test('Proposal validates the actual details contract and pending status', async () => {
    const r = await call('proposal', { name: 'Modelo', contact: '', details: tag }, user.idToken); assert.equal(r.status, 200);
    proposalId = r.body.result.id;
    const data = (await db.doc(`business_proposals/${proposalId}`).get()).data(); assert.equal(data.details, tag); assert.equal(data.status, 'pending'); assert.equal(data.userId, user.localId);
  });
  await test('Malformed fields, forbidden author/status/date, missing fields and oversized text rejected', async () => {
    for (const payload of [{ ...contact, userId: other.localId }, { ...contact, status: 'approved' }, { ...contact, createdAt: 1 },
      { name: '', contact: '' }, { ...contact, message: 'x'.repeat(2001) }, { ...contact, message: null }]) {
      assert.equal((await call('contact', payload, user.idToken)).status, 400);
    }
  });
  await db.doc(`establishments/${tag}`).set({ name: 'Modelo fictício', published: true, open: false });
  await test('Review uses real business ID, 1..5 integer stars, pending and authenticated author', async () => {
    const payload = { businessId: tag, message: 'Avaliação fictícia', stars: 5 };
    const r = await call('review', payload, user.idToken); assert.equal(r.status, 200); reviewId = r.body.result.id;
    const data = (await db.doc(`reviews/${reviewId}`).get()).data();
    assert.equal(data.business, 'Modelo fictício'); assert.equal(data.businessId, tag); assert.equal(data.userId, user.localId); assert.equal(data.status, 'pending');
    for (const stars of [-1, 0, 6, 2.5, '5']) assert.equal((await call('review', { ...payload, stars }, user.idToken)).status, 400);
    assert.notEqual((await call('review', { ...payload, businessId: 'missing' }, user.idToken)).status, 200);
    for (const state of [{ published: false }, { active: false }, { expiresAt: Timestamp.fromMillis(0) }]) {
      await db.doc(`establishments/${tag}`).set({ name: 'Modelo', published: true, ...state });
      assert.notEqual((await call('review', payload, user.idToken)).status, 200);
    }
  });
  await db.doc(`polls/${tag}`).set({ published: true, options: ['Sim', 'Não'] });
  await test('Vote validates parent, option, period and UID; changing choice updates one document', async () => {
    assert.equal((await call('vote', { pollId: tag, option: 'Sim' }, user.idToken)).status, 200);
    assert.equal((await call('vote', { pollId: tag, option: 'Não' }, user.idToken)).status, 200);
    assert.equal((await call('vote', { pollId: tag, option: 'Não' }, user.idToken)).body.result.duplicate, true);
    const vote = (await db.doc(`polls/${tag}/votes/${user.localId}`).get()).data(); assert.equal(vote.option, 'Não'); assert.ok(vote.updatedAt instanceof Timestamp);
    assert.equal((await db.collection(`polls/${tag}/votes`).get()).size, 1);
    assert.equal((await call('vote', { pollId: tag, option: 'Unknown' }, user.idToken)).status, 400);
    assert.equal((await call('vote', { pollId: tag, option: 'Sim', userId: other.localId }, user.idToken)).status, 400);
    assert.notEqual((await call('vote', { pollId: 'missing', option: 'Sim' }, user.idToken)).status, 200);
    for (const state of [{ published: false }, { active: false }, { expiresAt: Timestamp.fromMillis(0) }, { options: 'invalid' }]) {
      await db.doc(`polls/${tag}`).set({ published: true, options: ['Sim', 'Não'], ...state });
      assert.notEqual((await call('vote', { pollId: tag, option: 'Sim' }, user.idToken)).status, 200);
    }
  });
  await test('Favorites keep legacy name IDs, owner read, idempotence and safe deletion', async () => {
    const payload = { id: `${tag} Legado`, name: 'Modelo' };
    assert.equal((await call('favorite', payload, user.idToken)).status, 200);
    assert.equal((await call('favorite', payload, user.idToken)).body.result.duplicate, true);
    assert.equal(await read(`users/${user.localId}/favorites/${payload.id}`, user.idToken), 200);
    assert.equal(await read(`users/${user.localId}/favorites/${payload.id}`, other.idToken), 403);
    await db.doc(`users/${user.localId}/favorites/${payload.id}`).set({ legacyPrivate: true }, { merge: true });
    assert.equal((await call('unfavorite', { id: payload.id }, user.idToken)).status, 200);
    assert.equal((await db.doc(`users/${user.localId}/favorites/${payload.id}`).get()).exists, false);
  });
  await test('Devices bind token path to caller; validate platform/size; preserve cleanup and privacy', async () => {
    const token = `${tag}-fake-device`;
    assert.equal((await call('device', { token, platform: 'android' }, user.idToken)).status, 200);
    const data = (await db.doc(`users/${user.localId}/devices/${token}`).get()).data(); assert.equal(data.token, token); assert.equal(data.active, true);
    assert.equal(await read(`users/${user.localId}/devices/${token}`, other.idToken), 403);
    assert.equal((await call('device', { token, platform: 'forged' }, user.idToken)).status, 400);
    assert.equal((await call('device', { token: 'x'.repeat(1501), platform: 'android' }, user.idToken)).status, 400);
    assert.equal((await call('removeDevice', { token }, user.idToken)).status, 200);
  });
  await test('Metrics are allowlisted telemetry, server authored and cannot modify aggregates directly', async () => {
    const p = { action: 'business_open', target: tag, targetType: 'business' };
    const r = await call('metric', p, user.idToken); assert.equal(r.status, 200);
    assert.equal((await call('metric', p, user.idToken)).body.result.duplicate, true);
    const data = (await db.doc(`metrics/${r.body.result.id}`).get()).data(); assert.equal(data.userId, user.localId);
    assert.equal((await call('metric', { ...p, count: 9999 }, user.idToken)).status, 400);
    assert.equal((await call('metric', { ...p, action: 'change_rating' }, user.idToken)).status, 400);
  });
  await test('Concurrent duplicates commit once; quota transaction prevents spam and daily overflow', async () => {
    const fresh = await account('quota');
    const responses = await Promise.all(Array.from({ length: 5 }, () => call('contact', { ...contact, message: 'Concurrent fixture' }, fresh.idToken)));
    assert.ok(responses.every(r => r.status === 200), JSON.stringify(responses));
    assert.equal(new Set(responses.map(r => r.body.result.id)).size, 1);
    assert.equal((await call('contact', { ...contact, message: 'Spam fixture' }, fresh.idToken)).status, 429);
    await db.doc(`user_operation_limits/${digest(`${fresh.localId}:proposal`)}`).set({ day: Math.floor(Date.now() / 86400000), days: 10, minute: 0, minutes: 0 });
    assert.equal((await call('proposal', { name: 'Modelo', contact: '', details: 'Daily limit' }, fresh.idToken)).status, 429);
  });
  await test('Admin moderates only supported fields without rewriting authors or scores; legacy reviews supported', async () => {
    const ref = db.doc(`reviews/${reviewId}`), saved = (await ref.get()).data();
    assert.equal(await write(ref.path, { ...saved, status: 'approved' }, adminToken), 200);
    assert.equal(await write(ref.path, { ...saved, userId: other.localId }, adminToken), 403);
    assert.equal(await write(ref.path, { ...saved, stars: 100 }, adminToken), 403);
    await db.doc(`reviews/${tag}-legacy`).set({ business: 'Legado', stars: 4, userId: user.localId, message: 'Histórico', status: 'pending' });
    assert.equal(await write(`reviews/${tag}-legacy`, { business: 'Legado', stars: 4, userId: user.localId, message: 'Histórico', status: 'approved' }, adminToken), 200);
    const proposal = (await db.doc(`business_proposals/${proposalId}`).get()).data();
    assert.equal(await write(`business_proposals/${proposalId}`, { ...proposal, status: 'approved' }, adminToken), 200);
  });
  await test('Every mutation family shares enforced quotas, including metrics/votes/favorites/devices', async () => {
    const payloads = { metric: { action: 'business_open', target: tag, targetType: 'business' },
      vote: { pollId: tag, option: 'Sim' }, favorite: { id: tag, name: 'Modelo' }, unfavorite: { id: tag },
      device: { token: tag, platform: 'android' }, removeDevice: { token: tag },
      review: { businessId: tag, message: 'Modelo', stars: 4 } };
    const { LIMITS } = require('../user_operations');
    for (const [operation, payload] of Object.entries(payloads)) {
      await db.doc(`user_operation_limits/${digest(`${other.localId}:${operation}`)}`).set({
        minute: Math.floor(Date.now() / 60000), minutes: LIMITS[operation][0], day: 0, days: 0,
      });
      assert.equal((await call(operation, payload, other.idToken)).status, 429, operation);
    }
  });
  await test('Revoked old Admin token cannot read inbox/moderate, but retains normal registered-user rights', async () => {
    await mutate('revoke');
    assert.equal(await read(`contact_messages/${contactId}`, adminToken), 403);
    const saved = (await db.doc(`reviews/${reviewId}`).get()).data();
    assert.equal(await write(`reviews/${reviewId}`, { ...saved, status: 'rejected' }, adminToken), 403);
    assert.equal((await call('proposal', { name: 'Conta comum', contact: '', details: 'No administrative privileges' }, adminToken)).status, 200);
  });
  console.log(`User operations emulator: ${passed} scenarios passed; demo only; no production or real push.`);
}
main().catch(e => { console.error(e); process.exitCode = 1; }).finally(async () => {
  for (const uid of created) await auth.deleteUser(uid).catch(() => {});
  await db.terminate(); await admin.app().delete();
});
