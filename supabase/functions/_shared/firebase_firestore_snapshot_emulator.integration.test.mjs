import assert from 'node:assert/strict';
import test from 'node:test';
import { createFirebaseFirestoreRestStore } from './firebase_firestore_rest.mjs';

const PROJECT = 'demo-universal-search';
const DATABASE = '(default)';
const PREFIX = `projects/${PROJECT}/databases/${DATABASE}/documents`;
const FIXTURE_IDS = ['legacy-a', 'legacy-é', '\uE000', '\u{10000}'];
const LATE_ID = 'z-late-after-snapshot';

test('Firestore Emulator snapshot paging preserves legacy IDs, readTime, ordering, and public-only fields', {
  skip: process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:18087',
}, async () => {
  const base = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/${PREFIX}`;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT,
    emulator: { host: '127.0.0.1', port: 18087 },
  });
  await commit(FIXTURE_IDS.map((id, index) => ({
    update: {
      name: `${PREFIX}/establishments/${id}`,
      fields: {
        name: { stringValue: `Fixture ${index}` },
        category: { stringValue: 'Comércio' },
        published: { booleanValue: true },
        active: { booleanValue: true },
        catalogVersion: { integerValue: '1' },
        outboxOperationId: { stringValue: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}` },
        publicContactApproved: { booleanValue: false },
        phone: { stringValue: 'synthetic-private-contact' },
        ownerEmail: { stringValue: 'fixture@example.invalid' },
      },
    },
  })));

  try {
    const first = await store.queryEstablishmentsSnapshotPage({ limit: 2 });
    assert.equal(typeof first.readTime, 'string');
    assert.equal(first.documents.length, 2);
    await commit([{ update: {
      name: `${PREFIX}/establishments/${LATE_ID}`,
      fields: { name: { stringValue: 'Must not enter the pinned snapshot' } },
    } }]);

    const observed = [...first.documents];
    let cursor = first.documents.at(-1).id;
    let page = first;
    for (let iteration = 0; page.hasMore && iteration < 5; iteration += 1) {
      page = await store.queryEstablishmentsSnapshotPage({
        limit: 2, readTime: first.readTime, startAfterDocumentId: cursor,
      });
      assert.equal(page.readTime, first.readTime);
      observed.push(...page.documents);
      if (page.documents.length > 0) cursor = page.documents.at(-1).id;
    }

    assert.deepEqual(observed.map(({ id }) => id), [...FIXTURE_IDS].sort(compareCodePoints));
    assert.equal(observed.some(({ id }) => id === LATE_ID), false);
    assert.equal(JSON.stringify(observed).includes('synthetic-private-contact'), false);
    assert.equal(JSON.stringify(observed).includes('fixture@example.invalid'), false);
    assert.ok(observed.every(({ data }) => data.publicContactApproved === false && !Object.hasOwn(data, 'phone')));
    assert.equal(observed.some(({ id }) => id === '\uE000'), true);
    assert.equal(observed.some(({ id }) => id === '\u{10000}'), true);
  } finally {
    await commit([...FIXTURE_IDS, LATE_ID].map((id) => ({ delete: `${PREFIX}/establishments/${id}` })));
  }

  async function commit(writes) {
    const response = await fetch(`${base}:commit`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ writes }),
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) throw new Error('Local Firestore fixture operation failed.');
  }
});

function compareCodePoints(left, right) {
  const a = Array.from(left, (character) => character.codePointAt(0));
  const b = Array.from(right, (character) => character.codePointAt(0));
  for (let index = 0; index < Math.min(a.length, b.length); index += 1) {
    if (a[index] !== b[index]) return a[index] - b[index];
  }
  return a.length - b.length;
}
