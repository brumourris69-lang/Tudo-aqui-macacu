import assert from "node:assert/strict";
import { createHmac as hmacSha256 } from "node:crypto";
import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createCatalogReconciliationFileCheckpointStore } from "./catalog_reconciliation_file_checkpoint_store.mjs";
import { runCatalogReconciliationScan } from "./catalog_reconciliation_scan.mjs";
import { createCatalogReconciliationSnapshotReader } from "./catalog_reconciliation_snapshot_reader.mjs";
import { createFirebaseFirestoreRestStore } from "./firebase_firestore_rest.mjs";
import { createSupabaseCatalogReconciliationRpcClient } from "./supabase_catalog_reconciliation_rest.mjs";

const PROJECT = "demo-universal-search";
const DATABASE = "(default)";
const DOCUMENTS = `projects/${PROJECT}/databases/${DATABASE}/documents`;
const IDS = ["legacy-a", "legacy-é", "\uE000", "\u{10000}"];
const RELAY_CONTAINER = process.env.RECONCILIATION_LOCAL_RELAY_CONTAINER;
const JWT_SECRET = process.env.RECONCILIATION_LOCAL_POSTGREST_JWT_SECRET;
const ENABLED = process.env.FIRESTORE_EMULATOR_HOST === "127.0.0.1:18087" &&
  /^macacu-0755-pg-verified-[a-f0-9]{8,12}$/u.test(RELAY_CONTAINER ?? "") &&
  typeof JWT_SECRET === "string" && JWT_SECRET.length >= 32 &&
  JWT_SECRET.length <= 8192;

test(
  "read-only reconciliation scan joins the local Firestore Emulator and actual private PostgREST snapshot RPCs",
  {
    skip: !ENABLED,
    timeout: 60_000,
  },
  async (t) => {
    const temporaryDirectory = await mkdtemp(
      join(tmpdir(), "macacu-reconciliation-local-scan-"),
    );
    t.after(() => rm(temporaryDirectory, { recursive: true, force: true }));
    const rawFirestore = createFirebaseFirestoreRestStore({
      projectId: PROJECT,
      emulator: { host: "127.0.0.1", port: 18087 },
    });
    const apiKey = createSyntheticServiceJwt(JWT_SECRET);
    const catalogRpc = createSupabaseCatalogReconciliationRpcClient({
      url: "http://127.0.0.1:3000/",
      restPathPrefix: "",
      apiKey,
      fetchImpl: dockerExecPostgrestFetch,
      timeoutMs: 15_000,
    });
    const firestore = Object.freeze({
      queryEstablishmentsSnapshotPage: async (args) =>
        observeFirestore(() =>
          rawFirestore.queryEstablishmentsSnapshotPage(args)
        ),
    });
    const catalog = Object.freeze({
      beginSnapshot: async (id) =>
        observeRpc("begin", () => catalogRpc.beginSnapshot(id)),
      readPage: async (args) =>
        observeRpc("read", () => catalogRpc.readPage(args)),
      disposeSnapshot: async (id) =>
        observeRpc("dispose", () => catalogRpc.disposeSnapshot(id)),
    });
    const reader = createCatalogReconciliationSnapshotReader({
      firestore,
      catalog,
    });
    const checkpointStore = createCatalogReconciliationFileCheckpointStore({
      directory: temporaryDirectory,
      lockWaitMs: 2_000,
    });
    const base =
      `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/${DOCUMENTS}`;
    await firestoreFixture(base, "seed");
    let snapshotId;

    try {
      snapshotId = await reader.beginSnapshot();
      const result = await runCatalogReconciliationScan({
        snapshotId,
        reader,
        checkpointStore,
        pageSize: 2,
        maxPages: 10,
      });
      assert.equal(result.state, "complete");
      assert.ok(result.checkpoint.scannedCount >= IDS.length);
      assert.equal(result.checkpoint.done, true);
      const report = await checkpointStore.loadReport(snapshotId);
      assert.equal(report.checkpoint.sequence, result.checkpoint.sequence);
      assert.equal(report.findings.length, result.checkpoint.scannedCount);
      assert.equal(
        JSON.stringify(report).includes("fixture@example.invalid"),
        false,
      );
      assert.equal(
        JSON.stringify(report).includes("synthetic-private-contact"),
        false,
      );
      assert.ok(
        report.findings.every((finding) =>
          finding.id && finding.status && finding.action
        ),
      );
    } finally {
      if (snapshotId) await reader.disposeSnapshot(snapshotId).catch(() => {});
      await firestoreFixture(base, "delete");
    }

    async function firestoreFixture(endpoint, operation) {
      const writes = operation === "seed"
        ? IDS.map((id, index) => ({
          update: {
            name: `${DOCUMENTS}/establishments/${id}`,
            fields: {
              name: { stringValue: `Local Reconciliation ${index}` },
              category: { stringValue: "Comércio" },
              shortDescription: { stringValue: "Synthetic emulator fixture" },
              published: { booleanValue: true },
              active: { booleanValue: true },
              catalogVersion: { integerValue: "1" },
              outboxOperationId: {
                stringValue: `70000000-0000-4000-8000-${
                  String(index + 1).padStart(12, "0")
                }`,
              },
              publicContactApproved: { booleanValue: false },
              phone: { stringValue: "synthetic-private-contact" },
              ownerEmail: { stringValue: "fixture@example.invalid" },
            },
          },
        }))
        : IDS.map((id) => ({ delete: `${DOCUMENTS}/establishments/${id}` }));
      const response = await fetch(`${endpoint}:commit`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ writes }),
        signal: AbortSignal.timeout(5_000),
      });
      if (!response.ok) {
        throw new Error(
          "Local Firestore fixture operation failed.",
        );
      }
    }
  },
);

async function observeRpc(stage, operation) {
  try {
    return await operation();
  } catch (error) {
    console.log(
      `LOCAL_RECONCILIATION_RPC_FAILURE=${stage}:${safeCode(error?.code)}`,
    );
    throw error;
  }
}

async function observeFirestore(operation) {
  try {
    return await operation();
  } catch (error) {
    console.log(
      `LOCAL_RECONCILIATION_FIRESTORE_FAILURE=${safeCode(error?.code)}`,
    );
    throw error;
  }
}

function safeCode(value) {
  return typeof value === "string" && /^[a-z_-]{1,48}$/u.test(value)
    ? value
    : "unknown";
}

function createSyntheticServiceJwt(secret) {
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const body = `${encode({ alg: "HS256", typ: "JWT" })}.${
    encode({
      role: "service_role",
      aud: "authenticated",
      iat: now,
      exp: now + 600,
    })
  }`;
  const signature = signHmac(secret, body);
  return `${body}.${signature}`;
}

async function dockerExecPostgrestFetch(url, init) {
  const target = new URL(url);
  if (
    target.origin !== "http://127.0.0.1:3000" || init?.method !== "POST" ||
    !/^\/rpc\/(begin_catalog_reconciliation_snapshot_v2|read_catalog_reconciliation_page_v2|dispose_catalog_reconciliation_snapshot_v2)$/u
      .test(target.pathname)
  ) {
    throw new Error("Local PostgREST relay rejected an unexpected request.");
  }
  return await new Promise((resolve, reject) => {
    const child = spawn("docker", [
      "exec",
      "-i",
      RELAY_CONTAINER,
      "curl",
      "--silent",
      "--show-error",
      "--max-time",
      "12",
      "--request",
      "POST",
      "--header",
      `apikey: ${init.headers.apikey}`,
      "--header",
      `authorization: ${init.headers.authorization}`,
      "--header",
      "content-type: application/json",
      "--data-binary",
      "@-",
      "--write-out",
      "\n__HTTP_STATUS__:%{http_code}",
      String(url),
    ], { windowsHide: true, stdio: ["pipe", "pipe", "ignore"] });
    const chunks = [];
    let bytes = 0;
    let settled = false;
    const finishError = () => {
      if (settled) return;
      settled = true;
      reject(new Error("Local PostgREST relay failed."));
    };
    child.stdout.on("data", (chunk) => {
      bytes += chunk.byteLength;
      if (bytes > 4 * 1024 * 1024) {
        child.kill();
        finishError();
        return;
      }
      chunks.push(chunk);
    });
    child.on("error", (error) => {
      console.log(
        `LOCAL_POSTGREST_RELAY_PROCESS_ERROR=${safeCode(error?.code)}`,
      );
      finishError();
    });
    child.on("close", (code) => {
      if (settled || code !== 0) {
        if (code !== 0) {
          console.log(
            `LOCAL_POSTGREST_RELAY_EXIT=${
              Number.isInteger(code) ? code : "signal"
            }`,
          );
        }
        return finishError();
      }
      const output = Buffer.concat(chunks).toString("utf8");
      const marker = output.lastIndexOf("\n__HTTP_STATUS__:");
      if (marker < 0) return finishError();
      const status = Number(output.slice(marker + "\n__HTTP_STATUS__:".length));
      if (!Number.isInteger(status) || status < 100 || status > 599) {
        return finishError();
      }
      if (status < 200 || status >= 300) {
        console.log(`LOCAL_POSTGREST_HTTP_STATUS=${status}`);
      }
      settled = true;
      resolve(
        new Response(output.slice(0, marker), {
          status,
          headers: { "content-type": "application/json" },
        }),
      );
    });
    init.signal?.addEventListener("abort", () => {
      child.kill();
      finishError();
    }, { once: true });
    child.stdin.end(init.body ?? "");
  });
}

function signHmac(secret, content) {
  return hmacSha256("sha256", secret).update(content).digest("base64url");
}
