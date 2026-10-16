'use strict';

const FORBIDDEN_PROJECTS = new Set(['tudo-aqui-macacu', 'demo-universal-search']);
const EMULATOR_ENVIRONMENT_KEYS = Object.freeze([
  'FUNCTIONS_EMULATOR',
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_AUTH_EMULATOR_HOST',
  'PUBSUB_EMULATOR_HOST',
  'FIREBASE_EMULATOR_HUB',
]);
const EXPLICIT_CREDENTIAL_KEYS = Object.freeze([
  'GOOGLE_APPLICATION_CREDENTIALS',
  'FIREBASE_TOKEN',
]);

function stagingProjectContext({ env = process.env, adminProjectId } = {}) {
  let firebaseConfigProjectId;
  try {
    const firebaseConfig = typeof env?.FIREBASE_CONFIG === 'string'
      ? JSON.parse(env.FIREBASE_CONFIG)
      : env?.FIREBASE_CONFIG;
    firebaseConfigProjectId = firebaseConfig?.projectId;
  } catch (_) {
    firebaseConfigProjectId = undefined;
  }
  const candidateIds = [
    env?.STAGING_FIREBASE_PROJECT_ID,
    env?.GCLOUD_PROJECT,
    env?.GOOGLE_CLOUD_PROJECT,
    firebaseConfigProjectId,
    adminProjectId,
  ];
  return candidateIds.some(
    (projectId) => typeof projectId === 'string' && /(?:-staging|-homologacao)$/.test(projectId),
  );
}

function stagingBackendAllowed({ env = process.env, adminProjectId } = {}) {
  if (!env || env.STAGING_BACKEND_ENABLED !== 'true') return false;
  const configuredProjectId = env.STAGING_FIREBASE_PROJECT_ID;
  const runtimeProjectId = env.GCLOUD_PROJECT;
  if (typeof configuredProjectId !== 'string' || !configuredProjectId.trim() ||
      typeof runtimeProjectId !== 'string' || !runtimeProjectId.trim() ||
      typeof adminProjectId !== 'string' || !adminProjectId.trim()) return false;
  if (configuredProjectId !== runtimeProjectId || configuredProjectId !== adminProjectId ||
      FORBIDDEN_PROJECTS.has(configuredProjectId)) return false;
  if (env.GOOGLE_CLOUD_PROJECT && env.GOOGLE_CLOUD_PROJECT !== configuredProjectId) return false;
  if (!/(?:-staging|-homologacao)$/.test(configuredProjectId)) return false;
  if (EXPLICIT_CREDENTIAL_KEYS.some((key) => typeof env[key] === 'string' && env[key].length > 0)) {
    return false;
  }
  if (EMULATOR_ENVIRONMENT_KEYS.some((key) => Object.hasOwn(env, key))) {
    return false;
  }
  if (env.FIREBASE_CONFIG) {
    try {
      const firebaseConfig = typeof env.FIREBASE_CONFIG === 'string'
        ? JSON.parse(env.FIREBASE_CONFIG)
        : env.FIREBASE_CONFIG;
      if (firebaseConfig.projectId !== configuredProjectId) return false;
    } catch (_) {
      return false;
    }
  }
  return true;
}

module.exports = { stagingBackendAllowed, stagingProjectContext };
