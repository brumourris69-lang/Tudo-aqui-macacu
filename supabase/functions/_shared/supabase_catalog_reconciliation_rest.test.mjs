import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createSupabaseCatalogReconciliationRpcClient,
  SupabaseCatalogReconciliationRpcError,
} from './supabase_catalog_reconciliation_rest.mjs';

const SNAPSHOT = '60000000-0000-4000-8000-000000000001';
const OPERATION = '60000000-0000-4000-8000-000000000002';
const ID = 'modelo-reconciliation-legacy';
const CAPTURED = '2026-10-21T10:00:00.000Z';
const EXPIRES = '2026-10-21T11:00:00.000Z';

test('begin snapshot calls only the private fixed RPC with the caller snapshot UUID', async () => {
  const calls = [];
  const client = makeClient(async (url, init) => {
    calls.push({ url, init });
    return jsonResponse(snapshotHeader());
  });

  assert.deepEqual(await client.beginSnapshot(SNAPSHOT), snapshotHeader());
  assert.equal(calls[0].url, 'http://127.0.0.1:25432/rest/v1/rpc/begin_catalog_reconciliation_snapshot_v2');
  assert.equal(calls[0].init.method, 'POST');
  assert.deepEqual(JSON.parse(calls[0].init.body), { p_snapshot_id: SNAPSHOT });
});

test('read page sends bounded cursor arguments and accepts only explicit catalog/tombstone fields', async () => {
  const payload = pageResult({
    catalog_rows: [catalogRow()],
    tombstones: [tombstone()],
    next_cursor: ID,
    done: true,
  });
  const calls = [];
  const client = makeClient(async (url, init) => {
    calls.push({ url, init });
    return jsonResponse(payload);
  });

  assert.deepEqual(await client.readPage({ snapshotId: SNAPSHOT, afterId: 'legacy-a', limit: 50 }), payload);
  assert.equal(calls[0].url, 'http://127.0.0.1:25432/rest/v1/rpc/read_catalog_reconciliation_page_v2');
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    p_snapshot_id: SNAPSHOT, p_after_id: 'legacy-a', p_page_size: 50,
  });
  assert.equal(JSON.stringify(payload).includes('search_document'), false);
  assert.equal(JSON.stringify(payload).includes('ownerEmail'), false);
});

test('dispose is idempotent and uses only its exact argument', async () => {
  const calls = [];
  const client = makeClient(async (url, init) => {
    calls.push({ url, init });
    return jsonResponse(true);
  });

  assert.equal(await client.disposeSnapshot(SNAPSHOT), true);
  assert.match(calls[0].url, /rpc\/dispose_catalog_reconciliation_snapshot_v2$/u);
  assert.deepEqual(JSON.parse(calls[0].init.body), { p_snapshot_id: SNAPSHOT });
});

test('rejects arbitrary RPC names, malformed snapshot IDs, cursors, page sizes, and extra arguments', async () => {
  const client = makeClient(async () => jsonResponse(pageResult()));
  await assert.rejects(client.rpc('apply_establishment_projection_v2', {}), { code: 'invalid_snapshot' });
  await assert.rejects(client.beginSnapshot('not-a-uuid'), { code: 'invalid_snapshot' });
  await assert.rejects(client.readPage({ snapshotId: SNAPSHOT, afterId: '../escape', limit: 10 }), { code: 'invalid_snapshot' });
  await assert.rejects(client.readPage({ snapshotId: SNAPSHOT, afterId: null, limit: 201 }), { code: 'invalid_snapshot' });
  await assert.rejects(client.rpc('read_catalog_reconciliation_page_v2', {
    p_snapshot_id: SNAPSHOT, p_after_id: null, p_page_size: 10, p_extra: 'x',
  }), { code: 'invalid_snapshot' });
});

test('maps only known expired and invalid snapshot SQL states to sanitized errors', async () => {
  const expired = makeClient(async () => jsonResponse({ code: '55000', message: 'sensitive database detail' }, 409));
  const invalid = makeClient(async () => jsonResponse({ code: '22023', message: 'raw input echo' }, 400));
  await assert.rejects(expired.readPage({ snapshotId: SNAPSHOT, afterId: null, limit: 10 }), (error) => {
    assert.equal(error.code, 'snapshot_expired');
    assert.equal(error.message.includes('sensitive'), false);
    return true;
  });
  await assert.rejects(invalid.beginSnapshot(SNAPSHOT), (error) => {
    assert.equal(error.code, 'invalid_snapshot');
    assert.equal(error.message.includes('raw input'), false);
    return true;
  });
});

test('rejects malformed result shapes and rows with private/internal fields', async () => {
  for (const value of [
    { ...pageResult(), catalog_rows: [{ ...catalogRow(), search_document: 'SECRET' }] },
    { ...pageResult(), tombstones: [{ ...tombstone(), private_note: 'SECRET' }] },
    { ...pageResult(), next_cursor: 'wrong-id' },
    { ...pageResult(), snapshot_id: '60000000-0000-4000-8000-000000000099' },
  ]) {
    const client = makeClient(async () => jsonResponse(value));
    await assert.rejects(client.readPage({ snapshotId: SNAPSHOT, afterId: null, limit: 10 }), {
      code: 'catalog_unavailable',
    });
  }
});

test('bounds response bytes and maps transport failures without exposing upstream details', async () => {
  const oversized = makeClient(async () => jsonResponse('x'.repeat(5000)), { maxResponseBytes: 1024 });
  const failed = makeClient(async () => { throw new Error('credential or URL leaked'); });
  await assert.rejects(oversized.beginSnapshot(SNAPSHOT), { code: 'catalog_unavailable' });
  await assert.rejects(failed.beginSnapshot(SNAPSHOT), (error) => {
    assert.equal(error.code, 'catalog_unavailable');
    assert.equal(error.message.includes('credential'), false);
    return true;
  });
});

test('requires HTTPS outside loopback and never permits credentials embedded in the URL', () => {
  assert.throws(() => createSupabaseCatalogReconciliationRpcClient({
    url: 'http://example.invalid/', apiKey: 'x'.repeat(40), fetchImpl: async () => jsonResponse({}),
  }), SupabaseCatalogReconciliationRpcError);
  assert.throws(() => createSupabaseCatalogReconciliationRpcClient({
    url: 'http://name:password@127.0.0.1/', apiKey: 'x'.repeat(40), fetchImpl: async () => jsonResponse({}),
  }), SupabaseCatalogReconciliationRpcError);
});

function makeClient(fetchImpl, overrides = {}) {
  return createSupabaseCatalogReconciliationRpcClient({
    url: 'http://127.0.0.1:25432/', apiKey: 'synthetic-server-key-'.padEnd(40, 'x'),
    fetchImpl, timeoutMs: 500, ...overrides,
  });
}

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function snapshotHeader() {
  return {
    snapshot_id: SNAPSHOT, captured_at: CAPTURED, expires_at: EXPIRES,
    entity_count: 2, payload_bytes: 800, replayed: false,
  };
}

function pageResult(overrides = {}) {
  return {
    snapshot_id: SNAPSHOT, captured_at: CAPTURED, expires_at: EXPIRES,
    next_cursor: null, done: true, catalog_rows: [], tombstones: [], ...overrides,
  };
}

function catalogRow() {
  return {
    id: ID, content_kind: 'establishment', category_group: 'commerce', name: 'Fixture Market',
    summary: 'Synthetic public summary', category: 'Comércio', subcategory: 'Market',
    location: 'Cachoeiras de Macacu', artwork: 0, image_url: '', logo_url: '', gallery_urls: [],
    featured: false, is_open: true, maps_url: '', hours: '', services: [], products: [],
    additional_info: '', promotion_title: '', promotion_description: '', public_contact_approved: false,
    phone: null, whatsapp: null, instagram: null, published: false, active: true,
    expires_at: null, deleted_at: null, catalog_version: 2, outbox_operation_id: OPERATION,
  };
}

function tombstone() {
  return { id: ID, catalog_version: 3, outbox_operation_id: OPERATION, tombstoned_at: CAPTURED };
}
