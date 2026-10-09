'use strict';

const { createSearchBackend, SearchError, localOnly } = require('./business_search');
const { createFirestoreStore } = require('./business_search_firestore');

// Called only inside the demo emulator gate in index.js. No production export.
function registerLocalSearch({ admin, onCall, HttpsError, onDocumentWritten }) {
  if (!localOnly()) throw new Error('Busca permitida apenas no emulador demo local.');
  // The emulator wraps admin.firestore(); use the modular exports for types.
  const firestoreTypes = require('firebase-admin/firestore');
  // Explicit exception only inside the demo+loopback gate above. Default strict.
  const requireAppCheck = process.env.LOCAL_SEARCH_REQUIRE_APP_CHECK !== 'false';
  const db = admin.firestore();
  const backend = createSearchBackend({
    store: createFirestoreStore(db, firestoreTypes),
    isTimestamp: (value) => value instanceof firestoreTypes.Timestamp,
    authorizeImage: () => false,
    requireAppCheck,
  });
  return {
    syncBusinessSearchIndex: onDocumentWritten({ document: 'establishments/{id}',
      region: 'southamerica-east1', retry: true, maxInstances: 2, concurrency: 4 },
    async (event) => {
      if (!localOnly()) throw new Error('Busca de produção desabilitada.');
      await backend.synchronize(event.params.id);
    }),
    searchBusinesses: onCall({ region: 'southamerica-east1', enforceAppCheck: requireAppCheck,
      maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' },
    async (request) => {
      if (!localOnly()) throw new HttpsError('failed-precondition', 'Busca de produção desabilitada.');
      try { return await backend.search(request); }
      catch (error) {
        if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
        // Never return SDK errors, request/token contents, document data or credentials.
        throw new HttpsError('unavailable', 'Não foi possível pesquisar. Tente novamente.');
      }
    }),
  };
}
module.exports = { registerLocalSearch };
