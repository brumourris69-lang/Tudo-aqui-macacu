'use strict';

const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

let currentScenario = 'integration setup';
let currentStage = 'validating the isolated runtime';

function setDiagnosticContext(scenario, stage) {
  currentScenario = scenario;
  currentStage = stage;
}

function sanitizedFailureType(error) {
  const candidate = error && typeof error.name === 'string' ? error.name : 'IntegrationError';
  return /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(candidate) ? candidate : 'IntegrationError';
}

function sanitizedHarnessFrames(error) {
  if (!error || typeof error.stack !== 'string') return [];
  return error.stack.split(/\r?\n/).flatMap((line) => {
    const match = line.match(/\bat\s+(?:(.*?)\s+\()?[^\r\n]*legacy_job_contacts_migration_emulator\.js:(\d+):(\d+)\)?\s*$/);
    if (!match) return [];
    const functionName = match[1] ? `${match[1]} ` : '';
    return [`at ${functionName}legacy_job_contacts_migration_emulator.js:${match[2]}:${match[3]}`];
  });
}

function reportSanitizedFailure(error, scenario = currentScenario, stage = currentStage) {
  const frames = sanitizedHarnessFrames(error);
  const assertionLocation = frames[0]
    ? frames[0].replace(/^at\s+/, '')
    : 'legacy_job_contacts_migration_emulator.js:line unavailable';
  console.error('Legacy job contact migration integration failed.');
  console.error(`Scenario: ${scenario}`);
  console.error(`Assertion location: ${assertionLocation}`);
  console.error(`Failure type: ${sanitizedFailureType(error)}`);
  console.error(`Interrupted stage: ${stage}`);
  console.error('Sanitized stack:');
  for (const frame of frames.length ? frames : ['(no harness frame available)']) {
    console.error(`  ${frame}`);
  }
}

process.once('uncaughtException', (error) => {
  reportSanitizedFailure(error);
  process.exitCode = 1;
});

setDiagnosticContext('integration setup', 'validating project and Emulator endpoints');
const project = process.env.GCLOUD_PROJECT;
assert.equal(project, 'demo-universal-search', 'Refusing a Firebase project outside the disposable demo.');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
assert.equal(process.env.CONFIRM_LEGACY_JOB_CONTACT_MIGRATION, project,
  'Explicit confirmation of the demo project is required before creating or migrating fixtures.');
assert.equal(Number(process.versions.node.split('.')[0]), 22, 'Run this integration with Node.js 22.');
assert.ok(process.env.JAVA_HOME, 'Set JAVA_HOME to the existing Java 21 runtime for the Emulator.');
const javaExecutable = path.join(process.env.JAVA_HOME, 'bin',
  process.platform === 'win32' ? 'java.exe' : 'java');
const javaProbe = spawnSync(javaExecutable, ['-version'], {
  encoding: 'utf8', windowsHide: true,
});
assert.equal(javaProbe.error, undefined, 'The configured Java runtime must be executable.');
assert.equal(javaProbe.status, 0, 'The configured Java runtime must start successfully.');
assert.match(`${javaProbe.stdout}\n${javaProbe.stderr}`, /version\s+"21(?:\.|\")/,
  'Run this integration with Java 21.');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: project });
const db = admin.firestore();
const { FieldPath, FieldValue } = require('firebase-admin/firestore');
const { createLegacyJobContactMigrator } = require('../migrate_legacy_job_contacts');
const run = `legacy-migration-${randomUUID()}`;
const ids = {
  all: `${run}-all`,
  one: `${run}-one`,
  none: `${run}-none`,
  existing: `${run}-existing`,
  privateMetadata: `${run}-private-metadata`,
  unknown: `${run}-unknown`,
  unapproved: `${run}-unapproved`,
  conflict: `${run}-conflict`,
  blockedCandidate: `${run}-blocked-candidate`,
  orphan: `${run}-orphan`,
};
const administrativeFields = [
  'contact', 'phone', 'whatsapp', 'link', 'instagram', 'maps', 'mapsUrl', 'additionalInfo',
];
const unclassifiedFixtureMarker = 'fixture-private-value-sentinel-84e2d7';
const allAdministrativeValues = Object.fromEntries(administrativeFields.map((field) =>
  [field, `fictional-${field}-value`]));

async function main() {
  const jobs = db.collection('jobs');
  const privateJobs = db.collection('job_private');
  setDiagnosticContext('fixture setup', 'creating UUID-scoped fictional fixtures');
  await Promise.all([
    jobs.doc(ids.all).set({
      title: 'Vaga fictícia com campos administrativos',
      description: 'Descrição pública preservada.', published: true,
      ...allAdministrativeValues,
    }),
    jobs.doc(ids.one).set({ title: 'Vaga fictícia com um campo', published: true, phone: '1111111111' }),
    jobs.doc(ids.none).set({ title: 'Vaga fictícia sem contato', published: true }),
    jobs.doc(ids.existing).set({ title: 'Vaga fictícia com contato privado existente',
      published: true, contact: 'matching-fictional-contact' }),
    privateJobs.doc(ids.existing).set({ schemaVersion: 2, contact: 'matching-fictional-contact',
      updatedAt: 'fixture-metadata' }),
    jobs.doc(ids.privateMetadata).set({ title: 'Vaga fictícia com metadado privado', published: true }),
    privateJobs.doc(ids.privateMetadata).set({ schemaVersion: 2, updatedAt: 'fixture-metadata-only' }),
  ]);

  // A small page size deliberately exercises cursor pagination in both collections.
  const migrator = createLegacyJobContactMigrator({ db, FieldPath, FieldValue, pageSize: 1 });
  setDiagnosticContext('global preflight', 'checking complete inventory and pagination');
  const preflight = await migrator.preflightAll();
  assert.equal(preflight.status, 'ready-for-migration');
  assert.equal(preflight.candidateDocuments, 3);
  assert.equal(preflight.jobsExamined, 5);
  assert.equal(preflight.privateDocumentsExamined, 2);
  assert.equal(preflight.mode, 'preflight-only');
  for (const value of Object.values(allAdministrativeValues)) {
    assert.equal(JSON.stringify(preflight).includes(value), false);
  }

  // Preflight/dry-run is read-only: the source fields remain and no private doc was created.
  setDiagnosticContext('dry-run preservation', 'checking that preflight made no writes');
  const beforeApply = (await jobs.doc(ids.all).get()).data();
  assert.deepEqual(Object.fromEntries(administrativeFields.map((field) => [field, beforeApply[field]])),
    allAdministrativeValues);
  assert.equal((await privateJobs.doc(ids.all).get()).exists, false);
  assert.equal((await jobs.doc(ids.one).get()).get('phone'), '1111111111');
  assert.equal((await privateJobs.doc(ids.one).get()).exists, false);

  setDiagnosticContext('migration of eligible fixtures', 'applying the approved demo preflight');
  const result = await migrator.applyPreflight(preflight);
  assert.equal(result.status, 'applied');
  assert.equal(result.migrated, 3);

  setDiagnosticContext('migration verification', 'checking private transfer and public preservation');
  const migratedPublic = (await jobs.doc(ids.all).get()).data();
  assert.equal(migratedPublic.published, true);
  assert.equal(migratedPublic.description, 'Descrição pública preservada.');
  const migratedPrivate = (await privateJobs.doc(ids.all).get()).data();
  for (const field of administrativeFields) {
    assert.equal(Object.hasOwn(migratedPublic, field), false);
    assert.equal(migratedPrivate[field], allAdministrativeValues[field]);
  }
  assert.equal((await privateJobs.doc(ids.one).get()).get('phone'), '1111111111');
  assert.equal((await jobs.doc(ids.one).get()).get('phone'), undefined);
  assert.equal((await privateJobs.doc(ids.existing).get()).get('schemaVersion'), 2);
  assert.equal((await privateJobs.doc(ids.privateMetadata).get()).get('schemaVersion'), 2);

  setDiagnosticContext('idempotence', 're-running preflight and apply on migrated fixtures');
  const repeatPreflight = await migrator.preflightAll();
  const repeat = await migrator.applyPreflight(repeatPreflight);
  assert.equal(repeatPreflight.status, 'ready-for-migration');
  assert.equal(repeat.migrated, 0);

  setDiagnosticContext('global blocking fixtures', 'creating unclassified, conflicting and orphan fixtures');
  await Promise.all([
    jobs.doc(ids.unknown).set({ title: 'Vaga fictícia para revisão', contact: 'unknown-contact',
      customField: unclassifiedFixtureMarker }),
    jobs.doc(ids.unapproved).set({ title: 'Vaga fictícia pendente', contact: 'unapproved-contact',
      salary: 'unapproved-salary', eventDate: 'unapproved-event-date', date: 'unapproved-date' }),
    jobs.doc(ids.conflict).set({ title: 'Vaga fictícia com conflito', contact: 'legacy-conflict' }),
    jobs.doc(ids.blockedCandidate).set({ title: 'Vaga elegível bloqueada globalmente',
      published: true, contact: 'must-remain-public-until-review' }),
    privateJobs.doc(ids.conflict).set({ contact: 'stored-conflict' }),
    privateJobs.doc(ids.orphan).set({ contact: 'orphan-contact' }),
  ]);
  setDiagnosticContext('global blocking verification', 'checking blocked preflight and unchanged documents');
  const blockedPreflight = await migrator.preflightAll();
  assert.equal(blockedPreflight.status, 'blocked-for-review');
  const blockedApply = await migrator.applyPreflight(blockedPreflight);
  assert.equal(blockedApply.status, 'blocked-for-review');
  assert.equal(blockedApply.applied, 0);
  const blockedCandidate = (await jobs.doc(ids.blockedCandidate).get()).data();
  assert.equal(blockedCandidate.contact, 'must-remain-public-until-review');
  assert.equal((await privateJobs.doc(ids.blockedCandidate).get()).exists, false);
  const unknownJob = (await jobs.doc(ids.unknown).get()).data();
  assert.equal(unknownJob.contact, 'unknown-contact');
  assert.equal(unknownJob.customField, unclassifiedFixtureMarker);
  const unapprovedJob = (await jobs.doc(ids.unapproved).get()).data();
  assert.equal(unapprovedJob.contact, 'unapproved-contact');
  assert.equal(unapprovedJob.salary, 'unapproved-salary');
  assert.equal(unapprovedJob.eventDate, 'unapproved-event-date');
  assert.equal(unapprovedJob.date, 'unapproved-date');
  assert.equal((await jobs.doc(ids.conflict).get()).get('contact'), 'legacy-conflict');
  assert.equal((await privateJobs.doc(ids.conflict).get()).get('contact'), 'stored-conflict');
  assert.equal((await privateJobs.doc(ids.orphan).get()).get('contact'), 'orphan-contact');
  for (const value of [
    'unknown-contact', unclassifiedFixtureMarker, 'unapproved-contact', 'unapproved-salary',
    'unapproved-event-date', 'unapproved-date', 'legacy-conflict', 'stored-conflict',
    'must-remain-public-until-review', 'orphan-contact',
  ]) {
    assert.equal(JSON.stringify([blockedPreflight, blockedApply]).includes(value), false);
  }

  console.log('Legacy job contact migration Emulator integration passed: complete preflight, eight private fields, idempotence, global blocking and private-value-free reports.');
}

main().catch((error) => {
  reportSanitizedFailure(error);
  process.exitCode = 1;
}).finally(async () => {
  setDiagnosticContext('fixture cleanup', 'deleting only UUID-scoped fixtures created by this run');
  const fixtureReferences = Object.values(ids).flatMap((id) => [
    db.collection('jobs').doc(id),
    db.collection('job_private').doc(id),
  ]);
  const cleanupFailures = await Promise.all(fixtureReferences.map(async (reference) => {
    try {
      await reference.delete();
      return (await reference.get()).exists;
    } catch (_) {
      return true;
    }
  }));
  if (cleanupFailures.some(Boolean)) {
    reportSanitizedFailure(new Error('Fixture cleanup did not complete.'),
      'fixture cleanup', 'verifying removal of UUID-scoped fixtures');
    process.exitCode = 1;
  }
  try {
    await admin.app().delete();
  } catch (_) {
    reportSanitizedFailure(new Error('Firebase Admin shutdown failed.'),
      'fixture cleanup', 'shutting down the local Firebase Admin client');
    process.exitCode = 1;
  }
});
