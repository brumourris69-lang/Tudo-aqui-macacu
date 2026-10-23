import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const migration = readFileSync(
  new URL(
    "../../migrations/20261023000100_private_catalog_reconciliation_snapshot_v2.sql",
    import.meta.url,
  ),
  "utf8",
);
const tap = readFileSync(
  new URL(
    "../../tests/database/catalog_private_reconciliation_snapshot_v2.sql",
    import.meta.url,
  ),
  "utf8",
);

test("snapshot migration creates private bounded snapshot storage with expiry and deterministic keyset index", () => {
  assert.match(
    migration,
    /create table public\.catalog_reconciliation_snapshots_v2/i,
  );
  assert.match(
    migration,
    /create table public\.catalog_reconciliation_snapshot_rows_v2/i,
  );
  assert.match(migration, /expires_at timestamptz not null/i);
  assert.match(migration, /primary key\s*\(snapshot_id, entity_id\)/i);
  assert.match(
    migration,
    /catalog_reconciliation_snapshot_rows_v2_cursor_idx/i,
  );
  assert.match(migration, /collate "C"/i);
  assert.match(migration, /10_?000|10000/);
  assert.match(migration, /67108864/);
});

test("snapshot capture bounds each source read and every RPC has a fixed statement timeout", () => {
  assert.match(
    migration,
    /catalog_candidates as materialized\s*\([\s\S]*?from public\.public_establishment_catalog_v2 e[\s\S]*?limit 10001\s*\)/i,
  );
  assert.match(
    migration,
    /tombstone_candidates as materialized\s*\([\s\S]*?from public\.catalog_tombstones_v2 t[\s\S]*?limit 10001\s*\)/i,
  );
  assert.equal(
    (migration.match(/set statement_timeout = '30s'/gi) ?? []).length,
    3,
  );
  assert.match(
    migration,
    /public_establishment_catalog_v2_reconciliation_ids_idx/i,
  );
});

test("snapshot functions use explicit SECURITY DEFINER, postgres owner, empty search_path and fixed RPC surface", () => {
  for (
    const name of [
      "begin_catalog_reconciliation_snapshot_v2",
      "read_catalog_reconciliation_page_v2",
      "dispose_catalog_reconciliation_snapshot_v2",
    ]
  ) {
    const block = migration.match(
      new RegExp(
        `create or replace function public\\.${name}\\([\\s\\S]*?\\$function\\$;`,
        "i",
      ),
    )?.[0] ?? "";
    assert.match(block, /security definer/i, name);
    assert.match(block, /set search_path = ''/i, name);
    assert.match(
      migration,
      new RegExp(`alter function public\\.${name}\\(`, "i"),
    );
    assert.match(
      migration,
      new RegExp(`revoke all on function public\\.${name}\\(`, "i"),
    );
    assert.match(
      migration,
      new RegExp(
        `grant execute on function public\\.${name}\\(.*?to service_role`,
        "i",
      ),
    );
  }
  assert.doesNotMatch(
    migration,
    /grant\s+select\s+on\s+table\s+public\.catalog_reconciliation_snapshot/i,
  );
});

test("materialization explicitly excludes derived search and includes lifecycle metadata", () => {
  assert.match(migration, /'catalog_version'/i);
  assert.match(migration, /'outbox_operation_id'/i);
  assert.match(migration, /'published'/i);
  assert.match(migration, /'active'/i);
  assert.match(migration, /'expires_at'/i);
  assert.match(migration, /'deleted_at'/i);
  assert.match(migration, /'public_contact_approved'/i);
  assert.match(migration, /'tombstoned_at'/i);
  assert.doesNotMatch(migration, /'search_document'/i);
});

test("pgTAP has a self-consistent plan covering grants, visibility, snapshots, paging, expiry and disposal", () => {
  const plan = Number(tap.match(/select plan\((\d+)\)/i)?.[1]);
  const assertions = tap.match(
    /^select\s+(?:ok|is|isnt|throws_ok|lives_ok|has_function)\s*\(/gim,
  ) ?? [];
  assert.ok(Number.isInteger(plan) && plan > 20);
  assert.equal(assertions.length, plan);
  for (
    const phrase of [
      "service_role",
      "anon",
      "authenticated",
      "snapshot",
      "expired",
      "search_document",
      "unpublished",
      "tombstone",
      "cursor",
      "deterministic",
      "direct SELECT",
    ]
  ) assert.ok(tap.toLowerCase().includes(phrase.toLowerCase()), phrase);
});
