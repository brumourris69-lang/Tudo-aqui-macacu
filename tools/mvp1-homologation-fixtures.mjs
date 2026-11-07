#!/usr/bin/env node
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const DEMO_PROJECT = 'demo-universal-search';
const REQUIRED_FIRESTORE_HOST = '127.0.0.1:8087';
const MARKER = 'mvp1-homologacao-local-20261105';
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const admin = require('firebase-admin');

const fixtures = [
  {
    collection: 'ads',
    id: 'mvp1-qa-20261105-banner',
    data: {
      title: '[TESTE] Banner de homologação local',
      description: 'Conteúdo sintético para validação no MEmu.',
      link: '',
      order: 10,
    },
  },
  {
    collection: 'establishments',
    id: 'mvp1-qa-20261105-est-comercio',
    data: {
      name: '[TESTE] Loja do Centro',
      category: 'Comércio',
      subcategory: 'Vitrine sintética',
      description: 'Estabelecimento fictício de homologação local.',
      shortDescription: 'Dado de teste; não representa uma empresa real.',
      location: 'Local fictício — não visitar',
      artwork: 0,
      featured: true,
      hours: 'Seg-Dom: 00h às 23h',
    },
  },
  {
    collection: 'establishments',
    id: 'mvp1-qa-20261105-est-alimentacao',
    data: {
      name: '[TESTE] Café da Praça',
      category: 'Onde comer?',
      subcategory: 'Cafeteria sintética',
      description: 'Estabelecimento fictício de homologação local.',
      shortDescription: 'Dado de teste; não representa uma empresa real.',
      location: 'Local fictício — não visitar',
      artwork: 1,
      featured: false,
      hours: 'Seg-Sex: 08h às 18h',
    },
  },
  {
    collection: 'establishments',
    id: 'mvp1-qa-20261105-est-servicos',
    data: {
      name: '[TESTE] Serviços do Bairro',
      category: 'Serviços',
      subcategory: 'Atendimento sintético',
      description: 'Estabelecimento fictício de homologação local.',
      shortDescription: 'Dado de teste; não representa uma empresa real.',
      location: 'Local fictício — não visitar',
      artwork: 2,
      featured: false,
      hours: 'Seg-Sáb: 09h às 17h',
    },
  },
  {
    collection: 'events',
    id: 'mvp1-qa-20261105-evento-feira',
    data: {
      title: '[TESTE] Feira comunitária de demonstração',
      category: 'Cultura',
      description: 'Evento fictício para testar lista, filtro e detalhe.',
      location: 'Local fictício — sem endereço de visita',
      eventDate: '2026-11-12T18:00:00-03:00',
      endDate: '2026-11-12T21:00:00-03:00',
      startTime: '18h',
      endTime: '21h',
      organizer: 'Organização fictícia de teste',
    },
  },
  {
    collection: 'events',
    id: 'mvp1-qa-20261105-evento-musica',
    data: {
      title: '[TESTE] Encontro musical de demonstração',
      category: 'Música',
      description: 'Evento fictício para testar agenda e lembrete local.',
      location: 'Local fictício — sem endereço de visita',
      eventDate: '2026-11-18T19:00:00-03:00',
      endDate: '2026-11-18T22:00:00-03:00',
      startTime: '19h',
      endTime: '22h',
      organizer: 'Organização fictícia de teste',
    },
  },
  {
    collection: 'routes',
    id: 'mvp1-qa-20261105-ponto-praca',
    data: {
      title: '[TESTE] Ponto turístico de demonstração A',
      category: 'pontos_turisticos',
      type: 'tourism',
      description: 'Ponto fictício para testar a apresentação pública.',
      location: '',
      additionalInfo: 'Dado sintético; não usar para navegação real.',
      order: 10,
    },
  },
  {
    collection: 'routes',
    id: 'mvp1-qa-20261105-ponto-rio',
    data: {
      title: '[TESTE] Ponto turístico de demonstração B',
      category: 'pontos_turisticos',
      type: 'tourism',
      description: 'Ponto fictício para testar a apresentação pública.',
      location: '',
      additionalInfo: 'Dado sintético; não usar para navegação real.',
      order: 20,
    },
  },
  {
    collection: 'utilities',
    id: 'mvp1-qa-20261105-util-transporte',
    data: {
      name: '[TESTE] Transporte municipal',
      iconKey: 'bus',
      description: 'Atalho sintético para validar navegação interna.',
      destinationType: 'internal',
      destination: 'transport',
      order: 10,
      category: 'Serviços públicos',
    },
  },
  {
    collection: 'utilities',
    id: 'mvp1-qa-20261105-util-coleta',
    data: {
      name: '[TESTE] Coleta de resíduos',
      iconKey: 'trash',
      description: 'Atalho sintético para validar navegação interna.',
      destinationType: 'internal',
      destination: 'trash',
      order: 20,
      category: 'Serviços públicos',
    },
  },
];

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map(key => [key, stable(value[key])]),
    );
  }
  return value;
}

function sameJson(left, right) {
  return JSON.stringify(stable(left)) === JSON.stringify(stable(right));
}

function validateEnvironment() {
  if (process.env.FIRESTORE_EMULATOR_HOST !== REQUIRED_FIRESTORE_HOST) {
    throw new Error(`FIRESTORE_EMULATOR_HOST deve ser exatamente ${REQUIRED_FIRESTORE_HOST}.`);
  }
  for (const key of ['GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT']) {
    if (process.env[key] !== DEMO_PROJECT) {
      throw new Error(`${key} deve ser exatamente ${DEMO_PROJECT}.`);
    }
  }
  for (const key of [
    'GOOGLE_APPLICATION_CREDENTIALS',
    'FIREBASE_TOKEN',
    'FIREBASE_CONFIG',
  ]) {
    if (process.env[key]) throw new Error(`${key} precisa estar ausente; credenciais/fallback não são aceitos.`);
  }
  if (typeof fetch !== 'function') throw new Error('Node.js sem suporte a fetch não pode validar o Emulator.');
}

async function validateEmulator() {
  const response = await fetch(`http://${REQUIRED_FIRESTORE_HOST}/`, {
    signal: AbortSignal.timeout(3000),
  });
  if (!response.ok) throw new Error('O endpoint local do Firestore Emulator não respondeu com sucesso.');
  const hub = await fetch('http://127.0.0.1:4407/emulators', {
    signal: AbortSignal.timeout(3000),
  });
  if (!hub.ok) throw new Error('Não foi possível confirmar o Hub local do Firebase Emulator.');
  const services = await hub.json();
  if (services.firestore?.host !== '127.0.0.1' || services.firestore?.port !== 8087 ||
      services.auth?.host !== '127.0.0.1' || services.auth?.port !== 9097 ||
      'functions' in services || 'hosting' in services || 'storage' in services) {
    throw new Error('O Hub não corresponde ao ambiente local Auth/Firestore aprovado.');
  }
}

function references(db) {
  return fixtures.flatMap(fixture => [
    {
      kind: 'source',
      fixture,
      ref: db.collection(fixture.collection).doc(fixture.id),
    },
    {
      kind: 'projection',
      fixture,
      ref: db.collection('beta_public_catalog').doc(fixture.collection)
        .collection('items').doc(fixture.id),
    },
  ]);
}

function expectedSource(fixture) {
  return {
    ...fixture.data,
    active: true,
    published: true,
    fixtureMarker: MARKER,
  };
}

function expectedProjection(fixture) {
  return {
    visibility: 'public',
    sourceId: fixture.id,
    schemaVersion: 1,
    publicData: fixture.data,
  };
}

async function inspect(db) {
  const refs = references(db);
  const snapshots = await db.getAll(...refs.map(entry => entry.ref));
  const existing = snapshots
    .map((snapshot, index) => snapshot.exists ? refs[index] : null)
    .filter(Boolean);
  console.log(`Emulator: ${DEMO_PROJECT} em ${REQUIRED_FIRESTORE_HOST}; Auth local 127.0.0.1:9097.`);
  console.log(`Alvos de fixture existentes: ${existing.length}/${refs.length}.`);
  for (const entry of existing) console.log(`EXISTE ${entry.ref.path}; será preservado.`);
  const home = await db.doc('home_pages/published').get();
  console.log(`home_pages/published: ${home.exists ? 'existe e não será alterado' : 'ausente; defaults do app permanecem ativos'}.`);
  return existing.length;
}

async function seed(db) {
  const refs = references(db);
  const already = await db.runTransaction(async transaction => {
    const snapshots = [];
    for (const entry of refs) snapshots.push(await transaction.get(entry.ref));
    const existingCount = snapshots.filter(snapshot => snapshot.exists).length;
    if (existingCount === refs.length) {
      for (let index = 0; index < refs.length; index++) {
        const entry = refs[index];
        const value = snapshots[index].data();
        const expected = entry.kind === 'source'
          ? expectedSource(entry.fixture)
          : expectedProjection(entry.fixture);
        if (entry.kind === 'source') {
          const comparable = Object.fromEntries(
            Object.keys(value).filter(key => !['createdAt', 'updatedAt'].includes(key))
              .map(key => [key, value[key]]),
          );
          if (!sameJson(comparable, expected)) {
            throw new Error(`Fixture existente foi alterada; nenhuma escrita realizada: ${entry.ref.path}.`);
          }
        } else {
          const comparable = Object.fromEntries(
            Object.keys(value).filter(key => key !== 'updatedAt').map(key => [key, value[key]]),
          );
          if (!sameJson(comparable, expected)) {
            throw new Error(`Projeção existente não corresponde à fixture; nenhuma escrita realizada: ${entry.ref.path}.`);
          }
        }
      }
      return true;
    }
    if (existingCount !== 0) {
      throw new Error(`Há ${existingCount} de ${refs.length} documentos-alvo preexistentes; nenhuma escrita realizada.`);
    }

    const timestamp = admin.firestore.Timestamp.now();
    for (const fixture of fixtures) {
      const source = db.collection(fixture.collection).doc(fixture.id);
      const projection = db.collection('beta_public_catalog').doc(fixture.collection)
        .collection('items').doc(fixture.id);
      transaction.create(source, {
        ...expectedSource(fixture),
        createdAt: timestamp,
        updatedAt: timestamp,
      });
      transaction.create(projection, {
        ...expectedProjection(fixture),
        updatedAt: timestamp,
      });
    }
    return false;
  });
  console.log(already
    ? 'Fixture já estava completa e íntegra; nenhum documento foi sobrescrito.'
    : `Criadas ${fixtures.length} fontes e ${fixtures.length} projeções públicas sintéticas.`);
  for (const fixture of fixtures) console.log(`${fixture.collection}/${fixture.id}`);
}

async function remove(db) {
  const refs = references(db);
  await db.runTransaction(async transaction => {
    const snapshots = [];
    for (const entry of refs) snapshots.push(await transaction.get(entry.ref));
    const existingCount = snapshots.filter(snapshot => snapshot.exists).length;
    if (existingCount === 0) return;
    if (existingCount !== refs.length) {
      throw new Error(`Remoção seletiva interrompida: ${existingCount}/${refs.length} documentos existem.`);
    }
    for (let index = 0; index < refs.length; index++) {
      const entry = refs[index];
      const value = snapshots[index].data();
      const expected = entry.kind === 'source'
        ? expectedSource(entry.fixture)
        : expectedProjection(entry.fixture);
      if (entry.kind === 'source') {
        const comparable = Object.fromEntries(
          Object.keys(value).filter(key => !['createdAt', 'updatedAt'].includes(key))
            .map(key => [key, value[key]]),
        );
        if (!sameJson(comparable, expected)) {
          throw new Error(`Documento alterado; remoção bloqueada: ${entry.ref.path}.`);
        }
      } else {
        const comparable = Object.fromEntries(
          Object.keys(value).filter(key => key !== 'updatedAt').map(key => [key, value[key]]),
        );
        if (!sameJson(comparable, expected)) {
          throw new Error(`Projeção alterada; remoção bloqueada: ${entry.ref.path}.`);
        }
      }
    }
    for (const entry of refs) transaction.delete(entry.ref);
  });
  console.log(`Remoção seletiva concluída para ${fixtures.length} fontes e suas projeções, somente se todas ainda correspondiam às fixtures.`);
}

async function main() {
  const mode = process.argv[2];
  if (!['--inspect', '--seed', '--remove'].includes(mode)) {
    throw new Error('Uso: node tools/mvp1-homologation-fixtures.mjs --inspect|--seed|--remove');
  }
  validateEnvironment();
  await validateEmulator();
  const app = admin.initializeApp({ projectId: DEMO_PROJECT }, 'mvp1-local-homologation-fixtures');
  const db = app.firestore();
  try {
    if (mode === '--inspect') await inspect(db);
    if (mode === '--seed') await seed(db);
    if (mode === '--remove') await remove(db);
  } finally {
    await app.delete();
  }
}

main().catch(error => {
  console.error(`Fixture local interrompida: ${error.message}`);
  process.exitCode = 1;
});
