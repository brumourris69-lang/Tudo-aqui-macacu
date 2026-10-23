import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { createAdminEstablishmentsHandler } from './admin_establishments.mjs';
import { authorizeAdmin } from './admin_authorization.mjs';

const PROJECT_ID = 'demo-universal-search';
const EXPECTED_HOST = '127.0.0.1:8087';
const configuredHost = process.env.FIRESTORE_EMULATOR_HOST;
const emulatorEnabled = process.env.GCLOUD_PROJECT === PROJECT_ID && configuredHost === EXPECTED_HOST;
const requireFromFunctions = createRequire(path.resolve(
  path.dirname(fileURLToPath(import.meta.url)), '../../../functions/package.json'));
const { initializeApp, deleteApp } = requireFromFunctions('firebase-admin/app');
const { getFirestore, FieldValue } = requireFromFunctions('firebase-admin/firestore');

test('administrative producer transactions persist canonical and outbox documents atomically in Firestore Emulator', {
  skip: !emulatorEnabled && 'Requires the demo Firestore Emulator at 127.0.0.1:8087; no hosted Firebase is used.',
}, async () => {
  const app = initializeApp({ projectId: PROJECT_ID }, `admin-outbox-${randomUUID()}`);
  const db = getFirestore(app);
  const uid = `synthetic-admin-${randomUUID()}`;
  const authorizationRef = db.collection('admin_authorizations').doc(uid);
  const entityIds = new Set();
  const operationIds = new Set();
  const identity = Object.freeze({
    uid,
    authTime: Math.floor(Date.now() / 1000),
    isAnonymous: false,
    provider: 'password',
  });

  function createStore({ failOnOutboxId } = {}) {
    return {
      async runTransaction(callback) {
        return db.runTransaction(async (nativeTransaction) => {
          const snapshots = new Map();
          const transaction = {
            async get(collection, id) {
              const reference = db.collection(collection).doc(id);
              const snapshot = await nativeTransaction.get(reference);
              snapshots.set(`${collection}/${id}`, snapshot);
              return snapshot.exists ? {
                data: snapshot.data(),
                updateTime: formatUpdateTime(snapshot.updateTime),
              } : null;
            },
            create(collection, id, data, options = {}) {
              if (collection === 'catalog_outbox') {
                if (id === failOnOutboxId) throw new Error('Synthetic outbox staging failure.');
                operationIds.add(id);
              }
              if (collection === 'establishments') entityIds.add(id);
              nativeTransaction.create(db.collection(collection).doc(id), withTransforms(data, options));
            },
            update(collection, id, data, options = {}) {
              const key = `${collection}/${id}`;
              const snapshot = snapshots.get(key);
              if (!snapshot?.exists || formatUpdateTime(snapshot.updateTime) !== options.updateTime) {
                throw Object.assign(new Error('Synthetic transaction precondition failed.'), { code: 'conflict' });
              }
              nativeTransaction.update(db.collection(collection).doc(id), withTransforms(data, options));
            },
          };
          return callback(transaction);
        }, { maxAttempts: 5 });
      },
    };
  }

  function withTransforms(data, options = {}) {
    const result = { ...data };
    for (const field of options.deleteFields ?? []) result[field] = FieldValue.delete();
    for (const field of options.serverTimestampFields ?? []) result[field] = FieldValue.serverTimestamp();
    return result;
  }

  function makeHandler(store = createStore(), verifiedIdentity = identity) {
    return createAdminEstablishmentsHandler({
      // The handler's production-project guard remains active. Only its Firestore
      // dependency points at the explicit demo Emulator, with a synthetic verifier.
      projectId: 'tudo-aqui-macacu',
      store,
      verifyIdentity: async (token, projectId) => {
        assert.equal(token, 'synthetic-emulator-token');
        assert.equal(projectId, 'tudo-aqui-macacu');
        return verifiedIdentity;
      },
      authorizeAdmin,
      uuid: randomUUID,
    });
  }

  function request(handler, body) {
    return handler(new Request('http://127.0.0.1/manage-establishments', {
      method: 'POST',
      headers: {
        authorization: 'Bearer synthetic-emulator-token',
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    }));
  }

  const readSource = async (id) => (await db.collection('establishments').doc(id).get()).data();
  const readEvent = async (id) => (await db.collection('catalog_outbox').doc(id).get()).data();
  const baseData = {
    title: 'Emulator Fixture Listing',
    description: 'Synthetic public listing for transaction validation.',
    category: 'Comércio',
    subcategory: 'Fixture',
    published: true,
    active: true,
    publicContactApproved: false,
    phone: '+5521999999999',
  };
  const entityId = `modelo-emulator-${randomUUID()}`;
  const createRequestId = randomUUID();
  entityIds.add(entityId);
  operationIds.add(createRequestId);
  const handler = makeHandler();

  try {
    await authorizationRef.create({ enabled: true, pending: false, version: 'synthetic-auth-v1' });

    const createBody = {
      operation: 'create', requestId: createRequestId, entityId, data: baseData,
    };
    const created = await request(handler, createBody);
    assert.equal(created.status, 201);
    assert.deepEqual(await created.json(), {
      result: 'created', operationId: createRequestId, entityId, version: 1, replayed: false,
    });

    let source = await readSource(entityId);
    let event = await readEvent(createRequestId);
    assert.equal(source.catalogVersion, 1);
    assert.equal(source.outboxOperationId, createRequestId);
    assert.equal(event.schemaVersion, 2);
    assert.equal(event.entityId, entityId);
    assert.equal(event.version, 1);
    assert.equal(event.state, 'pending');
    assert.equal(event.attemptCount, 0);
    assert.ok(event.createdAt instanceof Date || typeof event.createdAt?.toDate === 'function');
    assert.ok(event.updatedAt instanceof Date || typeof event.updatedAt?.toDate === 'function');
    assert.equal(Object.hasOwn(event, 'email'), false);
    assert.equal(Object.hasOwn(event, 'phone'), false);
    assert.equal(JSON.stringify(event).includes('synthetic-emulator-token'), false);

    const replayed = await request(handler, createBody);
    assert.equal(replayed.status, 200);
    assert.equal((await replayed.json()).replayed, true);
    assert.equal((await readSource(entityId)).catalogVersion, 1);

    const updated = await request(handler, {
      operation: 'update', requestId: randomUUID(), entityId, expectedVersion: 1,
      data: { description: 'Updated synthetic listing.' },
    });
    const updatedBody = await updated.json();
    operationIds.add(updatedBody.operationId);
    assert.equal(updated.status, 200);
    assert.equal(updatedBody.version, 2);

    const concurrentIds = [randomUUID(), randomUUID()];
    concurrentIds.forEach((id) => operationIds.add(id));
    const concurrent = await Promise.all(concurrentIds.map((requestId, index) => request(handler, {
      operation: 'update', requestId, entityId, expectedVersion: 2,
      data: { description: `Concurrent synthetic update ${index}.` },
    })));
    const concurrentStatuses = concurrent.map((response) => response.status).sort();
    assert.deepEqual(concurrentStatuses, [200, 409]);
    const concurrentBodies = await Promise.all(concurrent.map((response) => response.clone().json()));
    const winningOperationId = concurrentBodies.find((body) => body.version === 3)?.operationId;
    assert.ok(concurrentIds.includes(winningOperationId));
    source = await readSource(entityId);
    assert.equal(source.catalogVersion, 3);
    assert.equal(source.outboxOperationId, winningOperationId);
    const committedConcurrentEvents = await Promise.all(concurrentIds.map(readEvent));
    assert.equal(committedConcurrentEvents.filter(Boolean).length, 1);

    const unpublishId = randomUUID();
    operationIds.add(unpublishId);
    const unpublished = await request(handler, {
      operation: 'unpublish', requestId: unpublishId, entityId, expectedVersion: 3,
    });
    assert.equal(unpublished.status, 200);
    source = await readSource(entityId);
    assert.equal(source.catalogVersion, 4);
    assert.equal(source.published, false);
    assert.equal(source.active, false);
    assert.equal(source.deletedAt ?? null, null);
    assert.equal((await readEvent(unpublishId)).version, 4);

    const republishId = randomUUID();
    operationIds.add(republishId);
    const republished = await request(handler, {
      operation: 'republish', requestId: republishId, entityId, expectedVersion: 4,
      data: { description: 'Republished synthetic listing.' },
    });
    assert.equal(republished.status, 200);
    source = await readSource(entityId);
    assert.equal(source.catalogVersion, 5);
    assert.equal(source.published, true);
    assert.equal(source.deletedAt ?? null, null);

    const deleteId = randomUUID();
    operationIds.add(deleteId);
    const deleted = await request(handler, {
      operation: 'delete', requestId: deleteId, entityId, expectedVersion: 5,
    });
    assert.equal(deleted.status, 200);
    source = await readSource(entityId);
    assert.equal(source.catalogVersion, 6);
    assert.equal(source.published, false);
    assert.ok(source.deletedAt);
    assert.equal((await readEvent(deleteId)).version, 6);

    const forbiddenRepublishId = randomUUID();
    operationIds.add(forbiddenRepublishId);
    const forbiddenRepublish = await request(handler, {
      operation: 'republish', requestId: forbiddenRepublishId, entityId, expectedVersion: 6,
    });
    assert.equal(forbiddenRepublish.status, 409);
    assert.equal(await readEvent(forbiddenRepublishId), undefined);
    assert.equal((await readSource(entityId)).catalogVersion, 6);

    const invalidId = randomUUID();
    const invalidEntityId = `invalid-${randomUUID()}`;
    operationIds.add(invalidId);
    entityIds.add(invalidEntityId);
    const invalid = await request(handler, {
      operation: 'create', requestId: invalidId, entityId: invalidEntityId,
      data: { ...baseData, adminNote: 'must-not-be-written' },
    });
    assert.equal(invalid.status, 400);
    assert.equal(await readSource(invalidEntityId), undefined);
    assert.equal(await readEvent(invalidId), undefined);

    const ordinaryIdentity = Object.freeze({ ...identity, uid: `synthetic-user-${randomUUID()}` });
    const ordinaryHandler = makeHandler(createStore(), ordinaryIdentity);
    const ordinaryRequestId = randomUUID();
    const ordinaryEntityId = `ordinary-${randomUUID()}`;
    operationIds.add(ordinaryRequestId);
    entityIds.add(ordinaryEntityId);
    const ordinaryUserWrite = await request(ordinaryHandler, {
      operation: 'create', requestId: ordinaryRequestId, entityId: ordinaryEntityId, data: baseData,
    });
    assert.equal(ordinaryUserWrite.status, 403);
    assert.equal(await readSource(ordinaryEntityId), undefined);
    assert.equal(await readEvent(ordinaryRequestId), undefined);

    const failedPairId = randomUUID();
    const failedPairEntityId = `failed-${randomUUID()}`;
    operationIds.add(failedPairId);
    entityIds.add(failedPairEntityId);
    const failOutboxHandler = makeHandler(createStore({ failOnOutboxId: failedPairId }));
    const failedPair = await request(failOutboxHandler, {
      operation: 'create', requestId: failedPairId, entityId: failedPairEntityId, data: baseData,
    });
    assert.equal(failedPair.status, 503);
    assert.equal(await readSource(failedPairEntityId), undefined);
    assert.equal(await readEvent(failedPairId), undefined);

    await authorizationRef.update({ enabled: false, pending: false, revoked: true });
    const revokedRequestId = randomUUID();
    operationIds.add(revokedRequestId);
    const revoked = await request(handler, {
      operation: 'update', requestId: revokedRequestId, entityId, expectedVersion: 6,
      data: { description: 'Must not be applied after revocation.' },
    });
    assert.equal(revoked.status, 403);
    assert.equal(await readEvent(revokedRequestId), undefined);
    assert.equal((await readSource(entityId)).catalogVersion, 6);
  } finally {
    await Promise.all([
      ...[...operationIds].map((id) => db.collection('catalog_outbox').doc(id).delete()),
      ...[...entityIds].map((id) => db.collection('establishments').doc(id).delete()),
      authorizationRef.delete(),
    ]);
    await deleteApp(app);
  }
});

function formatUpdateTime(timestamp) {
  const date = timestamp.toDate().toISOString();
  const nanos = String(timestamp.nanoseconds).padStart(9, '0');
  return date.replace(/\.\d{3}Z$/u, `.${nanos}Z`);
}
