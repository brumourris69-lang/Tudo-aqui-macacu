import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectId = 'demo-universal-search';
const authEndpoint = '127.0.0.1:9097';
const firestoreEndpoint = '127.0.0.1:8087';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requireFromFunctions = createRequire(path.join(root, 'functions', 'package.json'));
const { initializeApp, deleteApp } = requireFromFunctions('firebase-admin/app');
const { getAuth } = requireFromFunctions('firebase-admin/auth');
const { getFirestore } = requireFromFunctions('firebase-admin/firestore');
const command = process.argv[2];
const metadataPath = path.resolve(process.argv[3] || '');

function requireLocalRuntime() {
  assert.equal(command === 'setup' || command === 'cleanup', true,
    'Use setup|cleanup with a temporary metadata path.');
  assert.equal(process.env.GCLOUD_PROJECT, projectId);
  assert.equal(process.env.GOOGLE_CLOUD_PROJECT, projectId);
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, authEndpoint);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, firestoreEndpoint);
  assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
  assert.equal(process.env.FIREBASE_TOKEN, undefined);
  assert.ok(metadataPath.startsWith(path.resolve(os.tmpdir()) + path.sep));
  assert.match(path.basename(metadataPath), /^macacu-spark-local-fixtures-[a-f0-9-]+\.json$/u);
}

const runId = randomUUID();
const prefix = `spark-local-${runId}`;
const adminApp = initializeApp({ projectId }, `spark-local-fixtures-${runId}`);
const auth = getAuth(adminApp);
const db = getFirestore(adminApp);
const metadata = {
  schemaVersion: 1,
  projectId,
  runId,
  fixturePrefix: prefix,
  admin: {
    email: `spark-admin-${runId}@example.invalid`,
    password: `SparkLocal${runId.replaceAll('-', '').slice(0, 16)}`,
    uid: '',
    adminVersion: `spark-admin-${runId}`,
  },
  user: {
    email: `spark-user-${runId}@example.invalid`,
    password: `SparkUser${runId.replaceAll('-', '').slice(0, 16)}`,
    uid: '',
  },
  contentIds: {},
  homeMarker: runId,
  homeDraftTestTitles: [
    'Rascunho Home que não deve aparecer',
    'O que você procura hoje?Local',
  ],
};

async function writeContent(collection, id, source, { published = true } = {}) {
  const canonical = db.doc(`${collection}/${id}`);
  const projection = db.doc(`beta_public_catalog/${collection}/items/${id}`);
  await canonical.set({
    ...source,
    published,
    active: true,
    sparkLocalRunId: runId,
    createdAt: new Date(),
    updatedAt: new Date(),
    privateOwnerEmail: 'private-must-not-be-public@example.invalid',
  });
  if (published) {
    const publicData = Object.fromEntries(Object.entries(source).filter(([key]) => [
      'name', 'title', 'category', 'subcategory', 'description', 'shortDescription',
      'location', 'address', 'iconKey', 'imageUrl', 'logoUrl', 'maps', 'mapsUrl',
      'phone', 'whatsapp', 'instagram', 'type', 'employmentType', 'company',
      'eventDate', 'endDate', 'date', 'startsAt', 'startTime', 'endTime',
      'organizer', 'registrationUrl', 'contactUrl', 'link', 'destinationType',
      'destination', 'promotionTitle', 'promotionDescription', 'hours',
      'additionalInfo', 'galleryUrls', 'videoUrls', 'services', 'products',
      'artwork', 'order', 'featured', 'open', 'options',
    ].includes(key)));
    await projection.set({
      visibility: 'public', sourceId: id, schemaVersion: 1,
      updatedAt: new Date(), publicData,
    });
  }
}

async function setup() {
  assert.equal((await db.doc('home_pages/published').get()).exists, false,
    'Refusing to overwrite an existing Home page in the emulator.');
  assert.equal((await db.doc('home_pages/draft').get()).exists, false,
    'Refusing to overwrite an existing Home draft in the emulator.');

  const admin = await auth.createUser({
    email: metadata.admin.email,
    password: metadata.admin.password,
    displayName: 'Admin sintético Spark local',
    emailVerified: true,
  });
  metadata.admin.uid = admin.uid;
  await auth.setCustomUserClaims(admin.uid, {
    admin: true,
    adminVersion: metadata.admin.adminVersion,
  });
  await db.doc(`admin_authorizations/${admin.uid}`).set({
    enabled: true, pending: false, version: metadata.admin.adminVersion,
  });

  const user = await auth.createUser({
    email: metadata.user.email,
    password: metadata.user.password,
    displayName: 'Usuário sintético Spark local',
    emailVerified: true,
  });
  metadata.user.uid = user.uid;

  const storeId = `${prefix}-store`;
  const routeIds = [
    `${prefix}-tourism`,
    `${prefix}-guide`,
    `${prefix}-trail`,
    `${prefix}-history`,
  ];
  const eventId = `${prefix}-event`;
  const utilityId = `${prefix}-utility`;
  const draftId = `${prefix}-draft`;
  const tombstoneId = `${prefix}-tombstone`;
  metadata.contentIds = {
    establishments: [storeId, draftId, tombstoneId],
    routes: routeIds,
    events: [eventId],
    utilities: [utilityId],
  };
  await fs.writeFile(metadataPath, JSON.stringify(metadata, null, 2), {
    encoding: 'utf8', flag: 'wx', mode: 0o600,
  });

  await Promise.all([
    writeContent('establishments', storeId, {
      name: 'Comércio de demonstração Spark', category: 'Comércio',
      subcategory: 'Moda e acessórios',
      shortDescription: 'Registro sintético para validação local.',
      description: 'Conteúdo fictício do Emulator.', imageUrl: '',
      phone: '2220000000', whatsapp: '', instagram: '', order: 1,
    }),
    writeContent('routes', routeIds[0], {
      name: 'Ponto turístico de demonstração', category: 'Pontos turísticos',
      description: 'Conteúdo turístico sintético.', location: 'Cachoeiras de Macacu',
      imageUrl: '', order: 1,
    }),
    writeContent('routes', routeIds[1], {
      name: 'Guia turístico de demonstração', category: 'Guias turísticos',
      description: 'Guia sintético para teste local.', location: 'Centro',
      imageUrl: '', order: 2,
    }),
    writeContent('routes', routeIds[2], {
      name: 'Trilha de demonstração', category: 'Trilhas',
      description: 'Trilha sintética para teste local.', location: 'Serra',
      imageUrl: '', order: 3,
    }),
    writeContent('routes', routeIds[3], {
      name: 'História sintética', category: 'História da cidade',
      description: 'Registro histórico fictício para teste local.',
      location: 'Centro', imageUrl: '', order: 4,
    }),
    writeContent('events', eventId, {
      title: 'Evento de demonstração Spark', category: 'Cultura',
      description: 'Evento fictício do Emulator.', eventDate: '2026-11-15',
      startTime: '10:00', endTime: '12:00', location: 'Centro',
      imageUrl: '', order: 1,
    }),
    writeContent('utilities', utilityId, {
      name: 'Utilidade de demonstração', category: 'Serviços úteis',
      description: 'Serviço sintético local.', iconKey: 'info',
      destinationType: 'internal', destination: 'spark-local', order: 1,
    }),
    writeContent('establishments', draftId, {
      name: 'Rascunho invisível Spark', category: 'Alimentação',
      description: 'Não deve aparecer para visitantes.', order: 2,
    }, { published: false }),
    writeContent('establishments', tombstoneId, {
      name: 'Tombstone invisível Spark', category: 'Serviços',
      description: 'Exclusão lógica sintética.', order: 3,
    }, { published: false }),
  ]);
  await db.doc(`establishments/${tombstoneId}`).update({
    active: false, deleted: true, deletedAt: new Date(),
  });
  await db.doc('home_pages/published').set({
    sparkLocalRunId: runId,
    published: true,
    active: true,
    heroTitle: 'Tudo Aqui Macacu — Spark local',
    sectionOrder: ['banner', 'categories', 'highlights', 'events', 'tourism'],
    sections: { categories: true, highlights: true, events: true, tourism: true },
    sectionTitles: { highlights: 'Demonstração local', events: 'Eventos', tourism: 'Turismo' },
    categoryOrder: ['Comércio', 'Onde comer?', 'Serviços', 'Turismo', 'Eventos'],
    categoryIcons: { Comércio: 'store', Turismo: 'travel_explore', Eventos: 'event' },
    categoryVisible: { Comércio: true, Turismo: true, Eventos: true },
    visual: { backgroundType: 'gradient', slogan: 'Somente dados sintéticos' },
  });
  await db.doc('home_pages/draft').set({
    sparkLocalRunId: runId, published: false, active: false,
    heroTitle: 'Rascunho Home que não deve aparecer',
  });
  await fs.writeFile(metadataPath, JSON.stringify(metadata, null, 2), {
    encoding: 'utf8', mode: 0o600,
  });
  console.log(`Spark local fixtures created (${runId}); metadata kept outside the repository.`);
}

async function cleanup() {
  const saved = JSON.parse(await fs.readFile(metadataPath, 'utf8'));
  assert.equal(saved.projectId, projectId);
  assert.match(saved.fixturePrefix, /^spark-local-[a-f0-9-]+$/u);
  for (const [collection, ids] of Object.entries(saved.contentIds)) {
    for (const id of ids) {
      const canonical = db.doc(`${collection}/${id}`);
      const projection = db.doc(`beta_public_catalog/${collection}/items/${id}`);
      const current = await canonical.get();
      const prefixOwned = id.startsWith(`${saved.fixturePrefix}-`);
      const markerOwned = current.exists &&
        current.get('sparkLocalRunId') === saved.runId;
      assert.equal(prefixOwned || markerOwned, true,
        'Refusing to clean content not owned by this Spark local run.');
      if (prefixOwned || markerOwned) {
        const publicItem = await projection.get();
        if (publicItem.exists && (prefixOwned ||
            (markerOwned && publicItem.get('sourceId') === id))) {
          await projection.delete();
        }
      }
      if (markerOwned) {
        await canonical.delete();
      }
    }
  }
  for (const pageId of ['published', 'draft']) {
    const page = db.doc(`home_pages/${pageId}`);
    const current = await page.get();
    const editedByFixture = saved.homeDraftTestTitles?.includes(
      current.get('heroTitle'),
    ) ?? false;
    if (current.exists && (
      current.get('sparkLocalRunId') === saved.homeMarker ||
      editedByFixture
    )) {
      await page.delete();
    }
  }
  for (const account of [saved.admin, saved.user]) {
    if (account.uid) await db.recursiveDelete(db.doc(`users/${account.uid}`));
    if (account.uid) await db.doc(`admin_authorizations/${account.uid}`).delete();
    if (account.uid) {
      try { await auth.deleteUser(account.uid); }
      catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
    }
  }
  await fs.unlink(metadataPath);
  console.log(`Spark local fixtures cleaned (${saved.runId}); only owned IDs were removed.`);
}

try {
  requireLocalRuntime();
  if (command === 'setup') await setup();
  else await cleanup();
} finally {
  await deleteApp(adminApp);
}
