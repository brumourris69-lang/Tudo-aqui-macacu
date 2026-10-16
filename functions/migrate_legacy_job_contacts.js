'use strict';

const { isDeepStrictEqual } = require('node:util');
const {
  JOB_PUBLIC_FIELDS,
} = require('./public_content');
const {
  LEGACY_PRIVATE_JOB_FIELDS,
  UNAPPROVED_JOB_FIELDS,
} = require('./legacy_job_inventory');
const PRIVATE_METADATA_FIELDS = Object.freeze(['schemaVersion', 'updatedAt', 'legacyContactsMigratedAt']);
const DEMO_PROJECT = 'demo-universal-search';
const FIRESTORE_EMULATOR = '127.0.0.1:8087';
const AUTH_EMULATOR = '127.0.0.1:9097';
const ALLOWED_PRIVATE_FIELDS = new Set([
  ...LEGACY_PRIVATE_JOB_FIELDS,
  ...UNAPPROVED_JOB_FIELDS,
  ...PRIVATE_METADATA_FIELDS,
]);

function hasValue(value) {
  return value != null && !(typeof value === 'string' && value.trim() === '');
}

function safeErrorCode(error) {
  return typeof error?.code === 'string' && /^[a-z0-9_-]{1,40}$/i.test(error.code)
    ? error.code : 'migration-error';
}

function planLegacyJobContactMigration({ jobData, privateData }) {
  if (!jobData || typeof jobData !== 'object' || Array.isArray(jobData)) {
    return { status: 'ignored', reason: 'job-not-found' };
  }

  const publicPrivateFields = LEGACY_PRIVATE_JOB_FIELDS.filter((field) =>
    Object.hasOwn(jobData, field));
  const existingPrivate = privateData && typeof privateData === 'object' && !Array.isArray(privateData)
    ? privateData : {};
  for (const field of publicPrivateFields) {
    if (hasValue(jobData[field]) && Object.hasOwn(existingPrivate, field) &&
        !isDeepStrictEqual(jobData[field], existingPrivate[field])) {
      return { status: 'conflict', reason: 'different-private-value', field };
    }
  }

  const fieldsToCopy = {};
  const fieldsToRemove = [];
  for (const field of publicPrivateFields) {
    if (!hasValue(jobData[field])) continue;
    if (!Object.hasOwn(existingPrivate, field)) fieldsToCopy[field] = jobData[field];
    // A matching value already stored privately is safely transferred too.
    fieldsToRemove.push(field);
  }
  if (fieldsToRemove.length === 0) {
    return { status: 'ignored', reason: 'no-transferable-private-values' };
  }
  return { status: 'migrate', fieldsToCopy, fieldsToRemove };
}

function validateReviewedOrphanIds(ids) {
  if (!Array.isArray(ids) || ids.some((id) => typeof id !== 'string' || !id || id.includes('/'))) {
    throw new TypeError('Reviewed orphan IDs must be non-empty Firestore document IDs.');
  }
  return new Set(ids);
}

function createLegacyJobContactMigrator({ db, FieldPath, FieldValue, pageSize = 100,
  onEvent = () => {} }) {
  if (!db || !FieldPath || typeof FieldPath.documentId !== 'function' || !FieldValue ||
      !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 500) {
    throw new TypeError('Invalid migration dependencies or page size.');
  }

  const preflightSnapshots = new WeakMap();

  async function scanCollection(collection) {
    const records = new Map();
    let lastDocument = null;
    while (true) {
      let query = db.collection(collection)
        .orderBy(FieldPath.documentId())
        .limit(pageSize);
      if (lastDocument) query = query.startAfter(lastDocument);
      let page;
      try {
        page = await query.get();
      } catch (error) {
        const failure = new Error('Inventory read failed.');
        failure.collection = collection;
        failure.reason = safeErrorCode(error);
        throw failure;
      }
      try {
        for (const document of page.docs) records.set(document.id, document.data());
      } catch (error) {
        const failure = new Error('Inventory read failed.');
        failure.collection = collection;
        failure.reason = safeErrorCode(error);
        throw failure;
      }
      if (page.size < pageSize) break;
      lastDocument = page.docs[page.docs.length - 1];
    }
    return records;
  }

  async function scanAll() {
    let jobs;
    try {
      jobs = await scanCollection('jobs');
    } catch (error) {
      return { complete: false, jobs: new Map(), privateJobs: new Map(),
        failure: { collection: error.collection || 'jobs', reason: error.reason || 'migration-error' } };
    }
    try {
      const privateJobs = await scanCollection('job_private');
      return { complete: true, jobs, privateJobs };
    } catch (error) {
      return { complete: false, jobs, privateJobs: new Map(),
        failure: { collection: error.collection || 'job_private', reason: error.reason || 'migration-error' } };
    }
  }

  function sameRecords(left, right) {
    if (left.size !== right.size) return false;
    for (const [id, data] of left) {
      if (!right.has(id) || !isDeepStrictEqual(data, right.get(id))) return false;
    }
    return true;
  }

  function makeIncompleteReport(scan, reviewedOrphanPrivateIds) {
    return {
      status: 'inventory-incomplete',
      statusLabel: 'Inventário incompleto',
      mode: 'preflight-only',
      inventoryComplete: false,
      jobsExamined: scan.jobs.size,
      privateDocumentsExamined: scan.privateJobs.size,
      reviewedOrphanDocuments: reviewedOrphanPrivateIds.size,
      readFailures: [scan.failure],
      blockedDocuments: [],
      candidateDocuments: 0,
      missingPrivateDocuments: 0,
      orphanPrivateDocuments: 0,
      atomicity: 'per-document-transactions-only; no global atomicity',
    };
  }

  async function preflightAll({ reviewedOrphanPrivateIds = [] } = {}) {
    const reviewedOrphans = validateReviewedOrphanIds(reviewedOrphanPrivateIds);
    if (!validateEmulatorEnvironment(process.env)) {
      return makeIncompleteReport({
        complete: false,
        jobs: new Map(),
        privateJobs: new Map(),
        failure: { collection: 'environment', reason: 'demo-emulator-environment-required' },
      }, reviewedOrphans);
    }
    const scan = await scanAll();
    if (!scan.complete) return makeIncompleteReport(scan, reviewedOrphans);

    const blockedDocuments = [];
    const candidates = [];
    let missingPrivateDocuments = 0;
    let orphanPrivateDocuments = 0;
    let reviewedOrphanDocuments = 0;
    const reviewedOrphanDocumentIds = [];

    for (const [jobId, jobData] of scan.jobs) {
      const privateExists = scan.privateJobs.has(jobId);
      const privateData = privateExists ? scan.privateJobs.get(jobId) : null;
      if (!privateExists) missingPrivateDocuments++;

      const unapprovedFields = UNAPPROVED_JOB_FIELDS.filter((field) =>
        Object.hasOwn(jobData || {}, field) || Object.hasOwn(privateData || {}, field)).sort();
      const unclassifiedPublicFields = Object.keys(jobData || {}).filter((field) =>
        !JOB_PUBLIC_FIELDS.includes(field) && !LEGACY_PRIVATE_JOB_FIELDS.includes(field) &&
        !UNAPPROVED_JOB_FIELDS.includes(field)).sort();
      const unclassifiedPrivateFields = Object.keys(privateData || {}).filter((field) =>
        !ALLOWED_PRIVATE_FIELDS.has(field)).sort();
      const plan = planLegacyJobContactMigration({ jobData, privateData });
      const categories = [];
      if (unapprovedFields.length) categories.push('unapproved-fields');
      if (unclassifiedPublicFields.length) categories.push('unclassified-public-fields');
      if (unclassifiedPrivateFields.length) categories.push('unclassified-private-fields');
      if (plan.status === 'conflict') categories.push('private-field-conflict');

      if (categories.length) {
        blockedDocuments.push({
          jobId,
          categories,
          unapprovedFields,
          unclassifiedPublicFields,
          unclassifiedPrivateFields,
          conflictingFields: plan.status === 'conflict' ? [plan.field] : [],
        });
      } else if (plan.status === 'migrate') {
        candidates.push({ jobId, plan });
      }
    }

    for (const [jobId, privateData] of scan.privateJobs) {
      const unapprovedFields = UNAPPROVED_JOB_FIELDS.filter((field) =>
        Object.hasOwn(privateData || {}, field)).sort();
      const unclassifiedPrivateFields = Object.keys(privateData || {}).filter((field) =>
        !ALLOWED_PRIVATE_FIELDS.has(field)).sort();
      const isOrphan = !scan.jobs.has(jobId);
      const categories = [];
      if (unapprovedFields.length) categories.push('unapproved-fields');
      if (unclassifiedPrivateFields.length) categories.push('unclassified-private-fields');
      if (isOrphan) {
        orphanPrivateDocuments++;
        if (reviewedOrphans.has(jobId)) {
          reviewedOrphanDocuments++;
          reviewedOrphanDocumentIds.push(jobId);
        }
        else categories.push('unreviewed-orphan-private-document');
      }
      if (categories.length) {
        const existing = blockedDocuments.find((item) => item.jobId === jobId);
        if (existing) {
          existing.categories = [...new Set([...existing.categories, ...categories])];
          existing.unapprovedFields = [...new Set([...existing.unapprovedFields, ...unapprovedFields])].sort();
          existing.unclassifiedPrivateFields = unclassifiedPrivateFields;
        } else {
          blockedDocuments.push({
            jobId,
            categories,
            unapprovedFields,
            unclassifiedPublicFields: [],
            unclassifiedPrivateFields,
            conflictingFields: [],
          });
        }
      }
    }

    blockedDocuments.sort((left, right) => left.jobId.localeCompare(right.jobId));
    reviewedOrphanDocumentIds.sort((left, right) => left.localeCompare(right));
    const ready = blockedDocuments.length === 0;
    const report = {
      status: ready ? 'ready-for-migration' : 'blocked-for-review',
      statusLabel: ready ? 'Pronto para migração' : 'Bloqueado para revisão',
      mode: 'preflight-only',
      inventoryComplete: true,
      jobsExamined: scan.jobs.size,
      privateDocumentsExamined: scan.privateJobs.size,
      candidateDocuments: candidates.length,
      missingPrivateDocuments,
      orphanPrivateDocuments,
      reviewedOrphanDocuments,
      reviewedOrphanDocumentIds,
      blockedDocuments,
      readFailures: [],
      atomicity: 'per-document-transactions-only; no global atomicity',
    };
    if (report.status === 'ready-for-migration') {
      preflightSnapshots.set(report, { ...scan, candidates });
    }
    return report;
  }

  async function applyPreflight(preflight) {
    if (!validateEmulatorEnvironment(process.env)) {
      return {
        status: 'blocked-for-review',
        reason: 'demo-emulator-environment-required',
        applied: 0,
        atomicity: 'per-document-transactions-only; no global atomicity',
      };
    }
    const prepared = preflightSnapshots.get(preflight);
    if (!prepared || preflight.status !== 'ready-for-migration' ||
        preflight.inventoryComplete !== true) {
      return {
        status: preflight?.status === 'inventory-incomplete' ? 'inventory-incomplete' : 'blocked-for-review',
        reason: 'valid-ready-global-preflight-required',
        applied: 0,
        atomicity: 'per-document-transactions-only; no global atomicity',
      };
    }

    const current = await scanAll();
    if (!current.complete) {
      return {
        status: 'inventory-incomplete',
        reason: 'pre-application-read-failed',
        readFailures: [current.failure],
        applied: 0,
        atomicity: 'per-document-transactions-only; no global atomicity',
      };
    }
    if (!sameRecords(prepared.jobs, current.jobs) ||
        !sameRecords(prepared.privateJobs, current.privateJobs)) {
      return {
        status: 'blocked-for-review',
        reason: 'inventory-changed-after-preflight',
        applied: 0,
        atomicity: 'per-document-transactions-only; no global atomicity',
      };
    }

    let migrated = 0;
    for (let index = 0; index < prepared.candidates.length; index++) {
      const { jobId } = prepared.candidates[index];
      const expectedJob = prepared.jobs.get(jobId);
      const expectedPrivate = prepared.privateJobs.has(jobId)
        ? prepared.privateJobs.get(jobId) : null;
      let result;
      try {
        result = await db.runTransaction(async (transaction) => {
          const jobRef = db.collection('jobs').doc(jobId);
          const privateRef = db.collection('job_private').doc(jobId);
          const [jobSnapshot, privateSnapshot] = await Promise.all([
            transaction.get(jobRef), transaction.get(privateRef),
          ]);
          const currentJob = jobSnapshot.exists ? jobSnapshot.data() : null;
          const currentPrivate = privateSnapshot.exists ? privateSnapshot.data() : null;
          if (!jobSnapshot.exists || !isDeepStrictEqual(expectedJob, currentJob) ||
              !isDeepStrictEqual(expectedPrivate, currentPrivate)) {
            return { status: 'blocked-for-review', reason: 'document-changed-during-application' };
          }
          const plan = planLegacyJobContactMigration({ jobData: currentJob, privateData: currentPrivate });
          if (plan.status !== 'migrate') {
            return { status: 'blocked-for-review', reason: 'migration-plan-changed' };
          }

          if (Object.keys(plan.fieldsToCopy).length > 0) {
            const privatePatch = {
              ...plan.fieldsToCopy,
            };
            if (!privateSnapshot.exists || !Object.hasOwn(currentPrivate || {}, 'schemaVersion')) {
              privatePatch.schemaVersion = 1;
            }
            if (!Object.hasOwn(currentPrivate || {}, 'legacyContactsMigratedAt')) {
              privatePatch.legacyContactsMigratedAt = FieldValue.serverTimestamp();
            }
            transaction.set(privateRef, privatePatch, { merge: true });
          }
          transaction.update(jobRef, Object.fromEntries(plan.fieldsToRemove.map((field) =>
            [field, FieldValue.delete()])));
          return { status: 'migrated' };
        });
      } catch (error) {
        result = { status: 'stopped-during-application', reason: safeErrorCode(error) };
      }
      if (result.status !== 'migrated') {
        const stopped = {
          status: 'stopped-during-application',
          reason: result.reason || 'document-migration-failed',
          applied: migrated,
          remaining: prepared.candidates.length - index,
          atomicity: 'per-document-transactions-only; no global atomicity',
        };
        onEvent({ type: 'migration-stopped', jobId, reason: stopped.reason, applied: migrated });
        return stopped;
      }
      migrated++;
      onEvent({ type: 'migration-applied', jobId });
    }
    return {
      status: 'applied',
      applied: migrated,
      migrated,
      remaining: 0,
      atomicity: 'per-document-transactions-only; no global atomicity',
    };
  }

  async function migrateAll({ apply = false, reviewedOrphanPrivateIds = [] } = {}) {
    const preflight = await preflightAll({ reviewedOrphanPrivateIds });
    if (!apply || preflight.status !== 'ready-for-migration') return preflight;
    return applyPreflight(preflight);
  }

  return { preflightAll, applyPreflight, migrateAll };
}

function validateEmulatorEnvironment(env = process.env) {
  return env.GCLOUD_PROJECT === DEMO_PROJECT &&
    env.FIRESTORE_EMULATOR_HOST === FIRESTORE_EMULATOR &&
    env.FIREBASE_AUTH_EMULATOR_HOST === AUTH_EMULATOR;
}

function parseMode(args) {
  let apply = false;
  let dryRun = false;
  const reviewedOrphanPrivateIds = [];
  for (const arg of args) {
    if (arg === '--apply') apply = true;
    else if (arg === '--dry-run') dryRun = true;
    else if (arg.startsWith('--reviewed-orphan-id=')) {
      const id = arg.slice('--reviewed-orphan-id='.length);
      if (!id || id.includes('/')) throw new Error('Reviewed orphan ID must be a valid document ID.');
      reviewedOrphanPrivateIds.push(id);
    } else throw new Error('Unsupported migration option.');
  }
  if (apply && dryRun) throw new Error('Use either --dry-run or --apply.');
  return { apply, reviewedOrphanPrivateIds: [...new Set(reviewedOrphanPrivateIds)] };
}

async function runCli(args = process.argv.slice(2), env = process.env) {
  const options = parseMode(args);
  if (!validateEmulatorEnvironment(env)) {
    throw new Error('Refusing to run without the configured demo Auth and Firestore emulators.');
  }
  if (options.apply && env.CONFIRM_LEGACY_JOB_CONTACT_MIGRATION !== DEMO_PROJECT) {
    throw new Error('Apply mode requires the explicit demo-only confirmation variable.');
  }

  const admin = require('firebase-admin');
  const { FieldPath, FieldValue } = require('firebase-admin/firestore');
  admin.initializeApp({ projectId: DEMO_PROJECT });
  try {
    const migrator = createLegacyJobContactMigrator({
      db: admin.firestore(), FieldPath, FieldValue,
      onEvent: (event) => console.warn(JSON.stringify(event)),
    });
    const preflight = await migrator.preflightAll({
      reviewedOrphanPrivateIds: options.reviewedOrphanPrivateIds,
    });
    console.log(JSON.stringify(preflight));
    if (!options.apply || preflight.status !== 'ready-for-migration') {
      if (preflight.status !== 'ready-for-migration') process.exitCode = 2;
      return preflight;
    }
    const result = await migrator.applyPreflight(preflight);
    console.log(JSON.stringify(result));
    if (result.status !== 'applied') process.exitCode = 2;
    return result;
  } finally {
    await admin.app().delete();
  }
}

if (require.main === module) {
  runCli().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  LEGACY_PRIVATE_JOB_FIELDS,
  UNAPPROVED_JOB_FIELDS,
  planLegacyJobContactMigration,
  createLegacyJobContactMigrator,
  validateEmulatorEnvironment,
  parseMode,
  runCli,
};
