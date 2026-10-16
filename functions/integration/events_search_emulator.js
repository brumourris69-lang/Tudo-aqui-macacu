'use strict';

// Additive integration test for the persistent local demo emulator. It only
// creates and removes its own uniquely named fixtures; it never clears a DB.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const net = require('node:net');
const project = process.env.GCLOUD_PROJECT;
assert.equal(project, 'demo-universal-search', 'Refusing any Firebase project other than the local demo.');
assert.equal(process.env.FUNCTIONS_EMULATOR, 'true');
for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
  assert.match(process.env[key] || '', /^127\.0\.0\.1:\d+$/, `${key} must be loopback-only.`);
}
const functionsPort = Number(process.env.FUNCTIONS_EMULATOR_PORT || 5007);
assert.equal(functionsPort, 5007, 'Unexpected Functions Emulator port.');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: project });
const db = admin.firestore();
const { INDEX, RATE } = require('../business_search');
const hostPort = (value) => {
  const [host, port] = value.split(':');
  return { host, port: Number(port) };
};
function assertPortOpen({ host, port }, label) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host, port });
    socket.setTimeout(1500);
    socket.once('connect', () => { socket.destroy(); resolve(); });
    socket.once('timeout', () => { socket.destroy(); reject(new Error(`${label} did not respond.`)); });
    socket.once('error', () => reject(new Error(`${label} is unavailable.`)));
  });
}

const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const base = `http://127.0.0.1:${functionsPort}/${project}/southamerica-east1/searchBusinesses`;
const eventDetailBase = `http://127.0.0.1:${functionsPort}/${project}/southamerica-east1/getSearchEvent`;
const authBase = `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`;
const token = crypto.randomBytes(5).toString('hex');
const eventIds = [`event-${token}-a`, `event-${token}-b`, `event-${token}-draft`,
  `event-${token}-inactive`, `event-${token}-expired`];
const businessId = `business-event-${token}`;
const fixtureRefs = [...eventIds.map((id) => db.collection('events').doc(id)),
  db.collection('establishments').doc(businessId)];
let createdUser;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(predicate, label) {
  const deadline = Date.now() + 45000;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await pause(250);
  }
  throw new Error(`Timed out waiting for local event trigger: ${label}`);
}
async function callRaw(query, filter = 'events', limit = 20, cursor = null) {
  // Keep the test independent from any existing user search quota document.
  const rateKey = crypto.createHash('sha256').update(createdUser.localId).digest('hex');
  await db.collection(RATE).doc(rateKey).delete();
  const appCheck = Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url') + '.' +
    Buffer.from(JSON.stringify({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 300 })).toString('base64url') + '.';
  const response = await fetch(base, { method: 'POST', headers: {
    'Content-Type': 'application/json', Authorization: `Bearer ${createdUser.idToken}`,
    'X-Firebase-AppCheck': appCheck,
  }, body: JSON.stringify({ data: { query, filter, limit, ...(cursor ? { cursor } : {}) } }) });
  const body = await response.json();
  return { status: response.status, body };
}
async function call(query, filter = 'events', limit = 20, cursor = null) {
  const response = await callRaw(query, filter, limit, cursor);
  assert.equal(response.status, 200, JSON.stringify(response.body));
  return response.body.result;
}
async function callEventDetail(id, { token: authToken = createdUser.idToken, appToken = 'valid' } = {}) {
  const rateKey = crypto.createHash('sha256').update(`event-detail:${createdUser.localId}`).digest('hex');
  await db.collection(RATE).doc(rateKey).delete();
  const appCheck = Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url') + '.' +
    Buffer.from(JSON.stringify({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 300 })).toString('base64url') + '.';
  const response = await fetch(eventDetailBase, { method: 'POST', headers: {
    'Content-Type': 'application/json', ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
    ...(appToken === null ? {} : { 'X-Firebase-AppCheck': appToken === 'valid' ? appCheck : appToken }),
  }, body: JSON.stringify({ data: { id } }) });
  return { status: response.status, body: await response.json() };
}
async function main() {
  await Promise.all([
    assertPortOpen(hostPort(authHost), 'Auth Emulator'),
    assertPortOpen(hostPort(firestoreHost), 'Firestore Emulator'),
    assertPortOpen({ host: '127.0.0.1', port: functionsPort }, 'Functions Emulator'),
  ]);
  const signUp = await fetch(authBase, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }) });
  assert.equal(signUp.status, 200, 'Auth Emulator must create the temporary test visitor.');
  createdUser = await signUp.json();

  const eventBase = { published: true, title: `Evento Fictício ${token}`,
    category: 'Cultura', description: 'Encontro comunitário de teste',
    location: 'Praça de Teste', eventDate: '01/01/2000',
    imageUrl: 'https://images.example.invalid/event.jpg',
    ownerEmail: 'private@example.invalid', privateNotes: 'MUST_NOT_BE_INDEXED' };
  try {
    await fixtureRefs[0].set(eventBase);
    await fixtureRefs[1].set({ ...eventBase, eventDate: '2026-10-25T19:00' });
    await fixtureRefs[2].set({ ...eventBase, title: `oculto${token}`, published: false });
    await fixtureRefs[3].set({ ...eventBase, title: `inativo${token}`, active: false });
    await fixtureRefs[4].set({ ...eventBase, title: `expirado${token}`,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 60000) });
    await fixtureRefs[5].set({ name: `Evento Fictício ${token}`, category: 'Comércio', published: true });

    await until(async () => {
      const docs = await Promise.all(eventIds.map((id) => db.collection(INDEX).doc(`events__${id}`).get()));
      return docs[0].exists && docs[1].exists && !docs[2].exists && !docs[3].exists && !docs[4].exists &&
        (await db.collection(INDEX).doc(`establishments__${businessId}`).get()).exists;
    }, 'create, visibility policy and projection');

    const entries = await Promise.all(eventIds.slice(0, 2).map((id) => db.collection(INDEX).doc(`events__${id}`).get()));
    for (const snapshot of entries) {
      const indexed = snapshot.data();
      assert.equal(indexed.sourceCollection, 'events');
      assert.equal(indexed.group, 'events');
      assert.equal(indexed.type, 'events');
      assert.equal(indexed.destination, 'eventDetail');
      assert.ok(indexed.prefixes.includes(token));
      assert.equal(indexed.ownerEmail, undefined);
      assert.equal(indexed.privateNotes, undefined);
    }

    const first = await call(token, 'events', 1);
    assert.equal(first.results.length, 1);
    assert.equal(first.results[0].sourceCollection, 'events');
    assert.ok(first.nextCursor);
    const second = await call(token, 'events', 1, first.nextCursor);
    assert.equal(second.results.length, 1);
    assert.notEqual(second.results[0].id, first.results[0].id);
    // The backend deliberately avoids a lookahead read, so an exactly full
    // final page can carry a cursor whose next page is empty.
    assert.ok(second.nextCursor);
    const finalPage = await call(token, 'events', 1, second.nextCursor);
    assert.deepEqual(finalPage.results, []);
    assert.equal(finalPage.nextCursor, null);
    const all = await call(token, 'all', 20);
    assert.equal(all.results.filter((row) => row.sourceCollection === 'events').length, 2);
    assert.equal(all.results.filter((row) => row.sourceCollection === 'establishments').length, 1);
    assert.equal(new Set(all.results.map((row) => `${row.sourceCollection}:${row.id}`)).size, all.results.length);
    for (const hiddenTerm of [`oculto${token}`, `inativo${token}`, `expirado${token}`]) {
      assert.deepEqual((await call(hiddenTerm, 'events')).results, [], hiddenTerm);
    }

    const detail = await callEventDetail(eventIds[0]);
    assert.equal(detail.status, 200, JSON.stringify(detail.body));
    assert.equal(detail.body.result.status, 'available');
    assert.equal(detail.body.result.id, eventIds[0]);
    assert.equal(detail.body.result.data.title, eventBase.title);
    assert.equal(detail.body.result.data.description, eventBase.description);
    assert.equal(detail.body.result.data.eventDate, eventBase.eventDate);
    assert.equal(detail.body.result.data.imageUrl, eventBase.imageUrl);
    assert.equal(detail.body.result.data.ownerEmail, undefined);
    assert.equal(detail.body.result.data.privateNotes, undefined);
    assert.equal(detail.body.result.data.expiresAt, undefined);
    assert.deepEqual((await callEventDetail('missing-event')).body.result, { status: 'unavailable' });
    assert.equal((await callEventDetail('bad/id')).body.error.status, 'INVALID_ARGUMENT');
    assert.notEqual((await callEventDetail(eventIds[0], { token: null })).status, 200);
    assert.notEqual((await callEventDetail(eventIds[0], { appToken: null })).status, 200);
    assert.notEqual((await callEventDetail(eventIds[0], { appToken: 'malformed-token' })).status, 200);
    assert.deepEqual((await callEventDetail(eventIds[2])).body.result, { status: 'unavailable' });
    assert.deepEqual((await callEventDetail(eventIds[3])).body.result, { status: 'unavailable' });
    assert.deepEqual((await callEventDetail(eventIds[4])).body.result, { status: 'unavailable' });

    const eventDoc = fixtureRefs[0];
    await eventDoc.update({ title: `Evento Atualizado ${token}`, category: 'Música' });
    await until(async () => (await db.collection(INDEX).doc(`events__${eventIds[0]}`).get()).data()?.title === `Evento Atualizado ${token}`,
      'update event projection');
    assert.equal((await call(token, 'events', 20)).results.some((row) => row.title === `Evento Atualizado ${token}`), true);
    await eventDoc.update({ published: false });
    await until(async () => !(await db.collection(INDEX).doc(`events__${eventIds[0]}`).get()).exists,
      'unpublish event');
    assert.equal((await call(token, 'events', 20)).results.some((row) => row.id === eventIds[0]), false);
    await fixtureRefs[1].delete();
    await until(async () => !(await db.collection(INDEX).doc(`events__${eventIds[1]}`).get()).exists,
      'delete event');
    const invalid = await callRaw(token, 'events', 20,
      { queryKey: `events:${token}`, lastIndexId: `news__${eventIds[0]}` });
    assert.notEqual(invalid.status, 200, 'Invalid event cursor must be rejected.');
    assert.equal(invalid.body.error.status, 'INVALID_ARGUMENT');
  } finally {
    await Promise.all(fixtureRefs.map((ref) => ref.delete().catch(() => {})));
    await Promise.all([...eventIds.map((id) => db.collection(INDEX).doc(`events__${id}`).delete()),
      db.collection(INDEX).doc(`establishments__${businessId}`).delete()].map((promise) => promise.catch(() => {})));
    if (createdUser?.localId) {
      const rateKey = crypto.createHash('sha256').update(createdUser.localId).digest('hex');
      await db.collection(RATE).doc(rateKey).delete().catch(() => {});
      await admin.auth().deleteUser(createdUser.localId).catch(() => {});
    }
  }
  console.log(JSON.stringify({ project, emulatorServices: ['Auth', 'Firestore', 'Functions'], fixturesCreated: 6,
    fixturesRemoved: 6, tests: ['event trigger and projection', 'secure detail Auth/App Check and field allowlist', 'visibility', 'accentless prefix search',
      'events filter', 'Todos', 'pagination', 'composite identity', 'update', 'unpublish', 'delete'] }, null, 2));
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; })
  .finally(() => admin.app().delete());
