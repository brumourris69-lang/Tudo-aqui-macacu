'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  catalog,
  documentId,
  draftDocument,
  flattenCatalog,
  planImport,
  runImport,
  validateCatalog,
} = require('./import-explorar-macacu.cjs');

function fakeDb(initial = []) {
  const documents = new Map(initial.map(([id, data]) => [id, structuredClone(data)]));
  let committedBatches = 0;
  const db = {
    collection(name) {
      assert.equal(name, 'routes');
      return {
        async get() {
          return {
            docs: [...documents].map(([id, data]) => ({ id, data: () => data })),
          };
        },
        doc(id) { return { id }; },
      };
    },
    batch() {
      const creates = [];
      return {
        create(ref, data) { creates.push([ref.id, structuredClone(data)]); },
        async commit() {
          if (creates.some(([id]) => documents.has(id))) {
            throw new Error('already exists');
          }
          for (const [id, data] of creates) documents.set(id, data);
          committedBatches += 1;
        },
      };
    },
  };
  return { db, documents, batchCount: () => committedBatches };
}

test('catalog has exactly 65 unique attractions in six requested categories', () => {
  const items = validateCatalog();
  assert.equal(items.length, 65);
  assert.deepEqual(catalog.categories.map((category) => [category.key, category.items.length]), [
    ['cachoeiras_pocos_lagoas', 36],
    ['trilhas_montanhas', 7],
    ['parques_reservas', 6],
    ['historia_cultura', 10],
    ['roteiros_turisticos', 5],
    ['mirantes', 1],
  ]);
  assert.equal(new Set(items.map((item) => item.id)).size, 65);
  assert.equal(items[0].id, documentId('cachoeiras_pocos_lagoas', 'Cachoeira das Sete Quedas'));
});

test('catalog preserves only the two source-provided waterfall subgroups', () => {
  const items = flattenCatalog();
  const waterItems = items.filter((item) => item.category === 'cachoeiras_pocos_lagoas');
  assert.equal(waterItems.filter((item) => item.subcategory === 'Cachoeiras').length, 22);
  assert.equal(waterItems.filter((item) => item.subcategory === 'Poços e lagoas').length, 14);
  assert.ok(items.filter((item) => item.category !== 'cachoeiras_pocos_lagoas')
    .every((item) => item.subcategory === undefined));
});

test('draft documents contain no invented access, location, description or media data', () => {
  for (const item of flattenCatalog()) {
    const draft = draftDocument(item);
    assert.equal(draft.published, false);
    assert.equal(draft.active, false);
    assert.equal(draft.deleted, false);
    assert.equal(draft.iconKey, 'turismo');
    assert.equal('description' in draft, false);
    assert.equal('location' in draft, false);
    assert.equal('maps' in draft, false);
    assert.equal('imageUrl' in draft, false);
    assert.equal('galleryUrls' in draft, false);
  }
});

test('create-only import adds absent items and repeat import does not overwrite', async () => {
  const fake = fakeDb([
    ['existing-curated', { title: 'Poço Samambaia', description: 'Preservar este conteúdo' }],
  ]);
  const first = await runImport({
    db: fake.db,
    fieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' },
  });
  assert.equal(first.catalogCount, 65);
  assert.equal(first.created, 64);
  assert.equal(first.alreadyPresent, 1);
  assert.equal(fake.documents.get('existing-curated').description, 'Preservar este conteúdo');
  assert.equal([...fake.documents.values()].filter((data) => data.published === false && data.active === false).length, 64);
  assert.equal(fake.batchCount(), 1);

  const second = await runImport({
    db: fake.db,
    fieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' },
  });
  assert.equal(second.created, 0);
  assert.equal(second.alreadyPresent, 65);
  assert.equal(fake.batchCount(), 1);
});

test('same deterministic ID with a different title stops before any write', async () => {
  const first = flattenCatalog()[0];
  const fake = fakeDb([[first.id, { title: 'Outro conteúdo' }]]);
  await assert.rejects(() => runImport({
    db: fake.db,
    fieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' },
  }), /ID collision/);
  assert.equal(fake.batchCount(), 0);
  assert.equal(fake.documents.size, 1);
});
