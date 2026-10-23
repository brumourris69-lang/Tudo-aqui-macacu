import assert from 'node:assert/strict';
import test from 'node:test';
import { projectCanonicalEstablishment } from './catalog_outbox_protocol.mjs';
import { createCatalogReconciliationPlan } from './catalog_reconciliation.mjs';

const OP_A = '00000000-0000-4000-8000-000000000001';
const OP_B = '00000000-0000-4000-8000-000000000002';
const ID = 'modelo-legacy-001';
const DELETED_AT = '2026-10-20T12:00:00.000Z';

test('reports an exact canonical projection as in sync', () => {
  const canonical = record(OP_A, 3);
  const projection = project(canonical);
  const result = plan([canonical], [{ ...projection, search_document: 'private-index-derived-term' }]);

  assert.deepEqual(result.items, [{ id: ID, status: 'in_sync', action: 'none' }]);
  assert.deepEqual(result.summary, { in_sync: 1 });
});

test('plans only the current public projection when destination is absent or stale', () => {
  const canonical = record(OP_B, 4, { ownerEmail: 'private@example.invalid', adminNote: 'SECRET' });
  const stale = project(record(OP_A, 2));
  const result = plan([canonical], [stale]);
  const item = result.items[0];

  assert.equal(item.status, 'projection_outdated');
  assert.equal(item.action, 'apply_projection');
  assert.deepEqual(item.payload, project(canonical));
  assert.equal(JSON.stringify(item).includes('private@example.invalid'), false);
  assert.equal(JSON.stringify(item).includes('SECRET'), false);
});

test('does not choose between conflicting content or operation at the same version', () => {
  const canonical = record(OP_A, 3);
  const destination = { ...project(canonical), name: 'Different same-version content' };
  const result = plan([canonical], [destination]);

  assert.deepEqual(result.items, [{ id: ID, status: 'version_conflict', action: 'manual_review' }]);
});

test('plans a permanent tombstone separately from a reversible unpublished projection', () => {
  const deleted = record(OP_B, 4, { deletedAt: DELETED_AT, published: false });
  const result = plan([deleted], []);

  assert.equal(result.items[0].status, 'tombstone_missing');
  assert.equal(result.items[0].action, 'apply_tombstone');
  assert.deepEqual(result.items[0].payload, {
    id: ID, catalog_version: 4, outbox_operation_id: OP_B, deleted_at: DELETED_AT,
  });
});

test('an existing tombstone permanently blocks a live canonical projection', () => {
  const live = record(OP_B, 5, { published: true });
  const tombstone = { id: ID, catalog_version: 4, outbox_operation_id: OP_A, tombstoned_at: DELETED_AT };
  const result = plan([live], [], [tombstone]);

  assert.deepEqual(result.items, [{ id: ID, status: 'blocked_by_tombstone', action: 'manual_review' }]);
});

test('a deleted catalog row still blocks a live source when the tombstone snapshot is incomplete', () => {
  const live = record(OP_B, 5, { published: true });
  const deletedRow = { ...project(record(OP_A, 4, { deletedAt: DELETED_AT })), deleted_at: DELETED_AT };
  const result = plan([live], [deletedRow]);

  assert.deepEqual(result.items[0], { id: ID, status: 'blocked_by_tombstone', action: 'manual_review' });
});

test('recognizes a matching tombstone and does not require a catalog row', () => {
  const deleted = record(OP_A, 3, { deletedAt: DELETED_AT, published: false });
  const tombstone = { id: ID, catalog_version: 3, outbox_operation_id: OP_A, tombstoned_at: DELETED_AT };
  const result = plan([deleted], [], [tombstone]);

  assert.equal(result.items[0].status, 'in_sync_tombstone');
});

test('reports tombstone and catalog metadata divergence instead of claiming synchronization', () => {
  const deleted = record(OP_A, 3, { deletedAt: DELETED_AT, published: false });
  const tombstone = { id: ID, catalog_version: 3, outbox_operation_id: OP_A, tombstoned_at: DELETED_AT };
  const stale = { ...project(record(OP_A, 2)), deleted_at: DELETED_AT };
  const result = plan([deleted], [stale], [tombstone]);

  assert.deepEqual(result.items[0], { id: ID, status: 'tombstone_projection_conflict', action: 'manual_review' });
});

test('never overwrites a destination version newer than Firestore', () => {
  const canonical = record(OP_A, 3);
  const newer = project(record(OP_B, 4));
  const result = plan([canonical], [newer]);

  assert.deepEqual(result.items[0], { id: ID, status: 'destination_newer', action: 'manual_review' });
});

test('reports destination-only rows without proposing destructive deletion', () => {
  const result = plan([], [project(record(OP_A, 1))]);

  assert.deepEqual(result.items, [{ id: ID, status: 'canonical_missing', action: 'manual_review' }]);
});

test('invalid canonical metadata is reported without producing a write payload', () => {
  const invalid = record('not-an-operation-id', 2);
  const result = plan([invalid], []);

  assert.deepEqual(result.items, [{ id: ID, status: 'invalid_canonical', action: 'manual_review' }]);
});

test('rejects duplicate or malformed snapshots rather than returning an ambiguous plan', () => {
  const canonical = record(OP_A, 1);
  assert.throws(() => plan([canonical, canonical], []), { code: 'invalid-reconciliation-snapshot' });
  assert.throws(() => plan([canonical, { ...record(OP_A, 1), id: 'another-id' }], []),
    { code: 'invalid-reconciliation-snapshot' });
  assert.throws(() => createCatalogReconciliationPlan({ canonicalDocuments: null }),
    { code: 'invalid-reconciliation-snapshot' });
});

function plan(canonicalDocuments, catalogRows, tombstones = []) {
  return createCatalogReconciliationPlan({ canonicalDocuments, catalogRows, tombstones });
}

function project(value) {
  const { id, data } = value;
  return projectCanonicalEstablishment(id, data, {
    schemaVersion: 2, operationId: data.outboxOperationId, version: data.catalogVersion,
    authorUid: 'synthetic-admin', entityId: id, entityType: 'establishment', operation: 'reconcile', state: 'pending',
    attemptCount: 0, workerId: null, leaseToken: null, leaseExpiresAt: null,
    nextAttemptAt: null, lastErrorCode: null, syncedAt: null, createdAt: new Date(0), updatedAt: new Date(0),
  });
}

function record(operationId, catalogVersion, overrides = {}) {
  return { id: ID, data: {
    name: 'Local synthetic business', description: 'Public summary', category: 'Comércio',
    subcategory: 'Test', published: true, active: true, catalogVersion,
    outboxOperationId: operationId, publicContactApproved: false, deletedAt: null,
    ...overrides,
  } };
}
