'use strict';
// Never run against production; all HTTP destinations and SDKs are loopback.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { localOnly } = require('../business_search');
assert.equal(localOnly(), true);
assert.equal(process.env.GCLOUD_PROJECT, 'demo-universal-search');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { notificationTarget, loadTargetDevices } = require('../notification_delivery');
const project = process.env.GCLOUD_PROJECT;
const root = `http://127.0.0.1:8087/v1/projects/${project}/databases/(default)/documents`;
const run = `notification-${Date.now()}`;
let passed = 0;
async function test(name, body) { await body(); console.log('PASS', name); passed++; }
async function account(name, anonymous = false) {
  const email = `${run}-${name}@example.invalid`, password = 'LocalOnly123!';
  const response = await fetch('http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify(anonymous ? { returnSecureToken: true } : { email, password, returnSecureToken: true }),
  });
  assert.equal(response.status, 200);
  const user = await response.json();
  if (name === 'admin') {
    await require('../admin_claim_management').changeAdminClaim({ auth: admin.auth(), db, uid: user.localId, action: 'grant', operator: 'notification-test', reason: 'demo-only', apply: true, confirmation: `${project}:${user.localId}:grant` });
    const r = await fetch('http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-key', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
    assert.equal(r.status, 200); user.idToken = (await r.json()).idToken;
  }
  return { uid: user.localId, token: user.idToken, email };
}
function headers(user) { return { 'content-type': 'application/json', ...(user ? { authorization: `Bearer ${user.token}` } : {}) }; }
function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([k, v]) => [k, typeof v === 'boolean' ? { booleanValue: v } : { stringValue: v }]));
}
async function read(collection, id, user) { return (await fetch(`${root}/${collection}/${id}`, { headers: headers(user) })).status; }
async function write(collection, id, data, user) {
  return (await fetch(`${root}/${collection}/${id}`, { method: 'PATCH', headers: headers(user), body: JSON.stringify({ fields: fields(data) }) })).status;
}
async function query(collection, conditions, user) {
  const r = await fetch(`${root}:runQuery`, { method: 'POST', headers: headers(user), body: JSON.stringify({ structuredQuery: {
    from: [{ collectionId: collection }], where: { compositeFilter: { op: 'AND', filters: conditions.map(([field, value]) => ({
      fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: typeof value === 'boolean' ? { booleanValue: value } : { stringValue: value },
    } })) } }, limit: 100,
  } }) });
  return { status: r.status, data: await r.json() };
}
async function main() {
  // Load only this demo project's rules, leaving all emulator documents intact.
  const rules = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');
  const loaded = await fetch(`http://127.0.0.1:8087/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules', content: rules }] } }),
  });
  assert.equal(loaded.status, 200, 'local rules compile/load');
  const owner = await account('owner'), other = await account('other'), anonymous = await account('visitor', true), administrator = await account('admin');
  const publicData = { title: 'Aviso fictício', description: 'Comunicado local', published: true, targetEmail: '', link: 'https://example.invalid' };
  const privateData = { title: 'Privada fictícia', description: 'Somente destinatário', published: true, targetUid: owner.uid, link: 'https://example.invalid' };
  const ids = { public: `${run}-public`, private: `${run}-private`, legacy: `${run}-legacy`, missing: `${run}-missing`, draft: `${run}-draft` };
  await db.collection('notifications').doc(ids.legacy).set({ ...publicData, targetEmail: owner.email });
  const missing = { ...publicData }; delete missing.targetEmail;
  await db.collection('notifications').doc(ids.missing).set(missing);
  await test('Admin creates public and UID-private notifications; no recipient email in private record', async () => {
    assert.equal(await write('notifications', ids.public, publicData, administrator), 200);
    assert.equal(await write('private_notifications', ids.private, privateData, administrator), 200);
    assert.equal(Object.hasOwn((await db.collection('private_notifications').doc(ids.private).get()).data(), 'targetEmail'), false);
  });
  await test('Public reads allowed to recipient, other, anonymous, unauthenticated and Admin', async () => {
    for (const user of [owner, other, anonymous, undefined, administrator]) assert.equal(await read('notifications', ids.public, user), 200);
  });
  await test('Private reads allowed only to recipient and Admin; third party and both visitor modes denied', async () => {
    for (const [user, status] of [[owner, 200], [administrator, 200], [other, 403], [anonymous, 403], [undefined, 403]]) {
      assert.equal(await read('private_notifications', ids.private, user), status);
    }
  });
  await test('Legacy targeted record is Admin-only even when published; missing classification fails closed', async () => {
    for (const id of [ids.legacy, ids.missing]) {
      for (const user of [owner, other, anonymous, undefined]) assert.equal(await read('notifications', id, user), 403);
      assert.equal(await read('notifications', id, administrator), 200);
    }
  });
  await test('Recipient cannot read unpublished private notification', async () => {
    await db.collection('private_notifications').doc(ids.draft).set({ ...privateData, published: false });
    assert.equal(await read('private_notifications', ids.draft, owner), 403);
    assert.equal(await read('private_notifications', ids.draft, administrator), 200);
  });
  await test('New public recipient-email/UID writes denied even to Admin; private email field forbidden', async () => {
    assert.equal(await write('notifications', `${run}-bad`, { ...publicData, targetEmail: owner.email }, administrator), 403);
    assert.equal(await write('notifications', `${run}-bad`, { ...publicData, targetUid: owner.uid }, administrator), 403);
    assert.equal(await write('private_notifications', `${run}-bad`, { ...privateData, targetEmail: owner.email }, administrator), 403);
    assert.equal(await write('notifications', `${run}-bad`, { ...publicData, recipientEmail: owner.email }, administrator), 403);
    assert.equal(await write('push_queue', `${run}-bad`, { ...publicData, targetEmail: owner.email, status: 'queued' }, administrator), 403);
  });
  await test('Non-admin cannot create, alter recipient, update or delete notifications', async () => {
    for (const user of [owner, other, anonymous, undefined]) {
      assert.equal(await write('notifications', `${run}-forbidden`, publicData, user), 403);
      assert.equal(await write('private_notifications', ids.private, { ...privateData, targetUid: other.uid }, user), 403);
      assert.equal((await fetch(`${root}/private_notifications/${ids.private}`, { method: 'DELETE', headers: headers(user) })).status, 403);
    }
  });
  await test('Public get remains allowed but public Firestore lists require validated backend', async () => {
    assert.equal((await query('notifications', [['published', true], ['targetEmail', '']], undefined)).status, 403);
    assert.equal((await query('notifications', [['published', true]], owner)).status, 403);
    assert.equal(await read('notifications', ids.public, undefined), 200);
    assert.equal(await read('notifications', ids.legacy, undefined), 403);
  });
  await test('App private UID query succeeds only for matching authenticated recipient or Admin', async () => {
    const filters = [['published', true], ['targetUid', owner.uid]];
    for (const [user, status] of [[owner, 200], [administrator, 200], [other, 403], [anonymous, 403], [undefined, 403]]) {
      assert.equal((await query('private_notifications', filters, user)).status, status);
    }
  });
  for (const user of [owner, other]) {
    await db.collection('users').doc(user.uid).set({ email: user.email, role: 'user' });
    await db.collection('users').doc(user.uid).collection('devices').doc(`${run}-${user.uid}`).set({ token: `${run}-${user.uid}`, active: true });
  }
  await test('Push selects only UID devices; legacy email still resolves; missing legacy user never broadcasts', async () => {
    for (const target of [{ targetUid: owner.uid }, { targetEmail: owner.email }]) {
      const devices = await loadTargetDevices(db, notificationTarget(target));
      assert.equal(devices.length, 1); assert.equal(devices[0].get('token'), `${run}-${owner.uid}`);
    }
    assert.equal((await loadTargetDevices(db, notificationTarget({ targetEmail: 'missing@example.invalid' }))).length, 0);
    const broadcast = await loadTargetDevices(db, notificationTarget({ targetEmail: '' }));
    assert.ok(broadcast.some(d => d.get('token') === `${run}-${owner.uid}`));
    assert.ok(broadcast.some(d => d.get('token') === `${run}-${other.uid}`));
  });
  await test('Admin atomic notification + queue creation and actual Functions trigger (FCM simulated locally)', async () => {
    const id = `${run}-queued`;
    // Same Firestore atomic contract used by the Flutter repository.
    const body = { writes: [
      { update: { name: `projects/${project}/databases/(default)/documents/private_notifications/${id}`, fields: fields(privateData) } },
      { update: { name: `projects/${project}/databases/(default)/documents/push_queue/${id}`, fields: fields({ ...privateData, status: 'queued' }) } },
    ] };
    const response = await fetch(`${root}:commit`, { method: 'POST', headers: headers(administrator), body: JSON.stringify(body) });
    assert.equal(response.status, 200);
    const deadline = Date.now() + 45000;
    let data;
    do {
      data = (await db.collection('push_queue').doc(id).get()).data();
      if (data?.status === 'sent') break;
      await new Promise(resolve => setTimeout(resolve, 200));
    } while (Date.now() < deadline);
    assert.equal(data.status, 'sent'); assert.equal(data.recipients, 1); assert.equal(data.failureCount, 0);
    assert.equal(data.deliveryMode, 'emulator-simulated');
    assert.equal(await read('push_queue', id, owner), 403);
  });
  await test('Public and legacy email queues still execute through Functions without external FCM', async () => {
    for (const [suffix, targetEmail, count] of [['broadcast', '', null], ['legacy-queue', owner.email, 1]]) {
      const id = `${run}-${suffix}`;
      if (targetEmail) {
        // Existing legacy queue fixture, never a new client/Admin contract.
        await db.collection('push_queue').doc(id).set({ ...publicData, targetEmail, status: 'queued' });
      } else {
        assert.equal(await write('push_queue', id, { ...publicData, targetEmail, status: 'queued' }, administrator), 200);
      }
      const deadline = Date.now() + 45000;
      let data;
      do {
        data = (await db.collection('push_queue').doc(id).get()).data();
        if (data?.status === 'sent') break;
        await new Promise(resolve => setTimeout(resolve, 200));
      } while (Date.now() < deadline);
      assert.equal(data.status, 'sent'); assert.equal(data.deliveryMode, 'emulator-simulated');
      if (count !== null) assert.equal(data.recipients, count);
      else assert.ok(data.recipients >= 2);
    }
  });
  console.log(`Notification emulator integration: ${passed} passed; demo only; no real FCM delivery.`);
}
main().then(() => admin.app().delete()).catch(error => { console.error(error.message); process.exitCode = 1; });
