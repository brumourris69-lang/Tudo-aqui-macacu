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
  const authorizedJobDemo = () => localOnly() && process.env.GCLOUD_PROJECT === 'demo-universal-search';
  const jobDetailsOptions = { region: 'southamerica-east1', enforceAppCheck: requireAppCheck,
    maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' };
  const resolveJob = async (request, { requireAttestation = requireAppCheck, exactDemo = false } = {}) => {
    if (exactDemo ? !authorizedJobDemo() : !localOnly()) {
      throw new HttpsError('failed-precondition', 'Detalhe de vagas desabilitado.');
    }
    if (requireAttestation && !request.app?.appId) {
      throw new HttpsError('failed-precondition', 'Aplicativo não validado.');
    }
    try { return await backend.resolveJob(request); }
    catch (error) {
      if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Não foi possível carregar esta vaga.');
    }
  };
  return {
    syncBusinessSearchIndex: onDocumentWritten({ document: 'establishments/{id}',
      region: 'southamerica-east1', retry: true, maxInstances: 2, concurrency: 4 },
    async (event) => {
      if (!localOnly()) throw new Error('Busca de produção desabilitada.');
      await backend.synchronize('establishments', event.params.id);
    }),
    syncTourismSearchIndex: onDocumentWritten({ document: 'routes/{id}',
      region: 'southamerica-east1', retry: true, maxInstances: 2, concurrency: 4 },
    async (event) => {
      if (!localOnly()) throw new Error('Busca de produção desabilitada.');
      await backend.synchronize('routes', event.params.id);
    }),
    syncNewsSearchIndex: onDocumentWritten({ document: 'news/{id}',
      region: 'southamerica-east1', retry: true, maxInstances: 2, concurrency: 4 },
    async (event) => {
      if (!localOnly()) throw new Error('Busca de produção desabilitada.');
      await backend.synchronize('news', event.params.id);
    }),
    syncEventsSearchIndex: onDocumentWritten({ document: 'events/{id}',
      region: 'southamerica-east1', retry: true, maxInstances: 2, concurrency: 4 },
    async (event) => {
      if (!localOnly()) throw new Error('Busca de produção desabilitada.');
      await backend.synchronize('events', event.params.id);
    }),
    syncJobsSearchIndex: onDocumentWritten({ document: 'jobs/{id}',
      region: 'southamerica-east1', retry: true, maxInstances: 2, concurrency: 4 },
    async (event) => {
      if (!localOnly()) throw new Error('Busca de produção desabilitada.');
      await backend.synchronize('jobs', event.params.id);
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
    getSearchTourismSpot: onCall({ region: 'southamerica-east1', enforceAppCheck: requireAppCheck,
      maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' },
    async (request) => {
      if (!localOnly()) throw new HttpsError('failed-precondition', 'Busca de produção desabilitada.');
      try { return await backend.resolveTourism(request); }
      catch (error) {
        if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
        throw new HttpsError('unavailable', 'Não foi possível carregar este local.');
      }
    }),
    getSearchNewsArticle: onCall({ region: 'southamerica-east1', enforceAppCheck: requireAppCheck,
      maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' },
    async (request) => {
      if (!localOnly()) throw new HttpsError('failed-precondition', 'Detalhe de notícias desabilitado.');
      try { return await backend.resolveNews(request); }
      catch (error) {
        if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
        throw new HttpsError('unavailable', 'Não foi possível carregar esta notícia.');
      }
    }),
    getSearchEvent: onCall({ region: 'southamerica-east1', enforceAppCheck: requireAppCheck,
      maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' },
    async (request) => {
      if (!localOnly()) throw new HttpsError('failed-precondition', 'Detalhe de eventos desabilitado.');
      try { return await backend.resolveEvent(request); }
      catch (error) {
        if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
        throw new HttpsError('unavailable', 'Não foi possível carregar este evento.');
      }
    }),
    // Keep the legacy local name while preparing the dedicated contract.
    // Both share the same Auth/App Check/quota/visibility/projection resolver.
    getSearchJob: onCall(jobDetailsOptions, (request) => resolveJob(request)),
    ...(authorizedJobDemo() ? {
      getPublicJob: onCall({ ...jobDetailsOptions, enforceAppCheck: true },
        (request) => resolveJob(request, { requireAttestation: true, exactDemo: true })),
    } : {}),
  };
}
module.exports = { registerLocalSearch };
