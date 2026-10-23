'use strict';

const { localOnly } = require('./business_search');
const { changeAdminClaim } = require('./admin_claim_management');

const DEMO_PROJECT = 'demo-universal-search';
const DEMO_CONFIRMATION = DEMO_PROJECT;
const FIXTURE_ID = Object.freeze({
  establishment: 'local-demo-establishment',
  route: 'local-demo-route',
  utility: 'local-demo-utility',
  job: 'local-demo-job-assistant',
});

function requireSearchLocalEnvironment(env, confirmation = DEMO_CONFIRMATION) {
  const endpoint = (value, port) => value === `127.0.0.1:${port}`;
  if (confirmation !== DEMO_CONFIRMATION || !localOnly(env) ||
      env.GCLOUD_PROJECT !== DEMO_PROJECT ||
      !endpoint(env.FIREBASE_AUTH_EMULATOR_HOST, 9097) ||
      !endpoint(env.FIRESTORE_EMULATOR_HOST, 8087) ||
      !endpoint(env.FUNCTIONS_EMULATOR_HOST, 5007) ||
      env.FUNCTIONS_EMULATOR_PORT !== '5007' ||
      env.GOOGLE_APPLICATION_CREDENTIALS || env.FIREBASE_TOKEN) {
    throw new Error('This operation requires the explicitly confirmed local demo environment.');
  }
  if (env.FIREBASE_CONFIG) {
    let config;
    try { config = JSON.parse(env.FIREBASE_CONFIG); } catch (_) {
      throw new Error('Local Firebase identity could not be verified.');
    }
    if (config.projectId && config.projectId !== DEMO_PROJECT) {
      throw new Error('Local Firebase identity could not be verified.');
    }
  }
  return DEMO_PROJECT;
}

const fixtures = Object.freeze({
  establishment: Object.freeze({
    name: 'Estabelecimento fictício de demonstração',
    category: 'Comércio',
    subcategory: 'Demonstração',
    description: 'Conteúdo fictício para testar a listagem local.',
    shortDescription: 'Cadastro de demonstração.',
    location: 'Local de demonstração',
    address: '',
    published: true,
    active: true,
    featured: false,
    publicContactApproved: false,
  }),
  route: Object.freeze({
    title: 'Rota fictícia de demonstração',
    description: 'Rota fictícia para validar cartões e detalhes no Emulator.',
    category: 'Rota de demonstração',
    type: 'Demonstração',
    location: 'Local de demonstração',
    galleryUrls: [],
    published: true,
    active: true,
  }),
  utility: Object.freeze({
    name: 'Utilidade fictícia de demonstração',
    iconKey: 'explore',
    description: 'Atalho interno de demonstração; não representa um serviço oficial.',
    category: 'Demonstração',
    order: 999,
    destinationType: 'internal',
    destination: 'tourism',
    published: true,
    active: true,
  }),
  jobPublic: Object.freeze({
    title: 'Vaga fictícia de demonstração',
    description: 'Vaga fictícia para testar a administração local.',
    category: 'Demonstração',
    location: 'Local de demonstração',
    imageUrl: '',
    artwork: 0,
    galleryUrls: [],
    published: true,
    active: true,
    expiresAt: null,
    updatedAt: new Date('2026-10-01T00:00:00.000Z'),
  }),
  jobPrivate: Object.freeze({
    contact: 'contato-ficticio@example.invalid',
    phone: '',
    whatsapp: '',
    link: '',
    instagram: '',
    maps: '',
    mapsUrl: '',
    additionalInfo: 'Dados inteiramente fictícios de demonstração.',
    schemaVersion: 1,
    updatedAt: new Date('2026-10-01T00:00:00.000Z'),
  }),
});

async function createIfAbsent(db, collection, id, data) {
  const reference = db.collection(collection).doc(id);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (snapshot.exists) return 'preserved';
    transaction.create(reference, data);
    return 'created';
  });
}

async function createJobPairIfAbsent(db) {
  const publicRef = db.collection('jobs').doc(FIXTURE_ID.job);
  const privateRef = db.collection('job_private').doc(FIXTURE_ID.job);
  return db.runTransaction(async (transaction) => {
    const [publicSnapshot, privateSnapshot] = await Promise.all([
      transaction.get(publicRef), transaction.get(privateRef),
    ]);
    if (publicSnapshot.exists && privateSnapshot.exists) return 'preserved';
    if (publicSnapshot.exists || privateSnapshot.exists) return 'conflict';
    transaction.create(publicRef, { ...fixtures.jobPublic });
    transaction.create(privateRef, { ...fixtures.jobPrivate });
    return 'created';
  });
}

async function seedSearchLocalFixtures({ db, env, confirmation }) {
  requireSearchLocalEnvironment(env, confirmation);
  const operations = [
    ['establishment', () => createIfAbsent(db, 'establishments', FIXTURE_ID.establishment, fixtures.establishment)],
    ['route', () => createIfAbsent(db, 'routes', FIXTURE_ID.route, fixtures.route)],
    ['utility', () => createIfAbsent(db, 'utilities', FIXTURE_ID.utility, fixtures.utility)],
    ['job', () => createJobPairIfAbsent(db)],
  ];
  const result = { created: 0, preserved: 0, conflicts: 0, records: [] };
  for (const [kind, apply] of operations) {
    const status = await apply();
    result[status === 'conflict' ? 'conflicts' : status]++;
    result.records.push({ kind, status });
  }
  return result;
}

async function provisionSearchLocalAdmin({ auth, db, env, email, password,
  confirmation, grantAdmin = changeAdminClaim }) {
  requireSearchLocalEnvironment(env, confirmation);
  if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) ||
      email.length > 254 || typeof password !== 'string' || password.length < 12 || password.length > 128) {
    throw new Error('A valid local email and a password of at least 12 characters are required.');
  }
  try {
    await auth.getUserByEmail(email.trim());
    throw new Error('This email already exists in the local Emulator; no account was changed.');
  } catch (error) {
    if (error.message.includes('already exists')) throw error;
    if (error.code !== 'auth/user-not-found') throw new Error('Could not verify the local account.');
  }
  const user = await auth.createUser({ email: email.trim(), password });
  // Keep a newly created account if claim setup fails; the versioned helper
  // deliberately leaves its authorization disabled for manual local review.
  await grantAdmin({
    auth, db, uid: user.uid, action: 'grant', operator: 'local-owner-setup',
    reason: 'Fictional local demo owner account',
    confirmation: `${DEMO_PROJECT}:${user.uid}:grant`, apply: true, env,
  });
  const [savedUser, state] = await Promise.all([
    auth.getUser(user.uid),
    db.collection('admin_authorizations').doc(user.uid).get(),
  ]);
  const version = savedUser.customClaims?.adminVersion;
  const authorization = state.data();
  if (savedUser.customClaims?.admin !== true || typeof version !== 'string' ||
      authorization?.enabled !== true || authorization.pending !== false ||
      authorization.version !== version) {
    throw new Error('Local Admin authorization could not be verified; review the local account.');
  }
  return { project: DEMO_PROJECT, uid: user.uid, adminVersioned: true };
}

module.exports = {
  DEMO_PROJECT,
  DEMO_CONFIRMATION,
  FIXTURE_ID,
  fixtures,
  requireSearchLocalEnvironment,
  seedSearchLocalFixtures,
  provisionSearchLocalAdmin,
};
