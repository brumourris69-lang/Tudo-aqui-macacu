import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createCatalogReconciliationFileCheckpointStore } from "./catalog_reconciliation_file_checkpoint_store.mjs";

const SNAPSHOT = "reconciliation-v1.synthetic-snapshot-handle";
const OPERATION = "70000000-0000-4000-8000-000000000002";

test("atomically resumes checkpoint and public findings from a new store instance", async (t) => {
  const directory = await tempDirectory(t);
  const store = createCatalogReconciliationFileCheckpointStore({ directory });
  const current = checkpoint(1);

  assert.equal(await store.load(SNAPSHOT), null);
  await store.commitPage({
    expectedSequence: 0,
    checkpoint: current,
    findings: [finding()],
  });
  assert.deepEqual(
    await createCatalogReconciliationFileCheckpointStore({ directory }).load(
      SNAPSHOT,
    ),
    current,
  );
  assert.deepEqual(await store.loadReport(SNAPSHOT), {
    checkpoint: current,
    findings: [finding()],
  });
});

test("compare-and-swap serializes concurrent writers across independent store instances", async (t) => {
  const directory = await tempDirectory(t);
  const first = createCatalogReconciliationFileCheckpointStore({ directory });
  const second = createCatalogReconciliationFileCheckpointStore({ directory });
  const results = await Promise.allSettled([
    first.commitPage({
      expectedSequence: 0,
      checkpoint: checkpoint(1),
      findings: [finding()],
    }),
    second.commitPage({
      expectedSequence: 0,
      checkpoint: checkpoint(1),
      findings: [finding()],
    }),
  ]);

  assert.equal(
    results.filter(({ status }) => status === "fulfilled").length,
    1,
  );
  const rejected = results.find(({ status }) => status === "rejected");
  assert.equal(rejected.reason.code, "checkpoint_conflict");
  const report = await first.loadReport(SNAPSHOT);
  assert.equal(report.checkpoint.sequence, 1);
  assert.equal(report.findings.length, 1);
});

test("keeps snapshot handles confined and rejects private fields or invalid sequence transitions", async (t) => {
  const directory = await tempDirectory(t);
  const store = createCatalogReconciliationFileCheckpointStore({ directory });
  assert.equal(await store.load("../escape"), null);
  await assert.rejects(
    store.commitPage({
      expectedSequence: 0,
      checkpoint: checkpoint(1),
      findings: [{ ...finding(), ownerEmail: "private" }],
    }),
    { code: "invalid_checkpoint" },
  );
  await assert.rejects(
    store.commitPage({
      expectedSequence: 0,
      checkpoint: checkpoint(2),
      findings: [finding()],
    }),
    { code: "invalid_checkpoint" },
  );
  assert.equal(await store.load(SNAPSHOT), null);
});

test("does not advance report or checkpoint when an existing sequence does not match", async (t) => {
  const directory = await tempDirectory(t);
  const store = createCatalogReconciliationFileCheckpointStore({ directory });
  await store.commitPage({
    expectedSequence: 0,
    checkpoint: checkpoint(1),
    findings: [finding()],
  });
  await assert.rejects(
    store.commitPage({
      expectedSequence: 0,
      checkpoint: checkpoint(1),
      findings: [finding("another-id")],
    }),
    { code: "checkpoint_conflict" },
  );
  assert.deepEqual(await store.loadReport(SNAPSHOT), {
    checkpoint: checkpoint(1),
    findings: [finding()],
  });
});

test("rejects a checkpoint directory redirected through a Windows junction", async (t) => {
  const parent = await tempDirectory(t);
  const target = join(parent, "actual");
  const redirected = join(parent, "redirected");
  await import("node:fs/promises").then(({ mkdir }) => mkdir(target));
  try {
    await symlink(target, redirected, "junction");
  } catch (error) {
    if (["EPERM", "EACCES", "ENOTSUP"].includes(error?.code)) {
      t.skip("Windows does not permit creating a junction in this environment");
      return;
    }
    throw error;
  }

  const store = createCatalogReconciliationFileCheckpointStore({
    directory: redirected,
  });
  await assert.rejects(store.load(SNAPSHOT), {
    code: "checkpoint_storage_failed",
  });
});

test("uses a real bounded lock deadline even when the report clock is frozen", async (t) => {
  const directory = await tempDirectory(t);
  const lockName = createHash("sha256").update(SNAPSHOT, "utf8").digest("hex");
  await writeFile(join(directory, `${lockName}.json.lock`), "{}", {
    flag: "wx",
  });
  const childScript = `
    import { createCatalogReconciliationFileCheckpointStore } from ${
    JSON.stringify(
      new URL(
        "./catalog_reconciliation_file_checkpoint_store.mjs",
        import.meta.url,
      ).href,
    )
  };
    const store = createCatalogReconciliationFileCheckpointStore({
      directory: process.argv[1], lockWaitMs: 100, now: () => 1,
    });
    await store.commitPage({ expectedSequence: 0, checkpoint: {
      schemaVersion: 1, snapshotId: ${JSON.stringify(SNAPSHOT)}, pageSize: 1,
      cursor: "fixture-id", sequence: 1, scannedCount: 1,
      summary: { projection_missing: 1 }, done: false,
    }, findings: [] }).then(() => process.exit(2), (error) => {
      process.exit(error.code === "checkpoint_conflict" ? 0 : 3);
    });
  `;
  const result = spawnSync(
    process.execPath,
    ["--input-type=module", "-e", childScript, directory],
    { encoding: "utf8", timeout: 2_000, windowsHide: true },
  );
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, result.stderr);
});

async function tempDirectory(t) {
  const directory = await mkdtemp(
    join(tmpdir(), "macacu-reconciliation-checkpoint-"),
  );
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

function checkpoint(sequence, cursor = "fixture-id") {
  return {
    schemaVersion: 1,
    snapshotId: SNAPSHOT,
    pageSize: 1,
    cursor,
    sequence,
    scannedCount: sequence,
    summary: { projection_missing: sequence },
    done: false,
  };
}

function finding(id = "fixture-id") {
  return {
    id,
    status: "projection_missing",
    action: "apply_projection",
    payload: {
      id,
      content_kind: "establishment",
      category_group: "commerce",
      name: "Synthetic Shop",
      summary: "",
      category: "Comércio",
      subcategory: "",
      location: null,
      artwork: 0,
      image_url: "",
      logo_url: "",
      gallery_urls: [],
      featured: false,
      is_open: true,
      maps_url: "",
      hours: "",
      services: [],
      products: [],
      additional_info: "",
      promotion_title: "",
      promotion_description: "",
      public_contact_approved: false,
      phone: null,
      whatsapp: null,
      instagram: null,
      published: true,
      active: true,
      expires_at: null,
      deleted_at: null,
      catalog_version: 1,
      outbox_operation_id: OPERATION,
    },
  };
}
