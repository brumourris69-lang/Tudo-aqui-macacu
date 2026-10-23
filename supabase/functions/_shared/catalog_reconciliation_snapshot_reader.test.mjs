import assert from "node:assert/strict";
import test from "node:test";
import { createCatalogReconciliationSnapshotReader } from "./catalog_reconciliation_snapshot_reader.mjs";

const SNAPSHOT = "70000000-0000-4000-8000-000000000001";
const OP = "70000000-0000-4000-8000-000000000002";
const READ_TIME = "2026-10-21T12:00:00.000000Z";
const CAPTURED = "2026-10-21T12:00:00.000Z";
const EXPIRES = "2026-10-21T13:00:00.000Z";

test("begins paired snapshots and combines both ordered sources without skipping IDs", async () => {
  const calls = [];
  const firestore = {
    async queryEstablishmentsSnapshotPage(args) {
      calls.push({ source: "firestore", ...args });
      if (args.readTime === undefined) {
        return { documents: [], readTime: READ_TIME, hasMore: false };
      }
      if (args.startAfterDocumentId === null) {
        return {
          documents: [canonical("a"), canonical("c")],
          readTime: READ_TIME,
          hasMore: false,
        };
      }
      return {
        documents: [canonical("c")],
        readTime: READ_TIME,
        hasMore: false,
      };
    },
  };
  const catalog = {
    async beginSnapshot(id) {
      calls.push({ source: "begin", id });
      return snapshotHeader(id);
    },
    async readPage(args) {
      calls.push({ source: "catalog", ...args });
      if (args.afterId === null) {
        return {
          snapshot_id: SNAPSHOT,
          captured_at: CAPTURED,
          expires_at: EXPIRES,
          next_cursor: "c",
          done: true,
          catalog_rows: [row("b"), row("c")],
          tombstones: [],
        };
      }
      return {
        snapshot_id: SNAPSHOT,
        captured_at: CAPTURED,
        expires_at: EXPIRES,
        next_cursor: "c",
        done: true,
        catalog_rows: [row("c")],
        tombstones: [],
      };
    },
    async disposeSnapshot(id) {
      calls.push({ source: "dispose", id });
      return true;
    },
  };
  const reader = createCatalogReconciliationSnapshotReader({
    firestore,
    catalog,
    now: () => Date.parse(CAPTURED),
    createSnapshotId: () => SNAPSHOT,
  });

  const snapshotId = await reader.beginSnapshot();
  const first = await reader.readPage({ snapshotId, afterId: null, limit: 2 });
  const second = await reader.readPage({
    snapshotId,
    afterId: first.nextCursor,
    limit: 2,
  });

  assert.equal(typeof snapshotId, "string");
  assert.equal(snapshotId.length <= 256, true);
  assert.deepEqual(first.canonicalDocuments.map(({ id }) => id), ["a"]);
  assert.deepEqual(first.catalogRows.map(({ id }) => id), ["b"]);
  assert.equal(first.nextCursor, "b");
  assert.equal(first.done, false);
  assert.deepEqual(second.canonicalDocuments.map(({ id }) => id), ["c"]);
  assert.deepEqual(second.catalogRows.map(({ id }) => id), ["c"]);
  assert.equal(second.nextCursor, "c");
  assert.equal(second.done, true);
  assert.ok(
    calls.filter(({ source }) => source === "firestore" && source !== "begin")
      .every(({ readTime }) =>
        readTime === undefined || readTime === READ_TIME
      ),
  );
  assert.ok(
    calls.filter(({ source }) => source === "catalog")
      .every(({ snapshotId: used }) => used === SNAPSHOT),
  );
});

test("preserves the Unicode code-point cursor and filters canonical data to the public allowlist", async () => {
  const firestore = {
    async queryEstablishmentsSnapshotPage(args) {
      if (args.readTime === undefined) {
        return { documents: [], readTime: READ_TIME, hasMore: false };
      }
      return {
        documents: [{
          id: "\u{10000}",
          data: {
            name: "Unicode fixture",
            category: "Comércio",
            catalogVersion: 1,
            outboxOperationId: OP,
            ownerEmail: "private@example.invalid",
            phone: "private phone",
            publicContactApproved: false,
          },
          updateTime: CAPTURED,
        }],
        readTime: READ_TIME,
        hasMore: false,
      };
    },
  };
  const catalog = emptyCatalog();
  const reader = makeReader({ firestore, catalog });
  const snapshotId = await reader.beginSnapshot();
  const page = await reader.readPage({ snapshotId, afterId: null, limit: 10 });

  assert.equal(page.canonicalDocuments[0].id, "\u{10000}");
  assert.deepEqual(page.canonicalDocuments[0].data, {
    name: "Unicode fixture",
    category: "Comércio",
    catalogVersion: 1,
    outboxOperationId: OP,
    publicContactApproved: false,
  });
  assert.equal(JSON.stringify(page).includes("private@example.invalid"), false);
  assert.equal(JSON.stringify(page).includes("private phone"), false);
});

test("disposes destination snapshot when Firestore snapshot capture cannot be established", async () => {
  let disposed = 0;
  const reader = makeReader({
    firestore: {
      async queryEstablishmentsSnapshotPage() {
        throw Object.assign(new Error("secret"), {
          code: "backend_unavailable",
        });
      },
    },
    catalog: {
      ...emptyCatalog(),
      async disposeSnapshot() {
        disposed += 1;
        return true;
      },
    },
  });

  await assert.rejects(reader.beginSnapshot(), {
    code: "snapshot_read_failed",
  });
  assert.equal(disposed, 1);
});

test("rejects tampered, expired, and out-of-range snapshot requests before reading either source", async () => {
  let reads = 0;
  const reader = makeReader({
    now: () => Date.parse("2026-10-21T14:00:00.000Z"),
    firestore: {
      async queryEstablishmentsSnapshotPage() {
        reads += 1;
        throw new Error("unexpected");
      },
    },
  });

  await assert.rejects(
    reader.readPage({ snapshotId: "not-a-snapshot", afterId: null, limit: 10 }),
    {
      code: "invalid_snapshot",
    },
  );
  assert.equal(reads, 0);
});

function makeReader(
  { firestore, catalog = emptyCatalog(), now = () => Date.parse(CAPTURED) },
) {
  return createCatalogReconciliationSnapshotReader({
    firestore,
    catalog,
    now,
    createSnapshotId: () => SNAPSHOT,
  });
}

function emptyCatalog() {
  return {
    async beginSnapshot(id) {
      return snapshotHeader(id);
    },
    async readPage({ snapshotId }) {
      return {
        snapshot_id: snapshotId,
        captured_at: CAPTURED,
        expires_at: EXPIRES,
        next_cursor: null,
        done: true,
        catalog_rows: [],
        tombstones: [],
      };
    },
    async disposeSnapshot() {
      return true;
    },
  };
}

function canonical(id) {
  return {
    id,
    data: {
      name: `Shop ${id}`,
      category: "Comércio",
      catalogVersion: 1,
      outboxOperationId: OP,
    },
    updateTime: CAPTURED,
  };
}

function snapshotHeader(snapshotId) {
  return {
    snapshot_id: snapshotId,
    captured_at: CAPTURED,
    expires_at: EXPIRES,
    entity_count: 2,
    payload_bytes: 100,
    replayed: false,
  };
}

function row(id) {
  return { id, catalog_version: 1, outbox_operation_id: OP };
}
