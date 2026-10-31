'use strict';

const BETA_FIREBASE_PROJECT_ID = 'macacu-beta-261030-cf4a81';
const EMULATOR_ENVIRONMENT_KEYS = Object.freeze([
  'FUNCTIONS_EMULATOR',
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_AUTH_EMULATOR_HOST',
  'PUBSUB_EMULATOR_HOST',
  'FIREBASE_EMULATOR_HUB',
]);
const EXPLICIT_CREDENTIAL_KEYS = Object.freeze([
  'GOOGLE_APPLICATION_CREDENTIALS',
  'GOOGLE_CLOUD_KEYFILE_JSON',
  'FIREBASE_TOKEN',
]);

function configuredProjectId(env) {
  try {
    const config = typeof env?.FIREBASE_CONFIG === 'string'
      ? JSON.parse(env.FIREBASE_CONFIG)
      : env?.FIREBASE_CONFIG;
    return config?.projectId;
  } catch (_) {
    return null;
  }
}

function betaProjectContext({ env = process.env, adminProjectId } = {}) {
  return [env?.GCLOUD_PROJECT, env?.GOOGLE_CLOUD_PROJECT,
    configuredProjectId(env), adminProjectId].includes(BETA_FIREBASE_PROJECT_ID);
}

function betaBackendAllowed({ env = process.env, adminProjectId } = {}) {
  if (env?.GCLOUD_PROJECT !== BETA_FIREBASE_PROJECT_ID ||
      adminProjectId !== BETA_FIREBASE_PROJECT_ID) return false;
  if (env.GOOGLE_CLOUD_PROJECT && env.GOOGLE_CLOUD_PROJECT !== BETA_FIREBASE_PROJECT_ID) return false;
  if (env.STAGING_FIREBASE_PROJECT_ID) return false;
  if (env.FIREBASE_CONFIG && configuredProjectId(env) !== BETA_FIREBASE_PROJECT_ID) return false;
  if (EMULATOR_ENVIRONMENT_KEYS.some((key) => Object.hasOwn(env, key))) return false;
  if (EXPLICIT_CREDENTIAL_KEYS.some((key) => typeof env[key] === 'string' && env[key].length > 0)) return false;
  return true;
}

module.exports = {
  BETA_FIREBASE_PROJECT_ID,
  betaBackendAllowed,
  betaProjectContext,
};
