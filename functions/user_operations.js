'use strict';
const crypto = require('node:crypto');
const { secureBackendAllowed } = require('./secure_backend_environment');
const { SearchError } = require('./business_search');
const { publiclyVisible } = require('./content_visibility');
const ACTIONS = new Set(('business_open business_whatsapp business_phone business_map business_instagram business_share ' +
  'favorite_add favorite_remove external_click notification_open utility_open coupon_open content_share tourism_open event_open alert_open ' +
  'banner_view ad_view offer_open classified_view classified_contact adoption_view adoption_contact').split(' '));
// [per minute, per UTC day]. Security budgets, not claims of trusted analytics.
const LIMITS = { contact: [5, 20], proposal: [3, 10], review: [5, 20], metric: [120, 2000],
  vote: [30, 300], favorite: [60, 500], unfavorite: [60, 500], device: [10, 30], removeDevice: [10, 30] };
const FIELDS = { contact: ['name', 'contact', 'message'], proposal: ['name', 'contact', 'details'],
  review: ['businessId', 'message', 'stars'], metric: ['action', 'target', 'targetType'],
  vote: ['pollId', 'option'], favorite: ['id', 'name'], unfavorite: ['id'],
  device: ['token', 'platform'], removeDevice: ['token'] };
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
function invalid() { throw new SearchError('invalid-argument', 'Dados inválidos.'); }
function prepareOperation(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).some(k => !['operation', 'payload'].includes(k)) ||
      !Object.hasOwn(FIELDS, input.operation)) invalid();
  const { operation, payload } = input;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload) ||
      Object.keys(payload).length !== FIELDS[operation].length ||
      Object.keys(payload).some(k => !FIELDS[operation].includes(k))) invalid();
  const result = {};
  function str(key, max, required = false, identifier = false) {
    const value = payload[key];
    if (typeof value !== 'string' || value.length > max || (required && !value.trim()) ||
        (identifier && (value.includes('/') || value === '.' || value === '..'))) invalid();
    result[key] = value.trim();
  }
  switch (operation) {
    case 'contact': str('name', 120); str('contact', 180); str('message', 2000, true); break;
    case 'proposal': str('name', 160, true); str('contact', 180); str('details', 2000, true); break;
    case 'review':
      str('businessId', 200, true, true); str('message', 2000, true);
      if (!Number.isInteger(payload.stars) || payload.stars < 1 || payload.stars > 5) invalid();
      result.stars = payload.stars; break;
    case 'metric':
      str('action', 60, true); str('target', 200); str('targetType', 60);
      if (!ACTIONS.has(result.action)) invalid(); break;
    case 'vote': str('pollId', 200, true, true); str('option', 200, true); break;
    case 'favorite': str('id', 200, true, true); str('name', 200, true); break;
    case 'unfavorite': str('id', 200, true, true); break;
    case 'device':
      str('token', 1500, true, true); str('platform', 20, true);
      if (!['android', 'ios', 'web'].includes(result.platform)) invalid(); break;
    case 'removeDevice': str('token', 1500, true, true); break;
  }
  return { operation, payload: result };
}
function registerUserOperations({ admin, onCall, HttpsError }) {
  if (!secureBackendAllowed()) throw new Error('User operations requires demo emulator or authorized backend configuration');
  const { FieldValue, Timestamp } = require('firebase-admin/firestore');
  const db = admin.firestore();
  async function submit(request) {
    if (!secureBackendAllowed()) throw new SearchError('failed-precondition', 'Operação local indisponível.');
    const uid = request.auth?.uid;
    if (!uid || request.auth.token?.firebase?.sign_in_provider === 'anonymous') {
      throw new SearchError('unauthenticated', 'Entre com uma conta cadastrada.');
    }
    if (!request.app?.appId) throw new SearchError('failed-precondition', 'Aplicativo não validado.');
    const { operation: op, payload: p } = prepareOperation(request.data);
    const key = digest(`${uid}:${op}`), rateRef = db.collection('user_operation_limits').doc(key);
    const creates = { contact: 'contact_messages', proposal: 'business_proposals', review: 'reviews', metric: 'metrics' };
    const dedupRef = db.collection('user_operation_dedup').doc(digest(`${uid}:${op}:${JSON.stringify(p)}`));
    const newRef = creates[op] ? db.collection(creates[op]).doc() : null;
    const user = db.collection('users').doc(uid);
    const target = op === 'vote' ? db.collection('polls').doc(p.pollId).collection('votes').doc(uid)
      : ['favorite', 'unfavorite'].includes(op) ? user.collection('favorites').doc(p.id)
        : ['device', 'removeDevice'].includes(op) ? user.collection('devices').doc(p.token) : newRef;
    return db.runTransaction(async tx => {
      const now = Date.now(), minute = Math.floor(now / 60000), day = Math.floor(now / 86400000);
      const previous = (await tx.get(rateRef)).data();
      const minutes = previous?.minute === minute ? previous.minutes : 0;
      const days = previous?.day === day ? previous.days : 0;
      if (minutes >= LIMITS[op][0] || days >= LIMITS[op][1]) {
        throw new SearchError('resource-exhausted', 'Limite atingido. Aguarde para tentar novamente.');
      }
      const duplicate = creates[op] ? (await tx.get(dedupRef)).data() : null;
      let source;
      if (op === 'vote' || op === 'review') {
        source = (await tx.get(db.collection(op === 'vote' ? 'polls' : 'establishments').doc(p.pollId || p.businessId))).data();
        if (!publiclyVisible(op === 'vote' ? 'polls' : 'establishments', source, Date.now(), value => value instanceof Timestamp)) {
          throw new SearchError('failed-precondition', 'Conteúdo indisponível.');
        }
        if (op === 'vote' && (!Array.isArray(source.options) || !source.options.includes(p.option))) invalid();
        if (op === 'review' && (typeof (source.name ?? source.title) !== 'string' || !(source.name ?? source.title).trim())) invalid();
      }
      const existing = creates[op] ? null : (await tx.get(target)).data();
      tx.set(rateRef, { minute, minutes: minutes + 1, day, days: days + 1,
        expiresAt: Timestamp.fromMillis(now + 2 * 86400000) });
      if (duplicate?.expiresAt instanceof Timestamp && duplicate.expiresAt.toMillis() > now) {
        return { id: duplicate.id, duplicate: true };
      }
      const stamp = FieldValue.serverTimestamp();
      let data;
      switch (op) {
        case 'contact': data = { ...p, userId: uid, email: request.auth.token.email ?? '', read: false, createdAt: stamp }; break;
        case 'proposal': data = { ...p, userId: uid, status: 'pending', createdAt: stamp }; break;
        case 'review': data = { ...p, business: (source.name ?? source.title).slice(0, 180), userId: uid, status: 'pending', createdAt: stamp }; break;
        case 'metric': data = { ...p, userId: uid, createdAt: stamp }; break;
        case 'vote': data = { option: p.option, updatedAt: stamp }; break;
        case 'favorite': data = { ...p, updatedAt: stamp }; break;
        case 'device': data = { ...p, active: true, updatedAt: stamp }; break;
        case 'unfavorite': case 'removeDevice':
          if (existing) tx.delete(target);
          return { id: target.id, duplicate: !existing };
      }
      if (existing && Object.entries(data).filter(([k]) => k !== 'updatedAt').every(([k, v]) => existing[k] === v)) {
        return { id: target.id, duplicate: true };
      }
      tx.set(target, data);
      if (creates[op]) tx.set(dedupRef, { id: target.id, expiresAt: Timestamp.fromMillis(now + (op === 'metric' ? 5000 : 60000)) });
      return { id: target.id, duplicate: false };
    });
  }
  return { submitUserOperation: onCall({ region: 'southamerica-east1', enforceAppCheck: true,
    maxInstances: 2, concurrency: 4, timeoutSeconds: 15, memory: '256MiB' }, async request => {
    try { return await submit(request); }
    catch (error) {
      if (error instanceof SearchError) throw new HttpsError(error.code, error.message);
      throw new HttpsError('unavailable', 'Não foi possível concluir a operação.');
    }
  }) };
}
module.exports = { prepareOperation, registerUserOperations, LIMITS };
