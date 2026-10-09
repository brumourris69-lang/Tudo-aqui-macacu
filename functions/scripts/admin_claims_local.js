'use strict';
// Intentionally impossible to use on a production project. Do not relax guards.
const { localOnly } = require('../business_search');
if (!localOnly() || process.env.GCLOUD_PROJECT !== 'demo-universal-search' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9097') {
  throw new Error('Use only demo-universal-search with local Auth and Firestore emulators');
}
const admin = require('firebase-admin');
const { changeAdminClaim } = require('../admin_claim_management');
const args = process.argv.slice(2);
const get = name => { const index = args.indexOf(`--${name}`); return index < 0 ? undefined : args[index + 1]; };
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
changeAdminClaim({ auth: admin.auth(), db: admin.firestore(), uid: get('uid'),
  action: get('action'), operator: get('operator'), reason: get('reason'),
  confirmation: get('confirm'), apply: args.includes('--apply') })
  .then(result => console.log(JSON.stringify(result)))
  .catch(error => { console.error(error.message); process.exitCode = 1; })
  .finally(() => admin.app().delete());
