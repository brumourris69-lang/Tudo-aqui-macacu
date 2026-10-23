import { test } from "node:test";
import assert from "node:assert/strict";
import { createFirebaseFirestoreOutboxAdapter } from "./firebase_firestore_outbox_adapter.mjs";
import { createFirebaseFirestoreRestStore } from "./firebase_firestore_rest.mjs";

const PROJECT_ID = "tudo-aqui-macacu";
const TOKEN = "mock-service-token-secret-sentinel";

function firestoreDocument(name, fields, updateTime = "2026-10-20T12:00:00Z") {
  return { name, fields, updateTime };
}

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function transactionReadName(init) {
  return JSON.parse(init.body).structuredQuery.where.fieldFilter.value
    .referenceValue;
}

function transactionReadResponse(
  name,
  fields,
  updateTime = "2026-10-20T12:00:00Z",
) {
  return jsonResponse(
    fields === null ? [{ readTime: "2026-10-20T12:00:00Z" }] : [{
      document: firestoreDocument(name, fields, updateTime),
      readTime: "2026-10-20T12:00:00Z",
    }],
  );
}

test("commits source and outbox writes in one Firestore transaction", async () => {
  const calls = [];
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    now: () => Date.parse("2026-10-20T12:00:00Z"),
    fetchImpl: async (url, init) => {
      calls.push({ url: String(url), init });
      if (String(url).endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "opaque-tx-id" });
      }
      if (String(url).endsWith(":runQuery")) {
        const name = transactionReadName(init);
        if (name.endsWith("/admin_authorizations/admin-uid")) {
          return transactionReadResponse(name, {
            enabled: { booleanValue: true },
            pending: { booleanValue: false },
            version: { stringValue: "admin-v1" },
          });
        }
        if (name.endsWith("/catalog_outbox/request-id-123456")) {
          return transactionReadResponse(name, null);
        }
      }
      if (String(url).includes("/catalog_outbox/")) {
        return new Response("", { status: 404 });
      }
      if (String(url).endsWith(":commit")) {
        return jsonResponse({
          commitTime: "2026-10-20T12:00:00Z",
          writeResults: [{}, {}],
        });
      }
      throw new Error("unexpected request");
    },
  });

  await store.runTransaction(async (transaction) => {
    const admin = await transaction.get("admin_authorizations", "admin-uid");
    assert.equal(admin.data.enabled, true);
    assert.equal(
      await transaction.get("catalog_outbox", "request-id-123456"),
      null,
    );
    transaction.create("establishments", "entity-1", {
      name: "Example",
      catalogVersion: 1,
    }, {
      serverTimestampFields: ["createdAt", "updatedAt"],
    });
    transaction.create("catalog_outbox", "request-id-123456", {
      schemaVersion: 2,
      operationId: "request-id-123456",
      entityType: "establishment",
      entityId: "entity-1",
      authorUid: "admin-uid",
      version: 1,
      operation: "reconcile",
      state: "pending",
      attemptCount: 0,
      workerId: null,
      leaseToken: null,
      leaseExpiresAt: null,
      nextAttemptAt: null,
      lastErrorCode: null,
      syncedAt: null,
    }, {
      serverTimestampFields: ["createdAt", "updatedAt"],
    });
  });

  const commitCalls = calls.filter(({ url }) => url.endsWith(":commit"));
  assert.equal(commitCalls.length, 1);
  const commit = JSON.parse(commitCalls[0].init.body);
  assert.equal(commit.transaction, "opaque-tx-id");
  assert.equal(commit.writes.length, 2);
  assert.equal(
    commit.writes[0].update.name,
    `projects/${PROJECT_ID}/databases/(default)/documents/establishments/entity-1`,
  );
  assert.equal(
    commit.writes[1].update.name,
    `projects/${PROJECT_ID}/databases/(default)/documents/catalog_outbox/request-id-123456`,
  );
  assert.ok(commit.writes.every((write) => !write.update.name.includes("://")));
  const transactionalReads = calls.filter(({ url }) =>
    url.endsWith(":runQuery")
  );
  assert.equal(transactionalReads.length, 2);
  assert.deepEqual(
    transactionalReads.map(({ init }) => {
      const body = JSON.parse(init.body);
      return {
        transaction: body.transaction,
        collection: body.structuredQuery.from[0].collectionId,
        field: body.structuredQuery.where.fieldFilter.field.fieldPath,
        operator: body.structuredQuery.where.fieldFilter.op,
        reference: body.structuredQuery.where.fieldFilter.value.referenceValue,
      };
    }),
    [
      {
        transaction: "opaque-tx-id",
        collection: "admin_authorizations",
        field: "__name__",
        operator: "EQUAL",
        reference:
          `projects/${PROJECT_ID}/databases/(default)/documents/admin_authorizations/admin-uid`,
      },
      {
        transaction: "opaque-tx-id",
        collection: "catalog_outbox",
        field: "__name__",
        operator: "EQUAL",
        reference:
          `projects/${PROJECT_ID}/databases/(default)/documents/catalog_outbox/request-id-123456`,
      },
    ],
  );
  assert.ok(
    commit.writes.every((write) => write.currentDocument?.exists === false),
  );
  assert.ok(
    commit.writes.every((write) =>
      write.updateTransforms.some((item) =>
        item.setToServerValue === "REQUEST_TIME"
      )
    ),
  );
  for (
    const field of [
      "workerId",
      "leaseToken",
      "leaseExpiresAt",
      "nextAttemptAt",
      "lastErrorCode",
      "syncedAt",
    ]
  ) {
    assert.deepEqual(commit.writes[1].update.fields[field], {
      nullValue: null,
    });
  }
  assert.ok(
    calls.every(({ init }) => init.headers.authorization === `Bearer ${TOKEN}`),
  );
  assert.equal(commitCalls[0].url.includes(PROJECT_ID), true);
});

test("hosted homologation store accepts only an explicit non-production staging project", async () => {
  const stagingProject = "macacu-staging-261022";
  const requests = [];
  const options = {
    projectId: stagingProject,
    homologationProjectId: stagingProject,
    serviceAccountJson: JSON.stringify({
      type: "service_account",
      project_id: stagingProject,
    }),
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      if (String(url).endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "staging-tx" });
      }
      if (String(url).endsWith(":runQuery")) return jsonResponse([]);
      if (String(url).endsWith(":rollback")) return jsonResponse({});
      throw new Error("unexpected request");
    },
  };
  const store = createFirebaseFirestoreRestStore(options);
  await store.runTransaction((transaction) =>
    transaction.get("catalog_outbox", "operation-id-123456")
  );
  assert.equal(requests.length, 3);
  assert.ok(
    requests.every(({ url }) => url.includes(`/projects/${stagingProject}/`)),
  );
  assert.throws(() =>
    createFirebaseFirestoreRestStore({
      ...options,
      homologationProjectId: undefined,
    })
  );
  assert.throws(() =>
    createFirebaseFirestoreRestStore({ ...options, projectId: PROJECT_ID })
  );
  assert.throws(() =>
    createFirebaseFirestoreRestStore({
      ...options,
      projectId: "demo-universal-search",
      homologationProjectId: "demo-universal-search",
    })
  );
  assert.throws(() =>
    createFirebaseFirestoreRestStore({
      ...options,
      projectId: "macacu-prod-261022",
      homologationProjectId: "macacu-prod-261022",
    })
  );
});

test("Firestore REST adapter uses canonical resource names for Unicode and percent IDs", async () => {
  const requests = [];
  const id = "loja-café%Local";
  const expectedName =
    `projects/${PROJECT_ID}/databases/(default)/documents/establishments/${id}`;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      if (String(url).endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "unicode-tx" });
      }
      if (String(url).endsWith(":runQuery")) {
        const name = transactionReadName(init);
        assert.equal(name, expectedName);
        return transactionReadResponse(name, null);
      }
      if (String(url).endsWith(":rollback")) {
        return new Response("", { status: 200 });
      }
      throw new Error("unexpected request");
    },
  });

  const result = await store.runTransaction((transaction) =>
    transaction.get("establishments", id)
  );

  assert.equal(result, null);
  assert.equal(
    requests.some(({ init }) => {
      const body = JSON.parse(init.body);
      return body.structuredQuery?.where?.fieldFilter?.value?.referenceValue ===
        expectedName;
    }),
    true,
  );
});

test("rolls back read-only transactions so inspection does not leave Firestore transactions open", async () => {
  const calls = [];
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      const target = String(url);
      calls.push(target);
      if (target.endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "read-only-tx" });
      }
      if (target.endsWith(":rollback")) {
        assert.deepEqual(JSON.parse(init.body), {
          transaction: "read-only-tx",
        });
        return jsonResponse({});
      }
      throw new Error(
        "read-only transaction must not issue reads or writes in this focused test",
      );
    },
  });

  assert.equal(
    await store.runTransaction(async () => "inspected"),
    "inspected",
  );
  assert.deepEqual(
    calls.map((url) => new URL(url).pathname.split(":").at(-1)),
    ["beginTransaction", "rollback"],
  );
});

test("uses updateTime preconditions and update masks for existing legacy documents", async () => {
  let commitBody;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      const target = String(url);
      if (target.endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "tx-update" });
      }
      if (target.endsWith(":runQuery")) {
        const name = transactionReadName(init);
        assert.equal(
          name,
          `projects/${PROJECT_ID}/databases/(default)/documents/establishments/entity-1`,
        );
        return transactionReadResponse(name, {
          name: { stringValue: "Legacy" },
          legacyPrivate: { stringValue: "do-not-overwrite" },
        }, "2026-10-20T11:00:00Z");
      }
      if (target.endsWith(":commit")) {
        commitBody = JSON.parse(init.body);
        return jsonResponse({});
      }
      throw new Error("unexpected request");
    },
  });
  await store.runTransaction(async (transaction) => {
    const source = await transaction.get("establishments", "entity-1");
    transaction.update("establishments", "entity-1", {
      name: "Changed",
      catalogVersion: 2,
    }, {
      updateTime: source.updateTime,
      serverTimestampFields: ["updatedAt"],
    });
  });
  const write = commitBody.writes[0];
  assert.deepEqual(write.currentDocument, {
    updateTime: "2026-10-20T11:00:00Z",
  });
  assert.deepEqual(write.updateMask.fieldPaths.sort(), [
    "catalogVersion",
    "name",
  ]);
  assert.equal(write.update.fields.legacyPrivate, undefined);
});

test("removes an optional field through the REST update mask without writing null", async () => {
  let commitBody;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      const target = String(url);
      if (target.endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "tx-delete-field" });
      }
      if (target.endsWith(":runQuery")) {
        const name = transactionReadName(init);
        return transactionReadResponse(name, {
          expiresAt: { timestampValue: "2026-12-31T23:59:59Z" },
        });
      }
      if (target.endsWith(":commit")) {
        commitBody = JSON.parse(init.body);
        return jsonResponse({});
      }
      throw new Error("unexpected request");
    },
  });
  await store.runTransaction(async (transaction) => {
    const source = await transaction.get("establishments", "entity-1");
    transaction.update("establishments", "entity-1", { catalogVersion: 2 }, {
      updateTime: source.updateTime,
      deleteFields: ["expiresAt"],
    });
  });
  const write = commitBody.writes[0];
  assert.ok(write.updateMask.fieldPaths.includes("expiresAt"));
  assert.equal(write.update.fields.expiresAt, undefined);
});

test("allows an update whose only change is deleting the optional expiry field", async () => {
  let commitBody;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      const target = String(url);
      if (target.endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "tx-delete-only-field" });
      }
      if (target.endsWith(":runQuery")) {
        const name = transactionReadName(init);
        return transactionReadResponse(name, {
          expiresAt: { timestampValue: "2026-12-31T23:59:59Z" },
        });
      }
      if (target.endsWith(":commit")) {
        commitBody = JSON.parse(init.body);
        return jsonResponse({});
      }
      throw new Error("unexpected request");
    },
  });

  await store.runTransaction(async (transaction) => {
    const source = await transaction.get("establishments", "entity-1");
    transaction.update("establishments", "entity-1", {}, {
      updateTime: source.updateTime,
      deleteFields: ["expiresAt"],
    });
  });

  const write = commitBody.writes[0];
  assert.deepEqual(write.updateMask.fieldPaths, ["expiresAt"]);
  assert.deepEqual(write.update.fields, {});
});

test("keeps project and collection allowlists fixed and rejects unsafe document paths", async () => {
  const requests = [];
  assert.throws(
    () =>
      createFirebaseFirestoreRestStore({
        projectId: "demo-universal-search",
        getAccessToken: async () => TOKEN,
      }),
    { code: "invalid-request" },
  );
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url) => {
      requests.push(String(url));
      return jsonResponse({ transaction: "tx" });
    },
  });
  await assert.rejects(
    store.runTransaction((transaction) => transaction.get("users", "any")),
    { code: "invalid-request" },
  );
  await assert.rejects(
    store.runTransaction((transaction) =>
      transaction.get("establishments", "../other")
    ),
    { code: "invalid-request" },
  );
  assert.equal(requests.length, 4); // Both transactions begin and roll back; no unsafe document path is sent.
  assert.equal(
    requests.filter((url) => url.endsWith(":beginTransaction")).length,
    2,
  );
  assert.equal(requests.filter((url) => url.endsWith(":rollback")).length, 2);
});

test("trusted transaction store can access only the fixed internal scan checkpoint document", async () => {
  const requests = [];
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      if (String(url).endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "scan-state-tx" });
      }
      if (String(url).endsWith(":runQuery")) {
        const name = transactionReadName(init);
        return transactionReadResponse(name, null);
      }
      if (String(url).endsWith(":rollback")) return jsonResponse({});
      throw new Error("unexpected request");
    },
  });
  const result = await store.runTransaction((transaction) =>
    transaction.get("catalog_outbox_scan_state", "consumer-v1")
  );
  assert.equal(result, null);
  const query = requests.find(({ url }) => url.endsWith(":runQuery"));
  assert.equal(
    transactionReadName(query.init),
    `projects/${PROJECT_ID}/databases/(default)/documents/catalog_outbox_scan_state/consumer-v1`,
  );
  await assert.rejects(
    store.runTransaction((transaction) =>
      transaction.get("catalog_outbox_scan_state", "arbitrary")
    ),
    { code: "invalid-request" },
  );
});

test("converts Firestore errors to fixed codes and never returns raw response bodies", async () => {
  const secret = "private-firestore-response-sentinel";
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url) => {
      if (String(url).endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "tx-error" });
      }
      if (String(url).endsWith(":runQuery")) {
        return jsonResponse({
          error: { status: "UNAVAILABLE", message: secret },
        }, 503);
      }
      return jsonResponse(
        { error: { status: "UNAVAILABLE", message: secret } },
        503,
      );
    },
  });
  await assert.rejects(
    store.runTransaction((transaction) =>
      transaction.get("establishments", "entity-1")
    ),
    (error) => {
      assert.equal(error.code, "backend_unavailable");
      assert.equal(error.message.includes(secret), false);
      assert.equal(error.message.includes(TOKEN), false);
      return true;
    },
  );
});

test("keeps missing Firebase service credentials local and fails before any network request", async () => {
  let requests = 0;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    serviceAccountJson: "",
    fetchImpl: async () => {
      requests += 1;
      throw new Error("must not reach a network");
    },
  });
  await assert.rejects(store.runTransaction(async () => "unused"), {
    code: "backend_unavailable",
  });
  assert.equal(requests, 0);
});

test("a failed atomic commit is returned as unavailable without sending per-document writes", async () => {
  const requests = [];
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      if (String(url).endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "tx-failed-commit" });
      }
      if (String(url).endsWith(":commit")) {
        return jsonResponse({
          error: { message: "private backend body sentinel" },
        }, 503);
      }
      if (String(url).endsWith(":rollback")) return jsonResponse({});
      throw new Error("unexpected request");
    },
  });
  await assert.rejects(
    store.runTransaction(async (transaction) => {
      transaction.create("establishments", "entity-1", { name: "Atomic" });
      transaction.create("catalog_outbox", "request-id-123456", {
        state: "pending",
      });
    }),
    (error) => {
      assert.equal(error.code, "backend_unavailable");
      assert.equal(error.message.includes("sentinel"), false);
      return true;
    },
  );
  const commits = requests.filter(({ url }) => url.endsWith(":commit"));
  assert.equal(commits.length, 1);
  assert.equal(JSON.parse(commits[0].init.body).writes.length, 2);
  assert.equal(
    requests.some(({ url }) =>
      /\/documents\/(?:establishments|catalog_outbox)\//u.test(url)
    ),
    false,
  );
});

test("queries the outbox with fixed state filters, stable document ordering and snapshot cursor", async () => {
  const requests = [];
  const readTime = "2026-10-20T12:00:00.000000Z";
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      return jsonResponse([
        {
          document: firestoreDocument(
            "projects/tudo-aqui-macacu/databases/(default)/documents/catalog_outbox/op-1",
            {
              state: { stringValue: "pending" },
              createdAt: { timestampValue: readTime },
            },
          ),
          readTime,
        },
      ]);
    },
  });
  const page = await store.queryOutboxPage({
    limit: 20,
    readTime,
    startAfterDocumentId: "op-0",
  });
  assert.equal(requests.length, 1);
  assert.ok(requests[0].url.endsWith("/documents:runQuery"));
  const body = JSON.parse(requests[0].init.body);
  assert.equal(body.readTime, readTime);
  assert.equal(body.structuredQuery.from[0].collectionId, "catalog_outbox");
  assert.deepEqual(
    body.structuredQuery.where.fieldFilter.value.arrayValue.values,
    [
      { stringValue: "pending" },
      { stringValue: "processing" },
    ],
  );
  assert.deepEqual(body.structuredQuery.orderBy, [
    { field: { fieldPath: "__name__" }, direction: "ASCENDING" },
  ]);
  assert.equal(body.structuredQuery.startAt.before, false);
  assert.deepEqual(body.structuredQuery.startAt.values, [
    {
      referenceValue:
        "projects/tudo-aqui-macacu/databases/(default)/documents/catalog_outbox/op-0",
    },
  ]);
  assert.deepEqual(page.documents.map((item) => item.id), ["op-1"]);
  assert.equal(page.readTime, readTime);
  assert.equal(page.nextDocumentId, null);
  assert.equal(page.hasMore, false);
});

test("Firestore REST adapter rejects unsafe per-request timeout configuration", () => {
  assert.throws(() =>
    createFirebaseFirestoreRestStore({
      projectId: "demo-universal-search",
      emulator: { host: "127.0.0.1", port: 8087 },
      requestTimeoutMs: 50,
      fetchImpl: async () => jsonResponse([]),
    }), { code: "invalid-request" });
});

test("Firestore REST adapter aborts a stalled request at its configured timeout", async () => {
  const store = createFirebaseFirestoreRestStore({
    projectId: "demo-universal-search",
    emulator: { host: "127.0.0.1", port: 8087 },
    requestTimeoutMs: 100,
    fetchImpl: async (_url, init) =>
      await new Promise((_resolve, reject) => {
        if (init.signal.aborted) return reject(init.signal.reason);
        init.signal.addEventListener(
          "abort",
          () => reject(init.signal.reason),
          { once: true },
        );
      }),
  });
  await assert.rejects(store.queryOutboxPage({ limit: 1 }), (error) => {
    assert.equal(error.code, "backend_unavailable");
    assert.match(error.message, /unavailable/u);
    assert.doesNotMatch(error.message, /timeout|abort|secret/u);
    return true;
  });
});

test("queries canonical establishments at a fixed readTime with safe ID cursors and public-field projection", async () => {
  const requests = [];
  const readTime = "2026-10-21T12:00:00.000000Z";
  const id = "modelo-é-%legacy";
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      return jsonResponse([{
        document: firestoreDocument(
          `projects/${PROJECT_ID}/databases/(default)/documents/establishments/${id}`,
          {
            name: { stringValue: "Fixture Shop" },
            category: { stringValue: "Comércio" },
            published: { booleanValue: true },
            catalogVersion: { integerValue: "4" },
            outboxOperationId: {
              stringValue: "00000000-0000-4000-8000-000000000004",
            },
            publicContactApproved: { booleanValue: false },
            phone: { stringValue: "must-not-escape" },
            ownerEmail: { stringValue: "private@example.invalid" },
          },
        ),
        readTime,
      }]);
    },
  });

  const page = await store.queryEstablishmentsSnapshotPage({
    limit: 2,
    readTime,
    startAfterDocumentId: "modelo-a",
  });

  const body = JSON.parse(requests[0].init.body);
  assert.equal(body.readTime, readTime);
  assert.deepEqual(body.structuredQuery.from, [{
    collectionId: "establishments",
  }]);
  assert.deepEqual(body.structuredQuery.orderBy, [
    { field: { fieldPath: "__name__" }, direction: "ASCENDING" },
  ]);
  assert.equal(body.structuredQuery.limit, 2);
  assert.equal(body.structuredQuery.startAt.before, false);
  assert.deepEqual(body.structuredQuery.startAt.values, [{
    referenceValue:
      `projects/${PROJECT_ID}/databases/(default)/documents/establishments/modelo-a`,
  }]);
  assert.deepEqual(page.documents, [{
    id,
    data: {
      name: "Fixture Shop",
      category: "Comércio",
      published: true,
      catalogVersion: 4,
      outboxOperationId: "00000000-0000-4000-8000-000000000004",
      publicContactApproved: false,
    },
    updateTime: "2026-10-20T12:00:00Z",
  }]);
  assert.equal(page.readTime, readTime);
  assert.equal(page.hasMore, false);
  assert.equal(JSON.stringify(page).includes("must-not-escape"), false);
  assert.equal(JSON.stringify(page).includes("private@example.invalid"), false);
});

test("rejects invalid canonical snapshot arguments and inconsistent page reads before returning documents", async () => {
  let requests = 0;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async () => {
      requests += 1;
      return jsonResponse([]);
    },
  });
  await assert.rejects(store.queryEstablishmentsSnapshotPage({ limit: 0 }), {
    code: "invalid-request",
  });
  await assert.rejects(
    store.queryEstablishmentsSnapshotPage({
      limit: 1,
      startAfterDocumentId: "a/b",
    }),
    {
      code: "invalid-request",
    },
  );
  assert.equal(requests, 0);
});

test("rejects unsafe outbox query cursors and limits before sending a request", async () => {
  let requests = 0;
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    fetchImpl: async () => {
      requests += 1;
      return jsonResponse([]);
    },
  });
  await assert.rejects(store.queryOutboxPage({ limit: 101 }), {
    code: "invalid-request",
  });
  await assert.rejects(
    store.queryOutboxPage({ limit: 1, startAfterDocumentId: "../other" }),
    { code: "invalid-request" },
  );
  await assert.rejects(
    store.queryOutboxPage({ limit: 1, readTime: "not-a-timestamp" }),
    { code: "invalid-request" },
  );
  assert.equal(requests, 0);
});

test("emulator mode is an explicit loopback-only demo project transport", async () => {
  const requests = [];
  const store = createFirebaseFirestoreRestStore({
    projectId: "demo-universal-search",
    emulator: { host: "127.0.0.1", port: 18087 },
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), headers: init.headers });
      return jsonResponse([]);
    },
  });
  await store.queryOutboxPage({ limit: 1 });
  assert.match(
    requests[0].url,
    /^http:\/\/127\.0\.0\.1:18087\/v1\/projects\/demo-universal-search\/databases\/\(default\)\/documents:runQuery$/u,
  );
  assert.equal(requests[0].url.includes("firestore.googleapis.com"), false);
  assert.equal(Object.hasOwn(requests[0].headers, "authorization"), false);
});

test("emulator mode rejects remote hosts, another project, and service credentials", () => {
  const options = {
    projectId: "demo-universal-search",
    emulator: { host: "127.0.0.1", port: 18087 },
  };
  assert.throws(
    () =>
      createFirebaseFirestoreRestStore({
        ...options,
        emulator: { host: "firestore.googleapis.com", port: 18087 },
      }),
    { code: "invalid-request" },
  );
  assert.throws(
    () =>
      createFirebaseFirestoreRestStore({ ...options, projectId: PROJECT_ID }),
    { code: "invalid-request" },
  );
  assert.throws(
    () =>
      createFirebaseFirestoreRestStore({
        ...options,
        serviceAccountJson: '{"private_key":"must-not-be-used"}',
      }),
    { code: "invalid-request" },
  );
  assert.throws(
    () =>
      createFirebaseFirestoreRestStore({
        ...options,
        getAccessToken: async () => "credential-not-allowed",
      }),
    { code: "invalid-request" },
  );
});

test("outbox claim is encoded as one update inside the REST Firestore transaction", async () => {
  const requests = [];
  const operationId = "00000000-0000-4000-8000-000000000001";
  const now = Date.parse("2026-10-20T12:00:00Z");
  const fields = {
    schemaVersion: { integerValue: "2" },
    operationId: { stringValue: operationId },
    entityType: { stringValue: "establishment" },
    entityId: { stringValue: "modelo-legacy-01" },
    authorUid: { stringValue: "admin-user" },
    version: { integerValue: "4" },
    operation: { stringValue: "reconcile" },
    state: { stringValue: "pending" },
    attemptCount: { integerValue: "0" },
    workerId: { nullValue: null },
    leaseToken: { nullValue: null },
    leaseExpiresAt: { nullValue: null },
    nextAttemptAt: { nullValue: null },
    lastErrorCode: { nullValue: null },
    syncedAt: { nullValue: null },
    createdAt: { timestampValue: new Date(now).toISOString() },
    updatedAt: { timestampValue: new Date(now).toISOString() },
  };
  const store = createFirebaseFirestoreRestStore({
    projectId: PROJECT_ID,
    getAccessToken: async () => TOKEN,
    now: () => now,
    fetchImpl: async (url, init) => {
      const target = String(url);
      requests.push({ target, init });
      if (target.endsWith(":beginTransaction")) {
        return jsonResponse({ transaction: "claim-transaction" });
      }
      if (target.endsWith(":runQuery")) {
        return transactionReadResponse(
          transactionReadName(init),
          fields,
          "2026-10-20T11:59:00Z",
        );
      }
      if (target.endsWith(":commit")) {
        return jsonResponse({ commitTime: new Date(now).toISOString() });
      }
      if (target.endsWith(":rollback")) return jsonResponse({});
      throw new Error("unexpected request");
    },
  });
  const outbox = createFirebaseFirestoreOutboxAdapter({
    store,
    serverIdentity: { workerId: "worker-rest" },
    now: () => now,
    leaseDurationMs: 10_000,
  });
  const result = await outbox.claim(operationId, {
    workerId: "worker-rest",
    leaseToken: "lease-token-rest-00001",
    expectedState: "pending",
    expectedVersion: 4,
    now,
    leaseExpiresAt: now + 10_000,
  });
  assert.deepEqual(result, { claimed: true });
  const commitCall = requests.find(({ target }) => target.endsWith(":commit"));
  const commit = JSON.parse(commitCall.init.body);
  assert.equal(commit.transaction, "claim-transaction");
  assert.equal(commit.writes.length, 1);
  assert.deepEqual(commit.writes[0].currentDocument, {
    updateTime: "2026-10-20T11:59:00Z",
  });
  assert.deepEqual(commit.writes[0].updateTransforms, [
    { fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME" },
  ]);
  assert.deepEqual(commit.writes[0].update.fields.leaseToken, {
    stringValue: "lease-token-rest-00001",
  });
  assert.ok(commit.writes[0].updateMask.fieldPaths.includes("attemptCount"));
  assert.ok(requests.some(({ target, init }) =>
    target.endsWith(":runQuery") &&
    transactionReadName(init).endsWith(`/catalog_outbox/${operationId}`)
  ));
});
