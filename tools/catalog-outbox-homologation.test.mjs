import assert from "node:assert/strict";
import { createHmac, generateKeyPairSync } from "node:crypto";
import test from "node:test";
import {
  createConsumerSignature,
  HomologationRunnerError,
  makeSyntheticCanary,
  resolveHomologationConfig,
  runHomologationCanary,
} from "./catalog-outbox-homologation.mjs";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const stagingProject = "macacu-homologation";
const stagingRef = "stagehomologation123";
const serviceAccount = JSON.stringify({
  type: "service_account",
  project_id: stagingProject,
  client_email: `consumer@${stagingProject}.iam.gserviceaccount.com`,
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
});
const env = {
  CATALOG_HOMOLOGATION_ENVIRONMENT: "staging",
  CATALOG_HOMOLOGATION_EXCLUSIVE_ENVIRONMENT: "true",
  CATALOG_HOMOLOGATION_ENABLED: "true",
  CATALOG_HOMOLOGATION_CONFIRM:
    `RUN STAGING CANARY ${stagingProject} ${stagingRef}`,
  FIREBASE_PROJECT_ID: stagingProject,
  FIREBASE_PRODUCTION_PROJECT_ID: "tudo-aqui-macacu",
  CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID: stagingProject,
  CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL:
    `consumer@${stagingProject}.iam.gserviceaccount.com`,
  FIREBASE_SERVICE_ACCOUNT_JSON: serviceAccount,
  SUPABASE_PROJECT_REF: stagingRef,
  CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF: stagingRef,
  SUPABASE_PRODUCTION_PROJECT_REF: "prodref1234567890123",
  SUPABASE_PUBLISHABLE_KEY: "sb_publishable_synthetic_key_for_tests_only",
  SUPABASE_CATALOG_DATABASE_URL:
    `postgres://catalog_writer_v2_login.${stagingRef}:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres`,
  CATALOG_CONSUMER_HMAC_SECRET:
    "synthetic-hmac-secret-for-offline-tests-only-32-bytes",
};

test("homologation gate accepts explicitly armed isolated staging identifiers without exposing credentials", () => {
  const config = resolveHomologationConfig(env, { mode: "canary" });
  assert.equal(config.firebaseProjectId, stagingProject);
  assert.equal(config.supabaseProjectRef, stagingRef);
  assert.equal(
    config.firebaseServiceAccountEmail,
    env.CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL,
  );
  assert.equal(
    config.consumerUrl,
    `https://${stagingRef}.supabase.co/functions/v1/consume-catalog-outbox`,
  );
  assert.equal(JSON.stringify(config).includes("synthetic-password"), false);
  assert.equal(JSON.stringify(config).includes("synthetic-hmac"), false);
});

test("approved Firebase staging IDs may contain a unique suffix after the staging marker", () => {
  const projectId = "macacu-staging-261022";
  const actualServiceAccount = JSON.stringify({
    ...JSON.parse(serviceAccount),
    project_id: projectId,
    client_email: `consumer@${projectId}.iam.gserviceaccount.com`,
  });
  const config = resolveHomologationConfig({
    ...env,
    FIREBASE_PROJECT_ID: projectId,
    CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID: projectId,
    CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL:
      `consumer@${projectId}.iam.gserviceaccount.com`,
    FIREBASE_SERVICE_ACCOUNT_JSON: actualServiceAccount,
  });
  assert.equal(config.firebaseProjectId, projectId);
  assert.throws(() => resolveHomologationConfig({
    ...env,
    FIREBASE_PROJECT_ID: projectId,
    CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID: stagingProject,
    CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL:
      `consumer@${projectId}.iam.gserviceaccount.com`,
    FIREBASE_SERVICE_ACCOUNT_JSON: actualServiceAccount,
  }), HomologationRunnerError);
});

test("homologation preflight rejects production, demo, same-as-production, incomplete, and privileged configurations", () => {
  const invalid = [
    { FIREBASE_PROJECT_ID: "tudo-aqui-macacu" },
    { FIREBASE_PROJECT_ID: "demo-universal-search" },
    {
      FIREBASE_PROJECT_ID: "macacu-staging",
      FIREBASE_PRODUCTION_PROJECT_ID: "macacu-staging",
    },
    {
      SUPABASE_PROJECT_REF: "prodref1234567890123",
      SUPABASE_PRODUCTION_PROJECT_REF: "prodref1234567890123",
    },
    { CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF: "wrongstagingref12345" },
    {
      SUPABASE_CATALOG_DATABASE_URL: env.SUPABASE_CATALOG_DATABASE_URL.replace(
        "catalog_writer_v2_login",
        "service_role",
      ),
    },
    { SUPABASE_SERVICE_ROLE_KEY: "should-never-be-present" },
    { FIREBASE_SERVICE_ACCOUNT_JSON: undefined },
    {
      CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL:
        `other@${stagingProject}.iam.gserviceaccount.com`,
    },
    {
      FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
        ...JSON.parse(serviceAccount),
        private_key: "not-a-private-key",
      }),
    },
    { CATALOG_CONSUMER_HMAC_SECRET: undefined },
    {
      SUPABASE_PUBLISHABLE_KEY:
        "eyJhbGciOiJub25lIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature",
    },
    { CATALOG_HOMOLOGATION_EXCLUSIVE_ENVIRONMENT: "false" },
  ];
  for (const override of invalid) {
    assert.throws(
      () =>
        resolveHomologationConfig({ ...env, ...override }, {
          mode: "preflight",
        }),
      HomologationRunnerError,
    );
  }
  assert.throws(
    () =>
      resolveHomologationConfig({
        ...env,
        CATALOG_HOMOLOGATION_ENABLED: "false",
      }, { mode: "canary" }),
    HomologationRunnerError,
  );
  assert.throws(
    () =>
      resolveHomologationConfig(
        { ...env, CATALOG_HOMOLOGATION_CONFIRM: "yes" },
        { mode: "canary" },
      ),
    HomologationRunnerError,
  );
});

test("synthetic canary is a V2 atomic pair and public projection excludes private markers", () => {
  const canary = makeSyntheticCanary({
    id: "modelo-homologation-00000001",
    operationId: "71000000-0000-4000-8000-000000000001",
    now: () => 1_792_684_800_000,
  });
  assert.equal(canary.event.schemaVersion, 2);
  assert.equal(canary.event.state, "pending");
  assert.equal(canary.event.attemptCount, 0);
  assert.equal(canary.canonical.catalogVersion, 1);
  assert.equal(canary.canonical.outboxOperationId, canary.event.operationId);
  assert.equal(
    canary.canonical.homologationPrivateSentinel,
    "PRIVATE_HOMOLOGATION_SENTINEL",
  );
  assert.equal(
    Object.hasOwn(canary.projection, "homologationPrivateSentinel"),
    false,
  );
  assert.equal(Object.hasOwn(canary.projection, "ownerEmail"), false);
});

test("consumer HMAC uses the exact versioned method, path, and timestamp challenge", async () => {
  const timestamp = 1_792_684_800;
  const signed = await createConsumerSignature(
    env.CATALOG_CONSUMER_HMAC_SECRET,
    "/functions/v1/consume-catalog-outbox",
    timestamp,
  );
  const expected = createHmac("sha256", env.CATALOG_CONSUMER_HMAC_SECRET)
    .update(
      `catalog-outbox-consumer-v1\nPOST\n/functions/v1/consume-catalog-outbox\n${timestamp}`,
    )
    .digest("base64url");
  assert.equal(signed, `${timestamp}.${expected}`);
  await assert.rejects(
    createConsumerSignature("short", "/consume", timestamp),
    HomologationRunnerError,
  );
});

test("canary runner checks identity, TLS, least-privilege, empty queue, HMAC rejection, sync, replay, and public projection in order", async () => {
  const config = resolveHomologationConfig(env, { mode: "canary" });
  const calls = [];
  const canary = makeSyntheticCanary({
    id: "modelo-homologation-00000001",
    operationId: "71000000-0000-4000-8000-000000000001",
  });
  let consumed = false;
  const adapters = {
    inspectPostgres: async () => {
      calls.push("postgres");
      return {
        role: "catalog_writer_v2_login",
        tls: true,
        superuser: false,
        restrictedRoleAttributes: true,
        expectedExecutorMembership: true,
        noUnexpectedMemberships: true,
        publicSchemaCreate: false,
        executeProjection: true,
        executeTombstone: true,
        tablePrivileges: false,
      };
    },
    inspectFirestoreQueue: async () => {
      calls.push("queue");
      return { empty: true };
    },
    inspectCheckpoint: async () => {
      calls.push("checkpoint");
      return { idle: true, cursor: null };
    },
    rejectInvalidHmac: async () => {
      calls.push("invalid-hmac");
      return { status: 401 };
    },
    createCanaryPair: async (value) => {
      calls.push("create-pair");
      assert.deepEqual(value, canary);
      return { created: true };
    },
    readCanaryPair: async () => {
      calls.push("read-pair");
      return {
        canonical: canary.canonical,
        event: { ...canary.event, state: consumed ? "synced" : "pending" },
      };
    },
    invokeConsumer: async () => {
      calls.push("consume");
      consumed = true;
      return {
        status: 200,
        body: { ok: true, processed: 1, claimed: 1, states: { synced: 1 } },
      };
    },
    replayRestrictedWriter: async () => {
      calls.push("replay");
      return { result: "duplicate" };
    },
    readPublicRpc: async () => {
      calls.push("public-rpc");
      return { id: canary.id, name: canary.canonical.name };
    },
    rejectDirectTableRead: async () => {
      calls.push("direct-table");
      return { status: 403 };
    },
  };
  const result = await runHomologationCanary({
    config,
    adapters,
    canaryFactory: () => canary,
  });
  assert.deepEqual(calls, [
    "postgres",
    "queue",
    "checkpoint",
    "invalid-hmac",
    "create-pair",
    "read-pair",
    "consume",
    "read-pair",
    "replay",
    "public-rpc",
    "direct-table",
  ]);
  assert.equal(result.checks.restrictedPostgresTls, true);
  assert.equal(result.checks.restrictedPostgresRole, true);
  assert.equal(result.checks.privateWriterRpcsGranted, true);
  assert.equal(result.checks.directCatalogTableAccessDenied, true);
  assert.equal(result.checks.firestoreOutboxReadAllowed, true);
  assert.equal(result.checks.firestoreCanaryCreateAllowed, true);
  assert.equal(result.checks.firestoreConsumerUpdateAllowed, true);
  assert.equal(result.checks.consumerHmacRejected, true);
  assert.equal(result.checks.consumerAcknowledged, true);
  assert.equal(result.checks.idempotentReplay, true);
  assert.equal(result.checks.publicProjectionAllowlisted, true);
});

test("canary refuses a non-empty queue or unsafe database identity before writing anything", async () => {
  const config = resolveHomologationConfig(env, { mode: "canary" });
  let writes = 0;
  const safeDb = {
    role: "catalog_writer_v2_login",
    tls: true,
    superuser: false,
    restrictedRoleAttributes: true,
    expectedExecutorMembership: true,
    noUnexpectedMemberships: true,
    publicSchemaCreate: false,
    executeProjection: true,
    executeTombstone: true,
    tablePrivileges: false,
  };
  const base = {
    inspectPostgres: async () => safeDb,
    inspectFirestoreQueue: async () => ({ empty: true }),
    inspectCheckpoint: async () => ({ idle: true, cursor: null }),
    rejectInvalidHmac: async () => ({ status: 401 }),
    createCanaryPair: async () => {
      writes += 1;
      return { created: true };
    },
    readCanaryPair: async () => ({}),
    invokeConsumer: async () => ({ status: 503, body: {} }),
    replayRestrictedWriter: async () => ({ result: "invalid" }),
    readPublicRpc: async () => ({}),
    rejectDirectTableRead: async () => ({ status: 200 }),
  };
  const unsafeDatabaseCases = [
    { role: "service_role" },
    { tls: false },
    { superuser: true },
    { restrictedRoleAttributes: false },
    { expectedExecutorMembership: false },
    { noUnexpectedMemberships: false },
    { publicSchemaCreate: true },
    { executeProjection: false },
    { executeTombstone: false },
    { tablePrivileges: true },
  ];
  for (const override of unsafeDatabaseCases) {
    await assert.rejects(
      runHomologationCanary({
        config,
        adapters: {
          ...base,
          inspectPostgres: async () => ({ ...safeDb, ...override }),
        },
      }),
      HomologationRunnerError,
    );
    assert.equal(writes, 0);
  }
  await assert.rejects(
    runHomologationCanary({
      config,
      adapters: {
        ...base,
        inspectFirestoreQueue: async () => ({ empty: false }),
      },
    }),
    HomologationRunnerError,
  );
  assert.equal(writes, 0);
});

test("failed canary after atomic creation reports synthetic identifiers without deleting data or leaking secrets", async () => {
  const config = resolveHomologationConfig(env, { mode: "canary" });
  const canary = makeSyntheticCanary({
    id: "modelo-homologation-00000001",
    operationId: "71000000-0000-4000-8000-000000000001",
  });
  const adapters = {
    inspectPostgres: async () => ({
      role: "catalog_writer_v2_login",
      tls: true,
      superuser: false,
      restrictedRoleAttributes: true,
      expectedExecutorMembership: true,
      noUnexpectedMemberships: true,
      publicSchemaCreate: false,
      executeProjection: true,
      executeTombstone: true,
      tablePrivileges: false,
    }),
    inspectFirestoreQueue: async () => ({ empty: true }),
    inspectCheckpoint: async () => ({ idle: true, cursor: null }),
    rejectInvalidHmac: async () => ({ status: 401 }),
    createCanaryPair: async () => ({ created: true }),
    readCanaryPair: async () => ({
      canonical: canary.canonical,
      event: canary.event,
    }),
    invokeConsumer: async () => ({
      status: 503,
      body: { error: "consumer_unavailable" },
    }),
    replayRestrictedWriter: async () => ({ result: "duplicate" }),
    readPublicRpc: async () => ({}),
    rejectDirectTableRead: async () => ({ status: 403 }),
  };
  await assert.rejects(
    runHomologationCanary({ config, adapters, canaryFactory: () => canary }),
    (error) => {
      assert.equal(error.code, "consumer_not_confirmed");
      assert.deepEqual(error.canary, {
        id: canary.id,
        operationId: canary.event.operationId,
      });
      assert.doesNotMatch(error.message, /synthetic-hmac|password|PRIVATE/u);
      return true;
    },
  );
});
