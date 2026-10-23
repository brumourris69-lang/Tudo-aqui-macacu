import { createCatalogOutboxConsumerHandler } from "../_shared/catalog_outbox_consumer.mjs";
import { createCatalogOutboxProcessor } from "../_shared/catalog_outbox_processor.mjs";
import { createCatalogOutboxScanCheckpoint } from "../_shared/catalog_outbox_scan_checkpoint.mjs";
import { createCatalogOutboxScanRunner } from "../_shared/catalog_outbox_scan_runner.mjs";
import { resolveCatalogOutboxConsumerConfig } from "../_shared/catalog_outbox_consumer_config.mjs";
import { createFirebaseFirestoreRestStore } from "../_shared/firebase_firestore_rest.mjs";
import { createCatalogPostgresRpcDriver } from "../_shared/catalog_postgres_driver.mjs";
import postgres from "postgres";

const config = resolveCatalogOutboxConsumerConfig({
  CATALOG_CONSUMER_ENABLED: Deno.env.get("CATALOG_CONSUMER_ENABLED") ?? "",
  CATALOG_DATABASE_MODE: Deno.env.get("CATALOG_DATABASE_MODE") ?? "",
  FIREBASE_PROJECT_ID: Deno.env.get("FIREBASE_PROJECT_ID") ?? "",
  FIREBASE_SERVICE_ACCOUNT_JSON:
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "",
  CATALOG_CONSUMER_HOMOLOGATION: Deno.env.get("CATALOG_CONSUMER_HOMOLOGATION"),
  CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID: Deno.env.get(
    "CATALOG_HOMOLOGATION_PRODUCTION_FIREBASE_PROJECT_ID",
  ),
  CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID: Deno.env.get(
    "CATALOG_HOMOLOGATION_APPROVED_FIREBASE_PROJECT_ID",
  ),
  CATALOG_HOMOLOGATION_PRODUCTION_SUPABASE_REF: Deno.env.get(
    "CATALOG_HOMOLOGATION_PRODUCTION_SUPABASE_REF",
  ),
  CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF: Deno.env.get(
    "CATALOG_HOMOLOGATION_APPROVED_SUPABASE_REF",
  ),
  FIRESTORE_EMULATOR_HOST: Deno.env.get("FIRESTORE_EMULATOR_HOST"),
  SUPABASE_PROJECT_REF: Deno.env.get("SUPABASE_PROJECT_REF") ?? "",
  SUPABASE_CATALOG_DATABASE_URL:
    Deno.env.get("SUPABASE_CATALOG_DATABASE_URL") ?? "",
  CATALOG_CONSUMER_HMAC_SECRET: Deno.env.get("CATALOG_CONSUMER_HMAC_SECRET") ??
    "",
});

let processor: ReturnType<typeof createCatalogOutboxProcessor> | null = null;
let runner: ReturnType<typeof createCatalogOutboxScanRunner> | null = null;
let postgresDriver: ReturnType<typeof createCatalogPostgresRpcDriver> | null =
  null;
if (config.enabled) {
  try {
    const localMode = config.databaseMode === "local";
    const store = createFirebaseFirestoreRestStore({
      projectId: config.projectId,
      ...(localMode
        ? { emulator: parseFirestoreEmulatorHost(config.firestoreEmulatorHost) }
        : {
          serviceAccountJson: () => config.serviceAccountJson,
          ...(config.homologationProjectId
            ? { homologationProjectId: config.homologationProjectId }
            : {}),
        }),
      requestTimeoutMs: 3_000,
    });
    postgresDriver = createCatalogPostgresRpcDriver({
      connectionUrl: config.databaseUrl,
      mode: config.databaseMode,
      ...(localMode ? {} : { projectRef: config.supabaseProjectRef }),
      postgresFactory: postgres,
      timeoutMs: 5_000,
    });
    const workerId = `outbox-${crypto.randomUUID()}`;
    processor = createCatalogOutboxProcessor({
      store,
      serverIdentity: { workerId },
      rpc: postgresDriver.rpc,
      createLeaseToken: () => crypto.randomUUID(),
      pageSize: 1,
      scanPageSize: 25,
      maxScanPages: 4,
      leaseDurationMs: 120_000,
    });
    const checkpoint = createCatalogOutboxScanCheckpoint({
      store,
      workerId,
      createLeaseToken: () => crypto.randomUUID(),
      leaseDurationMs: 180_000,
    });
    runner = createCatalogOutboxScanRunner({
      checkpoint,
      processPage: processor.processPage,
      pageSize: 1,
    });
  } catch {
    // Missing or invalid server configuration stays disabled and is never logged.
  }
}

const handle = createCatalogOutboxConsumerHandler({
  enabled: config.enabled && Boolean(processor),
  secret: config.enabled ? config.hmacSecret : "",
  pageSize: 1,
  onMetric: (metric: Record<string, unknown>) =>
    console.log(JSON.stringify(metric)),
  processPage: () => {
    if (!processor || !runner) throw new Error("consumer-unavailable");
    return runner.run();
  },
});

Deno.serve(handle);

function parseFirestoreEmulatorHost(
  value: string,
): { host: "127.0.0.1" | "::1"; port: number } {
  const match = /^(127\.0\.0\.1|\[::1\]):(\d{1,5})$/u.exec(value);
  if (!match) throw new Error("invalid local Firestore Emulator endpoint");
  const port = Number(match[2]);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) {
    throw new Error("invalid local Firestore Emulator endpoint");
  }
  return { host: match[1] === "[::1]" ? "::1" : "127.0.0.1", port };
}
