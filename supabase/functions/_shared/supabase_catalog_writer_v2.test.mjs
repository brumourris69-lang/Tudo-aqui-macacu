import assert from 'node:assert/strict';
import test from 'node:test';
import { createSupabaseCatalogWriterV2 } from './supabase_catalog_writer_v2.mjs';

const projection = {
  id: 'modelo-public-01', content_kind: 'establishment', category_group: 'commerce',
  name: 'Loja de Teste', summary: '', category: 'Comércio', subcategory: '', location: null,
  artwork: 0, image_url: '', logo_url: '', gallery_urls: [], featured: false, is_open: true,
  maps_url: '', hours: '', services: [], products: [], additional_info: '', promotion_title: '',
  promotion_description: '', public_contact_approved: false, phone: null, whatsapp: null,
  instagram: null, published: true, active: true, expires_at: null, deleted_at: null,
  catalog_version: 1, outbox_operation_id: '00000000-0000-4000-8000-000000000001',
};

test('projection and tombstone call only their fixed private V2 RPCs', async () => {
  const calls = [];
  const writer = createSupabaseCatalogWriterV2({ rpc: async (...args) => { calls.push(args); return { data: 'applied', error: null }; } });
  assert.deepEqual(await writer.applyProjection(projection), { result: 'applied' });
  assert.deepEqual(await writer.applyTombstone({
    id: projection.id, catalog_version: 2, outbox_operation_id: projection.outbox_operation_id,
    deleted_at: '2026-10-20T12:00:00.000Z',
  }), { result: 'applied' });
  assert.equal(calls[0][0], 'apply_establishment_projection_v2');
  assert.deepEqual(Object.keys(calls[0][1]), ['p_projection']);
  assert.equal(calls[1][0], 'apply_establishment_tombstone_v2');
  assert.deepEqual(Object.keys(calls[1][1]), ['p_tombstone']);
});

test('writer accepts only the explicit public projection contract', async () => {
  let calls = 0;
  const writer = createSupabaseCatalogWriterV2({ rpc: async () => { calls++; return { data: 'applied', error: null }; } });
  await assert.rejects(writer.applyProjection({ ...projection, adminNote: 'private' }), { code: 'invalid_projection' });
  await assert.rejects(writer.applyProjection({ ...projection, deleted_at: '2026-10-20T12:00:00.000Z' }), { code: 'invalid_projection' });
  assert.equal(calls, 0);
});

test('SQL replay is reported as duplicate and conflicts are sanitized', async () => {
  const replay = createSupabaseCatalogWriterV2({ rpc: async () => ({ data: 'replayed', error: null }) });
  assert.deepEqual(await replay.applyProjection(projection), { result: 'duplicate' });
  const conflict = createSupabaseCatalogWriterV2({ rpc: async () => ({ data: null, error: { code: '23514', message: 'sensitive database text' } }) });
  assert.deepEqual(await conflict.applyProjection(projection), { result: 'conflict' });
});

test('writer preserves sanitized conflict and permanent-failure codes from REST adapters', async () => {
  const conflict = createSupabaseCatalogWriterV2({
    rpc: async () => { throw Object.assign(new Error('do not expose'), { code: 'catalog_conflict' }); },
  });
  assert.deepEqual(await conflict.applyProjection(projection), { result: 'conflict' });
  const permanent = createSupabaseCatalogWriterV2({
    rpc: async () => { throw Object.assign(new Error('do not expose'), { code: 'permanent_failure' }); },
  });
  await assert.rejects(permanent.applyProjection(projection),
    (error) => error.code === 'permanent_failure' && !error.message.includes('expose'));
});

test('writer sanitizes transient and invalid-projection errors without retaining messages', async () => {
  const transient = createSupabaseCatalogWriterV2({ rpc: async () => { throw Object.assign(new Error('secret body'), { code: 'ECONNRESET' }); } });
  await assert.rejects(transient.applyProjection(projection), (error) => error.code === 'catalog_unavailable' && !error.message.includes('secret'));
  const invalid = createSupabaseCatalogWriterV2({ rpc: async () => ({ data: null, error: { code: '22023', message: 'do not copy' } }) });
  await assert.rejects(invalid.applyProjection(projection), (error) => error.code === 'permanent_failure' && !error.message.includes('copy'));
});

test('unknown RPC results fail closed instead of acknowledging a write', async () => {
  const writer = createSupabaseCatalogWriterV2({ rpc: async () => ({ data: 'unexpected', error: null }) });
  assert.deepEqual(await writer.applyProjection(projection), { result: 'invalid' });
});
