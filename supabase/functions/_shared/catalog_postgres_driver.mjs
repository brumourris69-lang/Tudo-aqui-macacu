import { createSupabaseCatalogPostgresRpcClient } from "./catalog_postgres_writer_v2.mjs";

const WRITER_LOGIN = "catalog_writer_v2_login";
const JSONB_OID = 3_802;
const MAX_TIMEOUT_MS = 30_000;
const MAX_JSON_PAYLOAD_BYTES = 512 * 1_024;
const ALLOWED_SQL = new Set([
  "select public.apply_establishment_projection_v2($1::jsonb) as result",
  "select public.apply_establishment_tombstone_v2($1::jsonb) as result",
]);

export class SupabaseCatalogPostgresDriverError extends Error {
  constructor(code = "unavailable") {
    const safeCode = ["invalid_connection", "unavailable"].includes(code)
      ? code
      : "unavailable";
    super(
      safeCode === "invalid_connection"
        ? "Catalog database configuration is invalid."
        : "Catalog database is unavailable.",
    );
    this.name = "SupabaseCatalogPostgresDriverError";
    this.code = safeCode;
  }
}

/**
 * Creates the concrete PostgreSQL RPC transport while keeping the Deno/npm
 * driver injectable for tests. Only the two existing V2 RPC statements can
 * reach the driver; values remain bound as JSONB parameters.
 * @param {{connectionUrl: string, mode: "local" | "hosted", projectRef?: string, postgresFactory: (connectionUrl: string, options: Record<string, unknown>) => {unsafe: Function, typed: Function, end: Function}, timeoutMs?: number}} options
 */
export function createCatalogPostgresRpcDriver({
  connectionUrl,
  mode,
  projectRef,
  postgresFactory,
  timeoutMs = 5_000,
}) {
  const parsed = validateConnection(connectionUrl, mode, projectRef);
  if (
    !parsed || typeof postgresFactory !== "function" || !validTimeout(timeoutMs)
  ) {
    throw new SupabaseCatalogPostgresDriverError("invalid_connection");
  }

  const options = Object.freeze({
    max: 1,
    idle_timeout: 5,
    connect_timeout: 5,
    max_lifetime: 300,
    prepare: false,
    fetch_types: false,
    debug: false,
    onnotice: false,
    ssl: mode === "hosted"
      ? Object.freeze({ rejectUnauthorized: true })
      : false,
    connection: Object.freeze({
      application_name: "macacu-catalog-outbox-consumer",
      statement_timeout: timeoutMs,
      lock_timeout: Math.min(timeoutMs, 2_000),
      idle_in_transaction_session_timeout: timeoutMs,
    }),
  });

  let client;
  try {
    client = postgresFactory(connectionUrl, options);
  } catch {
    throw new SupabaseCatalogPostgresDriverError();
  }
  if (
    !client || typeof client.unsafe !== "function" ||
    typeof client.typed !== "function" ||
    typeof client.end !== "function"
  ) {
    try {
      void client?.end?.({ timeout: 1 });
    } catch {
      // Configuration is rejected without logging driver details.
    }
    throw new SupabaseCatalogPostgresDriverError();
  }

  const query = async ({ sql, parameters, timeoutMs: requestTimeoutMs }) => {
    if (
      !ALLOWED_SQL.has(sql) ||
      !Array.isArray(parameters) || parameters.length !== 1 ||
      typeof parameters[0] !== "string" ||
      new TextEncoder().encode(parameters[0]).byteLength >
        MAX_JSON_PAYLOAD_BYTES ||
      requestTimeoutMs !== timeoutMs
    ) {
      throw Object.assign(new Error("invalid database query"), {
        code: "22023",
      });
    }

    let driverQuery;
    try {
      const payload = JSON.parse(parameters[0]);
      if (
        payload === null || typeof payload !== "object" ||
        Array.isArray(payload)
      ) {
        throw Object.assign(new Error("invalid database payload"), {
          code: "22023",
        });
      }
      // postgres.js discovers parameter OIDs through Describe. An untyped
      // JSON string is then serialized again as JSON for the discovered JSONB
      // OID, turning the object into a JSON string scalar. Supply a typed JSONB
      // value so the driver serializes the object exactly once.
      driverQuery = client.unsafe(sql, [client.typed(payload, JSONB_OID)], {
        prepare: false,
        simple: false,
      });
      const pending = Promise.resolve(driverQuery);
      // A query may reject after the deadline/cancel race; observe that rejection.
      pending.catch(() => {});
      const rows = await Promise.race([
        pending,
        new Promise((_, reject) => {
          const timer = setTimeout(() => {
            try {
              void driverQuery?.cancel?.();
            } catch {
              // Server-side statement_timeout remains the independent bound.
            }
            reject(
              Object.assign(new Error("query timeout"), { code: "57014" }),
            );
          }, requestTimeoutMs);
          pending.finally(() => clearTimeout(timer)).catch(() => {});
        }),
      ]);
      if (
        !Array.isArray(rows) || rows.length !== 1 ||
        !Object.hasOwn(rows[0] ?? {}, "result")
      ) {
        throw Object.assign(new Error("invalid query result"), {
          code: "08006",
        });
      }
      return { rows: [{ result: rows[0].result }] };
    } catch (error) {
      const code =
        typeof error?.code === "string" && /^[0-9A-Z]{5}$/u.test(error.code)
          ? error.code
          : "08006";
      throw Object.assign(new Error("catalog database operation failed"), {
        code,
      });
    }
  };

  const rpc = createSupabaseCatalogPostgresRpcClient({ query, timeoutMs });
  let closed = false;
  return Object.freeze({
    rpc,
    async close() {
      if (closed) return;
      closed = true;
      try {
        await client.end({ timeout: 3 });
      } catch {
        throw new SupabaseCatalogPostgresDriverError();
      }
    },
  });
}

function validTimeout(value) {
  return Number.isSafeInteger(value) && value >= 100 && value <= MAX_TIMEOUT_MS;
}

function validateConnection(value, mode, projectRef) {
  if (
    typeof value !== "string" || value.length > 4_096 ||
    !["local", "hosted"].includes(mode)
  ) return null;
  try {
    const url = new URL(value);
    if (
      !["postgres:", "postgresql:"].includes(url.protocol) || !url.password ||
      !url.port ||
      url.pathname !== "/postgres" || url.search || url.hash
    ) return null;
    const username = decodeURIComponent(url.username);
    if (decodeURIComponent(url.password).length < 16) return null;
    if (mode === "local") {
      if (
        username !== WRITER_LOGIN ||
        !["127.0.0.1", "[::1]"].includes(url.hostname)
      ) return null;
    } else if (
      typeof projectRef !== "string" || !/^[a-z0-9]{20}$/u.test(projectRef) ||
      username !== `${WRITER_LOGIN}.${projectRef}` ||
      !url.hostname.endsWith(".pooler.supabase.com") || url.port !== "6543"
    ) {
      return null;
    }
    return url;
  } catch {
    return null;
  }
}
