import assert from "node:assert/strict";
import test from "node:test";
import { runCatalogReconciliationScan } from "./catalog_reconciliation_scan.mjs";

const SNAPSHOT = "snapshot-local-2026-10-21";
const OP_A = "00000000-0000-4000-8000-000000000001";
const OP_B = "00000000-0000-4000-8000-000000000002";

test("resumes a bounded read-only scan from its committed cursor without duplicating findings", async () => {
  const pages = [
    page([canonical("legacy-a", OP_A)], [], "legacy-a", false),
    page([canonical("legacy-b", OP_B)], [], "legacy-b", true),
  ];
  const fixture = harness(pages);

  const first = await runCatalogReconciliationScan({
    snapshotId: SNAPSHOT,
    reader: fixture.reader,
    checkpointStore: fixture.checkpointStore,
    pageSize: 1,
    maxPages: 1,
  });
  assert.equal(first.state, "paused");
  assert.equal(first.checkpoint.cursor, "legacy-a");
  assert.equal(first.checkpoint.sequence, 1);
  assert.deepEqual(first.summary, { projection_missing: 1 });

  const resumed = await runCatalogReconciliationScan({
    snapshotId: SNAPSHOT,
    reader: fixture.reader,
    checkpointStore: fixture.checkpointStore,
    pageSize: 1,
    maxPages: 1,
  });
  assert.equal(resumed.state, "complete");
  assert.equal(resumed.checkpoint.cursor, "legacy-b");
  assert.equal(resumed.checkpoint.sequence, 2);
  assert.deepEqual(resumed.summary, { projection_missing: 2 });
  assert.deepEqual(fixture.findings.map((entry) => entry.id), [
    "legacy-a",
    "legacy-b",
  ]);
  assert.deepEqual(fixture.readCursors, [null, "legacy-a"]);
});

test("does not advance a checkpoint when a snapshot page read fails", async () => {
  const fixture = harness([]);
  fixture.reader.readPage = async () => {
    throw Object.assign(new Error("private upstream message"), {
      code: "snapshot-expired",
    });
  };

  await assert.rejects(
    runCatalogReconciliationScan({
      snapshotId: SNAPSHOT,
      reader: fixture.reader,
      checkpointStore: fixture.checkpointStore,
    }),
    (error) =>
      error.code === "snapshot_expired" &&
      !error.message.includes("private upstream"),
  );
  assert.equal(fixture.checkpoint, null);
  assert.equal(fixture.findings.length, 0);
});

test("sanitizes checkpoint read failures without labeling them as destination writes", async () => {
  const fixture = harness([]);
  fixture.checkpointStore.load = async () => {
    throw new Error("private checkpoint store detail");
  };

  await assert.rejects(
    runCatalogReconciliationScan({
      snapshotId: SNAPSHOT,
      reader: fixture.reader,
      checkpointStore: fixture.checkpointStore,
    }),
    (error) =>
      error.code === "checkpoint_read_failed" &&
      !error.message.includes("private checkpoint"),
  );
  assert.equal(fixture.readCursors.length, 0);
});

test("rejects a page from a different snapshot before committing it", async () => {
  const fixture = harness([
    page([canonical("legacy-a", OP_A)], [], "legacy-a", true, "other-snapshot"),
  ]);

  await assert.rejects(
    runCatalogReconciliationScan({
      snapshotId: SNAPSHOT,
      reader: fixture.reader,
      checkpointStore: fixture.checkpointStore,
    }),
    { code: "invalid_snapshot_page" },
  );
  assert.equal(fixture.checkpoint, null);
  assert.equal(fixture.findings.length, 0);
});

test("rejects repeated or unsorted IDs rather than producing a partial reconciliation", async () => {
  const fixture = harness([{
    snapshotId: SNAPSHOT,
    canonicalDocuments: [
      canonical("legacy-b", OP_B),
      canonical("legacy-a", OP_A),
    ],
    catalogRows: [],
    tombstones: [],
    nextCursor: "legacy-a",
    done: true,
  }]);

  await assert.rejects(
    runCatalogReconciliationScan({
      snapshotId: SNAPSHOT,
      reader: fixture.reader,
      checkpointStore: fixture.checkpointStore,
    }),
    { code: "invalid_snapshot_page" },
  );
  assert.equal(fixture.checkpoint, null);
});

test("orders Unicode IDs by code point to match deterministic PostgreSQL C collation", async () => {
  const privateUse = "\uE000";
  const supplementary = "\u{10000}";
  assert.ok(
    privateUse > supplementary,
    "the fixture distinguishes UTF-16 from code-point order",
  );
  const fixture = harness([{
    snapshotId: SNAPSHOT,
    canonicalDocuments: [
      canonical(privateUse, OP_A),
      canonical(supplementary, OP_B),
    ],
    catalogRows: [],
    tombstones: [],
    nextCursor: supplementary,
    done: true,
  }]);

  const result = await runCatalogReconciliationScan({
    snapshotId: SNAPSHOT,
    reader: fixture.reader,
    checkpointStore: fixture.checkpointStore,
    pageSize: 2,
  });
  assert.equal(result.state, "complete");
  assert.equal(result.checkpoint.cursor, supplementary);
  assert.deepEqual(result.checkpoint.summary, { projection_missing: 2 });
});

test("rejects reserved Firestore IDs before recording any recommendation", async () => {
  const fixture = harness([
    page([canonical("__reserved__", OP_A)], [], "__reserved__", true),
  ]);

  await assert.rejects(
    runCatalogReconciliationScan({
      snapshotId: SNAPSHOT,
      reader: fixture.reader,
      checkpointStore: fixture.checkpointStore,
    }),
    { code: "invalid_snapshot_page" },
  );
  assert.equal(fixture.checkpoint, null);
  assert.equal(fixture.findings.length, 0);
});

test("keeps the last checkpoint when atomic report persistence fails", async () => {
  const fixture = harness([
    page([canonical("legacy-a", OP_A)], [], "legacy-a", true),
  ]);
  fixture.checkpointStore.commitPage = async () => {
    throw new Error("private persistence failure");
  };

  await assert.rejects(
    runCatalogReconciliationScan({
      snapshotId: SNAPSHOT,
      reader: fixture.reader,
      checkpointStore: fixture.checkpointStore,
    }),
    (error) =>
      error.code === "checkpoint_commit_failed" &&
      !error.message.includes("private persistence"),
  );
  assert.equal(fixture.checkpoint, null);
  assert.equal(fixture.findings.length, 0);
});

test("checkpoint compare-and-swap prevents two scanners from committing the same page", async () => {
  const fixture = harness([
    page([canonical("legacy-a", OP_A)], [], "legacy-a", true),
  ]);
  const options = {
    snapshotId: SNAPSHOT,
    reader: fixture.reader,
    checkpointStore: fixture.checkpointStore,
  };
  const results = await Promise.allSettled([
    runCatalogReconciliationScan(options),
    runCatalogReconciliationScan(options),
  ]);

  assert.equal(
    results.filter((result) => result.status === "fulfilled").length,
    1,
  );
  assert.equal(
    results.filter((result) =>
      result.status === "rejected" &&
      result.reason.code === "checkpoint_conflict"
    ).length,
    1,
  );
  assert.equal(fixture.checkpoint.sequence, 1);
  assert.equal(fixture.findings.length, 1);
});

test("enforces page limits and reports a resumable pause instead of reading unbounded data", async () => {
  const fixture = harness([
    page([canonical("legacy-a", OP_A)], [], "legacy-a", false),
    page([canonical("legacy-b", OP_B)], [], "legacy-b", true),
  ]);

  const result = await runCatalogReconciliationScan({
    snapshotId: SNAPSHOT,
    reader: fixture.reader,
    checkpointStore: fixture.checkpointStore,
    maxPages: 1,
  });
  assert.equal(result.state, "paused");
  assert.equal(result.checkpoint.sequence, 1);
  assert.equal(fixture.readCursors.length, 1);
});

function harness(pages) {
  const fixture = {
    checkpoint: null,
    findings: [],
    readCursors: [],
  };
  fixture.reader = {
    async readPage({ snapshotId, afterId, limit }) {
      fixture.readCursors.push(afterId);
      assert.equal(snapshotId, SNAPSHOT);
      assert.ok(limit > 0);
      const pageIndex = afterId === null
        ? 0
        : pages.findIndex((candidate) => candidate.nextCursor === afterId) + 1;
      const current = pages[pageIndex];
      if (!current) throw new Error("unexpected page read");
      return current;
    },
  };
  fixture.checkpointStore = {
    async load(id) {
      assert.equal(id, SNAPSHOT);
      return fixture.checkpoint;
    },
    async commitPage({ expectedSequence, checkpoint, findings }) {
      const actual = fixture.checkpoint?.sequence ?? 0;
      if (expectedSequence !== actual) {
        throw Object.assign(new Error("checkpoint conflict"), {
          code: "checkpoint_conflict",
        });
      }
      fixture.findings.push(...findings);
      fixture.checkpoint = structuredClone(checkpoint);
    },
  };
  return fixture;
}

function canonical(id, operationId) {
  return {
    id,
    data: {
      name: `Business ${id}`,
      category: "Comércio",
      published: true,
      active: true,
      catalogVersion: 1,
      outboxOperationId: operationId,
    },
  };
}

function page(
  canonicalDocuments,
  catalogRows,
  nextCursor,
  done,
  snapshotId = SNAPSHOT,
) {
  return {
    snapshotId,
    canonicalDocuments,
    catalogRows,
    tombstones: [],
    nextCursor,
    done,
  };
}
