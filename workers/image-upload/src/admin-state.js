import policy from '../../../functions/admin_authorization.js';
import upload from '../../../functions/home_image_upload.js';
const { currentAdminState } = policy;
const { UploadError } = upload;

// Existing Firestore REST API, authenticated as this caller (not Admin SDK).
// Rules permit only a get of the caller's minimal state; no public endpoint,
// service account, cache or JWT-supplied destination is used.
export async function verifyAdminState(auth, token, project, fetchImpl = fetch) {
  if (project !== 'tudo-aqui-macacu' || !auth?.uid) {
    throw new UploadError('failed-precondition', 'Configuração de autorização inválida.');
  }
  try {
    const response = await fetchImpl(
      `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/admin_authorizations/${encodeURIComponent(auth.uid)}`,
      { headers: { authorization: `Bearer ${token}` }, redirect: 'error',
        cache: 'no-store', signal: AbortSignal.timeout(5000) },
    );
    if ([403, 404].includes(response.status)) return false;
    if (!response.ok) throw new Error('Authorization unavailable');
    const { fields } = await response.json();
    return currentAdminState(auth.token, { enabled: fields?.enabled?.booleanValue,
      pending: fields?.pending?.booleanValue !== false,
      version: fields?.version?.stringValue });
  } catch (_) {
    throw new UploadError('unavailable', 'Não foi possível validar a autorização.');
  }
}
