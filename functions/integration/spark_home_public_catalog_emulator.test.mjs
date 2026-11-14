import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, test } from 'node:test';
import { initializeApp as initializeAdminApp, deleteApp as deleteAdminApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  collection,
  connectFirestoreEmulator,
  doc,
  documentId,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  where,
} from 'firebase/firestore';

const projectId = 'demo-universal-search';
const expectedHost = '127.0.0.1:8787';
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST ?? '';
const runId = randomUUID().replaceAll('-', '');
const adminApp = initializeAdminApp({ projectId }, `spark-home-seed-${runId}`);
const adminDb = getAdminFirestore(adminApp);
const clientApp = initializeApp({
  apiKey: 'demo-emulator-api-key',
  appId: '1:000000000000:web:spark-home-test',
  projectId,
}, `spark-home-public-client-${runId}`);
const clientDb = (await import('firebase/firestore')).getFirestore(clientApp);
const createdPaths = [];

function assertLocalOnly() {
  if (emulatorHost !== expectedHost || process.env.GCLOUD_PROJECT !== projectId) {
    throw new Error('Test requires only demo-universal-search at 127.0.0.1:8787.');
  }
  for (const name of ['GOOGLE_APPLICATION_CREDENTIALS', 'FIREBASE_TOKEN']) {
    if (process.env[name]) throw new Error(`Refusing hosted credential environment: ${name}`);
  }
  if (process.env.FIREBASE_CONFIG) {
    let config;
    try { config = JSON.parse(process.env.FIREBASE_CONFIG); } catch { throw new Error('Invalid local Firebase config.'); }
    if (config.projectId !== projectId) throw new Error('FIREBASE_CONFIG project mismatch.');
  }
  connectFirestoreEmulator(clientDb, '127.0.0.1', 8787);
}

async function seed(path, data) {
  createdPaths.push(path);
  await adminDb.doc(path).set(data);
}

const envelope = (id, publicData) => ({
  visibility: 'public',
  sourceId: id,
  schemaVersion: 1,
  updatedAt: Timestamp.now(),
  publicData,
});

before(async () => {
  assertLocalOnly();
  const businessId = `spark-home-business-${runId}`;
  const premiumBusinessId = `spark-home-premium-${runId}`;
  const adId = `spark-home-ad-${runId}`;
  const offerId = `spark-home-offer-${runId}`;
  const eventId = `spark-home-event-${runId}`;
  const utilityId = `spark-home-utility-${runId}`;
  const jobId = `spark-home-job-${runId}`;
  const inactiveBusinessId = `spark-home-inactive-${runId}`;
  const draftEventId = `spark-home-draft-event-${runId}`;
  const premiumUntil = Timestamp.fromMillis(Date.now() + 60 * 60 * 1000);

  await seed(`home_pages/published`, {
    title: `Home sintética ${runId}`,
    active: true,
    published: true,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await seed(`home_pages/draft`, {
    title: `Rascunho privado ${runId}`,
    active: true,
    published: false,
  });
  await seed(`establishments/${businessId}`, {
    name: `Comércio sintético ${runId}`,
    published: true,
    active: true,
    deleted: false,
    listingTier: 'basic',
    description: 'Campo canônico não deve ser lido pelo visitante.',
  });
  await seed(`beta_public_catalog/establishments_basic/items/${businessId}`, envelope(businessId, {
    name: `Comércio sintético ${runId}`,
    address: 'Centro de teste',
    phone: '22223333',
    category: 'Comércio',
  }));
  await seed(`establishments/${premiumBusinessId}`, {
    name: `Comércio Premium sintético ${runId}`,
    published: true,
    active: true,
    deleted: false,
    listingTier: 'premium',
    premiumUntil,
  });
  await seed(`beta_public_catalog/establishments_basic/items/${premiumBusinessId}`, envelope(premiumBusinessId, {
    name: `Comércio Premium sintético ${runId}`,
    address: 'Centro de teste',
    phone: '22223333',
    category: 'Comércio',
  }));
  await seed(`beta_public_catalog/establishments_premium/items/${premiumBusinessId}`, {
    visibility: 'public',
    sourceId: premiumBusinessId,
    schemaVersion: 1,
    listingTier: 'premium',
    premiumUntil,
    updatedAt: Timestamp.now(),
    publicData: { description: 'Complemento Premium sintético.' },
  });
  await seed(`ads/${adId}`, {
    title: `Banner sintético ${runId}`,
    businessId,
    published: true,
    active: true,
  });
  await seed(`beta_public_catalog/ads/items/${adId}`, envelope(adId, {
    title: `Banner sintético ${runId}`,
    businessId,
    destinationType: 'establishment',
    destination: businessId,
  }));
  await seed(`offers/${offerId}`, { title: `Destaque sintético ${runId}`, published: true, active: true });
  await seed(`beta_public_catalog/offers/items/${offerId}`, envelope(offerId, {
    title: `Destaque sintético ${runId}`,
    description: 'Conteúdo público de demonstração.',
  }));
  await seed(`events/${eventId}`, { title: `Evento sintético ${runId}`, published: true, active: true });
  await seed(`beta_public_catalog/events/items/${eventId}`, envelope(eventId, {
    title: `Evento sintético ${runId}`,
    category: 'Turismo',
  }));
  await seed(`beta_public_catalog/utilities/items/${utilityId}`, envelope(utilityId, {
    title: `Utilidade sintética ${runId}`,
    category: 'Utilidades',
  }));
  await seed(`jobs/${jobId}`, {
    title: `Vaga sintética ${runId}`,
    published: true,
    active: true,
    contact: 'Campo canônico não deve ser lido pelo visitante.',
  });
  await seed(`beta_public_catalog/jobs/items/${jobId}`, envelope(jobId, {
    title: `Vaga sintética ${runId}`,
    category: 'Serviços',
    company: 'Empresa de teste',
  }));
  await seed(`establishments/${inactiveBusinessId}`, {
    name: 'Estabelecimento inativo sintético',
    published: true,
    active: false,
    deleted: false,
    listingTier: 'premium',
    premiumUntil,
  });
  await seed(`beta_public_catalog/establishments_basic/items/${inactiveBusinessId}`, envelope(inactiveBusinessId, {
    name: 'Estabelecimento inativo sintético',
    address: 'Teste',
    category: 'Comércio',
  }));
  await seed(`beta_public_catalog/establishments_premium/items/${inactiveBusinessId}`, {
    visibility: 'public',
    sourceId: inactiveBusinessId,
    schemaVersion: 1,
    listingTier: 'premium',
    premiumUntil,
    updatedAt: Timestamp.now(),
    publicData: { description: 'Projeção de inativo deve ser negada.' },
  });
  await seed(`beta_public_catalog/events/items/${draftEventId}`, {
    ...envelope(draftEventId, { title: 'Evento em rascunho sintético.' }),
    visibility: 'draft',
  });
  const expiredUntil = Timestamp.fromMillis(Date.now() - 60_000);
  const expiredId = `spark-home-expired-${runId}`;
  await seed(`establishments/${expiredId}`, {
    name: 'Premium expirado sintético', published: true, active: true,
    deleted: false, listingTier: 'premium', premiumUntil: expiredUntil,
  });
  await seed(`beta_public_catalog/establishments_basic/items/${expiredId}`, envelope(expiredId, {
    name: 'Premium expirado sintético', address: 'Teste', category: 'Comércio',
  }));
  await seed(`beta_public_catalog/establishments_premium/items/${expiredId}`, {
    visibility: 'public', sourceId: expiredId, schemaVersion: 1,
    listingTier: 'premium', premiumUntil: expiredUntil, updatedAt: Timestamp.now(),
    publicData: { description: 'Não pode ser disponibilizado após vencer.' },
  });
});

after(async () => {
  for (const path of createdPaths.reverse()) await adminDb.doc(path).delete();
  await deleteApp(clientApp);
  await deleteAdminApp(adminApp);
});

test('Home reads its published configuration and bounded public projections', async () => {
  const page = await getDoc(doc(clientDb, 'home_pages/published'));
  assert.match(page.data().title, /^Home sintética /);

  const paths = [
    ['ads', 'spark-home-ad-'],
    ['offers', 'spark-home-offer-'],
    ['events', 'spark-home-event-'],
    ['utilities', 'spark-home-utility-'],
    ['jobs', 'spark-home-job-'],
  ];
  for (const [collectionName, prefix] of paths) {
    const result = await getDocs(query(
      collection(clientDb, 'beta_public_catalog', collectionName, 'items'),
      where('visibility', '==', 'public'),
      orderBy(documentId()),
      limit(40),
    ));
    assert.ok(result.docs.some((snapshot) => snapshot.id.startsWith(prefix)));
  }
  const basic = await getDocs(query(
    collection(clientDb, 'beta_public_catalog', 'establishments_basic', 'items'),
    where('visibility', '==', 'public'),
    orderBy(documentId()),
    limit(40),
  ));
  const business = basic.docs.find((snapshot) => snapshot.id.startsWith(`spark-home-business-${runId}`));
  assert.ok(business);
  assert.deepEqual(Object.keys(business.data().publicData).sort(), ['address', 'category', 'name', 'phone']);
});

test('public projection detail resolves while canonical and draft data stay denied', async () => {
  const adId = `spark-home-ad-${runId}`;
  const ad = await getDoc(doc(clientDb, 'beta_public_catalog', 'ads', 'items', adId));
  assert.equal(ad.data().sourceId, adId);
  assert.equal(ad.data().publicData.businessId, `spark-home-business-${runId}`);
  assert.equal(ad.data().publicData.destination, `spark-home-business-${runId}`);
  await assert.rejects(getDoc(doc(clientDb, 'ads', adId)), { code: 'permission-denied' });
  await assert.rejects(getDoc(doc(clientDb, 'home_pages/draft')), { code: 'permission-denied' });

  const premiumId = `spark-home-premium-${runId}`;
  const premium = await getDoc(doc(clientDb, 'beta_public_catalog', 'establishments_premium', 'items', premiumId));
  assert.equal(premium.data().sourceId, premiumId);
  assert.equal(premium.data().publicData.description, 'Complemento Premium sintético.');
  await assert.rejects(getDoc(doc(clientDb, 'establishments', premiumId)), { code: 'permission-denied' });

  const jobId = `spark-home-job-${runId}`;
  const job = await getDoc(doc(clientDb, 'beta_public_catalog', 'jobs', 'items', jobId));
  assert.equal(job.data().sourceId, jobId);
  assert.equal(job.data().publicData.title, `Vaga sintética ${runId}`);
  assert.equal('contact' in job.data().publicData, false);
  await assert.rejects(getDoc(doc(clientDb, 'jobs', jobId)), { code: 'permission-denied' });
});

test('rules reject unbounded public queries and expired Premium projections', async () => {
  await assert.rejects(
    getDocs(query(collection(clientDb, 'beta_public_catalog', 'ads', 'items'), limit(40))),
    { code: 'permission-denied' },
  );
  await assert.rejects(
    getDocs(query(
      collection(clientDb, 'beta_public_catalog', 'ads', 'items'),
      where('visibility', '==', 'public'),
      limit(41),
    )),
    { code: 'permission-denied' },
  );
  await assert.rejects(
    getDoc(doc(clientDb, 'beta_public_catalog', 'establishments_premium', 'items', `spark-home-expired-${runId}`)),
    { code: 'permission-denied' },
  );
  await assert.rejects(
    getDoc(doc(clientDb, 'beta_public_catalog', 'establishments_premium', 'items', `spark-home-inactive-${runId}`)),
    { code: 'permission-denied' },
  );
  await assert.rejects(
    getDoc(doc(clientDb, 'beta_public_catalog', 'events', 'items', `spark-home-draft-event-${runId}`)),
    { code: 'permission-denied' },
  );
});
