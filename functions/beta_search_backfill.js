'use strict';

const { BETA_PUBLIC_SEARCH_SOURCES } = require('./beta_public_search');

const BETA_BACKFILL_MAX_DOCUMENTS = 500;
const BETA_BACKFILL_MAX_PAGE_SIZE = 100;

function validateCheckpoint(checkpoint) {
  if (checkpoint == null) return { collections: {}, completed: [] };
  if (!checkpoint || typeof checkpoint !== 'object' || Array.isArray(checkpoint) ||
      !checkpoint.collections || typeof checkpoint.collections !== 'object' ||
      Array.isArray(checkpoint.collections) || !Array.isArray(checkpoint.completed)) {
    throw new TypeError('Invalid Beta search backfill checkpoint.');
  }
  const allowed = new Set(BETA_PUBLIC_SEARCH_SOURCES.map(([, collection]) => collection));
  for (const [collection, cursor] of Object.entries(checkpoint.collections)) {
    if (!allowed.has(collection) || (cursor !== null &&
        (typeof cursor !== 'string' || cursor.length < 1 || cursor.length > 1500))) {
      throw new TypeError('Invalid Beta search backfill cursor.');
    }
  }
  if (checkpoint.completed.some((collection) => !allowed.has(collection)) ||
      new Set(checkpoint.completed).size !== checkpoint.completed.length) {
    throw new TypeError('Invalid Beta search backfill completion state.');
  }
  return {
    collections: { ...checkpoint.collections },
    completed: [...checkpoint.completed],
  };
}

/**
 * Reads only the three Beta public source collections and delegates each
 * canonical re-read/upsert to the same idempotent backend used by triggers.
 * The caller owns checkpoint persistence. This helper never writes a cursor
 * document or starts itself, so merely packaging it cannot import hosted data.
 */
async function runBetaSearchBackfill({
  listPage,
  synchronize,
  checkpoint: rawCheckpoint,
  maxDocuments = 100,
  pageSize = 50,
}) {
  if (typeof listPage !== 'function' || typeof synchronize !== 'function') {
    throw new TypeError('Beta search backfill requires page and sync functions.');
  }
  if (!Number.isInteger(maxDocuments) || maxDocuments < 1 || maxDocuments > BETA_BACKFILL_MAX_DOCUMENTS ||
      !Number.isInteger(pageSize) || pageSize < 1 || pageSize > BETA_BACKFILL_MAX_PAGE_SIZE) {
    throw new RangeError('Beta search backfill limits are outside the supported bounds.');
  }

  const state = validateCheckpoint(rawCheckpoint);
  const completed = new Set(state.completed);
  let processed = 0;

  for (const [, collection] of BETA_PUBLIC_SEARCH_SOURCES) {
    if (completed.has(collection)) continue;
    let afterId = state.collections[collection] ?? null;
    while (processed < maxDocuments) {
      const limit = Math.min(pageSize, maxDocuments - processed);
      const page = await listPage({ collection, afterId, limit });
      if (!Array.isArray(page) || page.length > limit) {
        throw new TypeError('Beta search backfill page exceeded its requested bound.');
      }
      let previousId = afterId;
      for (const item of page) {
        if (!item || typeof item.id !== 'string' || item.id.length < 1 || item.id.length > 1500 ||
            (previousId !== null && item.id <= previousId)) {
          throw new TypeError('Beta search backfill page must have unique ascending document IDs.');
        }
        await synchronize(collection, item.id);
        previousId = item.id;
        afterId = item.id;
        state.collections[collection] = afterId;
        processed++;
      }
      if (page.length < limit) {
        completed.add(collection);
        state.collections[collection] = afterId;
        break;
      }
      if (processed >= maxDocuments) break;
    }
    if (processed >= maxDocuments) break;
  }

  state.completed = [...completed];
  return {
    processed,
    complete: BETA_PUBLIC_SEARCH_SOURCES.every(([, collection]) => completed.has(collection)),
    checkpoint: state,
  };
}

function createFirestoreSourcePageReader(db, FieldPath) {
  if (!db || typeof db.collection !== 'function' || !FieldPath ||
      typeof FieldPath.documentId !== 'function') {
    throw new TypeError('Firestore backfill reader requires Admin Firestore and FieldPath.');
  }
  const allowed = new Set(BETA_PUBLIC_SEARCH_SOURCES.map(([, collection]) => collection));
  return async ({ collection, afterId, limit }) => {
    if (!allowed.has(collection) || !Number.isInteger(limit) || limit < 1 || limit > BETA_BACKFILL_MAX_PAGE_SIZE) {
      throw new TypeError('Firestore backfill query is outside the Beta source allowlist.');
    }
    let query = db.collection(collection).orderBy(FieldPath.documentId()).limit(limit);
    if (afterId !== null) query = query.startAfter(afterId);
    const snapshot = await query.select(FieldPath.documentId()).get();
    return snapshot.docs.map((doc) => ({ id: doc.id }));
  };
}

module.exports = {
  BETA_BACKFILL_MAX_DOCUMENTS,
  BETA_BACKFILL_MAX_PAGE_SIZE,
  createFirestoreSourcePageReader,
  runBetaSearchBackfill,
};
