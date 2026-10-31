import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash, randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { changeAdminClaim } from '../admin_claim_management.js';
import { provisionSearchLocalAdmin, requireSearchLocalEnvironment } from '../local_demo_environment.js';

const PROJECT_ID = 'demo-universal-search';
const AUTH_HOST = '127.0.0.1:9097';
const FIRESTORE_HOST = '127.0.0.1:8087';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requireFromFunctions = createRequire(path.join(root, 'functions', 'package.json'));
const { initializeApp: initializeAdminApp, deleteApp: deleteAdminApp } = requireFromFunctions('firebase-admin/app');
const { getAuth: getAdminAuth } = requireFromFunctions('firebase-admin/auth');
const { getFirestore: getAdminFirestore } = requireFromFunctions('firebase-admin/firestore');
const { initializeApp: initializeClientApp, deleteApp: deleteClientApp } = requireFromFunctions('firebase/app');
const { initializeAuth, inMemoryPersistence, connectAuthEmulator,
  signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut } = requireFromFunctions('firebase/auth');
const { getFirestore, connectFirestoreEmulator, doc, setDoc, updateDoc,
  getDocFromServer, getDocsFromServer, collection, query, where } = requireFromFunctions('firebase/firestore');

const env = process.env;
assert.equal(env.GCLOUD_PROJECT, PROJECT_ID);
assert.equal(env.FIREBASE_CONFIG && JSON.parse(env.FIREBASE_CONFIG).projectId, PROJECT_ID);
assert.equal(env.FIREBASE_AUTH_EMULATOR_HOST, AUTH_HOST);
assert.equal(env.FIRESTORE_EMULATOR_HOST, FIRESTORE_HOST);
assert.equal(env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
assert.equal(env.FIREBASE_TOKEN, undefined);
requireSearchLocalEnvironment(env, PROJECT_ID);

const id = `business-client-${randomUUID()}`;
const emailSuffix = randomUUID();
const adminEmail = `business-admin-${emailSuffix}@example.invalid`;
const adminPassword = `Local-${randomUUID()}-Aa1!`;
const ordinaryEmail = `business-user-${emailSuffix}@example.invalid`;
const ordinaryPassword = `Local-${randomUUID()}-Bb2!`;
const serverApp = initializeAdminApp({ projectId: PROJECT_ID }, `business-rules-server-${process.pid}`);
const adminAuth = getAdminAuth(serverApp);
const adminDb = getAdminFirestore(serverApp);
const clientApps = [];
const clientAuths = [];
let ordinaryAuth = null;
let adminUid = null;

async function authenticatedClient(email, password, suffix) {
  const app = initializeClientApp({
    apiKey: 'demo-emulator-api-key',
    authDomain: `${PROJECT_ID}.firebaseapp.com`,
    projectId: PROJECT_ID,
    appId: `demo-${suffix}`,
  }, `business-rules-${suffix}-${process.pid}`);
  clientApps.push(app);
  const auth = initializeAuth(app, { persistence: inMemoryPersistence });
  clientAuths.push(auth);
  connectAuthEmulator(auth, `http://${AUTH_HOST}`, { disableWarnings: true });
  const credential = await signInWithEmailAndPassword(auth, email, password);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8087);
  return { app, auth, db, user: credential.user };
}

function expectDenied(operation, label) {
  return assert.rejects(operation, error => {
    assert.equal(error.code, 'permission-denied', `${label} must be rejected by Firestore Rules`);
    return true;
  });
}

const searchUrl = `http://127.0.0.1:5007/${PROJECT_ID}/southamerica-east1/searchBusinesses`;
const searchAppCheck = `${Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url')}.` +
  `${Buffer.from(JSON.stringify({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url')}.`;

async function waitForSearchIndex(expected) {
  const index = adminDb.collection('business_search_index').doc(`establishments__${id}`);
  const deadline = Date.now() + 15000;
  do {
    const snapshot = await index.get();
    if (snapshot.exists === expected) return;
    await new Promise(resolve => setTimeout(resolve, 100));
  } while (Date.now() < deadline);
  throw new Error(`Search index did not converge to expected presence=${expected}.`);
}

async function publicSearch() {
  const token = await ordinaryAuth.currentUser.getIdToken();
  const rateId = createHash('sha256').update(ordinaryAuth.currentUser.uid).digest('hex');
  await adminDb.collection('business_search_rate_limits').doc(rateId).delete();
  const response = await fetch(searchUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${token}`,
      'X-Firebase-AppCheck': searchAppCheck },
    body: JSON.stringify({ data: { query: 'cafe ficticio', filter: 'commerce', limit: 10 } }),
  });
  const body = await response.json();
  assert.equal(response.status, 200, 'public search callable should succeed in the Functions Emulator');
  assert.ok(Array.isArray(body.result?.results), 'search callable should return result rows');
  return body.result.results;
}

try {
  const provisioned = await provisionSearchLocalAdmin({ auth: adminAuth, db: adminDb,
    env, email: adminEmail, password: adminPassword, confirmation: PROJECT_ID });
  adminUid = provisioned.uid;
  const adminClient = await authenticatedClient(adminEmail, adminPassword, 'authorized-admin');
  const ordinaryClientApp = initializeClientApp({
    apiKey: 'demo-emulator-api-key', projectId: PROJECT_ID,
    appId: `demo-ordinary-${emailSuffix}`,
  }, `business-rules-ordinary-${process.pid}`);
  clientApps.push(ordinaryClientApp);
  ordinaryAuth = initializeAuth(ordinaryClientApp, { persistence: inMemoryPersistence });
  clientAuths.push(ordinaryAuth);
  connectAuthEmulator(ordinaryAuth, `http://${AUTH_HOST}`, { disableWarnings: true });
  await createUserWithEmailAndPassword(ordinaryAuth, ordinaryEmail, ordinaryPassword);
  const ordinaryDb = getFirestore(ordinaryClientApp);
  connectFirestoreEmulator(ordinaryDb, '127.0.0.1', 8087);

  const adminRef = doc(adminClient.db, 'establishments', id);
  const ordinaryRef = doc(ordinaryDb, 'establishments', id);
  const draft = {
    name: 'Café fictício da praça',
    category: 'Comércio',
    subcategory: 'Alimentação',
    description: 'Cadastro sintético para validar o editor administrativo.',
    location: 'Endereço fictício, Cachoeiras de Macacu',
    phone: '5521999990000',
    whatsapp: '5521999990000',
    instagram: 'https://instagram.com/cafe.ficticio',
    maps: 'https://maps.google.com/?q=-22.462,-42.653',
    imageUrl: 'https://images.example.invalid/cafe-cover.jpg',
    galleryUrls: ['https://images.example.invalid/cafe-cover.jpg',
      'https://images.example.invalid/cafe-interior.jpg'],
    videoUrls: ['https://www.youtube.com/watch?v=dQw4w9WgXcQ'],
    active: true,
    published: false,
    featured: false,
    publicContactApproved: false,
  };

  // The writes below use the Firebase client SDK and are evaluated by firestore.rules.
  await setDoc(adminRef, draft);
  const savedDraft = await getDocFromServer(adminRef);
  assert.equal(savedDraft.exists(), true);
  assert.equal(savedDraft.data().published, false);
  assert.equal(savedDraft.data().name, draft.name);
  assert.equal(savedDraft.data().category, draft.category);
  assert.equal(savedDraft.data().description, draft.description);
  assert.equal(savedDraft.data().location, draft.location);
  assert.equal(savedDraft.data().phone, draft.phone);
  assert.equal(savedDraft.data().whatsapp, draft.whatsapp);
  assert.equal(savedDraft.data().instagram, draft.instagram);
  assert.equal(savedDraft.data().maps, draft.maps);
  assert.equal(savedDraft.data().imageUrl, draft.imageUrl);
  assert.equal(savedDraft.data().active, true);
  assert.deepEqual(savedDraft.data().galleryUrls, draft.galleryUrls);
  assert.deepEqual(savedDraft.data().videoUrls, draft.videoUrls);
  process.stdout.write('PASS Admin client creates draft; name/category/media/contact fields persist.\n');

  await expectDenied(getDocFromServer(ordinaryRef), 'ordinary user reading a draft');
  await expectDenied(setDoc(doc(ordinaryDb, 'establishments', `${id}-unauthorized`), draft),
    'ordinary user creating an establishment');
  process.stdout.write('PASS ordinary client cannot read a draft or create an establishment.\n');

  await updateDoc(adminRef, {
    description: 'Descrição atualizada pelo Admin no cliente.',
    phone: '5521999990001',
    imageUrl: 'https://images.example.invalid/cafe-cover-v2.jpg',
    galleryUrls: ['https://images.example.invalid/cafe-cover-v2.jpg',
      'https://images.example.invalid/cafe-interior.jpg'],
    published: false,
  });
  const edited = await adminDb.collection('establishments').doc(id).get();
  assert.equal(edited.data().description, 'Descrição atualizada pelo Admin no cliente.');
  assert.equal(edited.data().phone, '5521999990001');
  assert.equal(edited.data().galleryUrls.length, 2);
  const sameName = await getDocsFromServer(query(collection(adminClient.db, 'establishments'),
    where('name', '==', draft.name)));
  assert.equal(sameName.docs.filter(item => item.id === id).length, 1,
    'editing the same record must not create a duplicate');
  process.stdout.write('PASS edit persists through the client SDK and keeps one document.\n');

  await updateDoc(adminRef, { active: true, published: true });
  const publicView = await getDocFromServer(ordinaryRef);
  assert.equal(publicView.exists(), true);
  assert.equal(publicView.data().category, 'Comércio');
  assert.equal(publicView.data().published, true);
  await waitForSearchIndex(true);
  const foundByCategory = (await publicSearch()).find(item => item.id === id);
  assert.ok(foundByCategory, 'published establishment must appear in its public category search');
  assert.equal(foundByCategory.category, 'Comércio');
  await expectDenied(getDocsFromServer(query(collection(ordinaryDb, 'establishments'),
    where('category', '==', 'Comércio'))), 'ordinary direct collection listing');
  process.stdout.write('PASS published active establishment appears in the public Comércio search; direct Firestore list stays restricted.\n');

  await updateDoc(adminRef, { active: false });
  await waitForSearchIndex(false);
  assert.equal((await publicSearch()).some(item => item.id === id), false,
    'inactive establishment must be absent from public search');
  await expectDenied(getDocFromServer(ordinaryRef), 'ordinary user reading an inactive establishment');
  await updateDoc(adminRef, { active: true, published: false });
  await waitForSearchIndex(false);
  assert.equal((await publicSearch()).some(item => item.id === id), false,
    'draft establishment must be absent from public search');
  await expectDenied(getDocFromServer(ordinaryRef), 'ordinary user reading an unpublished establishment');
  process.stdout.write('PASS inactive and draft establishments are absent from public search and direct public reads.\n');

  await updateDoc(adminRef, { active: true, published: true });
  await changeAdminClaim({ auth: adminAuth, db: adminDb, uid: adminUid, action: 'revoke',
    operator: 'local-business-client-rules-test', reason: 'Synthetic emulator revocation',
    confirmation: `${PROJECT_ID}:${adminUid}:revoke`, apply: true, env });
  await expectDenied(updateDoc(adminRef, { description: 'Não deve persistir após revogação.' }),
    'revoked Admin client updating an establishment');
  const revokedDocument = await adminDb.collection('establishments').doc(id).get();
  assert.notEqual(revokedDocument.data().description, 'Não deve persistir após revogação.');
  process.stdout.write('PASS revoked Admin client is denied; stored content remains unchanged.\n');

  process.stdout.write(JSON.stringify({
    project: PROJECT_ID,
    rulesFile: 'firestore.rules',
    sdk: 'Firebase Web Client SDK against Auth and Firestore Emulators',
    flow: ['create draft', 'reload persisted record', 'edit same record', 'publish',
      'public visibility', 'hide inactive/unpublished', 'deny ordinary and revoked Admin'],
    syntheticDocumentId: id,
    passed: 6,
  }, null, 2) + '\n');
} finally {
  await Promise.all(clientAuths.map(auth => signOut(auth).catch(() => {})));
  await Promise.all(clientApps.map(app => deleteClientApp(app).catch(() => {})));
  await deleteAdminApp(serverApp).catch(() => {});
}
