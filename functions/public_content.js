'use strict';
const crypto = require('node:crypto');
const { secureBackendAllowed } = require('./secure_backend_environment');
const { PUBLIC_COLLECTIONS, publiclyVisible } = require('./content_visibility');
const { SearchError } = require('./business_search');
const FIELDS = new Set(('title name description shortDescription category subcategory location address ' +
  'artwork icon iconKey imageUrl logoUrl galleryUrls link url maps mapsUrl whatsapp phone instagram ' +
  'hours services products additionalInfo promotionTitle promotionDescription featured open ' +
  'published active expiresAt updatedAt createdAt eventDate date startsAt contact company salary ' +
  'type employmentType options order destination destinationType discount price originalPrice ' +
  'code business businessId establishmentId validUntil rules buttonLabel label subtitle').split(' '));
function projectPublic(data, isTimestamp) {
  function encode(value, depth = 0) {
    if (isTimestamp(value)) return { _publicTimestamp: [value.seconds, value.nanoseconds] };
    if (typeof value === 'string') return value.slice(0, 4096);
    if (typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value))) return value;
    if (Array.isArray(value) && depth < 2) return value.slice(0, 40).map(v => encode(v, depth + 1));
    return null; // No arbitrary nested admin/profile maps.
  }
  return Object.fromEntries(Object.entries(data).filter(([key]) => FIELDS.has(key)).map(([key, value]) => [key, encode(value)]));
}
function registerPublicContent({ admin, onCall, HttpsError }) {
  if (!secureBackendAllowed()) throw new Error('Public listing requires demo emulator or authorized backend configuration');
  const { FieldPath, Timestamp } = require('firebase-admin/firestore');
  const db = admin.firestore();
  const isTimestamp = value => value instanceof Timestamp;
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
    const key = crypto.createHash('sha256').update(request.auth.uid).digest('hex');
    const rate = db.collection('public_content_rate_limits').doc(key);
    await db.runTransaction(async tx => {
      const previous = (await tx.get(rate)).data();
      const minute = Math.floor(Date.now() / 60000);
      const count = previous?.minute === minute ? previous.count : 0;
      if (count >= 120) throw new SearchError('resource-exhausted', 'Aguarde antes de carregar novamente.');
      tx.set(rate, { minute, count: count + 1, expiresAt: Timestamp.fromMillis(Date.now() + 86400000) });
    });
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
          items.push({ id: doc.id, data: projectPublic(data, isTimestamp) });
        }
      }
    }
    return { items, nextCursor: !exhausted && after ? after : null };
  }
  return { listPublicContent: onCall({ region: 'southamerica-east1', enforceAppCheck: true,
    maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' }, async request => {
    try { return await list(request); }
    catch (error) {
      if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Não foi possível carregar o conteúdo.');
    }
  }) };
}
module.exports = { registerPublicContent, projectPublic };
