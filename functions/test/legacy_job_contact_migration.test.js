'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  LEGACY_PRIVATE_JOB_FIELDS,
  UNAPPROVED_JOB_FIELDS,
  planLegacyJobContactMigration,
  createLegacyJobContactMigrator,
  validateEmulatorEnvironment,
  parseMode,
  runCli,
} = require('../migrate_legacy_job_contacts');

const safeEnv = {
  GCLOUD_PROJECT: 'demo-universal-search',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087',
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9097',
};
const originalEnvironment = Object.fromEntries(Object.keys(safeEnv).map((key) => [key, process.env[key]]));
Object.assign(process.env, safeEnv);
test.after(() => {
  for (const [key, value] of Object.entries(originalEnvironment)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});
const fakeFieldValue = {
  delete: () => ({ __fieldOperation: 'delete' }),
  serverTimestamp: () => ({ __fieldOperation: 'serverTimestamp' }),
};

function makeDb(initialJobs = {}, initialPrivate = {}, options = {}) {
  const jobs = new Map(Object.entries(structuredClone(initialJobs)));
  const privateJobs = new Map(Object.entries(structuredClone(initialPrivate)));
  const counters = { reads: { jobs: 0, job_private: 0 }, writes: 0, transactions: 0 };
  const stores = { jobs, job_private: privateJobs };

  function snapshot(collection, id) {
    const store = stores[collection];
    const exists = store.has(id);
    const value = store.get(id);
    return { id, exists, data: () => structuredClone(value) };
  }

  function documentReference(collection, id) {
    return { collectionName: collection, id };
  }

  function collection(name) {
    assert.ok(Object.hasOwn(stores, name), `unexpected collection ${name}`);
    return {
      doc(id) { return documentReference(name, id); },
      orderBy() { return this; },
      limit(size) { this.pageSize = size; return this; },
      startAfter(document) { this.afterId = document.id; return this; },
      async get() {
        counters.reads[name]++;
        if (options.readFailure?.collection === name) {
          throw options.readFailure.error;
        }
        const pageSize = this.pageSize || 100;
        const afterId = this.afterId || null;
        const ordered = [...stores[name].entries()]
          .sort(([left], [right]) => left.localeCompare(right))
          .filter(([id]) => afterId == null || id > afterId)
          .slice(0, pageSize)
          .map(([id]) => snapshot(name, id));
        return { docs: ordered, size: ordered.length };
      },
    };
  }

  const db = {
    collection,
    async runTransaction(operation) {
      counters.transactions++;
      options.beforeTransaction?.(counters.transactions, stores);
      const writes = [];
      const transaction = {
        async get(reference) {
          if (options.transactionReadFailure) throw options.transactionReadFailure;
          return snapshot(reference.collectionName, reference.id);
        },
        set(reference, patch, config) {
          writes.push({ type: 'set', reference, patch: structuredClone(patch), config });
          return transaction;
        },
        update(reference, patch) {
          writes.push({ type: 'update', reference, patch: structuredClone(patch) });
          return transaction;
        },
      };
      const result = await operation(transaction);
      if (options.transactionCommitFailure) throw options.transactionCommitFailure;
      for (const write of writes) {
        const target = stores[write.reference.collectionName];
        const current = target.get(write.reference.id) || {};
        const next = write.type === 'set' && !write.config?.merge
          ? {} : structuredClone(current);
        for (const [field, value] of Object.entries(write.patch)) {
          if (value?.__fieldOperation === 'delete') delete next[field];
          else next[field] = value;
        }
        target.set(write.reference.id, next);
        counters.writes++;
      }
      return result;
    },
  };

  return { db, jobs, privateJobs, counters };
}

function createMigrator(fake, options = {}) {
  return createLegacyJobContactMigrator({
    db: fake.db,
    FieldPath: { documentId: () => '__name__' },
    FieldValue: fakeFieldValue,
    ...options,
  });
}

test('migration plan includes all eight approved administrative fields', () => {
  const jobData = Object.fromEntries(LEGACY_PRIVATE_JOB_FIELDS.map((field) => [field, `fake-${field}`]));
  const plan = planLegacyJobContactMigration({ jobData, privateData: null });
  assert.equal(plan.status, 'migrate');
  assert.deepEqual(Object.keys(plan.fieldsToCopy), LEGACY_PRIVATE_JOB_FIELDS);
  assert.deepEqual(plan.fieldsToRemove, LEGACY_PRIVATE_JOB_FIELDS);
});

test('different existing private values are reported as a conflict without exposing values', () => {
  const plan = planLegacyJobContactMigration({
    jobData: { contact: 'legacy-private-value' },
    privateData: { contact: 'stored-private-url-value' },
  });
  assert.deepEqual(plan, {
    status: 'conflict',
    reason: 'different-private-value',
    field: 'contact',
  });
  assert.equal(JSON.stringify(plan).includes('legacy-private-value'), false);
  assert.equal(JSON.stringify(plan).includes('stored-private-url-value'), false);
});

test('empty and already-private fields are not copied or removed from the public document', () => {
  assert.deepEqual(planLegacyJobContactMigration({
    jobData: { contact: '', phone: null, whatsapp: 'same-value' },
    privateData: { whatsapp: 'same-value' },
  }), {
    status: 'migrate',
    fieldsToCopy: {},
    fieldsToRemove: ['whatsapp'],
  });
  assert.deepEqual(planLegacyJobContactMigration({
    jobData: { contact: '', phone: null }, privateData: null,
  }), { status: 'ignored', reason: 'no-transferable-private-values' });
  assert.deepEqual(planLegacyJobContactMigration({
    jobData: { contact: 'legacy-contact-value' }, privateData: { contact: '' },
  }), {
    status: 'conflict', reason: 'different-private-value', field: 'contact',
  });
});

test('unclassified, unapproved, conflicting, and unreviewed orphan data block globally', async () => {
  const fixture = makeDb({
    unknown: { title: 'Vaga fictícia', customField: 'unknown-private-value' },
    unapproved: { title: 'Vaga fictícia', salary: 'salary-private-value' },
    conflict: { title: 'Vaga fictícia', contact: 'legacy-contact-value' },
  }, {
    conflict: { contact: 'stored-contact-value' },
    orphan: { contact: 'orphan-contact-value' },
  });
  const report = await createMigrator(fixture).preflightAll();
  assert.equal(report.status, 'blocked-for-review');
  assert.equal(report.inventoryComplete, true);
  assert.equal(report.candidateDocuments, 0);
  assert.ok(report.blockedDocuments.some((item) => item.jobId === 'unknown' &&
    item.categories.includes('unclassified-public-fields')));
  assert.ok(report.blockedDocuments.some((item) => item.jobId === 'unapproved' &&
    item.categories.includes('unapproved-fields')));
  assert.ok(report.blockedDocuments.some((item) => item.jobId === 'conflict' &&
    item.categories.includes('private-field-conflict')));
  assert.ok(report.blockedDocuments.some((item) => item.jobId === 'orphan' &&
    item.categories.includes('unreviewed-orphan-private-document')));
  for (const privateValue of [
    'unknown-private-value', 'salary-private-value', 'legacy-contact-value',
    'stored-contact-value', 'orphan-contact-value',
  ]) assert.equal(JSON.stringify(report).includes(privateValue), false);
});

test('salary, eventDate, and date remain unapproved and block the whole migration', async () => {
  const job = { title: 'Vaga fictícia' };
  for (const field of UNAPPROVED_JOB_FIELDS) job[field] = `pending-${field}`;
  job.contact = 'fake-contact';
  const fake = makeDb({ job }, {});
  const report = await createMigrator(fake).preflightAll();
  assert.equal(report.status, 'blocked-for-review');
  assert.deepEqual(report.blockedDocuments[0].unapprovedFields, [...UNAPPROVED_JOB_FIELDS].sort());
  assert.equal(JSON.stringify(report).includes('pending-'), false);
  assert.equal(fake.counters.writes, 0);
});

test('missing private documents are counted as migration candidates when fields are classified', async () => {
  const fake = makeDb({ job: { title: 'Vaga fictícia', contact: 'fake-contact' } });
  const report = await createMigrator(fake).preflightAll();
  assert.equal(report.status, 'ready-for-migration');
  assert.equal(report.missingPrivateDocuments, 1);
  assert.equal(report.candidateDocuments, 1);
  assert.equal(fake.counters.writes, 0);
});

test('migrateAll defaults to a read-only dry-run and leaves all eight fields untouched', async () => {
  const job = { title: 'Vaga fictícia', published: true };
  for (const field of LEGACY_PRIVATE_JOB_FIELDS) job[field] = `private-${field}-sentinel`;
  const fake = makeDb({ originalJobId: job });
  const result = await createMigrator(fake).migrateAll();

  assert.equal(result.status, 'ready-for-migration');
  assert.equal(result.mode, 'preflight-only');
  assert.equal(result.candidateDocuments, 1);
  assert.deepEqual(fake.jobs.get('originalJobId'), job);
  assert.equal(fake.privateJobs.has('originalJobId'), false);
  assert.equal(fake.counters.transactions, 0);
  assert.equal(fake.counters.writes, 0);
  assert.equal(JSON.stringify(result).includes('sentinel'), false);
});

test('a reviewed orphan is recorded but does not silently disappear or block a clean inventory', async () => {
  const fake = makeDb({ job: { title: 'Vaga fictícia', contact: 'fake-contact' } }, {
    reviewedOrphan: { contact: 'orphan-private-value' },
  });
  const report = await createMigrator(fake).preflightAll({
    reviewedOrphanPrivateIds: ['reviewedOrphan'],
  });
  assert.equal(report.status, 'ready-for-migration');
  assert.equal(report.orphanPrivateDocuments, 1);
  assert.equal(report.reviewedOrphanDocuments, 1);
  assert.equal(fake.privateJobs.has('reviewedOrphan'), true);
  assert.equal(JSON.stringify(report).includes('orphan-private-value'), false);
});

test('a failure reading either collection returns inventory-incomplete without writes', async () => {
  for (const collection of ['jobs', 'job_private']) {
    const fake = makeDb({ job: { title: 'Vaga fictícia', contact: 'fake-contact' } }, {}, {
      readFailure: { collection, error: Object.assign(new Error('private synthetic detail'), { code: 'unavailable' }) },
    });
    const report = await createMigrator(fake).preflightAll();
    const result = await createMigrator(fake).applyPreflight(report);
    assert.equal(report.status, 'inventory-incomplete');
    assert.equal(report.inventoryComplete, false);
    assert.deepEqual(report.readFailures, [{ collection, reason: 'unavailable' }]);
    assert.equal(result.status, 'inventory-incomplete');
    assert.equal(result.applied, 0);
    assert.equal(JSON.stringify(report).includes('private synthetic detail'), false);
    assert.equal(fake.counters.writes, 0);
    assert.equal(fake.counters.transactions, 0);
    assert.equal(fake.jobs.get('job').contact, 'fake-contact');
    assert.equal(fake.privateJobs.has('job'), false);
  }
});

test('global preflight does not perform writes and prevents all application when blocked', async () => {
  const fake = makeDb({
    candidate: { title: 'Vaga fictícia', contact: 'private-contact-value' },
    needsReview: { title: 'Vaga fictícia', unknown: 'private-unknown-value' },
  });
  const migrator = createMigrator(fake);
  const preflight = await migrator.preflightAll();
  const result = await migrator.applyPreflight(preflight);
  assert.equal(preflight.status, 'blocked-for-review');
  assert.equal(result.status, 'blocked-for-review');
  assert.equal(result.applied, 0);
  assert.equal(fake.counters.transactions, 0);
  assert.equal(fake.counters.writes, 0);
  assert.equal(fake.jobs.get('candidate').contact, 'private-contact-value');
  assert.equal(fake.privateJobs.has('candidate'), false);
  assert.equal(fake.jobs.get('needsReview').unknown, 'private-unknown-value');
});

test('application is denied before any read or write outside the exact demo Emulator environment', async () => {
  const fake = makeDb({ job: { title: 'Vaga fictícia', contact: 'private-contact-value' } });
  const migrator = createLegacyJobContactMigrator({
    db: fake.db,
    FieldPath: { documentId: () => '__name__' },
    FieldValue: fakeFieldValue,
  });
  const report = await migrator.preflightAll();
  const beforeReads = { ...fake.counters.reads };
  const priorProject = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = 'production-project';
  let result;
  try {
    result = await migrator.applyPreflight(report);
  } finally {
    process.env.GCLOUD_PROJECT = priorProject;
  }
  assert.equal(result.status, 'blocked-for-review');
  assert.equal(result.reason, 'demo-emulator-environment-required');
  assert.deepEqual(fake.counters.reads, beforeReads);
  assert.equal(fake.counters.writes, 0);
  assert.equal(fake.jobs.get('job').contact, 'private-contact-value');
});

test('preflight refuses to inventory Firestore outside the exact demo Emulator environment', async () => {
  const fake = makeDb({ job: { title: 'Vaga fictícia', contact: 'private-contact-value' } });
  const migrator = createMigrator(fake);
  const priorProject = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = 'production-project';
  let report;
  try {
    report = await migrator.preflightAll();
  } finally {
    process.env.GCLOUD_PROJECT = priorProject;
  }
  assert.equal(report.status, 'inventory-incomplete');
  assert.equal(report.readFailures[0].reason, 'demo-emulator-environment-required');
  assert.deepEqual(fake.counters.reads, { jobs: 0, job_private: 0 });
  assert.equal(fake.counters.writes, 0);
});

test('application is idempotent and keeps private metadata while removing only transferred fields', async () => {
  const fake = makeDb({ job: {
    title: 'Vaga fictícia', published: true, contact: 'fake-contact',
    phone: 'fake-phone', salary: undefined,
  } }, {
    job: {
      schemaVersion: 2, updatedAt: 'existing-metadata',
      legacyContactsMigratedAt: 'existing-migration-metadata', phone: 'fake-phone',
    },
  });
  delete fake.jobs.get('job').salary;
  const migrator = createMigrator(fake);
  const firstPreflight = await migrator.preflightAll();
  assert.equal(firstPreflight.status, 'ready-for-migration');
  const firstApply = await migrator.applyPreflight(firstPreflight);
  assert.equal(firstApply.status, 'applied');
  assert.equal(firstApply.migrated, 1);
  assert.deepEqual(fake.jobs.get('job'), { title: 'Vaga fictícia', published: true });
  assert.equal(fake.privateJobs.get('job').contact, 'fake-contact');
  assert.equal(fake.privateJobs.get('job').phone, 'fake-phone');
  assert.equal(fake.privateJobs.get('job').schemaVersion, 2);
  assert.equal(fake.privateJobs.get('job').updatedAt, 'existing-metadata');
  assert.equal(fake.privateJobs.get('job').legacyContactsMigratedAt, 'existing-migration-metadata');

  const secondPreflight = await migrator.preflightAll();
  const secondApply = await migrator.applyPreflight(secondPreflight);
  assert.equal(secondPreflight.status, 'ready-for-migration');
  assert.equal(secondApply.status, 'applied');
  assert.equal(secondApply.migrated, 0);
  assert.equal(fake.counters.writes, 2);
});

test('reports and event logs include categories only and never administrative values', async () => {
  const events = [];
  const fake = makeDb({ job: { title: 'Vaga fictícia', additionalInfo: 'secret-admin-note' } });
  const migrator = createMigrator(fake, { onEvent: (event) => events.push(event) });
  const report = await migrator.preflightAll();
  const result = await migrator.applyPreflight(report);
  assert.equal(report.status, 'ready-for-migration');
  assert.equal(result.status, 'applied');
  assert.equal(JSON.stringify([report, result, events]).includes('secret-admin-note'), false);
  assert.ok(events.every((event) => !Object.hasOwn(event, 'value')));
});

test('a concurrent private conflict after preflight blocks before the first transaction', async () => {
  const fake = makeDb({ job: { title: 'Vaga fictícia', contact: 'before-change' } });
  const migrator = createMigrator(fake);
  const preflight = await migrator.preflightAll();
  fake.privateJobs.set('job', { contact: 'concurrent-private-conflict' });
  const result = await migrator.applyPreflight(preflight);
  assert.equal(result.status, 'blocked-for-review');
  assert.equal(result.reason, 'inventory-changed-after-preflight');
  assert.equal(result.applied, 0);
  assert.equal(fake.counters.transactions, 0);
  assert.equal(fake.counters.writes, 0);
  assert.equal(fake.jobs.get('job').contact, 'before-change');
  assert.equal(fake.privateJobs.get('job').contact, 'concurrent-private-conflict');
});

test('a conflict detected during application stops later documents', async () => {
  const fake = makeDb({
    a: { title: 'Vaga A', contact: 'fake-a' },
    b: { title: 'Vaga B', contact: 'fake-b' },
    c: { title: 'Vaga C', contact: 'fake-c' },
  }, {}, {
    beforeTransaction(number, stores) {
      if (number === 2) {
        stores.jobs.set('b', { title: 'Vaga B', contact: 'concurrent-change' });
        stores.job_private.set('b', { contact: 'concurrent-private-conflict' });
      }
    },
  });
  const migrator = createMigrator(fake);
  const preflight = await migrator.preflightAll();
  const result = await migrator.applyPreflight(preflight);
  assert.equal(preflight.status, 'ready-for-migration');
  assert.equal(result.status, 'stopped-during-application');
  assert.equal(result.reason, 'document-changed-during-application');
  assert.equal(result.applied, 1);
  assert.equal(fake.counters.transactions, 2);
  assert.equal(fake.privateJobs.get('b').contact, 'concurrent-private-conflict');
  assert.equal(fake.jobs.has('c'), true);
  assert.equal(fake.jobs.get('c').contact, 'fake-c');
  assert.equal(fake.privateJobs.has('c'), false);
});

test('CLI is dry-run by default and rejects non-demo destinations and ambiguous options', async () => {
  assert.equal(validateEmulatorEnvironment(safeEnv), true);
  assert.equal(validateEmulatorEnvironment({ ...safeEnv, GCLOUD_PROJECT: 'production' }), false);
  assert.deepEqual(parseMode([]), { apply: false, reviewedOrphanPrivateIds: [] });
  assert.deepEqual(parseMode(['--apply', '--reviewed-orphan-id=old-orphan']), {
    apply: true,
    reviewedOrphanPrivateIds: ['old-orphan'],
  });
  assert.throws(() => parseMode(['--apply', '--dry-run']), /either/);
  assert.throws(() => parseMode(['--reviewed-orphan-id=bad/id']), /orphan/i);
  await assert.rejects(runCli(['--apply'], safeEnv), /confirmation/);
  await assert.rejects(runCli(['--apply'], {
    ...safeEnv,
    CONFIRM_LEGACY_JOB_CONTACT_MIGRATION: 'not-the-demo-project',
  }), /confirmation/);
  await assert.rejects(runCli(['--dry-run'], { ...safeEnv, GCLOUD_PROJECT: 'production' }), /demo/i);
});
