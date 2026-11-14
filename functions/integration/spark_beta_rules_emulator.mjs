import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveLoopbackEmulatorEndpoint } from './spark_beta_rules_emulator_config.mjs';

const projectId = 'demo-universal-search';
const authEndpoint = resolveLoopbackEmulatorEndpoint(
  process.env.FIREBASE_AUTH_EMULATOR_HOST, 9097, 'Firebase Auth Emulator',
);
const firestoreEndpoint = resolveLoopbackEmulatorEndpoint(
  process.env.FIRESTORE_EMULATOR_HOST, 8087, 'Firestore Emulator',
);
const authHost = authEndpoint.address;
const firestoreHost = firestoreEndpoint.address;
assert.equal(process.env.GCLOUD_PROJECT, projectId);
assert.equal(process.env.GOOGLE_CLOUD_PROJECT, projectId);
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, authHost);
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, firestoreHost);
assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
assert.equal(process.env.FIREBASE_TOKEN, undefined);

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requireFromFunctions = createRequire(path.join(root, 'functions', 'package.json'));
const { initializeApp: initializeAdminApp, deleteApp: deleteAdminApp } =
  requireFromFunctions('firebase-admin/app');
const { getAuth: getAdminAuth } = requireFromFunctions('firebase-admin/auth');
const { getFirestore: getAdminFirestore } = requireFromFunctions('firebase-admin/firestore');
const { initializeApp, deleteApp } = requireFromFunctions('firebase/app');
const {
  connectAuthEmulator, createUserWithEmailAndPassword, getAuth,
  signInWithEmailAndPassword, signOut,
} = requireFromFunctions('firebase/auth');
const {
  collection, collectionGroup, connectFirestoreEmulator, deleteDoc, doc, getDocFromServer,
  getDocsFromServer, getFirestore, query, runTransaction, serverTimestamp,
  setDoc, where, limit, writeBatch, Timestamp,
} = requireFromFunctions('firebase/firestore');

const suffix = randomUUID();
const adminApp = initializeAdminApp({ projectId }, `spark-rules-admin-${suffix}`);
const adminAuth = getAdminAuth(adminApp);
const adminDb = getAdminFirestore(adminApp);
const users = [];
const apps = [];
const ownedPaths = new Set();
const preservedDocuments = new Map();
let passed = 0;

function pass(label) {
  passed++;
  console.log(`PASS ${label}`);
}

async function denied(promise, label) {
  await assert.rejects(promise, error => {
    assert.equal(error.code, 'permission-denied', label);
    return true;
  });
  pass(label);
}

async function client(label, claims = null) {
  const app = initializeApp({
    apiKey: 'demo-emulator-key',
    projectId,
    appId: `demo-${label}`,
  }, `spark-${label}-${suffix}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${authHost}`, { disableWarnings: true });
  const credential = await createUserWithEmailAndPassword(
    auth, `spark-${label}-${suffix}@example.invalid`, 'LocalOnly123!');
  users.push(credential.user.uid);
  if (claims) {
    await adminAuth.setCustomUserClaims(credential.user.uid, claims);
    await adminDb.doc(`admin_authorizations/${credential.user.uid}`).set({
      enabled: true, pending: false, version: claims.adminVersion,
    });
    ownedPaths.add(`admin_authorizations/${credential.user.uid}`);
    await credential.user.getIdToken(true);
  }
  const db = getFirestore(app);
  connectFirestoreEmulator(db, firestoreEndpoint.host, firestoreEndpoint.port);
  return { app, auth, db, uid: credential.user.uid };
}

async function guestClient() {
  const app = initializeApp({
    apiKey: 'demo-emulator-key',
    projectId,
    appId: `demo-guest`,
  }, `spark-guest-${suffix}`);
  apps.push(app);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, firestoreEndpoint.host, firestoreEndpoint.port);
  return db;
}

async function syncProfileTransaction(profileClient) {
  const user = profileClient.auth.currentUser;
  const profileRef = doc(profileClient.db, `users/${user.uid}`);
  await runTransaction(profileClient.db, async transaction => {
    const snapshot = await transaction.get(profileRef);
    transaction.set(profileRef, {
      displayName: user.displayName ?? '',
      email: user.email ?? '',
      photoUrl: user.photoURL ?? '',
      ...(!snapshot.exists() ? {
        role: 'user',
        createdAt: serverTimestamp(),
      } : {}),
      updatedAt: serverTimestamp(),
    }, { merge: true });
  });
}

async function main() {
  const rules = await readFile(path.join(root, 'firestore.beta.rules'), 'utf8');
  const loaded = await fetch(`http://${firestoreHost}/emulator/v1/projects/${projectId}:securityRules`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ rules: { files: [{ name: 'firestore.beta.rules', content: rules }] } }),
  });
  assert.equal(loaded.status, 200, 'Beta Rules must load into the isolated Emulator');

  const version = `spark-admin-${suffix}`;
  const guestDb = await guestClient();
  const visitor = await client('visitor');
  const other = await client('other');
  const admin = await client('admin', { admin: true, adminVersion: version });
  const revoked = await client('revoked', { admin: true, adminVersion: `revoked-${suffix}` });
  const pendingDeletion = await client('pending-deletion');
  await syncProfileTransaction(pendingDeletion);
  ownedPaths.add(`admin_authorizations/${revoked.uid}`);
  await adminDb.doc(`admin_authorizations/${revoked.uid}`).update({ enabled: false });

  assert.equal((await getDocFromServer(doc(guestDb, 'home_pages/published'))).exists(), false);
  assert.equal((await getDocFromServer(doc(visitor.db, 'home_pages/published'))).exists(), false);
  pass('public visitors receive a not-found snapshot when no published Home configuration exists');

  // Reproduce the startup race: independent calls can both read an absent
  // profile, then the later stale create-shaped merge is evaluated as update.
  const profileRef = doc(visitor.db, `users/${visitor.uid}`);
  assert.equal((await getDocFromServer(profileRef)).exists(), false);
  assert.equal((await getDocFromServer(profileRef)).exists(), false);
  const visitorUser = visitor.auth.currentUser;
  const createShape = {
    displayName: visitorUser.displayName ?? '',
    email: visitorUser.email ?? '',
    photoUrl: visitorUser.photoURL ?? '',
    role: 'user',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
  await setDoc(profileRef, createShape, { merge: true });
  await denied(setDoc(profileRef, createShape, { merge: true }),
    'stale simultaneous profile sync is denied by immutable createdAt Rules');
  ownedPaths.add(`users/${visitor.uid}`);

  // The fixed Flutter transaction re-reads on contention and sends an update
  // shape after another startup call has created the document.
  await adminDb.doc(`users/${visitor.uid}`).delete();
  await Promise.all([
    syncProfileTransaction(visitor),
    syncProfileTransaction(visitor),
    syncProfileTransaction(admin),
    syncProfileTransaction(admin),
  ]);
  ownedPaths.add(`users/${admin.uid}`);
  for (const profileClient of [visitor, admin]) {
    const saved = (await getDocFromServer(doc(
      profileClient.db, `users/${profileClient.uid}`))).data();
    assert.equal(saved.role, 'user');
    assert.equal(saved.email, profileClient.auth.currentUser.email);
    assert.equal(Object.hasOwn(saved, 'admin'), false);
  }
  pass('transactional profile sync handles concurrent startup for regular users and Admin without changing Rules');
  await denied(setDoc(doc(visitor.db,
    `admin_authorizations/${visitor.uid}`), {
      enabled: true, pending: false, version: `forged-${suffix}`,
    }), 'ordinary user cannot create an Admin authorization for itself');
  pass('ordinary user cannot self-elevate through admin_authorizations');

  const publicId = `spark-public-${suffix}`;
  const publicEventId = `spark-event-${suffix}`;
  const jobId = `spark-job-${suffix}`;
  const draftId = `spark-draft-${suffix}`;
  const deletedId = `spark-deleted-${suffix}`;
  const premiumId = `spark-premium-${suffix}`;
  const expiredPremiumId = `spark-premium-expired-${suffix}`;
  const inactivePremiumId = `spark-premium-inactive-${suffix}`;
  const unpublishedPremiumId = `spark-premium-unpublished-${suffix}`;
  const downgradeId = `spark-premium-downgrade-${suffix}`;
  const inactiveTransitionId = `spark-premium-inactive-transition-${suffix}`;
  const exactBoundaryId = `spark-premium-boundary-${suffix}`;
  const malformedPremiumId = `spark-premium-malformed-${suffix}`;
  const contactId = `spark-contact-${suffix}`;
  const contactQuotaPath = `users/${visitor.uid}/contact_message_limits/current`;
  const otherQuotaPath = `users/${other.uid}/contact_message_limits/current`;
  const concurrent = await client('concurrent');
  const concurrentQuotaPath = `users/${concurrent.uid}/contact_message_limits/current`;
  ownedPaths.add(`users/${concurrent.uid}`);
  const pendingQuotaPath =
    `users/${pendingDeletion.uid}/contact_message_limits/current`;
  const pendingMessageId = `${contactId}-pending-owner`;
  const pendingDeletionRequestPath =
    `account_deletion_requests/${pendingDeletion.uid}`;
  for (const pathName of [
    `users/${pendingDeletion.uid}`,
    pendingQuotaPath,
    `contact_messages/${pendingMessageId}`,
    pendingDeletionRequestPath,
  ]) ownedPaths.add(pathName);
  const proposalId = `spark-proposal-${suffix}`;
  const reviewId = `spark-review-${suffix}`;
  const canonical = (collectionId, id) => adminDb.doc(`${collectionId}/${id}`);
  const projection = (collectionId, id) => adminDb.doc(
    `beta_public_catalog/${collectionId === 'establishments'
      ? 'establishments_basic' : collectionId}/items/${id}`);
  const additionalPublicFixtures = [
    {
      collectionId: 'routes',
      id: `spark-tourism-${suffix}`,
      publicData: {
        name: 'Trilha sintética', type: 'tourism', category: 'Trilhas',
        location: 'Cachoeiras de Macacu',
      },
    },
    {
      collectionId: 'utilities',
      id: `spark-utility-${suffix}`,
      publicData: { name: 'Telefone útil sintético', category: 'Utilidades' },
    },
  ];
  for (const id of [publicId, draftId, deletedId]) {
    ownedPaths.add(`establishments/${id}`);
    ownedPaths.add(`beta_public_catalog/establishments_basic/items/${id}`);
  }
  // Synthetic copy of the pre-split wide projection. It must remain private
  // after the Basic reader switches to the dedicated safe collection.
  ownedPaths.add(`beta_public_catalog/establishments/items/${publicId}`);
  for (const id of [premiumId, expiredPremiumId, inactivePremiumId,
    unpublishedPremiumId, downgradeId, inactiveTransitionId,
    exactBoundaryId, malformedPremiumId]) {
    ownedPaths.add(`establishments/${id}`);
    ownedPaths.add(`beta_public_catalog/establishments_basic/items/${id}`);
    ownedPaths.add(`beta_public_catalog/establishments_premium/items/${id}`);
  }
  ownedPaths.add(`events/${publicEventId}`);
  ownedPaths.add(`beta_public_catalog/events/items/${publicEventId}`);
  for (const fixture of additionalPublicFixtures) {
    ownedPaths.add(`${fixture.collectionId}/${fixture.id}`);
    ownedPaths.add(`beta_public_catalog/${fixture.collectionId}/items/${fixture.id}`);
  }
  ownedPaths.add(`job_private/${jobId}`);
  ownedPaths.add(`jobs/${jobId}`);
  ownedPaths.add(`beta_public_catalog/jobs/items/${jobId}`);
  for (const pathName of ['home_pages/published', 'home_pages/draft']) {
    const snapshot = await adminDb.doc(pathName).get();
    preservedDocuments.set(pathName, snapshot.exists ? snapshot.data() : null);
    ownedPaths.add(pathName);
  }
  for (const pathName of [
    ...[1, 2, 3, 4].map(index => `contact_messages/${contactId}-${index}`),
    contactQuotaPath,
    otherQuotaPath,
    concurrentQuotaPath,
    `business_proposals/${proposalId}`,
    `reviews/${reviewId}`,
  ]) ownedPaths.add(pathName);

  await adminDb.runTransaction(async transaction => {
    transaction.set(canonical('establishments', publicId), {
      name: 'Comércio público sintético', published: true, active: true,
      privateOwnerEmail: 'must-not-be-projected@example.invalid',
    });
    transaction.set(projection('establishments', publicId), {
      visibility: 'public', sourceId: publicId, schemaVersion: 1,
      updatedAt: new Date(),
      publicData: { name: 'Comércio público sintético', category: 'Serviços' },
    });
    transaction.set(adminDb.doc(
      `beta_public_catalog/establishments/items/${publicId}`), {
      visibility: 'public', sourceId: publicId, schemaVersion: 1,
      updatedAt: new Date(),
      publicData: {
        name: 'Legacy sintético', galleryUrls: ['private legacy field'],
        mapsUrl: 'https://example.invalid/legacy',
      },
    });
  });
  const premiumUntil = new Date(Date.now() + 30 * 60_000);
  const expiredAt = new Date('2000-01-01T00:00:00.000Z');
  async function seedEstablishment(id, {
    tier = 'premium', expiry = premiumUntil, active = true, published = true,
    premiumProjectionData = {
      galleryUrls: ['https://example.invalid/premium.jpg'],
    },
  } = {}) {
    const basicData = {
      name: 'Comércio Premium sintético', address: 'Rua sintética, 1',
      phone: '(21) 2222-0000', category: 'Comércio', subcategory: 'Mercado',
    };
    await adminDb.doc(`establishments/${id}`).set({
      ...basicData,
      description: 'Detalhes comerciais canônicos sintéticos',
      galleryUrls: ['https://example.invalid/canonical-premium.jpg'],
      listingTier: tier, premiumUntil: expiry, active, published,
    });
    await adminDb.doc(`beta_public_catalog/establishments_basic/items/${id}`).set({
      visibility: 'public', sourceId: id, schemaVersion: 1,
      updatedAt: new Date(), publicData: basicData,
    });
    await adminDb.doc(`beta_public_catalog/establishments_premium/items/${id}`).set({
      visibility: 'public', sourceId: id, schemaVersion: 1,
      updatedAt: new Date(), listingTier: 'premium', premiumUntil: expiry,
      publicData: premiumProjectionData,
    });
  }
  await seedEstablishment(premiumId);
  await seedEstablishment(expiredPremiumId, { expiry: expiredAt });
  await seedEstablishment(inactivePremiumId, { active: false });
  await seedEstablishment(unpublishedPremiumId, { published: false });
  await seedEstablishment(downgradeId);
  await seedEstablishment(inactiveTransitionId);
  await seedEstablishment(malformedPremiumId, {
    tier: 'basic', expiry: null,
    premiumProjectionData: { name: 'Comércio Premium sintético', privateOwnerEmail: 'leak' },
  });
  await adminDb.runTransaction(async transaction => {
    transaction.set(canonical('events', publicEventId), {
      title: 'Evento sintético', published: true, active: true,
    });
    transaction.set(projection('events', publicEventId), {
      visibility: 'public', sourceId: publicEventId, schemaVersion: 1,
      updatedAt: new Date(),
      publicData: { title: 'Evento sintético', category: 'Cultura' },
    });
  });
  await adminDb.runTransaction(async transaction => {
    for (const fixture of additionalPublicFixtures) {
      transaction.set(canonical(fixture.collectionId, fixture.id), {
        ...fixture.publicData, published: true, active: true,
      });
      transaction.set(projection(fixture.collectionId, fixture.id), {
        visibility: 'public', sourceId: fixture.id, schemaVersion: 1,
        updatedAt: new Date(), publicData: fixture.publicData,
      });
    }
  });
  const deferredJobData = {
    title: 'Vaga sintética', company: 'Empresa sintética', type: 'job',
  };
  await adminDb.doc(`jobs/${jobId}`).set({
    ...deferredJobData, published: true, active: true,
  });
  await adminDb.doc(`beta_public_catalog/jobs/items/${jobId}`).set({
    visibility: 'public', sourceId: jobId, schemaVersion: 1,
    updatedAt: new Date(), publicData: deferredJobData,
  });
  await adminDb.doc(`job_private/${jobId}`).set({
    companyEmail: 'synthetic@example.invalid', contact: 'sintético',
  });
  await adminDb.doc('home_pages/published').set({
    published: true, active: true, heroTitle: 'Home sintética',
    banners: [{ id: `banner-${suffix}`, title: 'Banner sintético' }],
    highlights: [{ id: publicId, title: 'Destaque sintético' }],
  });
  await adminDb.doc('home_pages/draft').set({
    published: false, active: false, heroTitle: 'Rascunho Home',
  });
  await adminDb.runTransaction(async transaction => {
    transaction.set(canonical('establishments', draftId), {
      name: 'Rascunho', published: false, active: true,
    });
    transaction.delete(projection('establishments', draftId));
  });
  await adminDb.runTransaction(async transaction => {
    transaction.set(canonical('establishments', deletedId), {
      name: 'Tombstone', published: false, active: false,
      deleted: true, deletedAt: new Date(),
    });
    transaction.delete(projection('establishments', deletedId));
  });

  const visible = await getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${publicId}`));
  assert.equal(visible.data().publicData.name, 'Comércio público sintético');
  assert.equal('privateOwnerEmail' in visible.data().publicData, false);
  pass('visitor reads only the allowlisted public projection');
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments/items/${publicId}`)),
  'visitor cannot read the legacy wide establishment projection');
  pass('legacy wide projection is not exposed after the Basic/Premium split');
  const basicBusiness = await getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments_basic/items/${premiumId}`));
  assert.deepEqual(basicBusiness.data().publicData, {
    name: 'Comércio Premium sintético', address: 'Rua sintética, 1',
    phone: '(21) 2222-0000', category: 'Comércio', subcategory: 'Mercado',
  });
  pass('visitor reads the Basic projection without Premium fields');
  await denied(setDoc(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${premiumId}`), {
      visibility: 'public', sourceId: premiumId, schemaVersion: 1,
      updatedAt: serverTimestamp(),
      publicData: { name: 'Tentativa comum de alteração' },
    }, { merge: true }),
  'ordinary user cannot alter a Basic projection');
  const premiumBusiness = await getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments_premium/items/${premiumId}`));
  assert.equal(premiumBusiness.data().publicData.galleryUrls[0],
    'https://example.invalid/premium.jpg');
  pass('visitor reads a valid Premium projection for an active published establishment');
  await denied(getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments_premium/items/${expiredPremiumId}`)),
  'Premium projection is denied after expiry');
  await denied(getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments_premium/items/${inactivePremiumId}`)),
  'Premium projection is denied for an inactive establishment');
  await denied(getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments_premium/items/${unpublishedPremiumId}`)),
  'Premium projection is denied for an unpublished establishment');
  await denied(getDocsFromServer(query(
    collection(guestDb, 'beta_public_catalog/establishments_premium/items'),
    where('visibility', '==', 'public'), limit(40),
  )), 'Premium query fails closed when stale or expired records are present');
  await Promise.all([inactivePremiumId, unpublishedPremiumId].map(id =>
    adminDb.doc(`beta_public_catalog/establishments_basic/items/${id}`).delete()));
  await denied(getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments_premium/items/${malformedPremiumId}`)),
  'malformed Premium projection fails closed');
  await denied(setDoc(doc(visitor.db,
    `beta_public_catalog/establishments_premium/items/forged-${suffix}`), {
      visibility: 'public', sourceId: `forged-${suffix}`, schemaVersion: 1,
      updatedAt: serverTimestamp(), listingTier: 'premium', premiumUntil,
      publicData: { name: 'Projeção forjada' },
    }), 'ordinary user cannot create a Premium projection');
  await denied(setDoc(doc(visitor.db,
    `beta_public_catalog/establishments_premium/items/${premiumId}`), {
      visibility: 'public', sourceId: premiumId, schemaVersion: 1,
      updatedAt: serverTimestamp(), listingTier: 'premium', premiumUntil,
      publicData: { name: 'Tentativa de alteração' },
    }, { merge: true }), 'ordinary user cannot alter an existing Premium projection');
  await denied(runTransaction(admin.db, async transaction => {
    const basicData = {
      name: 'Válido no instante da gravação', address: 'Rua sintética, 1',
      phone: '(21) 2222-0000', category: 'Comércio',
    };
    transaction.set(doc(admin.db, `establishments/${exactBoundaryId}`), {
      ...basicData, published: true, active: true, listingTier: 'premium',
      premiumUntil: serverTimestamp(),
    });
    transaction.set(doc(admin.db,
      `beta_public_catalog/establishments_basic/items/${exactBoundaryId}`), {
        visibility: 'public', sourceId: exactBoundaryId, schemaVersion: 1,
        updatedAt: serverTimestamp(), publicData: basicData,
      });
    transaction.set(doc(admin.db,
      `beta_public_catalog/establishments_premium/items/${exactBoundaryId}`), {
        visibility: 'public', sourceId: exactBoundaryId, schemaVersion: 1,
        updatedAt: serverTimestamp(), listingTier: 'premium',
        premiumUntil: serverTimestamp(),
        publicData: { galleryUrls: [] },
      });
  }), 'Premium expiry equal to request.time is denied at the exact boundary');
  const downgradeCanonicalRef = doc(admin.db, `establishments/${downgradeId}`);
  const downgradeBasicRef = doc(admin.db,
    `beta_public_catalog/establishments_basic/items/${downgradeId}`);
  const downgradePremiumRef = doc(admin.db,
    `beta_public_catalog/establishments_premium/items/${downgradeId}`);
  await runTransaction(admin.db, async transaction => {
    const source = await transaction.get(downgradeCanonicalRef);
    const basic = await transaction.get(downgradeBasicRef);
    const premium = await transaction.get(downgradePremiumRef);
    assert.equal(source.exists(), true);
    assert.equal(basic.exists(), true);
    assert.equal(premium.exists(), true);
    transaction.update(downgradeCanonicalRef, {
      listingTier: 'basic', premiumUntil: null, updatedAt: serverTimestamp(),
    });
    transaction.update(downgradeBasicRef, {
      updatedAt: serverTimestamp(),
    });
    transaction.delete(downgradePremiumRef);
  });
  assert.equal((await getDocFromServer(downgradeBasicRef)).exists(), true);
  assert.equal((await getDocFromServer(downgradePremiumRef)).exists(), false);
  const downgradedCanonical = (await getDocFromServer(
    doc(admin.db, `establishments/${downgradeId}`))).data();
  assert.equal(downgradedCanonical.description,
    'Detalhes comerciais canônicos sintéticos');
  assert.deepEqual(downgradedCanonical.galleryUrls,
    ['https://example.invalid/canonical-premium.jpg']);
  pass('Admin downgrade atomically removes Premium and retains Basic');
  const transitionCanonicalRef = doc(admin.db, `establishments/${premiumId}`);
  const transitionBasicRef = doc(admin.db,
    `beta_public_catalog/establishments_basic/items/${premiumId}`);
  const transitionPremiumRef = doc(admin.db,
    `beta_public_catalog/establishments_premium/items/${premiumId}`);
  await denied(runTransaction(admin.db, async transaction => {
    transaction.update(transitionCanonicalRef, {
      description: 'Detalhe alterado sem atualizar projeção',
      updatedAt: serverTimestamp(),
    });
    transaction.update(transitionBasicRef, {
      updatedAt: serverTimestamp(),
    });
  }), 'canonical Premium changes are denied without a synchronized projection');
  await runTransaction(admin.db, async transaction => {
    const source = await transaction.get(transitionCanonicalRef);
    const basic = await transaction.get(transitionBasicRef);
    const premium = await transaction.get(transitionPremiumRef);
    assert.equal(source.exists(), true);
    assert.equal(basic.exists(), true);
    assert.equal(premium.exists(), true);
    transaction.update(transitionCanonicalRef, {
      description: 'Detalhe atualizado em conjunto', updatedAt: serverTimestamp(),
    });
    transaction.update(transitionBasicRef, { updatedAt: serverTimestamp() });
    transaction.update(transitionPremiumRef, {
      'publicData.description': 'Detalhe atualizado em conjunto',
      updatedAt: serverTimestamp(),
    });
  });
  assert.equal((await getDocFromServer(transitionPremiumRef))
    .data().publicData.description, 'Detalhe atualizado em conjunto');
  pass('Admin updates canonical and Premium projections atomically');
  await denied(runTransaction(admin.db, async transaction => {
    transaction.update(transitionCanonicalRef, {
      published: false, updatedAt: serverTimestamp(),
    });
    transaction.delete(transitionBasicRef);
    // Deliberately leave Premium behind to prove Rules require atomic cleanup.
  }), 'unpublish is denied when the Premium projection remains');
  await runTransaction(admin.db, async transaction => {
    const source = await transaction.get(transitionCanonicalRef);
    const basic = await transaction.get(transitionBasicRef);
    const premium = await transaction.get(transitionPremiumRef);
    assert.equal(source.exists(), true);
    assert.equal(basic.exists(), true);
    assert.equal(premium.exists(), true);
    transaction.update(transitionCanonicalRef, {
      published: false, updatedAt: serverTimestamp(),
    });
    transaction.delete(transitionBasicRef);
    transaction.delete(transitionPremiumRef);
  });
  assert.equal((await getDocFromServer(transitionPremiumRef)).exists(), false);
  pass('Admin unpublishes only when both public projections are removed atomically');
  const inactiveCanonicalRef = doc(admin.db, `establishments/${downgradeId}`);
  const inactiveBasicRef = doc(admin.db,
    `beta_public_catalog/establishments_basic/items/${downgradeId}`);
  await runTransaction(admin.db, async transaction => {
    const source = await transaction.get(inactiveCanonicalRef);
    const basic = await transaction.get(inactiveBasicRef);
    assert.equal(source.exists(), true);
    assert.equal(basic.exists(), true);
    transaction.update(inactiveCanonicalRef, {
      active: false, published: false, updatedAt: serverTimestamp(),
    });
    transaction.delete(inactiveBasicRef);
  });
  assert.equal((await getDocFromServer(inactiveBasicRef)).exists(), false);
  pass('Admin inactivation atomically removes the Basic projection');
  const inactivatedCanonicalRef = doc(admin.db,
    `establishments/${inactiveTransitionId}`);
  const inactivatedBasicRef = doc(admin.db,
    `beta_public_catalog/establishments_basic/items/${inactiveTransitionId}`);
  const inactivatedPremiumRef = doc(admin.db,
    `beta_public_catalog/establishments_premium/items/${inactiveTransitionId}`);
  await runTransaction(admin.db, async transaction => {
    assert.equal((await transaction.get(inactivatedBasicRef)).exists(), true);
    assert.equal((await transaction.get(inactivatedPremiumRef)).exists(), true);
    transaction.update(inactivatedCanonicalRef, {
      active: false, published: false, updatedAt: serverTimestamp(),
    });
    transaction.delete(inactivatedBasicRef);
    transaction.delete(inactivatedPremiumRef);
  });
  assert.equal((await getDocFromServer(inactivatedPremiumRef)).exists(), false);
  pass('Admin inactivation atomically removes an active Premium projection');
  const guestVisible = await getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments_basic/items/${publicId}`));
  assert.equal(guestVisible.data().publicData.name, 'Comércio público sintético');
  pass('unauthenticated visitor can read published public content');
  await denied(getDocFromServer(doc(guestDb, `establishments/${publicId}`)),
    'unauthenticated visitor cannot read canonical private content');
  await denied(getDocFromServer(doc(visitor.db, `establishments/${publicId}`)),
    'visitor cannot read canonical private content');
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${draftId}`)),
  'visitor cannot read a draft projection');
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${deletedId}`)),
  'visitor cannot read a tombstone projection');
  await denied(setDoc(doc(visitor.db, `establishments/forged-${suffix}`), { name: 'forged' }),
    'visitor cannot write canonical content');
  await denied(setDoc(doc(guestDb,
    `users/unauthenticated/favorites/forged`), { id: 'forged' }),
  'unauthenticated visitor cannot create account data');
  await denied(getDocFromServer(doc(other.db, contactQuotaPath)),
    'contact-message quota is private to its account');
  await denied(setDoc(doc(guestDb, `contact_messages/${contactId}-guest`), {
    uid: visitor.uid, email: visitor.auth.currentUser.email,
    contact: '21912345678', message: 'Sem login', status: 'pending',
    createdAt: serverTimestamp(), quotaPeriodStartedAt: serverTimestamp(),
  }), 'visitor cannot submit a contact message');
  await denied(setDoc(doc(visitor.db, `contact_messages/${contactId}-forged`), {
    uid: visitor.uid, email: 'outra-conta@example.invalid',
    contact: '21912345678', message: 'E-mail falsificado', status: 'pending',
    createdAt: serverTimestamp(), quotaPeriodStartedAt: serverTimestamp(),
  }), 'contact message cannot spoof account email or bypass quota');
  const quotaRef = doc(visitor.db, contactQuotaPath);
  for (let index = 1; index <= 3; index++) {
    const messageRef = doc(visitor.db, `contact_messages/${contactId}-${index}`);
    await runTransaction(visitor.db, async transaction => {
      const quotaSnapshot = await transaction.get(quotaRef);
      const priorQuota = quotaSnapshot.data();
      const periodStartedAt = priorQuota?.periodStartedAt ?? serverTimestamp();
      transaction.set(quotaRef, {
        uid: visitor.uid,
        count: index,
        periodStartedAt,
        lastMessageId: messageRef.id,
        updatedAt: serverTimestamp(),
      });
      transaction.set(messageRef, {
        uid: visitor.uid,
        email: visitor.auth.currentUser.email,
        contact: '21912345678',
        message: `Mensagem sintética ${index}`,
        status: 'pending',
        createdAt: serverTimestamp(),
        quotaPeriodStartedAt: periodStartedAt,
      });
    });
  }
  pass('registered user can send three atomic contact messages per rolling 24-hour period');
  await denied(deleteDoc(quotaRef),
    'account cannot delete its active quota before the 24-hour window expires');
  assert.equal((await getDocFromServer(quotaRef)).exists(), true);
  assert.equal((await getDocFromServer(doc(visitor.db,
    `users/${visitor.uid}`))).exists(), true);
  const messagesBeforeDeletion = await getDocsFromServer(query(
    collection(visitor.db, 'contact_messages'),
    where('uid', '==', visitor.uid), limit(100)));
  assert.equal(messagesBeforeDeletion.docs.some(message =>
    message.id === `${contactId}-1`), true);
  pass('active-quota denial leaves account profile and messages untouched');
  await denied(setDoc(quotaRef, {
    uid: visitor.uid, count: 1, periodStartedAt: serverTimestamp(),
    lastMessageId: `${contactId}-4`, updatedAt: serverTimestamp(),
  }), 'resetting an active quota after its delete was denied is blocked');
  assert.equal((await getDocFromServer(quotaRef)).data().count, 3);
  pass('blocked quota deletion preserves the existing count and period');
  const pendingQuotaRef = doc(pendingDeletion.db, pendingQuotaPath);
  const pendingMessageRef = doc(
    pendingDeletion.db, `contact_messages/${pendingMessageId}`);
  await runTransaction(pendingDeletion.db, async transaction => {
    const periodStartedAt = serverTimestamp();
    transaction.set(pendingQuotaRef, {
      uid: pendingDeletion.uid, count: 1, periodStartedAt,
      lastMessageId: pendingMessageRef.id, updatedAt: serverTimestamp(),
    });
    transaction.set(pendingMessageRef, {
      uid: pendingDeletion.uid,
      email: pendingDeletion.auth.currentUser.email,
      contact: '21912345678', message: 'Mensagem inicial sintética',
      status: 'pending', createdAt: serverTimestamp(),
      quotaPeriodStartedAt: periodStartedAt,
    });
  });
  const deletionRequestRef = doc(
    pendingDeletion.db, pendingDeletionRequestPath);
  const activeQuotaData = (await getDocFromServer(pendingQuotaRef)).data();
  const retryAfter = new Timestamp(
    activeQuotaData.periodStartedAt.seconds + 24 * 60 * 60,
    activeQuotaData.periodStartedAt.nanoseconds);
  await setDoc(deletionRequestRef, {
    uid: pendingDeletion.uid,
    requestedAt: serverTimestamp(),
    retryAfter,
    status: 'pending',
  });
  assert.equal((await getDocFromServer(deletionRequestRef)).data().status, 'pending');
  assert.equal((await getDocFromServer(pendingQuotaRef)).data().count, 1);
  assert.equal((await getDocFromServer(doc(pendingDeletion.db,
    `users/${pendingDeletion.uid}`))).exists(), true);
  pass('owner can register an immediate pending deletion request without deleting account data');
  assert.equal((await getDocFromServer(doc(admin.db,
    pendingDeletionRequestPath))).data().uid, pendingDeletion.uid);
  const adminRequests = await getDocsFromServer(query(
    collection(admin.db, 'account_deletion_requests'), limit(100)));
  assert.equal(adminRequests.docs.some(
    request => request.id === pendingDeletion.uid), true);
  pass('authorized Admin can inspect a bounded pending-deletion queue');
  await denied(getDocFromServer(doc(other.db,
    pendingDeletionRequestPath)),
  'another account cannot read the deletion request');
  await denied(deleteDoc(deletionRequestRef),
    'owner cannot discard a pending deletion request before completion');
  await denied(setDoc(deletionRequestRef, {
    uid: pendingDeletion.uid, requestedAt: serverTimestamp(), retryAfter,
    status: 'pending',
  }), 'duplicate request cannot overwrite the original request');
  await denied(setDoc(doc(other.db, pendingDeletionRequestPath), {
    uid: pendingDeletion.uid, requestedAt: serverTimestamp(), retryAfter,
    status: 'pending',
  }), 'another account cannot create a deletion request for this user');
  await denied(setDoc(doc(admin.db,
    `account_deletion_requests/${admin.uid}`), {
    uid: admin.uid, requestedAt: serverTimestamp(), retryAfter,
    status: 'pending',
  }), 'Admin cannot use the user deletion request flow');
  const newPendingMessage = doc(pendingDeletion.db,
    `contact_messages/${contactId}-after-deletion-request`);
  ownedPaths.add(`contact_messages/${contactId}-after-deletion-request`);
  await denied(runTransaction(pendingDeletion.db, async transaction => {
    const freshQuota = await transaction.get(pendingQuotaRef);
    const data = freshQuota.data();
    transaction.set(pendingQuotaRef, {
      ...data, count: 2, lastMessageId: newPendingMessage.id,
      updatedAt: serverTimestamp(),
    });
    transaction.set(newPendingMessage, {
      uid: pendingDeletion.uid,
      email: pendingDeletion.auth.currentUser.email,
      contact: '21912345678', message: 'Mensagem após pedido de exclusão',
      status: 'pending', createdAt: serverTimestamp(),
      quotaPeriodStartedAt: data.periodStartedAt,
    });
  }), 'pending deletion request freezes further contact messages');
  assert.equal((await getDocFromServer(pendingQuotaRef)).data().count, 1);
  pass('pending deletion does not allow extending the contact quota window');
  await adminDb.doc(pendingQuotaPath).update({
    periodStartedAt: new Date(Date.now() - 25 * 60 * 60 * 1000),
  });
  // Advance only the synthetic fixture's deadline to model the passage of 24h.
  await adminDb.doc(pendingDeletionRequestPath).update({
    retryAfter: new Date(Date.now() - 60 * 60 * 1000),
  });
  await deleteDoc(pendingQuotaRef);
  await deleteDoc(pendingMessageRef);
  const pendingCompletion = writeBatch(pendingDeletion.db);
  pendingCompletion.delete(doc(pendingDeletion.db, `users/${pendingDeletion.uid}`));
  pendingCompletion.delete(deletionRequestRef);
  await pendingCompletion.commit();
  assert.equal((await adminDb.doc(pendingDeletionRequestPath).get()).exists, false);
  assert.equal((await adminDb.doc(`users/${pendingDeletion.uid}`).get()).exists, false);
  pass('pending deletion can be completed after quota expiry without retaining the request');
  const fourthMessage = doc(visitor.db, `contact_messages/${contactId}-4`);
  await denied(runTransaction(visitor.db, async transaction => {
    const quotaSnapshot = await transaction.get(quotaRef);
    const priorQuota = quotaSnapshot.data();
    const periodStartedAt = priorQuota.periodStartedAt;
    transaction.set(quotaRef, {
      ...priorQuota, count: 4, lastMessageId: fourthMessage.id,
      updatedAt: serverTimestamp(),
    });
    transaction.set(fourthMessage, {
      uid: visitor.uid, email: visitor.auth.currentUser.email,
      contact: '21912345678', message: 'Quarta mensagem bloqueada',
      status: 'pending', createdAt: serverTimestamp(), quotaPeriodStartedAt: periodStartedAt,
    });
  }), 'fourth contact message is denied inside the same rolling 24-hour period');
  await denied(runTransaction(visitor.db, async transaction => {
    const quotaSnapshot = await transaction.get(quotaRef);
    const resetMessage = doc(visitor.db, `contact_messages/${contactId}-4`);
    transaction.set(quotaRef, {
      uid: visitor.uid, count: 1, periodStartedAt: serverTimestamp(),
      lastMessageId: resetMessage.id, updatedAt: serverTimestamp(),
    });
    transaction.set(resetMessage, {
      uid: visitor.uid, email: visitor.auth.currentUser.email,
      contact: '21912345678', message: 'Tentativa de reset antecipado',
      status: 'pending', createdAt: serverTimestamp(),
      quotaPeriodStartedAt: serverTimestamp(),
    });
  }), 'account cannot reset its contact quota before the 24-hour window expires');
  await adminDb.doc(otherQuotaPath).set({
    uid: other.uid, count: 3,
    periodStartedAt: new Date(Date.now() - 23 * 60 * 60 * 1000),
    lastMessageId: 'synthetic-other-message', updatedAt: new Date(),
  });
  await denied(deleteDoc(doc(visitor.db, otherQuotaPath)),
    'account cannot delete another user quota');
  await adminDb.doc(otherQuotaPath).update({
    periodStartedAt: new Date(Date.now() - (24 * 60 * 60 * 1000 - 60 * 1000)),
  });
  await denied(deleteDoc(doc(other.db, otherQuotaPath)),
    'quota deletion is denied just before the 24-hour boundary');
  await adminDb.doc(otherQuotaPath).update({
    periodStartedAt: new Date(Date.now() - (24 * 60 * 60 * 1000 + 60 * 1000)),
  });
  await deleteDoc(doc(other.db, otherQuotaPath));
  assert.equal((await getDocFromServer(doc(other.db, otherQuotaPath))).exists(), false);
  const afterExpiryMessageId = `${contactId}-after-expiry`;
  ownedPaths.add(`contact_messages/${afterExpiryMessageId}`);
  await runTransaction(other.db, async transaction => {
    const quotaRef = doc(other.db, otherQuotaPath);
    const messageRef = doc(other.db, `contact_messages/${afterExpiryMessageId}`);
    const periodStartedAt = serverTimestamp();
    transaction.set(quotaRef, {
      uid: other.uid, count: 1, periodStartedAt,
      lastMessageId: messageRef.id, updatedAt: serverTimestamp(),
    });
    transaction.set(messageRef, {
      uid: other.uid, email: other.auth.currentUser.email,
      contact: '21912345678', message: 'Primeira mensagem da nova janela',
      status: 'pending', createdAt: serverTimestamp(),
      quotaPeriodStartedAt: periodStartedAt,
    });
  });
  assert.equal((await getDocFromServer(doc(other.db, otherQuotaPath))).data().count, 1);
  pass('after expiry, owner may remove the old quota and start the next window');

  await syncProfileTransaction(concurrent);
  const concurrentMessageIds = Array.from({ length: 4 }, (_, index) =>
    `${contactId}-parallel-${index + 1}`);
  for (const id of concurrentMessageIds) ownedPaths.add(`contact_messages/${id}`);
  const concurrentResults = await Promise.allSettled(concurrentMessageIds.map(messageId =>
    runTransaction(concurrent.db, async transaction => {
      const quotaRef = doc(concurrent.db, concurrentQuotaPath);
      const quotaSnapshot = await transaction.get(quotaRef);
      const previous = quotaSnapshot.data();
      const periodStartedAt = previous?.periodStartedAt ?? serverTimestamp();
      const count = (previous?.count ?? 0) + 1;
      const messageRef = doc(concurrent.db, `contact_messages/${messageId}`);
      transaction.set(quotaRef, {
        uid: concurrent.uid, count, periodStartedAt,
        lastMessageId: messageRef.id, updatedAt: serverTimestamp(),
      });
      transaction.set(messageRef, {
        uid: concurrent.uid, email: concurrent.auth.currentUser.email,
        contact: '21912345678', message: `Mensagem paralela ${count}`,
        status: 'pending', createdAt: serverTimestamp(), quotaPeriodStartedAt: periodStartedAt,
      });
    })));
  assert.equal(concurrentResults.filter(result => result.status === 'fulfilled').length, 3);
  assert.equal(concurrentResults.filter(result => result.status === 'rejected').length, 1);
  assert.equal(concurrentResults.find(result => result.status === 'rejected').reason.code,
    'permission-denied');
  const concurrentQuota = (await getDocFromServer(
    doc(concurrent.db, concurrentQuotaPath))).data();
  assert.equal(concurrentQuota.count, 3);
  const concurrentMessages = await getDocsFromServer(query(
    collection(concurrent.db, 'contact_messages'),
    where('uid', '==', concurrent.uid), limit(10)));
  assert.equal(concurrentMessages.size, 3);
  pass('four concurrent sends commit exactly three atomic messages and one quota rejection');
  await adminDb.doc(contactQuotaPath).set({
    uid: visitor.uid,
    count: 3,
    periodStartedAt: new Date(Date.now() - 25 * 60 * 60 * 1000),
    lastMessageId: `${contactId}-3`,
    updatedAt: new Date(),
  });
  await runTransaction(visitor.db, async transaction => {
    const quotaSnapshot = await transaction.get(quotaRef);
    const messageRef = fourthMessage;
    assert.equal(quotaSnapshot.data().count, 3);
    const periodStartedAt = serverTimestamp();
    transaction.set(quotaRef, {
      uid: visitor.uid, count: 1, periodStartedAt,
      lastMessageId: messageRef.id, updatedAt: serverTimestamp(),
    });
    transaction.set(messageRef, {
      uid: visitor.uid, email: visitor.auth.currentUser.email,
      contact: '21912345678', message: 'Mensagem após janela diária',
      status: 'pending', createdAt: serverTimestamp(),
      quotaPeriodStartedAt: periodStartedAt,
    });
  });
  pass('quota resets after its 24-hour period has elapsed');
  await denied(setDoc(doc(visitor.db, `business_proposals/${proposalId}`), {
    uid: visitor.uid, name: 'Morador sintético', contact: '',
    details: 'Proposta de teste',
    status: 'pending', createdAt: serverTimestamp(),
  }), 'deferred proposal rejects a direct write by the signed-in owner');
  await denied(setDoc(doc(visitor.db, `reviews/${reviewId}`), {
    uid: visitor.uid, businessId: publicId,
    business: 'Comércio público sintético', message: 'Avaliação de teste',
    stars: 5, status: 'pending', published: false,
    createdAt: serverTimestamp(),
  }), 'deferred review rejects a direct write by the signed-in owner');
  assert.equal((await adminDb.doc(`business_proposals/${proposalId}`).get()).exists, false);
  assert.equal((await adminDb.doc(`reviews/${reviewId}`).get()).exists, false);
  pass('deferred proposal and review writes remain blocked under current Rules');
  await denied(setDoc(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/forged-${suffix}`), {
      visibility: 'public', sourceId: `forged-${suffix}`, schemaVersion: 1,
      updatedAt: new Date(), publicData: { name: 'forged' },
    }), 'ordinary user cannot publish a projection');

  const listed = await getDocsFromServer(query(
    collection(visitor.db, 'beta_public_catalog/establishments_basic/items'),
    where('visibility', '==', 'public'),
    limit(40),
  ));
  assert.equal(listed.docs.some(item => item.id === publicId), true);
  assert.equal(listed.docs.some(item => item.id === draftId || item.id === deletedId), false);
  pass('public list returns only projected public items');
  const routeFixture = additionalPublicFixtures.find(item =>
    item.collectionId === 'routes');
  const routeList = await getDocsFromServer(query(
    collection(visitor.db, 'beta_public_catalog/routes/items'),
    where('visibility', '==', 'public'), limit(40),
  ));
  assert.equal(routeList.docs.some(item => item.id === routeFixture.id), true);
  pass('existing non-establishment catalog list remains compatible');
  const publicEvent = await getDocFromServer(doc(visitor.db,
    `beta_public_catalog/events/items/${publicEventId}`));
  assert.equal(publicEvent.data().publicData.title, 'Evento sintético');
  pass('published Events use the same public projection contract');
  for (const fixture of additionalPublicFixtures) {
    const publicItem = await getDocFromServer(doc(visitor.db,
      `beta_public_catalog/${fixture.collectionId}/items/${fixture.id}`));
    assert.deepEqual(publicItem.data().publicData, fixture.publicData);
    pass(`visitor reads published ${fixture.collectionId} projection through client SDK`);
  }
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/jobs/items/${jobId}`)),
  'public client cannot read deferred job projections');
  pass('deferred job projections are not exposed to the public client');
  await denied(getDocFromServer(doc(visitor.db, `job_private/${jobId}`)),
    'ordinary user cannot read private job contact data');
  assert.equal((await getDocFromServer(doc(admin.db,
    `job_private/${jobId}`))).data().companyEmail, 'synthetic@example.invalid');
  await denied(setDoc(doc(admin.db, `jobs/${jobId}`), {
    title: 'Vaga nova', published: false, active: true,
  }), 'authorized Admin cannot create a deferred public job through Firestore');
  await denied(setDoc(doc(admin.db, `job_private/${jobId}`), {
    contact: 'contato atualizado sintético',
  }, { merge: true }), 'authorized Admin cannot update deferred private job data');
  assert.equal((await getDocFromServer(doc(admin.db,
    `job_private/${jobId}`))).data().contact, 'sintético');
  pass('deferred job records are readable by Admin but immutable to clients');
  const publicHome = (await getDocFromServer(doc(guestDb,
    'home_pages/published'))).data();
  assert.equal(publicHome.heroTitle, 'Home sintética');
  assert.equal(publicHome.banners[0].title, 'Banner sintético');
  assert.equal(publicHome.highlights[0].title, 'Destaque sintético');
  pass('unauthenticated visitor can read published Home, banners and highlights');
  await adminDb.doc('home_pages/published').update({ active: false });
  await denied(getDocFromServer(doc(guestDb, 'home_pages/published')),
    'unauthenticated visitor cannot read an inactive published Home');
  await adminDb.doc('home_pages/published').update({ active: true });
  await denied(getDocFromServer(doc(guestDb, 'home_pages/draft')),
    'unauthenticated visitor cannot read the Home draft');

  const adminCreatedId = `spark-admin-created-${suffix}`;
  ownedPaths.add(`establishments/${adminCreatedId}`);
  ownedPaths.add(`beta_public_catalog/establishments_basic/items/${adminCreatedId}`);
  await runTransaction(admin.db, async transaction => {
    transaction.set(doc(admin.db, `establishments/${adminCreatedId}`), {
      name: 'Criado pelo Admin', published: true, active: true,
    });
    transaction.set(doc(admin.db,
      `beta_public_catalog/establishments_basic/items/${adminCreatedId}`), {
      visibility: 'public', sourceId: adminCreatedId, schemaVersion: 1,
      updatedAt: serverTimestamp(),
      publicData: { name: 'Criado pelo Admin' },
    });
  });
  assert.equal((await getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${adminCreatedId}`)))
    .data().publicData.name, 'Criado pelo Admin');
  pass('authorized Admin can publish through the authenticated client SDK');

  const adBusinessId = `spark-ad-business-${suffix}`;
  const adDraftBusinessId = `spark-ad-draft-business-${suffix}`;
  const adInactiveBusinessId = `spark-ad-inactive-business-${suffix}`;
  const linkedAdId = `spark-linked-ad-${suffix}`;
  const unlinkedAdId = `spark-unlinked-ad-${suffix}`;
  const draftTargetAdId = `spark-draft-target-ad-${suffix}`;
  const inactiveTargetAdId = `spark-inactive-target-ad-${suffix}`;
  for (const [collection, id] of [
    ['establishments', adBusinessId],
    ['establishments', adDraftBusinessId],
    ['establishments', adInactiveBusinessId],
    ['ads', linkedAdId],
    ['beta_public_catalog/ads/items', linkedAdId],
    ['ads', unlinkedAdId],
    ['beta_public_catalog/ads/items', unlinkedAdId],
    ['ads', draftTargetAdId],
    ['beta_public_catalog/ads/items', draftTargetAdId],
    ['ads', inactiveTargetAdId],
    ['beta_public_catalog/ads/items', inactiveTargetAdId],
  ]) ownedPaths.add(`${collection}/${id}`);
  await adminDb.doc(`establishments/${adBusinessId}`).set({
    name: 'Comércio vinculado sintético', published: true, active: true,
  });
  await adminDb.doc(`establishments/${adDraftBusinessId}`).set({
    name: 'Comércio em rascunho sintético', published: false, active: true,
  });
  await adminDb.doc(`establishments/${adInactiveBusinessId}`).set({
    name: 'Comércio inativo sintético', published: true, active: false,
  });
  async function publishSyntheticAd(id, businessId) {
    const publicData = {
      title: 'Banner vinculado sintético',
      imageUrl: 'https://example.invalid/banner.jpg',
      businessId,
      link: '',
    };
    await runTransaction(admin.db, async transaction => {
      transaction.set(doc(admin.db, `ads/${id}`), {
        ...publicData, published: true, active: true,
      });
      transaction.set(doc(admin.db,
        `beta_public_catalog/ads/items/${id}`), {
          visibility: 'public', sourceId: id, schemaVersion: 1,
          updatedAt: serverTimestamp(), publicData,
        });
    });
  }
  await publishSyntheticAd(linkedAdId, adBusinessId);
  const linkedAd = await getDocFromServer(doc(visitor.db,
    `beta_public_catalog/ads/items/${linkedAdId}`));
  assert.equal(linkedAd.data().publicData.businessId, adBusinessId);
  assert.equal(linkedAd.data().publicData.link, '');
  pass('Admin publishes a banner with a valid establishment document ID');
  await denied(publishSyntheticAd(unlinkedAdId, ''),
    'Admin cannot publish a banner without an establishment ID');
  await denied(publishSyntheticAd(draftTargetAdId, adDraftBusinessId),
    'Admin cannot publish a banner linked to an unpublished establishment');
  await denied(publishSyntheticAd(inactiveTargetAdId, adInactiveBusinessId),
    'Admin cannot publish a banner linked to an inactive establishment');

  const broadId = `spark-full-${suffix}`;
  const broadPublicData = {
    name: 'Estabelecimento completo', title: 'Estabelecimento completo',
    category: 'Serviços', subcategory: 'Comércio', description: 'Descrição',
    shortDescription: 'Resumo', location: 'Centro', address: 'Rua de teste',
    iconKey: 'store', imageUrl: 'https://example.invalid/image.jpg',
    logoUrl: 'https://example.invalid/logo.jpg', maps: 'https://example.invalid/map',
    mapsUrl: 'https://example.invalid/map', phone: '+5521999999999',
    whatsapp: '+5521999999999', instagram: 'https://instagram.com/test',
    type: 'business', employmentType: 'CLT', company: 'Empresa sintética',
    eventDate: '2026-11-01', endDate: '2026-11-02', date: '2026-11-01',
    startsAt: '2026-11-01T12:00:00Z', startTime: '09:00', endTime: '18:00',
    organizer: 'Organizador sintético',
    registrationUrl: 'https://example.invalid/register',
    contactUrl: 'https://example.invalid/contact', link: 'https://example.invalid',
    destinationType: 'internal', destination: 'events',
    promotionTitle: 'Oferta', promotionDescription: 'Descrição da oferta',
    hours: '09:00-18:00', additionalInfo: 'Informação adicional',
    galleryUrls: ['https://example.invalid/gallery.jpg'],
    videoUrls: ['https://example.invalid/video.mp4'],
    services: ['Atendimento'], products: ['Produto'], artwork: 0, order: 1,
    featured: true, open: true, options: ['Opção A'],
  };
  const broadBasicData = {
    name: broadPublicData.name,
    title: broadPublicData.title,
    category: broadPublicData.category,
    subcategory: broadPublicData.subcategory,
    location: broadPublicData.location,
    address: broadPublicData.address,
    phone: broadPublicData.phone,
    order: broadPublicData.order,
  };
  const broadPremiumData = {
    description: broadPublicData.description,
    shortDescription: broadPublicData.shortDescription,
    iconKey: broadPublicData.iconKey,
    imageUrl: broadPublicData.imageUrl,
    logoUrl: broadPublicData.logoUrl,
    maps: broadPublicData.maps,
    mapsUrl: broadPublicData.mapsUrl,
    whatsapp: broadPublicData.whatsapp,
    instagram: broadPublicData.instagram,
    type: broadPublicData.type,
    contactUrl: broadPublicData.contactUrl,
    link: broadPublicData.link,
    hours: broadPublicData.hours,
    additionalInfo: broadPublicData.additionalInfo,
    galleryUrls: broadPublicData.galleryUrls,
    videoUrls: broadPublicData.videoUrls,
    services: broadPublicData.services,
    products: broadPublicData.products,
    artwork: broadPublicData.artwork,
    featured: broadPublicData.featured,
    open: broadPublicData.open,
    options: broadPublicData.options,
  };
  ownedPaths.add(`establishments/${broadId}`);
  ownedPaths.add(`beta_public_catalog/establishments_basic/items/${broadId}`);
  ownedPaths.add(`beta_public_catalog/establishments_premium/items/${broadId}`);
  await runTransaction(admin.db, async transaction => {
    transaction.set(doc(admin.db, `establishments/${broadId}`), {
      ...broadPublicData, published: true, active: true,
      listingTier: 'premium', premiumUntil,
    });
    transaction.set(doc(admin.db,
      `beta_public_catalog/establishments_basic/items/${broadId}`), {
      visibility: 'public', sourceId: broadId, schemaVersion: 1,
      updatedAt: serverTimestamp(), publicData: broadBasicData,
    });
    transaction.set(doc(admin.db,
      `beta_public_catalog/establishments_premium/items/${broadId}`), {
      visibility: 'public', sourceId: broadId, schemaVersion: 1,
      updatedAt: serverTimestamp(), listingTier: 'premium', premiumUntil,
        publicData: broadPremiumData,
    });
  });
  pass('Admin can publish Premium details separately from the Basic projection');
  const clientDraftId = `spark-client-draft-${suffix}`;
  ownedPaths.add(`establishments/${clientDraftId}`);
  ownedPaths.add(`beta_public_catalog/establishments_basic/items/${clientDraftId}`);
  await runTransaction(admin.db, async transaction => {
    const draftProjection = await transaction.get(doc(admin.db,
      `beta_public_catalog/establishments_basic/items/${clientDraftId}`));
    transaction.set(doc(admin.db, `establishments/${clientDraftId}`), {
      name: 'Rascunho criado pelo Admin', published: false, active: true,
    });
    if (draftProjection.exists) {
      transaction.delete(doc(admin.db,
        `beta_public_catalog/establishments_basic/items/${clientDraftId}`));
    }
  });
  pass('Admin can save a draft while atomically removing its projection');
  await denied(setDoc(doc(admin.db,
    `beta_public_catalog/establishments_basic/items/${publicId}`), {
    visibility: 'public', sourceId: publicId, schemaVersion: 1,
    updatedAt: serverTimestamp(),
    publicData: { name: 'Comércio público sintético', privateEmail: 'private@example.invalid' },
  }), 'Admin client cannot put private fields in a public projection');
  await denied(setDoc(doc(admin.db,
    `beta_public_catalog/establishments_basic/items/orphan-${suffix}`), {
    visibility: 'public', sourceId: `orphan-${suffix}`, schemaVersion: 1,
    updatedAt: serverTimestamp(), publicData: { name: 'Órfão' },
  }), 'Admin cannot publish a projection without an atomic canonical source');
  await setDoc(doc(admin.db, 'home_pages/draft'), {
    heroTitle: 'Home editada pelo Admin',
  }, { merge: true });
  assert.equal((await getDocFromServer(doc(admin.db,
    'home_pages/draft'))).data().heroTitle, 'Home editada pelo Admin');
  pass('authorized Admin can edit a private Home draft');
  await denied(setDoc(doc(visitor.db, 'home_pages/published'), {
    heroTitle: 'Tentativa comum',
  }, { merge: true }), 'ordinary user cannot modify the published Home');
  await denied(setDoc(doc(admin.db, `establishments/${publicId}`), {
    name: 'Alteração fora da projeção',
  }, { merge: true }),
  'Admin content cannot change without its projection in the same write');
  await runTransaction(admin.db, async transaction => {
    transaction.update(doc(admin.db, `establishments/${publicId}`), {
      address: 'Endereço atualizado atomicamente', updatedAt: serverTimestamp(),
    });
    transaction.update(doc(admin.db,
      `beta_public_catalog/establishments_basic/items/${publicId}`), {
      'publicData.address': 'Endereço atualizado atomicamente',
      updatedAt: serverTimestamp(),
    });
  });
  assert.equal((await getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${publicId}`)))
    .data().publicData.address, 'Endereço atualizado atomicamente');
  pass('Admin edits canonical data and the public projection atomically');
  await runTransaction(admin.db, async transaction => {
    transaction.update(doc(admin.db, `establishments/${publicId}`), {
      published: false, updatedAt: serverTimestamp(),
    });
    transaction.delete(doc(admin.db,
      `beta_public_catalog/establishments_basic/items/${publicId}`));
  });
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${publicId}`)),
  'Admin can unpublish and remove the public projection atomically');
  await denied(setDoc(doc(admin.db, `establishments/${deletedId}`), {
    deleted: false, deletedAt: null, published: true, active: true,
  }, { merge: true }), 'an Admin cannot revive a permanent tombstone');
  await denied(deleteDoc(doc(admin.db, `establishments/${publicId}`)),
    'an Admin cannot physically delete canonical content');

  const favoritePath = `users/${visitor.uid}/favorites/business::${publicId}`;
  const agendaPath = `users/${visitor.uid}/favorites/event::${publicId}`;
  ownedPaths.add(favoritePath);
  ownedPaths.add(agendaPath);
  await setDoc(doc(visitor.db, favoritePath), {
    id: `business::${publicId}`, name: 'Comércio público sintético',
    type: 'business', targetId: publicId,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  await setDoc(doc(visitor.db, agendaPath), {
    id: `event::${publicId}`, name: 'Evento sintético',
    type: 'event', targetId: publicId,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  assert.equal((await getDocFromServer(doc(visitor.db, favoritePath))).exists(), true);
  await denied(getDocFromServer(doc(other.db, favoritePath)),
    'a second account cannot read favorites or agenda of the first');
  await denied(setDoc(doc(other.db, `users/${visitor.uid}/favorites/forged`), {
    id: 'forged', name: 'forged', type: 'business', targetId: publicId,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }), 'a second account cannot write to another account');

  const adminProjection = await getDocFromServer(doc(admin.db,
    `beta_public_catalog/establishments_basic/items/${broadId}`));
  assert.equal(adminProjection.exists(), true);
  pass('authorized Admin reads the public catalog through the SDK');
  await runTransaction(admin.db, async transaction => {
    transaction.update(doc(admin.db, `establishments/${broadId}`), {
      active: false,
      published: false,
      deleted: true,
      deletedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.delete(doc(admin.db,
      `beta_public_catalog/establishments_basic/items/${broadId}`));
    transaction.delete(doc(admin.db,
      `beta_public_catalog/establishments_premium/items/${broadId}`));
  });
  assert.equal((await getDocFromServer(doc(admin.db,
    `establishments/${broadId}`))).data().deleted, true);
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments_basic/items/${broadId}`)),
  'visitor cannot read a logically deleted item after atomic Admin tombstone');
  pass('authorized Admin logically deletes published content atomically');
  await denied(setDoc(doc(revoked.db, `establishments/revoked-${suffix}`), { name: 'no' }),
    'a non-authorized Admin claim cannot write content');

  await adminDb.doc(`admin_authorizations/${admin.uid}`).update({ enabled: false });
  await adminAuth.setCustomUserClaims(admin.uid, {
    admin: true, adminVersion: version,
  });
  await admin.auth.currentUser.getIdToken(true);
  await denied(setDoc(doc(admin.db,
    `establishments/after-revocation-${suffix}`), { name: 'no' }),
    'a revoked Admin cannot create canonical content');
  await denied(getDocFromServer(doc(admin.db,
    `establishments/${publicId}`)), 'a revoked Admin cannot read canonical content');
  await denied(getDocFromServer(doc(admin.db, `job_private/${jobId}`)),
    'a revoked Admin cannot read private job contact data');
  ownedPaths.add(`establishments/after-revocation-${suffix}`);

  // Account deletion must be possible through the client SDK, but only for
  // records whose immutable owner UID is the currently authenticated user.
  const otherContact = `spark-other-contact-${suffix}`;
  const otherProposal = `spark-other-proposal-${suffix}`;
  const otherReview = `spark-other-review-${suffix}`;
  const votePath = `polls/account-deletion-${suffix}/votes/${visitor.uid}`;
  const otherVotePath = `polls/account-deletion-${suffix}/votes/${other.uid}`;
  const visitorDeletionRequestPath = `account_deletion_requests/${visitor.uid}`;
  for (const pathName of [
    `contact_messages/${otherContact}`,
    `business_proposals/${otherProposal}`,
    `reviews/${otherReview}`,
    votePath,
    otherVotePath,
    visitorDeletionRequestPath,
    `polls/account-deletion-${suffix}/votes/${visitor.uid}`,
    `polls/account-deletion-${suffix}/votes/${other.uid}`,
  ]) ownedPaths.add(pathName);
  await adminDb.doc(`contact_messages/${otherContact}`).set({
    uid: other.uid, email: other.auth.currentUser.email, contact: '2025550100',
    message: 'fixture', status: 'pending', createdAt: new Date(),
    quotaPeriodStartedAt: new Date(),
  });
  await adminDb.doc(`business_proposals/${otherProposal}`).set({
    uid: other.uid, name: 'fixture', contact: 'fixture', details: 'fixture',
    status: 'pending', createdAt: new Date(),
  });
  await adminDb.doc(`business_proposals/${proposalId}`).set({
    uid: visitor.uid, name: 'Historical synthetic', contact: 'fixture',
    details: 'Legacy record for deletion coverage', status: 'pending',
    createdAt: new Date(),
  });
  await adminDb.doc(`reviews/${otherReview}`).set({
    uid: other.uid, businessId: publicId, business: 'fixture', message: 'fixture',
    stars: 5, status: 'pending', published: false, createdAt: new Date(),
  });
  await adminDb.doc(`reviews/${reviewId}`).set({
    uid: visitor.uid, businessId: publicId, business: 'fixture',
    message: 'Legacy record for deletion coverage', stars: 5,
    status: 'pending', published: false, createdAt: new Date(),
  });
  await adminDb.doc(votePath).set({ uid: visitor.uid, option: 'fixture', createdAt: new Date() });
  await adminDb.doc(otherVotePath).set({ uid: other.uid, option: 'fixture', createdAt: new Date() });

  const ownMessages = await getDocsFromServer(query(
    collection(visitor.db, 'contact_messages'),
    where('uid', '==', visitor.uid), limit(100)));
  assert.ok(ownMessages.docs.length >= 3);
  for (const item of ownMessages.docs) await deleteDoc(item.ref);
  pass('account can enumerate and delete only its own contact messages');
  await denied(deleteDoc(doc(visitor.db, `contact_messages/${otherContact}`)),
    'account cannot delete another user contact message');

  const ownProposals = await getDocsFromServer(query(
    collection(visitor.db, 'business_proposals'),
    where('uid', '==', visitor.uid), limit(100)));
  assert.equal(ownProposals.docs.length, 1);
  await deleteDoc(ownProposals.docs[0].ref);
  pass('account can enumerate and delete its own business proposals');
  await denied(deleteDoc(doc(visitor.db, `business_proposals/${otherProposal}`)),
    'account cannot delete another user business proposal');

  const ownReviews = await getDocsFromServer(query(
    collection(visitor.db, 'reviews'), where('uid', '==', visitor.uid), limit(100)));
  assert.equal(ownReviews.docs.length, 1);
  await deleteDoc(ownReviews.docs[0].ref);
  pass('account can enumerate and delete its own reviews');
  await denied(deleteDoc(doc(visitor.db, `reviews/${otherReview}`)),
    'account cannot delete another user review');

  const ownVotes = await getDocsFromServer(query(
    collectionGroup(visitor.db, 'votes'), where('uid', '==', visitor.uid), limit(100)));
  assert.equal(ownVotes.docs.length, 1);
  await deleteDoc(ownVotes.docs[0].ref);
  pass('account can enumerate and delete its own poll votes');
  await denied(getDocsFromServer(query(
    collectionGroup(visitor.db, 'votes'), where('uid', '==', other.uid), limit(100))),
  'account cannot list another user votes through a collection-group query');
  await denied(deleteDoc(doc(visitor.db, otherVotePath)),
    'account cannot delete another user poll vote');

  const ownFavorites = await getDocsFromServer(query(
    collection(visitor.db, `users/${visitor.uid}/favorites`), limit(100)));
  for (const item of ownFavorites.docs) await deleteDoc(item.ref);
  const ownQuota = doc(visitor.db,
    `users/${visitor.uid}/contact_message_limits/current`);
  const visitorQuotaBeforeDeletion = (await getDocFromServer(ownQuota)).data();
  const visitorRetryAfter = new Timestamp(
    visitorQuotaBeforeDeletion.periodStartedAt.seconds + 24 * 60 * 60,
    visitorQuotaBeforeDeletion.periodStartedAt.nanoseconds);
  const visitorDeletionRequestRef = doc(visitor.db, visitorDeletionRequestPath);
  await setDoc(visitorDeletionRequestRef, {
    uid: visitor.uid,
    requestedAt: serverTimestamp(),
    retryAfter: visitorRetryAfter,
    status: 'pending',
  });
  pass('account can register deletion request while contact quota remains active');
  await adminDb.doc(contactQuotaPath).update({
    periodStartedAt: new Date(Date.now() - 25 * 60 * 60 * 1000),
  });
  await adminDb.doc(visitorDeletionRequestPath).update({
    retryAfter: new Date(Date.now() - 60 * 60 * 1000),
  });
  await deleteDoc(ownQuota);
  const deleteBatch = writeBatch(visitor.db);
  deleteBatch.delete(doc(visitor.db, `users/${visitor.uid}`));
  deleteBatch.delete(visitorDeletionRequestRef);
  await deleteBatch.commit();
  assert.equal((await adminDb.doc(`users/${visitor.uid}`).get()).exists, false);
  assert.equal((await adminDb.doc(visitorDeletionRequestPath).get()).exists, false);
  assert.equal((await adminDb.doc(`contact_messages/${otherContact}`).get()).exists, true);
  assert.equal((await adminDb.doc(`business_proposals/${otherProposal}`).get()).exists, true);
  assert.equal((await adminDb.doc(`reviews/${otherReview}`).get()).exists, true);
  assert.equal((await adminDb.doc(otherVotePath).get()).exists, true);
  pass('completed account deletion removes the pending request with its profile after quota expiry');

  // Simulate the project-IAM operator's Console runbook using privileged Admin
  // SDK calls against this demo Emulator only. This is operational evidence,
  // not proof that ordinary client Rules authorize these cleanup operations.
  const abandoned = await client('manual-abandoned');
  await syncProfileTransaction(abandoned);
  const abandonedRequestPath = `account_deletion_requests/${abandoned.uid}`;
  const abandonedQuotaPath = `users/${abandoned.uid}/contact_message_limits/current`;
  const abandonedFavoritePath = `users/${abandoned.uid}/favorites/business::manual-test`;
  const abandonedContactPath = `contact_messages/manual-${suffix}`;
  const abandonedProposalPath = `business_proposals/manual-${suffix}`;
  const abandonedReviewPath = `reviews/manual-${suffix}`;
  const abandonedVotePath = `polls/manual-${suffix}/votes/${abandoned.uid}`;
  const unrelatedContactPath = `contact_messages/manual-unrelated-${suffix}`;
  for (const pathName of [
    `users/${abandoned.uid}`, abandonedRequestPath, abandonedQuotaPath,
    abandonedFavoritePath, abandonedContactPath, abandonedProposalPath,
    abandonedReviewPath, abandonedVotePath, unrelatedContactPath,
  ]) ownedPaths.add(pathName);
  await adminDb.doc(abandonedQuotaPath).set({
    uid: abandoned.uid, count: 1, periodStartedAt: new Date(),
    lastMessageId: `manual-${suffix}`, updatedAt: new Date(),
  });
  await adminDb.doc(abandonedFavoritePath).set({
    id: 'business::manual-test', uid: abandoned.uid,
  });
  await adminDb.doc(abandonedContactPath).set({ uid: abandoned.uid, message: 'sintética' });
  await adminDb.doc(abandonedProposalPath).set({ uid: abandoned.uid, name: 'sintética' });
  await adminDb.doc(abandonedReviewPath).set({ uid: abandoned.uid, message: 'sintética' });
  await adminDb.doc(abandonedVotePath).set({ uid: abandoned.uid, option: 'sintética' });
  await adminDb.doc(unrelatedContactPath).set({ uid: other.uid, message: 'preservar' });
  const abandonedQuota = (await getDocFromServer(doc(
    abandoned.db, abandonedQuotaPath))).data();
  const abandonedRetryAfter = new Timestamp(
    abandonedQuota.periodStartedAt.seconds + 24 * 60 * 60,
    abandonedQuota.periodStartedAt.nanoseconds);
  await setDoc(doc(abandoned.db, abandonedRequestPath), {
    uid: abandoned.uid, requestedAt: serverTimestamp(),
    retryAfter: abandonedRetryAfter, status: 'pending',
  });
  await denied(getDocsFromServer(query(
    collection(other.db, 'account_deletion_requests'), limit(100))),
  'ordinary user cannot inspect the pending-deletion queue');
  const authorizedQueue = await adminDb.collection('account_deletion_requests')
    .where('status', '==', 'pending').limit(100).get();
  assert.equal(authorizedQueue.docs.some(item =>
    item.id === abandoned.uid && item.data().status === 'pending'), true);
  pass('privileged project-operator Emulator simulation can find the pending request');

  // Move only this Emulator fixture past the deadline to test the abandoned
  // request path without sleeping for 24 real hours.
  await adminDb.doc(abandonedQuotaPath).update({
    periodStartedAt: new Date(Date.now() - 25 * 60 * 60 * 1000),
  });
  await adminDb.doc(abandonedRequestPath).update({
    retryAfter: new Date(Date.now() - 60 * 60 * 1000),
  });
  const dueQueue = await adminDb.collection('account_deletion_requests')
    .where('status', '==', 'pending').limit(100).get();
  const dueRequest = dueQueue.docs.find(item => item.id === abandoned.uid);
  assert.ok(dueRequest);
  assert.equal(dueRequest.data().status, 'pending');
  assert.ok(dueRequest.data().retryAfter.toDate().getTime() <= Date.now());
  pass('operator queue identifies the request as due only after retryAfter');

  // Exercise recovery after a partial first pass: one owned record is removed,
  // then an injected interruption leaves both Auth and the queue intact.
  await adminDb.doc(abandonedFavoritePath).delete();
  await assert.rejects(async () => { throw new Error('injected local interruption'); });
  assert.equal((await adminDb.doc(abandonedRequestPath).get()).exists, true);
  assert.equal((await adminAuth.getUser(abandoned.uid)).uid, abandoned.uid);
  pass('partial manual cleanup keeps the request and Auth identity for safe retry');

  const deleteOwnedQuery = async collectionName => {
    const page = await adminDb.collection(collectionName)
      .where('uid', '==', abandoned.uid).limit(100).get();
    for (const item of page.docs) await item.ref.delete();
    return page.size;
  };
  await deleteOwnedQuery('contact_messages');
  await deleteOwnedQuery('business_proposals');
  await deleteOwnedQuery('reviews');
  const abandonedVotes = await adminDb.collectionGroup('votes')
    .where('uid', '==', abandoned.uid).limit(100).get();
  for (const item of abandonedVotes.docs) await item.ref.delete();
  await adminDb.doc(abandonedQuotaPath).delete();
  await adminDb.doc(`users/${abandoned.uid}`).delete();
  await adminAuth.deleteUser(abandoned.uid);
  // A failure at the final queue-removal step is resumable: Auth may already
  // be absent, so the operator verifies that fact by UID and removes the request.
  await assert.rejects(async () => { throw new Error('injected final-step interruption'); });
  assert.equal((await adminDb.doc(abandonedRequestPath).get()).exists, true);
  await assert.rejects(adminAuth.getUser(abandoned.uid), error =>
    error.code === 'auth/user-not-found');
  await adminDb.doc(abandonedRequestPath).delete();
  assert.equal((await adminDb.doc(abandonedFavoritePath).get()).exists, false);
  assert.equal((await adminDb.doc(abandonedContactPath).get()).exists, false);
  assert.equal((await adminDb.doc(abandonedProposalPath).get()).exists, false);
  assert.equal((await adminDb.doc(abandonedReviewPath).get()).exists, false);
  assert.equal((await adminDb.doc(abandonedVotePath).get()).exists, false);
  assert.equal((await adminDb.doc(`users/${abandoned.uid}`).get()).exists, false);
  assert.equal((await adminDb.doc(abandonedQuotaPath).get()).exists, false);
  assert.equal((await adminDb.doc(abandonedRequestPath).get()).exists, false);
  assert.equal((await adminDb.doc(unrelatedContactPath).get()).exists, true);
  await assert.rejects(adminAuth.getUser(abandoned.uid), error =>
    error.code === 'auth/user-not-found');
  pass('manual Emulator operator completion removes owned Firestore/Auth data and preserves another UID');

  await denied(deleteDoc(doc(admin.db, `users/${admin.uid}`)),
    'Admin claim cannot self-delete its protected profile');
  await denied(deleteDoc(doc(admin.db, `admin_authorizations/${admin.uid}`)),
    'client cannot remove administrative authorization during account deletion');
  await denied(deleteDoc(doc(visitor.db, `establishments/${publicId}`)),
    'account deletion cannot remove shared public or administrative content');

  console.log(`RESULT ${passed}/${passed} assertions passed`);
}

try {
  await main();
} finally {
  for (const pathName of ownedPaths) {
    if (preservedDocuments.has(pathName)) continue;
    try { await adminDb.doc(pathName).delete(); } catch { /* fixture-only cleanup */ }
  }
  for (const [pathName, previousData] of preservedDocuments) {
    try {
      if (previousData == null) await adminDb.doc(pathName).delete();
      else await adminDb.doc(pathName).set(previousData);
    } catch { /* restore only the exact pre-test document */ }
  }
  for (const uid of users) {
    try { await adminAuth.deleteUser(uid); } catch { /* created test user only */ }
  }
  for (const app of apps) await deleteApp(app).catch(() => {});
  await deleteAdminApp(adminApp).catch(() => {});
}
