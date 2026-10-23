import { createCatalogOutboxConsumerHandler } from "./catalog_outbox_consumer.mjs";
import { resolveCatalogOutboxConsumerConfig } from "./catalog_outbox_consumer_config.mjs";

const secret = "synthetic-deno-local-test-secret-at-least-32-bytes";
const nowSeconds = Math.floor(Date.parse("2026-10-21T00:00:00.000Z") / 1_000);

async function signature(pathname = "/consume") {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const message =
    `catalog-outbox-consumer-v1\nPOST\n${pathname}\n${nowSeconds}`;
  const signed = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)),
  );
  const encoded = btoa(String.fromCharCode(...signed)).replaceAll("+", "-")
    .replaceAll("/", "_").replace(/=+$/u, "");
  return `${nowSeconds}.${encoded}`;
}

function buildRequest(signed: string | null, body?: string): Request {
  return new Request("https://local.invalid/consume", {
    method: "POST",
    headers: {
      ...(signed ? { "x-catalog-run-signature": signed } : {}),
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    ...(body === undefined ? {} : { body }),
  });
}

Deno.test("Deno runtime rejects disabled and unauthenticated consumer requests before processing", async () => {
  let calls = 0;
  const disabled = createCatalogOutboxConsumerHandler({
    enabled: false,
    secret,
    processPage: () => {
      calls += 1;
      return { results: [] };
    },
    now: () => nowSeconds * 1_000,
  });
  const enabled = createCatalogOutboxConsumerHandler({
    enabled: true,
    secret,
    processPage: () => {
      calls += 1;
      return { results: [] };
    },
    now: () => nowSeconds * 1_000,
  });

  if ((await disabled(buildRequest(await signature()))).status !== 503) {
    throw new Error("disabled handler must fail closed");
  }
  if ((await enabled(buildRequest(null))).status !== 401) {
    throw new Error("missing HMAC must be rejected");
  }
  if (
    (await enabled(buildRequest(await signature(), '{"limit":1}'))).status !==
      400
  ) {
    throw new Error("caller parameters must be rejected");
  }
  if (calls !== 0) throw new Error("rejected request reached processor");
});

Deno.test("Deno runtime accepts a valid synthetic HMAC and returns only sanitized processor counts", async () => {
  let received: unknown;
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true,
    secret,
    now: () => nowSeconds * 1_000,
    processPage: (request: { limit: number; cursor: string | null }) => {
      received = request;
      return {
        results: [
          { eventId: "private-synthetic-id", state: "synced" },
          { eventId: "private-synthetic-id-2", state: "unknown-secret-state" },
        ],
        scannedPages: 2,
        scannedDocuments: 50,
        eligibleCount: 2,
        claimedCount: 1,
        nextCursor: null,
        readTime: null,
      };
    },
  });
  const response = await handler(buildRequest(await signature(), "{}"));
  const text = await response.text();
  if (response.status !== 200) {
    throw new Error("valid HMAC should invoke the processor");
  }
  if (
    JSON.stringify(received) !== JSON.stringify({ limit: 25, cursor: null })
  ) throw new Error("processor input must stay bounded");
  if (
    text.includes("private-synthetic") || text.includes("unknown-secret-state")
  ) throw new Error("response leaked processor details");
  if (
    text !==
      '{"ok":true,"busy":false,"processed":2,"states":{"synced":1,"unavailable":1},"scannedPages":2,"scannedDocuments":50,"eligible":2,"claimed":1,"hasMore":false}'
  ) {
    throw new Error("unexpected sanitized response");
  }
});

Deno.test("consumer configuration accepts only a demo emulator and the restricted PostgreSQL login", () => {
  const local = resolveCatalogOutboxConsumerConfig({
    CATALOG_CONSUMER_ENABLED: "true",
    CATALOG_DATABASE_MODE: "local",
    FIREBASE_PROJECT_ID: "demo-universal-search",
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8087",
    SUPABASE_CATALOG_DATABASE_URL: "postgres://catalog_writer_v2_login:synthetic-password@127.0.0.1:54329/postgres",
    CATALOG_CONSUMER_HMAC_SECRET: secret,
  });
  if (!local.enabled || local.projectId !== "demo-universal-search" ||
    local.databaseMode !== "local" || local.firestoreEmulatorHost !== "127.0.0.1:8087") {
    throw new Error("valid local integration configuration should be accepted");
  }

  const missingWriter = resolveCatalogOutboxConsumerConfig({
    CATALOG_CONSUMER_ENABLED: "true",
    CATALOG_DATABASE_MODE: "local",
    FIREBASE_PROJECT_ID: "demo-universal-search",
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8087",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic-service-role-key-not-real",
    CATALOG_CONSUMER_HMAC_SECRET: secret,
  });
  if (missingWriter.enabled) {
    throw new Error("service_role-only configuration must remain disabled");
  }
});
