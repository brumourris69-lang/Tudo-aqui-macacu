import assert from "node:assert/strict";
import test from "node:test";
import {
  createCatalogPostgresRpcDriver,
  SupabaseCatalogPostgresDriverError,
} from "./catalog_postgres_driver.mjs";
import { SupabaseCatalogPostgresError } from "./catalog_postgres_writer_v2.mjs";

const localUrl = "postgres://catalog_writer_v2_login:synthetic-password@127.0.0.1:54329/postgres";
const hostedUrl = "postgres://catalog_writer_v2_login.pilotref123456789012:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres";

function fakeClient(query) {
  return {
    typed: (value, type) => ({ value, type }),
    unsafe: query,
    end: async () => {},
  };
}

test("local driver binds the writer allowlist query and sets bounded non-prepared connection options", async () => {
  const calls = [];
  let clientOptions;
  const driver = createCatalogPostgresRpcDriver({
    connectionUrl: localUrl,
    mode: "local",
    timeoutMs: 2_500,
    postgresFactory: (_url, options) => {
      clientOptions = options;
      return fakeClient(async (...args) => {
        calls.push(args);
        return [{ result: "applied" }];
      });
    },
  });

  assert.deepEqual(await driver.rpc("apply_establishment_projection_v2", {
    p_projection: { id: "modelo-fixture", catalog_version: 1 },
  }), { data: "applied" });
  assert.equal(clientOptions.max, 1);
  assert.equal(clientOptions.connect_timeout, 5);
  assert.equal(clientOptions.idle_timeout, 5);
  assert.equal(clientOptions.prepare, false);
  assert.equal(clientOptions.ssl, false);
  assert.equal(clientOptions.connection.statement_timeout, 2_500);
  assert.equal(clientOptions.connection.lock_timeout, 2_000);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "select public.apply_establishment_projection_v2($1::jsonb) as result");
  assert.deepEqual(calls[0][1], [{
    value: { id: "modelo-fixture", catalog_version: 1 },
    type: 3_802,
  }]);
  assert.deepEqual(calls[0][2], { prepare: false, simple: false });
  await driver.close();
});

test("hosted driver requires the dedicated transaction-pooler login and verifies TLS certificates", async () => {
  let clientOptions;
  let clientUrl;
  const driver = createCatalogPostgresRpcDriver({
    connectionUrl: hostedUrl,
    mode: "hosted",
    projectRef: "pilotref123456789012",
    postgresFactory: (url, options) => {
      clientUrl = url;
      clientOptions = options;
      return fakeClient(async () => [{ result: "applied" }]);
    },
  });
  assert.equal(clientUrl, hostedUrl);
  assert.equal(clientOptions.prepare, false);
  assert.deepEqual(clientOptions.ssl, { rejectUnauthorized: true });
  assert.equal(clientOptions.max, 1);
  assert.equal(clientOptions.connection.statement_timeout, 5_000);
  await driver.close();
});

test("driver rejects service_role, malformed URLs, and non-pooler hosted endpoints before connecting", () => {
  let calls = 0;
  const postgresFactory = () => {
    calls += 1;
    return fakeClient(async () => []);
  };
  for (const options of [
    { connectionUrl: "postgres://service_role:synthetic-password@127.0.0.1:54329/postgres", mode: "local" },
    { connectionUrl: "postgres://catalog_writer_v2_login:synthetic-password@db.remote.invalid:5432/postgres", mode: "local" },
    { connectionUrl: "postgres://catalog_writer_v2_login:x@127.0.0.1:54329/postgres", mode: "local" },
    { connectionUrl: "postgres://catalog_writer_v2_login:synthetic-password@127.0.0.1:54329/postgres?sslmode=disable", mode: "local" },
    { connectionUrl: "postgres://catalog_writer_v2_login:synthetic-password@aws-0-us-east-1.pooler.supabase.com:6543/postgres", mode: "hosted", projectRef: "pilotref1234567890" },
    { connectionUrl: hostedUrl, mode: "hosted", projectRef: "anotherproject123456" },
  ]) {
    assert.throws(() => createCatalogPostgresRpcDriver({ ...options, postgresFactory }), SupabaseCatalogPostgresDriverError);
  }
  assert.equal(calls, 0);
});

test("driver times out and requests cancellation without exposing driver error details", async () => {
  let cancelled = false;
  const driver = createCatalogPostgresRpcDriver({
    connectionUrl: localUrl,
    mode: "local",
    timeoutMs: 100,
    postgresFactory: () => fakeClient(() => {
      const pending = new Promise(() => {});
      pending.cancel = async () => { cancelled = true; };
      return pending;
    }),
  });

  await assert.rejects(driver.rpc("apply_establishment_projection_v2", {
    p_projection: { id: "modelo-fixture", catalog_version: 1 },
  }), (error) => {
    assert.ok(error instanceof SupabaseCatalogPostgresError);
    assert.equal(error.code, "catalog_unavailable");
    assert.doesNotMatch(error.message, /synthetic|password|postgres/i);
    return true;
  });
  assert.equal(cancelled, true);
  await driver.close();
});

test("driver does not expose arbitrary SQL and maps only fixed SQLSTATEs", async () => {
  const calls = [];
  const driver = createCatalogPostgresRpcDriver({
    connectionUrl: localUrl,
    mode: "local",
    postgresFactory: () => fakeClient(async (...args) => {
      calls.push(args);
      throw Object.assign(new Error("password=do-not-leak"), { code: "23514" });
    }),
  });
  await assert.rejects(driver.rpc("arbitrary_sql", { p_projection: {} }), SupabaseCatalogPostgresError);
  assert.equal(calls.length, 0);
  await assert.rejects(driver.rpc("apply_establishment_projection_v2", {
    p_projection: { id: "modelo-fixture", catalog_version: 1 },
  }), (error) => {
    assert.equal(error.code, "catalog_conflict");
    assert.doesNotMatch(error.message, /do-not-leak|password/i);
    return true;
  });
  assert.equal(calls.length, 1);
  await driver.close();
});

test("driver rejects an oversized projection before it reaches PostgreSQL", async () => {
  let calls = 0;
  const driver = createCatalogPostgresRpcDriver({
    connectionUrl: localUrl,
    mode: "local",
    postgresFactory: () => fakeClient(async () => {
      calls += 1;
      return [{ result: "applied" }];
    }),
  });
  await assert.rejects(driver.rpc("apply_establishment_projection_v2", {
    p_projection: { id: "modelo-fixture", description: "x".repeat(600_000) },
  }), SupabaseCatalogPostgresError);
  assert.equal(calls, 0);
  await driver.close();
});
