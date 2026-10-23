import assert from "node:assert/strict";
import test from "node:test";
import { resolveCatalogOutboxConsumerConfig } from "./catalog_outbox_consumer_config.mjs";

const secret = "synthetic-hmac-secret-not-real-32-bytes";
const serviceAccount = JSON.stringify({
  type: "service_account",
  project_id: "demo-universal-search",
  client_email: "synthetic@demo-universal-search.iam.gserviceaccount.com",
  private_key: "synthetic-only-not-a-real-key",
});
const local = {
  CATALOG_CONSUMER_ENABLED: "true",
  CATALOG_DATABASE_MODE: "local",
  FIREBASE_PROJECT_ID: "demo-universal-search",
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8087",
  SUPABASE_CATALOG_DATABASE_URL:
    "postgres://catalog_writer_v2_login:synthetic-password@127.0.0.1:54329/postgres",
  CATALOG_CONSUMER_HMAC_SECRET: secret,
};

test("consumer stays disabled unless explicitly enabled", () => {
  assert.deepEqual(resolveCatalogOutboxConsumerConfig({}), { enabled: false });
  assert.deepEqual(
    resolveCatalogOutboxConsumerConfig({ CATALOG_CONSUMER_ENABLED: "false" }),
    {
      enabled: false,
    },
  );
});

test("local mode is scoped to the demo Firestore Emulator and dedicated PostgreSQL login", () => {
  const result = resolveCatalogOutboxConsumerConfig(local);
  assert.equal(result.enabled, true);
  assert.equal(result.projectId, "demo-universal-search");
  assert.equal(result.databaseMode, "local");
  assert.equal(result.databaseUrl, local.SUPABASE_CATALOG_DATABASE_URL);
  assert.equal(result.firestoreEmulatorHost, "127.0.0.1:8087");
  assert.equal(result.hmacSecret, secret);
  assert.equal(Object.hasOwn(result, "serviceRoleKey"), false);
  assert.equal(Object.hasOwn(result, "supabaseApiKey"), false);
});

test("consumer rejects incomplete local configuration and never falls back to service_role", () => {
  const missingDatabase = { ...local };
  delete missingDatabase.SUPABASE_CATALOG_DATABASE_URL;
  assert.deepEqual(resolveCatalogOutboxConsumerConfig(missingDatabase), {
    enabled: false,
  });

  const serviceRoleOnly = {
    ...local,
    SUPABASE_CATALOG_DATABASE_URL: undefined,
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role-key-not-real",
  };
  assert.deepEqual(resolveCatalogOutboxConsumerConfig(serviceRoleOnly), {
    enabled: false,
  });

  const mixedCredentials = {
    ...local,
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role-key-not-real",
  };
  assert.deepEqual(resolveCatalogOutboxConsumerConfig(mixedCredentials), {
    enabled: false,
  });
});

test("local mode rejects non-demo projects, non-loopback emulators, other DB roles, and remote hosts", () => {
  for (
    const overrides of [
      { FIREBASE_PROJECT_ID: "tudo-aqui-macacu" },
      { FIRESTORE_EMULATOR_HOST: "192.168.1.10:8087" },
      {
        SUPABASE_CATALOG_DATABASE_URL:
          "postgres://service_role:synthetic-password@127.0.0.1:54329/postgres",
      },
      {
        SUPABASE_CATALOG_DATABASE_URL:
          "postgres://catalog_writer_v2_login:synthetic-password@db.example.invalid:5432/postgres",
      },
      {
        SUPABASE_CATALOG_DATABASE_URL:
          "postgres://catalog_writer_v2_login:synthetic-password@127.0.0.1:54329/postgres?sslmode=disable",
      },
    ]
  ) {
    assert.deepEqual(
      resolveCatalogOutboxConsumerConfig({ ...local, ...overrides }),
      { enabled: false },
    );
  }
});

test("hosted mode requires the restricted pooler identity, TLS-capable endpoint, and project credentials", () => {
  const env = {
    CATALOG_CONSUMER_ENABLED: "true",
    CATALOG_DATABASE_MODE: "hosted",
    FIREBASE_PROJECT_ID: "demo-universal-search",
    FIREBASE_SERVICE_ACCOUNT_JSON: serviceAccount,
    SUPABASE_PROJECT_REF: "pilotref123456789012",
    SUPABASE_CATALOG_DATABASE_URL:
      "postgres://catalog_writer_v2_login.pilotref123456789012:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres",
    CATALOG_CONSUMER_HMAC_SECRET: secret,
  };
  const result = resolveCatalogOutboxConsumerConfig(env);
  assert.equal(result.enabled, true);
  assert.equal(result.databaseMode, "hosted");
  assert.equal(result.databaseUrl, env.SUPABASE_CATALOG_DATABASE_URL);
  assert.equal(result.supabaseProjectRef, env.SUPABASE_PROJECT_REF);
  assert.equal(result.serviceAccountJson, serviceAccount);
  assert.equal(Object.hasOwn(result, "serviceRoleKey"), false);

  for (
    const databaseUrl of [
      "postgres://service_role.pilotref123456789012:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres",
      "postgres://catalog_writer_v2_login.wrongref123456789012:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres",
      "postgres://catalog_writer_v2_login.pilotref123456789012:synthetic-password@db.pilotref123456789012.supabase.co:5432/postgres",
      "postgres://catalog_writer_v2_login.pilotref123456789012:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres?sslmode=disable",
    ]
  ) {
    assert.deepEqual(
      resolveCatalogOutboxConsumerConfig({
        ...env,
        SUPABASE_CATALOG_DATABASE_URL: databaseUrl,
      }),
      { enabled: false },
    );
  }
});

test("hosted homologation mode requires an isolated staging Firebase project and a distinct production Supabase reference", () => {
  const stagingProject = "macacu-staging-261022";
  const stagingRef = "stagehomologation123";
  const env = {
    CATALOG_CONSUMER_ENABLED: "true",
    CATALOG_DATABASE_MODE: "hosted",
    CATALOG_CONSUMER_HOMOLOGATION: "true",
    CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID: "tudo-aqui-macacu",
    CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID: stagingProject,
    CATALOG_HOMOLOGATION_PRODUCTION_SUPABASE_REF: "prodref1234567890123",
    FIREBASE_PROJECT_ID: stagingProject,
    FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
      type: "service_account",
      project_id: stagingProject,
      client_email: `consumer@${stagingProject}.iam.gserviceaccount.com`,
      private_key: "synthetic-only-not-a-real-key",
    }),
    SUPABASE_PROJECT_REF: stagingRef,
    CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF: stagingRef,
    SUPABASE_CATALOG_DATABASE_URL:
      `postgres://catalog_writer_v2_login.${stagingRef}:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres`,
    CATALOG_CONSUMER_HMAC_SECRET: secret,
  };
  const result = resolveCatalogOutboxConsumerConfig(env);
  assert.equal(result.enabled, true);
  assert.equal(result.homologationProjectId, stagingProject);
  for (
    const override of [
      { FIREBASE_PROJECT_ID: "tudo-aqui-macacu" },
      { FIREBASE_PROJECT_ID: "demo-universal-search" },
      {
        FIREBASE_PROJECT_ID: "macacu-staging",
        CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID: "macacu-staging",
      },
      { CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID: "another-staging-project" },
      {
        SUPABASE_PROJECT_REF: "prodref1234567890123",
        SUPABASE_CATALOG_DATABASE_URL:
          "postgres://catalog_writer_v2_login.prodref1234567890123:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres",
      },
      { CATALOG_HOMOLOGATION_PRODUCTION_SUPABASE_REF: "stagehomologation123" },
      { CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF: "prodref1234567890123" },
      {
        CATALOG_CONSUMER_HOMOLOGATION: "true",
        CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID: undefined,
      },
    ]
  ) {
    assert.deepEqual(
      resolveCatalogOutboxConsumerConfig({ ...env, ...override }),
      { enabled: false },
    );
  }
});
