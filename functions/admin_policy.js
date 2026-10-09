'use strict';

function isAdminClaim(token) {
  return token?.admin === true && token.firebase?.sign_in_provider !== 'anonymous';
}
module.exports = { isAdminClaim };
