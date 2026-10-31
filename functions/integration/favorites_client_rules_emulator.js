'use strict';
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase/app');
const {
  createUserWithEmailAndPassword,
  connectAuthEmulator,
  getAuth,
  signInWithEmailAndPassword,
  signOut,
} = require('firebase/auth');
const {
  collection,
  connectFirestoreEmulator,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  setDoc,
} = require('firebase/firestore');
const admin = require('firebase-admin');

async function main() {
  const requiredProject = 'demo-universal-search';
  assert.equal(process.env.GCLOUD_PROJECT, requiredProject);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');

  admin.initializeApp({ projectId: requiredProject });
  const adminAuth = admin.auth();
  const adminDb = admin.firestore();
  const suffix = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const clients = [];
  const users = [];
  const adminAuthorizationPaths = [];
  let passed = 0;

  function check(name, condition) {
    assert.ok(condition, name);
    passed++;
    console.log(`PASS ${name}`);
  }

  async function denied(promise, label) {
    await assert.rejects(promise, (error) => {
      assert.equal(error.code, 'permission-denied', label);
      return true;
    });
    passed++;
    console.log(`PASS ${label}`);
  }

  async function newClient(label) {
    const app = initializeApp(
      { apiKey: 'demo-api-key', projectId: requiredProject, appId: `demo-${label}` },
      `favorites-${label}-${suffix}`,
    );
    clients.push(app);
    const auth = getAuth(app);
    connectAuthEmulator(auth, 'http://127.0.0.1:9097', { disableWarnings: true });
    const db = getFirestore(app);
    connectFirestoreEmulator(db, '127.0.0.1', 8087);
    const credential = await createUserWithEmailAndPassword(
      auth,
      `favorites-${label}-${suffix}@example.invalid`,
      'LocalOnly123!',
    );
    users.push(credential.user);
    return { auth, db, user: credential.user };
  }

  try {
    const owner = await newClient('owner');
    const other = await newClient('other');
    const administrator = await newClient('admin');
    const adminVersion = `favorites-admin-${suffix}`;
    await adminAuth.setCustomUserClaims(administrator.user.uid, {
      admin: true,
      adminVersion,
    });
    const adminAuthorizationPath = `admin_authorizations/${administrator.user.uid}`;
    adminAuthorizationPaths.push(adminAuthorizationPath);
    await adminDb.doc(adminAuthorizationPath).set({
      enabled: true,
      pending: false,
      version: adminVersion,
    });
    await administrator.user.getIdToken(true);
    const favoritePath = `users/${owner.user.uid}/favorites/business::fixture-${suffix}`;
    await adminDb.doc(favoritePath).set({
      type: 'business',
      targetId: `fixture-${suffix}`,
      name: 'Comércio público fictício',
    });
    const favoriteRef = doc(owner.db, favoritePath);

    check('authenticated owner can read their own saved favorite', (await getDoc(favoriteRef)).exists());
    await denied(
      getDoc(doc(other.db, favoritePath)),
      'a different authenticated account cannot read another user\'s favorite',
    );
    await denied(
      setDoc(doc(owner.db, `${favoritePath}-forged`), { type: 'tourism' }),
      'client cannot create favorite documents directly',
    );
    await denied(
      setDoc(favoriteRef, { type: 'tourism', targetId: 'forged', name: 'Alterado' }),
      'client cannot update favorite documents directly',
    );
    await denied(deleteDoc(favoriteRef), 'client cannot delete favorite documents directly');
    await denied(
      getDocs(collection(owner.db, `users/${other.user.uid}/favorites`)),
      'owner cannot list another account\'s favorites',
    );

    const eventFixtures = [
      {
        id: `agenda-published-${suffix}`,
        data: { title: 'Evento publicado fictício', published: true, active: true },
        visible: true,
      },
      {
        id: `agenda-deleted-false-${suffix}`,
        data: { title: 'Evento não excluído fictício', published: true, active: true, deleted: false },
        visible: true,
      },
      {
        id: `agenda-no-deletion-fields-${suffix}`,
        data: { title: 'Evento legado fictício', published: true, active: true },
        visible: true,
      },
      {
        id: `agenda-draft-${suffix}`,
        data: { title: 'Rascunho fictício', published: false, active: true },
        visible: false,
      },
      {
        id: `agenda-inactive-${suffix}`,
        data: { title: 'Evento inativo fictício', published: true, active: false },
        visible: false,
      },
      {
        id: `agenda-deleted-${suffix}`,
        data: {
          title: 'Evento excluído fictício',
          published: true,
          active: true,
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        visible: false,
      },
      {
        id: `agenda-deleted-flag-${suffix}`,
        data: {
          title: 'Evento tombstone fictício',
          published: true,
          active: true,
          deleted: true,
        },
        visible: false,
      },
      {
        id: `agenda-deleted-false-marker-${suffix}`,
        data: {
          title: 'Evento com tombstone permanente fictício',
          published: true,
          active: true,
          deleted: false,
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        visible: false,
      },
      {
        id: `agenda-null-deleted-at-${suffix}`,
        data: {
          title: 'Evento com marcador inválido fictício',
          published: true,
          active: true,
          deletedAt: null,
        },
        visible: false,
      },
    ];
    for (const fixture of eventFixtures) {
      await adminDb.doc(`events/${fixture.id}`).set(fixture.data);
    }
    const agendaEvent = eventFixtures[0];
    const agendaFavoritePath =
      `users/${owner.user.uid}/favorites/event::${agendaEvent.id}`;
    await adminDb.doc(agendaFavoritePath).set({
      type: 'event',
      targetId: agendaEvent.id,
      name: agendaEvent.data.title,
    });
    const agendaFavoriteRef = doc(owner.db, agendaFavoritePath);
    const adminCreatedEventPath = `events/admin-created-${suffix}`;
    await setDoc(doc(administrator.db, adminCreatedEventPath), {
      title: 'Rascunho criado pelo Admin fictício',
      description: 'Fixture local de autorização.',
      published: false,
      active: true,
      featured: false,
    });
    check(
      'authorized Admin can create an unpublished event through the client SDK',
      (await getDoc(doc(administrator.db, adminCreatedEventPath))).exists(),
    );
    check(
      'authorized Admin can read an unpublished event as an administrator',
      (await getDoc(doc(administrator.db,
        `events/${eventFixtures.find((fixture) => fixture.id.startsWith('agenda-draft-')).id}`))).exists(),
    );
    check(
      'authorized Admin can list event documents through the client SDK',
      !(await getDocs(collection(administrator.db, 'events'))).empty,
    );
    await denied(
      getDocs(collection(owner.db, 'events')),
      'regular account cannot bypass the public detail-only event Rules with a list query',
    );
    await denied(
      getDoc(doc(administrator.db, favoritePath)),
      'Admin client cannot read another account\'s personal favorites',
    );
    await denied(
      getDocs(collection(administrator.db, `users/${owner.user.uid}/favorites`)),
      'Admin client cannot list another account\'s personal favorites',
    );
    await denied(
      deleteDoc(doc(administrator.db, favoritePath)),
      'Admin client cannot delete another account\'s personal favorites',
    );
    check(
      'agenda event is readable by its owner only',
      (await getDoc(agendaFavoriteRef)).exists(),
    );
    await denied(
      getDoc(doc(other.db, agendaFavoritePath)),
      'another account cannot read the owner\'s saved agenda event',
    );
    await denied(
      getDoc(doc(administrator.db, agendaFavoritePath)),
      'Admin client cannot read another account\'s personal agenda',
    );
    for (const fixture of eventFixtures) {
      const eventRef = doc(owner.db, `events/${fixture.id}`);
      if (fixture.visible) {
        check(
          'published active event is readable by a regular account',
          (await getDoc(eventRef)).exists(),
        );
      } else {
        await denied(
          getDoc(eventRef),
          `regular account cannot read ${fixture.id.split('-').slice(1, -1).join('-')} event`,
        );
      }
    }
    await denied(
      setDoc(doc(owner.db, `events/forged-${suffix}`), {
        title: 'Evento forjado',
        published: true,
        active: true,
      }),
      'regular account cannot create an event',
    );
    await denied(
      deleteDoc(doc(owner.db, `events/${agendaEvent.id}`)),
      'regular account cannot delete a published event',
    );

    await signOut(owner.auth);
    await denied(getDoc(favoriteRef), 'signed-out client cannot read saved favorites');

    const visibleId = `favorite-visible-${suffix}`;
    const hiddenId = `favorite-hidden-${suffix}`;
    const tombstoneId = `favorite-tombstone-${suffix}`;
    await adminDb.doc(`routes/${visibleId}`).set({
      title: 'Ponto público fictício', published: true, active: true,
    });
    await adminDb.doc(`routes/${hiddenId}`).set({
      title: 'Rascunho fictício', published: false, active: true,
    });
    await adminDb.doc(`routes/${tombstoneId}`).set({
      title: 'Excluído logicamente', published: true, active: true,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    check(
      'public authenticated reader can read a published tourism item',
      (await getDoc(doc(owner.db, `routes/${visibleId}`))).exists(),
    );
    await denied(
      getDoc(doc(owner.db, `routes/${hiddenId}`)),
      'unpublished tourism item is not readable by a regular account',
    );
    await denied(
      getDoc(doc(owner.db, `routes/${tombstoneId}`)),
      'logically removed tourism item is not readable by a regular account',
    );

    const ownerSignIn = await signInWithEmailAndPassword(
      owner.auth,
      owner.user.email,
      'LocalOnly123!',
    );
    check('re-authenticated owner can still read their persisted favorite', ownerSignIn.user.uid === owner.user.uid && (await getDoc(doc(owner.db, favoritePath))).exists());
    await signOut(owner.auth);
    const switched = await signInWithEmailAndPassword(
      owner.auth,
      other.user.email,
      'LocalOnly123!',
    );
    check('switching accounts changes the active Firebase identity', switched.user.uid === other.user.uid);
    await denied(
      getDoc(doc(owner.db, favoritePath)),
      'switched account does not inherit the previous account favorites',
    );

    await adminDb.doc(adminAuthorizationPath).update({ enabled: false });
    await denied(
      getDoc(doc(administrator.db,
        `events/${eventFixtures.find((fixture) => fixture.id.startsWith('agenda-draft-')).id}`)),
      'revoked Admin cannot read an unpublished event',
    );
    const revokedEventPath = `events/revoked-admin-write-${suffix}`;
    await denied(
      setDoc(doc(administrator.db, revokedEventPath), {
        title: 'Não deve ser criado',
        description: 'Tentativa após revogação.',
        published: true,
        active: true,
        featured: false,
      }),
      'revoked Admin cannot create an event',
    );
    check(
      'revoked Admin write left no event behind',
      !(await adminDb.doc(revokedEventPath).get()).exists,
    );

    console.log(`Favorites Rules client Emulator: ${passed} assertions passed; project=${requiredProject}; loopback only.`);
  } finally {
    await Promise.all(clients.map((app) => deleteApp(app).catch(() => {})));
    await adminAuth.deleteUsers([...new Set(users.map((user) => user.uid))]).catch(() => {});
    await Promise.all(adminAuthorizationPaths.map((path) =>
      adminDb.doc(path).delete().catch(() => {})));
    await adminDb.doc(`users/${users[0]?.uid}/favorites/business::fixture-${suffix}`).delete().catch(() => {});
    await adminDb.doc(`users/${users[0]?.uid}/favorites/event::agenda-published-${suffix}`).delete().catch(() => {});
    for (const suffixPath of [
      `routes/favorite-visible-${suffix}`,
      `routes/favorite-hidden-${suffix}`,
      `routes/favorite-tombstone-${suffix}`,
      `events/admin-created-${suffix}`,
      ...['published', 'deleted-false', 'no-deletion-fields', 'draft', 'inactive', 'deleted',
        'deleted-flag', 'deleted-false-marker', 'null-deleted-at'].map((state) =>
        `events/agenda-${state}-${suffix}`),
    ]) await adminDb.doc(suffixPath).delete().catch(() => {});
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
