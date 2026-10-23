import { authorizeAdmin } from '../_shared/admin_authorization.mjs';
import { createAdminEstablishmentsHandler } from '../_shared/admin_establishments.mjs';
import { createFirebaseFirestoreRestStore } from '../_shared/firebase_firestore_rest.mjs';
import { createFirebaseSigningKeyResolver } from '../_shared/firebase_signing_keys.mjs';
import { verifyFirebaseIdToken } from '../_shared/firebase_id_token.mjs';

const FIREBASE_PROJECT_ID = 'tudo-aqui-macacu';
const getSigningKey = createFirebaseSigningKeyResolver();
const firestore = createFirebaseFirestoreRestStore({
  projectId: FIREBASE_PROJECT_ID,
  serviceAccountJson: () => Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? '',
});
const handle = createAdminEstablishmentsHandler({
  projectId: FIREBASE_PROJECT_ID,
  verifyIdentity: (token: string, projectId: string) => verifyFirebaseIdToken(token, {
    projectId,
    getSigningKey,
  }),
  authorizeAdmin,
  store: firestore,
});

Deno.serve(handle);
