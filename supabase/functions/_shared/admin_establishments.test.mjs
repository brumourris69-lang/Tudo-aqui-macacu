import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createAdminEstablishmentsHandler } from './admin_establishments.mjs';
import { authorizeAdmin } from './admin_authorization.mjs';

const SUPABASE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const PROJECT_ID = 'tudo-aqui-macacu';
const ADMIN_UID = 'verified-admin-uid';
const REQUEST_ID = '11111111-1111-4111-8111-111111111111';
const ENTITY_ID = 'establishment-1';
const IDENTITY = Object.freeze({ uid: ADMIN_UID, authTime: 1_797_000_000, isAnonymous: false, provider: 'password' });
const AUTHORIZATION = Object.freeze({ enabled: true, pending: false, version: 'admin-v4' });

function makeRequest(body, token = 'firebase-token-sentinel') {
  return new Request('https://edge.invalid/manage-establishments', {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

function createStore(initial = {}) {
  const documents = new Map(Object.entries(initial));
  const commits = [];
  let updateTime = 1;
  let queue = Promise.resolve();

  return {
    documents,
    commits,
    async runTransaction(callback) {
      const snapshot = new Map(documents);
      const writes = [];
      const tx = {
        async get(collection, id) {
          const key = `${collection}/${id}`;
          const stored = snapshot.get(key);
          return stored ? structuredClone(stored) : null;
        },
        create(collection, id, data, options = {}) {
          writes.push({ kind: 'create', collection, id, data: structuredClone(data), options });
        },
        update(collection, id, data, options = {}) {
          writes.push({ kind: 'update', collection, id, data: structuredClone(data), options });
        },
      };
      const result = await callback(tx);
      if (writes.length === 0) return result;

      let release;
      const previousQueue = queue;
      queue = new Promise((resolve) => { release = resolve; });
      await previousQueue;
      try {
        const next = new Map(documents);
        for (const write of writes) {
          const key = `${write.collection}/${write.id}`;
          const current = next.get(key);
          if (write.kind === 'create' && current) throw Object.assign(new Error('conflict'), { code: 'conflict' });
          if (write.kind === 'update' && (!current || current.updateTime !== write.options.updateTime)) {
            throw Object.assign(new Error('conflict'), { code: 'conflict' });
          }
          const data = write.kind === 'create'
            ? { ...write.data }
            : { ...current.data, ...write.data };
          for (const field of write.options.deleteFields ?? []) delete data[field];
          const timestamp = new Date(updateTime++).toISOString();
          for (const field of write.options.serverTimestampFields ?? []) data[field] = timestamp;
          next.set(key, { data, updateTime: timestamp });
        }
        documents.clear();
        for (const [key, value] of next) documents.set(key, value);
        commits.push(writes);
      } finally {
        release();
      }
      return result;
    },
  };
}

function fixture(options = {}) {
  const store = options.store ?? createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
  });
  const calls = { verified: [], authorizationReads: [], logs: [] };
  const handler = createAdminEstablishmentsHandler({
    projectId: PROJECT_ID,
    store,
    uuid: options.uuid ?? (() => '22222222-2222-4222-8222-222222222222'),
    verifyIdentity: async (token, projectId) => {
      calls.verified.push({ token, projectId });
      if (options.verifyError) throw options.verifyError;
      return options.identity ?? IDENTITY;
    },
    authorizeAdmin: async (identity, readAuthorization) => {
      calls.authorizationReads.push(identity.uid);
      return authorizeAdmin(identity, readAuthorization);
    },
    log: (...values) => calls.logs.push(values),
  });
  return { handler, store, calls };
}

const validData = Object.freeze({
  title: 'Café Exemplo',
  description: 'Descrição pública de demonstração.',
  category: 'Onde comer?',
  subcategory: 'Cafeteria',
  imageUrl: 'https://images.example.test/cafe.jpg',
  published: true,
  active: true,
  phone: '+5521999999999',
  whatsapp: 'https://wa.me/5521999999999',
  publicContactApproved: false,
});

test('requires a verified Firebase bearer identity before opening a transaction', async () => {
  const { handler, store } = fixture();
  const response = await handler(new Request('https://edge.invalid', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}',
  }));
  assert.equal(response.status, 401);
  assert.equal(store.commits.length, 0);
});

test('cancels an oversized request body while streaming instead of buffering it all', async () => {
  let cancelled = false;
  const body = new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array(40 * 1024)); },
    cancel() { cancelled = true; },
  });
  const request = {
    method: 'POST',
    headers: new Headers({ authorization: 'Bearer firebase-token-sentinel', 'content-type': 'application/json' }),
    body,
  };
  const { handler } = fixture();
  const response = await handler(request);
  assert.equal(response.status, 400);
  assert.equal(cancelled, true);
});

test('disables Supabase JWT gateway verification only for this Firebase-token function', async () => {
  const config = await readFile(path.join(SUPABASE_ROOT, 'config.toml'), 'utf8');
  assert.match(config, /\[functions\.manage-establishments\]\s*\nverify_jwt\s*=\s*false/iu);
  assert.doesNotMatch(config, /^\[functions\]\s*$/imu,
    'no global Functions gateway override is present');
});

test('creates the canonical establishment and server-owned outbox event atomically', async () => {
  const { handler, store, calls } = fixture();
  const response = await handler(makeRequest({ operation: 'create', requestId: REQUEST_ID, data: validData }));
  const body = await response.json();
  assert.equal(response.status, 201);
  assert.equal(body.result, 'created');
  assert.equal(body.entityId, '22222222-2222-4222-8222-222222222222');
  assert.equal(body.version, 1);
  assert.deepEqual(calls.verified, [{ token: 'firebase-token-sentinel', projectId: PROJECT_ID }]);
  assert.equal(calls.authorizationReads[0], ADMIN_UID);
  assert.equal(store.commits.length, 1);
  assert.equal(store.commits[0].length, 2);
  const [sourceWrite, outboxWrite] = store.commits[0];
  assert.equal(sourceWrite.collection, 'establishments');
  assert.equal(sourceWrite.data.catalogVersion, 1);
  assert.equal(sourceWrite.data.outboxOperationId, REQUEST_ID);
  assert.equal(outboxWrite.collection, 'catalog_outbox');
  assert.equal(outboxWrite.id, REQUEST_ID);
  assert.equal(outboxWrite.data.state, 'pending');
  assert.equal(outboxWrite.data.operation, 'reconcile');
  assert.equal(outboxWrite.data.authorUid, ADMIN_UID);
  assert.deepEqual(outboxWrite.data, {
    schemaVersion: 2,
    operationId: REQUEST_ID,
    entityType: 'establishment',
    entityId: body.entityId,
    authorUid: ADMIN_UID,
    version: 1,
    operation: 'reconcile',
    state: 'pending',
    attemptCount: 0,
    workerId: null,
    leaseToken: null,
    leaseExpiresAt: null,
    nextAttemptAt: null,
    lastErrorCode: null,
    syncedAt: null,
  });
  assert.deepEqual(outboxWrite.options.serverTimestampFields, ['createdAt', 'updatedAt']);
  assert.equal(outboxWrite.data.phone, undefined);
});

test('creates legacy fixture IDs explicitly for the initial content importer', async () => {
  const { handler, store } = fixture();
  const response = await handler(makeRequest({
    operation: 'create', requestId: REQUEST_ID, entityId: 'modelo-1', data: validData,
  }));
  const body = await response.json();
  assert.equal(response.status, 201);
  assert.equal(body.entityId, 'modelo-1');
  assert.equal(store.commits.length, 1);
  assert.equal(store.commits[0][0].id, 'modelo-1');
  assert.equal(store.commits[0][1].data.entityId, 'modelo-1');

  const replay = await handler(makeRequest({
    operation: 'create', requestId: REQUEST_ID, entityId: 'different-id', data: validData,
  }));
  assert.deepEqual(await replay.json(), {
    result: 'replayed', operationId: REQUEST_ID, entityId: 'modelo-1', version: 1, replayed: true,
  });
  assert.equal(store.commits.length, 1);

  const invalid = await handler(makeRequest({
    operation: 'create', requestId: '33333333-3333-4333-8333-333333333333',
    entityId: 'unsafe/id', data: validData,
  }));
  assert.equal(invalid.status, 400);
  assert.equal(store.commits.length, 1);
});

test('preserves Firestore document IDs without pilot-only ASCII restrictions', async () => {
  const { handler, store } = fixture();
  const entityId = 'modelo-café-2026';
  const response = await handler(makeRequest({
    operation: 'create',
    requestId: '55555555-5555-4555-8555-555555555555',
    entityId,
    data: validData,
  }));

  assert.equal(response.status, 201);
  assert.equal((await response.json()).entityId, entityId);
  assert.equal(store.documents.has(`establishments/${entityId}`), true);

  for (const invalidId of ['.', '..', 'unsafe/id', '__reserved__', 'x'.repeat(1501)]) {
    const invalid = await handler(makeRequest({
      operation: 'create',
      requestId: crypto.randomUUID(),
      entityId: invalidId,
      data: validData,
    }));
    assert.equal(invalid.status, 400, `reject invalid Firestore document ID: ${invalidId.length}`);
  }
});

test('republishes an unpublished establishment with its edited fields atomically', async () => {
  const initial = {
    [`establishments/${ENTITY_ID}`]: {
      data: {
        title: 'Nome anterior',
        published: false,
        active: false,
        catalogVersion: 4,
      },
      updateTime: 'source-v4',
    },
  };
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    ...initial,
  });
  const { handler } = fixture({ store });

  const response = await handler(makeRequest({
    operation: 'republish',
    requestId: '44444444-4444-4444-8444-444444444444',
    entityId: ENTITY_ID,
    expectedVersion: 4,
    data: { title: 'Nome atualizado', category: 'Comércio', published: true },
  }));
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.result, 'republished');
  assert.equal(body.version, 5);
  const source = store.documents.get(`establishments/${ENTITY_ID}`).data;
  assert.equal(source.title, 'Nome atualizado');
  assert.equal(source.published, true);
  assert.equal(source.active, true);
  assert.equal(source.catalogVersion, 5);
  assert.equal(source.outboxOperationId, '44444444-4444-4444-8444-444444444444');
  assert.equal(store.commits[0].length, 2);
  assert.equal(store.commits[0][1].collection, 'catalog_outbox');
});

test('rejects anonymous, unverified, mismatched-project identities and invalid authorization without writes', async () => {
  for (const scenario of [
    { verifyError: Object.assign(new Error('invalid'), { code: 'wrong-project' }), expected: 401 },
    { identity: { ...IDENTITY, isAnonymous: true }, expected: 403 },
    { authState: null, expected: 403 },
    { authState: { enabled: true, pending: true, version: 'v1' }, expected: 403 },
    { authState: { enabled: false, pending: false, version: 'v1' }, expected: 403 },
    { authState: { enabled: true, pending: false, revoked: true, version: 'v1' }, expected: 403 },
    { authState: { enabled: true, pending: false, version: '' }, expected: 403 },
  ]) {
    const initial = scenario.authState === undefined
      ? { [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' } }
      : (scenario.authState === null ? {} : {
        [`admin_authorizations/${ADMIN_UID}`]: { data: scenario.authState, updateTime: 'auth-v1' },
      });
    const store = createStore(initial);
    const { handler } = fixture({ ...scenario, store });
    const response = await handler(makeRequest({ operation: 'create', requestId: REQUEST_ID, data: validData }));
    assert.equal(response.status, scenario.expected);
    assert.equal(store.commits.length, 0);
  }
});

test('fails closed when the trusted authorization read is unavailable', async () => {
  let writes = 0;
  const store = { async runTransaction(callback) {
    return callback({
      async get() { throw new Error('private Firestore outage detail'); },
      create() { writes += 1; },
      update() { writes += 1; },
    });
  } };
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({ operation: 'create', requestId: REQUEST_ID, data: validData }));
  const body = await response.text();
  assert.equal(response.status, 503);
  assert.equal(body.includes('private Firestore'), false);
  assert.equal(writes, 0);
});

test('update increments the monotonic version and preserves unknown legacy fields', async () => {
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${ENTITY_ID}`]: {
      data: { name: 'Antes', title: 'Antes', category: 'Comércio', catalogVersion: 4, privateLegacy: 'keep' },
      updateTime: 'source-v4',
    },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({
    operation: 'update', requestId: REQUEST_ID, entityId: ENTITY_ID, expectedVersion: 4,
    data: { title: 'Depois', description: 'Nova descrição' },
  }));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).version, 5);
  const source = store.documents.get(`establishments/${ENTITY_ID}`).data;
  assert.equal(source.title, 'Depois');
  assert.equal(source.name, 'Depois');
  assert.equal(source.privateLegacy, 'keep');
  assert.equal(source.catalogVersion, 5);
});

test('first authorized update migrates an unversioned legacy record atomically', async () => {
  const legacyId = 'modelo-legado-sem-versao';
  const legacyOperationId = '33333333-3333-4333-8333-333333333333';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${legacyId}`]: {
      data: { title: 'Cadastro antigo', category: 'Comércio', privateLegacy: 'preserved' },
      updateTime: 'legacy-source-v0',
    },
  });
  const { handler } = fixture({ store });

  const response = await handler(makeRequest({
    operation: 'update', requestId: legacyOperationId, entityId: legacyId,
    expectedVersion: 0, data: { title: 'Cadastro migrado' },
  }));

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    result: 'updated', operationId: legacyOperationId, entityId: legacyId,
    version: 1, replayed: false,
  });
  assert.equal(store.commits.length, 1);
  assert.equal(store.commits[0].length, 2);
  const [sourceWrite, outboxWrite] = store.commits[0];
  assert.equal(sourceWrite.collection, 'establishments');
  assert.equal(sourceWrite.id, legacyId);
  assert.equal(sourceWrite.options.updateTime, 'legacy-source-v0');
  assert.equal(sourceWrite.data.catalogVersion, 1);
  assert.equal(sourceWrite.data.outboxOperationId, legacyOperationId);
  assert.equal(store.documents.get(`establishments/${legacyId}`).data.privateLegacy, 'preserved');
  assert.equal(outboxWrite.collection, 'catalog_outbox');
  assert.equal(outboxWrite.id, legacyOperationId);
  assert.equal(outboxWrite.data.entityId, legacyId);
  assert.equal(outboxWrite.data.version, 1);
  assert.equal(outboxWrite.data.schemaVersion, 2);
});

test('clears an optional expiry by deleting the Firestore field rather than storing null', async () => {
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${ENTITY_ID}`]: {
      data: { name: 'Com validade', category: 'Comércio', expiresAt: '2026-12-31T23:59:59.000Z', catalogVersion: 1 },
      updateTime: 'source-v1',
    },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({
    operation: 'update', requestId: REQUEST_ID, entityId: ENTITY_ID, expectedVersion: 1,
    data: { expiresAt: null },
  }));
  assert.equal(response.status, 200);
  const source = store.documents.get(`establishments/${ENTITY_ID}`).data;
  assert.equal(Object.hasOwn(source, 'expiresAt'), false);
  assert.equal(source.catalogVersion, 2);
});

test('rejects stale versions and logical deletion without a version precondition', async () => {
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${ENTITY_ID}`]: { data: { name: 'Atual', catalogVersion: 3 }, updateTime: 'source-v3' },
  });
  const { handler } = fixture({ store });
  const stale = await handler(makeRequest({
    operation: 'update', requestId: REQUEST_ID, entityId: ENTITY_ID, expectedVersion: 2,
    data: { description: 'Não deve salvar' },
  }));
  assert.equal(stale.status, 409);
  const deleteWithoutVersion = await handler(makeRequest({ operation: 'delete',
    requestId: '33333333-3333-4333-8333-333333333333', entityId: ENTITY_ID }));
  assert.equal(deleteWithoutVersion.status, 400);
  assert.equal(store.commits.length, 0);
  assert.equal(store.documents.get(`establishments/${ENTITY_ID}`).data.catalogVersion, 3);
});

test('unpublish is reversible and never writes the logical-deletion timestamp', async () => {
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${ENTITY_ID}`]: { data: { name: 'Ativo', published: true, active: true, catalogVersion: 1 }, updateTime: 'source-v1' },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({
    operation: 'unpublish', requestId: REQUEST_ID, entityId: ENTITY_ID, expectedVersion: 1,
  }));
  assert.equal(response.status, 200);
  const source = store.documents.get(`establishments/${ENTITY_ID}`).data;
  assert.equal(source.published, false);
  assert.equal(source.active, false);
  assert.equal(Object.hasOwn(source, 'deletedAt'), false);
  assert.equal(source.catalogVersion, 2);
  assert.equal(store.documents.has(`establishments/${ENTITY_ID}`), true);
  assert.equal(store.commits[0].length, 2);
  assert.deepEqual(store.commits[0][0].options.serverTimestampFields, ['updatedAt']);
  assert.equal(store.commits[0][1].data.version, 2);
});

test('republish preserves the original ID and atomically creates a fresh versioned outbox event', async () => {
  const legacyId = 'modelo-estabelecimento-123';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${legacyId}`]: {
      data: { name: 'Despublicado', published: false, active: false, deletedAt: null,
        catalogVersion: 8, outboxOperationId: 'old-operation-id' },
      updateTime: 'source-v8',
    },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({ operation: 'republish', requestId: REQUEST_ID,
    entityId: legacyId, expectedVersion: 8 }));
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.result, 'republished');
  assert.equal(body.entityId, legacyId);
  assert.equal(body.version, 9);
  assert.equal(store.commits.length, 1);
  assert.equal(store.commits[0].length, 2);
  const [sourceWrite, outboxWrite] = store.commits[0];
  assert.equal(sourceWrite.collection, 'establishments');
  assert.equal(sourceWrite.id, legacyId);
  assert.deepEqual(sourceWrite.data, { published: true, active: true,
    catalogVersion: 9, outboxOperationId: REQUEST_ID });
  assert.deepEqual(sourceWrite.options.serverTimestampFields, ['updatedAt']);
  assert.equal(outboxWrite.collection, 'catalog_outbox');
  assert.equal(outboxWrite.id, REQUEST_ID);
  assert.equal(outboxWrite.data.entityId, legacyId);
  assert.equal(outboxWrite.data.version, 9);
  assert.equal(outboxWrite.data.operationId, REQUEST_ID);
  assert.equal(outboxWrite.data.state, 'pending');
  assert.deepEqual(Object.keys(body).sort(), [
    'entityId', 'operationId', 'replayed', 'result', 'version',
  ].sort());
});

test('republish rejects logical deletions without changing source or outbox', async () => {
  const tombstoned = 'modelo-ja-excluido-456';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${tombstoned}`]: { data: { name: 'Excluído', published: false,
      active: false, deletedAt: '2026-10-19T12:00:00.000Z', catalogVersion: 4 }, updateTime: 'source-v4' },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({ operation: 'republish', requestId: REQUEST_ID,
    entityId: tombstoned, expectedVersion: 4 }));

  assert.equal(response.status, 409);
  assert.equal(store.commits.length, 0);
  assert.equal(store.documents.get(`establishments/${tombstoned}`).data.catalogVersion, 4);
  assert.equal(store.documents.has(`catalog_outbox/${REQUEST_ID}`), false);
});

test('republish requires current Admin authorization and writes nothing when denied', async () => {
  const legacyId = 'modelo-sem-admin-789';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: { enabled: true, pending: true,
      version: 'admin-v4' }, updateTime: 'auth-v2' },
    [`establishments/${legacyId}`]: { data: { published: false, active: false,
      deletedAt: null, catalogVersion: 2 }, updateTime: 'source-v2' },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({ operation: 'republish', requestId: REQUEST_ID,
    entityId: legacyId, expectedVersion: 2 }));

  assert.equal(response.status, 403);
  assert.equal(store.commits.length, 0);
  assert.equal(store.documents.get(`establishments/${legacyId}`).data.published, false);
});

test('update cannot bypass the explicit republish operation', async () => {
  const legacyId = 'modelo-republish-required-001';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${legacyId}`]: { data: { published: false, active: false,
      deletedAt: null, catalogVersion: 3 }, updateTime: 'source-v3' },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({ operation: 'update', requestId: REQUEST_ID,
    entityId: legacyId, expectedVersion: 3, data: { published: true, active: true } }));

  assert.equal(response.status, 409);
  assert.equal(store.commits.length, 0);
  assert.equal(store.documents.get(`establishments/${legacyId}`).data.published, false);
});

test('unpublish followed by republish keeps one canonical ID and advances each outbox version', async () => {
  const legacyId = 'modelo-catalogo-legado-001';
  const secondRequestId = '33333333-3333-4333-8333-333333333333';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${legacyId}`]: { data: { name: 'Legado', published: true,
      active: true, deletedAt: null, catalogVersion: 20 }, updateTime: 'source-v20' },
  });
  const { handler } = fixture({ store });
  const unpublish = await handler(makeRequest({ operation: 'unpublish', requestId: REQUEST_ID,
    entityId: legacyId, expectedVersion: 20 }));
  const republish = await handler(makeRequest({ operation: 'republish', requestId: secondRequestId,
    entityId: legacyId, expectedVersion: 21 }));

  assert.equal(unpublish.status, 200);
  assert.equal(republish.status, 200);
  assert.equal((await unpublish.json()).version, 21);
  assert.equal((await republish.json()).version, 22);
  const source = store.documents.get(`establishments/${legacyId}`).data;
  assert.equal(source.published, true);
  assert.equal(source.active, true);
  assert.equal(source.deletedAt, null);
  assert.equal(source.catalogVersion, 22);
  assert.equal(source.outboxOperationId, secondRequestId);
  assert.equal(store.documents.has(`establishments/${ENTITY_ID}`), false);
  assert.equal(store.commits.length, 2);
  assert.deepEqual(store.commits.map((writes) => writes.map((write) => write.collection)), [
    ['establishments', 'catalog_outbox'],
    ['establishments', 'catalog_outbox'],
  ]);
  assert.deepEqual(store.commits.map((writes) => writes[1].data.version), [21, 22]);
});

test('logical delete writes a permanent timestamp tombstone and a versioned outbox pair', async () => {
  const legacyId = 'modelo-logical-delete-legacy';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${legacyId}`]: { data: { name: 'Legado', published: true,
      active: true, deletedAt: null, catalogVersion: 8 }, updateTime: 'source-v8' },
  });
  const { handler } = fixture({ store });
  const response = await handler(makeRequest({ operation: 'delete', requestId: REQUEST_ID,
    entityId: legacyId, expectedVersion: 8 }));

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    result: 'deleted', operationId: REQUEST_ID, entityId: legacyId, version: 9, replayed: false,
  });
  const source = store.documents.get(`establishments/${legacyId}`).data;
  const outbox = store.documents.get(`catalog_outbox/${REQUEST_ID}`).data;
  assert.equal(source.deletedAt, '1970-01-01T00:00:00.001Z');
  assert.equal(source.published, false);
  assert.equal(source.active, false);
  assert.equal(source.catalogVersion, 9);
  assert.equal(source.outboxOperationId, REQUEST_ID);
  assert.equal(outbox.entityId, legacyId);
  assert.equal(outbox.version, 9);
  assert.equal(store.commits.length, 1);
  assert.deepEqual(store.commits[0].map((write) => write.collection), [
    'establishments', 'catalog_outbox',
  ]);
});

test('logical delete is replay-safe and prevents later update or republish', async () => {
  const legacyId = 'modelo-logical-delete-locked';
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${legacyId}`]: { data: { name: 'Legado', published: true,
      active: true, deletedAt: null, catalogVersion: 3 }, updateTime: 'source-v3' },
  });
  const { handler } = fixture({ store });
  const request = { operation: 'delete', requestId: REQUEST_ID, entityId: legacyId, expectedVersion: 3 };
  const first = await handler(makeRequest(request));
  const replay = await handler(makeRequest(request));
  assert.equal(first.status, 200);
  assert.equal((await replay.json()).replayed, true);
  assert.equal(store.commits.length, 1);

  const update = await handler(makeRequest({ operation: 'update', requestId: '33333333-3333-4333-8333-333333333333',
    entityId: legacyId, expectedVersion: 4, data: { title: 'Ressuscitar' } }));
  const republish = await handler(makeRequest({ operation: 'republish', requestId: '44444444-4444-4444-8444-444444444444',
    entityId: legacyId, expectedVersion: 4 }));
  assert.equal(update.status, 409);
  assert.equal(republish.status, 409);
  assert.equal(store.commits.length, 1);
});

test('request replay returns the prior result and does not duplicate the outbox event', async () => {
  const { handler, store } = fixture();
  const request = { operation: 'create', requestId: REQUEST_ID, data: validData };
  const first = await handler(makeRequest(request));
  assert.equal(first.status, 201);
  const second = await handler(makeRequest(request));
  const response = await second.json();
  assert.equal(second.status, 200);
  assert.equal(response.replayed, true);
  assert.equal(response.entityId, '22222222-2222-4222-8222-222222222222');
  assert.equal(store.commits.length, 1);
});

test('a legacy schemaVersion 1 outbox event remains replayable without lifecycle fields', async () => {
  const legacyEvent = {
    schemaVersion: 1,
    operationId: REQUEST_ID,
    entityType: 'establishment',
    entityId: ENTITY_ID,
    authorUid: ADMIN_UID,
    version: 7,
    operation: 'reconcile',
    state: 'pending',
    attemptCount: 0,
  };
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`catalog_outbox/${REQUEST_ID}`]: { data: legacyEvent, updateTime: 'outbox-v1' },
  });
  const { handler } = fixture({ store });

  const response = await handler(makeRequest({ operation: 'create', requestId: REQUEST_ID, data: validData }));
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.replayed, true);
  assert.equal(body.entityId, ENTITY_ID);
  assert.equal(body.version, 7);
  assert.equal(store.commits.length, 0);
});

test('schemaVersion 2 replay requires all lifecycle fields to be present', async () => {
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`catalog_outbox/${REQUEST_ID}`]: {
      data: {
        schemaVersion: 2, operationId: REQUEST_ID, entityType: 'establishment', entityId: ENTITY_ID,
        authorUid: ADMIN_UID, version: 7, operation: 'reconcile', state: 'pending', attemptCount: 0,
        workerId: null, leaseToken: null, leaseExpiresAt: null, nextAttemptAt: null,
        lastErrorCode: null, // syncedAt deliberately absent
      },
      updateTime: 'outbox-v2-incomplete',
    },
  });
  const { handler } = fixture({ store });

  const response = await handler(makeRequest({ operation: 'create', requestId: REQUEST_ID, data: validData }));
  assert.equal(response.status, 409);
  assert.equal(store.commits.length, 0);
});

test('two concurrent updates with the same version cannot both commit', async () => {
  const store = createStore({
    [`admin_authorizations/${ADMIN_UID}`]: { data: AUTHORIZATION, updateTime: 'auth-v1' },
    [`establishments/${ENTITY_ID}`]: { data: { name: 'Antes', catalogVersion: 1 }, updateTime: 'source-v1' },
  });
  const { handler } = fixture({ store });
  const send = (requestId, title) => handler(makeRequest({
    operation: 'update', requestId, entityId: ENTITY_ID, expectedVersion: 1, data: { title },
  }));
  const results = await Promise.all([
    send(REQUEST_ID, 'Um'),
    send('33333333-3333-4333-8333-333333333333', 'Dois'),
  ]);
  assert.deepEqual(results.map((response) => response.status).sort(), [200, 409]);
  assert.equal(store.commits.length, 1);
});

test('strict request validation and safe projection exclude private and unknown fields', async () => {
  const { handler, store } = fixture();
  const invalid = await handler(makeRequest({
    operation: 'create', requestId: REQUEST_ID,
    data: { ...validData, serviceAccountKey: 'secret-sentinel' },
  }));
  assert.equal(invalid.status, 400);
  assert.equal(store.commits.length, 0);
  const spoofedIdentity = await handler(makeRequest({
    operation: 'create', requestId: REQUEST_ID, uid: ADMIN_UID, data: validData,
  }));
  assert.equal(spoofedIdentity.status, 400);
  assert.equal(store.commits.length, 0);
  const unsafeContact = await handler(makeRequest({
    operation: 'create', requestId: REQUEST_ID,
    data: { ...validData, whatsapp: 'javascript:alert(1)' },
  }));
  assert.equal(unsafeContact.status, 400);
  assert.equal(store.commits.length, 0);

  const { projectPublicEstablishment } = await import('./admin_establishments.mjs');
  const projection = projectPublicEstablishment('pilot-demo-1', {
    name: 'Café', description: 'Resumo', category: 'Onde comer?', subcategory: 'Café',
    imageUrl: 'https://images.example.test/a.png', published: true, active: true,
    phone: '+5521999999999', whatsapp: 'private-contact', ownerEmail: 'private@example.test',
    catalogVersion: 8, outboxOperationId: 'internal-operation-id',
    deletedAt: null, adminNote: 'private-admin-sentinel', unknownPrivate: 'secret-sentinel',
  });
  assert.deepEqual(Object.keys(projection).sort(), [
    'active', 'category', 'deleted_at', 'expires_at', 'id', 'image_url', 'name',
    'published', 'subcategory', 'summary',
  ].sort());
  assert.equal(JSON.stringify(projection).includes('secret-sentinel'), false);
  assert.equal(JSON.stringify(projection).includes('private@example.test'), false);
  assert.equal(JSON.stringify(projection).includes('internal-operation-id'), false);
  assert.equal(JSON.stringify(projection).includes('private-admin-sentinel'), false);
  assert.equal(projectPublicEstablishment('legacy-firestore-auto-id', {
    name: 'Legado', category: 'Comércio', published: true, active: true,
  }).id, 'legacy-firestore-auto-id', 'Firestore IDs are preserved without pilot-only remapping');
});

test('rejects impossible ISO expiry dates instead of normalizing them into another month', async () => {
  const { handler, store } = fixture();
  const response = await handler(makeRequest({
    operation: 'create', requestId: REQUEST_ID,
    data: { ...validData, expiresAt: '2026-02-30T12:00:00Z' },
  }));
  assert.equal(response.status, 400);
  assert.equal(store.commits.length, 0);
});

test('transaction failures are sanitized and never produce partial writes', async () => {
  const store = {
    commits: [],
    async runTransaction() { throw new Error('sensitive Firestore response body sentinel'); },
  };
  const { handler, calls } = fixture({ store });
  const response = await handler(makeRequest({ operation: 'create', requestId: REQUEST_ID, data: validData }));
  const body = await response.text();
  assert.equal(response.status, 503);
  assert.equal(body.includes('sentinel'), false);
  assert.equal(body.includes(ADMIN_UID), false);
  assert.equal(body.includes('firebase-token-sentinel'), false);
  assert.equal(calls.logs.length, 0);
});

test('does not log bearer tokens or raw verifier exceptions', async () => {
  const methods = ['debug', 'info', 'log', 'warn', 'error'];
  const original = Object.fromEntries(methods.map((method) => [method, console[method]]));
  const output = [];
  for (const method of methods) console[method] = (...values) => output.push(values.join(' '));
  try {
    const { handler } = fixture({ verifyError: new Error('raw token parser detail sentinel') });
    const response = await handler(makeRequest({ operation: 'create', requestId: REQUEST_ID, data: validData }));
    assert.equal(response.status, 401);
  } finally {
    for (const method of methods) console[method] = original[method];
  }
  assert.deepEqual(output, []);
  assert.equal(output.join(' ').includes('sentinel'), false);
});
