'use strict';

const crypto = require('node:crypto');
const { INDEX, SOURCE, RATE, SearchError } = require('./business_search');

function createFirestoreStore(db, { FieldPath, FieldValue, Timestamp }) {
  const sourceRef = (id) => db.collection(SOURCE).doc(id);
  const indexRef = (id) => db.collection(INDEX).doc(`establishments__${id}`);
  return {
    transaction: (body) => db.runTransaction((tx) => body({
      source: async (id) => (await tx.get(sourceRef(id))).data() || null,
      index: async (id) => (await tx.get(indexRef(id))).data() || null,
      replace: (id, data) => { tx.set(indexRef(id), { ...data, indexedAt: FieldValue.serverTimestamp() }); },
      remove: (id) => { tx.delete(indexRef(id)); },
    })),
    async candidates({ anchor, filter, after, count }) {
      let query = db.collection(INDEX).where('prefixes', 'array-contains', anchor);
      if (filter !== 'all') query = query.where('group', '==', filter);
      query = query.orderBy(FieldPath.documentId());
      if (after) query = query.startAfter(after);
      const snapshot = await query.limit(count)
        .select('id', 'sourceCollection', 'terms', 'schemaVersion').get();
      return snapshot.docs.map((doc) => ({ ...doc.data(), indexId: doc.id }));
    },
    async sources(ids) {
      // Batched RPC reduces round trips, not billed document reads.
      const docs = await db.getAll(...ids.map(sourceRef));
      return docs.map((doc) => doc.data() || null);
    },
    async admit(uid, now) {
      const key = crypto.createHash('sha256').update(uid).digest('hex');
      const ref = db.collection(RATE).doc(key);
      await db.runTransaction(async (tx) => {
        const previous = (await tx.get(ref)).data();
        const minute = Math.floor(now / 60000);
        const used = previous?.minute === minute ? previous.count : 0;
        if (used >= 30 || (previous && now - previous.lastAt < 350)) {
          throw new SearchError('resource-exhausted', 'Aguarde antes de pesquisar novamente.');
        }
        tx.set(ref, { minute, count: used + 1, lastAt: now,
          expiresAt: Timestamp.fromMillis(now + 86400000) });
      });
    },
  };
}
module.exports = { createFirestoreStore };
