'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const catalog = require('./data/explorar-macacu-1.0.json');
const PROJECT_ID = 'demo-universal-search';
const EXPECTED_COUNTS = Object.freeze({
  cachoeiras_pocos_lagoas: 36,
  trilhas_montanhas: 7,
  parques_reservas: 6,
  historia_cultura: 10,
  roteiros_turisticos: 5,
  mirantes: 1,
});

function normalizeName(value) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function documentId(category, title) {
  const slug = normalizeName(title).replace(/\s+/g, '-');
  return `explorar-${category}-${slug}`;
}

function flattenCatalog(source = catalog) {
  return source.categories.flatMap((category) =>
    category.items.map((item, index) => ({
      ...item,
      category: category.key,
      categoryName: category.name,
      order: index + 1,
      id: documentId(category.key, item.title),
    })),
  );
}

function validateCatalog(source = catalog) {
  const keys = source.categories.map((category) => category.key);
  if (source.schemaVersion !== 1 ||
      JSON.stringify(keys) !== JSON.stringify(Object.keys(EXPECTED_COUNTS))) {
    throw new Error('Catalog schema or category order is invalid.');
  }
  for (const category of source.categories) {
    if (category.items.length !== EXPECTED_COUNTS[category.key]) {
      throw new Error(`Unexpected item count for ${category.key}.`);
    }
  }
  const items = flattenCatalog(source);
  if (items.length !== 65 ||
      new Set(items.map((item) => item.id)).size !== items.length ||
      new Set(items.map((item) => normalizeName(item.title))).size !== items.length) {
    throw new Error('Catalog contains an unexpected total or duplicate.');
  }
  for (const item of items) {
    if (!item.title.trim() || item.title !== item.title.trim()) {
      throw new Error('Catalog contains an empty or malformed title.');
    }
  }
  return items;
}

function draftDocument(item) {
  return {
    title: item.title,
    category: item.category,
    ...(item.subcategory ? { subcategory: item.subcategory } : {}),
    iconKey: 'turismo',
    order: item.order,
    published: false,
    active: false,
    deleted: false,
  };
}

function planImport(items, existingDocuments) {
  const byId = new Map(existingDocuments.map((document) => [document.id, document]));
  const byName = new Map();
  for (const document of existingDocuments) {
    const data = document.data || {};
    const title = (data.title || data.name || '').toString();
    const key = normalizeName(title);
    if (key) byName.set(key, [...(byName.get(key) || []), document]);
  }

  const create = [];
  const existing = [];
  const conflicts = [];
  for (const item of items) {
    const sameId = byId.get(item.id);
    if (sameId) {
      const oldTitle = (sameId.data.title || sameId.data.name || '').toString();
      if (normalizeName(oldTitle) !== normalizeName(item.title)) {
        conflicts.push({ id: item.id, title: item.title });
      } else {
        existing.push({ id: item.id, reason: 'id' });
      }
      continue;
    }
    const sameName = byName.get(normalizeName(item.title)) || [];
    if (sameName.length) {
      existing.push({ id: sameName[0].id, reason: 'name' });
      continue;
    }
    create.push(item);
  }
  return { create, existing, conflicts };
}

function verifyBackup(directory, checksumPath) {
  if (!directory || !checksumPath || !fs.existsSync(directory) ||
      !fs.existsSync(checksumPath)) {
    throw new Error('A verified pre-import Emulator export is required.');
  }
  const rows = fs.readFileSync(checksumPath, 'utf8').trim().split(/\r?\n/);
  const expected = new Map(rows.map((row) => {
    const match = /^([a-f0-9]{64})  (.+)$/i.exec(row);
    if (!match) throw new Error('Backup checksum manifest is malformed.');
    return [match[2].replaceAll('\\', '/'), match[1].toLowerCase()];
  }));
  const actualFiles = [];
  function walk(current, relative = '') {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const name = relative ? `${relative}/${entry.name}` : entry.name;
      const target = path.join(current, entry.name);
      if (entry.isDirectory()) walk(target, name);
      else if (entry.isFile()) actualFiles.push([name.replaceAll('\\', '/'), target]);
    }
  }
  walk(directory);
  if (actualFiles.length !== expected.size) {
    throw new Error('Backup file inventory changed after verification.');
  }
  for (const [relative, filename] of actualFiles) {
    const digest = crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
    if (expected.get(relative) !== digest) {
      throw new Error('Backup integrity verification failed.');
    }
  }
}

async function verifyLocalEnvironment(env, configPath) {
  if (env.LOCAL_TOURISM_IMPORT_CONFIRM !== PROJECT_ID ||
      env.GCLOUD_PROJECT !== PROJECT_ID || env.GOOGLE_CLOUD_PROJECT !== PROJECT_ID ||
      env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8087' ||
      env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9097' ||
      env.GOOGLE_APPLICATION_CREDENTIALS || env.FIREBASE_TOKEN) {
    throw new Error('Explicit demo project and loopback Emulator settings are required.');
  }
  let firebaseConfig;
  try { firebaseConfig = JSON.parse(env.FIREBASE_CONFIG || '{}'); }
  catch (_) { throw new Error('FIREBASE_CONFIG is not valid JSON.'); }
  if (firebaseConfig.projectId !== PROJECT_ID) {
    throw new Error('FIREBASE_CONFIG must identify only the demo Emulator project.');
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  if (config.emulators?.auth?.host !== '127.0.0.1' ||
      config.emulators.auth.port !== 9097 ||
      config.emulators?.firestore?.host !== '127.0.0.1' ||
      config.emulators.firestore.port !== 8087 ||
      config.emulators?.hub?.host !== '127.0.0.1' ||
      config.emulators.hub.port !== 4407 ||
      !config.firestore?.rules ||
      path.resolve(path.dirname(configPath), config.firestore.rules) !==
        path.resolve(__dirname, '..', 'firestore.beta.rules')) {
    throw new Error('The supplied config does not point to the expected local Beta Rules.');
  }
  const response = await fetch('http://127.0.0.1:4407/emulators', {
    signal: AbortSignal.timeout(3000),
  });
  if (!response.ok) throw new Error('Local Emulator Hub health check failed.');
  const emulators = await response.json();
  const active = Object.keys(emulators).filter((name) => !['hub', 'logging'].includes(name)).sort();
  if (JSON.stringify(active) !== JSON.stringify(['auth', 'firestore']) ||
      emulators.auth?.host !== '127.0.0.1' || emulators.auth?.port !== 9097 ||
      emulators.firestore?.host !== '127.0.0.1' || emulators.firestore?.port !== 8087) {
    throw new Error('Only the expected loopback Auth and Firestore Emulators may be active.');
  }
}

async function runImport({ db, fieldValue, source = catalog }) {
  const items = validateCatalog(source);
  const snapshot = await db.collection('routes').get();
  const existingDocuments = snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
  const plan = planImport(items, existingDocuments);
  if (plan.conflicts.length) {
    throw new Error(`ID collision detected for ${plan.conflicts.length} catalog item(s); no writes made.`);
  }
  if (plan.create.length) {
    const batch = db.batch();
    for (const item of plan.create) {
      const ref = db.collection('routes').doc(item.id);
      batch.create(ref, {
        ...draftDocument(item),
        createdAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  return {
    project: PROJECT_ID,
    collection: 'routes',
    catalogCount: items.length,
    created: plan.create.length,
    alreadyPresent: plan.existing.length,
    conflicts: 0,
    visibility: 'all new documents are drafts and inactive',
  };
}

async function main() {
  const configPath = process.env.TOURISM_IMPORT_CONFIG;
  if (!configPath) throw new Error('TOURISM_IMPORT_CONFIG is required.');
  await verifyLocalEnvironment(process.env, configPath);
  verifyBackup(process.env.TOURISM_IMPORT_BACKUP, process.env.TOURISM_IMPORT_BACKUP_CHECKSUMS);

  const admin = require('../functions/node_modules/firebase-admin');
  admin.initializeApp({ projectId: PROJECT_ID });
  try {
    const result = await runImport({
      db: admin.firestore(),
      fieldValue: admin.firestore.FieldValue,
    });
    console.log(JSON.stringify(result));
  } finally {
    await admin.app().delete();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`Explorar Macacu import stopped safely: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  PROJECT_ID,
  catalog,
  documentId,
  draftDocument,
  flattenCatalog,
  normalizeName,
  planImport,
  runImport,
  validateCatalog,
  verifyBackup,
  verifyLocalEnvironment,
};
