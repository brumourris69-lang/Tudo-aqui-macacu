import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveLoopbackEmulatorEndpoint } from './spark_beta_rules_emulator_config.mjs';

const projectId = 'demo-universal-search';
const authEndpoint = resolveLoopbackEmulatorEndpoint(
  process.env.FIREBASE_AUTH_EMULATOR_HOST, 19097, 'Firebase Auth Emulator',
);
const firestoreEndpoint = resolveLoopbackEmulatorEndpoint(
  process.env.FIRESTORE_EMULATOR_HOST, 18087, 'Firestore Emulator',
);
assert.equal(process.env.GCLOUD_PROJECT, projectId);
assert.equal(process.env.GOOGLE_CLOUD_PROJECT, projectId);
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, authEndpoint.address);
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, firestoreEndpoint.address);
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
  connectAuthEmulator, createUserWithEmailAndPassword, deleteUser, getAuth,
} = requireFromFunctions('firebase/auth');
const {
  collection, collectionGroup, connectFirestoreEmulator, deleteDoc, doc, getDoc, getDocs, getFirestore,
  limit, query, runTransaction, serverTimestamp, setDoc,
  startAfter, where, writeBatch,
} = requireFromFunctions('firebase/firestore');

const suffix = randomUUID();
const adminApp = initializeAdminApp({ projectId }, `deletion-admin-${suffix}`);
const adminAuth = getAdminAuth(adminApp);
const adminDb = getAdminFirestore(adminApp);
const apps = [];
const users = [];
let passed = 0;
const pass = label => { passed++; console.log(`PASS ${label}`); };

async function client(label, email = `${label}-${suffix}@example.invalid`) {
  const app = initializeApp({
    apiKey: 'demo-emulator-key', projectId, appId: `demo-${label}`,
  }, `deletion-${label}-${suffix}`);
  apps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://${authEndpoint.address}`, { disableWarnings: true });
  const credential = await createUserWithEmailAndPassword(auth, email, 'LocalOnly123!');
  users.push(credential.user.uid);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, firestoreEndpoint.host, firestoreEndpoint.port);
  return { app, auth, db, user: credential.user };
}

async function seedProfile(uid, email) {
  await adminDb.doc(`users/${uid}`).set({
    displayName: 'Synthetic account', email, photoUrl: '', role: 'user',
    createdAt: new Date(), updatedAt: new Date(),
  });
}

async function removeByQuery(db, collectionName, filters, expectedUid, {
  expectedEmail, interruptAfterFirst = false,
} = {}) {
  let cursor;
  let pages = 0;
  while (true) {
    let current = query(collection(db, collectionName), ...filters, limit(100));
    if (cursor) current = query(current, startAfter(cursor));
    const page = await getDocs(current);
    if (page.empty) return;
    const batch = writeBatch(db);
    for (const item of page.docs) {
      const data = item.data();
      const uidFields = ['uid', 'userId'];
      const ownsUid = uidFields.some(field => data[field] === expectedUid) ||
        data.targetUid === expectedUid;
      const ownsLegacyEmail = typeof expectedEmail === 'string' &&
        data.targetEmail === expectedEmail &&
        (!Object.hasOwn(data, 'targetUid') || data.targetUid === '');
      assert.ok(ownsUid || ownsLegacyEmail,
        `client query returned a record without matching owner: ${item.ref.path}`);
      for (const field of uidFields) {
        if (Object.hasOwn(data, field)) assert.equal(data[field], expectedUid,
          `conflicting owner field: ${item.ref.path}`);
      }
      if (Object.hasOwn(data, 'targetUid')) {
        assert.ok(data.targetUid === expectedUid || (ownsLegacyEmail && data.targetUid === ''));
      }
      batch.delete(item.ref);
    }
    await batch.commit();
    pages++;
    if (interruptAfterFirst && pages === 1) throw new Error('synthetic interruption');
    if (page.size < 100) return;
    cursor = page.docs.at(-1);
  }
}

async function run() {
  const rules = await readFile(path.join(root, 'firestore.beta.rules'), 'utf8');
  const loaded = await fetch(`http://${firestoreEndpoint.address}/emulator/v1/projects/${projectId}:securityRules`, {
    method: 'PUT', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ rules: { files: [{ name: 'firestore.beta.rules', content: rules }] } }),
  });
  assert.equal(loaded.status, 200, 'the exact local Beta/Spark Rules must load');

  const owner = await client('owner');
  const stranger = await client('stranger');
  const activeQuota = await client('active-quota');
  const interrupted = await client('interrupted');
  const administrator = await client('admin');
  const revokedAdmin = await client('revoked-admin');
  const unknownLegacyVote = await client('unknown-legacy-vote');
  const legacyCallable = await client('legacy-callable');
  await adminAuth.setCustomUserClaims(administrator.user.uid, { admin: true, adminVersion: `v-${suffix}` });
  await adminDb.doc(`admin_authorizations/${administrator.user.uid}`).set({ enabled: true, pending: false, version: `v-${suffix}` });
  await administrator.user.getIdToken(true);
  await adminAuth.setCustomUserClaims(revokedAdmin.user.uid, { admin: true, adminVersion: `revoked-${suffix}` });
  await adminDb.doc(`admin_authorizations/${revokedAdmin.user.uid}`).set({ enabled: false, pending: false, version: `revoked-${suffix}` });
  await revokedAdmin.user.getIdToken(true);
  await seedProfile(owner.user.uid, owner.user.email);
  await seedProfile(stranger.user.uid, stranger.user.email);
  await seedProfile(activeQuota.user.uid, activeQuota.user.email);
  await seedProfile(interrupted.user.uid, interrupted.user.email);
  await seedProfile(unknownLegacyVote.user.uid, unknownLegacyVote.user.email);
  await seedProfile(legacyCallable.user.uid, legacyCallable.user.email);
  await adminDb.doc(`users/${administrator.user.uid}`).set({
    displayName: 'Synthetic admin', email: administrator.user.email, photoUrl: '', role: 'admin',
    createdAt: new Date(), updatedAt: new Date(),
  });
  await adminDb.doc(`users/${revokedAdmin.user.uid}`).set({
    displayName: 'Synthetic revoked admin', email: revokedAdmin.user.email, photoUrl: '', role: 'user',
    createdAt: new Date(), updatedAt: new Date(),
  });

  const ownerUid = owner.user.uid;
  const otherUid = stranger.user.uid;
  const mvpFavoritePath = `users/${ownerUid}/favorites/business::mvp-fixture`;
  await setDoc(doc(owner.db, mvpFavoritePath), {
    id: 'business::mvp-fixture', name: 'Synthetic MVP favorite',
    type: 'business', targetId: 'mvp-fixture',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  pass('MVP favorite creation is allowed only under the authenticated user path');
  const mvpQuotaRef = doc(owner.db, `users/${ownerUid}/contact_message_limits/current`);
  assert.equal((await getDoc(mvpQuotaRef)).exists(), false,
    'the signed-in owner can read only its own message quota');
  pass('MVP owner can read its own contact quota before sending');
  await deleteDoc(doc(owner.db, mvpFavoritePath));
  assert.equal((await getDoc(doc(owner.db, mvpFavoritePath))).exists(), false);
  pass('MVP favorites are isolated under the authenticated owner UID');

  const ownedPaths = [
    `users/${ownerUid}/favorites/favorite-1`,
    `users/${ownerUid}/devices/device-1`,
    `contact_messages/contact-${suffix}`,
    `business_proposals/proposal-${suffix}`,
    `reviews/review-${suffix}`,
    `metrics/metric-${suffix}`,
    `private_notifications/private-${suffix}`,
    `push_queue/queue-${suffix}`,
    `notifications/legacy-notification-${suffix}`,
  ];
  await adminDb.doc(ownedPaths[0]).set({ id: 'favorite-1', name: 'Synthetic', type: 'business', targetId: 'fixture', createdAt: new Date() });
  await adminDb.doc(ownedPaths[1]).set({ targetUid: ownerUid, token: 'synthetic-device-token' });
  await adminDb.doc(ownedPaths[2]).set({ uid: ownerUid, email: owner.user.email, contact: '0000000000', message: 'synthetic', status: 'pending', createdAt: new Date() });
  await adminDb.doc(ownedPaths[3]).set({ userId: ownerUid, name: 'Synthetic', contact: 'synthetic', details: 'synthetic', status: 'pending', createdAt: new Date() });
  await adminDb.doc(ownedPaths[4]).set({ uid: ownerUid, businessId: 'fixture', message: 'synthetic', stars: 5, status: 'pending', published: false, createdAt: new Date() });
  await adminDb.doc(ownedPaths[5]).set({ userId: ownerUid, event: 'synthetic', createdAt: new Date() });
  await adminDb.doc(ownedPaths[6]).set({ targetUid: ownerUid, title: 'synthetic' });
  await adminDb.doc(ownedPaths[7]).set({ targetUid: ownerUid, targetEmail: '', status: 'queued' });
  await adminDb.doc(ownedPaths[8]).set({ targetEmail: owner.user.email, targetUid: '', title: 'synthetic' });
  const missingRecipientUidPath = `notifications/missing-recipient-uid-${suffix}`;
  await adminDb.doc(missingRecipientUidPath).set({ targetEmail: owner.user.email, title: 'synthetic' });

  await adminDb.doc('beta_public_catalog/polls/items/public-poll').set({
    sourceId: 'public-poll', visibility: 'public', publicData: { options: ['yes', 'no'] },
  });
  const deferredProposal = doc(owner.db, `business_proposals/deferred-${suffix}`);
  await assert.rejects(setDoc(deferredProposal, {
    uid: ownerUid, name: 'Synthetic', contact: '', details: 'deferred',
    status: 'pending', createdAt: serverTimestamp(),
  }), error => error.code === 'permission-denied');
  const deferredReview = doc(owner.db, `reviews/deferred-${suffix}`);
  await assert.rejects(setDoc(deferredReview, {
    uid: ownerUid, businessId: 'fixture', business: 'Synthetic', message: 'deferred',
    stars: 5, status: 'pending', published: false, createdAt: serverTimestamp(),
  }), error => error.code === 'permission-denied');
  await assert.rejects(setDoc(doc(owner.db, `polls/public-poll/votes/${ownerUid}`), {
    uid: ownerUid, option: 'yes', createdAt: serverTimestamp(),
  }), error => error.code === 'permission-denied');
  await assert.rejects(setDoc(doc(administrator.db, `push_queue/deferred-${suffix}`), {
    title: 'Synthetic', description: '', link: '', targetEmail: '',
    published: true, status: 'queued', createdAt: serverTimestamp(),
  }), error => error.code === 'permission-denied');
  pass('deferred proposals, reviews, votes, and remote-push queue reject new client writes');

  const publishedLegacyVotePath = `polls/public-poll/votes/${ownerUid}`;
  await adminDb.doc(publishedLegacyVotePath).set({ option: 'yes', createdAt: new Date() });
  await adminDb.doc('beta_public_catalog/polls/items/unpublished-poll').set({
    sourceId: 'unpublished-poll', visibility: 'private', publicData: { options: ['yes', 'no'] },
  });
  const unknownLegacyUid = unknownLegacyVote.user.uid;
  const unpublishedLegacyVotePath = `polls/unpublished-poll/votes/${unknownLegacyUid}`;
  await adminDb.doc(unpublishedLegacyVotePath).set({ option: 'yes', createdAt: new Date() });
  const currentVotePath = `polls/current-poll/votes/${ownerUid}`;
  await adminDb.doc(currentVotePath).set({ uid: ownerUid, option: 'yes', createdAt: new Date() });

  await removeByQuery(owner.db, 'contact_messages', [where('uid', '==', ownerUid)], ownerUid);
  await removeByQuery(owner.db, 'business_proposals', [where('userId', '==', ownerUid)], ownerUid);
  await removeByQuery(owner.db, 'reviews', [where('uid', '==', ownerUid)], ownerUid);
  await removeByQuery(owner.db, 'metrics', [where('userId', '==', ownerUid)], ownerUid);
  await removeByQuery(owner.db, 'private_notifications', [where('targetUid', '==', ownerUid)], ownerUid);
  await removeByQuery(owner.db, 'push_queue', [where('targetUid', '==', ownerUid)], ownerUid);
  await removeByQuery(owner.db, 'notifications', [
    where('targetEmail', '==', owner.user.email),
  ], ownerUid, { expectedEmail: owner.user.email });
  assert.equal((await adminDb.doc(missingRecipientUidPath).get()).exists, false,
    'legacy current-email records without targetUid are still owner-enumerable and removable');

  const voteQuery = query(collectionGroup(owner.db, 'votes'), where('uid', '==', ownerUid), limit(100));
  const currentVotes = await getDocs(voteQuery);
  for (const item of currentVotes.docs) await deleteDoc(item.ref);
  const publicPolls = await getDocs(query(
    collection(owner.db, 'beta_public_catalog/polls/items'),
    where('visibility', '==', 'public'), limit(40),
  ));
  for (const poll of publicPolls.docs) {
    const legacyVote = doc(owner.db, `polls/${poll.id}/votes/${ownerUid}`);
    const snapshot = await getDoc(legacyVote);
    if (!snapshot.exists()) continue;
    const voteOwner = snapshot.data().uid;
    if (voteOwner != null && voteOwner !== ownerUid) throw new Error('legacy vote owner mismatch');
    await deleteDoc(legacyVote);
  }
  assert.ok(publicPolls.docs.some(poll => poll.id === 'public-poll'));

  for (const pathName of ownedPaths.slice(2)) {
    assert.equal((await adminDb.doc(pathName).get()).exists, false, `owned data remains: ${pathName}`);
  }
  assert.equal((await adminDb.doc(publishedLegacyVotePath).get()).exists, false);
  assert.equal((await adminDb.doc(currentVotePath).get()).exists, false);
  assert.equal((await adminDb.doc(unpublishedLegacyVotePath).get()).exists, true,
    'unpublished legacy vote without uid is intentionally not discoverable by a safe owner query');
  pass('owner client removes discoverable personal records; unpublished legacy vote remains an explicit gap');

  const hashedRateId = createHash('sha256').update(`${legacyCallable.user.uid}:favorite`).digest('hex');
  const hashedRatePath = `user_operation_limits/${hashedRateId}`;
  await adminDb.doc(hashedRatePath).set({ minute: 1, minutes: 1, day: 1, days: 1, expiresAt: new Date(Date.now() + 86_400_000) });
  await assert.rejects(deleteDoc(doc(legacyCallable.db, hashedRatePath)),
    error => error.code === 'permission-denied');
  assert.equal((await adminDb.doc(hashedRatePath).get()).exists, true);
  assert.equal((await adminAuth.getUser(legacyCallable.user.uid)).uid, legacyCallable.user.uid);
  pass('hashed legacy callable rate-limit data is not owner-enumerable or deletable under Rules');

  await assert.rejects(
    removeByQuery(stranger.db, 'contact_messages', [where('uid', '==', ownerUid)], otherUid),
    error => error.code === 'permission-denied',
  );
  await assert.rejects(deleteDoc(doc(stranger.db, `users/${ownerUid}/favorites/favorite-1`)),
    error => error.code === 'permission-denied');
  pass('other account cannot enumerate or delete the owner’s personal data');

  const deviceDocs = await getDocs(query(collection(owner.db, `users/${ownerUid}/devices`), limit(100)));
  for (const item of deviceDocs.docs) await deleteDoc(item.ref);
  const favoriteDocs = await getDocs(query(collection(owner.db, `users/${ownerUid}/favorites`), limit(100)));
  for (const item of favoriteDocs.docs) await deleteDoc(item.ref);
  pass('owner can remove device tokens and favorites under its own UID path');

  const interruptedUid = interrupted.user.uid;
  for (let index = 0; index < 105; index++) {
    await adminDb.doc(`contact_messages/page-${suffix}-${String(index).padStart(3, '0')}`).set({
      uid: interruptedUid, email: interrupted.user.email, contact: '0000000000',
      message: `synthetic-${index}`, status: 'pending', createdAt: new Date(),
    });
  }
  await assert.rejects(removeByQuery(interrupted.db, 'contact_messages', [
    where('uid', '==', interruptedUid),
  ], interruptedUid, { interruptAfterFirst: true }), /synthetic interruption/);
  const remainingAfterInterrupt = await getDocs(query(
    collection(interrupted.db, 'contact_messages'),
    where('uid', '==', interruptedUid), limit(100),
  ));
  assert.equal(remainingAfterInterrupt.size, 5);
  await removeByQuery(interrupted.db, 'contact_messages', [where('uid', '==', interruptedUid)], interruptedUid);
  assert.equal((await getDocs(query(collection(interrupted.db, 'contact_messages'), where('uid', '==', interruptedUid), limit(100)))).size, 0);
  pass('paginated client cleanup resumes after an interruption without skipping records');

  await assert.rejects(deleteDoc(doc(administrator.db, `users/${administrator.user.uid}`)),
    error => error.code === 'permission-denied');
  await assert.rejects(deleteDoc(doc(revokedAdmin.db, `users/${revokedAdmin.user.uid}`)),
    error => error.code === 'permission-denied');
  await assert.rejects(deleteDoc(doc(owner.db, `users/${stranger.user.uid}`)),
    error => error.code === 'permission-denied');
  pass('authorized/revoked Admin identities and other-user profiles cannot be self/third-party deleted');

  const mismatch = await client('mismatch');
  await seedProfile(mismatch.user.uid, mismatch.user.email);
  const mismatchRecord = `contact_messages/mixed-owner-${suffix}`;
  await adminDb.doc(mismatchRecord).set({
    uid: mismatch.user.uid, userId: otherUid, email: mismatch.user.email,
    contact: '0000000000', message: 'synthetic conflict', status: 'pending',
    createdAt: new Date(),
  });
  const conflictingQuery = await getDocs(query(
    collection(mismatch.db, 'contact_messages'),
    where('uid', '==', mismatch.user.uid), limit(100),
  ));
  assert.equal(conflictingQuery.size, 1,
    'the owner query may return a malformed document keyed by this UID');
  await assert.rejects(deleteDoc(conflictingQuery.docs[0].ref),
    error => error.code === 'permission-denied');
  assert.equal((await adminAuth.getUser(mismatch.user.uid)).uid, mismatch.user.uid);
  assert.equal((await adminDb.doc(mismatchRecord).get()).exists, true);
  pass('a conflicting record cannot be deleted; the app ownership check stops cleanup and preserves Auth');

  const visibleForUnknown = await getDocs(query(
    collection(unknownLegacyVote.db, 'beta_public_catalog/polls/items'),
    where('visibility', '==', 'public'), limit(40),
  ));
  assert.equal(visibleForUnknown.docs.some(poll => poll.id === 'unpublished-poll'), false);
  assert.equal((await adminDb.doc(unpublishedLegacyVotePath).get()).exists, true);
  assert.equal((await adminAuth.getUser(unknownLegacyUid)).uid, unknownLegacyUid);
  pass('legacy vote for an unpublished poll cannot be discovered safely by the owner query');

  const pendingUid = activeQuota.user.uid;
  const pendingQuotaPath = `users/${pendingUid}/contact_message_limits/current`;
  const pendingRequestPath = `account_deletion_requests/${pendingUid}`;
  await adminDb.doc(pendingQuotaPath).set({
    uid: pendingUid, count: 1,
    periodStartedAt: new Date(Date.now() - 60_000), updatedAt: new Date(),
  });
  const quotaStartedAt = (await adminDb.doc(pendingQuotaPath).get()).data().periodStartedAt.toDate();
  const retryAt = new Date(quotaStartedAt.getTime() + 24 * 60 * 60 * 1000);
  await assert.rejects(deleteDoc(doc(activeQuota.db, pendingQuotaPath)),
    error => error.code === 'permission-denied');
  await setDoc(doc(activeQuota.db, pendingRequestPath), {
    uid: pendingUid, requestedAt: serverTimestamp(),
    retryAfter: retryAt, status: 'pending',
  });
  assert.equal((await adminDb.doc(pendingRequestPath).get()).data().status, 'pending');
  assert.equal((await adminAuth.getUser(pendingUid)).uid, pendingUid);
  pass('active quota blocks early counter deletion and leaves a durable pending request with Auth intact');

  const expired = new Date(Date.now() - 25 * 60 * 60 * 1000);
  await adminDb.doc(pendingQuotaPath).set({ uid: pendingUid, count: 1, periodStartedAt: expired, updatedAt: expired });
  await adminDb.doc(pendingRequestPath).update({
    retryAfter: new Date(expired.getTime() + 24 * 60 * 60 * 1000),
  });
  await deleteDoc(doc(activeQuota.db, pendingQuotaPath));
  const finalize = writeBatch(activeQuota.db);
  finalize.delete(doc(activeQuota.db, pendingRequestPath));
  finalize.delete(doc(activeQuota.db, `users/${pendingUid}`));
  await finalize.commit();
  assert.equal((await adminDb.doc(pendingRequestPath).get()).exists, false);
  assert.equal((await adminDb.doc(`users/${pendingUid}`).get()).exists, false);
  pass('owner resumes an expired pending request and atomically removes request plus profile');
  const { EmailAuthProvider, reauthenticateWithCredential } = requireFromFunctions('firebase/auth');
  await reauthenticateWithCredential(
    activeQuota.user,
    EmailAuthProvider.credential(activeQuota.user.email, 'LocalOnly123!'),
  );
  await deleteUser(activeQuota.user);
  await assert.rejects(adminAuth.getUser(pendingUid), error => error.code === 'auth/user-not-found');
  pass('resumed pending deletion removes Firebase Auth only after Firestore cleanup completes');

  // The second registered account proves authorization of its own data is
  // independent; an Admin SDK fixture cannot confer a client permission.
  await adminDb.doc(`contact_messages/other-${suffix}`).set({ uid: otherUid, email: stranger.user.email, contact: '0000000000', message: 'synthetic', status: 'pending', createdAt: new Date() });
  await removeByQuery(stranger.db, 'contact_messages', [where('uid', '==', otherUid)], otherUid);
  assert.equal((await adminDb.doc(`contact_messages/other-${suffix}`).get()).exists, false);
  pass('second account can delete only its own records');

  // Auth account creation/deletion remains client-side and requires recent
  // login. Reauthenticate with the synthetic password and delete own Auth.
  const credential = EmailAuthProvider.credential(owner.user.email, 'LocalOnly123!');
  await reauthenticateWithCredential(owner.user, credential);
  const removeOwnerProfile = writeBatch(owner.db);
  removeOwnerProfile.delete(doc(owner.db, `users/${ownerUid}`));
  await removeOwnerProfile.commit();
  await deleteUser(owner.user);
  await assert.rejects(adminAuth.getUser(ownerUid), error => error.code === 'auth/user-not-found');
  pass('reauthenticated SDK client can delete only its own Firebase Auth identity');

  console.log(`RESULT ${passed}/${passed} assertions passed`);
}

try {
  await run();
} finally {
  for (const uid of users) {
    try { await adminAuth.deleteUser(uid); } catch { /* ephemeral synthetic Auth fixture */ }
  }
  for (const app of apps) await deleteApp(app).catch(() => {});
  await deleteAdminApp(adminApp).catch(() => {});
}
