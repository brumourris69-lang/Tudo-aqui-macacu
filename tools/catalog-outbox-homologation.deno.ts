import postgres from "postgres";
import { createGoogleAccessToken } from "../supabase/functions/_shared/firebase_signing_keys.mjs";
import { createCatalogPostgresRpcDriver } from "../supabase/functions/_shared/catalog_postgres_driver.mjs";
import { createSupabaseCatalogWriterV2 } from "../supabase/functions/_shared/supabase_catalog_writer_v2.mjs";
import {
  createConsumerSignature,
  HomologationRunnerError,
  resolveHomologationConfig,
  runHomologationCanary,
} from "./catalog-outbox-homologation.mjs";

const ENV_NAMES = [
  "CATALOG_HOMOLOGATION_ENVIRONMENT",
  "CATALOG_HOMOLOGATION_EXCLUSIVE_ENVIRONMENT",
  "CATALOG_HOMOLOGATION_ENABLED",
  "CATALOG_HOMOLOGATION_CONFIRM",
  "FIREBASE_PROJECT_ID",
  "FIREBASE_PRODUCTION_PROJECT_ID",
  "CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID",
  "CATALOG_HOMOLOGATION_APPROVED_FIREBASE_SERVICE_ACCOUNT_EMAIL",
  "FIREBASE_SERVICE_ACCOUNT_JSON",
  "SUPABASE_PROJECT_REF",
  "SUPABASE_PRODUCTION_PROJECT_REF",
  "CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF",
  "SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_URL",
  "SUPABASE_CATALOG_DATABASE_URL",
  "CATALOG_CONSUMER_HMAC_SECRET",
];
const MAX_RESPONSE_BYTES = 64 * 1024;
const CHECKPOINT_ID = "consumer-v1";
type HomologationConfig = {
  firebaseProjectId: string;
  firebaseServiceAccountEmail: string;
  supabaseProjectRef: string;
  supabaseUrl: string;
  consumerUrl: string;
};
type SyntheticCanary = {
  id: string;
  operationId: string;
  canonical: Record<string, unknown>;
  event: Record<string, unknown>;
  projection: Record<string, unknown>;
};
type FirestoreValue = Record<string, unknown>;
type FirestoreDocument = {
  name: string;
  fields: Record<string, FirestoreValue>;
  updateTime?: string;
};
type FirestoreDecodedDocument = {
  name: string;
  data: Record<string, unknown>;
  updateTime?: string;
};

const args = Deno.args;
if (args.length !== 1 || !["--preflight", "--canary"].includes(args[0])) {
  console.error(
    JSON.stringify({
      ok: false,
      code: "usage",
      usage: "--preflight | --canary",
    }),
  );
  Deno.exit(2);
}

const mode = args[0] === "--canary" ? "canary" : "preflight";
const env = Object.fromEntries(
  ENV_NAMES.map((name) => [name, Deno.env.get(name)]),
);
let config: HomologationConfig;
try {
  config = resolveHomologationConfig(env, { mode });
} catch (error) {
  const record = error as { code?: unknown };
  const code =
    error instanceof HomologationRunnerError && typeof record.code === "string"
      ? record.code
      : "configuration_rejected";
  console.error(JSON.stringify({ ok: false, code }));
  Deno.exit(2);
}

if (mode === "preflight") {
  console.log(JSON.stringify({
    ok: true,
    mode: "preflight",
    networkUsed: false,
    target: {
      firebaseProjectId: config.firebaseProjectId,
      firebaseServiceAccountEmail: config.firebaseServiceAccountEmail,
      supabaseProjectRef: config.supabaseProjectRef,
    },
    checks: {
      nonProductionFirebaseTarget: true,
      distinctSupabaseProductionReference: true,
      approvedStagingProjectId: true,
      approvedServiceAccountIdentityAndKeyShape: true,
      dedicatedPostgresPoolerLogin: true,
      tlsRequiredByHostedDriver: true,
      publishableKeyOnly: true,
      hmacConfigured: true,
      canaryArmed: false,
    },
    note:
      "Static checks only. No identity, IAM, network, TLS handshake, database privileges, RPC, or hosted state was contacted.",
  }));
  Deno.exit(0);
}

try {
  const result = await runHomologationCanary({
    config,
    adapters: makeAdapters(config, env),
  });
  console.log(JSON.stringify(result));
} catch (error) {
  const record = error as {
    code?: unknown;
    canary?: { id?: unknown; operationId?: unknown };
  };
  const safe = {
    ok: false,
    code: error instanceof HomologationRunnerError &&
        typeof record.code === "string"
      ? record.code
      : "homologation_failed",
    ...(record.canary && typeof record.canary.id === "string" &&
        typeof record.canary.operationId === "string"
      ? {
        canary: {
          id: record.canary.id,
          operationId: record.canary.operationId,
        },
      }
      : {}),
  };
  console.error(JSON.stringify(safe));
  Deno.exit(1);
}

function makeAdapters(
  config: HomologationConfig,
  env: Record<string, string | undefined>,
) {
  const accountJson = requiredEnv(env, "FIREBASE_SERVICE_ACCOUNT_JSON");
  const databaseUrl = requiredEnv(env, "SUPABASE_CATALOG_DATABASE_URL");
  const hmacSecret = requiredEnv(env, "CATALOG_CONSUMER_HMAC_SECRET");
  const publishableKey = requiredEnv(env, "SUPABASE_PUBLISHABLE_KEY");
  let tokenPromise: Promise<string> | undefined;
  async function accessToken() {
    if (!tokenPromise) {
      tokenPromise = createGoogleAccessToken({
        serviceAccountJson: accountJson,
        projectId: config.firebaseProjectId,
      })
        .then((value) => value.accessToken)
        .catch(() => {
          tokenPromise = undefined;
          throw new HomologationRunnerError("firebase_token_exchange_failed");
        });
    }
    return await tokenPromise;
  }
  async function firestore(
    path: string,
    { method = "GET", body, allowNotFound = false }: {
      method?: string;
      body?: unknown;
      allowNotFound?: boolean;
    } = {},
  ): Promise<unknown> {
    const url =
      `https://firestore.googleapis.com/v1/projects/${config.firebaseProjectId}/databases/(default)/documents/${path}`;
    let response;
    try {
      response = await fetch(url, {
        method,
        headers: {
          accept: "application/json",
          authorization: `Bearer ${await accessToken()}`,
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      throw new HomologationRunnerError("firestore_request_failed");
    }
    if (allowNotFound && response.status === 404) return null;
    return await readJson(response, "firestore_response_invalid");
  }
  async function document(
    collection: string,
    id: string,
  ): Promise<FirestoreDecodedDocument | null> {
    const name = `${collection}/${encodeURIComponent(id)}`;
    const raw = await firestore(name, { allowNotFound: true }) as
      | FirestoreDocument
      | null;
    return raw ? decodeFirestoreDocument(raw) : null;
  }
  async function inspectPostgres() {
    const sql = postgres(databaseUrl, {
      max: 1,
      connect_timeout: 8,
      idle_timeout: 5,
      prepare: false,
      fetch_types: false,
      ssl: { rejectUnauthorized: true },
      connection: {
        application_name: "macacu-catalog-homologation-preflight",
        statement_timeout: 5_000,
        lock_timeout: 2_000,
        idle_in_transaction_session_timeout: 5_000,
      },
    });
    try {
      const rows = await sql.unsafe(
        `
        with recursive inherited_roles(role_oid) as (
          select membership.roleid
          from pg_auth_members membership
          where membership.member = (select oid from pg_roles where rolname = current_user)
          union
          select membership.roleid
          from pg_auth_members membership
          join inherited_roles inherited on membership.member = inherited.role_oid
        )
        select current_user::text as role_name,
          current_setting('is_superuser') = 'on' as is_superuser,
          (select not (rolcreatedb or rolcreaterole or rolreplication or rolbypassrls)
           from pg_roles where rolname = current_user) as restricted_role_attributes,
          exists (
            select 1 from inherited_roles inherited
            join pg_roles role on role.oid = inherited.role_oid
            where role.rolname = 'catalog_writer_v2'
          ) as expected_executor_membership,
          not exists (
            select 1 from inherited_roles inherited
            join pg_roles role on role.oid = inherited.role_oid
            where role.rolname <> 'catalog_writer_v2'
          ) as no_unexpected_memberships,
          not has_schema_privilege(current_user, 'public', 'CREATE') as no_public_schema_create,
          (select ssl from pg_stat_ssl where pid = pg_backend_pid()) as tls,
          has_function_privilege(current_user, 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE') as execute_projection,
          has_function_privilege(current_user, 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE') as execute_tombstone,
          (has_table_privilege(current_user, 'public.public_establishment_catalog_v2', 'SELECT') or
           has_table_privilege(current_user, 'public.public_establishment_catalog_v2', 'INSERT') or
           has_table_privilege(current_user, 'public.public_establishment_catalog_v2', 'UPDATE') or
           has_table_privilege(current_user, 'public.public_establishment_catalog_v2', 'DELETE') or
           has_table_privilege(current_user, 'public.public_establishment_catalog_v2', 'TRUNCATE') or
           has_table_privilege(current_user, 'public.public_establishment_catalog_v2', 'REFERENCES') or
           has_table_privilege(current_user, 'public.public_establishment_catalog_v2', 'TRIGGER') or
           has_any_column_privilege(current_user, 'public.public_establishment_catalog_v2', 'SELECT') or
           has_any_column_privilege(current_user, 'public.public_establishment_catalog_v2', 'INSERT') or
           has_any_column_privilege(current_user, 'public.public_establishment_catalog_v2', 'UPDATE') or
           has_any_column_privilege(current_user, 'public.public_establishment_catalog_v2', 'REFERENCES') or
           has_table_privilege(current_user, 'public.catalog_tombstones_v2', 'SELECT') or
           has_table_privilege(current_user, 'public.catalog_tombstones_v2', 'INSERT') or
           has_table_privilege(current_user, 'public.catalog_tombstones_v2', 'UPDATE') or
           has_table_privilege(current_user, 'public.catalog_tombstones_v2', 'DELETE') or
           has_table_privilege(current_user, 'public.catalog_tombstones_v2', 'TRUNCATE') or
           has_table_privilege(current_user, 'public.catalog_tombstones_v2', 'REFERENCES') or
           has_table_privilege(current_user, 'public.catalog_tombstones_v2', 'TRIGGER') or
           has_any_column_privilege(current_user, 'public.catalog_tombstones_v2', 'SELECT') or
           has_any_column_privilege(current_user, 'public.catalog_tombstones_v2', 'INSERT') or
           has_any_column_privilege(current_user, 'public.catalog_tombstones_v2', 'UPDATE') or
           has_any_column_privilege(current_user, 'public.catalog_tombstones_v2', 'REFERENCES')) as direct_table_privileges
      `,
        [],
        { prepare: false },
      );
      const row = rows[0];
      return {
        role: row?.role_name,
        superuser: row?.is_superuser,
        restrictedRoleAttributes: row?.restricted_role_attributes,
        expectedExecutorMembership: row?.expected_executor_membership,
        noUnexpectedMemberships: row?.no_unexpected_memberships,
        publicSchemaCreate: row?.no_public_schema_create === false,
        tls: row?.tls,
        executeProjection: row?.execute_projection,
        executeTombstone: row?.execute_tombstone,
        tablePrivileges: row?.direct_table_privileges,
      };
    } catch {
      throw new HomologationRunnerError("postgres_privilege_probe_failed");
    } finally {
      await sql.end({ timeout: 3 }).catch(() => {});
    }
  }
  async function consumerRequest(
    signature: string,
  ): Promise<{ status: number; body: unknown }> {
    let response;
    try {
      response = await fetch(config.consumerUrl, {
        method: "POST",
        headers: {
          apikey: publishableKey,
          "content-type": "application/json",
          "x-catalog-run-signature": signature,
        },
        body: "{}",
        signal: AbortSignal.timeout(95_000),
      });
    } catch {
      throw new HomologationRunnerError("consumer_request_failed");
    }
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
      throw new HomologationRunnerError("consumer_response_invalid");
    }
    let body;
    try {
      body = text === "" ? {} : JSON.parse(text);
    } catch {
      throw new HomologationRunnerError("consumer_response_invalid");
    }
    return { status: response.status, body };
  }
  return {
    inspectPostgres,
    async inspectFirestoreQueue() {
      const response = await firestore(":runQuery", {
        method: "POST",
        body: {
          structuredQuery: {
            from: [{ collectionId: "catalog_outbox" }],
            where: {
              fieldFilter: {
                field: { fieldPath: "state" },
                op: "IN",
                value: {
                  arrayValue: {
                    values: [{ stringValue: "pending" }, {
                      stringValue: "processing",
                    }],
                  },
                },
              },
            },
            orderBy: [{
              field: { fieldPath: "__name__" },
              direction: "ASCENDING",
            }],
            limit: 1,
          },
        },
      });
      if (!Array.isArray(response)) {
        throw new HomologationRunnerError("firestore_queue_probe_invalid");
      }
      return {
        empty: !response.some((item: unknown) =>
          isRecord(item) && item.document !== undefined
        ),
      };
    },
    async inspectCheckpoint() {
      const checkpoint = await document(
        "catalog_outbox_scan_state",
        CHECKPOINT_ID,
      );
      if (!checkpoint) return { idle: true, cursor: null };
      const data = checkpoint.data;
      return {
        idle: data.cursor === null && data.cursorReadTime === null &&
          data.workerId === null &&
          data.leaseToken === null && data.leaseExpiresAt === null,
        cursor: data.cursor,
      };
    },
    async rejectInvalidHmac() {
      const timestamp = Math.floor(Date.now() / 1_000);
      const response = await consumerRequest(`${timestamp}.${"A".repeat(43)}`);
      return { status: response.status };
    },
    async createCanaryPair(canary: SyntheticCanary) {
      const root =
        `projects/${config.firebaseProjectId}/databases/(default)/documents`;
      const sourceFields = { ...canary.canonical };
      delete sourceFields.createdAt;
      delete sourceFields.updatedAt;
      const eventFields = { ...canary.event };
      delete eventFields.createdAt;
      delete eventFields.updatedAt;
      const response = await firestore(":commit", {
        method: "POST",
        body: {
          writes: [
            {
              update: {
                name: `${root}/establishments/${encodeURIComponent(canary.id)}`,
                fields: encodeFields(sourceFields),
              },
              updateTransforms: ["createdAt", "updatedAt"].map((fieldPath) => ({
                fieldPath,
                setToServerValue: "REQUEST_TIME",
              })),
              currentDocument: { exists: false },
            },
            {
              update: {
                name: `${root}/catalog_outbox/${
                  encodeURIComponent(canary.operationId)
                }`,
                fields: encodeFields(eventFields),
              },
              updateTransforms: ["createdAt", "updatedAt"].map((fieldPath) => ({
                fieldPath,
                setToServerValue: "REQUEST_TIME",
              })),
              currentDocument: { exists: false },
            },
          ],
        },
      });
      if (
        !isRecord(response) || !Array.isArray(response.writeResults) ||
        response.writeResults.length !== 2
      ) {
        throw new HomologationRunnerError("canary_atomic_commit_unconfirmed");
      }
      return { created: true };
    },
    async readCanaryPair(canary: SyntheticCanary) {
      const [canonical, event] = await Promise.all([
        document("establishments", canary.id),
        document("catalog_outbox", canary.operationId),
      ]);
      return { canonical: canonical?.data, event: event?.data };
    },
    async invokeConsumer(_canary: SyntheticCanary) {
      const path = new URL(config.consumerUrl).pathname;
      const signature = await createConsumerSignature(hmacSecret, path);
      return await consumerRequest(signature);
    },
    async replayRestrictedWriter(projection: Record<string, unknown>) {
      const driver = createCatalogPostgresRpcDriver({
        connectionUrl: databaseUrl,
        mode: "hosted",
        projectRef: config.supabaseProjectRef,
        postgresFactory: postgres,
        timeoutMs: 5_000,
      });
      try {
        const writer = createSupabaseCatalogWriterV2({ rpc: driver.rpc });
        return await writer.applyProjection(projection);
      } finally {
        await driver.close();
      }
    },
    async readPublicRpc(id: string) {
      const response = await fetch(
        `${config.supabaseUrl}/rest/v1/rpc/get_public_establishment_v2`,
        {
          method: "POST",
          headers: {
            apikey: publishableKey,
            "content-type": "application/json",
          },
          body: JSON.stringify({ p_id: id }),
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (!response.ok) throw new HomologationRunnerError("public_rpc_denied");
      return await readJson(response, "public_rpc_response_invalid");
    },
    async rejectDirectTableRead(id: string) {
      const url =
        `${config.supabaseUrl}/rest/v1/public_establishment_catalog_v2?id=eq.${
          encodeURIComponent(id)
        }&select=id`;
      const response = await fetch(url, {
        headers: { apikey: publishableKey },
        signal: AbortSignal.timeout(10_000),
      });
      if (response.status === 401 || response.status === 403) {
        return { status: response.status };
      }
      if (response.body) await response.body.cancel().catch(() => {});
      return { status: response.status };
    },
  };
}

async function readJson(response: Response, code: string): Promise<unknown> {
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
    throw new HomologationRunnerError(code);
  }
  let value;
  try {
    value = text === "" ? {} : JSON.parse(text);
  } catch {
    throw new HomologationRunnerError(code);
  }
  if (!response.ok) throw new HomologationRunnerError(code);
  return value;
}

function encodeFields(
  value: Record<string, unknown>,
): Record<string, FirestoreValue> {
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, encodeValue(item)]),
  );
}

function encodeValue(value: unknown): FirestoreValue {
  if (value === null) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isSafeInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (isRecord(value)) return { mapValue: { fields: encodeFields(value) } };
  throw new HomologationRunnerError("canary_encoding_failed");
}

function decodeFirestoreDocument(
  value: FirestoreDocument,
): FirestoreDecodedDocument {
  const prefix = `projects/${
    Deno.env.get("FIREBASE_PROJECT_ID")
  }/databases/(default)/documents/`;
  if (
    typeof value.name !== "string" || !value.name.startsWith(prefix) ||
    !value.fields
  ) {
    throw new HomologationRunnerError("firestore_document_invalid");
  }
  return {
    name: value.name,
    data: decodeFields(value.fields),
    updateTime: value.updateTime,
  };
}

function decodeFields(
  fields: Record<string, FirestoreValue>,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]),
  );
}

function decodeValue(value: FirestoreValue): unknown {
  if (Object.hasOwn(value, "stringValue")) return value.stringValue;
  if (Object.hasOwn(value, "booleanValue")) return value.booleanValue;
  if (Object.hasOwn(value, "integerValue")) return Number(value.integerValue);
  if (Object.hasOwn(value, "doubleValue")) return value.doubleValue;
  if (Object.hasOwn(value, "timestampValue")) return value.timestampValue;
  if (Object.hasOwn(value, "nullValue")) return null;
  if (Object.hasOwn(value, "arrayValue")) {
    const array = value.arrayValue;
    if (
      !isRecord(array) ||
      (array.values !== undefined && !Array.isArray(array.values))
    ) throw new HomologationRunnerError("firestore_value_invalid");
    return ((array.values ?? []) as FirestoreValue[]).map(decodeValue);
  }
  if (Object.hasOwn(value, "mapValue")) {
    const map = value.mapValue;
    if (!isRecord(map) || !isRecord(map.fields ?? {})) {
      throw new HomologationRunnerError("firestore_value_invalid");
    }
    return decodeFields((map.fields ?? {}) as Record<string, FirestoreValue>);
  }
  throw new HomologationRunnerError("firestore_value_invalid");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requiredEnv(
  env: Record<string, string | undefined>,
  name: string,
): string {
  const value = env[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new HomologationRunnerError("configuration_rejected");
  }
  return value;
}
