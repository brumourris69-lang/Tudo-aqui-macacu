const VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/u;

const AUTHORIZATION_ERRORS = Object.freeze({
  'admin-not-authorized': 'Administrator authorization was denied.',
  'authorization-unavailable': 'Administrator authorization is unavailable.',
});

export class AdminAuthorizationError extends Error {
  constructor(code) {
    super(AUTHORIZATION_ERRORS[code] ?? AUTHORIZATION_ERRORS['admin-not-authorized']);
    this.name = 'AdminAuthorizationError';
    this.code = AUTHORIZATION_ERRORS[code]
      ? code
      : 'admin-not-authorized';
  }
}

/**
 * Resolves current administrative authorization from an injected trusted
 * representation of admin_authorizations/{uid}. `identity` must come only
 * from verifyFirebaseIdToken; this function never reads caller-supplied JWT
 * claims and never logs identity or authorization data.
 */
export async function authorizeAdmin(identity, readAuthorization) {
  if (!identity || typeof identity.uid !== 'string' ||
    identity.uid.length === 0 || identity.uid.length > 128 ||
    identity.isAnonymous !== false || typeof readAuthorization !== 'function') {
    throw new AdminAuthorizationError('admin-not-authorized');
  }

  let state;
  try {
    state = await readAuthorization(identity.uid);
  } catch {
    throw new AdminAuthorizationError('authorization-unavailable');
  }

  if (!state || state.enabled !== true || state.pending !== false ||
    state.revoked === true ||
    (state.revokedAt !== undefined && state.revokedAt !== null) ||
    typeof state.version !== 'string' ||
    !VERSION_PATTERN.test(state.version)) {
    throw new AdminAuthorizationError('admin-not-authorized');
  }

  return Object.freeze({
    authorized: true,
    version: state.version,
  });
}
