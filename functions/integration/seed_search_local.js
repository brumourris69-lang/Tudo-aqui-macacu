'use strict';
// Persistent fictional fixtures, exclusively in the local demo emulator.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { Timestamp } = require('firebase-admin/firestore');
if (process.env.GCLOUD_PROJECT !== 'demo-universal-search' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8087' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9097' ||
    process.env.FUNCTIONS_EMULATOR !== 'true') throw new Error('Local demo only');
admin.initializeApp({ projectId: 'demo-universal-search' });
const db = admin.firestore();
const fixtures = [
  ['local-eletronica-vieira', 'Eletrônica Vieira', 'Tecnologia', 'Eletrônicos'],
  ['local-padaria-central', 'Padaria Central', 'Onde comer?', 'Padaria'],
  ['local-oficina-macacu', 'Oficina Macacu', 'Serviços', 'Oficina'],
  ['local-barbearia-modelo', 'Barbearia Modelo', 'Beleza', 'Barbearia'],
  ['local-eletricista-modelo', 'Eletricista Modelo', 'Profissionais', 'Eletricista'],
];
async function main() {
  const batch = db.batch();
  const base = { published: true, active: true, open: true,
    shortDescription: 'Estabelecimento fictício para teste local. Não representa um negócio real.',
    location: 'Ambiente de testes — Cachoeiras de Macacu', imageUrl: '', logoUrl: '',
    galleryUrls: [], services: [], products: [], featured: false };
  for (const [id, name, category, subcategory] of fixtures) {
    batch.set(db.collection('establishments').doc(id), { ...base, name, category, subcategory });
  }
  for (const [id, fields] of [
    ['local-unpublished', { published: false }],
    ['local-inactive', { active: false }],
    ['local-expired', { expiresAt: Timestamp.fromMillis(Date.now() - 60000) }],
  ]) batch.set(db.collection('establishments').doc(id), {
    ...base, name: 'Modelo bloqueado fictício', category: 'Tecnologia', ...fields,
  });
  await batch.commit();
  // Deliberately do NOT invoke synchronize manually: verify the real trigger.
  for (let attempt = 0; attempt < 100; attempt++) {
    const indexes = await db.getAll(...fixtures.map(([id]) =>
      db.collection('business_search_index').doc(`establishments__${id}`)));
    if (indexes.every((doc, i) => doc.exists && doc.data().title === fixtures[i][1])) {
      for (const id of ['local-unpublished', 'local-inactive', 'local-expired']) {
        assert.equal((await db.collection('business_search_index').doc(`establishments__${id}`).get()).exists, false);
      }
      console.log('PASS: five stable fictional sources indexed by the actual trigger; three ineligible absent.');
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 300));
  }
  throw new Error('Trigger did not index fictional fixtures within 30 seconds');
}
main().catch(error => { console.error(error.message); process.exitCode = 1; })
  .finally(() => admin.app().delete());
