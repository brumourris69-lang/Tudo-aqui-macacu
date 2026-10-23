const RPCS = new Map([
  ["apply_establishment_projection_v2", {
    argument: "p_projection",
    sql: "select public.apply_establishment_projection_v2($1::jsonb) as result",
  }],
  ["apply_establishment_tombstone_v2", {
    argument: "p_tombstone",
    sql: "select public.apply_establishment_tombstone_v2($1::jsonb) as result",
  }],
]);
const MAX_TIMEOUT_MS = 30_000;

export class SupabaseCatalogPostgresError extends Error {
  constructor(code = "catalog_unavailable") {
    const safeCode =
      ["catalog_unavailable", "catalog_conflict", "permanent_failure"].includes(
          code,
        )
        ? code
        : "catalog_unavailable";
    super(
      safeCode === "catalog_conflict"
        ? "Catalog operation conflicts with persisted state."
        : safeCode === "permanent_failure"
        ? "Catalog rejected the projection."
        : "Catalog is unavailable.",
    );
    this.name = "SupabaseCatalogPostgresError";
    this.code = safeCode;
  }
}

/**
 * Creates the Postgres-backed `rpc(name, args)` contract consumed by the
 * existing V2 writer and processor. The injected query adapter must bind
 * parameters, enforce `timeoutMs`, use TLS, disable prepared statements when
 * connected through a transaction pooler, and expose only one query result.
 * No Postgres driver or connection string is imported or retained here.
 *
 * @param {{query: (request: {sql: string, parameters: string[], timeoutMs: number}) => Promise<{rows: Array<{result: unknown}>}>, timeoutMs?: number}} options
 */
export function createSupabaseCatalogPostgresRpcClient(
  { query, timeoutMs = 10_000 },
) {
  if (
    typeof query !== "function" || !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < 100 || timeoutMs > MAX_TIMEOUT_MS
  ) {
    throw new SupabaseCatalogPostgresError("permanent_failure");
  }

  return async function rpc(name, args) {
    const spec = RPCS.get(name);
    if (
      !spec || !plainObject(args) || Object.keys(args).length !== 1 ||
      !Object.hasOwn(args, spec.argument) || !plainObject(args[spec.argument])
    ) {
      throw new SupabaseCatalogPostgresError("permanent_failure");
    }

    let payload;
    try {
      payload = JSON.stringify(args[spec.argument]);
    } catch {
      throw new SupabaseCatalogPostgresError("permanent_failure");
    }
    if (typeof payload !== "string") {
      throw new SupabaseCatalogPostgresError("permanent_failure");
    }

    let response;
    try {
      response = await query({
        sql: spec.sql,
        parameters: [payload],
        timeoutMs,
      });
    } catch (error) {
      throw mapPostgresError(error);
    }

    if (
      !response || !Array.isArray(response.rows) ||
      response.rows.length !== 1 ||
      !plainObject(response.rows[0]) ||
      !Object.hasOwn(response.rows[0], "result")
    ) {
      throw new SupabaseCatalogPostgresError();
    }
    return Object.freeze({ data: response.rows[0].result });
  };
}

function mapPostgresError(error) {
  if (error?.code === "23514") {
    return new SupabaseCatalogPostgresError("catalog_conflict");
  }
  if (error?.code === "22023") {
    return new SupabaseCatalogPostgresError("permanent_failure");
  }
  return new SupabaseCatalogPostgresError();
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype ||
      Object.getPrototypeOf(value) === null);
}
