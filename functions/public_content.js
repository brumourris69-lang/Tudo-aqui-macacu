'use strict';
const crypto = require('node:crypto');
const net = require('node:net');
const { secureBackendAllowed } = require('./secure_backend_environment');
const { stagingBackendAllowed } = require('./secure_staging_environment');
const { PUBLIC_COLLECTIONS, publiclyVisible } = require('./content_visibility');
const { SearchError } = require('./business_search');
const { projectPublic, JOB_FIELDS } = require('./public_content_projection');
const STAGING_PUBLIC_COLLECTIONS = new Set(['establishments', 'routes', 'utilities', 'jobs']);
const PUBLIC_RESPONSE_MAX_BYTES = 256 * 1024;
function createPublicContentRegistrar({ admin, onCall, HttpsError, staging = false, env = process.env,
  backendAllowedOverride }) {
  const adminProjectId = staging ? admin.app().options.projectId : '';
  const backendAllowed = () => staging
    ? stagingBackendAllowed({ env, adminProjectId })
    : backendAllowedOverride ? backendAllowedOverride() : secureBackendAllowed();
  if (!backendAllowed()) throw new Error(staging
    ? 'Public listing requires the authorized staging configuration'
    : 'Public listing requires demo emulator or authorized backend configuration');
  const { FieldPath, Timestamp } = require('firebase-admin/firestore');
  const db = admin.firestore();
  const isTimestamp = value => value instanceof Timestamp;
  function rateLimitPrincipal(request) {
    if (request.auth != null) {
      const uid = request.auth.uid;
      if (typeof uid !== 'string' || uid.length === 0 || uid.length > 128 || uid.includes('/')) {
        throw new SearchError('unauthenticated', 'Sessão inválida.');
      }
      return `uid:${uid}`;
    }
    const appId = request.app?.appId;
    const ip = request.rawRequest?.ip || request.rawRequest?.socket?.remoteAddress;
    if (typeof appId !== 'string' || appId.length === 0 || appId.length > 256) {
      throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    }
    // Prefer an IP bucket where the runtime exposes a validated address. Some
    // emulator/runtime adapters omit it, so fall back to a shared per-app
    // bucket instead of opening an unmetered path; never trust forwarded headers.
    const network = typeof ip === 'string' && net.isIP(ip) !== 0 ? ip : 'shared';
    // Store only a pseudonymous App Check + network bucket digest, never the raw address.
    return `visitor:${appId}:${network}`;
  }
  async function admit(principal, rateCollection, message) {
    const key = crypto.createHash('sha256').update(principal).digest('hex');
    const rate = db.collection(rateCollection).doc(key);
    await db.runTransaction(async tx => {
      const previous = (await tx.get(rate)).data();
      const minute = Math.floor(Date.now() / 60000);
      const count = previous?.minute === minute ? previous.count : 0;
      if (count >= 120) throw new SearchError('resource-exhausted', message);
      tx.set(rate, { minute, count: count + 1, expiresAt: Timestamp.fromMillis(Date.now() + 86400000) });
    });
  }
  function validDocumentId(id) {
    return typeof id === 'string' && id.trim().length > 0 && id === id.trim() &&
      id !== '.' && id !== '..' && !id.includes('/') && Buffer.byteLength(id) <= 1500;
  }
  async function list(request) {
    if (!backendAllowed()) throw new SearchError('failed-precondition', staging
      ? 'Listagem de homologação indisponível.' : 'Listagem local indisponível.');
    if (!request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    const input = request.data;
    if (!input || Object.keys(input).some(k => !['collection', 'limit', 'cursor'].includes(k)) ||
        !PUBLIC_COLLECTIONS.includes(input.collection) ||
        (staging && !STAGING_PUBLIC_COLLECTIONS.has(input.collection)) ||
        !Number.isInteger(input.limit) || input.limit < 1 || input.limit > 40 ||
        (input.cursor != null && (typeof input.cursor !== 'string' || !input.cursor ||
          input.cursor.length > 1500 || input.cursor.includes('/')))) {
      throw new SearchError('invalid-argument', 'Listagem inválida.');
    }
    await admit(rateLimitPrincipal(request), 'public_content_rate_limits', 'Aguarde antes de carregar novamente.');
    const items = [];
    let after = input.cursor || null, scanned = 0, exhausted = false, responseLimitReached = false;
    while (items.length < input.limit && scanned < 80 && !exhausted) {
      let query = db.collection(input.collection)
        .where(input.collection === 'utilities' ? 'active' : 'published', '==', true);
      if (input.collection === 'notifications') query = query.where('targetEmail', '==', '');
      query = query.orderBy(FieldPath.documentId());
      if (after) query = query.startAfter(after);
      // Small batches bound duplicate reads when a page stops at the byte ceiling.
      const count = Math.min(input.limit - items.length, 80 - scanned, 10);
      const batch = await query.limit(count).get();
      scanned += batch.size; exhausted = batch.size < count;
      for (const doc of batch.docs) {
        const data = doc.data();
        // Always use current source and server clock; no visibility cache/index.
        if (publiclyVisible(input.collection, data, Date.now(), isTimestamp)) {
          const projected = projectPublic(data, isTimestamp, input.collection);
          if (projected !== null) {
            const item = { id: doc.id, data: projected };
            const candidate = { items: [...items, item], nextCursor: doc.id };
            if (Buffer.byteLength(JSON.stringify(candidate), 'utf8') > PUBLIC_RESPONSE_MAX_BYTES) {
              if (items.length === 0) {
                throw new SearchError('resource-exhausted', 'Este conteúdo excede o limite de resposta.');
              }
              responseLimitReached = true;
              break;
            }
            items.push(item);
            after = doc.id;
            continue;
          }
        }
        after = doc.id;
      }
      if (responseLimitReached) break;
    }
    return { items, nextCursor: (responseLimitReached || !exhausted) && after ? after : null };
  }
  const listPublicContent = onCall({ region: 'southamerica-east1', enforceAppCheck: true,
    maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' }, async request => {
    try { return await list(request); }
    catch (error) {
      if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Não foi possível carregar o conteúdo.');
    }
  });
  const detailCollections = new Set(['establishments', 'routes', 'utilities', 'jobs', 'events']);
  const getPublicContentDetail = onCall({ region: 'southamerica-east1', enforceAppCheck: true,
    maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' }, async request => {
    try {
      if (!backendAllowed()) throw new SearchError('failed-precondition', 'Detalhes públicos indisponíveis.');
      if (!request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
      const input = request.data;
      if (!input || typeof input !== 'object' || Array.isArray(input) ||
          Object.keys(input).length !== 2 || !Object.hasOwn(input, 'collection') ||
          !Object.hasOwn(input, 'id') || !detailCollections.has(input.collection) ||
          (staging && !STAGING_PUBLIC_COLLECTIONS.has(input.collection)) ||
          !validDocumentId(input.id)) {
        throw new SearchError('invalid-argument', 'Detalhe público inválido.');
      }
      await admit(rateLimitPrincipal(request), 'public_content_detail_rate_limits',
        'Aguarde antes de carregar outro detalhe.');
      const snapshot = await db.collection(input.collection).doc(input.id).get();
      const data = snapshot.data();
      if (!snapshot.exists || !publiclyVisible(input.collection, data, Date.now(), isTimestamp)) {
        return { status: 'unavailable' };
      }
      const projected = projectPublic(data, isTimestamp, input.collection);
      if (projected === null) return { status: 'unavailable' };
      const response = { status: 'available', id: input.id, data: projected };
      if (Buffer.byteLength(JSON.stringify(response), 'utf8') > PUBLIC_RESPONSE_MAX_BYTES) {
        throw new SearchError('resource-exhausted', 'Este conteúdo excede o limite de resposta.');
      }
      return response;
    } catch (error) {
      if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Não foi possível carregar este conteúdo.');
    }
  });
  const registrations = { listPublicContent, getPublicContentDetail };
  if (staging) {
    registrations.getPublicJob = onCall({ region: 'southamerica-east1', enforceAppCheck: true,
      maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' }, async request => {
      try {
        if (!backendAllowed()) throw new SearchError('failed-precondition', 'Detalhes de vagas indisponíveis.');
        if (typeof request.auth?.uid !== 'string' || !request.auth.uid || request.auth.uid.length > 128 ||
            request.auth.uid.includes('/')) throw new SearchError('unauthenticated', 'Sessão necessária.');
        if (!request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
        const input = request.data;
        if (!input || typeof input !== 'object' || Array.isArray(input) ||
            Object.keys(input).length !== 1 || !Object.hasOwn(input, 'id') || !validDocumentId(input.id)) {
          throw new SearchError('invalid-argument', 'Detalhe público inválido.');
        }
        await admit(request.auth.uid, 'public_job_detail_rate_limits',
          'Aguarde antes de carregar outra vaga.');
        const snapshot = await db.collection('jobs').doc(input.id).get();
        const data = snapshot.data();
        if (!snapshot.exists || !publiclyVisible('jobs', data, Date.now(), isTimestamp)) {
          return { status: 'unavailable' };
        }
        const projected = projectPublic(data, isTimestamp, 'jobs');
        if (projected === null) return { status: 'unavailable' };
        return { status: 'available', id: input.id, data: projected };
      } catch (error) {
        if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
        throw new HttpsError('unavailable', 'Não foi possível carregar esta vaga.');
      }
    });
  }
  return registrations;
}

function registerPublicContent(options) {
  return createPublicContentRegistrar(options);
}

function registerStagingPublicContent(options) {
  return createPublicContentRegistrar({ ...options, staging: true });
}

function registerBetaPublicContent(options) {
  const { betaBackendAllowed } = require('./secure_beta_environment');
  const adminProjectId = options.admin.app().options.projectId;
  const env = options.env || process.env;
  return createPublicContentRegistrar({ ...options, env,
    backendAllowedOverride: () => betaBackendAllowed({ env, adminProjectId }) });
}

module.exports = { registerPublicContent, registerStagingPublicContent, projectPublic,
  registerBetaPublicContent,
  JOB_PUBLIC_FIELDS: Object.freeze([...JOB_FIELDS]), PUBLIC_RESPONSE_MAX_BYTES };
