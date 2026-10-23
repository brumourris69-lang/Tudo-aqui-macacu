import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { authorizeAdmin } from './admin_authorization.mjs';
import { createAdminEstablishmentsHandler } from './admin_establishments.mjs';
import { createCatalogOutboxProcessor } from './catalog_outbox_processor.mjs';
import { createCatalogOutboxConsumerHandler } from './catalog_outbox_consumer.mjs';
import { projectCanonicalEstablishment } from './catalog_outbox_protocol.mjs';
import { createFirebaseFirestoreRestStore, FirestoreRestError } from './firebase_firestore_rest.mjs';
import { createSupabaseCatalogRpcRestClient } from './supabase_catalog_rpc_rest.mjs';
import { createSupabaseCatalogWriterV2 } from './supabase_catalog_writer_v2.mjs';

const projectId = 'demo-universal-search';
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const containerName = process.env.CATALOG_POSTGRES_TEST_CONTAINER;
const postgrestContainerName = process.env.CATALOG_POSTGREST_TEST_CONTAINER;
const postgrestUrl = process.env.CATALOG_POSTGREST_URL;
const postgrestApiKey = process.env.CATALOG_POSTGREST_API_KEY;
const postgresImage = 'public.ecr.aws/supabase/postgres:15.19.0.004';
const postgrestImage = 'postgrest/postgrest:v14.18';

test('Firestore Emulator processor persists a public projection through disposable PostgreSQL', {
  skip: !emulatorHost || !containerName
    ? 'Set FIRESTORE_EMULATOR_HOST and CATALOG_POSTGRES_TEST_CONTAINER for local integration only.'
    : false,
}, async () => {
  const address = parseLoopback(emulatorHost);
  assert.ok(address, 'Firestore Emulator must use loopback');
  assert.match(containerName, /^macacu-0755-pg-[a-z0-9-]+$/u, 'only the named disposable test container is allowed');
  const usePostgrest = postgrestUrl !== undefined || postgrestApiKey !== undefined || postgrestContainerName !== undefined;
  let parsedPostgrestUrl;
  if (usePostgrest) {
    assert.equal(typeof postgrestUrl, 'string');
    assert.equal(typeof postgrestApiKey, 'string');
    assert.equal(typeof postgrestContainerName, 'string');
    assert.match(postgrestContainerName, /^macacu-0755-rest-[a-z0-9-]+$/u,
      'only the named disposable PostgREST container is allowed');
    parsedPostgrestUrl = new URL(postgrestUrl);
    assert.equal(parsedPostgrestUrl.protocol, 'http:');
    assert.ok(['127.0.0.1', '[::1]', 'localhost'].includes(parsedPostgrestUrl.hostname),
      'PostgREST HTTP integration must use loopback');
    assert.equal(parsedPostgrestUrl.username, '');
    assert.equal(parsedPostgrestUrl.password, '');
    assert.equal(parsedPostgrestUrl.pathname, '/');
    assert.equal(parsedPostgrestUrl.search, '');
    assert.equal(parsedPostgrestUrl.hash, '');
    assert.ok(postgrestApiKey.length >= 32, 'integration key must be synthetic and locally provisioned');
  } else {
    assert.equal(postgrestUrl, undefined);
    assert.equal(postgrestApiKey, undefined);
    assert.equal(postgrestContainerName, undefined);
  }

  const inspection = await inspectContainer(containerName);
  assert.equal(inspection.State.Running, true);
  assert.equal(inspection.Config.Image, postgresImage);
  assert.equal(inspection.Config.Labels?.['codex.task'], 'macacu-0755-local-validation');
  assert.deepEqual(inspection.HostConfig.PortBindings ?? {}, {});
  if (usePostgrest) {
    assert.match(inspection.HostConfig.NetworkMode, /^macacu-0755-rest-[a-z0-9-]+$/u);
    assert.ok(inspection.Mounts.length >= 1);
  } else {
    assert.equal(inspection.HostConfig.NetworkMode, 'none');
    assert.ok(Object.values(inspection.NetworkSettings.Ports ?? {}).every((bindings) => bindings === null));
    assert.ok(inspection.Mounts.length >= 2);
  }
  assert.ok(inspection.Mounts.every((mount) => mount.RW === false));

  if (usePostgrest) {
    const restInspection = await inspectContainer(postgrestContainerName);
    assert.equal(restInspection.State.Running, true);
    assert.equal(restInspection.Config.Image, postgrestImage);
    assert.equal(restInspection.Config.Labels?.['codex.task'], 'macacu-0755-local-validation');
    assert.deepEqual(restInspection.Mounts, []);
    const bindings = restInspection.HostConfig.PortBindings?.['3000/tcp'] ?? [];
    assert.equal(bindings.length, 1);
    assert.equal(bindings[0].HostIp, '127.0.0.1');
    assert.equal(Number(bindings[0].HostPort), Number(parsedPostgrestUrl.port));
    assert.deepEqual(Object.keys(restInspection.NetworkSettings.Networks ?? {}), [inspection.HostConfig.NetworkMode]);
  }

  const store = createFirebaseFirestoreRestStore({
    projectId,
    emulator: { host: address.host, port: address.port },
  });
  const rpc = usePostgrest
    ? createSupabaseCatalogRpcRestClient({ url: postgrestUrl, apiKey: postgrestApiKey, restPathPrefix: '' })
    : createPsqlRpc(containerName);
  const writer = createSupabaseCatalogWriterV2({ rpc });
  const id = `e2e-${randomUUID()}`;
  const operationId = randomUUID();
  const canonical = canonicalDocument(operationId, 1, 'PostgreSQL integration fixture v1');
  const event = outboxEvent(operationId, id, 1);

  await store.runTransaction(async (transaction) => {
    transaction.create('establishments', id, canonical, { serverTimestampFields: ['createdAt', 'updatedAt'] });
    transaction.create('catalog_outbox', operationId, event, { serverTimestampFields: ['createdAt', 'updatedAt'] });
  });

  // The Firestore adapter pins the first query readTime five seconds in the past.
  await delay(5_200);
  const processor = createProcessor({ store, rpc });
  const triggerSecret = 'synthetic-only-consumer-secret-with-at-least-32-bytes';
  const triggerTimestamp = Math.floor(Date.now() / 1_000);
  const triggerSignature = createHmac('sha256', triggerSecret)
    .update(`catalog-outbox-consumer-v1\nPOST\n/consume\n${triggerTimestamp}`, 'utf8').digest('base64url');
  const trigger = createCatalogOutboxConsumerHandler({
    processPage: (request) => processor.processPage({ ...request, limit: 10 }),
    secret: triggerSecret,
    enabled: true,
  });
  const triggerResponse = await trigger(new Request('http://127.0.0.1/consume', {
    method: 'POST',
    headers: { 'x-catalog-run-signature': `${triggerTimestamp}.${triggerSignature}` },
  }));
  assert.equal(triggerResponse.status, 200);
  const triggerSummary = await triggerResponse.json();
  assert.equal(triggerSummary.ok, true);
  assert.ok(triggerSummary.processed >= 1);
  assert.ok(triggerSummary.states.synced >= 1,
    `sanitized consumer summary=${JSON.stringify(triggerSummary)}`);
  const outcome = { state: 'synced', write: 'applied' };
  const persistedEvent = await readDocument(store, 'catalog_outbox', operationId);
  assert.equal(outcome?.state, 'synced', `sanitized outcome=${JSON.stringify({
    state: outcome?.state, reason: outcome?.reason, errorCode: outcome?.errorCode, write: outcome?.write,
    persistedErrorCode: persistedEvent?.lastErrorCode,
  })}`);
  assert.equal(outcome?.write, 'applied');

  assert.equal(persistedEvent?.state, 'synced');
  assert.equal(persistedEvent?.attemptCount, 1);

  const persisted = await readProjection(containerName, id);
  assert.deepEqual(persisted, {
    id,
    catalog_version: 1,
    outbox_operation_id: operationId,
    name: canonical.name,
    published: true,
    deleted_at: null,
    phone: null,
    public_contact_approved: false,
  });

  const projection = projectCanonicalEstablishment(id, canonical, event);
  assert.ok(projection);
  assert.deepEqual(await writer.applyProjection(projection), { result: 'duplicate' });
  assert.deepEqual(await readProjection(containerName, id), persisted);
  assert.equal(Object.hasOwn(projection, 'ownerEmail'), false);
  assert.equal(Object.hasOwn(projection, 'adminNote'), false);

  const operation2 = randomUUID();
  const canonical2 = canonicalDocument(operation2, 2, 'PostgreSQL integration fixture v2');
  await updatePair(store, id, operation2, canonical2, 2);
  assert.equal((await processAfterSnapshot(store, rpc)).results.find((result) => result.eventId === operation2)?.state, 'synced');
  assert.deepEqual(await readProjection(containerName, id), {
    ...persisted,
    catalog_version: 2,
    outbox_operation_id: operation2,
    name: canonical2.name,
  });

  const staleOperation = randomUUID();
  await store.runTransaction(async (transaction) => {
    transaction.create('catalog_outbox', staleOperation, outboxEvent(staleOperation, id, 1), {
      serverTimestampFields: ['createdAt', 'updatedAt'],
    });
  });
  const stalePage = await processAfterSnapshot(store, rpc);
  assert.equal(stalePage.results.find((result) => result.eventId === staleOperation)?.state, 'superseded');
  assert.equal((await readProjection(containerName, id))?.catalog_version, 2);

  const operation3 = randomUUID();
  const canonical3 = canonicalDocument(operation3, 3, 'Unpublished fixture', { published: false });
  await updatePair(store, id, operation3, canonical3, 3);
  assert.equal((await processAfterSnapshot(store, rpc)).results.find((result) => result.eventId === operation3)?.state, 'synced');
  const unpublished = await readProjection(containerName, id);
  assert.equal(unpublished?.published, false);
  assert.equal(unpublished?.catalog_version, 3);

  const operation4 = randomUUID();
  const canonical4 = canonicalDocument(operation4, 4, 'Republished fixture');
  await updatePair(store, id, operation4, canonical4, 4);
  assert.equal((await processAfterSnapshot(store, rpc)).results.find((result) => result.eventId === operation4)?.state, 'synced');
  const republished = await readProjection(containerName, id);
  assert.equal(republished?.published, true);
  assert.equal(republished?.catalog_version, 4);

  const operation5 = randomUUID();
  const deletedAt = new Date().toISOString();
  const canonical5 = canonicalDocument(operation5, 5, 'Deleted fixture', { deletedAt });
  await updatePair(store, id, operation5, canonical5, 5);
  assert.equal((await processAfterSnapshot(store, rpc)).results.find((result) => result.eventId === operation5)?.state, 'synced');
  const deletedProjection = await readProjection(containerName, id);
  assert.equal(deletedProjection?.catalog_version, 5);
  assert.equal(deletedProjection?.outbox_operation_id, operation5);
  assert.equal(Date.parse(deletedProjection?.deleted_at), Date.parse(deletedAt));
  const tombstone = await readTombstone(containerName, id);
  assert.equal(tombstone?.id, id);
  assert.equal(tombstone?.catalog_version, 5);
  assert.equal(tombstone?.outbox_operation_id, operation5);
  assert.equal(Date.parse(tombstone?.tombstoned_at), Date.parse(deletedAt));
  assert.deepEqual(await readPublicCounts(containerName, id), { detail: 0, search: 0, list: 0 });
  const staleProjection = projectCanonicalEstablishment(id, canonical4, outboxEvent(operation4, id, 4));
  assert.ok(staleProjection);
  assert.deepEqual(await writer.applyProjection(staleProjection), { result: 'conflict' });
  assert.deepEqual(await readPublicCounts(containerName, id), { detail: 0, search: 0, list: 0 });

  const retryId = `e2e-${randomUUID()}`;
  const retryOperation = randomUUID();
  const retrySource = canonicalDocument(retryOperation, 1, 'Retry fixture');
  await createPair(store, retryId, retryOperation, retrySource, 1);
  let failBeforeWrite = true;
  const unavailableOnce = async (name, args) => {
    if (failBeforeWrite) {
      failBeforeWrite = false;
      throw Object.assign(new Error('synthetic transport loss'), { code: 'ECONNRESET' });
    }
    return rpc(name, args);
  };
  const failedAttempt = await processAfterSnapshot(store, unavailableOnce);
  assert.equal(failedAttempt.results.find((result) => result.eventId === retryOperation)?.state, 'pending');
  assert.equal((await readDocument(store, 'catalog_outbox', retryOperation))?.lastErrorCode, 'catalog_unavailable');
  await delay(1_200);
  const recovered = await createProcessor({ store, rpc }).processPage({ limit: 25 });
  assert.equal(recovered.results.find((result) => result.eventId === retryOperation)?.state, 'synced');
  assert.equal((await readProjection(containerName, retryId))?.outbox_operation_id, retryOperation);

  const ackId = `e2e-${randomUUID()}`;
  const ackOperation = randomUUID();
  const ackSource = canonicalDocument(ackOperation, 1, 'Lost acknowledgement fixture');
  await createPair(store, ackId, ackOperation, ackSource, 1);
  await delay(5_200);
  let failAck = true;
  const ackFaultStore = {
    queryOutboxPage: store.queryOutboxPage,
    runTransaction(callback) {
      return store.runTransaction((transaction) => callback({
        get: (...args) => transaction.get(...args),
        create: (...args) => transaction.create(...args),
        update(collection, documentId, value, options) {
          if (collection === 'catalog_outbox' && documentId === ackOperation &&
            value.state === 'synced' && failAck) {
            failAck = false;
            throw new FirestoreRestError('backend_unavailable');
          }
          transaction.update(collection, documentId, value, options);
        },
      }));
    },
  };
  const ackPending = await createProcessor({ store: ackFaultStore, rpc, leaseDurationMs: 1_000 }).processPage({ limit: 25 });
  assert.equal(ackPending.results.find((result) => result.eventId === ackOperation)?.state, 'ack_pending');
  assert.equal((await readProjection(containerName, ackId))?.outbox_operation_id, ackOperation);
  await delay(1_200);
  const ackRecovered = await createProcessor({ store, rpc, leaseDurationMs: 1_000 }).processPage({ limit: 25 });
  const ackOutcome = ackRecovered.results.find((result) => result.eventId === ackOperation);
  assert.equal(ackOutcome?.state, 'synced');
  assert.equal(ackOutcome?.write, 'duplicate');

  const concurrentId = `e2e-${randomUUID()}`;
  const concurrentOperation = randomUUID();
  const concurrentSource = canonicalDocument(concurrentOperation, 1, 'Concurrent worker fixture');
  await createPair(store, concurrentId, concurrentOperation, concurrentSource, 1);
  await delay(5_200);
  let concurrentWrites = 0;
  const countingRpc = async (name, args) => {
    const value = args.p_projection ?? args.p_tombstone;
    if (value?.id === concurrentId) concurrentWrites += 1;
    return rpc(name, args);
  };
  const [workerA, workerB] = await Promise.all([
    createProcessor({ store, rpc: countingRpc, workerId: 'e2e-worker-a' }).processPage({ limit: 25 }),
    createProcessor({ store, rpc: countingRpc, workerId: 'e2e-worker-b' }).processPage({ limit: 25 }),
  ]);
  assert.equal(concurrentWrites, 1);
  assert.equal((await readDocument(store, 'catalog_outbox', concurrentOperation))?.state, 'synced');
  assert.equal((await readProjection(containerName, concurrentId))?.outbox_operation_id, concurrentOperation);
  assert.ok([...workerA.results, ...workerB.results].some((result) => result.eventId === concurrentOperation));

  const adminUid = `synthetic-admin-${randomUUID()}`;
  const adminEntityId = `e2e-${randomUUID()}`;
  const adminCreateOperation = randomUUID();
  await store.runTransaction(async (transaction) => {
    transaction.create('admin_authorizations', adminUid, {
      enabled: true, pending: false, version: 'emulator-test-v1',
    });
  });
  const adminHandler = createAdminEstablishmentsHandler({
    projectId: 'tudo-aqui-macacu',
    store,
    uuid: () => adminEntityId,
    verifyIdentity: async () => ({
      uid: adminUid, authTime: Math.floor(Date.now() / 1_000), isAnonymous: false, provider: 'password',
    }),
    authorizeAdmin,
  });
  const adminRequest = (body) => new Request('http://127.0.0.1/manage-establishments', {
    method: 'POST',
    headers: { authorization: 'Bearer synthetic-firebase-identity', 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const adminCreate = await adminHandler(adminRequest({
    operation: 'create', requestId: adminCreateOperation, data: adminData(),
  }));
  assert.equal(adminCreate.status, 201);
  const created = await adminCreate.json();
  assert.equal(created.entityId, adminEntityId);
  assert.equal(created.version, 1);
  await delay(5_200);
  const adminPublished = await processAfterSnapshot(store, rpc);
  assert.equal(adminPublished.results.find((result) => result.eventId === adminCreateOperation)?.state, 'synced');
  assert.equal((await readProjection(containerName, adminEntityId))?.published, true);

  const deleteOperation = randomUUID();
  const adminDelete = await adminHandler(adminRequest({
    operation: 'delete', requestId: deleteOperation, entityId: adminEntityId, expectedVersion: 1,
  }));
  assert.equal(adminDelete.status, 200);
  assert.equal((await adminDelete.json()).result, 'deleted');
  const deletedSource = await readDocument(store, 'establishments', adminEntityId);
  assert.ok(typeof deletedSource?.deletedAt === 'string');
  assert.equal(deletedSource?.catalogVersion, 2);
  assert.equal(deletedSource?.outboxOperationId, deleteOperation);
  await delay(5_200);
  const adminDeleted = await processAfterSnapshot(store, rpc);
  assert.equal(adminDeleted.results.find((result) => result.eventId === deleteOperation)?.state, 'synced');
  const adminDeletedProjection = await readProjection(containerName, adminEntityId);
  assert.equal(adminDeletedProjection?.catalog_version, 2);
  assert.equal(Date.parse(adminDeletedProjection?.deleted_at), Date.parse(deletedSource.deletedAt));
  assert.deepEqual(await readPublicCounts(containerName, adminEntityId), { detail: 0, search: 0, list: 0 });
});

function createProcessor({ store, rpc, workerId = `e2e-worker-${randomUUID()}`, leaseDurationMs = 30_000 }) {
  return createCatalogOutboxProcessor({
    store,
    serverIdentity: { workerId },
    rpc,
    createLeaseToken: randomUUID,
    leaseDurationMs,
    pageSize: 25,
  });
}

function createPsqlRpc(name) {
  const functions = new Map([
    ['apply_establishment_projection_v2', 'public.apply_establishment_projection_v2'],
    ['apply_establishment_tombstone_v2', 'public.apply_establishment_tombstone_v2'],
  ]);
  return async (functionName, args) => {
    const sqlFunction = functions.get(functionName);
    const payload = args?.p_projection ?? args?.p_tombstone;
    if (!sqlFunction || !payload || typeof payload !== 'object') {
      return { data: null, error: { code: '22023' } };
    }
    const result = await runDocker([
      'exec', '--interactive', '--env', 'PGAPPNAME=macacu-0755-rpc-integration', name,
      'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate',
      '-U', 'supabase_admin', '-d', 'postgres', '-v', `payload=${JSON.stringify(payload)}`,
      '-f', '-',
    ], 10_000, `select ${sqlFunction}(:'payload'::jsonb);\n`);
    if (result.code !== 0) {
      const code = extractSqlState(result.stderr);
      process.stderr.write(`${JSON.stringify({ event: 'postgres_rpc_error', exitCode: result.code, sqlState: code })}\n`);
      return { data: null, error: { code } };
    }
    const value = result.stdout.trim();
    if (!['applied', 'replayed'].includes(value)) {
      process.stderr.write(`${JSON.stringify({ event: 'postgres_rpc_unexpected_result', outputLength: value.length })}\n`);
    }
    return { data: value, error: null };
  };
}

async function readProjection(container, id) {
  const result = await psql(container, [
    '-v', `id=${id}`,
    '-f', '-',
  ], "select json_build_object('id', id, 'catalog_version', catalog_version, 'outbox_operation_id', outbox_operation_id, 'name', name, 'published', published, 'deleted_at', deleted_at, 'phone', phone, 'public_contact_approved', public_contact_approved)::text from public.public_establishment_catalog_v2 where id = :'id';\n");
  return result.stdout ? JSON.parse(result.stdout) : null;
}

async function readTombstone(container, id) {
  const result = await psql(container, [
    '-v', `id=${id}`,
    '-f', '-',
  ], "select json_build_object('id', id, 'catalog_version', catalog_version, 'outbox_operation_id', outbox_operation_id, 'tombstoned_at', tombstoned_at)::text from public.catalog_tombstones_v2 where id = :'id';\n");
  return result.stdout ? JSON.parse(result.stdout) : null;
}

async function readPublicCounts(container, id) {
  const result = await psql(container, ['-v', `id=${id}`, '-f', '-'],
    "select json_build_object('detail', (select count(*)::integer from public.get_public_establishment_v2(:'id')), 'search', (select count(*)::integer from public.search_public_establishments_v2('Republished', 'all', 40, null) where id = :'id'), 'list', (select count(*)::integer from public.list_public_establishments_v2('all', 40, null) where id = :'id'))::text;\n");
  return JSON.parse(result.stdout);
}

async function readDocument(store, collection, id) {
  return store.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(collection, id);
    return snapshot?.data ?? null;
  });
}

async function inspectContainer(name) {
  const result = await runDocker(['inspect', name]);
  if (result.code !== 0) throw new Error('Disposable PostgreSQL container inspection failed.');
  return JSON.parse(result.stdout)[0];
}

function psql(name, args, stdin) {
  return runDocker([
    'exec', '--interactive', name, 'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
    '-U', 'supabase_admin', '-d', 'postgres', ...args,
  ], 10_000, stdin).then((result) => {
    if (result.code !== 0) {
      const sqlState = extractSqlState(result.stderr);
      throw new Error(`Disposable PostgreSQL query failed (${sqlState}).`);
    }
    return result;
  });
}

function runDocker(args, timeoutMs = 10_000, stdin = '') {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', args, { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill();
      reject(Object.assign(new Error('Local PostgreSQL command timed out.'), { code: '08006' }));
    }, timeoutMs);
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdin.end(stdin);
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(Object.assign(new Error('Local Docker command failed.'), { code: error.code }));
    });
    child.once('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });
}

function canonicalDocument(operationId, version, name, overrides = {}) {
  return {
    name,
    description: 'Synthetic public summary only',
    category: 'Comércio',
    subcategory: 'Teste',
    published: true,
    active: true,
    catalogVersion: version,
    outboxOperationId: operationId,
    publicContactApproved: false,
    deletedAt: null,
    ownerEmail: 'private-sentinel@example.invalid',
    adminNote: 'PRIVATE_SENTINEL_DO_NOT_PROJECT',
    ...overrides,
  };
}

function adminData() {
  return {
    title: 'Estabelecimento sintético',
    description: 'Somente fixture local para validar o consumidor.',
    category: 'Comércio',
    subcategory: 'Teste',
    imageUrl: '',
    published: true,
    active: true,
    publicContactApproved: false,
  };
}

function outboxEvent(operationId, entityId, version) {
  const timestamp = new Date();
  return {
    schemaVersion: 2,
    operationId,
    entityType: 'establishment',
    entityId,
    authorUid: 'synthetic-admin',
    version,
    operation: 'reconcile',
    state: 'pending',
    attemptCount: 0,
    createdAt: timestamp,
    updatedAt: timestamp,
    workerId: null,
    leaseToken: null,
    leaseExpiresAt: null,
    nextAttemptAt: null,
    lastErrorCode: null,
    syncedAt: null,
  };
}

async function createPair(store, id, operationId, source, version) {
  await store.runTransaction(async (transaction) => {
    transaction.create('establishments', id, source, { serverTimestampFields: ['createdAt', 'updatedAt'] });
    transaction.create('catalog_outbox', operationId, outboxEvent(operationId, id, version), {
      serverTimestampFields: ['createdAt', 'updatedAt'],
    });
  });
}

async function updatePair(store, id, operationId, source, version) {
  await store.runTransaction(async (transaction) => {
    const current = await transaction.get('establishments', id);
    assert.ok(current, 'canonical establishment exists before update');
    transaction.update('establishments', id, source, {
      updateTime: current.updateTime,
      serverTimestampFields: ['updatedAt'],
    });
    transaction.create('catalog_outbox', operationId, outboxEvent(operationId, id, version), {
      serverTimestampFields: ['createdAt', 'updatedAt'],
    });
  });
}

async function processAfterSnapshot(store, rpc) {
  await delay(5_200);
  return createProcessor({ store, rpc }).processPage({ limit: 25 });
}

function parseLoopback(value) {
  const match = typeof value === 'string' && /^(127\.0\.0\.1|::1):(\d{1,5})$/u.exec(value);
  if (!match) return null;
  const port = Number(match[2]);
  return Number.isSafeInteger(port) && port >= 1 && port <= 65_535
    ? { host: match[1], port } : null;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function extractSqlState(stderr) {
  for (const match of String(stderr).matchAll(/\b([0-9A-Z]{5})\b/gu)) {
    if (/\d/u.test(match[1])) return match[1];
  }
  return '08006';
}
