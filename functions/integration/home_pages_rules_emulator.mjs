import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT_ID = 'demo-universal-search';
const FIRESTORE_HOST = '127.0.0.1:8087';
const AUTH_HOST = '127.0.0.1:9097';
assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID);
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, FIRESTORE_HOST);
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, AUTH_HOST);

for (const endpoint of [FIRESTORE_HOST, AUTH_HOST]) {
  const parsed = new URL(`http://${endpoint}`);
  assert.equal(parsed.hostname, '127.0.0.1');
  assert.ok(parsed.port);
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requireFromFunctions = createRequire(path.join(root, 'functions/package.json'));
const { initializeApp: initializeAdminApp, deleteApp: deleteAdminApp } =
  requireFromFunctions('firebase-admin/app');
const { getAuth } = requireFromFunctions('firebase-admin/auth');
const {
  FieldValue: AdminFieldValue,
  getFirestore: getAdminFirestore,
} = requireFromFunctions('firebase-admin/firestore');
const { initializeApp: initializeClientApp, deleteApp: deleteClientApp } =
  requireFromFunctions('firebase/app');
const {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  inMemoryPersistence,
  initializeAuth,
  signOut,
} = requireFromFunctions('firebase/auth');
const {
  connectFirestoreEmulator,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  collection,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} = requireFromFunctions('firebase/firestore');

const runId = `home-rules-${randomUUID()}`;
const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, `${runId}-server`);
const adminAuth = getAuth(adminApp);
const adminDb = getAdminFirestore(adminApp);
const clients = [];
const userIds = new Set();
const documentPaths = new Set();
const checks = [];

function clientFor(label) {
  const app = initializeClientApp({
    apiKey: 'demo-key',
    projectId: PROJECT_ID,
    appId: `demo-${label}`,
  }, `${runId}-${label}`);
  const auth = initializeAuth(app, { persistence: inMemoryPersistence });
  connectAuthEmulator(auth, `http://${AUTH_HOST}`, { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8087);
  const client = { app, auth, db };
  clients.push(client);
  return client;
}

async function account(client, label, authorization) {
  const password = `Local-${randomUUID()}-Aa1!`;
  const email = `${runId}-${label}@example.invalid`;
  const credential = await createUserWithEmailAndPassword(client.auth, email, password);
  const uid = credential.user.uid;
  userIds.add(uid);
  if (authorization) {
    await adminAuth.setCustomUserClaims(uid, {
      admin: true,
      adminVersion: authorization.version,
    });
    const authorizationRef = adminDb.doc(`admin_authorizations/${uid}`);
    documentPaths.add(authorizationRef.path);
    await authorizationRef.set({
      enabled: authorization.enabled,
      pending: false,
      version: authorization.version,
      operationId: randomUUID(),
      updatedAt: AdminFieldValue.serverTimestamp(),
    });
    await credential.user.getIdToken(true);
  }
  return credential.user;
}

async function denied(operation, message) {
  await assert.rejects(operation, (error) => {
    assert.ok(
      ['permission-denied', 'unauthenticated'].includes(error.code),
      `${message}: expected a Rules denial, received ${error.code ?? error.name}`,
    );
    return true;
  }, message);
}

async function check(label, callback) {
  await callback();
  checks.push(label);
  console.log(`PASS ${label}`);
}

async function cleanup() {
  await Promise.all([...documentPaths].map((documentPath) =>
    adminDb.doc(documentPath).delete().catch(() => {})));
  await Promise.all([...userIds].map((uid) => adminAuth.deleteUser(uid).catch(() => {})));
  await Promise.all(clients.map(({ auth, app }) => Promise.all([
    signOut(auth).catch(() => {}),
    deleteClientApp(app).catch(() => {}),
  ])));
  await deleteAdminApp(adminApp).catch(() => {});
}

async function main() {
  for (const [host, label] of [[FIRESTORE_HOST, 'Firestore'], [AUTH_HOST, 'Auth']]) {
    const response = await fetch(`http://${host}/`);
    assert.ok(response.status < 500, `${label} Emulator must be reachable locally.`);
  }

  const adminClient = clientFor('admin');
  const commonClient = clientFor('common');
  const revokedClient = clientFor('revoked');
  const adminVersion = `home-admin-${randomUUID()}`;
  const revokedVersion = `home-revoked-${randomUUID()}`;
  const adminUser = await account(adminClient, 'admin', {
    enabled: true,
    version: adminVersion,
  });
  const commonUser = await account(commonClient, 'common');
  const revokedUser = await account(revokedClient, 'revoked', {
    enabled: false,
    version: revokedVersion,
  });
  const publishedPath = 'home_pages/published';
  const draftPath = 'home_pages/draft';
  documentPaths.add(publishedPath);
  documentPaths.add(draftPath);
  for (const documentPath of [publishedPath, draftPath]) {
    assert.equal((await adminDb.doc(documentPath).get()).exists, false,
      `Fresh Emulator unexpectedly contains ${documentPath}; no document was overwritten.`);
  }
  await adminDb.doc(publishedPath).set({
    title: 'Home pública sintética',
    version: 1,
    published: true,
  });
  await adminDb.doc(draftPath).set({
    title: 'Rascunho privado sintético',
    version: 1,
    published: false,
  });

  const commonPublished = doc(commonClient.db, publishedPath);
  const commonDraft = doc(commonClient.db, draftPath);
  const adminDraft = doc(adminClient.db, draftPath);
  const adminPublished = doc(adminClient.db, publishedPath);
  const revokedDraft = doc(revokedClient.db, draftPath);
  const revokedPublished = doc(revokedClient.db, publishedPath);

  await check('Admin autenticado e autorizado lê rascunho', async () => {
    assert.equal((await getDoc(adminDraft)).data().title, 'Rascunho privado sintético');
    assert.equal((await adminUser.getIdTokenResult(true)).claims.admin, true);
  });

  await check('Admin edita rascunho pela SDK cliente', async () => {
    await updateDoc(adminDraft, {
      title: 'Rascunho editado por Admin',
      updatedAt: serverTimestamp(),
    });
    assert.equal((await getDoc(adminDraft)).data().title, 'Rascunho editado por Admin');
  });

  await check('Admin publica a configuração pela SDK cliente', async () => {
    const batch = writeBatch(adminClient.db);
    batch.set(adminDraft, {
      title: 'Home publicada pelo Admin',
      version: 2,
      published: false,
      updatedAt: serverTimestamp(),
    });
    batch.set(adminPublished, {
      title: 'Home publicada pelo Admin',
      version: 2,
      published: true,
      publishedAt: serverTimestamp(),
    });
    await batch.commit();
    assert.equal((await getDoc(adminPublished)).data().version, 2);
    assert.equal((await getDoc(adminPublished)).data().published, true);
  });

  await check('Usuário comum lê somente published; get e list de draft são negados', async () => {
    assert.equal((await getDoc(commonPublished)).data().title, 'Home publicada pelo Admin');
    await denied(getDoc(commonDraft), 'Common user must not read a draft.');
    await denied(getDocs(collection(commonClient.db, 'home_pages')),
      'Common user must not list the collection containing drafts.');
  });

  await check('Usuário comum não cria, altera nem publica home_pages', async () => {
    await denied(setDoc(commonDraft, { title: 'Escrita negada' }),
      'Common user must not write a draft.');
    await denied(updateDoc(commonPublished, { title: 'Publicação negada' }),
      'Common user must not modify published content.');
    assert.equal((await adminDb.doc(publishedPath).get()).get('title'), 'Home publicada pelo Admin');
  });

  await check('Admin revogado não lê draft nem escreve ou publica', async () => {
    await denied(getDoc(revokedDraft), 'Revoked Admin must not read a draft.');
    await denied(setDoc(revokedDraft, { title: 'Revogado' }),
      'Revoked Admin must not write a draft.');
    await denied(updateDoc(revokedPublished, { title: 'Revogado' }),
      'Revoked Admin must not publish.');
    assert.equal((await adminDb.doc(publishedPath).get()).get('title'), 'Home publicada pelo Admin');
  });

  const establishmentPrefix = `establishments/${runId}`;
  const establishmentPublishedPath = `${establishmentPrefix}-published`;
  const establishmentDraftPath = `${establishmentPrefix}-draft`;
  const establishmentInactivePath = `${establishmentPrefix}-inactive`;
  const establishmentCreatedPath = `${establishmentPrefix}-created-by-admin`;
  const utilityCreatedPath = `utilities/${runId}-created-by-admin`;
  for (const documentPath of [
    establishmentPublishedPath,
    establishmentDraftPath,
    establishmentInactivePath,
    establishmentCreatedPath,
    utilityCreatedPath,
  ]) {
    documentPaths.add(documentPath);
    assert.equal((await adminDb.doc(documentPath).get()).exists, false,
      `Fresh Emulator unexpectedly contains ${documentPath}; no document was overwritten.`);
  }
  const establishmentFixture = {
    name: 'Comércio sintético da praça',
    title: 'Comércio sintético da praça',
    description: 'Fixture local para autorização das Rules.',
    category: 'Comércio',
    published: true,
    active: true,
  };
  await adminDb.doc(establishmentPublishedPath).set(establishmentFixture);
  await adminDb.doc(establishmentDraftPath).set({
    ...establishmentFixture,
    published: false,
  });
  await adminDb.doc(establishmentInactivePath).set({
    ...establishmentFixture,
    active: false,
  });

  const adminEstablishmentDraft = doc(adminClient.db, establishmentDraftPath);
  const adminEstablishmentCreated = doc(adminClient.db, establishmentCreatedPath);
  const commonEstablishmentPublished = doc(commonClient.db, establishmentPublishedPath);
  const commonEstablishmentDraft = doc(commonClient.db, establishmentDraftPath);
  const commonEstablishmentInactive = doc(commonClient.db, establishmentInactivePath);
  const commonEstablishmentCreated = doc(commonClient.db, establishmentCreatedPath);
  const revokedEstablishmentDraft = doc(revokedClient.db, establishmentDraftPath);
  const revokedEstablishmentPublished = doc(revokedClient.db, establishmentPublishedPath);

  await check('Admin autorizado edita draft e cria estabelecimento publicado/utilidade pela SDK cliente', async () => {
    await updateDoc(adminEstablishmentDraft, {
      description: 'Descrição atualizada pelo Admin sintético.',
      updatedAt: serverTimestamp(),
    });
    await setDoc(adminEstablishmentCreated, {
      ...establishmentFixture,
      published: true,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(adminClient.db, utilityCreatedPath), {
      name: 'Atendimento sintético',
      iconKey: 'phone',
      description: 'Utilidade fictícia para validar a autorização.',
      category: 'Serviços',
      destinationType: 'internal',
      destination: 'usefulPhones',
      order: 10,
      active: true,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    assert.equal((await getDoc(adminEstablishmentDraft)).data().published, false);
    assert.equal((await getDoc(adminEstablishmentCreated)).data().name, establishmentFixture.name);
    assert.equal((await getDoc(doc(adminClient.db, utilityCreatedPath))).data().active, true);
  });

  await check('Usuário comum lê estabelecimento publicado e ativo, mas não draft/inativo', async () => {
    assert.equal((await getDoc(commonEstablishmentPublished)).data().published, true);
    await denied(getDoc(commonEstablishmentDraft), 'Common user must not read an establishment draft.');
    await denied(getDoc(commonEstablishmentInactive), 'Common user must not read an inactive establishment.');
    await denied(getDocs(collection(commonClient.db, 'establishments')),
      'Common user must not list the administrative establishments collection.');
  });

  await check('Usuário comum não cria/edita estabelecimentos ou utilidades', async () => {
    await denied(setDoc(commonEstablishmentCreated, establishmentFixture),
      'Common user must not create an establishment.');
    await denied(updateDoc(commonEstablishmentPublished, {
      description: 'Alteração sem autorização',
    }), 'Common user must not edit a published establishment.');
    await denied(setDoc(doc(commonClient.db, utilityCreatedPath), {
      name: 'Utilidade não autorizada',
    }), 'Common user must not create a utility.');
    assert.equal((await adminDb.doc(establishmentPublishedPath).get()).get('description'),
      establishmentFixture.description);
  });

  await check('Admin revogado não lê draft nem grava estabelecimento', async () => {
    await denied(getDoc(revokedEstablishmentDraft), 'Revoked Admin must not read an establishment draft.');
    await denied(updateDoc(revokedEstablishmentPublished, {
      description: 'Admin revogado',
    }), 'Revoked Admin must not edit a published establishment.');
    assert.equal((await adminDb.doc(establishmentPublishedPath).get()).get('description'),
      establishmentFixture.description);
  });

  const routePrefix = `routes/${runId}`;
  const routePublishedPath = `${routePrefix}-published`;
  const routeDraftPath = `${routePrefix}-draft`;
  const routeInactivePath = `${routePrefix}-inactive`;
  const routeCreatedPath = `${routePrefix}-created-by-admin`;
  for (const documentPath of [
    routePublishedPath,
    routeDraftPath,
    routeInactivePath,
    routeCreatedPath,
  ]) {
    documentPaths.add(documentPath);
    assert.equal((await adminDb.doc(documentPath).get()).exists, false,
      `Fresh Emulator unexpectedly contains ${documentPath}; no document was overwritten.`);
  }
  const routeFixture = {
    title: 'Trilha sintética para regras',
    description: 'Conteúdo fictício criado somente no Emulator.',
    category: 'trilhas',
    iconKey: 'turismo',
    order: 1,
    published: true,
    active: true,
  };
  await adminDb.doc(routePublishedPath).set(routeFixture);
  await adminDb.doc(routeDraftPath).set({ ...routeFixture, published: false });
  await adminDb.doc(routeInactivePath).set({ ...routeFixture, active: false });

  const adminRoutePublished = doc(adminClient.db, routePublishedPath);
  const adminRouteDraft = doc(adminClient.db, routeDraftPath);
  const adminRouteCreated = doc(adminClient.db, routeCreatedPath);
  const commonRoutePublished = doc(commonClient.db, routePublishedPath);
  const commonRouteDraft = doc(commonClient.db, routeDraftPath);
  const commonRouteInactive = doc(commonClient.db, routeInactivePath);
  const commonRouteCreated = doc(commonClient.db, routeCreatedPath);
  const revokedRoutePublished = doc(revokedClient.db, routePublishedPath);
  const revokedRouteDraft = doc(revokedClient.db, routeDraftPath);

  await check('Admin cria e edita conteúdo turístico pela SDK cliente com iconKey e ordem nomeados', async () => {
    await updateDoc(adminRouteDraft, {
      description: 'Descrição editada pelo Admin sintético.',
      iconKey: 'turismo',
      order: 2,
      updatedAt: serverTimestamp(),
    });
    await setDoc(adminRouteCreated, {
      ...routeFixture,
      title: 'Ponto fictício criado pelo Admin',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    assert.equal((await getDoc(adminRouteDraft)).data().published, false);
    assert.equal((await getDoc(adminRouteDraft)).data().order, 2);
    assert.equal((await getDoc(adminRouteCreated)).data().iconKey, 'turismo');
  });

  await check('Usuário comum lê somente rota publicada e ativa; rascunho e inativo são negados', async () => {
    assert.equal((await getDoc(commonRoutePublished)).data().published, true);
    await denied(getDoc(commonRouteDraft), 'Common user must not read a tourism draft.');
    await denied(getDoc(commonRouteInactive), 'Common user must not read inactive tourism content.');
    await denied(getDocs(collection(commonClient.db, 'routes')),
      'Common user must not list administrative tourism content.');
  });

  await check('Usuário comum não cria, edita ou ativa conteúdo turístico', async () => {
    await denied(setDoc(commonRouteCreated, routeFixture),
      'Common user must not create tourism content.');
    await denied(updateDoc(commonRoutePublished, {
      description: 'Edição sem autorização',
    }), 'Common user must not edit published tourism content.');
    assert.equal((await adminDb.doc(routePublishedPath).get()).get('description'),
      routeFixture.description);
  });

  await check('Admin autorizado desativa e oculta logicamente a rota sem apagá-la', async () => {
    await updateDoc(adminRoutePublished, {
      active: false,
      published: false,
      deleted: true,
      deletedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    const stored = await adminDb.doc(routePublishedPath).get();
    assert.equal(stored.exists, true);
    assert.equal(stored.get('active'), false);
    assert.equal(stored.get('published'), false);
    assert.equal(stored.get('deleted'), true);
    await denied(getDoc(commonRoutePublished),
      'Common user must not read logically removed tourism content.');
  });

  await check('Admin revogado não lê rascunho nem edita conteúdo turístico publicado', async () => {
    await denied(getDoc(revokedRouteDraft), 'Revoked Admin must not read a tourism draft.');
    await denied(updateDoc(revokedRoutePublished, {
      description: 'Admin revogado',
    }), 'Revoked Admin must not edit tourism content.');
    assert.equal((await adminDb.doc(routeDraftPath).get()).get('description'),
      'Descrição editada pelo Admin sintético.');
  });

  console.log(JSON.stringify({
    project: PROJECT_ID,
    firestore: FIRESTORE_HOST,
    auth: AUTH_HOST,
    rulesFile: 'firestore.rules',
    checksPassed: checks.length,
    note: 'Client SDK calls were evaluated by Firestore Emulator Rules. Admin SDK was used only to provision and clean exact synthetic fixtures.',
  }, null, 2));
}

main().catch((error) => {
  console.error(`Home Rules validation failed: ${error.code ?? error.name ?? 'error'}`);
  console.error(error.message);
  process.exitCode = 1;
}).finally(cleanup);
