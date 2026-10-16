'use strict';

const crypto = require('node:crypto');
const { INDEX, SOURCE, ROUTES, NEWS, EVENTS, JOBS, RATE, SearchError, indexId } = require('./business_search');

function createFirestoreStore(db, { FieldPath, FieldValue, Timestamp }) {
  const sourceRef = (collection, id) => db.collection(collection).doc(id);
  const indexRef = (collection, id) => db.collection(INDEX).doc(indexId(collection, id));
  return {
    transaction: (body) => db.runTransaction((tx) => body({
      source: async (collection, id) => (await tx.get(sourceRef(collection, id))).data() || null,
      index: async (collection, id) => (await tx.get(indexRef(collection, id))).data() || null,
      replace: (collection, id, data) => { tx.set(indexRef(collection, id), { ...data, indexedAt: FieldValue.serverTimestamp() }); },
      remove: (collection, id) => { tx.delete(indexRef(collection, id)); },
    })),
    async candidates({ anchor, filter, after, count }) {
      let query = db.collection(INDEX).where('prefixes', 'array-contains', anchor);
      if (filter === 'tourism') query = query.where('type', '==', 'tourism');
      else if (filter === 'news') query = query.where('type', '==', 'news');
      else if (filter === 'events' || filter === 'jobs') query = query.where('type', '==', filter);
      else if (filter !== 'all') query = query.where('group', '==', filter);
      query = query.orderBy(FieldPath.documentId());
      if (after) query = query.startAfter(after);
      const snapshot = await query.limit(count)
        .select('id', 'sourceCollection', 'terms', 'schemaVersion', 'type', 'group').get();
      return snapshot.docs.map((doc) => ({ ...doc.data(), indexId: doc.id }));
    },
    async sources(items) {
      // Batched RPC reduces round trips, not billed document reads.
      const docs = await db.getAll(...items.map(({ sourceCollection, id }) => sourceRef(sourceCollection, id)));
      return docs.map((doc) => doc.data() || null);
    },
    async readSource(collection, id) {
      if (![ROUTES, NEWS, EVENTS, JOBS].includes(collection)) return null;
      return (await sourceRef(collection, id).get()).data() || null;
    },
    async admit(uid, now, scope = 'search') {
      const key = crypto.createHash('sha256').update(scope === 'search' ? uid : `${scope}:${uid}`).digest('hex');
      const ref = db.collection(RATE).doc(key);
      await db.runTransaction(async (tx) => {
        const previous = (await tx.get(ref)).data();
        const minute = Math.floor(now / 60000);
        const used = previous?.minute === minute ? previous.count : 0;
        const limit = scope === 'search' ? 30 : 60;
        const interval = scope === 'search' ? 350 : 200;
        if (used >= limit || (previous && now - previous.lastAt < interval)) {
          throw new SearchError('resource-exhausted', 'Aguarde antes de pesquisar novamente.');
        }
        tx.set(ref, { minute, count: used + 1, lastAt: now,
          expiresAt: Timestamp.fromMillis(now + 86400000) });
      });
    },
  };
}
module.exports = { createFirestoreStore };
