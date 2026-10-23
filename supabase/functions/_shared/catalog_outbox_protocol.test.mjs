import test from 'node:test';
import assert from 'node:assert/strict';
import {
  OUTBOX_STATES,
  createCatalogOutboxProtocol,
} from './catalog_outbox_protocol.mjs';

const OP_1 = '00000000-0000-4000-8000-000000000001';
const OP_2 = '00000000-0000-4000-8000-000000000002';
const ENTITY_ID = 'modelo-established-legacy-01';
const baseEvent = (overrides = {}) => ({
  schemaVersion: 1,
  operationId: OP_1,
  entityType: 'establishment',
  entityId: ENTITY_ID,
  authorUid: 'admin-user-not-used-in-projection',
  version: 4,
  operation: 'reconcile',
  state: 'pending',
  attemptCount: 0,
  ...overrides,
});
const baseV2Event = (overrides = {}) => ({
  ...baseEvent({ schemaVersion: 2 }),
  createdAt: new Date('2026-10-20T12:00:00.000Z'),
  updatedAt: new Date('2026-10-20T12:00:00.000Z'),
  workerId: null,
  leaseToken: null,
  leaseExpiresAt: null,
  nextAttemptAt: null,
  lastErrorCode: null,
  syncedAt: null,
  ...overrides,
});
const baseSource = (overrides = {}) => ({
  name: 'Mercado do Bairro',
  description: 'Resumo público',
  category: 'Comércio',
  subcategory: 'Mercado',
  published: true,
  active: true,
  publicContactApproved: true,
  phone: '+5521999999999',
  whatsapp: 'https://wa.me/5521999999999',
  instagram: '@mercado',
  catalogVersion: 4,
  outboxOperationId: OP_1,
  updatedAt: '2026-10-20T12:00:00.000Z',
  ownerEmail: 'must-not-leave-firestore@example.test',
  adminNote: 'private sentinel',
  ...overrides,
});

function memoryAdapters({ event = baseEvent(), source = baseSource(), now = 1_000, beforeTransition } = {}) {
  const events = new Map([[event.operationId, structuredClone(event)]]);
  const sources = new Map([[event.entityId, structuredClone(source)]]);
  const rows = new Map();
  const tombstones = new Map();
  const writes = [];
  let clock = now;
  let transitionFault;
  const outbox = {
    async inspect(id) { return events.has(id) ? structuredClone(events.get(id)) : null; },
    async claim(id, claim) {
      const current = events.get(id);
      if (!current || current.version !== claim.expectedVersion) return { claimed: false, reason: 'changed' };
      if (current.state === 'synced' || current.state === 'superseded' || current.state === 'dead_letter') {
        return { claimed: false, reason: 'terminal' };
      }
      if (current.nextAttemptAt != null && timestampMillis(current.nextAttemptAt) > claim.now) {
        return { claimed: false, reason: 'retry_scheduled' };
      }
      if (current.state === 'processing' && timestampMillis(current.leaseExpiresAt) > claim.now) {
        return { claimed: false, reason: 'busy' };
      }
      if (current.state !== claim.expectedState || (current.state !== 'pending' && current.state !== 'processing')) {
        return { claimed: false, reason: 'changed' };
      }
      Object.assign(current, {
        state: 'processing', workerId: claim.workerId, leaseToken: claim.leaseToken,
        leaseExpiresAt: current.schemaVersion === 2 ? new Date(claim.leaseExpiresAt) : claim.leaseExpiresAt,
        attemptCount: current.attemptCount + 1,
        nextAttemptAt: null,
        ...(current.schemaVersion === 2 ? { updatedAt: new Date(claim.now) } : {}),
      });
      return { claimed: true, event: structuredClone(current) };
    },
    async readClaimed(owner) {
      const id = owner.eventId;
      const current = events.get(id);
      if (!leaseMatches(current, owner, clock)) return null;
      return structuredClone(current);
    },
    async renewLease(renewal) {
      const id = renewal.eventId;
      const current = events.get(id);
      if (renewal.expectedState !== 'processing' || !leaseMatches(current, renewal, clock) ||
        current.version !== renewal.expectedVersion) return false;
      current.leaseExpiresAt = current.schemaVersion === 2 ? new Date(renewal.leaseExpiresAt) : renewal.leaseExpiresAt;
      if (current.schemaVersion === 2) current.updatedAt = new Date(renewal.now);
      return true;
    },
    async transition(transition) {
      const id = transition.eventId;
      if (transitionFault) {
        const error = transitionFault;
        transitionFault = null;
        throw error;
      }
      await beforeTransition?.(id, transition, events);
      const current = events.get(id);
      if (!leaseMatches(current, transition, clock) || current.version !== transition.expectedVersion ||
        current.state !== transition.expectedState) return false;
      const patch = { ...transition.patch };
      if (current.schemaVersion === 2) {
        for (const key of ['nextAttemptAt', 'syncedAt']) {
          if (typeof patch[key] === 'number') patch[key] = new Date(patch[key]);
        }
        Object.assign(current, patch, {
          workerId: null,
          leaseToken: null,
          leaseExpiresAt: null,
          updatedAt: new Date(transition.now),
        });
      } else {
        Object.assign(current, patch);
        delete current.workerId;
        delete current.leaseToken;
        delete current.leaseExpiresAt;
      }
      return true;
    },
    failNextTransition(error) { transitionFault = error; },
  };
  const canonical = {
    async get(id) { return sources.has(id) ? structuredClone(sources.get(id)) : null; },
  };
  const catalog = {
    async applyProjection(value) { return applyVersioned(value); },
    async applyTombstone(value) { return applyVersioned(value); },
  };
  function applyVersioned(value) {
    const id = value.id;
    const tombstone = tombstones.get(id);
    const current = rows.get(id);
    const currentVersion = Math.max(tombstone?.catalogVersion ?? 0, current?.catalogVersion ?? 0);
    if (value.catalog_version < currentVersion) return { result: 'stale' };
    if (tombstone && value.catalog_version >= tombstone.catalogVersion) {
      if (value.deleted_at != null && value.catalog_version === tombstone.catalogVersion &&
        value.outbox_operation_id === tombstone.outboxOperationId) return { result: 'duplicate' };
      return { result: 'tombstoned' };
    }
    if (current && value.catalog_version === current.catalogVersion) {
      if (value.outbox_operation_id === current.outboxOperationId &&
        JSON.stringify(value) === JSON.stringify(current.value)) return { result: 'duplicate' };
      return { result: 'conflict' };
    }
    if (value.deleted_at != null) {
      tombstones.set(id, { catalogVersion: value.catalog_version, outboxOperationId: value.outbox_operation_id });
      rows.set(id, { catalogVersion: value.catalog_version, outboxOperationId: value.outbox_operation_id, value: structuredClone(value) });
    } else {
      rows.set(id, { catalogVersion: value.catalog_version, outboxOperationId: value.outbox_operation_id, value: structuredClone(value) });
    }
    writes.push(structuredClone(value));
    return { result: 'applied' };
  }
  return {
    outbox, canonical, catalog, events, sources, rows, tombstones, writes,
    setNow(value) { clock = value; },
    getNow() { return clock; },
    failNextTransition(error) { outbox.failNextTransition(error); },
  };
}

function leaseMatches(current, owner, now) {
  return current?.state === 'processing' && current.workerId === owner.workerId &&
    current.leaseToken === owner.leaseToken && current.version === owner.expectedVersion &&
    timestampMillis(current.leaseExpiresAt) > now;
}

function timestampMillis(value) {
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  if (value && Number.isSafeInteger(value.seconds) && Number.isInteger(value.nanoseconds)) {
    return value.seconds * 1_000 + Math.floor(value.nanoseconds / 1_000_000);
  }
  return Number.NaN;
}

function protocol(adapters, options = {}) {
  let token = 0;
  return createCatalogOutboxProtocol({
    ...adapters,
    now: adapters.getNow,
    createLeaseToken: () => `lease-${String(++token).padStart(20, '0')}`,
    leaseDurationMs: 100,
    retryPolicy: { baseDelayMs: 10, maximumDelayMs: 25, maxAttempts: 3 },
    ...options,
  });
}

test('publishes only an allowlisted projection, then marks the matching event synced', async () => {
  const adapters = memoryAdapters();
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');

  assert.equal(result.state, 'synced');
  assert.equal(adapters.events.get(OP_1).state, 'synced');
  assert.equal(adapters.rows.get(ENTITY_ID).catalogVersion, 4);
  assert.equal(adapters.rows.get(ENTITY_ID).outboxOperationId, OP_1);
  const row = adapters.writes[0];
  assert.deepEqual(Object.keys(row).sort(), [
    'active', 'additional_info', 'artwork', 'category', 'category_group', 'catalog_version',
    'content_kind', 'deleted_at', 'expires_at', 'featured', 'gallery_urls', 'hours', 'id',
    'image_url', 'instagram', 'is_open', 'logo_url', 'location', 'maps_url', 'name',
    'outbox_operation_id', 'phone', 'products', 'promotion_description', 'promotion_title',
    'public_contact_approved', 'published', 'services', 'subcategory', 'summary', 'whatsapp',
  ].sort());
  const serialized = JSON.stringify(row);
  assert.equal(serialized.includes('private sentinel'), false);
  assert.equal(serialized.includes('example.test'), false);
  assert.equal(adapters.writes[0].name, 'Mercado do Bairro');
});

test('reversible unpublish updates the visible projection without creating a tombstone', async () => {
  const adapters = memoryAdapters({ source: baseSource({ published: false, active: false }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'synced');
  assert.equal(adapters.rows.get(ENTITY_ID).value.published, false);
  assert.equal(adapters.rows.get(ENTITY_ID).value.deleted_at, null);
  assert.equal(adapters.tombstones.has(ENTITY_ID), false);
});

test('unapproved public contacts are omitted from the projected V2 row', async () => {
  const adapters = memoryAdapters({ source: baseSource({ publicContactApproved: false }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'synced');
  const row = adapters.rows.get(ENTITY_ID).value;
  assert.equal(row.public_contact_approved, false);
  assert.equal(row.phone, null);
  assert.equal(row.whatsapp, null);
  assert.equal(row.instagram, null);
});

test('logical deletion writes a permanent versioned tombstone', async () => {
  const adapters = memoryAdapters({ source: baseSource({ deletedAt: '2026-10-20T12:01:00.000Z' }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'synced');
  assert.equal(adapters.tombstones.get(ENTITY_ID).catalogVersion, 4);
  assert.equal(adapters.tombstones.get(ENTITY_ID).outboxOperationId, OP_1);
});

test('logical deletion tombstones the ID even when legacy public fields are malformed', async () => {
  const adapters = memoryAdapters({ source: baseSource({
    category: 'legacy-unknown-category',
    name: null,
    deletedAt: '2026-10-20T12:01:00.000Z',
  }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'synced');
  assert.equal(adapters.tombstones.get(ENTITY_ID).catalogVersion, 4);
});

test('impossible deletion timestamps are rejected without creating a tombstone', async () => {
  const adapters = memoryAdapters({ source: baseSource({ deletedAt: '2026-02-30T12:00:00.000Z' }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'dead_letter');
  assert.equal(adapters.tombstones.has(ENTITY_ID), false);
  assert.equal(adapters.writes.length, 0);
});

test('impossible expiration timestamps are rejected instead of normalized', async () => {
  const adapters = memoryAdapters({ source: baseSource({ expiresAt: '2026-02-30T12:00:00.000Z' }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'dead_letter');
  assert.equal(adapters.writes.length, 0);
});

test('a later canonical version supersedes an older event without writing', async () => {
  const adapters = memoryAdapters({ source: baseSource({ catalogVersion: 5, outboxOperationId: OP_2 }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'superseded');
  assert.equal(adapters.events.get(OP_1).state, 'superseded');
  assert.equal(adapters.writes.length, 0);
});

test('same version with a different operation is dead-lettered as inconsistent', async () => {
  const adapters = memoryAdapters({ source: baseSource({ outboxOperationId: OP_2 }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'dead_letter');
  assert.equal(adapters.events.get(OP_1).lastErrorCode, 'event_inconsistent');
  assert.equal(adapters.writes.length, 0);
});

test('canonical source behind the event is dead-lettered without publication', async () => {
  const adapters = memoryAdapters({ source: baseSource({ catalogVersion: 3 }) });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'dead_letter');
  assert.equal(adapters.events.get(OP_1).lastErrorCode, 'event_inconsistent');
  assert.equal(adapters.writes.length, 0);
});

test('malformed operation IDs are dead-lettered before reaching the V2 catalog adapter', async () => {
  const invalidId = 'not-a-sql-uuid';
  const adapters = memoryAdapters({
    event: baseEvent({ operationId: invalidId }),
    source: baseSource({ outboxOperationId: invalidId }),
  });
  const result = await protocol(adapters).processOnce(invalidId, 'worker-a');
  assert.equal(result.state, 'dead_letter');
  assert.equal(adapters.events.get(invalidId).lastErrorCode, 'event_inconsistent');
  assert.equal(adapters.writes.length, 0);
});

test('two workers racing for one pending event produce exactly one lease holder', async () => {
  const adapters = memoryAdapters();
  const processor = protocol(adapters);
  const claims = await Promise.all([
    processor.acquireLease(OP_1, 'worker-a'),
    processor.acquireLease(OP_1, 'worker-b'),
  ]);
  assert.equal(claims.filter((claim) => claim.acquired).length, 1);
  assert.equal(claims.filter((claim) => claim.reason === 'busy').length, 1);
  assert.equal(adapters.events.get(OP_1).attemptCount, 1);
});

test('expired lease can be recovered and the previous worker cannot renew it', async () => {
  const adapters = memoryAdapters();
  const processor = protocol(adapters);
  const first = await processor.acquireLease(OP_1, 'worker-a');
  adapters.setNow(first.leaseExpiresAt);
  const second = await processor.acquireLease(OP_1, 'worker-b');
  assert.equal(second.acquired, true);
  assert.equal(await processor.renewLease(first, 100), false);
  assert.equal(adapters.events.get(OP_1).workerId, 'worker-b');
});

test('the current lease may renew only when token, owner, state, and version still match', async () => {
  const adapters = memoryAdapters();
  const processor = protocol(adapters);
  const lease = await processor.acquireLease(OP_1, 'worker-a');
  assert.equal(await processor.renewLease(lease, 200), true);
  assert.equal(adapters.events.get(OP_1).leaseExpiresAt, adapters.getNow() + 200);
  assert.equal(await processor.renewLease({ ...lease, leaseToken: 'wrong-lease-token-0000' }, 200), false);
  assert.equal(await processor.renewLease({ ...lease, expectedVersion: 5 }, 200), false);
});

test('interrupted processing is reclaimed after expiry and can finish idempotently', async () => {
  const adapters = memoryAdapters();
  const processor = protocol(adapters);
  const abandoned = await processor.acquireLease(OP_1, 'worker-a');
  adapters.setNow(abandoned.leaseExpiresAt + 1);
  const result = await processor.processOnce(OP_1, 'worker-b');
  assert.equal(result.state, 'synced');
  assert.equal(adapters.events.get(OP_1).attemptCount, 2);
});

test('retryable failure schedules bounded exponential backoff with a sanitized code', async () => {
  const adapters = memoryAdapters();
  adapters.canonical.get = async () => { throw Object.assign(new Error('private raw response'), { code: 'firestore_unavailable' }); };
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  const event = adapters.events.get(OP_1);
  assert.equal(result.state, 'pending');
  assert.equal(event.lastErrorCode, 'firestore_unavailable');
  assert.equal(event.nextAttemptAt, 1_010);
  assert.equal(JSON.stringify(event).includes('private raw response'), false);
  assert.equal(await protocol(adapters).processOnce(OP_1, 'worker-b').then((value) => value.reason), 'retry_scheduled');
});

test('retries cap their delay and dead-letter after the configured attempt budget', async () => {
  const adapters = memoryAdapters();
  adapters.canonical.get = async () => { throw Object.assign(new Error('secret'), { code: 'unlisted-sensitive-code' }); };
  const processor = protocol(adapters, { retryPolicy: { baseDelayMs: 10, maximumDelayMs: 25, maxAttempts: 3 } });
  assert.equal((await processor.processOnce(OP_1, 'worker-a')).state, 'pending');
  adapters.setNow(1_010);
  assert.equal((await processor.processOnce(OP_1, 'worker-a')).state, 'pending');
  assert.equal(adapters.events.get(OP_1).nextAttemptAt, 1_030);
  adapters.setNow(1_030);
  assert.equal((await processor.processOnce(OP_1, 'worker-a')).state, 'dead_letter');
  assert.equal(adapters.events.get(OP_1).lastErrorCode, 'unknown_transient');
});

test('terminal adapter failures dead-letter immediately without storing raw errors', async () => {
  const adapters = memoryAdapters();
  adapters.canonical.get = async () => { throw Object.assign(new Error('private document'), { permanent: true }); };
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'dead_letter');
  assert.equal(adapters.events.get(OP_1).lastErrorCode, 'permanent_failure');
  assert.equal(JSON.stringify(adapters.events.get(OP_1)).includes('private document'), false);
});

test('catalog write failure retries and never marks the event synced', async () => {
  const adapters = memoryAdapters();
  adapters.catalog.applyProjection = async () => { throw Object.assign(new Error('database message'), { code: 'catalog_unavailable' }); };
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'pending');
  assert.equal(adapters.events.get(OP_1).state, 'pending');
  assert.equal(adapters.events.get(OP_1).lastErrorCode, 'catalog_unavailable');
});

test('confirmed catalog write followed by lost acknowledgement is safely replayed', async () => {
  const adapters = memoryAdapters();
  const processor = protocol(adapters);
  adapters.failNextTransition(new Error('private ack response'));
  const first = await processor.processOnce(OP_1, 'worker-a');
  assert.equal(first.state, 'ack_pending');
  assert.equal(adapters.events.get(OP_1).state, 'processing');
  adapters.setNow(adapters.events.get(OP_1).leaseExpiresAt + 1);
  const second = await processor.processOnce(OP_1, 'worker-b');
  assert.equal(second.state, 'synced');
  assert.equal(adapters.writes.length, 1);
  assert.equal(adapters.events.get(OP_1).attemptCount, 2);
});

test('repeated acknowledgement failures are bounded and eventually dead-lettered', async () => {
  const adapters = memoryAdapters({ beforeTransition: async (_id, transition) => {
    if (transition.patch.state === 'synced') throw new Error('raw acknowledgement detail');
  } });
  const processor = protocol(adapters);
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    assert.equal((await processor.processOnce(OP_1, 'worker-a')).state, 'ack_pending');
    adapters.setNow(adapters.events.get(OP_1).leaseExpiresAt + 1);
  }
  assert.equal((await processor.processOnce(OP_1, 'worker-b')).state, 'dead_letter');
  assert.equal(adapters.events.get(OP_1).lastErrorCode, 'retry_exhausted');
  assert.equal(adapters.writes.length, 1);
  assert.equal(JSON.stringify(adapters.events.get(OP_1)).includes('raw acknowledgement detail'), false);
});

test('a worker whose lease expired during the catalog write cannot acknowledge', async () => {
  let adapters;
  adapters = memoryAdapters({ beforeTransition: async (_id, transition) => {
    if (transition.patch.state === 'synced') adapters.setNow(transition.now + 101);
  } });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-a');
  assert.equal(result.state, 'lease_lost');
  assert.equal(adapters.events.get(OP_1).state, 'processing');
  assert.equal(adapters.writes.length, 1);
});

test('replay of a terminal synced event does not write twice', async () => {
  const adapters = memoryAdapters();
  const processor = protocol(adapters);
  assert.equal((await processor.processOnce(OP_1, 'worker-a')).state, 'synced');
  const duplicate = await processor.processOnce(OP_1, 'worker-b');
  assert.equal(duplicate.reason, 'terminal');
  assert.equal(adapters.writes.length, 1);
});

test('a stale upsert cannot replace a versioned tombstone in the simulated catalog', async () => {
  const adapters = memoryAdapters({ source: baseSource({ deletedAt: '2026-10-20T12:01:00.000Z' }) });
  await protocol(adapters).processOnce(OP_1, 'worker-a');
  const stale = await adapters.catalog.applyProjection({
    id: ENTITY_ID, name: 'Stale', catalog_version: 3, outbox_operation_id: 'older-operation',
  });
  assert.equal(stale.result, 'stale');
  const attemptedResurrection = await adapters.catalog.applyProjection({
    id: ENTITY_ID, name: 'Must remain deleted', catalog_version: 5,
    outbox_operation_id: OP_2, deleted_at: null,
  });
  assert.equal(attemptedResurrection.result, 'tombstoned');
  assert.notEqual(adapters.rows.get(ENTITY_ID).value.name, 'Must remain deleted');
  assert.equal(adapters.tombstones.get(ENTITY_ID).catalogVersion, 4);
});

test('public state names expose the five documented lifecycle states', () => {
  assert.deepEqual([...OUTBOX_STATES], ['pending', 'processing', 'synced', 'superseded', 'dead_letter']);
});

test('legacy V1 event remains eligible when lease and retry lifecycle fields are absent', async () => {
  const event = baseEvent();
  for (const key of ['workerId', 'leaseToken', 'leaseExpiresAt', 'nextAttemptAt', 'lastErrorCode', 'syncedAt']) {
    delete event[key];
  }
  const adapters = memoryAdapters({ event });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-v1');
  assert.equal(result.state, 'synced');
  assert.equal(adapters.events.get(OP_1).state, 'synced');
  assert.equal(adapters.writes.length, 1);
});

test('complete V2 pending event is claimed, projected, and acknowledged with lifecycle fields retained', async () => {
  const adapters = memoryAdapters({ event: baseV2Event() });
  const result = await protocol(adapters).processOnce(OP_1, 'worker-v2');
  const event = adapters.events.get(OP_1);
  assert.equal(result.state, 'synced');
  assert.equal(event.schemaVersion, 2);
  assert.equal(event.state, 'synced');
  assert.equal(event.workerId, null);
  assert.equal(event.leaseToken, null);
  assert.equal(event.leaseExpiresAt, null);
  assert.equal(event.nextAttemptAt, null);
  assert.equal(event.lastErrorCode, null);
  assert.ok(event.syncedAt instanceof Date);
  assert.equal(adapters.writes.length, 1);
});

test('V2 rejects each missing lifecycle field before claiming or publishing', async () => {
  for (const key of ['workerId', 'leaseToken', 'leaseExpiresAt', 'nextAttemptAt', 'lastErrorCode', 'syncedAt']) {
    const event = baseV2Event();
    delete event[key];
    const adapters = memoryAdapters({ event });
    const result = await protocol(adapters).processOnce(OP_1, 'worker-v2');
    assert.deepEqual(result, { state: 'not_processed', reason: 'invalid_event' }, `missing ${key}`);
    assert.equal(adapters.events.get(OP_1).state, 'pending', `state changed for missing ${key}`);
    assert.equal(adapters.writes.length, 0, `catalog write occurred for missing ${key}`);
  }
});

test('V2 rejects malformed lifecycle types and unknown schema versions before side effects', async () => {
  for (const overrides of [
    { workerId: 17 },
    { leaseToken: '' },
    { leaseExpiresAt: 'not-a-timestamp' },
    { nextAttemptAt: 'not-a-timestamp' },
    { lastErrorCode: 'raw-secret-error' },
    { syncedAt: 'not-a-timestamp' },
    { schemaVersion: 3 },
    { unexpectedPrivateField: 'must-not-be-accepted' },
    { attemptCount: 1 },
    { nextAttemptAt: new Date('2026-10-20T12:00:00.000Z'), lastErrorCode: 'catalog_unavailable' },
    { state: 'synced' },
    { state: 'dead_letter' },
  ]) {
    const event = baseV2Event(overrides);
    const initialState = event.state;
    const adapters = memoryAdapters({ event });
    const result = await protocol(adapters).processOnce(OP_1, 'worker-v2');
    assert.equal(result.reason, 'invalid_event', JSON.stringify(Object.keys(overrides)));
    assert.equal(adapters.writes.length, 0);
    assert.equal(adapters.events.get(OP_1).state, initialState);
  }
});

test('V2 retries preserve timestamp semantics and never store raw failures', async () => {
  const adapters = memoryAdapters({ event: baseV2Event() });
  adapters.canonical.get = async () => { throw Object.assign(new Error('private response body'), { code: 'catalog_unavailable' }); };
  const result = await protocol(adapters).processOnce(OP_1, 'worker-v2');
  const event = adapters.events.get(OP_1);
  assert.equal(result.state, 'pending');
  assert.equal(event.state, 'pending');
  assert.equal(event.lastErrorCode, 'catalog_unavailable');
  assert.equal(event.nextAttemptAt.getTime(), 1_010);
  assert.equal(event.workerId, null);
  assert.equal(event.leaseToken, null);
  assert.equal(event.leaseExpiresAt, null);
  assert.equal(JSON.stringify(event).includes('private response body'), false);
});

test('V2 accepts Firestore Timestamp-shaped values and rejects ISO strings in timestamp fields', async () => {
  const firestoreTimestamp = { seconds: 1_792_500_000, nanoseconds: 123_000_000 };
  const valid = memoryAdapters({ event: baseV2Event({ createdAt: firestoreTimestamp, updatedAt: firestoreTimestamp }) });
  assert.equal((await protocol(valid).processOnce(OP_1, 'worker-v2')).state, 'synced');

  const invalid = memoryAdapters({ event: baseV2Event({ createdAt: '2026-10-20T12:00:00.000Z' }) });
  const result = await protocol(invalid).processOnce(OP_1, 'worker-v2');
  assert.deepEqual(result, { state: 'not_processed', reason: 'invalid_event' });
  assert.equal(invalid.writes.length, 0);
});

test('V2 preserves reversible unpublish and permanent tombstone semantics', async () => {
  const unpublished = memoryAdapters({
    event: baseV2Event(),
    source: baseSource({ published: false, active: false }),
  });
  assert.equal((await protocol(unpublished).processOnce(OP_1, 'worker-v2')).state, 'synced');
  assert.equal(unpublished.rows.get(ENTITY_ID).value.published, false);
  assert.equal(unpublished.rows.get(ENTITY_ID).value.deleted_at, null);
  assert.equal(unpublished.tombstones.has(ENTITY_ID), false);

  const deleted = memoryAdapters({
    event: baseV2Event(),
    source: baseSource({ deletedAt: '2026-10-20T12:01:00.000Z' }),
  });
  assert.equal((await protocol(deleted).processOnce(OP_1, 'worker-v2')).state, 'synced');
  assert.equal(deleted.tombstones.get(ENTITY_ID).catalogVersion, 4);
});

test('V2 expired lease is recoverable, while a delayed version cannot overwrite canonical state', async () => {
  const processingEvent = baseV2Event({
    state: 'processing',
    attemptCount: 1,
    workerId: 'worker-old',
    leaseToken: 'lease-token-from-old-worker',
    leaseExpiresAt: new Date(1_100),
  });
  const adapters = memoryAdapters({ event: processingEvent, now: 1_000 });
  const processor = protocol(adapters);
  assert.equal((await processor.processOnce(OP_1, 'worker-new')).reason, 'busy');
  adapters.setNow(1_101);
  const recovered = await processor.processOnce(OP_1, 'worker-new');
  assert.equal(recovered.state, 'synced');
  assert.equal(adapters.events.get(OP_1).attemptCount, 2);
  assert.equal(adapters.writes.length, 1);

  const stale = memoryAdapters({
    event: baseV2Event(),
    source: baseSource({ catalogVersion: 5, outboxOperationId: OP_2 }),
  });
  assert.equal((await protocol(stale).processOnce(OP_1, 'worker-v2')).state, 'superseded');
  assert.equal(stale.writes.length, 0);
});

test('V2 retries a confirmed write after lost acknowledgement idempotently', async () => {
  const adapters = memoryAdapters({ event: baseV2Event() });
  const processor = protocol(adapters);
  adapters.failNextTransition(new Error('private acknowledgement detail'));
  assert.equal((await processor.processOnce(OP_1, 'worker-a')).state, 'ack_pending');
  assert.equal(adapters.events.get(OP_1).state, 'processing');
  adapters.setNow(adapters.events.get(OP_1).leaseExpiresAt.getTime() + 1);
  assert.equal((await processor.processOnce(OP_1, 'worker-b')).state, 'synced');
  assert.equal(adapters.events.get(OP_1).attemptCount, 2);
  assert.equal(adapters.writes.length, 1);
});

test('V2 concurrent processing has one lease holder and terminal replay performs no second write', async () => {
  const adapters = memoryAdapters({ event: baseV2Event() });
  const processor = protocol(adapters);
  const results = await Promise.all([
    processor.processOnce(OP_1, 'worker-a'),
    processor.processOnce(OP_1, 'worker-b'),
  ]);
  assert.equal(results.filter((result) => result.state === 'synced').length, 1);
  assert.equal(results.filter((result) => result.reason === 'busy').length, 1);
  assert.equal(adapters.writes.length, 1);
  const replay = await processor.processOnce(OP_1, 'worker-c');
  assert.equal(replay.reason, 'terminal');
  assert.equal(adapters.writes.length, 1);
});
