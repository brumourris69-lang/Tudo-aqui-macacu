const STATES = Object.freeze(['pending', 'processing', 'synced', 'superseded', 'dead_letter']);
const TERMINAL_STATES = new Set(['synced', 'superseded', 'dead_letter']);
const SAFE_ERROR_CODES = new Set([
  'firestore_unavailable', 'catalog_unavailable', 'unknown_transient',
  'permanent_failure', 'event_inconsistent', 'catalog_conflict',
  'invalid_catalog_result', 'retry_exhausted',
]);
const OPERATION_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const COMMERCE_CATEGORIES = new Set([
  'Comércio', 'Onde comer?', 'Saúde', 'Imóveis', 'Veículos', 'Pets', 'Beleza',
  'Academias', 'Educação', 'Hospedagem', 'Tecnologia',
]);
const SERVICE_CATEGORIES = new Set(['Serviços', 'Profissionais']);
export const DEFAULT_RETRY_POLICY = Object.freeze({ baseDelayMs: 1_000, maximumDelayMs: 60_000, maxAttempts: 8 });

export const OUTBOX_STATES = STATES;

export function calculateRetryDelayMs(attemptCount, policy = DEFAULT_RETRY_POLICY) {
  validateRetryPolicy(policy);
  if (!Number.isSafeInteger(attemptCount) || attemptCount < 1) {
    throw new TypeError('attemptCount must be a positive safe integer');
  }
  const exponent = Math.min(attemptCount - 1, 52);
  return Math.min(policy.maximumDelayMs, policy.baseDelayMs * (2 ** exponent));
}

/**
 * Builds an explicit V2 catalog row from the canonical Firestore document.
 * Unknown/private fields are never copied. Validation and persistence remain
 * the responsibility of the eventual Firestore and PostgreSQL adapters.
 */
export function projectCanonicalEstablishment(id, source, event) {
  if (!isFirestoreDocumentId(id) || !isPlainObject(source) || !validEvent(event)) return null;
  const name = source.name ?? source.title;
  const category = source.category;
  if (typeof name !== 'string' || name.trim() === '') return null;
  const categoryGroup = COMMERCE_CATEGORIES.has(category) ? 'commerce' :
    SERVICE_CATEGORIES.has(category) ? 'services' : null;
  if (!categoryGroup) return null;

  const string = (value, fallback = '') => value == null ? fallback :
    (typeof value === 'string' ? value : null);
  const array = (value) => value == null ? [] :
    (Array.isArray(value) && value.every((item) => typeof item === 'string') ? [...value] : null);
  const bool = (value, fallback) => value == null ? fallback :
    (typeof value === 'boolean' ? value : null);
  const timestamp = (value) => {
    if (value == null) return null;
    return normalizeTimestamp(value) ?? undefined;
  };

  const summary = string(source.shortDescription ?? source.description, '');
  const subcategory = string(source.subcategory, '');
  const location = string(source.location, null);
  const artwork = source.artwork == null ? 0 : source.artwork;
  const imageUrl = string(source.imageUrl, '');
  const logoUrl = string(source.logoUrl, '');
  const galleryUrls = array(source.galleryUrls);
  const featured = bool(source.featured, false);
  const isOpen = bool(source.open, true);
  const mapsUrl = string(source.mapsUrl ?? source.maps, '');
  const hours = string(source.hours, '');
  const services = array(source.services);
  const products = array(source.products);
  const additionalInfo = string(source.additionalInfo, '');
  const promotionTitle = string(source.promotionTitle, '');
  const promotionDescription = string(source.promotionDescription, '');
  const expiresAt = timestamp(source.expiresAt);
  const deletedAt = timestamp(source.deletedAt);
  const approvedContacts = source.publicContactApproved === true;
  const phone = approvedContacts ? string(source.phone, null) : null;
  const whatsapp = approvedContacts ? string(source.whatsapp, null) : null;
  const instagram = approvedContacts ? string(source.instagram, null) : null;
  const catalogVersion = source.catalogVersion;
  const operationId = source.outboxOperationId;

  if ([summary, subcategory, imageUrl, logoUrl, mapsUrl, hours, additionalInfo,
    promotionTitle, promotionDescription].includes(null) || location === undefined ||
    galleryUrls === null || services === null || products === null ||
    featured === null || isOpen === null || expiresAt === undefined || deletedAt === undefined ||
    phone === undefined || whatsapp === undefined || instagram === undefined ||
    !Number.isSafeInteger(artwork) || artwork < 0 || artwork > 18 ||
    catalogVersion !== event.version || operationId !== event.operationId) return null;

  const row = {
    id,
    content_kind: 'establishment',
    category_group: categoryGroup,
    name: name.trim(),
    summary,
    category,
    subcategory,
    location,
    artwork,
    image_url: imageUrl,
    logo_url: logoUrl,
    gallery_urls: galleryUrls,
    featured,
    is_open: isOpen,
    maps_url: mapsUrl,
    hours,
    services,
    products,
    additional_info: additionalInfo,
    promotion_title: promotionTitle,
    promotion_description: promotionDescription,
    public_contact_approved: approvedContacts,
    phone,
    whatsapp,
    instagram,
    published: source.published === true,
    active: source.active === true,
    expires_at: expiresAt,
    deleted_at: deletedAt,
    catalog_version: event.version,
    outbox_operation_id: event.operationId,
  };
  return Object.freeze(row);
}

/**
 * Coordinates the future protocol through atomic adapter operations.
 * The adapters must implement each lease/state transition transactionally;
 * this module itself never connects to Firebase or Supabase.
 */
export function createCatalogOutboxProtocol({
  outbox,
  canonical,
  catalog,
  now = Date.now,
  createLeaseToken,
  leaseDurationMs = 30_000,
  retryPolicy = DEFAULT_RETRY_POLICY,
}) {
  if (!outbox || !canonical || !catalog || typeof now !== 'function' ||
    typeof createLeaseToken !== 'function' || !Number.isSafeInteger(leaseDurationMs) || leaseDurationMs < 1) {
    throw new TypeError('Outbox protocol adapters and clock are required');
  }
  for (const [adapter, methods] of [
    [outbox, ['inspect', 'claim', 'readClaimed', 'renewLease', 'transition']],
    [canonical, ['get']],
    [catalog, ['applyProjection', 'applyTombstone']],
  ]) {
    if (methods.some((method) => typeof adapter[method] !== 'function')) {
      throw new TypeError('Outbox protocol adapter is incomplete');
    }
  }
  validateRetryPolicy(retryPolicy);

  async function acquireLease(eventId, workerId) {
    if (typeof eventId !== 'string' || eventId.length === 0 ||
      typeof workerId !== 'string' || workerId.trim() === '') {
      return { acquired: false, reason: 'invalid_request' };
    }
    const time = safeNow(now);
    let snapshot;
    try { snapshot = await outbox.inspect(eventId); } catch { return { acquired: false, reason: 'unavailable' }; }
    if (!snapshot) return { acquired: false, reason: 'missing' };
    // V2 is a strict persisted contract and must not be "repaired" by claiming
    // an incomplete document. Preserve V1's historical quarantine behavior:
    // malformed legacy payloads can be claimed and moved to dead_letter.
    if (![1, 2].includes(snapshot.schemaVersion) ||
      (snapshot.schemaVersion === 2 && (!validEvent(snapshot) || snapshot.operationId !== eventId))) {
      return { acquired: false, reason: 'invalid_event' };
    }
    if (TERMINAL_STATES.has(snapshot.state)) return { acquired: false, reason: 'terminal' };
    if (snapshot.nextAttemptAt != null) {
      const retryAt = timestampMillis(snapshot.nextAttemptAt);
      if (retryAt === null) return { acquired: false, reason: 'invalid_event' };
      if (retryAt > time) return { acquired: false, reason: 'retry_scheduled' };
    }
    if (!Number.isSafeInteger(snapshot.version) || snapshot.version < 1 ||
      !STATES.includes(snapshot.state)) return { acquired: false, reason: 'invalid_event' };
    const leaseToken = createLeaseToken();
    if (typeof leaseToken !== 'string' || leaseToken.length < 16 || leaseToken.length > 256) {
      return { acquired: false, reason: 'invalid_request' };
    }
    let claimed;
    try {
      claimed = await outbox.claim(eventId, {
        workerId,
        leaseToken,
        expectedState: snapshot.state,
        expectedVersion: snapshot.version,
        now: time,
        leaseExpiresAt: time + leaseDurationMs,
      });
    } catch {
      return { acquired: false, reason: 'unavailable' };
    }
    if (!claimed?.claimed) return { acquired: false, reason: SAFE_CLAIM_REASONS.has(claimed?.reason) ? claimed.reason : 'changed' };
    return Object.freeze({
      acquired: true,
      eventId,
      workerId,
      leaseToken,
      expectedVersion: snapshot.version,
      leaseExpiresAt: time + leaseDurationMs,
    });
  }

  async function renewLease(lease, durationMs = leaseDurationMs) {
    if (!validLease(lease) || !Number.isSafeInteger(durationMs) || durationMs < 1) return false;
    const time = safeNow(now);
    try {
      return await outbox.renewLease({
        ...lease,
        expectedState: 'processing',
        expectedVersion: lease.expectedVersion,
        now: time,
        leaseExpiresAt: time + durationMs,
      }) === true;
    } catch {
      return false;
    }
  }

  async function processOnce(eventId, workerId) {
    const lease = await acquireLease(eventId, workerId);
    if (!lease.acquired) {
      const state = lease.reason === 'unavailable' ? 'unavailable' : 'not_processed';
      return Object.freeze({ state, reason: lease.reason });
    }
    let event;
    try { event = await outbox.readClaimed(lease); } catch (error) { return handleFailure(lease, safeFailureCode(error)); }
    if (!event || !validClaimedEvent(eventId, event, lease)) return complete(lease, 'dead_letter', { lastErrorCode: 'event_inconsistent' });
    if (event.attemptCount > retryPolicy.maxAttempts) {
      return complete(lease, 'dead_letter', { lastErrorCode: 'retry_exhausted' });
    }

    let source;
    try { source = await canonical.get(event.entityId); } catch (error) { return handleFailure(lease, safeFailureCode(error)); }
    if (!source) return complete(lease, 'dead_letter', { lastErrorCode: 'event_inconsistent' });

    const sourceVersion = source.catalogVersion;
    if (!Number.isSafeInteger(sourceVersion) || sourceVersion < 1) {
      return complete(lease, 'dead_letter', { lastErrorCode: 'event_inconsistent' });
    }
    if (sourceVersion > event.version) return complete(lease, 'superseded', {});
    if (sourceVersion < event.version || source.outboxOperationId !== event.operationId) {
      return complete(lease, 'dead_letter', { lastErrorCode: 'event_inconsistent' });
    }

    let writeResult;
    try {
      if (source.deletedAt != null) {
        const deletedAt = normalizeTimestamp(source.deletedAt);
        if (deletedAt === null) return complete(lease, 'dead_letter', { lastErrorCode: 'event_inconsistent' });
        writeResult = await catalog.applyTombstone(Object.freeze({
          id: event.entityId,
          catalog_version: event.version,
          outbox_operation_id: event.operationId,
          deleted_at: deletedAt,
        }));
      } else {
        const projection = projectCanonicalEstablishment(event.entityId, source, event);
        if (!projection) return complete(lease, 'dead_letter', { lastErrorCode: 'event_inconsistent' });
        writeResult = await catalog.applyProjection(projection);
      }
    } catch (error) {
      return handleFailure(lease, safeFailureCode(error));
    }
    if (writeResult?.result === 'stale') return complete(lease, 'superseded', {});
    if (writeResult?.result === 'conflict' || writeResult?.result === 'tombstoned') {
      return complete(lease, 'dead_letter', { lastErrorCode: 'catalog_conflict' });
    }
    if (writeResult?.result !== 'applied' && writeResult?.result !== 'duplicate') {
      return complete(lease, 'dead_letter', { lastErrorCode: 'invalid_catalog_result' });
    }

    // A catalog acknowledgement is valid only after the adapter confirms an
    // applied write or an idempotent duplicate. If this state write fails, the
    // next lease holder safely replays the same version and operation ID.
    const acknowledged = await transition(lease, {
      state: 'synced',
      syncedAt: safeNow(now),
      lastErrorCode: null,
      nextAttemptAt: null,
    });
    if (acknowledged === false) return Object.freeze({ state: 'lease_lost' });
    if (acknowledged === null) return Object.freeze({ state: 'ack_pending' });
    return Object.freeze({ state: 'synced', write: writeResult.result });
  }

  async function complete(lease, state, metadata) {
    const changed = await transition(lease, { state, ...metadata, nextAttemptAt: null });
    return Object.freeze({ state: changed === true ? state : changed === false ? 'lease_lost' : 'state_unconfirmed' });
  }

  async function handleFailure(lease, code) {
    const event = await outbox.readClaimed(lease).catch(() => null);
    if (!event) return Object.freeze({ state: 'lease_lost' });
    const terminal = event.attemptCount >= retryPolicy.maxAttempts || code === 'permanent_failure';
    const state = terminal ? 'dead_letter' : 'pending';
    const nextAttemptAt = terminal ? null : safeNow(now) + calculateRetryDelayMs(event.attemptCount, retryPolicy);
    const changed = await transition(lease, {
      state,
      lastErrorCode: code,
      nextAttemptAt,
    });
    if (changed !== true) return Object.freeze({ state: changed === false ? 'lease_lost' : 'state_unconfirmed' });
    return Object.freeze({ state, errorCode: code, ...(nextAttemptAt == null ? {} : { nextAttemptAt }) });
  }

  async function transition(lease, patch) {
    try {
      return await outbox.transition({
        ...lease,
        expectedState: 'processing',
        expectedVersion: lease.expectedVersion,
        now: safeNow(now),
        patch,
      }) === true;
    } catch {
      return null;
    }
  }

  return Object.freeze({ acquireLease, renewLease, processOnce });
}

const SAFE_CLAIM_REASONS = new Set(['busy', 'retry_scheduled', 'terminal', 'missing', 'changed', 'invalid_event']);

function validLease(value) {
  return Boolean(value && value.acquired === true && typeof value.eventId === 'string' &&
    typeof value.workerId === 'string' && typeof value.leaseToken === 'string' &&
    Number.isSafeInteger(value.expectedVersion) && value.expectedVersion > 0);
}

function validClaimedEvent(id, event, lease) {
  return validEvent(event) && event.operationId === id && event.state === 'processing' &&
    event.version === lease.expectedVersion && event.attemptCount > 0 &&
    typeof event.leaseToken === 'string' && event.leaseToken === lease.leaseToken &&
    event.workerId === lease.workerId;
}

function isFirestoreDocumentId(value) {
  return typeof value === 'string' && value.length > 0 && !value.includes('/') &&
    new TextEncoder().encode(value).byteLength <= 1500 && value !== '.' && value !== '..' &&
    (!value.startsWith('__') || !value.endsWith('__') || /^__id\d+__$/u.test(value));
}

function validEvent(event) {
  if (!isPlainObject(event) || ![1, 2].includes(event.schemaVersion) ||
    typeof event.operationId !== 'string' || !OPERATION_ID_PATTERN.test(event.operationId) ||
    event.entityType !== 'establishment' || !isFirestoreDocumentId(event.entityId) ||
    typeof event.authorUid !== 'string' || event.authorUid.length === 0 || event.authorUid.length > 128 ||
    !Number.isSafeInteger(event.version) || event.version < 1 || event.version > 2_147_483_647 ||
    event.operation !== 'reconcile' || !STATES.includes(event.state) ||
    !Number.isSafeInteger(event.attemptCount) || event.attemptCount < 0) return false;
  if (event.schemaVersion === 1) return true;
  return validV2Event(event);
}

/** Exposes the persisted V1/V2 validator to trusted server-side adapters. */
export function isValidCatalogOutboxEvent(event) {
  return validEvent(event);
}

const V2_EVENT_KEYS = new Set([
  'schemaVersion', 'operationId', 'entityType', 'entityId', 'authorUid', 'version', 'operation',
  'state', 'attemptCount', 'workerId', 'leaseToken', 'leaseExpiresAt', 'nextAttemptAt',
  'lastErrorCode', 'syncedAt', 'createdAt', 'updatedAt',
]);
const V2_LIFECYCLE_KEYS = [
  'workerId', 'leaseToken', 'leaseExpiresAt', 'nextAttemptAt', 'lastErrorCode', 'syncedAt',
];

function validV2Event(event) {
  if (Object.keys(event).some((key) => !V2_EVENT_KEYS.has(key)) ||
    [...V2_EVENT_KEYS].some((key) => !Object.hasOwn(event, key)) ||
    !isTimestamp(event.createdAt) || !isTimestamp(event.updatedAt) ||
    V2_LIFECYCLE_KEYS.some((key) => !Object.hasOwn(event, key)) ||
    !(event.workerId === null || (typeof event.workerId === 'string' && event.workerId.length > 0 && event.workerId.length <= 128)) ||
    !(event.leaseToken === null || (typeof event.leaseToken === 'string' && event.leaseToken.length >= 16 && event.leaseToken.length <= 256)) ||
    !(event.leaseExpiresAt === null || isTimestamp(event.leaseExpiresAt)) ||
    !(event.nextAttemptAt === null || isTimestamp(event.nextAttemptAt)) ||
    !(event.lastErrorCode === null || SAFE_ERROR_CODES.has(event.lastErrorCode)) ||
    !(event.syncedAt === null || isTimestamp(event.syncedAt))) return false;

  const leaseIsClear = event.workerId === null && event.leaseToken === null && event.leaseExpiresAt === null;
  switch (event.state) {
    case 'pending':
      return event.syncedAt === null && leaseIsClear &&
        (event.attemptCount === 0
          ? event.nextAttemptAt === null && event.lastErrorCode === null
          : event.nextAttemptAt !== null && event.lastErrorCode !== null);
    case 'processing':
      return event.attemptCount > 0 && event.workerId !== null && event.leaseToken !== null &&
        event.leaseExpiresAt !== null && event.nextAttemptAt === null && event.syncedAt === null;
    case 'synced':
      return event.attemptCount > 0 && leaseIsClear && event.nextAttemptAt === null &&
        event.lastErrorCode === null && event.syncedAt !== null;
    case 'superseded':
      return event.attemptCount > 0 && leaseIsClear && event.nextAttemptAt === null && event.syncedAt === null;
    case 'dead_letter':
      return event.attemptCount > 0 && leaseIsClear && event.nextAttemptAt === null &&
        event.lastErrorCode !== null && event.syncedAt === null;
    default:
      return false;
  }
}

function isTimestamp(value) {
  // Numeric epoch values are an internal clock representation, not persisted
  // Firestore Timestamp values. Accept Date/Timestamp objects in V2 documents.
  return typeof value !== 'number' && timestampMillis(value) !== null;
}

function timestampMillis(value) {
  if (value instanceof Date) {
    const milliseconds = value.getTime();
    return Number.isSafeInteger(milliseconds) && milliseconds >= 0 ? milliseconds : null;
  }
  if (Number.isSafeInteger(value) && value >= 0) return value;
  if (!value || typeof value !== 'object') return null;
  if (Number.isSafeInteger(value.seconds) && Number.isInteger(value.nanoseconds) &&
    value.seconds >= 0 && value.nanoseconds >= 0 && value.nanoseconds < 1_000_000_000) {
    const milliseconds = value.seconds * 1_000 + Math.floor(value.nanoseconds / 1_000_000);
    return Number.isSafeInteger(milliseconds) ? milliseconds : null;
  }
  return null;
}

function normalizeTimestamp(value) {
  if (typeof value !== 'string') return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|([+-])(\d{2}):(\d{2}))$/u.exec(value);
  if (!match) return null;
  const [, yearText, monthText, dayText, hourText, minuteText, secondText, , , offsetHourText, offsetMinuteText] = match;
  const year = Number(yearText), month = Number(monthText), day = Number(dayText);
  const hour = Number(hourText), minute = Number(minuteText), second = Number(secondText);
  if (year < 1 || month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59 ||
    (offsetHourText !== undefined && (Number(offsetHourText) > 23 || Number(offsetMinuteText) > 59))) return null;
  const calendar = new Date(0);
  calendar.setUTCHours(0, 0, 0, 0);
  calendar.setUTCFullYear(year, month - 1, day);
  if (calendar.getUTCFullYear() !== year || calendar.getUTCMonth() !== month - 1 || calendar.getUTCDate() !== day ||
    !Number.isFinite(Date.parse(value))) return null;
  return new Date(value).toISOString();
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function safeNow(clock) {
  const value = clock();
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError('clock must return epoch milliseconds');
  return value;
}

function safeFailureCode(error) {
  if (error?.permanent === true) return 'permanent_failure';
  const code = typeof error?.code === 'string' ? error.code : '';
  return SAFE_ERROR_CODES.has(code) && code.endsWith('_unavailable') ? code : 'unknown_transient';
}

function validateRetryPolicy(policy) {
  if (!policy || !Number.isSafeInteger(policy.baseDelayMs) || policy.baseDelayMs < 1 ||
    !Number.isSafeInteger(policy.maximumDelayMs) || policy.maximumDelayMs < policy.baseDelayMs ||
    !Number.isSafeInteger(policy.maxAttempts) || policy.maxAttempts < 1) {
    throw new TypeError('retry policy is invalid');
  }
}
