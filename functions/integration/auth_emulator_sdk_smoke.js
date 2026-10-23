'use strict';

const assert = require('node:assert/strict');
const projectId = process.env.GCLOUD_PROJECT;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
assert.equal(projectId, 'demo-universal-search');
assert.equal(authHost, '127.0.0.1:19097');

const admin = require('firebase-admin');
admin.initializeApp({ projectId });
const { initializeApp, deleteApp } = require('firebase/app');
const { initializeAuth, inMemoryPersistence, connectAuthEmulator,
  createUserWithEmailAndPassword, signOut } = require('firebase/auth');

async function main() {
  const clientApp = initializeApp({ apiKey: 'demo-key', projectId, appId: 'demo-auth-smoke' }, 'auth-sdk-smoke');
  const auth = initializeAuth(clientApp, { persistence: inMemoryPersistence });
  connectAuthEmulator(auth, `http://${authHost}`, { disableWarnings: true });
  const suffix = require('node:crypto').randomUUID();
  try {
    const result = await createUserWithEmailAndPassword(auth,
      `auth-smoke-${suffix}@example.invalid`, `Local-${suffix}-Aa1!`);
    const token = await result.user.getIdToken(true);
    const decoded = await admin.auth().verifyIdToken(token);
    assert.equal(decoded.uid, result.user.uid);
    assert.equal(decoded.aud, projectId);
    assert.equal(decoded.firebase.sign_in_provider, 'password');
    console.log('Auth Emulator SDK token issuance and Admin SDK verification: PASS');
    await admin.auth().deleteUser(result.user.uid);
  } finally {
    await signOut(auth).catch(() => {});
    await deleteApp(clientApp);
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error(`Auth Emulator SDK smoke failed: ${error.code ?? error.name ?? 'error'}`);
  process.exitCode = 1;
});
