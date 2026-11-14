import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const projectId = 'demo-universal-search';
function requireLoopback(name) {
  const value = process.env[name] ?? '';
  assert.match(value, /^127\.0\.0\.1:\d{1,5}$/, `${name} must be loopback with an explicit port`);
  const port = Number(value.split(':')[1]);
  assert.ok(port >= 1 && port <= 65535, `${name} port is invalid`);
  return value;
}

const authEndpoint = requireLoopback('FIREBASE_AUTH_EMULATOR_HOST');
const firestoreEndpoint = requireLoopback('FIRESTORE_EMULATOR_HOST');
assert.equal(process.env.GCLOUD_PROJECT, projectId);
assert.equal(process.env.GOOGLE_CLOUD_PROJECT, projectId);
assert.equal(process.env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
assert.equal(process.env.FIREBASE_TOKEN, undefined);

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requireFromFunctions = createRequire(path.join(root, 'functions', 'package.json'));
const { initializeApp, deleteApp } = requireFromFunctions('firebase/app');
const {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  deleteUser,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} = requireFromFunctions('firebase/auth');
const {
  collection,
  connectFirestoreEmulator,
  deleteDoc,
  doc,
  getDocFromServer,
  getDocsFromServer,
  getFirestore,
  serverTimestamp,
  setDoc,
  updateDoc,
} = requireFromFunctions('firebase/firestore');

const suffix = randomUUID();
const apps = [];
let assertions = 0;

function pass(description) {
  assertions += 1;
  console.log(`PASS ${description}`);
}

async function denied(operation, description) {
  await assert.rejects(operation, (error) => {
    assert.equal(error.code, 'permission-denied', description);
    return true;
  });
  pass(description);
}

async function client(label, clientProjectId = projectId, authenticate = true) {
  const app = initializeApp({
    apiKey: 'demo-emulator-key',
    projectId: clientProjectId,
    appId: `demo-${label}`,
  }, `spark-favorites-${label}-${suffix}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${authEndpoint}`, { disableWarnings: true });
  const db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', Number(firestoreEndpoint.split(':')[1]));
  if (!authenticate) return { app, auth, db };
  const email = `${label}-${suffix}@example.invalid`;
  const password = 'LocalOnly123!';
  const credential = await createUserWithEmailAndPassword(auth, email, password);
  return { app, auth, db, email, password, user: credential.user };
}

async function main() {
  const owner = await client('owner');
  const other = await client('other');
  const guest = await client('guest', projectId, false);
  const favoriteId = `business::fixture-${suffix}`;
  const favoritePath = `users/${owner.user.uid}/favorites/${favoriteId}`;
  const favoriteRef = doc(owner.db, favoritePath);
  const profileRef = doc(owner.db, `users/${owner.user.uid}`);
  const data = {
    id: favoriteId,
    name: 'Comércio sintético',
    type: 'business',
    targetId: `fixture-${suffix}`,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  try {
    await denied(
      getDocFromServer(doc(guest.db, favoritePath)),
      'unauthenticated visitor cannot read a saved favorite',
    );
    await denied(
      setDoc(doc(guest.db, favoritePath), data),
      'unauthenticated visitor cannot create a favorite',
    );
    await denied(
      deleteDoc(doc(guest.db, favoritePath)),
      'unauthenticated visitor cannot remove a favorite',
    );

    await setDoc(favoriteRef, data);
    pass('authenticated user can add a valid favorite at their own UID path');
    assert.equal((await getDocFromServer(favoriteRef)).data().targetId, data.targetId);
    pass('owner can read the saved favorite from Firestore');
    assert.equal((await getDocsFromServer(collection(owner.db, `users/${owner.user.uid}/favorites`))).size, 1);
    pass('owner can list their own favorites');

    await denied(
      getDocFromServer(doc(other.db, favoritePath)),
      'another authenticated user cannot read the owner favorite',
    );
    await denied(
      getDocsFromServer(collection(other.db, `users/${owner.user.uid}/favorites`)),
      'another authenticated user cannot list the owner favorites',
    );
    await denied(
      setDoc(doc(other.db, `users/${owner.user.uid}/favorites/${favoriteId}`), data),
      'another authenticated user cannot overwrite the owner favorite',
    );
    await denied(
      deleteDoc(doc(other.db, favoritePath)),
      'another authenticated user cannot delete the owner favorite',
    );
    await denied(
      setDoc(doc(owner.db, `users/${other.user.uid}/favorites/${favoriteId}`), data),
      'owner cannot write under another account UID path',
    );

    await denied(
      setDoc(doc(owner.db, `users/${owner.user.uid}/favorites/forged-${suffix}`), {
        ...data,
        id: 'different-document-id',
      }),
      'Rules reject malformed favorite identity and document fields',
    );

    const before = (await getDocFromServer(favoriteRef)).data();
    await updateDoc(favoriteRef, {
      name: 'Comércio sintético atualizado',
      updatedAt: serverTimestamp(),
    });
    const after = (await getDocFromServer(favoriteRef)).data();
    assert.equal(after.name, 'Comércio sintético atualizado');
    assert.equal(after.createdAt.toMillis(), before.createdAt.toMillis());
    pass('owner can update a favorite without changing its identity or creation time');

    await signOut(owner.auth);
    await signInWithEmailAndPassword(owner.auth, owner.email, owner.password);
    assert.equal((await getDocFromServer(favoriteRef)).exists(), true);
    pass('favorite persists across sign-out and sign-in with the same account');

    await deleteDoc(favoriteRef);
    assert.equal((await getDocFromServer(favoriteRef)).exists(), false);
    pass('owner can remove their own favorite');

    // Exercise the postcondition relevant to account deletion: owner data is
    // removed before the client deletes its own Auth identity.
    await setDoc(profileRef, {
      displayName: 'Synthetic owner',
      email: owner.email,
      photoUrl: '',
      role: 'user',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(favoriteRef, data);
    await deleteDoc(favoriteRef);
    await deleteDoc(profileRef);
    await deleteUser(owner.auth.currentUser);
    assert.equal(owner.auth.currentUser, null);
    pass('authenticated owner removes own favorite and profile before deleting own Auth account');
    await assert.rejects(
      signInWithEmailAndPassword(owner.auth, owner.email, owner.password),
      (error) => error.code === 'auth/user-not-found',
    );
    pass('deleted Firebase Auth identity can no longer restore access to favorites');
    await denied(
      getDocFromServer(doc(guest.db, favoritePath)),
      'deleted account favorite is absent and cannot be read by an unauthenticated client',
    );

    console.log(`Spark favorites client Emulator: ${assertions}/${assertions} assertions passed; project=${projectId}; loopback only.`);
  } finally {
    await Promise.all(apps.map((app) => deleteApp(app).catch(() => {})));
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
