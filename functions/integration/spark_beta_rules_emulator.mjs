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
  setDoc, where, limit,
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
  ownedPaths.add(`admin_authorizations/${revoked.uid}`);
  await adminDb.doc(`admin_authorizations/${revoked.uid}`).update({ enabled: false });

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
  const contactId = `spark-contact-${suffix}`;
  const contactQuotaPath = `users/${visitor.uid}/contact_message_limits/current`;
  const proposalId = `spark-proposal-${suffix}`;
  const reviewId = `spark-review-${suffix}`;
  const canonical = (collectionId, id) => adminDb.doc(`${collectionId}/${id}`);
  const projection = (collectionId, id) => adminDb.doc(
    `beta_public_catalog/${collectionId}/items/${id}`);
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
    {
      collectionId: 'jobs',
      id: jobId,
      publicData: {
        name: 'Vaga sintética', title: 'Vaga sintética',
        company: 'Empresa sintética', type: 'job',
      },
    },
  ];
  for (const id of [publicId, draftId, deletedId]) {
    ownedPaths.add(`establishments/${id}`);
    ownedPaths.add(`beta_public_catalog/establishments/items/${id}`);
  }
  ownedPaths.add(`events/${publicEventId}`);
  ownedPaths.add(`beta_public_catalog/events/items/${publicEventId}`);
  for (const fixture of additionalPublicFixtures) {
    ownedPaths.add(`${fixture.collectionId}/${fixture.id}`);
    ownedPaths.add(`beta_public_catalog/${fixture.collectionId}/items/${fixture.id}`);
  }
  ownedPaths.add(`job_private/${jobId}`);
  for (const pathName of ['home_pages/published', 'home_pages/draft']) {
    const snapshot = await adminDb.doc(pathName).get();
    preservedDocuments.set(pathName, snapshot.exists ? snapshot.data() : null);
    ownedPaths.add(pathName);
  }
  for (const pathName of [
    ...[1, 2, 3, 4].map(index => `contact_messages/${contactId}-${index}`),
    contactQuotaPath,
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
    `beta_public_catalog/establishments/items/${publicId}`));
  assert.equal(visible.data().publicData.name, 'Comércio público sintético');
  assert.equal('privateOwnerEmail' in visible.data().publicData, false);
  pass('visitor reads only the allowlisted public projection');
  const guestVisible = await getDocFromServer(doc(guestDb,
    `beta_public_catalog/establishments/items/${publicId}`));
  assert.equal(guestVisible.data().publicData.name, 'Comércio público sintético');
  pass('unauthenticated visitor can read published public content');
  await denied(getDocFromServer(doc(guestDb, `establishments/${publicId}`)),
    'unauthenticated visitor cannot read canonical private content');
  await denied(getDocFromServer(doc(visitor.db, `establishments/${publicId}`)),
    'visitor cannot read canonical private content');
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments/items/${draftId}`)),
  'visitor cannot read a draft projection');
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments/items/${deletedId}`)),
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
    uid: other.uid, name: 'Nome', contact: '', details: 'Proposta',
    status: 'pending', createdAt: serverTimestamp(),
  }), 'user cannot submit a proposal as another account');
  await setDoc(doc(visitor.db, `business_proposals/${proposalId}`), {
    uid: visitor.uid, name: 'Morador sintético', contact: '',
    details: 'Proposta de teste', status: 'pending',
    createdAt: serverTimestamp(),
  });
  pass('authenticated user can submit a pending business proposal');
  await setDoc(doc(visitor.db, `reviews/${reviewId}`), {
    uid: visitor.uid, businessId: publicId,
    business: 'Comércio público sintético', message: 'Avaliação de teste',
    stars: 5, status: 'pending', published: false,
    createdAt: serverTimestamp(),
  });
  pass('authenticated user can submit a moderated unpublished review');
  await denied(setDoc(doc(visitor.db,
    `beta_public_catalog/establishments/items/forged-${suffix}`), {
      visibility: 'public', sourceId: `forged-${suffix}`, schemaVersion: 1,
      updatedAt: new Date(), publicData: { name: 'forged' },
    }), 'ordinary user cannot publish a projection');

  const listed = await getDocsFromServer(query(
    collection(visitor.db, 'beta_public_catalog/establishments/items'),
    where('visibility', '==', 'public'),
    limit(40),
  ));
  assert.equal(listed.docs.some(item => item.id === publicId), true);
  assert.equal(listed.docs.some(item => item.id === draftId || item.id === deletedId), false);
  pass('public list returns only projected public items');
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
  await denied(getDocFromServer(doc(visitor.db, `job_private/${jobId}`)),
    'ordinary user cannot read private job contact data');
  assert.equal((await getDocFromServer(doc(admin.db,
    `job_private/${jobId}`))).data().companyEmail, 'synthetic@example.invalid');
  await setDoc(doc(admin.db, `job_private/${jobId}`), {
    contact: 'contato atualizado sintético',
  }, { merge: true });
  assert.equal((await getDocFromServer(doc(admin.db,
    `job_private/${jobId}`))).data().contact, 'contato atualizado sintético');
  pass('authorized Admin can read and update private job data');
  const publicHome = (await getDocFromServer(doc(guestDb,
    'home_pages/published'))).data();
  assert.equal(publicHome.heroTitle, 'Home sintética');
  assert.equal(publicHome.banners[0].title, 'Banner sintético');
  assert.equal(publicHome.highlights[0].title, 'Destaque sintético');
  pass('unauthenticated visitor can read published Home, banners and highlights');
  await denied(getDocFromServer(doc(guestDb, 'home_pages/draft')),
    'unauthenticated visitor cannot read the Home draft');

  const adminCreatedId = `spark-admin-created-${suffix}`;
  ownedPaths.add(`establishments/${adminCreatedId}`);
  ownedPaths.add(`beta_public_catalog/establishments/items/${adminCreatedId}`);
  await runTransaction(admin.db, async transaction => {
    transaction.set(doc(admin.db, `establishments/${adminCreatedId}`), {
      name: 'Criado pelo Admin', published: true, active: true,
    });
    transaction.set(doc(admin.db,
      `beta_public_catalog/establishments/items/${adminCreatedId}`), {
      visibility: 'public', sourceId: adminCreatedId, schemaVersion: 1,
      updatedAt: serverTimestamp(),
      publicData: { name: 'Criado pelo Admin' },
    });
  });
  assert.equal((await getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments/items/${adminCreatedId}`)))
    .data().publicData.name, 'Criado pelo Admin');
  pass('authorized Admin can publish through the authenticated client SDK');
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
  ownedPaths.add(`establishments/${broadId}`);
  ownedPaths.add(`beta_public_catalog/establishments/items/${broadId}`);
  await runTransaction(admin.db, async transaction => {
    transaction.set(doc(admin.db, `establishments/${broadId}`), {
      ...broadPublicData, published: true, active: true,
    });
    transaction.set(doc(admin.db,
      `beta_public_catalog/establishments/items/${broadId}`), {
      visibility: 'public', sourceId: broadId, schemaVersion: 1,
      updatedAt: serverTimestamp(), publicData: broadPublicData,
    });
  });
  pass('Admin can publish a complete allowlisted establishment payload');
  const clientDraftId = `spark-client-draft-${suffix}`;
  ownedPaths.add(`establishments/${clientDraftId}`);
  ownedPaths.add(`beta_public_catalog/establishments/items/${clientDraftId}`);
  await runTransaction(admin.db, async transaction => {
    const draftProjection = await transaction.get(doc(admin.db,
      `beta_public_catalog/establishments/items/${clientDraftId}`));
    transaction.set(doc(admin.db, `establishments/${clientDraftId}`), {
      name: 'Rascunho criado pelo Admin', published: false, active: true,
    });
    if (draftProjection.exists) {
      transaction.delete(doc(admin.db,
        `beta_public_catalog/establishments/items/${clientDraftId}`));
    }
  });
  pass('Admin can save a draft while atomically removing its projection');
  await denied(setDoc(doc(admin.db,
    `beta_public_catalog/establishments/items/${publicId}`), {
    visibility: 'public', sourceId: publicId, schemaVersion: 1,
    updatedAt: serverTimestamp(),
    publicData: { name: 'Comércio público sintético', privateEmail: 'private@example.invalid' },
  }), 'Admin client cannot put private fields in a public projection');
  await denied(setDoc(doc(admin.db,
    `beta_public_catalog/establishments/items/orphan-${suffix}`), {
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
      description: 'Atualizado atomicamente', updatedAt: serverTimestamp(),
    });
    transaction.update(doc(admin.db,
      `beta_public_catalog/establishments/items/${publicId}`), {
      'publicData.description': 'Atualizado atomicamente',
      updatedAt: serverTimestamp(),
    });
  });
  assert.equal((await getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments/items/${publicId}`)))
    .data().publicData.description, 'Atualizado atomicamente');
  pass('Admin edits canonical data and the public projection atomically');
  await runTransaction(admin.db, async transaction => {
    transaction.update(doc(admin.db, `establishments/${publicId}`), {
      published: false, updatedAt: serverTimestamp(),
    });
    transaction.delete(doc(admin.db,
      `beta_public_catalog/establishments/items/${publicId}`));
  });
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments/items/${publicId}`)),
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
    `beta_public_catalog/establishments/items/${broadId}`));
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
      `beta_public_catalog/establishments/items/${broadId}`));
  });
  assert.equal((await getDocFromServer(doc(admin.db,
    `establishments/${broadId}`))).data().deleted, true);
  await denied(getDocFromServer(doc(visitor.db,
    `beta_public_catalog/establishments/items/${broadId}`)),
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
  for (const pathName of [
    `contact_messages/${otherContact}`,
    `business_proposals/${otherProposal}`,
    `reviews/${otherReview}`,
    votePath,
    otherVotePath,
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
  await adminDb.doc(`reviews/${otherReview}`).set({
    uid: other.uid, businessId: publicId, business: 'fixture', message: 'fixture',
    stars: 5, status: 'pending', published: false, createdAt: new Date(),
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
  await deleteDoc(ownQuota);
  await deleteDoc(doc(visitor.db, `users/${visitor.uid}`));
  assert.equal((await getDocFromServer(doc(visitor.db,
    `users/${visitor.uid}`))).exists(), false);
  assert.equal((await adminDb.doc(`contact_messages/${otherContact}`).get()).exists, true);
  assert.equal((await adminDb.doc(`business_proposals/${otherProposal}`).get()).exists, true);
  assert.equal((await adminDb.doc(`reviews/${otherReview}`).get()).exists, true);
  assert.equal((await adminDb.doc(otherVotePath).get()).exists, true);
  pass('account deletion removes profile, favorites and quota while preserving other users');
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
