'use strict';
const { isAdminClaim } = require('./admin_policy');

function currentAdminState(token, state) {
  return isAdminClaim(token) && typeof token.adminVersion === 'string' &&
    token.adminVersion.length > 0 && state?.enabled === true &&
    state.version === token.adminVersion && state.pending === false;
}

// The caller must supply a token already verified by the Firebase callable
// runtime or verifyIdToken. Never pass a client-decoded JWT here.
async function authorizeCurrentAdmin(auth, { db, firebaseAuth, rawToken } = {}) {
  if (!auth?.uid || !isAdminClaim(auth.token)) return false;
  if (!db) throw new Error('Administrative authorization unavailable');
  if (rawToken) {
    if (!firebaseAuth) throw new Error('Revocation verifier unavailable');
    const verified = await firebaseAuth.verifyIdToken(rawToken, true);
    if (verified.uid !== auth.uid) return false;
  }
  const snapshot = await db.collection('admin_authorizations').doc(auth.uid).get();
  return snapshot.exists && currentAdminState(auth.token, snapshot.data());
}
module.exports = { currentAdminState, authorizeCurrentAdmin };
