'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
let inventoryApi;
try { inventoryApi = require('../legacy_job_inventory'); } catch { inventoryApi = {}; }

const privateFields = ['contact', 'phone', 'whatsapp', 'link', 'instagram', 'maps', 'mapsUrl', 'additionalInfo'];

function requireInventory() {
  assert.equal(typeof inventoryApi.classifyLegacyJob, 'function', 'legacy inventory classifier must exist');
  assert.equal(typeof inventoryApi.createLegacyJobInventory, 'function', 'legacy inventory reader must exist');
}

function makeDb(jobs, privateJobs, counters = { writes: 0 }, readFailure = null) {
  const documentsFor = (values) => Object.entries(values).map(([id, data]) => ({ id, data: () => data }));
  const makeQuery = (name, values) => {
    let pageSize = 100;
    let afterId = null;
    return {
      orderBy() { return this; },
      limit(size) { pageSize = size; return this; },
      startAfter(document) { afterId = typeof document === 'string' ? document : document.id; return this; },
      async get() {
        counters.readsByCollection ??= {};
        counters.readsByCollection[name] = (counters.readsByCollection[name] || 0) + 1;
        if (readFailure?.collection === name) throw readFailure.error;
        const all = documentsFor(values).sort((a, b) => a.id.localeCompare(b.id));
        const remaining = afterId == null ? all : all.filter((document) => document.id > afterId);
        const page = remaining.slice(0, pageSize);
        return { docs: page, size: page.length };
      },
    };
  };
  const db = {
    collection(name) {
      assert.ok(name === 'jobs' || name === 'job_private', `unexpected collection ${name}`);
      if (name === 'jobs') {
        return {
          set() { counters.writes++; throw new Error('inventory must not write'); },
          update() { counters.writes++; throw new Error('inventory must not write'); },
          delete() { counters.writes++; throw new Error('inventory must not write'); },
          ...makeQuery(name, jobs),
        };
      }
      return {
        ...makeQuery(name, privateJobs),
        doc(id) {
          return {
            async get() {
              const value = privateJobs[id];
              return { exists: Object.hasOwn(privateJobs, id), data: () => value };
            },
            set() { counters.writes++; throw new Error('inventory must not write'); },
            update() { counters.writes++; throw new Error('inventory must not write'); },
            delete() { counters.writes++; throw new Error('inventory must not write'); },
          };
        },
      };
    },
  };
  return db;
}

test('inventory classifies all eight approved private administrative fields', () => {
  requireInventory();
  const jobData = Object.fromEntries(privateFields.map((field) => [field, `fictional-${field}`]));
  const result = inventoryApi.classifyLegacyJob({ jobData, privateData: null, privateExists: false });
  assert.deepEqual(result.privateFieldsPresent, privateFields);
  assert.deepEqual(result.unapprovedFields, []);
  assert.deepEqual(result.unclassifiedFields, []);
  assert.equal(result.privateDocumentMissing, true);
  assert.equal(result.manualReviewRequired, true);
  assert.equal(JSON.stringify(result).includes('fictional-'), false);
});

test('inventory separates explicitly unapproved fields from unknown fields', () => {
  requireInventory();
  const result = inventoryApi.classifyLegacyJob({
    jobData: { title: 'Fictício', salary: 'Privado', eventDate: 'ontem', date: 'ontem', mysteryField: 'não classificar' },
    privateData: {}, privateExists: true,
  });
  assert.deepEqual(result.unapprovedFields, ['date', 'eventDate', 'salary']);
  assert.deepEqual(result.unclassifiedFields, ['mysteryField']);
  assert.equal(result.manualReviewRequired, true);
});

test('inventory detects missing private documents and conflicting private fields without values', () => {
  requireInventory();
  const missing = inventoryApi.classifyLegacyJob({
    jobData: { phone: 'public-secret' }, privateData: null, privateExists: false,
  });
  const conflict = inventoryApi.classifyLegacyJob({
    jobData: { contact: 'legacy-secret' }, privateData: { contact: 'private-secret' }, privateExists: true,
  });
  assert.equal(missing.privateDocumentMissing, true);
  assert.deepEqual(conflict.conflictingPrivateFields, ['contact']);
  assert.equal(JSON.stringify([missing, conflict]).includes('secret'), false);
});

test('inventory reads jobs and private counterparts without any Firestore writes', async () => {
  requireInventory();
  const counters = { writes: 0 };
  const db = makeDb({ one: { title: 'Vaga fictícia', contact: 'fictional-contact' } }, {}, counters);
  const inventory = inventoryApi.createLegacyJobInventory({ db, FieldPath: { documentId: () => '__name__' } });
  const report = await inventory.inventoryAll();
  assert.equal(report.examined, 1);
  assert.equal(report.affected, 1);
  assert.equal(report.privateFieldCounts.contact, 1);
  assert.equal(report.missingPrivateDocuments, 1);
  assert.equal(report.manualReviewDocuments, 1);
  assert.equal(report.documents[0].jobId, 'one');
  assert.equal(counters.writes, 0);
  assert.deepEqual(counters.readsByCollection, { jobs: 1, job_private: 1 });
  assert.equal(JSON.stringify(report).includes('fictional-contact'), false);
});

test('inventory recognizes a corresponding private document without marking an otherwise clean job', async () => {
  requireInventory();
  const report = await inventoryApi.createLegacyJobInventory({
    db: makeDb({ paired: { title: 'Vaga pública fictícia', published: true } },
      { paired: { contact: 'private-only-fictional-contact' } }),
    FieldPath: { documentId: () => '__name__' },
  }).inventoryAll();
  assert.equal(report.examined, 1);
  assert.equal(report.missingPrivateDocuments, 0);
  assert.equal(report.orphanPrivateDocuments, 0);
  assert.equal(report.manualReviewDocuments, 0);
  assert.equal(JSON.stringify(report).includes('private-only-fictional-contact'), false);
});

test('inventory lists an orphan private document by ID and category without its values', async () => {
  requireInventory();
  const report = await inventoryApi.createLegacyJobInventory({
    db: makeDb({}, { orphan: { contact: 'orphan-private-secret' } }),
    FieldPath: { documentId: () => '__name__' },
  }).inventoryAll();
  assert.equal(report.orphanPrivateDocuments, 1);
  assert.deepEqual(report.orphanDocuments, [{ jobId: 'orphan', category: 'orphan-private-document' }]);
  assert.equal(JSON.stringify(report).includes('orphan-private-secret'), false);
});

test('inventory scans both collections completely in stable pages without per-document rereads', async () => {
  requireInventory();
  const counters = { writes: 0 };
  const jobs = {
    jobA: { title: 'Vaga A', published: true },
    jobB: { title: 'Vaga B', published: true },
    jobC: { title: 'Vaga C', published: true },
  };
  const privateJobs = {
    jobA: { contact: 'private-a' },
    jobB: { contact: 'private-b' },
    orphan: { contact: 'private-orphan' },
  };
  const report = await inventoryApi.createLegacyJobInventory({
    db: makeDb(jobs, privateJobs, counters),
    FieldPath: { documentId: () => '__name__' },
    pageSize: 2,
  }).inventoryAll();
  assert.equal(report.examined, 3);
  assert.equal(report.orphanPrivateDocuments, 1);
  assert.deepEqual(counters.readsByCollection, { jobs: 2, job_private: 2 });
  assert.equal(counters.writes, 0);
});

test('inventory detects conflicts, unknown fields and absent private docs in its safe report', async () => {
  requireInventory();
  const jobs = {
    conflict: { title: 'Vaga A', contact: 'same-name-conflict', salary: 'not-approved' },
    unknown: { title: 'Vaga B', customLegacy: 'unknown-value' },
  };
  const privateJobs = { conflict: { contact: 'different-private-value' } };
  const report = await inventoryApi.createLegacyJobInventory({
    db: makeDb(jobs, privateJobs), FieldPath: { documentId: () => '__name__' },
  }).inventoryAll();
  assert.equal(report.conflictDocuments, 1);
  assert.equal(report.unclassifiedFieldCounts.customLegacy, 1);
  assert.deepEqual(report.documents.map((item) => item.jobId), ['conflict', 'unknown']);
  assert.equal(JSON.stringify(report).includes('same-name-conflict'), false);
  assert.equal(JSON.stringify(report).includes('different-private-value'), false);
  assert.equal(JSON.stringify(report).includes('not-approved'), false);
});

test('inventory is deterministic and repeatable for unchanged fixture documents', async () => {
  requireInventory();
  const jobs = { one: { title: 'Fictício', whatsapp: 'fictional-contact' } };
  const privateJobs = {};
  const first = await inventoryApi.createLegacyJobInventory({
    db: makeDb({ ...jobs }, privateJobs), FieldPath: { documentId: () => '__name__' },
  }).inventoryAll();
  const second = await inventoryApi.createLegacyJobInventory({
    db: makeDb({ ...jobs }, privateJobs), FieldPath: { documentId: () => '__name__' },
  }).inventoryAll();
  assert.deepEqual(second, first);
});

test('inventory CLI allows dry-run only and requires the exact local demo endpoints', () => {
  requireInventory();
  const safeEnvironment = {
    GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087',
    FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9097',
  };
  assert.equal(inventoryApi.validateInventoryEnvironment(safeEnvironment), true);
  assert.equal(inventoryApi.validateInventoryEnvironment({ ...safeEnvironment, GCLOUD_PROJECT: 'production' }), false);
  assert.equal(inventoryApi.parseInventoryArgs([]), true);
  assert.equal(inventoryApi.parseInventoryArgs(['--dry-run']), true);
  assert.throws(() => inventoryApi.parseInventoryArgs(['--apply']), /dry-run only/i);
  assert.equal(JSON.stringify(safeEnvironment).includes('contact'), false);
});

test('inventory runtime guard reads the actual process environment before loading Firebase Admin', () => {
  requireInventory();
  const original = {
    GCLOUD_PROJECT: process.env.GCLOUD_PROJECT,
    FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST,
    FIREBASE_AUTH_EMULATOR_HOST: process.env.FIREBASE_AUTH_EMULATOR_HOST,
  };
  try {
    process.env.GCLOUD_PROJECT = 'production-project';
    process.env.FIRESTORE_EMULATOR_HOST = 'firestore.googleapis.com:443';
    process.env.FIREBASE_AUTH_EMULATOR_HOST = 'auth.example.invalid:443';
    assert.throws(() => inventoryApi.assertSafeInventoryRuntime(), /demo Auth and Firestore emulators/);
  } finally {
    for (const [key, value] of Object.entries(original)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test('inventory fails closed when either collection cannot be read', async () => {
  requireInventory();
  for (const collection of ['jobs', 'job_private']) {
    const db = makeDb({ job: { title: 'Fictitious' } }, { orphan: { contact: 'secret' } },
      { writes: 0 }, { collection, error: Object.assign(new Error('private fixture details'), { code: 'unavailable' }) });
    const inventory = inventoryApi.createLegacyJobInventory({
      db, FieldPath: { documentId: () => '__name__' },
    });
    await assert.rejects(inventory.inventoryAll(), (error) => {
      assert.equal(error.code, 'unavailable');
      return true;
    });
  }
});
