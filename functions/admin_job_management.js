'use strict';

const { authorizeCurrentAdmin } = require('./admin_authorization');
const { Timestamp } = require('firebase-admin/firestore');

const PUBLIC_DEFAULTS = Object.freeze({ title: '', description: '', imageUrl: '', artwork: 0,
  galleryUrls: [], category: '', location: '', address: '', published: false, active: false, expiresAt: null });
const PUBLIC_TEXT = { title: 140, description: 3000, category: 120, location: 240, address: 240 };
const PRIVATE_LIMITS = { contact: 320, phone: 64, whatsapp: 2048, link: 2048,
  instagram: 2048, maps: 2048, mapsUrl: 2048, additionalInfo: 3000 };
const ENVELOPES = { list: ['operation', 'pageSize', 'cursor'], get: ['operation', 'jobId'],
  create: ['operation', 'jobId', 'publicData', 'privateData'],
  update: ['operation', 'jobId', 'publicData', 'privateData'], delete: ['operation', 'jobId'] };
const MIN_CURSOR_SECONDS = -62135596800;
const MAX_CURSOR_SECONDS = 253402300799;

function plain(value) {
  return value !== null && typeof value === 'object' &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function validId(value) {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= 128 &&
    !/[\/\u0000-\u001f\u007f]/.test(value) && value !== '.' && value !== '..' && !/^__.*__$/.test(value);
}

function cursorTime(value) {
  return value !== null && typeof value === 'object' &&
    Number.isSafeInteger(value.seconds) && value.seconds >= MIN_CURSOR_SECONDS && value.seconds <= MAX_CURSOR_SECONDS &&
    Number.isInteger(value.nanoseconds) && value.nanoseconds >= 0 && value.nanoseconds <= 999999999;
}

function httpsUrl(value) {
  if (typeof value !== 'string' || value.length > 2048 || value !== value.trim() || !/^https:\/\//i.test(value)) return false;
  try { const url = new URL(value); return url.protocol === 'https:' && Boolean(url.hostname) && !url.username && !url.password; }
  catch (_) { return false; }
}

function isoDate(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.\d{1,3})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/.exec(value);
  if (!match) return null;
  const year = Number(match[1]), month = Number(match[2]), day = Number(match[3]);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  const date = new Date(value);
  return year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= days[month - 1] &&
    Number.isFinite(date.getTime()) && date.getUTCFullYear() >= 1 && date.getUTCFullYear() <= 9999 ? date : null;
}

function registerAdminJobManagement({ admin, onCall, HttpsError, authorizeAdmin = authorizeCurrentAdmin, now = Date.now }) {
  // Only errors created here may retain their code; SDK messages/details never escape.
  const controlled = new WeakSet();
  function fail(code, message) {
    const error = new HttpsError(code, message);
    controlled.add(error);
    throw error;
  }
  const invalid = () => fail('invalid-argument', 'Invalid administrative job request.');
  function objectKeys(value, allowed) {
    if (!plain(value) || Reflect.ownKeys(value).some(key => typeof key !== 'string' || !allowed.includes(key))) invalid();
  }
  function privateSize(value) {
    if (Buffer.byteLength(JSON.stringify(value), 'utf8') > 16 * 1024) invalid();
  }
  const timestamp = value => Timestamp.fromDate(new Date(value));
  function validate(body) {
    if (!plain(body) || typeof body.operation !== 'string' || !Object.hasOwn(ENVELOPES, body.operation)) invalid();
    objectKeys(body, ENVELOPES[body.operation]);
    if (body.operation === 'list') {
      const size = body.pageSize === undefined ? 30 : body.pageSize;
      if (!Number.isInteger(size) || size < 1 || size > 40) invalid();
      let cursor = null;
      if (Object.hasOwn(body, 'cursor')) {
        if (typeof body.cursor !== 'string' || !/^[A-Za-z0-9_-]+$/.test(body.cursor) || body.cursor.length > 1024) invalid();
        try {
          const bytes = Buffer.from(body.cursor, 'base64url');
          if (bytes.toString('base64url') !== body.cursor) invalid();
          cursor = JSON.parse(bytes.toString('utf8'));
        } catch (_) { invalid(); }
        objectKeys(cursor, ['updatedAt', 'id']);
        objectKeys(cursor.updatedAt, ['seconds', 'nanoseconds']);
        if (!cursorTime(cursor.updatedAt) || !validId(cursor.id)) invalid();
      }
      return { ...body, pageSize: size, cursor };
    }
    if (!validId(body.jobId)) invalid();
    if (body.operation !== 'create' && body.operation !== 'update') return body;
    objectKeys(body.publicData, Object.keys(PUBLIC_DEFAULTS));
    objectKeys(body.privateData, Object.keys(PRIVATE_LIMITS));
    const publicData = { ...body.publicData }, privateData = { ...body.privateData };
    for (const [field, value] of Object.entries(publicData)) {
      if (Object.hasOwn(PUBLIC_TEXT, field)) {
        if (typeof value !== 'string' || value.length > PUBLIC_TEXT[field]) invalid();
      } else if (field === 'imageUrl') { if (value !== '' && !httpsUrl(value)) invalid(); }
      else if (field === 'galleryUrls') {
        if (!Array.isArray(value) || value.length > 20 || !Array.from(value).every(httpsUrl)) invalid();
      } else if (field === 'artwork') { if (!Number.isSafeInteger(value)) invalid(); }
      else if (field === 'published' || field === 'active') { if (typeof value !== 'boolean') invalid(); }
      else if (field === 'expiresAt' && value !== null) {
        const date = isoDate(value);
        if (!date) invalid();
        publicData.expiresAt = timestamp(date.getTime());
      }
    }
    for (const [field, value] of Object.entries(privateData)) {
      if (typeof value !== 'string' || value.length > PRIVATE_LIMITS[field]) invalid();
    }
    privateSize(privateData);
    return { ...body, publicData, privateData };
  }

  function publicProjection(data) {
    const result = {};
    for (const [field, fallback] of Object.entries(PUBLIC_DEFAULTS)) {
      const value = data[field];
      if (field === 'expiresAt') {
        const time = value?.toMillis?.();
        result[field] = Number.isFinite(time) ? new Date(time).toISOString() : null;
      } else if (field === 'galleryUrls') result[field] = Array.isArray(value) ? value.filter(httpsUrl).slice(0, 20) : [];
      else result[field] = typeof value === typeof fallback ? value : fallback;
    }
    return result;
  }
  function privateProjection(data) {
    return Object.fromEntries(Object.keys(PRIVATE_LIMITS).map(field => [field, typeof data[field] === 'string' ? data[field] : '']));
  }

  async function handle(request) {
    if (typeof request?.auth?.uid !== 'string' || !request.auth.uid) fail('unauthenticated', 'Authentication required.');
    if (!request.app) fail('permission-denied', 'App verification required.');
    const header = request.rawRequest?.headers?.authorization ?? request.rawRequest?.get?.('authorization');
    const rawToken = typeof header === 'string' ? /^Bearer ([^\s]+)$/i.exec(header)?.[1] : null;
    if (!rawToken) fail('unauthenticated', 'Authentication required.');
    const db = admin.firestore();
    let authorized;
    try { authorized = await authorizeAdmin(request.auth, { db, firebaseAuth: admin.auth(), rawToken }); }
    catch (error) {
      if (typeof error?.code === 'string' && error.code.startsWith('auth/')) fail('permission-denied', 'Administrative authorization denied.');
      fail('unavailable', 'Administrative authorization unavailable.');
    }
    if (authorized !== true) fail('permission-denied', 'Administrative authorization denied.');
    const body = validate(request.data);
    if (body.operation === 'list') {
      let query = db.collection('jobs').orderBy('updatedAt', 'desc').orderBy('__name__', 'desc');
      if (body.cursor) query = query.startAfter(
        new Timestamp(body.cursor.updatedAt.seconds, body.cursor.updatedAt.nanoseconds), body.cursor.id);
      const snapshot = await query.limit(body.pageSize + 1).get();
      const page = snapshot.docs.slice(0, body.pageSize);
      let nextCursor = null;
      if (snapshot.docs.length > body.pageSize) {
        const last = page[page.length - 1], time = last.data().updatedAt;
        if (!cursorTime(time) || !validId(last.id)) fail('failed-precondition', 'Job pagination metadata requires repair.');
        nextCursor = Buffer.from(JSON.stringify({ updatedAt: { seconds: time.seconds, nanoseconds: time.nanoseconds }, id: last.id })).toString('base64url');
      }
      return { status: 'available', items: page.map(doc => {
        const data = publicProjection(doc.data());
        return { id: doc.id, summary: { title: data.title, published: data.published, active: data.active } };
      }), nextCursor };
    }
    const publicRef = db.collection('jobs').doc(body.jobId), privateRef = db.collection('job_private').doc(body.jobId);
    return db.runTransaction(async transaction => {
      const publicSnapshot = await transaction.get(publicRef);
      const privateSnapshot = await transaction.get(privateRef);
      if (body.operation === 'create') {
        if (publicSnapshot.exists || privateSnapshot.exists) fail('failed-precondition', 'Job already exists; reload before retrying.');
      } else {
        if (!publicSnapshot.exists) fail('not-found', 'Job not found.');
        if (body.operation !== 'delete' && !privateSnapshot.exists) fail('failed-precondition', 'Private job record requires migration.');
      }
      if (body.operation === 'get') return { status: 'available', jobId: body.jobId,
        publicData: publicProjection(publicSnapshot.data()), privateData: privateProjection(privateSnapshot.data()) };
      if (body.operation === 'delete') {
        transaction.delete(publicRef);
        if (privateSnapshot.exists) transaction.delete(privateRef);
        return { status: 'deleted', jobId: body.jobId };
      }
      const clock = now();
      const updatedAt = timestamp(typeof clock === 'number' ? clock : clock.toMillis());
      const privateValue = body.operation === 'update' ? { ...privateSnapshot.data() } : {};
      for (const [field, value] of Object.entries(body.privateData)) {
        if (value === '') delete privateValue[field];
        else privateValue[field] = value;
      }
      privateSize(Object.fromEntries(Object.keys(PRIVATE_LIMITS).filter(field => Object.hasOwn(privateValue, field)).map(field => [field, privateValue[field]])));
      privateValue.updatedAt = updatedAt;
      privateValue.schemaVersion = 1;
      if (body.operation === 'create') {
        transaction.create(publicRef, { ...body.publicData, updatedAt });
        transaction.create(privateRef, privateValue);
      } else {
        transaction.update(publicRef, { ...body.publicData, updatedAt });
        // Replace the transaction snapshot to remove explicit empty fields without
        // deleting omitted fields; a concurrent change retries the transaction.
        transaction.set(privateRef, privateValue);
      }
      return { status: body.operation === 'create' ? 'created' : 'updated', jobId: body.jobId };
    });
  }

  const manageAdminJob = onCall({ region: 'southamerica-east1', enforceAppCheck: true }, async request => {
    try { return await handle(request); }
    catch (error) {
      if (controlled.has(error)) throw error;
      const operation = typeof request?.data?.operation === 'string' &&
        Object.hasOwn(ENVELOPES, request.data.operation) ? request.data.operation : 'unknown';
      const errorName = /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(error?.name || '') ? error.name : 'Error';
      const rawCode = error?.code;
      const errorCode = (typeof rawCode === 'string' && /^[A-Za-z0-9_/-]{1,40}$/.test(rawCode)) ||
        (Number.isInteger(rawCode) && rawCode >= 0 && rawCode <= 99) ? rawCode : 'unknown';
      const firstFrame = String(error?.stack || '').split('\n').find(line => /^\s+at /.test(line));
      const frameMatch = firstFrame && /\bat ([A-Za-z0-9_.$<>]+) \((?:.*[\\/])?([^\\/():]+\.js):(\d+):\d+\)/.exec(firstFrame);
      const errorOrigin = frameMatch ? `${frameMatch[1]}@${frameMatch[2]}:${frameMatch[3]}` : 'unknown';
      // Keep actionable failure metadata while never logging request values or SDK messages.
      console.error('manageAdminJob failed', { operation, errorName, errorCode, errorOrigin });
      const code = error?.code;
      if (code === 10 || code === 'aborted') fail('aborted', 'Job operation conflicted; reload before retrying.');
      if (code === 14 || code === 4 || code === 'unavailable' || code === 'deadline-exceeded') fail('unavailable', 'Job service unavailable; reload before retrying.');
      fail('internal', 'Administrative job operation failed.');
    }
  });
  return { manageAdminJob };
}

module.exports = { registerAdminJobManagement };
