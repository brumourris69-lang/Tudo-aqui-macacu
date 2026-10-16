'use strict';

const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

const project = process.env.GCLOUD_PROJECT;
assert.equal(project, 'demo-universal-search', 'Refusing a Firebase project outside the disposable demo.');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: project });
const db = admin.firestore();
const { FieldPath } = require('firebase-admin/firestore');
const { createLegacyJobInventory } = require('../legacy_job_inventory');
const run = `legacy-inventory-${randomUUID()}`;
const ids = {
  paired: `${run}-paired`,
  legacy: `${run}-legacy`,
  conflict: `${run}-conflict`,
  unknown: `${run}-unknown`,
  orphan: `${run}-orphan`,
};

async function main() {
  const jobs = db.collection('jobs');
  const privateJobs = db.collection('job_private');
  const created = [];
  async function seed(reference, data) {
    await reference.set(data);
    created.push(reference);
  }
  try {
    await seed(jobs.doc(ids.paired), { title: 'Vaga fictícia pareada', published: true });
    await seed(privateJobs.doc(ids.paired), { contact: 'private-paired@example.invalid' });
    await seed(jobs.doc(ids.legacy), { title: 'Vaga fictícia legada', published: true,
      contact: 'legacy-contact@example.invalid', phone: '000-111', whatsapp: 'fake-whatsapp',
      link: 'https://example.invalid/fake', instagram: 'fake-instagram', maps: 'fake-map',
      mapsUrl: 'fake-map-url', additionalInfo: 'fake-admin-info', salary: 'unapproved-salary',
      eventDate: 'unapproved-event-date', date: 'unapproved-date' });
    await seed(jobs.doc(ids.conflict), {
      title: 'Vaga fictícia com conflito', contact: 'legacy-conflict@example.invalid' });
    await seed(privateJobs.doc(ids.conflict), { contact: 'private-conflict@example.invalid' });
    await seed(jobs.doc(ids.unknown), {
      title: 'Vaga fictícia com campo desconhecido', customLegacy: 'unknown-private-value' });
    await seed(privateJobs.doc(ids.orphan), { contact: 'orphan-contact@example.invalid' });

    const inventory = createLegacyJobInventory({ db, FieldPath, pageSize: 2 });
    const report = await inventory.inventoryAll();
    const reviewed = new Map(report.documents.map((document) => [document.jobId, document]));
    assert.equal(reviewed.has(ids.paired), false);
    assert.deepEqual(reviewed.get(ids.legacy).privateFieldsPresent,
      ['contact', 'phone', 'whatsapp', 'link', 'instagram', 'maps', 'mapsUrl', 'additionalInfo']);
    assert.deepEqual(reviewed.get(ids.legacy).unapprovedFields, ['date', 'eventDate', 'salary']);
    assert.equal(reviewed.get(ids.legacy).privateDocumentMissing, true);
    assert.deepEqual(reviewed.get(ids.conflict).conflictingPrivateFields, ['contact']);
    assert.deepEqual(reviewed.get(ids.unknown).unclassifiedFields, ['customLegacy']);
    assert.equal(report.orphanDocuments.some((document) =>
      document.jobId === ids.orphan && document.category === 'orphan-private-document'), true);
    const serialized = JSON.stringify(report);
    for (const privateValue of ['private-paired@example.invalid', 'legacy-contact@example.invalid',
      'legacy-conflict@example.invalid', 'private-conflict@example.invalid', 'orphan-contact@example.invalid',
      'unknown-private-value', 'fake-admin-info']) {
      assert.equal(serialized.includes(privateValue), false, 'report must not include private fixture values');
    }
    console.log('Legacy job inventory Emulator integration passed: pairs, missing private docs, orphans, conflicts, unapproved and unknown fields; report contains no private values.');
  } finally {
    await Promise.all(created.map((reference) => reference.delete().catch(() => {})));
  }
}

main().catch((error) => {
  console.error(error.name || 'IntegrationError');
  process.exitCode = 1;
}).finally(async () => {
  await admin.app().delete().catch(() => {});
});
