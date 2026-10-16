'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { verifyCandidate, loadVerifiedSnapshot } = require('./firestore_rules_containment_contract');

const PROJECT_ID = 'demo-universal-search';
const TARGET_COLLECTIONS = ['establishments', 'routes', 'utilities', 'jobs'];
const FIRESTORE_ROOT = `/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const createdDocuments = [];
const createdUsers = [];
let activeScenario = 'preflight';
let activeHttpStatus;
let activeSafeStatus;

class HttpStatusError extends Error {
  constructor(status, safeStatus) {
    super('Local emulator request failed.');
    this.status = status;
    this.safeStatus = safeStatus;
  }
}

class LocalTransportError extends Error {}

function fail(message) {
  throw new Error(message);
}

function parseLoopbackHost(value, label) {
  const match = /^127\.0\.0\.1:(\d{1,5})$/.exec(value || '');
  if (!match) fail(`${label} must be an explicit 127.0.0.1 host and port.`);
  const port = Number(match[1]);
  if (port < 1 || port > 65535) fail(`${label} port is invalid.`);
  return port;
}

function assertLocalConfig(configPath, rulesPath, authPort, firestorePort) {
  if (!configPath || !path.isAbsolute(configPath)) fail('An absolute emulator config path is required.');
  let config;
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch {
    fail('The isolated emulator config is missing or invalid.');
  }
  const firestoreRules = path.resolve(path.dirname(configPath), config.firestore?.rules || '');
  if (firestoreRules !== path.resolve(rulesPath)) fail('Emulator config does not point to the expected verified Rules.');
  if (
    config.emulators?.auth?.host !== '127.0.0.1' ||
    config.emulators?.firestore?.host !== '127.0.0.1' ||
    config.emulators.auth.port !== authPort ||
    config.emulators.firestore.port !== firestorePort ||
    config.emulators.firestore.websocketPort < 1 ||
    config.emulators.hub?.host !== '127.0.0.1' ||
    config.emulators.logging?.host !== '127.0.0.1' ||
    config.emulators.hub.port < 1 ||
    config.emulators.logging.port < 1 ||
    config.emulators?.ui?.enabled !== false ||
    config.emulators?.singleProjectMode !== true
  ) {
    fail('Emulator config is not restricted to the expected loopback services.');
  }
  const allowedEmulatorKeys = new Set(['auth', 'firestore', 'hub', 'logging', 'ui', 'singleProjectMode']);
  if (Object.keys(config.emulators || {}).some((key) => !allowedEmulatorKeys.has(key))) {
    fail('Unexpected emulator service is configured.');
  }
  if (config.emulators.auth.dataDir || config.emulators.firestore.dataDir || config.emulators.firestore.exportOnExit) {
    fail('Persistent data import or export configuration is not permitted.');
  }
}

function extractAdminEmail(rules) {
  const match = /function\s+admin\s*\(\s*\)\s*\{([\s\S]*?)^\s*\}/m.exec(rules);
  if (!match) fail('Published Admin helper could not be identified.');
  const emailMatches = [...match[1].matchAll(/request\.auth\.token\.email\s*==\s*['"]([^'"]+)['"]/g)];
  if (emailMatches.length !== 1) fail('Published Admin helper is not a single-email predicate.');
  return emailMatches[0][1];
}

async function request(url, { method = 'GET', token, body } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  try {
    return await fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      redirect: 'error',
    });
  } catch {
    throw new LocalTransportError('Local emulator transport failed.');
  }
}

async function jsonResponse(response) {
  if (!response.ok) {
    const safeStatus = await readSafeStatus(response);
    throw new HttpStatusError(response.status, safeStatus);
  }
  try {
    return await response.json();
  } catch {
    throw new Error('Local emulator returned an invalid response.');
  }
}

async function readSafeStatus(response) {
  const allowedStatuses = new Set([
    'ALREADY_EXISTS',
    'FAILED_PRECONDITION',
    'INTERNAL',
    'INVALID_ARGUMENT',
    'NOT_FOUND',
    'PERMISSION_DENIED',
    'RESOURCE_EXHAUSTED',
    'UNAUTHENTICATED',
  ]);
  let payload;
  try {
    payload = JSON.parse(await response.text());
  } catch {
    return undefined;
  }
  const status = String(payload?.error?.status || '').toUpperCase();
  if (!allowedStatuses.has(status)) return undefined;
  const message = String(payload?.error?.message || '').toLowerCase();
  const category = message.includes('microsecond') || message.includes('timestamp precision')
    ? 'TIMESTAMP_PRECISION'
    : message.includes('precondition') || message.includes('update time')
      ? 'PRECONDITION_MISMATCH'
      : undefined;
  return category ? `${status}:${category}` : status;
}

function localAuthUrl(authHost) {
  return `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`;
}

function localAuthSignInUrl(authHost) {
  return `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`;
}

async function createUser(authHost, { email, anonymous = false }) {
  const password = `T-${crypto.randomBytes(18).toString('hex')}!a1`;
  const payload = anonymous
    ? { returnSecureToken: true }
    : { email, password, returnSecureToken: true };
  // A fresh, non-importing Emulator invocation is the backstop for the rare
  // case where Auth accepts a signup but its response is lost before we learn
  // the UID/token needed for targeted cleanup.
  let user;
  try {
    const response = await request(localAuthUrl(authHost), { method: 'POST', body: payload });
    user = await jsonResponse(response);
    if (!user.localId || !user.idToken) throw new Error('Local identity response was incomplete.');
  } catch {
    if (anonymous) fail('Auth Emulator signup request did not complete.');
    try {
      const recovery = await request(localAuthSignInUrl(authHost), {
        method: 'POST',
        body: { email, password, returnSecureToken: true },
      });
      user = await jsonResponse(recovery);
      if (!user.localId || !user.idToken) fail('Auth Emulator returned an incomplete local identity.');
    } catch {
      fail('Auth Emulator signup request did not complete.');
    }
  }
  const result = { uid: user.localId, token: user.idToken };
  createdUsers.push(result);
  return result;
}

function documentUrl(collection, id) {
  const collectionPath = `/${encodeURIComponent(collection)}`;
  const suffix = id ? `${collectionPath}/${encodeURIComponent(id)}` : collectionPath;
  return `http://${process.env.FIRESTORE_EMULATOR_HOST}${FIRESTORE_ROOT}${suffix}`;
}

function firestoreFields(fields) {
  const encoded = {};
  for (const [key, value] of Object.entries(fields)) {
    if (typeof value === 'boolean') encoded[key] = { booleanValue: value };
    else encoded[key] = { stringValue: String(value) };
  }
  return { fields: encoded };
}

async function reserveFixtureId(collection, id = crypto.randomUUID()) {
  const response = await firestoreCall('GET', collection, id, 'owner');
  await expectStatus(response, [404], 'unique-fixture-id');
  createdDocuments.push({ collection, id, marker: crypto.randomUUID() });
  return id;
}

function fixtureMarker(collection, id) {
  const fixture = createdDocuments.find((entry) => entry.collection === collection && entry.id === id);
  if (!fixture) fail('Fixture ownership marker is unavailable.');
  return fixture.marker;
}

async function assertFixtureOwnership(collection, id, marker) {
  const response = await firestoreCall('GET', collection, id, 'owner');
  if (response.status === 404) {
    await response.arrayBuffer();
    return false;
  }
  const document = await jsonResponse(response);
  if (document.fields?.fixtureMarker?.stringValue !== marker) {
    fail('Fixture ownership check failed.');
  }
  return true;
}

async function deleteFixture(collection, id, marker, token) {
  if (!(await assertFixtureOwnership(collection, id, marker))) return null;
  return firestoreCall(
    'DELETE', collection, id, token, undefined,
    '?currentDocument.exists=true',
  );
}

async function seedDocument(collection, fields, id) {
  const reservedId = await reserveFixtureId(collection, id || crypto.randomUUID());
  const url = `${documentUrl(collection)}?documentId=${encodeURIComponent(reservedId)}`;
  const response = await request(url, {
    method: 'POST',
    token: 'owner',
    body: firestoreFields({ ...fields, fixtureMarker: fixtureMarker(collection, reservedId) }),
  });
  await jsonResponse(response);
  return reservedId;
}

async function firestoreCall(method, collection, id, token, body, query = '') {
  let url = id ? documentUrl(collection, id) : documentUrl(collection);
  if (query) url += query;
  return request(url, { method, token, body });
}

async function firestoreQuery(collection, token, field, value) {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}${FIRESTORE_ROOT}:runQuery`;
  const encodedValue = typeof value === 'boolean' ? { booleanValue: value } : { stringValue: String(value) };
  return request(url, {
    method: 'POST',
    token,
    body: {
      structuredQuery: {
        from: [{ collectionId: collection }],
        where: {
          fieldFilter: {
            field: { fieldPath: field },
            op: 'EQUAL',
            value: encodedValue,
          },
        },
        limit: 100,
      },
    },
  });
}

async function expectStatus(response, accepted, description) {
  activeScenario = description;
  activeHttpStatus = response.status;
  const safeStatus = accepted.includes(response.status) ? undefined : await readSafeStatus(response);
  if (!accepted.includes(response.status)) {
    throw new HttpStatusError(response.status, safeStatus);
  }
  await response.arrayBuffer();
  return description;
}

async function runScenario(name, callback) {
  activeScenario = name;
  activeHttpStatus = undefined;
  activeSafeStatus = undefined;
  await callback();
  process.stdout.write(`PASS ${name}\n`);
}

async function cleanup(authHost) {
  const cleanupFailures = [];
  for (const { collection, id, marker } of createdDocuments.reverse()) {
    try {
      const response = await deleteFixture(collection, id, marker, 'owner');
      if (!response) continue;
      if (!response.ok && response.status !== 404) {
        activeHttpStatus = response.status;
        activeSafeStatus = await readSafeStatus(response);
        cleanupFailures.push('document');
      }
      else {
        await response.arrayBuffer();
        const verifyDelete = await firestoreCall('GET', collection, id, 'owner');
        await expectStatus(verifyDelete, [404], 'fixture-cleanup-verified');
      }
    } catch {
      cleanupFailures.push('document');
    }
  }
  for (const user of createdUsers.reverse()) {
    try {
      const response = await request(localAuthUrl(authHost).replace('accounts:signUp', 'accounts:delete'), {
        method: 'POST',
        body: { idToken: user.token },
      });
      if (!response.ok && response.status !== 404) cleanupFailures.push('auth-user');
      else {
        await response.arrayBuffer();
        const verifyDelete = await request(
          localAuthUrl(authHost).replace('accounts:signUp', 'accounts:lookup'),
          { method: 'POST', body: { idToken: user.token } },
        );
        await verifyDelete.arrayBuffer();
        if (verifyDelete.status !== 400 && verifyDelete.status !== 401) cleanupFailures.push('auth-user');
      }
    } catch {
      cleanupFailures.push('auth-user');
    }
  }
  createdDocuments.length = 0;
  createdUsers.length = 0;
  if (cleanupFailures.length) fail('Fixture cleanup did not complete fully.');
}

async function main() {
  const snapshotPath = process.env.FIRESTORE_RULES_SNAPSHOT_PATH;
  const candidatePath = process.env.FIRESTORE_RULES_CANDIDATE_PATH;
  const originalRulesPath = process.env.FIRESTORE_RULES_ORIGINAL_PATH;
  const testMode = process.env.FIRESTORE_RULES_TEST_MODE;
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
  const selectedProjects = [process.env.GCLOUD_PROJECT, process.env.GOOGLE_CLOUD_PROJECT].filter(Boolean);
  if (!selectedProjects.length || selectedProjects.some((projectId) => projectId !== PROJECT_ID)) {
    fail('Only the demo-universal-search project is permitted.');
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.FIREBASE_TOKEN) {
    fail('Cloud credentials are not permitted in this harness.');
  }
  if (!snapshotPath || !path.isAbsolute(snapshotPath) || !candidatePath || !path.isAbsolute(candidatePath)) {
    fail('Absolute snapshot and candidate paths are required.');
  }
  const authPort = parseLoopbackHost(authHost, 'Auth Emulator');
  const firestorePort = parseLoopbackHost(firestoreHost, 'Firestore Emulator');
  const { content: publishedRules } = loadVerifiedSnapshot(snapshotPath);
  verifyCandidate(snapshotPath, candidatePath);
  let expectedRulesPath;
  if (testMode === 'candidate') {
    expectedRulesPath = candidatePath;
  } else if (testMode === 'snapshot' && originalRulesPath && path.isAbsolute(originalRulesPath)) {
    let originalRules;
    try {
      originalRules = fs.readFileSync(originalRulesPath, 'utf8');
    } catch {
      fail('Verified original Rules copy is missing or unreadable.');
    }
    if (originalRules !== publishedRules) fail('Original Rules copy differs from the verified snapshot.');
    expectedRulesPath = originalRulesPath;
  } else {
    fail('An explicit snapshot or candidate test mode is required.');
  }
  assertLocalConfig(process.env.FIRESTORE_RULES_EMULATOR_CONFIG, expectedRulesPath, authPort, firestorePort);

  const adminEmail = extractAdminEmail(publishedRules);
  const isCandidate = testMode === 'candidate';
  const fixture = {
    target: Object.fromEntries(TARGET_COLLECTIONS.map((collection) => [collection, crypto.randomUUID()])),
    utilityActiveOnly: crypto.randomUUID(),
    private: crypto.randomUUID(),
    eventPublished: crypto.randomUUID(),
    eventUnpublished: crypto.randomUUID(),
  };
  let users;
  let cleanupNeeded = false;
  try {
    await runScenario('create disposable identities and isolated fixtures', async () => {
      const admin = await createUser(authHost, { email: adminEmail });
      const ordinary = await createUser(authHost, { email: `ordinary-${crypto.randomUUID()}@example.test` });
      const anonymous = await createUser(authHost, { anonymous: true });
      users = { admin, ordinary, anonymous };

      for (const collection of TARGET_COLLECTIONS) {
        await seedDocument(collection, {
          published: true,
          active: true,
          fixtureMarker: crypto.randomUUID(),
        }, fixture.target[collection]);
      }
      await seedDocument('utilities', {
        published: false,
        active: true,
        fixtureMarker: crypto.randomUUID(),
      }, fixture.utilityActiveOnly);
      await seedDocument('job_private', {
        fixtureMarker: crypto.randomUUID(),
      }, fixture.private);
      await seedDocument('events', {
        published: true,
        fixtureMarker: crypto.randomUUID(),
      }, fixture.eventPublished);
      await seedDocument('events', {
        published: false,
        fixtureMarker: crypto.randomUUID(),
      }, fixture.eventUnpublished);
      cleanupNeeded = true;
    });

    const { admin, ordinary, anonymous } = users;
    const identities = [
      { name: 'visitor', token: undefined },
      { name: 'anonymous', token: anonymous.token },
      { name: 'ordinary', token: ordinary.token },
    ];

    await runScenario('public direct get and list denied for target collections', async () => {
      for (const collection of TARGET_COLLECTIONS) {
        for (const identity of identities) {
          const get = await firestoreCall('GET', collection, fixture.target[collection], identity.token);
          await expectStatus(get, isCandidate ? [401, 403] : [200], `${identity.name}-${collection}-get`);
          const list = await firestoreCall('GET', collection, undefined, identity.token, undefined, '?pageSize=100');
          const listAllowed =
            !isCandidate && identity.name !== 'visitor' && collection !== 'utilities';
          await expectStatus(list, listAllowed ? [200] : [401, 403], `${identity.name}-${collection}-unfiltered-list`);
        }
        const visitorPublishedQuery = await firestoreQuery(collection, undefined, 'published', true);
        await expectStatus(
          visitorPublishedQuery,
          isCandidate ? [401, 403] : [200],
          `visitor-${collection}-published-query`,
        );
        const adminGet = await firestoreCall('GET', collection, fixture.target[collection], admin.token);
        await expectStatus(adminGet, [200], `admin-${collection}-get`);
        const adminList = await firestoreCall('GET', collection, undefined, admin.token, undefined, '?pageSize=100');
        await expectStatus(adminList, [200], `admin-${collection}-list`);
      }
    });

    await runScenario('utilities publication and active flags do not grant public access', async () => {
      for (const id of [fixture.target.utilities, fixture.utilityActiveOnly]) {
        for (const identity of identities) {
          const response = await firestoreCall('GET', 'utilities', id, identity.token);
          await expectStatus(response, isCandidate ? [401, 403] : [200], `${identity.name}-utility-get`);
        }
        const response = await firestoreCall('GET', 'utilities', id, admin.token);
        await expectStatus(response, [200], 'admin-utility-get');
      }
      const activeQuery = await firestoreQuery('utilities', undefined, 'active', true);
      await expectStatus(activeQuery, isCandidate ? [401, 403] : [200], 'visitor-utilities-active-query');
    });

    await runScenario('authorized Admin retains CRUD on the four public collections', async () => {
      for (const collection of TARGET_COLLECTIONS) {
        const id = await reserveFixtureId(collection);
        const marker = fixtureMarker(collection, id);
        const create = await firestoreCall(
          'POST', collection, undefined, admin.token,
          firestoreFields({ published: true, active: true, fixtureMarker: marker }),
          `?documentId=${encodeURIComponent(id)}`,
        );
        await expectStatus(create, [200], `admin-${collection}-create`);
        const update = await firestoreCall(
          'PATCH', collection, id, admin.token,
          firestoreFields({ fixtureUpdated: true }),
          '?updateMask.fieldPaths=fixtureUpdated',
        );
        await expectStatus(update, [200], `admin-${collection}-update`);
        const remove = await deleteFixture(collection, id, marker, admin.token);
        if (!remove) fail('Admin fixture disappeared before deletion.');
        await expectStatus(remove, [200], `admin-${collection}-delete`);
        const verifyDelete = await firestoreCall('GET', collection, id, 'owner');
        await expectStatus(verifyDelete, [404], `admin-${collection}-delete-verified`);
        createdDocuments.splice(createdDocuments.findIndex((doc) => doc.collection === collection && doc.id === id), 1);
      }
    });

    await runScenario('non-Admin writes are denied on the four public collections', async () => {
      const writeIdentities = identities;
      for (const collection of TARGET_COLLECTIONS) {
        for (const identity of writeIdentities) {
          const id = await reserveFixtureId(collection);
          const create = await firestoreCall(
            'POST', collection, undefined, identity.token,
            firestoreFields({ fixtureMarker: fixtureMarker(collection, id) }),
            `?documentId=${encodeURIComponent(id)}`,
          );
          await expectStatus(create, [401, 403], `${identity.name}-${collection}-create`);
          const update = await firestoreCall(
            'PATCH', collection, fixture.target[collection], identity.token,
            firestoreFields({ fixtureMarker: crypto.randomUUID() }),
            '?updateMask.fieldPaths=fixtureMarker',
          );
          await expectStatus(update, [401, 403], `${identity.name}-${collection}-update`);
          const remove = await firestoreCall('DELETE', collection, fixture.target[collection], identity.token);
          await expectStatus(remove, [401, 403], `${identity.name}-${collection}-delete`);
        }
      }
    });

    await runScenario('job_private is denied for every identity and operation', async () => {
      const allIdentities = [...identities, { name: 'admin', token: admin.token }];
      for (const identity of allIdentities) {
        const get = await firestoreCall('GET', 'job_private', fixture.private, identity.token);
        await expectStatus(get, [401, 403], `${identity.name}-private-get`);
        const list = await firestoreCall('GET', 'job_private', undefined, identity.token, undefined, '?pageSize=100');
        await expectStatus(list, [401, 403], `${identity.name}-private-list`);
        const createId = await reserveFixtureId('job_private');
        const marker = fixtureMarker('job_private', createId);
        const adminHasPublishedWrite = identity.name === 'admin' && !isCandidate;
        const create = await firestoreCall(
          'POST', 'job_private', undefined, identity.token,
          firestoreFields({ fixtureMarker: marker }),
          `?documentId=${encodeURIComponent(createId)}`,
        );
        await expectStatus(create, adminHasPublishedWrite ? [200] : [401, 403], `${identity.name}-private-create`);
        if (adminHasPublishedWrite) {
          const update = await firestoreCall(
            'PATCH', 'job_private', createId, identity.token,
            firestoreFields({ fixtureUpdated: true }),
            '?updateMask.fieldPaths=fixtureUpdated',
          );
          await expectStatus(update, [200], 'admin-private-update-original');
          const remove = await deleteFixture('job_private', createId, marker, identity.token);
          if (!remove) fail('Original Admin private fixture disappeared before deletion.');
          await expectStatus(remove, [200], 'admin-private-delete-original');
          await expectStatus(await firestoreCall('GET', 'job_private', createId, 'owner'), [404], 'admin-private-delete-verified');
          createdDocuments.splice(createdDocuments.findIndex((doc) => doc.collection === 'job_private' && doc.id === createId), 1);
        } else {
          const update = await firestoreCall(
            'PATCH', 'job_private', fixture.private, identity.token,
            firestoreFields({ fixtureUpdated: true }),
            '?updateMask.fieldPaths=fixtureUpdated',
          );
          await expectStatus(update, [401, 403], `${identity.name}-private-update`);
          const remove = await firestoreCall('DELETE', 'job_private', fixture.private, identity.token);
          await expectStatus(remove, [401, 403], `${identity.name}-private-delete`);
        }
      }
      const privateStillExists = await firestoreCall('GET', 'job_private', fixture.private, 'owner');
      await expectStatus(privateStillExists, [200], 'fixture-preserved-after-denied-access');
    });

    await runScenario('out-of-scope events permissions remain unchanged', async () => {
      const published = await firestoreCall('GET', 'events', fixture.eventPublished);
      await expectStatus(published, [200], 'visitor-event-published-get');
      const unpublished = await firestoreCall('GET', 'events', fixture.eventUnpublished);
      await expectStatus(unpublished, [401, 403], 'visitor-event-unpublished-get');
      const signedRead = await firestoreCall('GET', 'events', fixture.eventUnpublished, ordinary.token);
      await expectStatus(signedRead, [200], 'signed-in-event-unpublished-get');
      const signedList = await firestoreCall('GET', 'events', undefined, ordinary.token, undefined, '?pageSize=100');
      await expectStatus(signedList, [200], 'signed-in-event-list');
      const adminEventId = await reserveFixtureId('events');
      const marker = fixtureMarker('events', adminEventId);
      const create = await firestoreCall(
        'POST', 'events', undefined, admin.token,
        firestoreFields({ published: true, fixtureMarker: marker }),
        `?documentId=${encodeURIComponent(adminEventId)}`,
      );
      await expectStatus(create, [200], 'admin-event-create');
      const remove = await deleteFixture('events', adminEventId, marker, admin.token);
      if (!remove) fail('Admin event fixture disappeared before deletion.');
      await expectStatus(remove, [200], 'admin-event-delete');
      const verifyDelete = await firestoreCall('GET', 'events', adminEventId, 'owner');
      await expectStatus(verifyDelete, [404], 'admin-event-delete-verified');
      createdDocuments.splice(createdDocuments.findIndex((doc) => doc.collection === 'events' && doc.id === adminEventId), 1);
    });
  } finally {
    if (cleanupNeeded || createdDocuments.length || createdUsers.length) await cleanup(authHost);
  }
}

main().then(() => {
  process.stdout.write('Fixture cleanup completed.\n');
}).catch((error) => {
  const failure = error instanceof HttpStatusError
    ? `HTTP ${error.status}${error.safeStatus ? ` ${error.safeStatus}` : ''}`
    : error instanceof LocalTransportError
      ? 'local transport'
      : Number.isInteger(activeHttpStatus)
        ? `response handling HTTP ${activeHttpStatus}${activeSafeStatus ? ` ${activeSafeStatus}` : ''}`
        : `internal ${error?.name === 'TypeError' ? 'TypeError' : 'Error'}`;
  process.stderr.write(`FAIL ${activeScenario} [${failure}]\n`);
  process.exitCode = 1;
});
