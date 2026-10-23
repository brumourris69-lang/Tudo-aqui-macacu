import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import admin from 'firebase-admin';
import { startLocalAdminEstablishmentsBridge, ADMIN_BRIDGE_PATH,
  assertLocalAdminBridgeEnvironment, DEMO_PROJECT_ID } from './local_admin_establishments_bridge.mjs';
import { changeAdminClaim } from '../admin_claim_management.js';
import { provisionSearchLocalAdmin, requireSearchLocalEnvironment } from '../local_demo_environment.js';

const env = process.env;
assertLocalAdminBridgeEnvironment(env);
requireSearchLocalEnvironment(env, DEMO_PROJECT_ID);
assert.equal(env.GCLOUD_PROJECT, DEMO_PROJECT_ID);

const defaultApp = admin.initializeApp({ projectId: DEMO_PROJECT_ID }, `bridge-auth-test-${process.pid}`);
const auth = admin.auth(defaultApp);
const db = admin.firestore(defaultApp);
const uidSuffix = randomUUID();
const adminEmail = `bridge-admin-${uidSuffix}@example.invalid`;
const ordinaryEmail = `bridge-user-${uidSuffix}@example.invalid`;
const password = `Local-${randomUUID()}-Aa1!`;
const ordinaryPassword = `Local-${randomUUID()}-Aa1!`;
const establishmentId = `bridge-auth-${uidSuffix}`;
const requestId = randomUUID();
let bridge;

async function signIn(email, passwordValue) {
  const response = await fetch(
    'http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-emulator-api-key',
    { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password: passwordValue, returnSecureToken: true }) },
  );
  if (!response.ok) throw new Error(`auth-emulator-sign-in-${response.status}`);
  const result = await response.json();
  if (typeof result.idToken !== 'string') throw new Error('auth-emulator-token-missing');
  return result.idToken;
}

async function call(token, operationId, entityId) {
  return fetch(`http://127.0.0.1:5077${ADMIN_BRIDGE_PATH}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ operation: 'create', requestId: operationId, entityId,
      data: { name: 'Estabelecimento fictício de integração', category: 'Comércio',
        description: 'Fixture descartável do Auth Emulator.', published: true,
        active: true, publicContactApproved: false } }),
  });
}

try {
  const provisioned = await provisionSearchLocalAdmin({ auth, db, env, email: adminEmail,
    password, confirmation: DEMO_PROJECT_ID });
  const ordinary = await auth.createUser({ email: ordinaryEmail, password: ordinaryPassword });
  bridge = await startLocalAdminEstablishmentsBridge({ env });

  const adminToken = await signIn(adminEmail, password);
  const accepted = await call(adminToken, requestId, establishmentId);
  assert.equal(accepted.status, 201);
  const result = await accepted.json();
  assert.equal(result.entityId, establishmentId);
  assert.equal(result.version, 1);
  const [source, event] = await Promise.all([
    db.collection('establishments').doc(establishmentId).get(),
    db.collection('catalog_outbox').doc(requestId).get(),
  ]);
  assert.equal(source.exists, true);
  assert.equal(source.data().catalogVersion, 1);
  assert.equal(source.data().outboxOperationId, requestId);
  assert.equal(event.exists, true);
  assert.equal(event.data().schemaVersion, 2);
  assert.equal(event.data().state, 'pending');
  assert.equal(JSON.stringify(event.data()).includes(adminEmail), false);
  assert.equal(JSON.stringify(event.data()).includes(password), false);

  const ordinaryToken = await signIn(ordinaryEmail, ordinaryPassword);
  const denied = await call(ordinaryToken, randomUUID(), `ordinary-${uidSuffix}`);
  assert.equal(denied.status, 403);
  assert.equal((await db.collection('establishments').doc(`ordinary-${uidSuffix}`).get()).exists, false);

  const invalid = await call('synthetic-invalid-token', randomUUID(), `invalid-${uidSuffix}`);
  assert.equal(invalid.status, 401);
  assert.equal((await db.collection('establishments').doc(`invalid-${uidSuffix}`).get()).exists, false);

  await changeAdminClaim({ auth, db, uid: provisioned.uid, action: 'revoke',
    operator: 'local-bridge-integration-test', reason: 'Synthetic emulator revocation',
    confirmation: `${DEMO_PROJECT_ID}:${provisioned.uid}:revoke`, apply: true, env });
  const revokedOldToken = await call(adminToken, randomUUID(), `revoked-old-${uidSuffix}`);
  assert.equal(revokedOldToken.status, 401);
  const revokedFreshToken = await signIn(adminEmail, password);
  const revokedFresh = await call(revokedFreshToken, randomUUID(), `revoked-fresh-${uidSuffix}`);
  assert.equal(revokedFresh.status, 403);
  assert.equal((await db.collection('establishments').doc(`revoked-fresh-${uidSuffix}`).get()).exists, false);

  process.stdout.write('Auth Emulator + real local bridge: PASS (Admin, ordinary, invalid, revoked token and atomic source/outbox).\n');
} catch (error) {
  const code = typeof error?.code === 'string' ? error.code : 'integration-failed';
  process.stderr.write(`Local bridge Auth Emulator integration failed: ${code}.\n`);
  process.exitCode = 1;
} finally {
  if (bridge) await bridge.close().catch(() => { process.exitCode = 1; });
  await defaultApp.delete().catch(() => { process.exitCode = 1; });
}
