import postgres from "postgres";
import { createHmac } from "node:crypto";
import { createCatalogOutboxConsumerHandler } from "./catalog_outbox_consumer.mjs";
import { createCatalogOutboxProcessor } from "./catalog_outbox_processor.mjs";
import { projectCanonicalEstablishment } from "./catalog_outbox_protocol.mjs";
import {
  createFirebaseFirestoreRestStore,
  FirestoreRestError,
} from "./firebase_firestore_rest.mjs";
import { createCatalogPostgresRpcDriver } from "./catalog_postgres_driver.mjs";
import { createSupabaseCatalogWriterV2 } from "./supabase_catalog_writer_v2.mjs";

const projectId = "demo-universal-search";
const requiredEnv = [
  "FIRESTORE_EMULATOR_HOST",
  "SUPABASE_CATALOG_DATABASE_URL",
  "CATALOG_TEST_POSTGRES_VERIFY_URL",
];
const integrationEnabled = requiredEnv.every((name) =>
  Boolean(Deno.env.get(name))
);
type FirestoreStore = ReturnType<typeof createFirebaseFirestoreRestStore>;
type FirestoreTransaction = Parameters<
  Parameters<FirestoreStore["runTransaction"]>[0]
>[0];
type PostgresClient = ReturnType<typeof postgres>;
type ProcessPage = Awaited<
  ReturnType<ReturnType<typeof createCatalogOutboxProcessor>["processPage"]>
>;

Deno.test({
  name:
    "Deno outbox consumer writes through catalog_writer_v2_login into PostgreSQL and acknowledges Firestore",
  ignore: !integrationEnabled,
  async fn() {
    const emulator = parseLoopback(Deno.env.get("FIRESTORE_EMULATOR_HOST")!);
    const connectionUrl = Deno.env.get("SUPABASE_CATALOG_DATABASE_URL")!;
    const verifyUrl = Deno.env.get("CATALOG_TEST_POSTGRES_VERIFY_URL")!;
    assert(emulator !== null, "Firestore Emulator must be loopback-only");
    assert(
      isLoopbackDatabaseUrl(verifyUrl),
      "verification connection must target loopback",
    );

    const restrictedIdentity = postgres(connectionUrl, {
      max: 1,
      connect_timeout: 5,
      idle_timeout: 5,
      prepare: false,
      fetch_types: false,
      ssl: false,
    });
    const verify = postgres(verifyUrl, {
      max: 1,
      connect_timeout: 5,
      idle_timeout: 5,
      prepare: false,
      fetch_types: false,
      ssl: false,
    });
    const writerDriver = createCatalogPostgresRpcDriver({
      connectionUrl,
      mode: "local",
      postgresFactory: postgres,
      timeoutMs: 5_000,
    });

    try {
      const identity = await restrictedIdentity.unsafe(
        "select current_user as current_user",
        [],
        {
          prepare: false,
        },
      );
      assert(
        identity.length === 1 &&
          identity[0].current_user === "catalog_writer_v2_login",
        "the real Deno connection must authenticate as the restricted login",
      );

      const store = createFirebaseFirestoreRestStore({
        projectId,
        emulator,
        // The official Firestore Emulator accepts the synthetic `owner`
        // bearer token as an Admin SDK-equivalent rules bypass. Keep it in
        // this test-only loopback adapter; production access-token behavior
        // and client Rules tests remain separate and unchanged.
        fetchImpl: (input, init) => {
          const target = new URL(
            input instanceof Request ? input.url : String(input),
          );
          assert(
            target.protocol === "http:" && target.hostname === emulator.host &&
              Number(target.port) === emulator.port,
            "test Firestore requests must remain on the configured emulator",
          );
          const headers = new Headers(init?.headers);
          headers.set("authorization", "Bearer owner");
          return fetch(target, { ...init, headers });
        },
        requestTimeoutMs: 3_000,
      });
      const identityId = `modelo-deno-${crypto.randomUUID()}`;
      const workerRpc = async (name: string, args: Record<string, unknown>) => {
        const payload = (args.p_projection ?? args.p_tombstone) as Record<
          string,
          unknown
        >;
        if (payload?.id === identityId) {
          assert(
            payload.category === "Comércio",
            "Deno writer must preserve the canonical UTF-8 category",
          );
        }
        return await writerDriver.rpc(name, args);
      };
      const workerA = processor(store, workerRpc, "deno-worker-a");
      const op1 = crypto.randomUUID();
      const source1 = canonical(op1, 1, "Deno PostgreSQL fixture v1");
      await createPair(store, identityId, op1, source1, 1);
      await waitForFirestoreSnapshot();
      const projection1 = projectCanonicalEstablishment(
        identityId,
        source1,
        outboxEvent(op1, identityId, 1),
      );
      assert(
        projection1 !== null,
        "synthetic canonical fixture must produce a V2 projection",
      );
      const shape = await verify.unsafe(
        "select jsonb_typeof($1::jsonb) as root_type, left(($1::jsonb)::text, 1) as first_char",
        [verify.typed(projection1, 3_802)],
        { prepare: false },
      );
      assert(
        shape[0]?.root_type === "object" && shape[0]?.first_char === "{",
        `PostgreSQL JSONB binding must preserve an object (${
          shape[0]?.root_type
        }/${shape[0]?.first_char})`,
      );
      const categoryProbe = await verify.unsafe(
        "select $1::jsonb ->> 'category' as category, ($1::jsonb ->> 'category' = 'Comércio') as matches",
        [verify.typed(projection1, 3_802)],
        { prepare: false },
      );
      assert(
        categoryProbe[0]?.matches === true,
        `PostgreSQL fixture category must preserve UTF-8 (${
          JSON.stringify(categoryProbe[0]?.category)
        })`,
      );

      const consumerSecret = "synthetic-deno-consumer-hmac-secret-not-real";
      const consumer = createCatalogOutboxConsumerHandler({
        enabled: true,
        secret: consumerSecret,
        processPage: () => workerA.processPage({ limit: 1 }),
      });
      const response = await consumer(signedRequest(consumerSecret));
      assert(
        response.status === 200,
        "signed Deno consumer request should run",
      );
      const summary = await response.json();
      assert(
        summary.ok === true && summary.states.synced === 1,
        `consumer must acknowledge only after PostgreSQL success (${
          JSON.stringify(summary)
        })`,
      );
      const event1 = await readEvent(store, op1);
      assert(
        event1 !== null && event1.state === "synced" &&
          event1.attemptCount === 1,
        "Firestore event must be confirmed after SQL commit",
      );
      const row1 = await readCatalogRow(verify, identityId);
      assert(
        row1?.catalog_version === 1 && row1.outbox_operation_id === op1,
        "PostgreSQL must persist the original ID and operation",
      );
      assert(
        !JSON.stringify(row1).includes("PRIVATE_SENTINEL"),
        "private canonical fields must not enter the public projection",
      );

      const replay = await createSupabaseCatalogWriterV2({ rpc: workerRpc })
        .applyProjection(
          projectCanonicalEstablishment(
            identityId,
            source1,
            outboxEvent(op1, identityId, 1),
          )!,
        );
      assert(
        replay.result === "duplicate",
        "same operation/version replay must be idempotent",
      );

      const op2 = crypto.randomUUID();
      const source2 = canonical(op2, 2, "Deno PostgreSQL fixture v2");
      await updatePair(store, identityId, op2, source2, 2);
      await waitForFirestoreSnapshot();
      const updated = await workerA.processPage({ limit: 1 });
      assert(
        outcome(updated, op2) === "synced",
        "next version must be written and acknowledged",
      );
      assert(
        (await readCatalogRow(verify, identityId))?.catalog_version === 2,
        "newer version must persist",
      );

      const staleOperation = crypto.randomUUID();
      await createEvent(store, staleOperation, identityId, 1);
      await waitForFirestoreSnapshot();
      const stale = await workerA.processPage({ limit: 1 });
      assert(
        outcome(stale, staleOperation) === "superseded",
        "old outbox event must not overwrite the current version",
      );
      assert(
        (await readCatalogRow(verify, identityId))?.catalog_version === 2,
        "stale event must leave destination version unchanged",
      );

      const retryId = `modelo-deno-${crypto.randomUUID()}`;
      const retryOperation = crypto.randomUUID();
      await createPair(
        store,
        retryId,
        retryOperation,
        canonical(retryOperation, 1, "retry fixture"),
        1,
      );
      await waitForFirestoreSnapshot();
      let failOnce = true;
      const unavailableOnce = (
        name: string,
        args: Record<string, unknown>,
      ) => {
        const payload = (args.p_projection ?? args.p_tombstone) as Record<
          string,
          unknown
        >;
        if (payload.id === retryId && failOnce) {
          failOnce = false;
          throw Object.assign(new Error("synthetic PostgreSQL disconnect"), {
            code: "08006",
          });
        }
        return workerRpc(name, args);
      };
      const failed = await processor(
        store,
        unavailableOnce,
        "deno-retry-worker",
      ).processPage({ limit: 1 });
      assert(
        outcome(failed, retryOperation) === "pending",
        "database failure must schedule retry rather than acknowledge",
      );
      const retryEvent = await readEvent(store, retryOperation);
      assert(
        retryEvent !== null && retryEvent.lastErrorCode ===
            "catalog_unavailable",
        "retry error code must be sanitized",
      );
      await delay(5_300);
      const recovered = await processor(
        store,
        workerRpc,
        "deno-retry-worker-recovered",
      ).processPage({ limit: 1 });
      assert(
        outcome(recovered, retryOperation) === "synced",
        "retry must recover into PostgreSQL",
      );
      assert(
        (await readCatalogRow(verify, retryId))?.outbox_operation_id ===
          retryOperation,
        "retry destination state must persist",
      );

      const ackId = `modelo-deno-${crypto.randomUUID()}`;
      const ackOperation = crypto.randomUUID();
      await createPair(
        store,
        ackId,
        ackOperation,
        canonical(ackOperation, 1, "ack recovery fixture"),
        1,
      );
      await waitForFirestoreSnapshot();
      let failAck = true;
      const ackFaultStore = faultSyncedAcknowledgement(
        store,
        ackOperation,
        () => {
          if (!failAck) return false;
          failAck = false;
          return true;
        },
      );
      const ackLost = await processor(
        ackFaultStore,
        workerRpc,
        "deno-ack-worker",
        1_000,
      ).processPage({ limit: 1 });
      assert(
        outcome(ackLost, ackOperation) === "ack_pending",
        "failed Firestore acknowledgement must remain recoverable",
      );
      assert(
        (await readCatalogRow(verify, ackId))?.outbox_operation_id ===
          ackOperation,
        "destination write must remain committed after lost acknowledgement",
      );
      await delay(1_200);
      const ackRecovered = await processor(
        store,
        workerRpc,
        "deno-ack-recovery",
        1_000,
      ).processPage({ limit: 1 });
      assert(
        outcome(ackRecovered, ackOperation) === "synced",
        "expired lease must allow safe acknowledgement recovery",
      );
      const ackResult = ackRecovered.results.find((
        item: Record<string, unknown>,
      ) => item.eventId === ackOperation) as
        | Record<string, unknown>
        | undefined;
      assert(
        ackResult?.write === "duplicate",
        "recovery must replay the committed SQL operation idempotently",
      );

      const concurrentId = `modelo-deno-${crypto.randomUUID()}`;
      const concurrentOperation = crypto.randomUUID();
      await createPair(
        store,
        concurrentId,
        concurrentOperation,
        canonical(concurrentOperation, 1, "concurrency fixture"),
        1,
      );
      await waitForFirestoreSnapshot();
      let sqlCalls = 0;
      const countRpc = (name: string, args: Record<string, unknown>) => {
        const payload = (args.p_projection ?? args.p_tombstone) as Record<
          string,
          unknown
        >;
        if (payload.id === concurrentId) sqlCalls += 1;
        return workerRpc(name, args);
      };
      const [a, b] = await Promise.all([
        processor(store, countRpc, "deno-concurrent-a").processPage({
          limit: 1,
        }),
        processor(store, countRpc, "deno-concurrent-b").processPage({
          limit: 1,
        }),
      ]);
      assert(
        sqlCalls === 1,
        "two concurrent Deno workers must produce one destination call",
      );
      const concurrentEvent = await readEvent(store, concurrentOperation);
      assert(
        concurrentEvent !== null && concurrentEvent.state === "synced",
        "one worker must own and confirm the claim",
      );
      assert(
        (await readCatalogRow(verify, concurrentId))?.outbox_operation_id ===
          concurrentOperation,
        "the concurrent operation must be persisted once",
      );
      assert(
        [...a.results, ...b.results].some((item: Record<string, unknown>) =>
          item.eventId === concurrentOperation
        ),
        "both worker results must be accounted for",
      );
    } finally {
      await writerDriver.close();
      await restrictedIdentity.end({ timeout: 3 });
      await verify.end({ timeout: 3 });
    }
  },
});

function processor(
  store: FirestoreStore,
  rpc: (name: string, args: Record<string, unknown>) => Promise<unknown>,
  workerId: string,
  leaseDurationMs = 30_000,
) {
  return createCatalogOutboxProcessor({
    store,
    serverIdentity: { workerId },
    rpc,
    createLeaseToken: () => crypto.randomUUID(),
    pageSize: 1,
    leaseDurationMs,
  });
}

function canonical(
  operationId: string,
  version: number,
  name: string,
  overrides: Record<string, unknown> = {},
) {
  return {
    name,
    description: "Synthetic public summary only",
    category: "Comércio",
    subcategory: "Teste",
    published: true,
    active: true,
    catalogVersion: version,
    outboxOperationId: operationId,
    publicContactApproved: false,
    deletedAt: null,
    ownerEmail: "private-sentinel@example.invalid",
    adminNote: "PRIVATE_SENTINEL_DO_NOT_PROJECT",
    ...overrides,
  };
}

function outboxEvent(operationId: string, entityId: string, version: number) {
  const timestamp = new Date();
  return {
    schemaVersion: 2,
    operationId,
    entityType: "establishment",
    entityId,
    authorUid: "synthetic-admin",
    version,
    operation: "reconcile",
    state: "pending",
    attemptCount: 0,
    createdAt: timestamp,
    updatedAt: timestamp,
    workerId: null,
    leaseToken: null,
    leaseExpiresAt: null,
    nextAttemptAt: null,
    lastErrorCode: null,
    syncedAt: null,
  };
}

async function createPair(
  store: FirestoreStore,
  id: string,
  operationId: string,
  source: Record<string, unknown>,
  version: number,
) {
  await store.runTransaction((transaction) => {
    transaction.create("establishments", id, source, {
      serverTimestampFields: ["createdAt", "updatedAt"],
    });
    transaction.create(
      "catalog_outbox",
      operationId,
      outboxEvent(operationId, id, version),
      {
        serverTimestampFields: ["createdAt", "updatedAt"],
      },
    );
    return Promise.resolve();
  });
}

async function updatePair(
  store: FirestoreStore,
  id: string,
  operationId: string,
  source: Record<string, unknown>,
  version: number,
) {
  await store.runTransaction(async (transaction) => {
    const current = await transaction.get("establishments", id);
    assert(current !== null, "canonical document must exist before update");
    transaction.update("establishments", id, source, {
      updateTime: current.updateTime,
      serverTimestampFields: ["updatedAt"],
    });
    transaction.create(
      "catalog_outbox",
      operationId,
      outboxEvent(operationId, id, version),
      {
        serverTimestampFields: ["createdAt", "updatedAt"],
      },
    );
  });
}

async function createEvent(
  store: FirestoreStore,
  operationId: string,
  entityId: string,
  version: number,
) {
  await store.runTransaction((transaction) => {
    transaction.create(
      "catalog_outbox",
      operationId,
      outboxEvent(operationId, entityId, version),
      {
        serverTimestampFields: ["createdAt", "updatedAt"],
      },
    );
    return Promise.resolve();
  });
}

async function readEvent(store: FirestoreStore, id: string) {
  return await store.runTransaction((transaction) =>
    transaction.get("catalog_outbox", id).then((record) => record?.data ?? null)
  );
}

async function readCatalogRow(verify: PostgresClient, id: string) {
  const rows = await verify.unsafe(
    "select json_build_object('id', id, 'catalog_version', catalog_version, 'outbox_operation_id', outbox_operation_id, 'name', name, 'published', published, 'deleted_at', deleted_at)::json as row from public.public_establishment_catalog_v2 where id = $1",
    [id],
    { prepare: false },
  );
  return rows[0]?.row ?? null;
}

function faultSyncedAcknowledgement(
  store: FirestoreStore,
  operationId: string,
  shouldFail: () => boolean,
) {
  return {
    queryOutboxPage: (
      options: Parameters<FirestoreStore["queryOutboxPage"]>[0],
    ) => store.queryOutboxPage(options),
    runTransaction<T>(
      callback: (transaction: FirestoreTransaction) => Promise<T>,
    ): Promise<T> {
      return store.runTransaction((transaction) =>
        callback({
          get: (collection, id) => transaction.get(collection, id),
          create: (collection, id, data, options) =>
            transaction.create(collection, id, data, options),
          update(
            collection: string,
            id: string,
            data: Record<string, unknown>,
            options,
          ) {
            if (
              collection === "catalog_outbox" && id === operationId &&
              data.state === "synced" && shouldFail()
            ) {
              throw new FirestoreRestError("backend_unavailable");
            }
            return transaction.update(collection, id, data, options);
          },
        })
      );
    },
  };
}

function signedRequest(secret: string) {
  const timestamp = Math.floor(Date.now() / 1_000);
  const signature = createHmac("sha256", secret)
    .update(`catalog-outbox-consumer-v1\nPOST\n/consume\n${timestamp}`, "utf8")
    .digest("base64url");
  return new Request("http://127.0.0.1/consume", {
    method: "POST",
    headers: { "x-catalog-run-signature": `${timestamp}.${signature}` },
  });
}

function outcome(page: ProcessPage, eventId: string) {
  return page.results.find((item) => item.eventId === eventId)?.state;
}

function parseLoopback(
  value: string,
): { host: "127.0.0.1" | "::1"; port: number } | null {
  const match = /^(127\.0\.0\.1|\[::1\]):(\d{1,5})$/u.exec(value);
  if (!match) return null;
  const port = Number(match[2]);
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) return null;
  return { host: match[1] === "[::1]" ? "::1" : "127.0.0.1", port };
}

function isLoopbackDatabaseUrl(value: string) {
  try {
    return ["127.0.0.1", "[::1]"].includes(new URL(value).hostname);
  } catch {
    return false;
  }
}

async function waitForFirestoreSnapshot() {
  await delay(5_300);
}

function delay(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
