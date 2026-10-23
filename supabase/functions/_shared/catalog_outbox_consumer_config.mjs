const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u;
const SUPABASE_PROJECT_REF_PATTERN = /^[a-z0-9]{20}$/u;
const MAX_SERVICE_ACCOUNT_BYTES = 32 * 1024;
const MIN_SECRET_LENGTH = 32;
const MAX_DATABASE_URL_LENGTH = 4_096;
const LOCAL_FIRESTORE_PROJECT = "demo-universal-search";
const PRODUCTION_FIREBASE_PROJECT = "tudo-aqui-macacu";
const WRITER_LOGIN = "catalog_writer_v2_login";
const HOMOLOGATION_MARKER = /(?:^|-)staging(?:-|$)|(?:^|-)homologation(?:-|$)/u;

/** @typedef {{enabled: false}} DisabledConsumerConfig */
/** @typedef {{enabled: true, projectId: string, databaseMode: "local", databaseUrl: string, firestoreEmulatorHost: string, hmacSecret: string}} LocalConsumerConfig */
/** @typedef {{enabled: true, projectId: string, databaseMode: "hosted", databaseUrl: string, supabaseProjectRef: string, serviceAccountJson: string, hmacSecret: string, homologationProjectId?: string}} HostedConsumerConfig */
/** @typedef {DisabledConsumerConfig | LocalConsumerConfig | HostedConsumerConfig} CatalogOutboxConsumerConfig */

/**
 * Resolves a fail-closed consumer configuration. Local mode can only target
 * loopback emulators with the dedicated PostgreSQL LOGIN; hosted mode can only
 * target a Supabase transaction pooler with the same restricted identity.
 * service_role credentials are rejected and are never returned to composition.
 * @returns {CatalogOutboxConsumerConfig}
 */
export function resolveCatalogOutboxConsumerConfig(env) {
  if (
    !env || typeof env !== "object" || env.CATALOG_CONSUMER_ENABLED !== "true"
  ) {
    return Object.freeze({ enabled: false });
  }

  if (env.SUPABASE_SERVICE_ROLE_KEY !== undefined) {
    return Object.freeze({ enabled: false });
  }

  const mode = env.CATALOG_DATABASE_MODE;
  const projectId = stringValue(env.FIREBASE_PROJECT_ID, 1, 30);
  const databaseUrl = stringValue(
    env.SUPABASE_CATALOG_DATABASE_URL,
    1,
    MAX_DATABASE_URL_LENGTH,
  );
  const hmacSecret = stringValue(
    env.CATALOG_CONSUMER_HMAC_SECRET,
    MIN_SECRET_LENGTH,
    8_192,
  );
  if (
    !projectId || !PROJECT_ID_PATTERN.test(projectId) || !databaseUrl ||
    !hmacSecret
  ) {
    return Object.freeze({ enabled: false });
  }

  if (mode === "local") {
    const emulatorHost = stringValue(env.FIRESTORE_EMULATOR_HOST, 1, 128);
    if (
      projectId !== LOCAL_FIRESTORE_PROJECT ||
      env.FIREBASE_SERVICE_ACCOUNT_JSON !== undefined ||
      !validLoopbackHostPort(emulatorHost) ||
      !validLocalDatabaseUrl(databaseUrl)
    ) {
      return Object.freeze({ enabled: false });
    }
    return Object.freeze({
      enabled: true,
      projectId,
      databaseMode: "local",
      databaseUrl,
      firestoreEmulatorHost: emulatorHost,
      hmacSecret,
    });
  }

  if (mode === "hosted") {
    const serviceAccountJson = stringValue(
      env.FIREBASE_SERVICE_ACCOUNT_JSON,
      1,
      MAX_SERVICE_ACCOUNT_BYTES,
    );
    const projectRef = stringValue(env.SUPABASE_PROJECT_REF, 20, 20);
    const homologation = env.CATALOG_CONSUMER_HOMOLOGATION === "true";
    const productionFirebaseProject = stringValue(
      env.CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID,
      1,
      30,
    );
    const approvedFirebaseProject = stringValue(
      env.CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID,
      1,
      30,
    );
    const productionSupabaseRef = stringValue(
      env.CATALOG_HOMOLOGATION_PRODUCTION_SUPABASE_REF,
      20,
      20,
    );
    const approvedSupabaseRef = stringValue(
      env.CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF,
      20,
      20,
    );
    const invalidHomologation =
      env.CATALOG_CONSUMER_HOMOLOGATION !== undefined && !homologation ||
      (homologation &&
        (projectId === PRODUCTION_FIREBASE_PROJECT ||
          projectId === LOCAL_FIRESTORE_PROJECT ||
          !HOMOLOGATION_MARKER.test(projectId) ||
          productionFirebaseProject !== PRODUCTION_FIREBASE_PROJECT ||
          approvedFirebaseProject !== projectId ||
          productionSupabaseRef === null ||
          !SUPABASE_PROJECT_REF_PATTERN.test(productionSupabaseRef) ||
          approvedSupabaseRef !== projectRef ||
          projectRef === productionSupabaseRef));
    if (
      !serviceAccountJson || !projectRef ||
      !SUPABASE_PROJECT_REF_PATTERN.test(projectRef) ||
      !validServiceAccount(serviceAccountJson, projectId) ||
      !validHostedDatabaseUrl(databaseUrl, projectRef) ||
      env.FIRESTORE_EMULATOR_HOST !== undefined || invalidHomologation
    ) {
      return Object.freeze({ enabled: false });
    }
    return Object.freeze({
      enabled: true,
      projectId,
      databaseMode: "hosted",
      databaseUrl,
      supabaseProjectRef: projectRef,
      serviceAccountJson,
      hmacSecret,
      ...(homologation ? { homologationProjectId: projectId } : {}),
    });
  }

  return Object.freeze({ enabled: false });
}

function stringValue(value, minimum, maximum) {
  return typeof value === "string" && value.length >= minimum &&
      value.length <= maximum
    ? value
    : null;
}

function parseDatabaseUrl(value) {
  try {
    const url = new URL(value);
    if (
      !["postgres:", "postgresql:"].includes(url.protocol) ||
      url.password.length < 16 ||
      !url.username || !url.port || url.pathname !== "/postgres" ||
      url.search || url.hash
    ) return null;
    return { url, username: decodeURIComponent(url.username) };
  } catch {
    return null;
  }
}

function validLocalDatabaseUrl(value) {
  const parsed = parseDatabaseUrl(value);
  return parsed !== null && parsed.username === WRITER_LOGIN &&
    ["127.0.0.1", "[::1]"].includes(parsed.url.hostname);
}

function validHostedDatabaseUrl(value, projectRef) {
  const parsed = parseDatabaseUrl(value);
  return parsed !== null &&
    parsed.username === `${WRITER_LOGIN}.${projectRef}` &&
    parsed.url.hostname.endsWith(".pooler.supabase.com") &&
    parsed.url.port === "6543";
}

function validLoopbackHostPort(value) {
  if (!value) return false;
  const match = /^(127\.0\.0\.1|\[::1\]):(\d{1,5})$/u.exec(value);
  if (!match) return false;
  const port = Number(match[2]);
  return Number.isSafeInteger(port) && port >= 1 && port <= 65_535;
}

function validServiceAccount(raw, projectId) {
  try {
    const account = JSON.parse(raw);
    return account?.type === "service_account" &&
      account.project_id === projectId &&
      typeof account.client_email === "string" &&
      account.client_email.endsWith(`@${projectId}.iam.gserviceaccount.com`) &&
      typeof account.private_key === "string" && account.private_key.length > 0;
  } catch {
    return false;
  }
}
