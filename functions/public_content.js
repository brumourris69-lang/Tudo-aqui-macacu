'use strict';
const crypto = require('node:crypto');
const { secureBackendAllowed } = require('./secure_backend_environment');
const { PUBLIC_COLLECTIONS, publiclyVisible } = require('./content_visibility');
const { SearchError } = require('./business_search');
const { projectPublic, JOB_FIELDS } = require('./public_content_projection');
function registerPublicContent({ admin, onCall, HttpsError }) {
  if (!secureBackendAllowed()) throw new Error('Public listing requires demo emulator or authorized backend configuration');
  const { FieldPath, Timestamp } = require('firebase-admin/firestore');
  const db = admin.firestore();
  const isTimestamp = value => value instanceof Timestamp;
  async function admit(uid, rateCollection, message) {
    const key = crypto.createHash('sha256').update(uid).digest('hex');
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
    if (!secureBackendAllowed()) throw new SearchError('failed-precondition', 'Listagem local indisponível.');
    if (!request.auth?.uid) throw new SearchError('unauthenticated', 'Sessão necessária.');
    if (!request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    const input = request.data;
    if (!input || Object.keys(input).some(k => !['collection', 'limit', 'cursor'].includes(k)) ||
        !PUBLIC_COLLECTIONS.includes(input.collection) ||
        !Number.isInteger(input.limit) || input.limit < 1 || input.limit > 40 ||
        (input.cursor != null && (typeof input.cursor !== 'string' || !input.cursor ||
          input.cursor.length > 1500 || input.cursor.includes('/')))) {
      throw new SearchError('invalid-argument', 'Listagem inválida.');
    }
    await admit(request.auth.uid, 'public_content_rate_limits', 'Aguarde antes de carregar novamente.');
    const items = [];
    let after = input.cursor || null, scanned = 0, exhausted = false;
    while (items.length < input.limit && scanned < 80 && !exhausted) {
      let query = db.collection(input.collection)
        .where(input.collection === 'utilities' ? 'active' : 'published', '==', true);
      if (input.collection === 'notifications') query = query.where('targetEmail', '==', '');
      query = query.orderBy(FieldPath.documentId());
      if (after) query = query.startAfter(after);
      const count = Math.min(input.limit - items.length, 80 - scanned);
      const batch = await query.limit(count).get();
      scanned += batch.size; exhausted = batch.size < count;
      for (const doc of batch.docs) {
        after = doc.id;
        const data = doc.data();
        // Always use current source and server clock; no visibility cache/index.
        if (publiclyVisible(input.collection, data, Date.now(), isTimestamp)) {
          const projected = projectPublic(data, isTimestamp, input.collection);
          if (projected !== null) items.push({ id: doc.id, data: projected });
        }
      }
    }
    return { items, nextCursor: !exhausted && after ? after : null };
  }
  const listPublicContent = onCall({ region: 'southamerica-east1', enforceAppCheck: true,
    maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' }, async request => {
    try { return await list(request); }
    catch (error) {
      if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Não foi possível carregar o conteúdo.');
    }
  });
  const detailCollections = new Set(['establishments', 'routes', 'utilities']);
  const getPublicContentDetail = onCall({ region: 'southamerica-east1', enforceAppCheck: true,
    maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' }, async request => {
    try {
      if (!secureBackendAllowed()) throw new SearchError('failed-precondition', 'Detalhes públicos indisponíveis.');
      if (typeof request.auth?.uid !== 'string' || !request.auth.uid || request.auth.uid.length > 128 ||
          request.auth.uid.includes('/')) throw new SearchError('unauthenticated', 'Sessão necessária.');
      if (!request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
      const input = request.data;
      if (!input || typeof input !== 'object' || Array.isArray(input) ||
          Object.keys(input).length !== 2 || !Object.hasOwn(input, 'collection') ||
          !Object.hasOwn(input, 'id') || !detailCollections.has(input.collection) ||
          !validDocumentId(input.id)) {
        throw new SearchError('invalid-argument', 'Detalhe público inválido.');
      }
      await admit(request.auth.uid, 'public_content_detail_rate_limits',
        'Aguarde antes de carregar outro detalhe.');
      const snapshot = await db.collection(input.collection).doc(input.id).get();
      const data = snapshot.data();
      if (!snapshot.exists || !publiclyVisible(input.collection, data, Date.now(), isTimestamp)) {
        return { status: 'unavailable' };
      }
      const projected = projectPublic(data, isTimestamp, input.collection);
      if (projected === null) return { status: 'unavailable' };
      return { status: 'available', id: input.id, data: projected };
    } catch (error) {
      if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Não foi possível carregar este conteúdo.');
    }
  });
  return { listPublicContent, getPublicContentDetail };
}
module.exports = { registerPublicContent, projectPublic, JOB_PUBLIC_FIELDS: Object.freeze([...JOB_FIELDS]) };
