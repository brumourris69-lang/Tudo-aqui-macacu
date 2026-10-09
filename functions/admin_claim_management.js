'use strict';
const { localOnly } = require('./business_search');
const { randomUUID } = require('node:crypto');

async function changeAdminClaim({ auth, db, uid, action, operator, reason, confirmation, apply = false, env = process.env }) {
  if (!localOnly(env) || env.GCLOUD_PROJECT !== 'demo-universal-search' ||
      env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9097') {
    throw new Error('Admin claim changes are permitted only in the local demo emulator');
  }
  if (typeof uid !== 'string' || !uid.length || uid.length > 128 || uid.includes('/') ||
      !['grant', 'revoke'].includes(action) || typeof operator !== 'string' || !operator.trim() ||
      typeof reason !== 'string' || !reason.trim()) throw new Error('Invalid claim change request');
  const user = await auth.getUser(uid);
  if (action === 'grant' && (user.disabled || !user.providerData?.length)) {
    throw new Error('Disabled or anonymous account cannot receive Admin');
  }
  const claims = { ...(user.customClaims || {}) };
  const version = randomUUID();
  if (action === 'grant') { claims.admin = true; claims.adminVersion = version; }
  else { delete claims.admin; delete claims.adminVersion; if (claims.role === 'admin') delete claims.role; }
  if (!apply) return { project: env.GCLOUD_PROJECT, uid, action, dryRun: true };
  if (confirmation !== `${env.GCLOUD_PROJECT}:${uid}:${action}`) throw new Error('Explicit confirmation does not match project, UID and action');
  // Trusted local operator only; no callable/HTTP export and no client write rule.
  const audit = db.collection('admin_claim_changes').doc();
  const state = db.collection('admin_authorizations').doc(uid);
  await audit.set({ uid, action, operator: operator.trim(), reason: reason.trim(),
    beforeAdmin: user.customClaims?.admin === true, afterAdmin: action === 'grant',
    status: 'prepared', createdAt: new Date(), project: env.GCLOUD_PROJECT });
  try {
    // Commit the kill switch BEFORE touching Auth. Pending changes cannot
    // overlap; a partial failure remains disabled for trusted manual review.
    await db.runTransaction(async transaction => {
      const previous = await transaction.get(state);
      if (previous.data()?.pending === true) throw new Error('Pending administrative change');
      transaction.set(state, { enabled: false, pending: true, version,
        operationId: audit.id, updatedAt: new Date() });
    });
    await auth.setCustomUserClaims(uid, claims);
    if (action === 'revoke') await auth.revokeRefreshTokens(uid);
    await db.runTransaction(async transaction => {
      const current = await transaction.get(state);
      if (current.data()?.operationId !== audit.id) throw new Error('Administrative operation changed');
      transaction.set(state, { enabled: action === 'grant', pending: false,
        version, operationId: audit.id, updatedAt: new Date() });
    });
    await audit.update({ status: 'applied', finishedAt: new Date() });
  } catch (_) {
    await audit.update({ status: 'failed-review-required', finishedAt: new Date() });
    throw new Error('Claim change failed; review trusted local audit before retrying');
  }
  return { project: env.GCLOUD_PROJECT, uid, action, dryRun: false, auditId: audit.id };
}
module.exports = { changeAdminClaim };
