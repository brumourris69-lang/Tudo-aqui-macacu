'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const test = require('node:test');

let bridge;
test.before(async () => {
  bridge = await import('../integration/local_admin_establishments_bridge.mjs');
});

const { ADMIN_BRIDGE_PATH, ADMIN_BRIDGE_PORT, DEMO_PROJECT_ID } = {
  ADMIN_BRIDGE_PATH: '/functions/v1/manage-establishments',
  ADMIN_BRIDGE_PORT: 5077,
  DEMO_PROJECT_ID: 'demo-universal-search',
};

const expectedHub = {
  auth: { host: '127.0.0.1', port: 9097 },
  firestore: { host: '127.0.0.1', port: 8087 },
  functions: { host: '127.0.0.1', port: 5007 },
};

function localEnvironment(overrides = {}) {
  return {
    GCLOUD_PROJECT: DEMO_PROJECT_ID,
    FIREBASE_CONFIG: JSON.stringify({ projectId: DEMO_PROJECT_ID }),
    FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9097',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087',
    LOCAL_ADMIN_BRIDGE_CONFIRM: DEMO_PROJECT_ID,
    LOCAL_ADMIN_BRIDGE_PORT: String(ADMIN_BRIDGE_PORT),
    ...overrides,
  };
}

function createFakeFirestore(initial = {}, { failOnCreate } = {}) {
  const documents = new Map(Object.entries(initial).map(([key, data]) => [key, structuredClone(data)]));
  const reference = (collection, id) => ({ collection, id, key: `${collection}/${id}` });
  const db = {
    collection: (collection) => ({ doc: (id) => reference(collection, id) }),
    async runTransaction(callback) {
      const staged = new Map();
      const native = {
        async get(ref) {
          const value = staged.has(ref.key) ? staged.get(ref.key) : documents.get(ref.key);
          return value === undefined ? { exists: false } : {
            exists: true,
            data: () => structuredClone(value),
            updateTime: { seconds: 100, nanoseconds: 42 },
          };
        },
        create(ref, value) {
          if (ref.key === failOnCreate) throw new Error('synthetic transaction failure');
          if (documents.has(ref.key) || staged.has(ref.key)) throw Object.assign(new Error(), { code: 6 });
          staged.set(ref.key, structuredClone(value));
        },
        update(ref, value) {
          const previous = staged.has(ref.key) ? staged.get(ref.key) : documents.get(ref.key);
          if (previous === undefined) throw Object.assign(new Error(), { code: 5 });
          staged.set(ref.key, { ...structuredClone(previous), ...structuredClone(value) });
        },
      };
      const result = await callback(native);
      for (const [key, value] of staged) documents.set(key, value);
      return result;
    },
  };
  return { db, documents };
}

function fixture() {
  const uid = 'synthetic-admin-uid';
  const { db, documents } = createFakeFirestore({
    [`admin_authorizations/${uid}`]: { enabled: true, pending: false, version: 'admin-v1' },
  });
  const tokenCalls = [];
  const auth = {
    async verifyIdToken(token, checkRevoked) {
      tokenCalls.push({ token, checkRevoked });
      if (token === 'invalid-token' || token === 'revoked-token') {
        throw Object.assign(new Error('sensitive SDK detail'), { code: 'auth/id-token-revoked' });
      }
      const decoded = {
        uid, sub: uid, aud: DEMO_PROJECT_ID,
        iss: `https://securetoken.google.com/${DEMO_PROJECT_ID}`,
        auth_time: 1000, firebase: { sign_in_provider: 'password' },
      };
      if (token === 'wrong-project-token') decoded.aud = 'unapproved-project';
      if (token === 'anonymous-token') decoded.firebase.sign_in_provider = 'anonymous';
      if (token === 'ordinary-token') decoded.uid = decoded.sub = 'synthetic-ordinary-uid';
      return decoded;
    },
  };
  const fieldValue = {
    serverTimestamp: () => ({ __syntheticServerTimestamp: true }),
    delete: () => ({ __syntheticDelete: true }),
  };
  return { db, documents, auth, fieldValue, tokenCalls, uid };
}

async function withServer(handler, callback) {
  const server = bridge.createLocalAdminEstablishmentsServer(handler);
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  try {
    const address = server.address();
    assert.equal(address.address, '127.0.0.1');
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

test('local bridge accepts only the pinned demo Emulator configuration without credentials', () => {
  assert.deepEqual(bridge.assertLocalAdminBridgeEnvironment(localEnvironment()), {
    projectId: DEMO_PROJECT_ID, host: '127.0.0.1', port: 5077,
    path: ADMIN_BRIDGE_PATH,
  });
  for (const overrides of [
    { GCLOUD_PROJECT: 'tudo-aqui-macacu' },
    { FIREBASE_AUTH_EMULATOR_HOST: '10.0.2.2:9097' },
    { FIRESTORE_EMULATOR_HOST: 'example.invalid:8087' },
    { LOCAL_ADMIN_BRIDGE_CONFIRM: 'other-project' },
    { LOCAL_ADMIN_BRIDGE_PORT: '5078' },
    { GOOGLE_APPLICATION_CREDENTIALS: 'synthetic-key-file' },
    { FIREBASE_TOKEN: 'synthetic-cli-token' },
    { FIREBASE_CONFIG: '{bad json' },
    { FIREBASE_CONFIG: JSON.stringify({ projectId: 'other-project' }) },
  ]) {
    assert.throws(() => bridge.assertLocalAdminBridgeEnvironment(localEnvironment(overrides)));
  }
});

test('Emulator Hub identity is checked at loopback before the bridge can start', async () => {
  const urls = [];
  assert.equal(await bridge.verifyDemoEmulatorHub({ fetchImpl: async (url) => {
    urls.push(url);
    return { ok: true, json: async () => expectedHub };
  } }), true);
  assert.deepEqual(urls, ['http://127.0.0.1:4407/emulators']);
  await assert.rejects(bridge.verifyDemoEmulatorHub({ fetchImpl: async () => ({
    ok: true, json: async () => ({ ...expectedHub, firestore: { host: '0.0.0.0', port: 8087 } }),
  }) }));
  await assert.rejects(bridge.verifyDemoEmulatorHub({ fetchImpl: async () => ({ ok: false }) }));
});

test('route reuses the administrative handler, verifies the Auth Emulator token, and commits source/outbox together', async () => {
  const state = fixture();
  const handler = bridge.createLocalAdminEstablishmentsHandler({ env: localEnvironment(),
    auth: state.auth, db: state.db, fieldValue: state.fieldValue,
    uuid: () => 'd193d6f0-5bb3-4eb5-9c43-f9c000000001' });
  await withServer(handler, async (origin) => {
    const operationId = 'd193d6f0-5bb3-4eb5-9c43-f9c000000002';
    const response = await fetch(`${origin}${ADMIN_BRIDGE_PATH}`, {
      method: 'POST',
      headers: { authorization: 'Bearer valid-token', 'content-type': 'application/json' },
      body: JSON.stringify({ operation: 'create', requestId: operationId,
        entityId: 'integration-bridge-fixture', data: {
          name: 'Fictional bridge fixture', category: 'Comércio',
          publicContactApproved: false, phone: '+5521999999999',
        } }),
    });
    assert.equal(response.status, 201);
    const result = await response.json();
    assert.equal(result.entityId, 'integration-bridge-fixture');
    assert.equal(result.version, 1);
    assert.deepEqual(state.tokenCalls, [{ token: 'valid-token', checkRevoked: true }]);
    const source = state.documents.get('establishments/integration-bridge-fixture');
    const event = state.documents.get(`catalog_outbox/${operationId}`);
    assert.equal(source.catalogVersion, 1);
    assert.equal(source.outboxOperationId, operationId);
    assert.equal(event.schemaVersion, 2);
    assert.equal(event.entityId, 'integration-bridge-fixture');
    assert.equal(event.state, 'pending');
    assert.equal(Object.hasOwn(event, 'phone'), false);
    assert.equal(JSON.stringify(result).includes('valid-token'), false);
  });
});

test('invalid, wrong-project, anonymous, ordinary and revoked identities fail closed without writes', async () => {
  const state = fixture();
  const handler = bridge.createLocalAdminEstablishmentsHandler({ env: localEnvironment(),
    auth: state.auth, db: state.db, fieldValue: state.fieldValue });
  await withServer(handler, async (origin) => {
    const missingToken = await fetch(`${origin}${ADMIN_BRIDGE_PATH}`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ operation: 'create', requestId: 'a193d6f0-5bb3-4eb5-9c43-f9c000000001',
        entityId: 'missing-token-fixture', data: { name: 'Denied fixture', category: 'Comércio' } }),
    });
    assert.equal(missingToken.status, 401);
    assert.equal(state.documents.has('establishments/missing-token-fixture'), false);
    for (const [token, expectedStatus] of [
      ['invalid-token', 401], ['wrong-project-token', 401],
      ['anonymous-token', 403], ['ordinary-token', 403], ['revoked-token', 401],
    ]) {
      const response = await fetch(`${origin}${ADMIN_BRIDGE_PATH}`, {
        method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        body: JSON.stringify({ operation: 'create',
          requestId: 'a193d6f0-5bb3-4eb5-9c43-f9c000000001',
          entityId: `denied-${token}`, data: { name: 'Denied fixture', category: 'Comércio' } }),
      });
      assert.equal(response.status, expectedStatus, token);
      const body = await response.text();
      assert.equal(body.includes(token), false);
      assert.equal(body.includes('sensitive SDK detail'), false);
    }
    state.documents.set('admin_authorizations/synthetic-admin-uid', {
      enabled: false, pending: false, version: 'admin-v1',
    });
    const revokedAdmin = await fetch(`${origin}${ADMIN_BRIDGE_PATH}`, {
      method: 'POST', headers: { authorization: 'Bearer valid-token', 'content-type': 'application/json' },
      body: JSON.stringify({ operation: 'create',
        requestId: 'b193d6f0-5bb3-4eb5-9c43-f9c000000001',
        entityId: 'revoked-admin-fixture', data: { name: 'Denied fixture', category: 'Comércio' } }),
    });
    assert.equal(revokedAdmin.status, 403);
    assert.equal(state.documents.has('establishments/revoked-admin-fixture'), false);
    assert.equal(state.documents.has('catalog_outbox/b193d6f0-5bb3-4eb5-9c43-f9c000000001'), false);
  });
});

test('HTTP surface is limited to the exact Flutter route, bounded JSON body, and safe preflight', async () => {
  let handlerCalls = 0;
  const serverHandler = async (request) => {
    handlerCalls++;
    if (request.method === 'OPTIONS') return new Response(null, { status: 204 });
    return new Response('{"ok":true}', { status: 200, headers: { 'content-type': 'application/json' } });
  };
  await withServer(serverHandler, async (origin) => {
    assert.equal((await fetch(`${origin}/`)).status, 404);
    assert.equal((await fetch(`${origin}${ADMIN_BRIDGE_PATH}?extra=1`, { method: 'POST' })).status, 404);
    assert.equal((await fetch(`${origin}${ADMIN_BRIDGE_PATH}`, { method: 'GET' })).status, 405);
    assert.equal((await fetch(`${origin}${ADMIN_BRIDGE_PATH}`, { method: 'OPTIONS' })).status, 204);
    const oversized = await fetch(`${origin}${ADMIN_BRIDGE_PATH}`, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: 'x'.repeat(32 * 1024 + 1),
    });
    assert.equal(oversized.status, 413);
    assert.equal(handlerCalls, 1);
  });
});

test('bridge contract matches the Flutter local test endpoint and remains opt-in', async () => {
  const [environmentSource, repositorySource, configSource] = await Promise.all([
    fs.readFile(path.resolve(__dirname, '../../lib/core/config/local_search_environment.dart'), 'utf8'),
    fs.readFile(path.resolve(__dirname, '../../lib/core/content/hybrid_admin_establishments_repository.dart'), 'utf8'),
    fs.readFile(path.resolve(__dirname, '../../firebase.search-local-admin-e2e.json'), 'utf8'),
  ]);
  assert.match(environmentSource, /adminBridgePort\s*=\s*5077/);
  assert.match(environmentSource, /adminBridgePath\s*=\s*'\/functions\/v1\/manage-establishments'/);
  assert.match(repositorySource, /const enabled = bool\.fromEnvironment\(\s*'HYBRID_ADMIN_ENABLED',\s*defaultValue:\s*false/s);
  assert.equal(bridge.ADMIN_BRIDGE_PORT, 5077);
  assert.equal(bridge.ADMIN_BRIDGE_PATH, '/functions/v1/manage-establishments');
  const config = JSON.parse(configSource);
  assert.equal(config.firestore.rules, 'firestore.hybrid-outbox-v2-candidate.rules');
  for (const [service, port] of [['auth', 9097], ['firestore', 8087], ['functions', 5007]]) {
    assert.equal(config.emulators[service].host, '127.0.0.1');
    assert.equal(config.emulators[service].port, port);
  }
  assert.equal(config.emulators.ui.enabled, false);
  assert.equal(Object.hasOwn(config, 'import'), false);
  assert.equal(Object.hasOwn(config, 'export'), false);
});

test('failed Firestore transaction leaves neither the canonical document nor outbox event', async () => {
  const operationId = 'c193d6f0-5bb3-4eb5-9c43-f9c000000001';
  const { db, documents } = createFakeFirestore({
    'admin_authorizations/synthetic-admin-uid': { enabled: true, pending: false, version: 'admin-v1' },
  }, { failOnCreate: `catalog_outbox/${operationId}` });
  const state = fixture();
  const handler = bridge.createLocalAdminEstablishmentsHandler({ env: localEnvironment(),
    auth: state.auth, db, fieldValue: state.fieldValue });
  const response = await handler(new Request(`http://127.0.0.1${ADMIN_BRIDGE_PATH}`, {
    method: 'POST', headers: { authorization: 'Bearer valid-token', 'content-type': 'application/json' },
    body: JSON.stringify({ operation: 'create', requestId: operationId,
      entityId: 'atomic-failure-fixture', data: { name: 'Atomic fixture', category: 'Comércio' } }),
  }));
  assert.equal(response.status, 503);
  assert.equal(documents.has('establishments/atomic-failure-fixture'), false);
  assert.equal(documents.has(`catalog_outbox/${operationId}`), false);
});
