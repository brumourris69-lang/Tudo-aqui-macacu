import { createPrivateKey } from "node:crypto";
import { projectCanonicalEstablishment } from "../supabase/functions/_shared/catalog_outbox_protocol.mjs";
import { resolveCatalogOutboxConsumerConfig } from "../supabase/functions/_shared/catalog_outbox_consumer_config.mjs";

const STAGING_MARKER = /(?:^|-)staging(?:-|$)|(?:^|-)homologation(?:-|$)/u;
const PROJECT_REF = /^[a-z0-9]{20}$/u;
const PUBLIC_FIELDS = new Set([
  "id",
  "name",
  "summary",
  "category",
  "subcategory",
  "location",
  "artwork",
  "image_url",
  "logo_url",
  "gallery_urls",
  "featured",
  "is_open",
  "maps_url",
  "hours",
  "services",
  "products",
  "additional_info",
  "promotion_title",
  "promotion_description",
  "phone",
  "whatsapp",
  "instagram",
]);
const PRIVATE_SENTINEL = "PRIVATE_HOMOLOGATION_SENTINEL";

export class HomologationRunnerError extends Error {
  constructor(code, canary = null) {
    super("Homologation preflight or canary check failed.");
    this.name = "HomologationRunnerError";
    this.code = /^[a-z_]{1,48}$/u.test(code) ? code : "homologation_failed";
    if (canary) {
      this.canary = Object.freeze({
        id: canary.id,
        operationId: canary.operationId,
      });
    }
  }
}

/** Resolves a staging-only contract. The returned object deliberately excludes all credentials. */
export function resolveHomologationConfig(env, { mode = "preflight" } = {}) {
  if (
    !env || typeof env !== "object" || !["preflight", "canary"].includes(mode)
  ) {
    throw new HomologationRunnerError("invalid_mode");
  }
  const firebaseProjectId = env.FIREBASE_PROJECT_ID;
  const productionFirebaseId = env.FIREBASE_PRODUCTION_PROJECT_ID;
  const approvedFirebaseProjectId =
    env.CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID;
  const approvedServiceAccountEmail =
    env.CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL;
  const supabaseProjectRef = env.SUPABASE_PROJECT_REF;
  const productionSupabaseRef = env.SUPABASE_PRODUCTION_PROJECT_REF;
  const approvedSupabaseRef = env.CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF;
  if (
    env.CATALOG_HOMOLOGATION_ENVIRONMENT !== "staging" ||
    env.CATALOG_HOMOLOGATION_EXCLUSIVE_ENVIRONMENT !== "true" ||
    typeof firebaseProjectId !== "string" ||
    !STAGING_MARKER.test(firebaseProjectId) ||
    approvedFirebaseProjectId !== firebaseProjectId ||
    firebaseProjectId === "tudo-aqui-macacu" ||
    firebaseProjectId === "demo-universal-search" ||
    typeof productionFirebaseId !== "string" ||
    productionFirebaseId !== "tudo-aqui-macacu" ||
    typeof approvedServiceAccountEmail !== "string" ||
    !approvedServiceAccountEmail.endsWith(
      `@${firebaseProjectId}.iam.gserviceaccount.com`,
    ) ||
    firebaseProjectId === productionFirebaseId ||
    typeof supabaseProjectRef !== "string" ||
    !PROJECT_REF.test(supabaseProjectRef) ||
    approvedSupabaseRef !== supabaseProjectRef ||
    typeof productionSupabaseRef !== "string" ||
    !PROJECT_REF.test(productionSupabaseRef) ||
    supabaseProjectRef === productionSupabaseRef
  ) {
    throw new HomologationRunnerError("staging_target_rejected");
  }
  if (
    mode === "canary" && (env.CATALOG_HOMOLOGATION_ENABLED !== "true" ||
      env.CATALOG_HOMOLOGATION_CONFIRM !==
        `RUN STAGING CANARY ${firebaseProjectId} ${supabaseProjectRef}`)
  ) {
    throw new HomologationRunnerError("canary_not_armed");
  }
  if (
    env.SUPABASE_SERVICE_ROLE_KEY !== undefined ||
    env.SUPABASE_ACCESS_TOKEN !== undefined ||
    env.GOOGLE_APPLICATION_CREDENTIALS !== undefined
  ) {
    throw new HomologationRunnerError(
      "privileged_or_implicit_credentials_rejected",
    );
  }
  validateFirebasePrivateKey(
    env.FIREBASE_SERVICE_ACCOUNT_JSON,
    firebaseProjectId,
    approvedServiceAccountEmail,
  );

  const publishableKey = env.SUPABASE_PUBLISHABLE_KEY;
  if (!isPublishableKey(publishableKey)) {
    throw new HomologationRunnerError("public_key_rejected");
  }
  const consumerConfig = resolveCatalogOutboxConsumerConfig({
    ...env,
    CATALOG_CONSUMER_ENABLED: "true",
    CATALOG_DATABASE_MODE: "hosted",
    CATALOG_CONSUMER_HOMOLOGATION: "true",
    CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID: productionFirebaseId,
    CATALOG_HOMOLOGATION_PRODUCTION_SUPABASE_REF: productionSupabaseRef,
  });
  if (!consumerConfig.enabled || !validHmacSecret(consumerConfig.hmacSecret)) {
    throw new HomologationRunnerError("consumer_configuration_rejected");
  }
  const suppliedSupabaseUrl = env.SUPABASE_URL;
  const expectedSupabaseUrl = `https://${supabaseProjectRef}.supabase.co`;
  if (
    suppliedSupabaseUrl !== undefined &&
    normalizeOrigin(suppliedSupabaseUrl) !== expectedSupabaseUrl
  ) {
    throw new HomologationRunnerError("supabase_url_mismatch");
  }
  const consumerUrl =
    `${expectedSupabaseUrl}/functions/v1/consume-catalog-outbox`;
  return Object.freeze({
    mode,
    firebaseProjectId,
    firebaseServiceAccountEmail: approvedServiceAccountEmail,
    supabaseProjectRef,
    supabaseUrl: expectedSupabaseUrl,
    consumerUrl,
    databaseHost: new URL(consumerConfig.databaseUrl).hostname,
    databaseUsername: new URL(consumerConfig.databaseUrl).username,
    databaseTlsRequired: true,
    exclusiveEnvironmentAttested: true,
    ...(mode === "canary" ? { armed: true } : { armed: false }),
  });
}

/** Creates only fictional data and a projection using the production allowlist. */
export function makeSyntheticCanary(
  {
    id = `modelo-homologation-${crypto.randomUUID()}`,
    operationId = crypto.randomUUID(),
    now = Date.now,
  } = {},
) {
  if (
    typeof id !== "string" ||
    !/^modelo-homologation-[a-f0-9-]{8,64}$/u.test(id) ||
    typeof operationId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu
      .test(operationId) ||
    typeof now !== "function"
  ) throw new HomologationRunnerError("invalid_canary_fixture");
  const timestamp = now();
  if (!Number.isSafeInteger(timestamp) || timestamp < 0) {
    throw new HomologationRunnerError("invalid_canary_clock");
  }
  const canonical = Object.freeze({
    name: "Estabelecimento sintético de homologação",
    description:
      "Registro fictício usado somente para validar a sincronização.",
    category: "Comércio",
    subcategory: "Homologação",
    location: "Localidade fictícia",
    published: true,
    active: true,
    publicContactApproved: false,
    catalogVersion: 1,
    outboxOperationId: operationId,
    createdAt: new Date(timestamp),
    updatedAt: new Date(timestamp),
    deletedAt: null,
    homologationPrivateSentinel: PRIVATE_SENTINEL,
    ownerEmail: "synthetic-owner@example.invalid",
    adminNote: PRIVATE_SENTINEL,
  });
  const event = Object.freeze({
    schemaVersion: 2,
    operationId,
    entityType: "establishment",
    entityId: id,
    authorUid: "homologation-runner",
    version: 1,
    operation: "reconcile",
    state: "pending",
    attemptCount: 0,
    workerId: null,
    leaseToken: null,
    leaseExpiresAt: null,
    nextAttemptAt: null,
    lastErrorCode: null,
    syncedAt: null,
    createdAt: new Date(timestamp),
    updatedAt: new Date(timestamp),
  });
  const projection = projectCanonicalEstablishment(id, canonical, event);
  if (!projection) {
    throw new HomologationRunnerError("canary_projection_invalid");
  }
  return Object.freeze({ id, operationId, canonical, event, projection });
}

export async function createConsumerSignature(
  secret,
  pathname,
  timestampSeconds = Math.floor(Date.now() / 1000),
) {
  if (
    !validHmacSecret(secret) || typeof pathname !== "string" ||
    !pathname.startsWith("/") ||
    !Number.isSafeInteger(timestampSeconds) ||
    timestampSeconds < 1_000_000_000 || timestampSeconds > 9_999_999_999
  ) {
    throw new HomologationRunnerError("invalid_signature_input");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const message =
    `catalog-outbox-consumer-v1\nPOST\n${pathname}\n${timestampSeconds}`;
  const digest = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)),
  );
  let binary = "";
  for (const byte of digest) binary += String.fromCharCode(byte);
  return `${timestampSeconds}.${
    btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "")
  }`;
}

/** Runs a canary using injected adapters; it never deletes the synthetic pair. */
export async function runHomologationCanary(
  { config, adapters, canaryFactory = () => makeSyntheticCanary() },
) {
  if (
    !config || config.mode !== "canary" || config.armed !== true || !adapters ||
    [
      "inspectPostgres",
      "inspectFirestoreQueue",
      "inspectCheckpoint",
      "rejectInvalidHmac",
      "createCanaryPair",
      "readCanaryPair",
      "invokeConsumer",
      "replayRestrictedWriter",
      "readPublicRpc",
      "rejectDirectTableRead",
    ]
      .some((name) => typeof adapters[name] !== "function")
  ) throw new HomologationRunnerError("canary_configuration_rejected");
  const checks = Object.create(null);
  checks.firebaseServiceAccountMatchesApprovedIdentity = true;
  const db = await safeCall(adapters.inspectPostgres, "postgres_probe_failed");
  if (
    db.role !== "catalog_writer_v2_login" || db.tls !== true ||
    db.superuser !== false || db.restrictedRoleAttributes !== true ||
    db.expectedExecutorMembership !== true ||
    db.noUnexpectedMemberships !== true ||
    db.publicSchemaCreate !== false ||
    db.executeProjection !== true || db.executeTombstone !== true ||
    db.tablePrivileges !== false
  ) {
    throw new HomologationRunnerError(
      "postgres_identity_or_privileges_rejected",
    );
  }
  checks.restrictedPostgresTls = true;
  checks.restrictedPostgresRole = true;
  checks.privateWriterRpcsGranted = true;
  checks.directCatalogTableAccessDenied = true;
  if (
    (await safeCall(
      adapters.inspectFirestoreQueue,
      "firestore_queue_probe_failed",
    )).empty !== true
  ) {
    throw new HomologationRunnerError("staging_outbox_not_empty");
  }
  checks.firestoreOutboxReadAllowed = true;
  if (
    (await safeCall(
      adapters.inspectCheckpoint,
      "firestore_checkpoint_probe_failed",
    )).idle !== true
  ) {
    throw new HomologationRunnerError("staging_checkpoint_not_idle");
  }
  checks.firestoreCheckpointReadAllowed = true;
  checks.stagingQueueEmpty = true;
  const invalidHmac = await safeCall(
    adapters.rejectInvalidHmac,
    "consumer_hmac_probe_failed",
  );
  if (invalidHmac.status !== 401) {
    throw new HomologationRunnerError("consumer_hmac_not_rejected");
  }
  checks.consumerHmacRejected = true;

  const canary = canaryFactory();
  let created = false;
  try {
    const creation = await safeCall(
      () => adapters.createCanaryPair(canary),
      "canary_pair_create_failed",
    );
    if (creation.created !== true) {
      throw new HomologationRunnerError("canary_pair_not_created");
    }
    created = true;
    checks.atomicCanaryPairCreated = true;
    checks.firestoreCanaryCreateAllowed = true;
    let pair = await safeCall(
      () => adapters.readCanaryPair(canary),
      "canary_pair_read_failed",
    );
    if (!samePair(pair, canary, "pending")) {
      throw new HomologationRunnerError("canary_pair_mismatch");
    }
    const consumed = await safeCall(
      () => adapters.invokeConsumer(canary),
      "consumer_invocation_failed",
    );
    if (
      consumed.status !== 200 || consumed.body?.ok !== true ||
      consumed.body?.processed !== 1 ||
      consumed.body?.claimed !== 1 || consumed.body?.states?.synced !== 1
    ) {
      throw new HomologationRunnerError("consumer_not_confirmed");
    }
    pair = await safeCall(
      () => adapters.readCanaryPair(canary),
      "canary_ack_read_failed",
    );
    if (!samePair(pair, canary, "synced")) {
      throw new HomologationRunnerError("firestore_ack_not_confirmed");
    }
    checks.consumerAcknowledged = true;
    checks.firestoreConsumerUpdateAllowed = true;
    const replay = await safeCall(
      () => adapters.replayRestrictedWriter(canary.projection),
      "writer_replay_failed",
    );
    if (replay.result !== "duplicate") {
      throw new HomologationRunnerError("writer_replay_not_idempotent");
    }
    checks.idempotentReplay = true;
    const publicRow = await safeCall(
      () => adapters.readPublicRpc(canary.id),
      "public_rpc_probe_failed",
    );
    if (!validPublicCanaryRow(publicRow, canary)) {
      throw new HomologationRunnerError("public_projection_invalid");
    }
    checks.publicProjectionAllowlisted = true;
    const directRead = await safeCall(
      () => adapters.rejectDirectTableRead(canary.id),
      "direct_table_probe_failed",
    );
    if (![401, 403].includes(directRead.status)) {
      throw new HomologationRunnerError("direct_table_read_not_denied");
    }
    checks.directTableReadDenied = true;
    return Object.freeze({
      ok: true,
      checks: Object.freeze({ ...checks }),
      canary: Object.freeze({ id: canary.id, operationId: canary.operationId }),
      processed: 1,
    });
  } catch (error) {
    if (error instanceof HomologationRunnerError) {
      if (created) {
        error.canary = Object.freeze({
          id: canary.id,
          operationId: canary.operationId,
        });
      }
      throw error;
    }
    throw new HomologationRunnerError(
      "homologation_failed",
      created ? canary : null,
    );
  }
}

function samePair(pair, canary, expectedState) {
  return pair?.canonical?.catalogVersion === 1 &&
    pair.canonical.outboxOperationId === canary.operationId &&
    pair?.event?.schemaVersion === 2 &&
    pair.event.operationId === canary.operationId &&
    pair.event.entityId === canary.id && pair.event.version === 1 &&
    pair.event.state === expectedState;
}

function validPublicCanaryRow(row, canary) {
  const value = Array.isArray(row) ? row.length === 1 ? row[0] : null : row;
  return value && typeof value === "object" && !Array.isArray(value) &&
    value.id === canary.id &&
    value.catalog_version === undefined &&
    value.outbox_operation_id === undefined &&
    Object.keys(value).every((key) => PUBLIC_FIELDS.has(key)) &&
    !Object.values(value).includes(PRIVATE_SENTINEL) &&
    !JSON.stringify(value).includes("synthetic-owner@example.invalid");
}

function isPublishableKey(value) {
  if (typeof value !== "string" || value.length < 20 || value.length > 8_192) {
    return false;
  }
  if (/^sb_publishable_[A-Za-z0-9_-]{16,}$/u.test(value)) return true;
  const pieces = value.split(".");
  if (pieces.length !== 3) return false;
  try {
    const payload = JSON.parse(
      atob(
        pieces[1].replaceAll("-", "+").replaceAll("_", "/") +
          "=".repeat((4 - pieces[1].length % 4) % 4),
      ),
    );
    return payload?.role === "anon" && Number.isSafeInteger(payload.exp) &&
      payload.exp > Date.now() / 1000;
  } catch {
    return false;
  }
}

function validHmacSecret(value) {
  return typeof value === "string" &&
    new TextEncoder().encode(value).byteLength >= 32 &&
    new TextEncoder().encode(value).byteLength <= 256;
}

function validateFirebasePrivateKey(raw, projectId, approvedEmail) {
  try {
    if (typeof raw !== "string" || raw.length > 32 * 1_024) throw new Error();
    const account = JSON.parse(raw);
    if (
      account.project_id !== projectId ||
      account.type !== "service_account" ||
      account.client_email !== approvedEmail ||
      typeof account.private_key !== "string"
    ) throw new Error();
    const key = createPrivateKey(account.private_key.replaceAll("\\n", "\n"));
    if (
      key.asymmetricKeyType !== "rsa" ||
      (key.asymmetricKeyDetails?.modulusLength ?? 0) < 2_048
    ) throw new Error();
  } catch {
    throw new HomologationRunnerError("firebase_identity_credential_rejected");
  }
}

function normalizeOrigin(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password &&
        !url.pathname.replaceAll("/", "") && !url.search && !url.hash
      ? url.origin
      : null;
  } catch {
    return null;
  }
}

async function safeCall(callback, code) {
  try {
    return await callback();
  } catch {
    throw new HomologationRunnerError(code);
  }
}
