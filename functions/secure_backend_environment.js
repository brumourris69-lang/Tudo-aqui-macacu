'use strict';
const { localOnly } = require('./business_search');

// Deployment preparation only. No production flag is set by this repository.
// Emulator flags must never select a real project, even with explicit opt-in.
function secureBackendAllowed(env = process.env) {
  if (localOnly(env) && env.GCLOUD_PROJECT === 'demo-universal-search') return true;
  if (env.FUNCTIONS_EMULATOR || env.FIRESTORE_EMULATOR_HOST || env.FIREBASE_AUTH_EMULATOR_HOST) return false;
  return env.GCLOUD_PROJECT === 'tudo-aqui-macacu' && env.SECURE_BACKEND_ENABLED === 'true';
}
module.exports = { secureBackendAllowed };
