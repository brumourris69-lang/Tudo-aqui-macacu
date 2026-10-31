'use strict';

const { createSearchBackend, SearchError } = require('./business_search');
const { createFirestoreStore } = require('./business_search_firestore');
const { betaBackendAllowed } = require('./secure_beta_environment');

const BETA_PUBLIC_SEARCH_SOURCES = Object.freeze([
  ['Establishments', 'establishments'],
  ['Routes', 'routes'],
  ['Events', 'events'],
]);

function registerBetaPublicSearch({
  admin,
  onCall,
  onDocumentWritten,
  HttpsError,
  env = process.env,
}) {
  const adminProjectId = admin.app().options.projectId;
  const backendAllowed = () => betaBackendAllowed({ env, adminProjectId });
  if (!backendAllowed()) {
    throw new Error('Beta public search requires its exact isolated Firebase project.');
  }

  const firestoreTypes = require('firebase-admin/firestore');
  const backend = createSearchBackend({
    store: createFirestoreStore(admin.firestore(), firestoreTypes),
    isTimestamp: (value) => value instanceof firestoreTypes.Timestamp,
    authorizeImage: () => false,
    requireAppCheck: true,
  });
  const options = {
    region: 'southamerica-east1',
    enforceAppCheck: true,
    maxInstances: 2,
    concurrency: 4,
    timeoutSeconds: 15,
    memory: '256MiB',
  };

  const registrations = {
    searchPublicContent: onCall(options, async (request) => {
      if (!backendAllowed()) {
        throw new HttpsError('failed-precondition', 'Busca pública Beta indisponível.');
      }
      try {
        return await backend.searchPublic(request);
      } catch (error) {
        if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
        throw new HttpsError('unavailable', 'Não foi possível pesquisar. Tente novamente.');
      }
    }),
  };

  for (const [suffix, collection] of BETA_PUBLIC_SEARCH_SOURCES) {
    const name = `syncBetaSearch${suffix}`;
    registrations[name] = onDocumentWritten({
      document: `${collection}/{id}`,
      region: 'southamerica-east1',
      retry: true,
      maxInstances: 2,
      concurrency: 4,
    }, async (event) => {
      if (!backendAllowed()) {
        throw new Error('Beta search indexing identity changed; refusing the write.');
      }
      await backend.synchronize(collection, event.params.id);
    });
  }

  return registrations;
}

module.exports = { BETA_PUBLIC_SEARCH_SOURCES, registerBetaPublicSearch };
