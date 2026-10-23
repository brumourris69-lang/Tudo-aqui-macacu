import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createAdminEstablishmentsHandler } from '../../supabase/functions/_shared/admin_establishments.mjs';
import { authorizeAdmin } from '../../supabase/functions/_shared/admin_authorization.mjs';

export const DEMO_PROJECT_ID = 'demo-universal-search';
export const ADMIN_BRIDGE_HOST = '127.0.0.1';
export const ADMIN_BRIDGE_PORT = 5077;
export const ADMIN_BRIDGE_PATH = '/functions/v1/manage-establishments';
export const ADMIN_BRIDGE_MAX_BODY_BYTES = 32 * 1024;
const HANDLER_PROJECT_ID = 'tudo-aqui-macacu';
const ALLOWED_COLLECTIONS = new Set([
  'admin_authorizations', 'catalog_outbox', 'establishments',
]);
const SAFE_FAILURE = JSON.stringify({ error: {
  code: 'backend_unavailable', message: 'O serviço está indisponível. Tente novamente.',
} });

function fail() {
  throw new Error('Local Admin bridge configuration is invalid.');
}

export function assertLocalAdminBridgeEnvironment(env = process.env) {
  if (env.GCLOUD_PROJECT !== DEMO_PROJECT_ID ||
      env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9097' ||
      env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8087' ||
      env.LOCAL_ADMIN_BRIDGE_CONFIRM !== DEMO_PROJECT_ID ||
      (env.LOCAL_ADMIN_BRIDGE_PORT !== undefined &&
        env.LOCAL_ADMIN_BRIDGE_PORT !== String(ADMIN_BRIDGE_PORT)) ||
      env.GOOGLE_APPLICATION_CREDENTIALS || env.FIREBASE_TOKEN ||
      (env.GOOGLE_CLOUD_PROJECT && env.GOOGLE_CLOUD_PROJECT !== DEMO_PROJECT_ID)) fail();

  if (typeof env.FIREBASE_CONFIG !== 'string') fail();
  let firebaseConfig;
  try { firebaseConfig = JSON.parse(env.FIREBASE_CONFIG); } catch { fail(); }
  if (firebaseConfig?.projectId !== DEMO_PROJECT_ID) fail();
  return Object.freeze({ projectId: DEMO_PROJECT_ID, host: ADMIN_BRIDGE_HOST,
    port: ADMIN_BRIDGE_PORT, path: ADMIN_BRIDGE_PATH });
}

export async function verifyDemoEmulatorHub({ fetchImpl = fetch, timeoutMs = 2000 } = {}) {
  let response;
  try {
    response = await fetchImpl('http://127.0.0.1:4407/emulators', {
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch { fail(); }
  if (!response?.ok) fail();
  let hub;
  try { hub = await response.json(); } catch { fail(); }
  for (const [name, port] of [['auth', 9097], ['firestore', 8087], ['functions', 5007]]) {
    if (hub?.[name]?.host !== '127.0.0.1' || Number(hub[name].port) !== port) fail();
  }
  return true;
}

function formatUpdateTime(value) {
  const seconds = Number.isInteger(value?.seconds) ? value.seconds : value?._seconds;
  const nanoseconds = Number.isInteger(value?.nanoseconds) ? value.nanoseconds : value?._nanoseconds;
  if (!Number.isInteger(seconds) || !Number.isInteger(nanoseconds)) {
    throw new Error('Firestore transaction metadata is unavailable.');
  }
  return `${seconds}.${String(nanoseconds).padStart(9, '0')}`;
}

function createAdminStore(db, fieldValue) {
  if (!db || typeof db.runTransaction !== 'function' ||
      typeof fieldValue?.serverTimestamp !== 'function' ||
      typeof fieldValue?.delete !== 'function') fail();

  function reference(collection, id) {
    if (!ALLOWED_COLLECTIONS.has(collection) || typeof id !== 'string' ||
        id.length === 0 || id.includes('/')) throw new Error('Unsupported Firestore path.');
    return db.collection(collection).doc(id);
  }

  function withTransforms(data, options = {}) {
    const result = { ...data };
    for (const field of options.serverTimestampFields ?? []) {
      result[field] = fieldValue.serverTimestamp();
    }
    for (const field of options.deleteFields ?? []) result[field] = fieldValue.delete();
    return result;
  }

  return Object.freeze({
    runTransaction(callback) {
      return db.runTransaction(async (native) => {
        const snapshots = new Map();
        const transaction = {
          async get(collection, id) {
            const ref = reference(collection, id);
            const snapshot = await native.get(ref);
            snapshots.set(`${collection}/${id}`, snapshot);
            return snapshot.exists ? {
              data: snapshot.data(), updateTime: formatUpdateTime(snapshot.updateTime),
            } : null;
          },
          create(collection, id, data, options = {}) {
            native.create(reference(collection, id), withTransforms(data, options));
          },
          update(collection, id, data, options = {}) {
            const key = `${collection}/${id}`;
            const snapshot = snapshots.get(key);
            if (!snapshot?.exists || formatUpdateTime(snapshot.updateTime) !== options.updateTime) {
              throw Object.assign(new Error('Firestore transaction precondition failed.'), { code: 'conflict' });
            }
            native.update(reference(collection, id), withTransforms(data, options));
          },
        };
        return callback(transaction);
      }, { maxAttempts: 5 });
    },
  });
}

export function createLocalAdminEstablishmentsHandler({ env = process.env, auth, db,
  fieldValue, uuid } = {}) {
  assertLocalAdminBridgeEnvironment(env);
  if (typeof auth?.verifyIdToken !== 'function') fail();
  const store = createAdminStore(db, fieldValue);

  return createAdminEstablishmentsHandler({
    // The shared handler retains its production contract guard. Token audience,
    // issuer and every Firebase connection are pinned to the demo Emulator here.
    projectId: HANDLER_PROJECT_ID,
    store,
    authorizeAdmin,
    ...(uuid ? { uuid } : {}),
    async verifyIdentity(token, expectedProjectId) {
      if (expectedProjectId !== HANDLER_PROJECT_ID) fail();
      const decoded = await auth.verifyIdToken(token, true);
      const provider = decoded?.firebase?.sign_in_provider;
      if (decoded?.aud !== DEMO_PROJECT_ID ||
          decoded?.iss !== `https://securetoken.google.com/${DEMO_PROJECT_ID}` ||
          typeof decoded?.uid !== 'string' || !decoded.uid || decoded.sub !== decoded.uid ||
          typeof provider !== 'string' || !provider) fail();
      return Object.freeze({ uid: decoded.uid, authTime: decoded.auth_time,
        isAnonymous: provider === 'anonymous', provider });
    },
  });
}

async function readBoundedBody(request, limit) {
  const declared = Number(request.headers['content-length'] ?? 0);
  if (Number.isFinite(declared) && declared > limit) return null;
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.byteLength;
    if (size > limit) {
      request.resume();
      return null;
    }
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, size);
}

function sendJson(response, status, body) {
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store', 'connection': 'close' });
  response.end(body);
}

export function createLocalAdminEstablishmentsServer(handler) {
  if (typeof handler !== 'function') fail();
  const server = createServer(async (incoming, outgoing) => {
    if (incoming.url !== ADMIN_BRIDGE_PATH) {
      sendJson(outgoing, 404, '{"error":{"code":"not_found","message":"Rota indisponível."}}');
      return;
    }
    if (incoming.method !== 'OPTIONS' && incoming.method !== 'POST') {
      sendJson(outgoing, 405, '{"error":{"code":"invalid_request","message":"Método não permitido."}}');
      return;
    }

    try {
      const body = incoming.method === 'POST'
        ? await readBoundedBody(incoming, ADMIN_BRIDGE_MAX_BODY_BYTES)
        : undefined;
      if (body === null) {
        sendJson(outgoing, 413, '{"error":{"code":"invalid_request","message":"A solicitação é inválida."}}');
        return;
      }
      const headers = new Headers();
      if (typeof incoming.headers.authorization === 'string') {
        headers.set('authorization', incoming.headers.authorization);
      }
      if (typeof incoming.headers['content-type'] === 'string') {
        headers.set('content-type', incoming.headers['content-type']);
      }
      const webRequest = new Request(`http://127.0.0.1${ADMIN_BRIDGE_PATH}`, {
        method: incoming.method, headers,
        ...(body === undefined ? {} : { body }),
      });
      const result = await handler(webRequest);
      outgoing.writeHead(result.status, Object.fromEntries(result.headers.entries()));
      outgoing.end(Buffer.from(await result.arrayBuffer()));
    } catch {
      if (!outgoing.headersSent) sendJson(outgoing, 503, SAFE_FAILURE);
      else outgoing.destroy();
    }
  });
  server.headersTimeout = 5000;
  server.requestTimeout = 10000;
  server.maxHeadersCount = 24;
  return server;
}

export async function startLocalAdminEstablishmentsBridge({ env = process.env,
  fetchImpl = fetch, adminSdk } = {}) {
  const config = assertLocalAdminBridgeEnvironment(env);
  await verifyDemoEmulatorHub({ fetchImpl });
  const requireFromFunctions = createRequire(new URL('../package.json', import.meta.url));
  const sdk = adminSdk ?? {
    initializeApp: requireFromFunctions('firebase-admin/app').initializeApp,
    getAuth: requireFromFunctions('firebase-admin/auth').getAuth,
    getFirestore: requireFromFunctions('firebase-admin/firestore').getFirestore,
    FieldValue: requireFromFunctions('firebase-admin/firestore').FieldValue,
    deleteApp: requireFromFunctions('firebase-admin/app').deleteApp,
  };
  const app = sdk.initializeApp({ projectId: DEMO_PROJECT_ID }, `local-admin-bridge-${process.pid}`);
  const handler = createLocalAdminEstablishmentsHandler({ env, auth: sdk.getAuth(app),
    db: sdk.getFirestore(app), fieldValue: sdk.FieldValue });
  const server = createLocalAdminEstablishmentsServer(handler);
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(config.port, config.host, resolve);
    });
    const address = server.address();
    if (!address || typeof address === 'string' || address.address !== ADMIN_BRIDGE_HOST ||
        address.port !== ADMIN_BRIDGE_PORT) throw new Error('Loopback bind could not be verified.');
  } catch (error) {
    await new Promise((resolve) => server.close(() => resolve()));
    await sdk.deleteApp(app);
    throw error;
  }

  let closing;
  return Object.freeze({
    host: config.host, port: config.port, path: config.path,
    close() {
      closing ??= (async () => {
        await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
        await sdk.deleteApp(app);
      })();
      return closing;
    },
  });
}

async function main() {
  const bridge = await startLocalAdminEstablishmentsBridge();
  process.stdout.write(`Local Admin bridge ready at http://${bridge.host}:${bridge.port}${bridge.path} for ${DEMO_PROJECT_ID}.\n`);
  let closing = false;
  const stop = async (signal) => {
    if (closing) return;
    closing = true;
    try { await bridge.close(); process.stdout.write(`Local Admin bridge stopped (${signal}).\n`); }
    catch { process.exitCode = 1; }
  };
  process.once('SIGINT', () => { void stop('SIGINT').then(() => process.exit()); });
  process.once('SIGTERM', () => { void stop('SIGTERM').then(() => process.exit()); });
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main().catch(() => {
    process.stderr.write('Local Admin bridge stopped safely; verify demo Emulator configuration and loopback services.\n');
    process.exitCode = 1;
  });
}
