'use strict';

const { isDeepStrictEqual } = require('node:util');
const { JOB_PUBLIC_FIELDS } = require('./public_content');
const PUBLIC_JOB_FIELDS = new Set(JOB_PUBLIC_FIELDS);

const LEGACY_PRIVATE_JOB_FIELDS = Object.freeze([
  'contact', 'phone', 'whatsapp', 'link', 'instagram', 'maps', 'mapsUrl', 'additionalInfo',
]);
const UNAPPROVED_JOB_FIELDS = Object.freeze(['salary', 'eventDate', 'date']);
const DEMO_PROJECT = 'demo-universal-search';
const FIRESTORE_EMULATOR = '127.0.0.1:8087';
const AUTH_EMULATOR = '127.0.0.1:9097';

function hasValue(value) {
  return value != null && !(typeof value === 'string' && value.trim() === '');
}

function reviewResult({ privateFieldsPresent, unapprovedFields, unclassifiedFields,
  conflictingPrivateFields, privateDocumentMissing }) {
  const reviewReasons = [];
  if (privateFieldsPresent.length > 0) reviewReasons.push('legacy-private-fields-in-public-document');
  if (privateDocumentMissing) reviewReasons.push('private-document-missing');
  if (conflictingPrivateFields.length > 0) reviewReasons.push('private-field-conflict');
  if (unapprovedFields.length > 0) reviewReasons.push('unapproved-fields-present');
  if (unclassifiedFields.length > 0) reviewReasons.push('unclassified-fields-present');

  return {
    privateFieldsPresent,
    unapprovedFields,
    unclassifiedFields,
    conflictingPrivateFields,
    privateDocumentMissing,
    manualReviewRequired: reviewReasons.length > 0,
    reviewReasons,
  };
}

function classifyLegacyJob({ jobData, privateData, privateExists }) {
  const job = jobData && typeof jobData === 'object' && !Array.isArray(jobData) ? jobData : {};
  const privateJob = privateData && typeof privateData === 'object' && !Array.isArray(privateData)
    ? privateData : {};
  const privateFieldsPresent = LEGACY_PRIVATE_JOB_FIELDS.filter((field) => Object.hasOwn(job, field));
  const unapprovedFields = UNAPPROVED_JOB_FIELDS.filter((field) => Object.hasOwn(job, field)).sort();
  const unclassifiedFields = Object.keys(job).filter((field) =>
    !PUBLIC_JOB_FIELDS.has(field) &&
    !LEGACY_PRIVATE_JOB_FIELDS.includes(field) &&
    !UNAPPROVED_JOB_FIELDS.includes(field)).sort();
  const conflictingPrivateFields = privateFieldsPresent.filter((field) =>
    hasValue(job[field]) && hasValue(privateJob[field]) && !isDeepStrictEqual(job[field], privateJob[field]));
  return reviewResult({
    privateFieldsPresent,
    unapprovedFields,
    unclassifiedFields,
    conflictingPrivateFields,
    privateDocumentMissing: privateExists !== true,
  });
}

function createLegacyJobInventory({ db, FieldPath, pageSize = 100 }) {
  if (!db || !FieldPath || typeof FieldPath.documentId !== 'function' ||
      !Number.isInteger(pageSize) || pageSize < 1 || pageSize > 500) {
    throw new TypeError('Invalid inventory dependencies or page size.');
  }

  async function inventoryAll() {
    const unclassifiedCounts = new Map();
    const jobRecords = new Map();
    const report = {
      mode: 'read-only-dry-run',
      examined: 0,
      affected: 0,
      privateFieldCounts: Object.fromEntries(LEGACY_PRIVATE_JOB_FIELDS.map((field) => [field, 0])),
      unapprovedFieldCounts: Object.fromEntries(UNAPPROVED_JOB_FIELDS.map((field) => [field, 0])),
      unclassifiedFieldCounts: {},
      missingPrivateDocuments: 0,
      conflictDocuments: 0,
      manualReviewDocuments: 0,
      documents: [],
      orphanPrivateDocuments: 0,
      orphanDocuments: [],
    };
    async function scanCollection(collection, onDocument) {
      let lastDocument = null;
      while (true) {
        let query = db.collection(collection).orderBy(FieldPath.documentId()).limit(pageSize);
        if (lastDocument) query = query.startAfter(lastDocument);
        const page = await query.get();
        for (const document of page.docs) await onDocument(document);
        if (page.size < pageSize) break;
        lastDocument = page.docs[page.docs.length - 1];
      }
    }

    // Read each collection once in stable pages. Keep only known legacy private
    // values briefly for conflict comparison; never include values in reports.
    await scanCollection('jobs', (document) => {
      const jobData = document.data();
      const classification = classifyLegacyJob({ jobData, privateData: null, privateExists: true });
      const privateValues = Object.fromEntries(classification.privateFieldsPresent
        .map((field) => [field, jobData[field]]));
      jobRecords.set(document.id, { classification, privateValues, privateDocumentMissing: true });
      report.examined++;
      for (const field of classification.privateFieldsPresent) report.privateFieldCounts[field]++;
      for (const field of classification.unapprovedFields) report.unapprovedFieldCounts[field]++;
      for (const field of classification.unclassifiedFields) {
        unclassifiedCounts.set(field, (unclassifiedCounts.get(field) || 0) + 1);
      }
      if (classification.privateFieldsPresent.length > 0) report.affected++;
    });

    await scanCollection('job_private', (document) => {
      const record = jobRecords.get(document.id);
      if (!record) {
        report.orphanPrivateDocuments++;
        report.orphanDocuments.push({ jobId: document.id, category: 'orphan-private-document' });
        return;
      }
      record.privateDocumentMissing = false;
      if (record.classification.privateFieldsPresent.length === 0) return;
      const privateData = document.data();
      record.conflictingPrivateFields = record.classification.privateFieldsPresent.filter((field) =>
        hasValue(record.privateValues[field]) && hasValue(privateData?.[field]) &&
        !isDeepStrictEqual(record.privateValues[field], privateData[field]));
      record.privateValues = null;
    });

    for (const [jobId, record] of jobRecords) {
      const result = reviewResult({
        ...record.classification,
        conflictingPrivateFields: record.conflictingPrivateFields || [],
        privateDocumentMissing: record.privateDocumentMissing,
      });
      if (result.privateDocumentMissing) report.missingPrivateDocuments++;
      if (result.conflictingPrivateFields.length > 0) report.conflictDocuments++;
      if (result.manualReviewRequired) {
        report.manualReviewDocuments++;
        report.documents.push({ jobId, ...result });
      }
    }
    report.unclassifiedFieldCounts = Object.fromEntries([...unclassifiedCounts].sort(([a], [b]) =>
      a < b ? -1 : a > b ? 1 : 0));
    report.orphanDocuments.sort((a, b) => a.jobId < b.jobId ? -1 : a.jobId > b.jobId ? 1 : 0);
    report.manualReviewTotal = report.manualReviewDocuments + report.orphanPrivateDocuments;
    for (const record of jobRecords.values()) record.privateValues = null;
    return report;
  }

  return { inventoryAll };
}

function validateInventoryEnvironment(env = process.env) {
  return env.GCLOUD_PROJECT === DEMO_PROJECT &&
    env.FIRESTORE_EMULATOR_HOST === FIRESTORE_EMULATOR &&
    env.FIREBASE_AUTH_EMULATOR_HOST === AUTH_EMULATOR;
}

function parseInventoryArgs(args) {
  if (args.some((arg) => arg !== '--dry-run')) {
    throw new Error('Inventory is read-only dry-run only; --apply is not supported.');
  }
  return true;
}

function assertSafeInventoryRuntime() {
  if (!validateInventoryEnvironment(process.env)) {
    throw new Error('Refusing to run without the configured demo Auth and Firestore emulators.');
  }
}

async function runLegacyJobInventory(args = process.argv.slice(2)) {
  parseInventoryArgs(args);
  assertSafeInventoryRuntime();
  const admin = require('firebase-admin');
  const { FieldPath } = require('firebase-admin/firestore');
  admin.initializeApp({ projectId: DEMO_PROJECT });
  try {
    const inventory = createLegacyJobInventory({ db: admin.firestore(), FieldPath });
    const report = await inventory.inventoryAll();
    console.log(JSON.stringify(report));
    return report;
  } finally {
    await admin.app().delete();
  }
}

if (require.main === module) {
  runLegacyJobInventory().catch(() => {
    console.error('Legacy job inventory failed; no private field values were logged.');
    process.exitCode = 1;
  });
}

module.exports = {
  LEGACY_PRIVATE_JOB_FIELDS,
  UNAPPROVED_JOB_FIELDS,
  classifyLegacyJob,
  createLegacyJobInventory,
  validateInventoryEnvironment,
  parseInventoryArgs,
  assertSafeInventoryRuntime,
  runLegacyJobInventory,
};
