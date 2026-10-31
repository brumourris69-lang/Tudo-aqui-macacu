import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  fingerprintFixture,
  getFirebaseCliReadOnlySession,
  isUnchangedOwnedFixture,
  isUnchangedSyntheticUser,
} from './staging-rules-client-homologation.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(ROOT, 'functions/package.json'));
const PROJECT_ID = 'macacu-rules-hml-29oct26-a71c';
const PROJECT_NUMBER = '158164993050';
const PRODUCTION_IDS = new Set(['tudo-aqui-macacu']);
const EXISTING_STAGING_IDS = new Set(['macacu-staging-261022', 'rmhnaduzkykyudqnsdyf']);
const WEB_APP_ID = '1:158164993050:web:f1993ab15a1c65c6597da3';
const IAM_GRANT_EXPIRES_AT = '2026-10-29T23:30:00Z';
const PUBLISHER_EMAIL = `rules-publisher-hml-mvtzuxcs@${PROJECT_ID}.iam.gserviceaccount.com`;
const FIXTURE_OPERATOR_EMAIL = `fixture-operator-hml-mvtzuxcs@${PROJECT_ID}.iam.gserviceaccount.com`;
const PUBLISHER_ROLE = `projects/${PROJECT_ID}/roles/rulesPublisherHml`;
const FIXTURE_ROLE = `projects/${PROJECT_ID}/roles/fixtureOperatorHml`;
const EXPECTED_CANDIDATE_SHA256 =
  'ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8';
const EXPECTED_DENY_ALL_SHA256 =
  'ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb';
const CANDIDATE_PATH = resolve(ROOT, 'firestore.rules');
const MIRROR_PATH = resolve(ROOT, 'firestore.claims-local.rules');
const DENY_ALL_PATH = resolve(
  ROOT,
  'docs/staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.rules',
);
const DENY_ALL_METADATA_PATH = resolve(
  ROOT,
  'docs/staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.metadata.json',
);
const RULES_RELEASE_NAME = `projects/${PROJECT_ID}/releases/cloud.firestore`;
const TEMP_ROLE_BINDINGS = [
  {
    role: PUBLISHER_ROLE,
    member: `serviceAccount:${PUBLISHER_EMAIL}`,
    permissions: [
      'firebaserules.rulesets.create',
      'firebaserules.rulesets.get',
      'firebaserules.releases.create',
      'firebaserules.releases.get',
      'firebaserules.releases.update',
    ],
  },
  {
    role: FIXTURE_ROLE,
    member: `serviceAccount:${FIXTURE_OPERATOR_EMAIL}`,
    permissions: [
      'firebaseauth.users.create',
      'firebaseauth.users.get',
      'firebaseauth.users.update',
      'firebaseauth.users.delete',
      'datastore.databases.get',
      'datastore.entities.create',
      'datastore.entities.get',
      'datastore.entities.list',
      'datastore.entities.update',
      'datastore.entities.delete',
    ],
  },
];
const DENY_ALL_RULES = readFileSync(DENY_ALL_PATH);
const CANDIDATE_RULES = readFileSync(CANDIDATE_PATH);
const CANDIDATE_MIRROR = readFileSync(MIRROR_PATH);
const sha256 = (buffer) => createHash('sha256').update(buffer).digest('hex');

function requireEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`Disposable Rules homologation blocked: ${label} mismatch`);
}

function requireUnless(condition, label) {
  if (!condition) throw new Error(`Disposable Rules homologation blocked: ${label}`);
}

function validateLocalInputs() {
  requireUnless(PROJECT_ID && !PRODUCTION_IDS.has(PROJECT_ID), 'production project is prohibited');
  requireUnless(!EXISTING_STAGING_IDS.has(PROJECT_ID), 'existing staging project is prohibited');
  requireUnless(sha256(CANDIDATE_RULES) === EXPECTED_CANDIDATE_SHA256, 'approved Rules candidate hash');
  requireUnless(CANDIDATE_RULES.equals(CANDIDATE_MIRROR), 'approved Rules and tested mirror differ');
  requireUnless(sha256(DENY_ALL_RULES) === EXPECTED_DENY_ALL_SHA256, 'deny-all restoration template hash');
  const metadata = JSON.parse(readFileSync(DENY_ALL_METADATA_PATH, 'utf8'));
  requireUnless(metadata.projectId === 'macacu-staging-261022', 'deny-all template provenance is unexpected');
  requireUnless(metadata.sourceFile?.sha256 === EXPECTED_DENY_ALL_SHA256, 'deny-all template metadata hash');
  for (const key of [
    'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'GOOGLE_APPLICATION_CREDENTIALS',
    'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE', 'CLOUDSDK_AUTH_ACCESS_TOKEN',
    'FIREBASE_TOKEN', 'FIREBASE_CONFIG', 'FIRESTORE_EMULATOR_HOST',
    'FIREBASE_AUTH_EMULATOR_HOST', 'FIREBASE_DATABASE_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST', 'FIREBASE_FUNCTIONS_EMULATOR_HOST',
    'FIREBASE_APPCHECK_DEBUG_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY',
    'http_proxy', 'https_proxy', 'all_proxy', 'NODE_USE_ENV_PROXY',
    'NODE_TLS_REJECT_UNAUTHORIZED', 'NODE_EXTRA_CA_CERTS', 'SSL_CERT_FILE',
    'SSL_CERT_DIR', 'GRPC_DEFAULT_SSL_ROOTS_FILE_PATH', 'NODE_OPTIONS', 'NODE_PATH',
  ]) requireUnless(!process.env[key], `unexpected ${key} environment override`);
  requireUnless(Date.now() < Date.parse(IAM_GRANT_EXPIRES_AT), 'temporary IAM grants have expired');
  return {
    candidateSha256: sha256(CANDIDATE_RULES),
    denyAllSha256: sha256(DENY_ALL_RULES),
  };
}

async function apiRequest({ host, path, method = 'GET', token, body, allowedStatus = [200] }) {
  const url = new URL(`https://${host}${path}`);
  requireEqual(url.protocol, 'https:', 'API transport security');
  requireUnless(
    [
      'firebase.googleapis.com', 'cloudbilling.googleapis.com', 'firestore.googleapis.com',
      'firebaserules.googleapis.com', 'identitytoolkit.googleapis.com',
      'iam.googleapis.com', 'iamcredentials.googleapis.com', 'cloudresourcemanager.googleapis.com',
      'serviceusage.googleapis.com',
    ].includes(url.hostname),
    'API host allowlist',
  );
  const resolvedToken = typeof token === 'function' ? await token() : token;
  const response = await fetch(url, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(25000),
    headers: {
      authorization: `Bearer ${resolvedToken}`,
      accept: 'application/json',
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!allowedStatus.includes(response.status)) {
    throw new Error(`${method} ${host}${url.pathname} returned HTTP ${response.status}`);
  }
  if (response.status === 404 || response.status === 204) return null;
  return response.json();
}

function parsePermissionNames(result) {
  return result?.permissions ?? [];
}

async function checkProjectIamPermissions(publisherToken, fixtureToken) {
  const publisher = await apiRequest({
    host: 'cloudresourcemanager.googleapis.com',
    path: `/v3/projects/${PROJECT_ID}:testIamPermissions`,
    method: 'POST',
    token: publisherToken,
    body: { permissions: [
      'firebaserules.rulesets.create', 'firebaserules.rulesets.get',
      'firebaserules.releases.create', 'firebaserules.releases.get',
      'firebaserules.releases.update', 'firebaseauth.users.create',
      'datastore.entities.create', 'resourcemanager.projects.setIamPolicy',
      'iam.serviceAccountKeys.create',
    ] },
  });
  const fixture = await apiRequest({
    host: 'cloudresourcemanager.googleapis.com',
    path: `/v3/projects/${PROJECT_ID}:testIamPermissions`,
    method: 'POST',
    token: fixtureToken,
    body: { permissions: [
      'firebaserules.rulesets.create', 'firebaserules.rulesets.get',
      'firebaserules.releases.create', 'firebaserules.releases.update',
      'firebaseauth.users.create', 'firebaseauth.users.get',
      'firebaseauth.users.update', 'firebaseauth.users.delete',
      'datastore.databases.get', 'datastore.entities.create',
      'datastore.entities.get', 'datastore.entities.list',
      'datastore.entities.update', 'datastore.entities.delete',
      'resourcemanager.projects.setIamPolicy', 'iam.serviceAccountKeys.create',
    ] },
  });
  const publisherAllowed = parsePermissionNames(publisher);
  const fixtureAllowed = parsePermissionNames(fixture);
  const expectedPublisherAllowed = TEMP_ROLE_BINDINGS[0].permissions;
  const expectedFixtureAllowed = TEMP_ROLE_BINDINGS[1].permissions;
  for (const permission of expectedPublisherAllowed) {
    requireUnless(publisherAllowed.includes(permission), `publisher missing ${permission}`);
  }
  for (const permission of expectedFixtureAllowed) {
    requireUnless(fixtureAllowed.includes(permission), `fixture operator missing ${permission}`);
  }
  for (const permission of [
    'firebaseauth.users.create', 'datastore.entities.create',
    'resourcemanager.projects.setIamPolicy', 'iam.serviceAccountKeys.create',
  ]) requireUnless(!publisherAllowed.includes(permission), `publisher has excessive ${permission}`);
  for (const permission of [
    'firebaserules.rulesets.create', 'firebaserules.releases.update',
    'resourcemanager.projects.setIamPolicy', 'iam.serviceAccountKeys.create',
  ]) requireUnless(!fixtureAllowed.includes(permission), `fixture operator has excessive ${permission}`);
  return { publisherAllowed, fixtureAllowed };
}

let sourceAccessToken;
let sourcePrincipal;
let cachedAccessTokens = new Map();

async function getImpersonatedAccessToken(serviceAccountEmail) {
  requireUnless(Date.now() < Date.parse(IAM_GRANT_EXPIRES_AT), 'temporary IAM grants have expired');
  const cached = cachedAccessTokens.get(serviceAccountEmail);
  if (cached && cached.expiresAt - Date.now() > 60000) return cached.token;
  const tokenResponse = await apiRequest({
    host: 'iamcredentials.googleapis.com',
    path: `/v1/projects/-/serviceAccounts/${serviceAccountEmail}:generateAccessToken`,
    method: 'POST',
    token: sourceAccessToken,
    body: { scope: ['https://www.googleapis.com/auth/cloud-platform'], lifetime: '600s' },
  });
  requireUnless(typeof tokenResponse.accessToken === 'string' && tokenResponse.accessToken.length > 100,
    `could not impersonate ${serviceAccountEmail}`);
  const expiresAt = Date.parse(tokenResponse.expireTime);
  requireUnless(Number.isFinite(expiresAt) && expiresAt > Date.now(), 'impersonated token expiry is invalid');
  cachedAccessTokens.set(serviceAccountEmail, { token: tokenResponse.accessToken, expiresAt });
  return tokenResponse.accessToken;
}

function impersonatedCredential(serviceAccountEmail) {
  return {
    async getAccessToken() {
      const token = await getImpersonatedAccessToken(serviceAccountEmail);
      const expiresAt = cachedAccessTokens.get(serviceAccountEmail).expiresAt;
      return { access_token: token, expires_in: Math.max(1, Math.floor((expiresAt - Date.now()) / 1000)) };
    },
  };
}

async function verifyTemporaryIamSetup(ownerToken) {
  requireUnless(Date.now() < Date.parse(IAM_GRANT_EXPIRES_AT), 'temporary IAM grants have expired');
  const project = await apiRequest({
    host: 'firebase.googleapis.com', path: `/v1beta1/projects/${PROJECT_ID}`, token: ownerToken,
  });
  requireEqual(project.projectId, PROJECT_ID, 'Firebase project ID');
  requireEqual(project.projectNumber, PROJECT_NUMBER, 'Firebase project number');
  const iamProjectPolicy = await apiRequest({
    host: 'cloudresourcemanager.googleapis.com',
    path: `/v3/projects/${PROJECT_NUMBER}:getIamPolicy`, method: 'POST', token: ownerToken,
    body: { options: { requestedPolicyVersion: 3 } },
  });
  for (const roleBinding of TEMP_ROLE_BINDINGS) {
    const binding = iamProjectPolicy.bindings?.find((item) =>
      item.role === roleBinding.role && item.members?.includes(roleBinding.member) &&
      item.condition?.expression === `request.time < timestamp('${IAM_GRANT_EXPIRES_AT}')`);
    requireUnless(binding, `temporary custom-role binding missing for ${roleBinding.role}`);
    const role = await apiRequest({
      host: 'iam.googleapis.com', path: `/v1/${roleBinding.role}`, token: ownerToken,
    });
    requireUnless(role.deleted !== true, `temporary custom role ${roleBinding.role} is deleted`);
    assert.deepEqual([...role.includedPermissions].sort(), [...roleBinding.permissions].sort());
  }
  const serviceAccounts = [PUBLISHER_EMAIL, FIXTURE_OPERATOR_EMAIL];
  for (const serviceAccountEmail of serviceAccounts) {
    const account = await apiRequest({
      host: 'iam.googleapis.com', path: `/v1/projects/${PROJECT_ID}/serviceAccounts/${serviceAccountEmail}`,
      token: ownerToken,
    });
    requireEqual(account.email, serviceAccountEmail, 'temporary service identity');
    requireUnless(account.disabled !== true, 'temporary service identity is disabled');
    const keys = await apiRequest({
      host: 'iam.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/serviceAccounts/${serviceAccountEmail}/keys?keyTypes=USER_MANAGED`,
      token: ownerToken,
    });
    requireEqual(keys.keys?.length ?? 0, 0, 'service-account user-managed key count');
    const policy = await apiRequest({
      host: 'iam.googleapis.com',
      path: `/v1/projects/${PROJECT_ID}/serviceAccounts/${serviceAccountEmail}:getIamPolicy`,
      method: 'POST', token: ownerToken, body: { options: { requestedPolicyVersion: 3 } },
    });
    const tokenBinding = policy.bindings?.find((item) =>
      item.role === 'roles/iam.serviceAccountTokenCreator' &&
      item.members?.includes(`user:${sourcePrincipal}`) &&
      item.condition?.expression === `request.time < timestamp('${IAM_GRANT_EXPIRES_AT}')`);
    requireUnless(tokenBinding, 'short-lived keyless impersonation binding missing');
  }
  const [publisherToken, fixtureToken] = await Promise.all([
    getImpersonatedAccessToken(PUBLISHER_EMAIL), getImpersonatedAccessToken(FIXTURE_OPERATOR_EMAIL),
  ]);
  return { project, publisherToken, fixtureToken };
}

async function readRelease(token) {
  return apiRequest({
    host: 'firebaserules.googleapis.com',
    path: `/v1/${RULES_RELEASE_NAME}`, token, allowedStatus: [200, 404],
  });
}

async function readRuleset(token, rulesetName) {
  return apiRequest({
    host: 'firebaserules.googleapis.com', path: `/v1/${rulesetName}`, token,
  });
}

async function assertReleaseUnchanged(token, expected, label) {
  const actual = await readRelease(token);
  requireEqual(actual?.rulesetName ?? null, expected?.rulesetName ?? null, `${label} active Ruleset`);
  requireEqual(actual?.updateTime ?? null, expected?.updateTime ?? null, `${label} Release updateTime`);
  return actual;
}

async function createRuleset(token, sourceBytes) {
  const result = await apiRequest({
    host: 'firebaserules.googleapis.com', path: `/v1/projects/${PROJECT_ID}/rulesets`,
    method: 'POST', token,
    body: { source: { files: [{ name: 'firestore.rules', content: sourceBytes.toString('utf8') }] } },
  });
  requireUnless(typeof result.name === 'string' && result.name.startsWith(`projects/${PROJECT_ID}/rulesets/`),
    'created Ruleset resource identity');
  return { name: result.name, sourceSha256: sha256(Buffer.from(result.source?.files?.[0]?.content ?? sourceBytes.toString('utf8'))) };
}

async function assertRulesetHash(token, rulesetName, expectedHash) {
  const ruleset = await readRuleset(token, rulesetName);
  const files = ruleset.source?.files ?? [];
  requireEqual(files.length, 1, 'Ruleset source count');
  requireEqual(files[0].name, 'firestore.rules', 'Ruleset filename');
  const observedHash = sha256(Buffer.from(files[0].content, 'utf8'));
  requireEqual(observedHash, expectedHash, 'Ruleset source hash');
  return observedHash;
}

async function assertProjectPreflight(ownerToken, fixtureToken) {
  const [billing, databases, services, authConfig, webConfig, authQuery] = await Promise.all([
    apiRequest({ host: 'cloudbilling.googleapis.com', path: `/v1/projects/${PROJECT_ID}/billingInfo`, token: ownerToken }),
    apiRequest({ host: 'firestore.googleapis.com', path: `/v1/projects/${PROJECT_ID}/databases`, token: ownerToken }),
    Promise.all(['firebaserules.googleapis.com', 'identitytoolkit.googleapis.com', 'firestore.googleapis.com']
      .map((service) => apiRequest({
        host: 'serviceusage.googleapis.com', path: `/v1/projects/${PROJECT_NUMBER}/services/${service}`, token: ownerToken,
      }))),
    apiRequest({ host: 'identitytoolkit.googleapis.com', path: `/admin/v2/projects/${PROJECT_ID}/config`, token: ownerToken }),
    apiRequest({ host: 'firebase.googleapis.com', path: `/v1beta1/projects/${PROJECT_ID}/webApps/${WEB_APP_ID}/config`, token: ownerToken }),
    apiRequest({ host: 'identitytoolkit.googleapis.com', path: `/v1/projects/${PROJECT_ID}/accounts:query`, method: 'POST', token: fixtureToken, body: { limit: '1' } }),
  ]);
  requireEqual(billing.billingEnabled, false, 'billing must remain disabled');
  requireEqual(databases.databases?.length, 1, 'only the dedicated database may exist');
  requireEqual(databases.databases[0].name, `projects/${PROJECT_ID}/databases/(default)`, 'default database ID');
  requireEqual(databases.databases[0].deleteProtectionState, 'DELETE_PROTECTION_ENABLED', 'database delete protection');
  requireUnless(services.every((service) => service.state === 'ENABLED'), 'required APIs must be enabled');
  requireEqual(authConfig.signIn?.email?.enabled, true, 'email/password provider');
  requireUnless(authConfig.signIn?.anonymous?.enabled !== true, 'anonymous Auth must remain disabled');
  requireUnless(authConfig.signIn?.phoneNumber?.enabled !== true, 'phone Auth must remain disabled');
  requireUnless(authConfig.signIn?.google?.enabled !== true, 'Google Auth must remain disabled');
  requireUnless(typeof webConfig.apiKey === 'string' && webConfig.apiKey.length > 20, 'web app SDK configuration');
  requireEqual(Number(authQuery.recordsCount ?? 0), 0, 'new project Auth user count');
  return { apiKey: webConfig.apiKey, appId: WEB_APP_ID, authProvider: 'email/password', authUsersBeforeTest: 0 };
}

function syntheticIdentity(role, runId) {
  return {
    email: `rules-hml-${role}+${runId}@example.invalid`,
    password: randomBytes(32).toString('base64url'),
    displayName: `Synthetic ${role}`,
  };
}

function toFirestoreValue(value) {
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number' && Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === 'number') return { doubleValue: value };
  if (value === null) return { nullValue: null };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(toFirestoreValue) } };
  if (value && typeof value === 'object') {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, toFirestoreValue(item)])) } };
  }
  throw new Error('Unsupported synthetic Firestore fixture value');
}

function fromFirestoreValue(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return new Date(value.timestampValue);
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values ?? []).map(fromFirestoreValue);
  if ('mapValue' in value) return fromFirestoreFields(value.mapValue.fields ?? {});
  return undefined;
}

function fromFirestoreFields(fields = {}) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, fromFirestoreValue(value)]));
}

function firestoreDocumentPath(path) {
  return path.split('/').map(encodeURIComponent).join('/');
}

function firestoreDocumentUrl(path) {
  return `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${firestoreDocumentPath(path)}`;
}

async function firestoreServerGet(path, fixtureToken) {
  const document = await apiRequest({
    host: 'firestore.googleapis.com', path: firestoreDocumentUrl(path), token: fixtureToken,
    allowedStatus: [200, 404],
  });
  return document ? fromFirestoreFields(document.fields ?? {}) : null;
}

async function firestoreServerCreate(path, fixture, fixtureToken) {
  if (await firestoreServerGet(path, fixtureToken)) {
    throw new Error(`Synthetic Firestore path already exists; refusing to overwrite: ${path}`);
  }
  const segments = path.split('/');
  const documentId = segments.pop();
  requireUnless(segments.length >= 1 && segments.length % 2 === 1, 'Firestore fixture path shape');
  const collectionPath = segments.map(encodeURIComponent).join('/');
  const created = await apiRequest({
    host: 'firestore.googleapis.com',
    path: `/v1/projects/${PROJECT_ID}/databases/(default)/documents/${collectionPath}?documentId=${encodeURIComponent(documentId)}`,
    method: 'POST', token: fixtureToken,
    body: { fields: Object.fromEntries(Object.entries(fixture).map(([key, value]) => [key, toFirestoreValue(value)])) },
    allowedStatus: [200, 201],
  });
  const returnedId = created.name?.split('/').pop();
  requireUnless(
    created.name?.startsWith(`projects/${PROJECT_ID}/databases/(default)/documents/`) &&
      typeof returnedId === 'string' && decodeURIComponent(returnedId) === documentId,
    'created fixture document identity',
  );
}

async function firestoreServerUpdateField(path, field, value, runId, fixtureToken) {
  const current = await firestoreServerGet(path, fixtureToken);
  requireEqual(current?.stagingRunId, runId, 'synthetic authorization ownership before update');
  const query = new URLSearchParams();
  query.append('updateMask.fieldPaths', field);
  await apiRequest({
    host: 'firestore.googleapis.com',
    path: `${firestoreDocumentUrl(path)}?${query.toString()}`,
    method: 'PATCH', token: fixtureToken,
    body: { fields: { [field]: toFirestoreValue(value) } },
  });
}

async function firestoreServerDelete(path, runId, expectedFingerprint, fixtureToken) {
  const current = await firestoreServerGet(path, fixtureToken);
  if (!current) return;
  if (!isUnchangedOwnedFixture(runId, current, expectedFingerprint)) {
    throw new Error(`Refusing to delete a synthetic Firestore document changed after creation: ${path}`);
  }
  await apiRequest({
    host: 'firestore.googleapis.com', path: firestoreDocumentUrl(path),
    method: 'DELETE', token: fixtureToken, allowedStatus: [200, 204],
  });
}

function eventData(runId, { published = true, active = true, deleted = false, deletedAt = false } = {}) {
  return {
    title: `Synthetic event ${runId}`,
    name: `Synthetic event ${runId}`,
    description: 'Fixture fictícia criada exclusivamente para teste das Rules.',
    category: 'homologation-fixture',
    published,
    active,
    deleted,
    featured: false,
    synthetic: true,
    stagingRunId: runId,
    ...(deletedAt ? { deletedAt: new Date() } : {}),
  };
}

function expectDenied(error, label) {
  assert.ok(error, `${label}: expected permission denial`);
  assert.match(String(error.code ?? error.message), /permission-denied|PERMISSION_DENIED/i, label);
}

async function publishRelease(token, rulesetName, existingRelease) {
  const current = await readRelease(token);
  requireEqual(current?.rulesetName ?? null, existingRelease?.rulesetName ?? null, 'Release pre-mutation Ruleset');
  requireEqual(current?.updateTime ?? null, existingRelease?.updateTime ?? null, 'Release pre-mutation updateTime');
  const release = {
    name: RULES_RELEASE_NAME,
    rulesetName,
  };
  if (current) {
    await apiRequest({
      host: 'firebaserules.googleapis.com', path: `/v1/${RULES_RELEASE_NAME}`,
      method: 'PATCH', token,
      body: { release },
    });
  } else {
    await apiRequest({
      host: 'firebaserules.googleapis.com', path: `/v1/projects/${PROJECT_ID}/releases`,
      method: 'POST', token,
      body: { name: RULES_RELEASE_NAME, rulesetName },
    });
  }
  const actual = await readRelease(token);
  requireEqual(actual?.rulesetName, rulesetName, 'Release post-mutation Ruleset');
  requireUnless(typeof actual?.updateTime === 'string', 'Release updateTime after mutation');
  return actual;
}

async function verifyAdminSdkAndClientRules({ apiKey, publisherToken, fixtureCredential, fixtureToken }) {
  const adminAppSdk = require('firebase-admin/app');
  const adminAuthSdk = require('firebase-admin/auth');
  const clientAppSdk = require('firebase/app');
  const clientAuthSdk = require('firebase/auth');
  const clientFirestoreSdk = require('firebase/firestore');
  const runId = randomUUID();
  const adminApp = adminAppSdk.initializeApp({ projectId: PROJECT_ID, credential: fixtureCredential }, `rules-hml-admin-${runId}`);
  const serverAuth = adminAuthSdk.getAuth(adminApp);
  const createdUsers = new Map();
  const createdPaths = new Map();
  const clientApps = [];
  const clients = {};
  const results = [];
  let candidateRelease;
  let candidateRulesetName;
  let denyAllRuleset;
  let denyAllRelease;
  let candidatePublished = false;
  let cleanupErrors = [];
  let testError = null;

  const record = (name) => { results.push(name); process.stdout.write(`PASS ${name}\n`); };
  async function expectClientDenied(operation, name) {
    try { await operation(); } catch (error) { expectDenied(error, name); record(name); return; }
    throw new Error(`${name}: client operation was unexpectedly allowed`);
  }
  async function makeClient(role, adminVersion) {
    const identity = syntheticIdentity(role, runId);
    const user = await serverAuth.createUser({
      email: identity.email, password: identity.password, displayName: identity.displayName, disabled: false,
    });
    const expectedUser = {
      uid: user.uid, email: identity.email, displayName: identity.displayName, emailVerified: false,
      disabled: false, customClaims: adminVersion ? { admin: true, adminVersion } : {},
    };
    createdUsers.set(user.uid, expectedUser);
    if (adminVersion) {
      await serverAuth.setCustomUserClaims(user.uid, { admin: true, adminVersion });
      const path = `admin_authorizations/${user.uid}`;
      const fixture = { enabled: true, pending: false, version: adminVersion, stagingRunId: runId };
      await firestoreServerCreate(path, fixture, fixtureToken);
      createdPaths.set(path, fingerprintFixture(fixture));
    }
    const app = clientAppSdk.initializeApp({
      apiKey, appId: WEB_APP_ID, authDomain: `${PROJECT_ID}.firebaseapp.com`, projectId: PROJECT_ID,
    }, `rules-hml-client-${role}-${runId}`);
    clientApps.push(app);
    const auth = clientAuthSdk.initializeAuth(app, { persistence: clientAuthSdk.inMemoryPersistence });
    const signedIn = await clientAuthSdk.signInWithEmailAndPassword(auth, identity.email, identity.password);
    if (adminVersion) await clientAuthSdk.getIdToken(signedIn.user, true);
    clients[role] = {
      app, auth, db: clientFirestoreSdk.getFirestore(app), user: signedIn.user,
    };
    return user.uid;
  }
  async function seed(path, fixture) {
    await firestoreServerCreate(path, fixture, fixtureToken);
    createdPaths.set(path, fingerprintFixture(fixture));
  }

  try {
    const before = await readRelease(publisherToken);
    requireEqual(before, null, 'new-project Release before baseline creation');
    const denyAllRulesetInfo = await createRuleset(publisherToken, DENY_ALL_RULES);
    requireEqual(denyAllRulesetInfo.sourceSha256, EXPECTED_DENY_ALL_SHA256, 'deny-all Ruleset creation hash');
    denyAllRuleset = denyAllRulesetInfo.name;
    await assertReleaseUnchanged(publisherToken, before, 'Release after deny-all Ruleset creation');
    denyAllRelease = await publishRelease(publisherToken, denyAllRuleset, before);
    await assertRulesetHash(publisherToken, denyAllRuleset, EXPECTED_DENY_ALL_SHA256);
    record('dedicated project begins with explicit deny-all Rules');

    const beforeCandidate = await readRelease(publisherToken);
    requireEqual(beforeCandidate?.rulesetName, denyAllRuleset, 'deny-all baseline before candidate publication');
    requireEqual(beforeCandidate?.updateTime, denyAllRelease.updateTime, 'deny-all baseline updateTime');
    const candidateRuleset = await createRuleset(publisherToken, CANDIDATE_RULES);
    requireEqual(candidateRuleset.sourceSha256, EXPECTED_CANDIDATE_SHA256, 'candidate Ruleset creation hash');
    candidateRulesetName = candidateRuleset.name;
    await assertReleaseUnchanged(publisherToken, beforeCandidate, 'Release after candidate Ruleset creation');
    candidateRelease = await publishRelease(publisherToken, candidateRuleset.name, beforeCandidate);
    candidatePublished = true;
    await assertRulesetHash(publisherToken, candidateRuleset.name, EXPECTED_CANDIDATE_SHA256);
    record('approved candidate Rules published only to the isolated project');

    const adminVersion = `homologation-${runId}`;
    const adminUid = await makeClient('admin', adminVersion);
    const commonUid = await makeClient('common', null);
    const otherCommonUid = await makeClient('other-common', null);
    const revokedVersion = `revoked-${runId}`;
    const revokedUid = await makeClient('revoked-admin', revokedVersion);
    const revokedAuthPath = `admin_authorizations/${revokedUid}`;
    await firestoreServerUpdateField(revokedAuthPath, 'enabled', false, runId, fixtureToken);
    createdPaths.set(revokedAuthPath, fingerprintFixture({
      enabled: false, pending: false, version: revokedVersion, stagingRunId: runId,
    }));
    record('four synthetic Auth accounts and a revoked-admin state created');

    const fixtures = {
      published: `events/${runId}-published`,
      legacyPublished: `events/${runId}-legacy-published`,
      draft: `events/${runId}-draft`,
      inactive: `events/${runId}-inactive`,
      deleted: `events/${runId}-deleted`,
      deletedAt: `events/${runId}-deleted-at`,
      homeDraft: `home_pages/${runId}-draft`,
      agenda: `users/${commonUid}/favorites/event::${runId}-published`,
      businessFavorite: `users/${commonUid}/favorites/business::${runId}-business`,
    };
    const eventFixtures = [
      [fixtures.published, eventData(runId)],
      [fixtures.legacyPublished, { ...eventData(runId), deleted: undefined }],
      [fixtures.draft, eventData(runId, { published: false })],
      [fixtures.inactive, eventData(runId, { active: false })],
      [fixtures.deleted, eventData(runId, { deleted: true })],
      [fixtures.deletedAt, eventData(runId, { deletedAt: true })],
    ];
    for (const [path, fixture] of eventFixtures) {
      if (fixture.deleted === undefined) delete fixture.deleted;
      await seed(path, fixture);
    }
    const homeDraft = { title: `Private draft ${runId}`, stagingRunId: runId, published: false };
    await seed(fixtures.homeDraft, homeDraft);
    const agenda = { type: 'event', targetId: `${runId}-published`, name: `Synthetic event ${runId}`, stagingRunId: runId };
    const businessFavorite = { type: 'business', targetId: `${runId}-business`, name: `Synthetic business ${runId}`, stagingRunId: runId };
    await seed(fixtures.agenda, agenda);
    await seed(fixtures.businessFavorite, businessFavorite);
    record('synthetic Events, one private Home draft, Favorites and Agenda fixtures seeded by server identity');

    const adminNewEventPath = `events/${runId}-admin-created`;
    const adminNewEvent = eventData(runId, { published: false });
    const adminNewEventRef = clientFirestoreSdk.doc(clients.admin.db, adminNewEventPath);
    await clientFirestoreSdk.runTransaction(clients.admin.db, async (transaction) => {
      const existing = await transaction.get(adminNewEventRef);
      if (existing.exists()) throw new Error('Refusing to overwrite an existing path');
      transaction.set(adminNewEventRef, adminNewEvent);
    });
    createdPaths.set(adminNewEventPath, fingerprintFixture(adminNewEvent));
    record('authorized Admin client creates a draft event');
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.admin.db, fixtures.draft))).exists(), true);
    record('authorized Admin client reads a draft event');
    await clientFirestoreSdk.updateDoc(clientFirestoreSdk.doc(clients.admin.db, adminNewEventPath), { published: true });
    const adminPublished = { ...adminNewEvent, published: true };
    createdPaths.set(adminNewEventPath, fingerprintFixture(adminPublished));
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.common.db, adminNewEventPath))).exists(), true);
    record('authorized Admin publishes and ordinary user reads the event');

    for (const path of [fixtures.published, fixtures.legacyPublished]) {
      assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.common.db, path))).exists(), true);
    }
    record('ordinary user can read active published events, including legacy deleted-field semantics');
    for (const [key, label] of [
      ['draft', 'ordinary user cannot read draft Events'],
      ['inactive', 'ordinary user cannot read inactive Events'],
      ['deleted', 'ordinary user cannot read deleted true tombstones'],
      ['deletedAt', 'ordinary user cannot read deletedAt tombstones'],
      ['homeDraft', 'ordinary user cannot read private Home drafts'],
    ]) {
      await expectClientDenied(
        () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.common.db, fixtures[key])), label,
      );
    }
    await expectClientDenied(
      () => clientFirestoreSdk.setDoc(clientFirestoreSdk.doc(clients.common.db, fixtures.published), eventData(runId)),
      'ordinary user cannot overwrite a public Event',
    );
    await expectClientDenied(
      () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.common.db, `admin_authorizations/${adminUid}`)),
      'ordinary user cannot read Admin authorization state',
    );
    await expectClientDenied(
      () => clientFirestoreSdk.getDocs(clientFirestoreSdk.collection(clients.common.db, 'events')),
      'ordinary user cannot bypass public list policy for Events',
    );
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.common.db, fixtures.agenda))).exists(), true);
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.common.db, fixtures.businessFavorite))).exists(), true);
    record('owner can read personal Favorite and Agenda documents');
    for (const path of [fixtures.agenda, fixtures.businessFavorite]) {
      await expectClientDenied(
        () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients['other-common'].db, path)),
        `another account cannot read personal record ${path.endsWith('agenda') ? 'Agenda' : 'Favorite'}`,
      );
      await expectClientDenied(
        () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.admin.db, path)),
        `Admin cannot read another account personal record ${path.endsWith('agenda') ? 'Agenda' : 'Favorite'}`,
      );
    }
    await expectClientDenied(
      () => clientFirestoreSdk.setDoc(clientFirestoreSdk.doc(clients.common.db, fixtures.agenda), {
        type: 'event', targetId: 'forged', stagingRunId: runId,
      }),
      'client cannot write Favorite or Agenda records directly',
    );
    await expectClientDenied(
      () => clientFirestoreSdk.updateDoc(clientFirestoreSdk.doc(clients['revoked-admin'].db, fixtures.draft), {
        published: true,
      }),
      'revoked Admin cannot publish an Event',
    );
    await expectClientDenied(
      () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients['revoked-admin'].db, fixtures.draft)),
      'revoked Admin cannot read draft Events',
    );
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.admin.db, fixtures.homeDraft))).exists(), true);
    record('active Admin can read private Home drafts');
    const anonymousApp = clientAppSdk.initializeApp({
      apiKey, appId: WEB_APP_ID, authDomain: `${PROJECT_ID}.firebaseapp.com`, projectId: PROJECT_ID,
    }, `rules-hml-client-visitor-${runId}`);
    clientApps.push(anonymousApp);
    const anonymousDb = clientFirestoreSdk.getFirestore(anonymousApp);
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(anonymousDb, fixtures.published))).exists(), true);
    record('unauthenticated visitor can read public published Events');

    const latest = await readRelease(publisherToken);
    requireEqual(latest?.rulesetName, candidateRelease.rulesetName, 'candidate Release while checks run');
    requireEqual(latest?.updateTime, candidateRelease.updateTime, 'candidate Release timestamp while checks run');
  } catch (error) {
    testError = error;
  } finally {
    await Promise.all(clientApps.map((app) => clientAppSdk.deleteApp(app).catch(() => undefined)));
    for (const [path, expectedFingerprint] of createdPaths) {
      try {
        const current = await firestoreServerGet(path, fixtureToken);
        if (!current) continue;
        if (!isUnchangedOwnedFixture(runId, current, expectedFingerprint)) {
          cleanupErrors.push(`changed Firestore fixture preserved: ${path}`);
          continue;
        }
        await firestoreServerDelete(path, runId, expectedFingerprint, fixtureToken);
      } catch {
        cleanupErrors.push(`Firestore fixture cleanup failed: ${path}`);
      }
    }
    for (const [uid, expectedUser] of createdUsers) {
      try {
        const current = await serverAuth.getUser(uid);
        if (!isUnchangedSyntheticUser(current, expectedUser)) {
          cleanupErrors.push(`changed synthetic Auth account preserved: ${uid}`);
          continue;
        }
        await serverAuth.deleteUser(uid);
      } catch (error) {
        if (error?.code !== 'auth/user-not-found') cleanupErrors.push(`synthetic Auth account cleanup failed: ${uid}`);
      }
    }
    await adminAppSdk.deleteApp(adminApp).catch(() => cleanupErrors.push('Admin SDK app disposal failed'));
    if (candidatePublished) {
      try {
        const current = await readRelease(publisherToken);
        if (current?.rulesetName !== candidateRelease?.rulesetName || current?.updateTime !== candidateRelease?.updateTime) {
          cleanupErrors.push('Release changed concurrently; deny-all restoration skipped to protect third-party changes');
        } else {
          const restoring = await createRuleset(publisherToken, DENY_ALL_RULES);
          requireEqual(restoring.sourceSha256, EXPECTED_DENY_ALL_SHA256, 'deny-all restoration Ruleset hash');
          await assertReleaseUnchanged(publisherToken, current, 'Release after restoration Ruleset creation');
          await publishRelease(publisherToken, restoring.name, current);
          await assertRulesetHash(publisherToken, restoring.name, EXPECTED_DENY_ALL_SHA256);
          const finalRelease = await readRelease(publisherToken);
          requireEqual(finalRelease.rulesetName, restoring.name, 'final deny-all Release Ruleset');
          record('candidate Rules replaced by verified deny-all Rules');
        }
      } catch (error) {
        cleanupErrors.push(`deny-all restoration failed: ${error.message}`);
      }
    }
    if (denyAllRuleset && !candidatePublished) {
      // The explicit deny-all baseline is already active when candidate deployment failed.
      const finalRelease = await readRelease(publisherToken).catch(() => null);
      if (finalRelease?.rulesetName === candidateRulesetName) {
        cleanupErrors.push('candidate Release may have changed during publication; deny-all restoration skipped without an observed updateTime');
      } else if (finalRelease?.rulesetName !== denyAllRuleset) {
        cleanupErrors.push('deny-all baseline no longer active; no concurrent Release overwrite attempted');
      }
    }
    cachedAccessTokens = new Map();
    if (cleanupErrors.length) {
      process.stderr.write(`CLEANUP_WARNING ${JSON.stringify(cleanupErrors)}\n`);
    }
  }
  return {
    runId,
    passed: results.length,
    results,
    createdPaths: createdPaths.size,
    createdUsers: createdUsers.size,
    cleanupErrors,
    testError: testError?.message ?? null,
  };
}

async function run() {
  const local = validateLocalInputs();
  const session = await getFirebaseCliReadOnlySession();
  sourceAccessToken = session.accessToken;
  sourcePrincipal = session.principalEmail;
  await verifyTemporaryIamSetup(sourceAccessToken);
  const publisherCredential = impersonatedCredential(PUBLISHER_EMAIL);
  const fixtureCredential = impersonatedCredential(FIXTURE_OPERATOR_EMAIL);
  const publisherTokenProvider = () => getImpersonatedAccessToken(PUBLISHER_EMAIL);
  const fixtureTokenProvider = () => getImpersonatedAccessToken(FIXTURE_OPERATOR_EMAIL);
  const iam = await checkProjectIamPermissions(publisherTokenProvider, fixtureTokenProvider);
  const publisherRead = await readRelease(publisherTokenProvider);
  requireEqual(publisherRead, null, 'project must not already have a Firestore Release');
  const projectConfig = await assertProjectPreflight(sourceAccessToken, fixtureTokenProvider);
  const before = await readRelease(publisherTokenProvider);
  requireEqual(before, null, 'Release before deny-all baseline');
  process.stdout.write(JSON.stringify({
    preflight: 'passed', projectId: PROJECT_ID, projectNumber: PROJECT_NUMBER,
    billingEnabled: false, database: '(default)', auth: 'email/password only',
    denyAllSha256: local.denyAllSha256, candidateSha256: local.candidateSha256,
    temporaryIdentities: [PUBLISHER_EMAIL, FIXTURE_OPERATOR_EMAIL],
    keylessImpersonation: true, iamBoundariesVerified: true,
  }) + '\n');
  // A short warm-up verifies each access token without logging token contents.
  await publisherCredential.getAccessToken();
  await fixtureCredential.getAccessToken();
  // The runner uses the dedicated publisher token for Rules and fixture token for Admin setup/cleanup.
  const result = await verifyAdminSdkAndClientRules({
    apiKey: projectConfig.apiKey,
    publisherToken: publisherTokenProvider,
    fixtureCredential,
    fixtureToken: fixtureTokenProvider,
    // Assert role separation once more immediately before any Rules publication.
    iam,
  });
  process.stdout.write(JSON.stringify({
    outcome: result.testError || result.cleanupErrors.length ? 'INCOMPLETE' : 'PASS',
    projectId: PROJECT_ID,
    runId: result.runId,
    clientSdkAssertions: result.passed,
    syntheticAuthAccountsCreated: result.createdUsers,
    syntheticFirestoreDocumentsCreated: result.createdPaths,
    testError: result.testError,
    cleanup: result.cleanupErrors.length ? result.cleanupErrors : 'all synthetic resources removed',
    finalRulesState: result.cleanupErrors.some((item) => item.includes('deny-all restoration'))
      ? 'unknown; inspect exact Release before any further action'
      : 'deny-all verified',
  }) + '\n');
  if (result.testError || result.cleanupErrors.length) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run().catch((error) => {
    process.stderr.write(`DISPOSABLE_RULES_HOMOLOGATION_FAILED ${error.message}\n`);
    process.exitCode = 1;
  });
}
