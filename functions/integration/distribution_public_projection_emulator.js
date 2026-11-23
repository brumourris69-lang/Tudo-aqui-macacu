'use strict';

const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const path = require('node:path');
const { createRequire } = require('node:module');
const root = path.resolve(__dirname, '../..');
const requireFromFunctions = createRequire(path.join(root, 'functions', 'package.json'));
const { initializeApp: initializeAdminApp, deleteApp: deleteAdminApp } = requireFromFunctions('firebase-admin/app');
const { getFirestore: getAdminFirestore, Timestamp } = requireFromFunctions('firebase-admin/firestore');
const { getAuth: getAdminAuth } = requireFromFunctions('firebase-admin/auth');
const { initializeApp, deleteApp } = requireFromFunctions('firebase/app');
const {
  getAuth, connectAuthEmulator, createUserWithEmailAndPassword,
  signInWithCustomToken, deleteUser,
} = requireFromFunctions('firebase/auth');
const {
  connectFirestoreEmulator, doc, getDocFromServer, collection, query, where,
  orderBy, documentId, limit, getDocsFromServer, setDoc, deleteDoc, runTransaction,
  serverTimestamp, Timestamp: ClientTimestamp,
} = requireFromFunctions('firebase/firestore');

const projectId = 'demo-universal-search';
const expectedFirestoreHost = process.env.DISTRIBUTION_TEST_FIRESTORE_HOST || '127.0.0.1:8087';
const expectedAuthHost = process.env.DISTRIBUTION_TEST_AUTH_HOST || '127.0.0.1:9097';
const useEmailAdminPolicy = process.env.DISTRIBUTION_TEST_EMAIL_ADMIN === 'true';
const suffix = randomUUID().replaceAll('-', '');
const adminApp = initializeAdminApp({ projectId }, `distribution-projection-fixtures-${suffix}`);
const adminDb = getAdminFirestore(adminApp);
const adminAuth = getAdminAuth(adminApp);
const publicApp = initializeApp({
  apiKey: 'demo-emulator-api-key', projectId, appId: `demo-public-${suffix}`,
}, `distribution-projection-public-${suffix}`);
const publicDb = requireFromFunctions('firebase/firestore').getFirestore(publicApp);
const userApp = initializeApp({
  apiKey: 'demo-emulator-api-key', authDomain: `${projectId}.firebaseapp.com`,
  projectId, appId: `demo-user-${suffix}`,
}, `distribution-projection-user-${suffix}`);
const userAuth = getAuth(userApp);
const userDb = requireFromFunctions('firebase/firestore').getFirestore(userApp);
const adminClientApp = initializeApp({
  apiKey: 'demo-emulator-api-key', projectId, appId: `demo-admin-${suffix}`,
}, `distribution-projection-admin-${suffix}`);
const adminClientAuth = getAuth(adminClientApp);
const adminClientDb = requireFromFunctions('firebase/firestore').getFirestore(adminClientApp);
let userCredential;
let adminCredential;
let adminUid;
const fixturePaths = [];

function assertLocalOnly() {
  assert.equal(process.env.GCLOUD_PROJECT, projectId);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, expectedFirestoreHost);
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, expectedAuthHost);
  assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
  assert.equal(process.env.FIREBASE_TOKEN, undefined);
  assert.equal(JSON.parse(process.env.FIREBASE_CONFIG || '{}').projectId, projectId);
  for (const endpoint of [expectedFirestoreHost, expectedAuthHost]) {
    const parsed = new URL(`http://${endpoint}`);
    assert.equal(parsed.hostname, '127.0.0.1');
    assert.ok(Number(parsed.port) > 0 && Number(parsed.port) < 65536);
    assert.equal(parsed.pathname, '/');
  }
  const firestoreUrl = new URL(`http://${expectedFirestoreHost}`);
  connectFirestoreEmulator(publicDb, firestoreUrl.hostname, Number(firestoreUrl.port));
  connectFirestoreEmulator(userDb, firestoreUrl.hostname, Number(firestoreUrl.port));
  connectFirestoreEmulator(adminClientDb, firestoreUrl.hostname, Number(firestoreUrl.port));
  connectAuthEmulator(userAuth, `http://${expectedAuthHost}`, { disableWarnings: true });
  connectAuthEmulator(adminClientAuth, `http://${expectedAuthHost}`, { disableWarnings: true });
}

async function seed(pathname, data) {
  fixturePaths.push(pathname);
  await adminDb.doc(pathname).set(data);
}

async function assertPermissionDenied(label, operation) {
  await assert.rejects(operation, { code: 'permission-denied' }, label);
}

async function main() {
  assertLocalOnly();
  const basicId = `distribution-basic-${suffix}`;
  const premiumId = `distribution-premium-${suffix}`;
  const expiredId = `distribution-expired-${suffix}`;
  const draftId = `distribution-draft-${suffix}`;
  const updatedAt = Timestamp.now();
  const envelope = (id, publicData) => ({
    visibility: 'public', sourceId: id, schemaVersion: 1, updatedAt, publicData,
  });

  await seed(`establishments/${basicId}`, {
    name: 'Comércio sintético', published: true, active: true,
    deleted: false, listingTier: 'basic', description: 'Privado no canônico.',
  });
  await seed(`beta_public_catalog/establishments_basic/items/${basicId}`, envelope(basicId, {
    name: 'Comércio sintético', category: 'Comércio', location: 'Centro',
  }));
  const premiumUntil = Timestamp.fromMillis(Date.now() + 60 * 60 * 1000);
  await seed(`establishments/${premiumId}`, {
    name: 'Premium sintético', published: true, active: true,
    deleted: false, listingTier: 'premium', premiumUntil,
  });
  await seed(`beta_public_catalog/establishments_basic/items/${premiumId}`, envelope(premiumId, {
    name: 'Premium sintético', category: 'Comércio',
  }));
  await seed(`beta_public_catalog/establishments_premium/items/${premiumId}`, {
    ...envelope(premiumId, { description: 'Descrição Premium sintética.' }),
    listingTier: 'premium', premiumUntil,
  });
  const expiredUntil = Timestamp.fromMillis(Date.now() - 60_000);
  await seed(`establishments/${expiredId}`, {
    name: 'Premium expirado sintético', published: true, active: true,
    deleted: false, listingTier: 'premium', premiumUntil: expiredUntil,
  });
  await seed(`beta_public_catalog/establishments_basic/items/${expiredId}`, envelope(expiredId, {
    name: 'Premium expirado sintético', category: 'Comércio',
  }));
  await seed(`beta_public_catalog/establishments_premium/items/${expiredId}`, {
    ...envelope(expiredId, { description: 'Não deve ser lida.' }),
    listingTier: 'premium', premiumUntil: expiredUntil,
  });
  await seed(`establishments/${draftId}`, {
    name: 'Rascunho sintético', published: false, active: true,
    deleted: false, listingTier: 'basic',
  });
  await seed(`beta_public_catalog/establishments_basic/items/${draftId}`, {
    ...envelope(draftId, { name: 'Rascunho sintético', category: 'Comércio' }),
    visibility: 'draft',
  });
  await seed(`home_pages/published`, { title: 'Home sintética', published: true });
  await seed(`home_pages/draft`, { title: 'Rascunho privado', published: false });
  const bannerId = `distribution-banner-${suffix}`;
  await seed(`ads/${bannerId}`, {
    title: 'Banner sintético', businessId: basicId, published: true, active: true,
  });
  await seed(`beta_public_catalog/ads/items/${bannerId}`, envelope(bannerId, {
    title: 'Banner sintético', businessId: basicId,
  }));
  const utilityId = `distribution-utility-${suffix}`;
  await seed(`utilities/${utilityId}`, {
    title: 'Utilidade sintética', active: true, published: true,
  });
  await seed(`beta_public_catalog/utilities/items/${utilityId}`, envelope(utilityId, {
    title: 'Utilidade sintética',
  }));

  userCredential = await createUserWithEmailAndPassword(
    userAuth, `projection-${suffix}@example.invalid`, `Local-${suffix}-Aa1!`,
  );

  const page = await getDocsFromServer(query(
    collection(publicDb, 'beta_public_catalog', 'establishments_basic', 'items'),
    where('visibility', '==', 'public'), orderBy(documentId()), limit(40),
  ));
  assert.ok(page.docs.some(snapshot => snapshot.id === basicId));

  adminUid = `projection-admin-${suffix}`;
  const adminEmail = useEmailAdminPolicy
    ? process.env.DISTRIBUTION_TEST_ADMIN_EMAIL
    : `projection-admin-${suffix}@example.invalid`;
  assert.ok(typeof adminEmail === 'string' && adminEmail.includes('@'));
  if (useEmailAdminPolicy) {
    adminCredential = await createUserWithEmailAndPassword(
      adminClientAuth, adminEmail, `Local-${suffix}-Aa1!`,
    );
    adminUid = adminCredential.user.uid;
  } else {
    await adminAuth.createUser({ uid: adminUid, email: adminEmail });
    await adminAuth.setCustomUserClaims(adminUid, { admin: true, adminVersion: 'fixture-v1' });
  }
  await seed(`admin_authorizations/${adminUid}`, {
    enabled: true, pending: false, version: 'fixture-v1',
  });
  if (!useEmailAdminPolicy) {
    adminCredential = await signInWithCustomToken(
      adminClientAuth, await adminAuth.createCustomToken(adminUid),
    );
  }
  const adminPublishedId = `distribution-admin-published-${suffix}`;
  const adminCanonicalRef = doc(adminClientDb, 'establishments', adminPublishedId);
  const adminProjectionRef = doc(
    adminClientDb, 'beta_public_catalog', 'establishments_basic', 'items', adminPublishedId,
  );
  const adminPremiumProjectionRef = doc(
    adminClientDb, 'beta_public_catalog', 'establishments_premium', 'items', adminPublishedId,
  );
  const adminPremiumUntil = ClientTimestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000));
  await runTransaction(adminClientDb, async (transaction) => {
    await transaction.get(adminCanonicalRef);
    transaction.set(adminCanonicalRef, {
      name: 'Publicação Admin sintética', title: 'Publicação Admin sintética',
      category: 'Comércio', published: true, active: true, deleted: false,
      listingTier: 'premium', premiumUntil: adminPremiumUntil,
      updatedAt: serverTimestamp(),
    });
    transaction.set(adminProjectionRef, {
      ...envelope(adminPublishedId, {
        name: 'Publicação Admin sintética', category: 'Comércio',
      }),
      updatedAt: serverTimestamp(),
    });
    transaction.set(adminPremiumProjectionRef, {
      visibility: 'public', sourceId: adminPublishedId, schemaVersion: 1,
      updatedAt: serverTimestamp(), listingTier: 'premium',
      premiumUntil: adminPremiumUntil,
      publicData: { description: 'Descrição Premium publicada pela transação Admin.' },
    });
  });
  assert.equal((await getDocFromServer(adminProjectionRef)).data().visibility, 'public');
  assert.equal(
    (await getDocFromServer(doc(
      publicDb, 'beta_public_catalog', 'establishments_premium', 'items', adminPublishedId,
    ))).data().publicData.description,
    'Descrição Premium publicada pela transação Admin.',
  );
  await assertPermissionDenied('Admin cannot write a projection without a canonical transaction', runTransaction(adminClientDb, async (transaction) => {
    transaction.set(adminProjectionRef, {
      ...envelope(adminPublishedId, {
        name: 'Projeção fora da transação canônica', category: 'Comércio',
      }),
      updatedAt: serverTimestamp(),
    });
  }));
  await assertPermissionDenied('Admin cannot unpublish canonical content while leaving public projections', runTransaction(adminClientDb, async (transaction) => {
    transaction.update(adminCanonicalRef, { published: false, updatedAt: serverTimestamp() });
  }));
  await assertPermissionDenied('Admin cannot delete canonical content while leaving public projections', runTransaction(adminClientDb, async (transaction) => {
    transaction.delete(adminCanonicalRef);
  }));
  await runTransaction(adminClientDb, async (transaction) => {
    const canonical = await transaction.get(adminCanonicalRef);
    transaction.update(adminCanonicalRef, { published: false, updatedAt: serverTimestamp() });
    transaction.delete(adminProjectionRef);
    transaction.delete(adminPremiumProjectionRef);
    assert.equal(canonical.data().published, true);
  });
  await assertPermissionDenied('unpublished establishment projection is not public', getDocFromServer(doc(
    publicDb, 'beta_public_catalog', 'establishments_basic', 'items', adminPublishedId,
  )));
  await assertPermissionDenied('unpublished Premium projection is not public', getDocFromServer(doc(
    publicDb, 'beta_public_catalog', 'establishments_premium', 'items', adminPublishedId,
  )));

  const adminBasicId = `distribution-admin-basic-${suffix}`;
  const adminBasicCanonicalRef = doc(adminClientDb, 'establishments', adminBasicId);
  const adminBasicProjectionRef = doc(
    adminClientDb, 'beta_public_catalog', 'establishments_basic', 'items', adminBasicId,
  );
  const absentPremiumProjectionRef = doc(
    adminClientDb, 'beta_public_catalog', 'establishments_premium', 'items', adminBasicId,
  );
  fixturePaths.push(
    `establishments/${adminBasicId}`,
    `beta_public_catalog/establishments_basic/items/${adminBasicId}`,
  );
  await runTransaction(adminClientDb, async (transaction) => {
    await transaction.get(adminBasicCanonicalRef);
    transaction.set(adminBasicCanonicalRef, {
      name: 'Estabelecimento Básico sintético', category: 'Comércio',
      published: true, active: true, deleted: false, listingTier: 'basic',
      premiumUntil: null, updatedAt: serverTimestamp(),
    });
    transaction.set(adminBasicProjectionRef, {
      ...envelope(adminBasicId, {
        name: 'Estabelecimento Básico sintético', category: 'Comércio',
      }),
      updatedAt: serverTimestamp(),
    });
    // The production repository skips this delete when no Premium projection exists.
  });
  assert.equal((await getDocFromServer(adminBasicProjectionRef)).data().visibility, 'public');
  await assertPermissionDenied(
    'ordinary user cannot delete a public Basic projection',
    deleteDoc(doc(
      userDb, 'beta_public_catalog', 'establishments_basic', 'items', adminBasicId,
    )),
  );
  await assertPermissionDenied(
    'Admin cannot delete an absent Premium projection for a visible Basic establishment',
    runTransaction(adminClientDb, async (transaction) => {
      await transaction.get(adminBasicCanonicalRef);
      transaction.delete(absentPremiumProjectionRef);
    }),
  );
  await runTransaction(adminClientDb, async (transaction) => {
    await transaction.get(adminBasicCanonicalRef);
    const premiumProjection = await transaction.get(absentPremiumProjectionRef);
    transaction.update(adminBasicCanonicalRef, {
      active: false, published: false, deleted: true,
      deletedAt: serverTimestamp(), updatedAt: serverTimestamp(),
    });
    transaction.delete(adminBasicProjectionRef);
    if (premiumProjection.exists()) transaction.delete(absentPremiumProjectionRef);
  });
  await assertPermissionDenied(
    'unpublished Basic projection is not public after Admin removal',
    getDocFromServer(doc(
      publicDb, 'beta_public_catalog', 'establishments_basic', 'items', adminBasicId,
    )),
  );

  const downgradeId = `distribution-admin-premium-to-basic-${suffix}`;
  const downgradeCanonicalRef = doc(adminClientDb, 'establishments', downgradeId);
  const downgradeBasicRef = doc(
    adminClientDb, 'beta_public_catalog', 'establishments_basic', 'items', downgradeId,
  );
  const downgradePremiumRef = doc(
    adminClientDb, 'beta_public_catalog', 'establishments_premium', 'items', downgradeId,
  );
  const downgradePremiumUntil = ClientTimestamp.fromDate(new Date(Date.now() + 60 * 60 * 1000));
  fixturePaths.push(
    `establishments/${downgradeId}`,
    `beta_public_catalog/establishments_basic/items/${downgradeId}`,
    `beta_public_catalog/establishments_premium/items/${downgradeId}`,
  );
  await runTransaction(adminClientDb, async (transaction) => {
    await transaction.get(downgradeCanonicalRef);
    transaction.set(downgradeCanonicalRef, {
      name: 'Premium para Básico sintético', category: 'Comércio',
      published: true, active: true, deleted: false, listingTier: 'premium',
      premiumUntil: downgradePremiumUntil, updatedAt: serverTimestamp(),
    });
    transaction.set(downgradeBasicRef, {
      ...envelope(downgradeId, {
        name: 'Premium para Básico sintético', category: 'Comércio',
      }),
      updatedAt: serverTimestamp(),
    });
    transaction.set(downgradePremiumRef, {
      visibility: 'public', sourceId: downgradeId, schemaVersion: 1,
      updatedAt: serverTimestamp(), listingTier: 'premium',
      premiumUntil: downgradePremiumUntil, publicData: {},
    });
  });
  await runTransaction(adminClientDb, async (transaction) => {
    await transaction.get(downgradeCanonicalRef);
    await transaction.get(downgradeBasicRef);
    const premiumProjection = await transaction.get(downgradePremiumRef);
    transaction.update(downgradeCanonicalRef, {
      listingTier: 'basic', premiumUntil: null, updatedAt: serverTimestamp(),
    });
    transaction.set(downgradeBasicRef, {
      ...envelope(downgradeId, {
        name: 'Premium para Básico sintético', category: 'Comércio',
      }),
      updatedAt: serverTimestamp(),
    });
    if (premiumProjection.exists()) transaction.delete(downgradePremiumRef);
  });
  assert.equal((await getDocFromServer(downgradeBasicRef)).data().visibility, 'public');
  await assertPermissionDenied(
    'Premium projection is inaccessible after a synchronized downgrade to Basic',
    getDocFromServer(doc(
      publicDb, 'beta_public_catalog', 'establishments_premium', 'items', downgradeId,
    )),
  );

  const basicRef = doc(publicDb, 'beta_public_catalog', 'establishments_basic', 'items', basicId);
  const basic = await getDocFromServer(basicRef);
  assert.equal(basic.data().sourceId, basicId);
  assert.deepEqual(Object.keys(basic.data().publicData).sort(), ['category', 'location', 'name']);
  await assertPermissionDenied('canonical establishment stays private', getDocFromServer(doc(publicDb, 'establishments', basicId)));
  await assertPermissionDenied('draft basic projection is private', getDocFromServer(doc(publicDb, 'beta_public_catalog', 'establishments_basic', 'items', draftId)));
  await assertPermissionDenied('draft Home page is private', getDocFromServer(doc(publicDb, 'home_pages', 'draft')));

  const premium = await getDocFromServer(doc(
    publicDb, 'beta_public_catalog', 'establishments_premium', 'items', premiumId,
  ));
  assert.equal(premium.data().publicData.description, 'Descrição Premium sintética.');
  const banner = await getDocFromServer(doc(publicDb, 'beta_public_catalog', 'ads', 'items', bannerId));
  assert.equal(banner.data().publicData.businessId, basicId);
  const bannerPage = await getDocsFromServer(query(
    collection(publicDb, 'beta_public_catalog', 'ads', 'items'),
    where('visibility', '==', 'public'), orderBy(documentId()), limit(40),
  ));
  assert.ok(bannerPage.docs.some(snapshot => snapshot.id === bannerId));
  const utility = await getDocFromServer(doc(publicDb, 'beta_public_catalog', 'utilities', 'items', utilityId));
  assert.equal(utility.data().publicData.title, 'Utilidade sintética');
  await assertPermissionDenied('expired Premium projection is private', getDocFromServer(doc(
    publicDb, 'beta_public_catalog', 'establishments_premium', 'items', expiredId,
  )));

  await assertPermissionDenied('ordinary user cannot write a public projection', setDoc(
    doc(userDb, 'beta_public_catalog', 'establishments_basic', 'items', `unauthorized-${suffix}`),
    {
      ...envelope(`unauthorized-${suffix}`, { name: 'Não autorizado' }),
      updatedAt: serverTimestamp(),
    },
  ));
  await assertPermissionDenied('ordinary user cannot write canonical content', setDoc(
    doc(userDb, 'establishments', `unauthorized-${suffix}`), { name: 'Não autorizado' },
  ));
  assert.equal((await getDocFromServer(doc(publicDb, 'home_pages', 'published'))).data().title, 'Home sintética');

  process.stdout.write('PASS: cliente público lê Basic/Premium vigente, banners, utilidades e Home; Admin publica e despublica Basic/Premium na transação canônica; Rules negam projeção isolada, despublicação/remoção canônica sem limpeza das projeções, canônico público, rascunhos, Premium vencido e gravações de usuário comum.\n');
}

main().catch(error => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}).finally(async () => {
  for (const pathname of fixturePaths.reverse()) {
    try { await adminDb.doc(pathname).delete(); } catch {}
  }
  if (userCredential) {
    try { await deleteUser(userCredential.user); } catch {}
  }
  if (adminCredential) {
    try { await deleteUser(adminCredential.user); } catch {}
  } else if (adminUid) {
    try { await adminAuth.deleteUser(adminUid); } catch {}
  }
  await Promise.all([
    deleteApp(publicApp), deleteApp(userApp), deleteApp(adminClientApp), deleteAdminApp(adminApp),
  ]);
});
