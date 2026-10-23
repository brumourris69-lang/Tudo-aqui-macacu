import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const templateUrl = new URL('../../schedules/consume_catalog_outbox.sql.example', import.meta.url);
const entrypointUrl = new URL('../consume-catalog-outbox/index.ts', import.meta.url);
const configHelperUrl = new URL('./catalog_outbox_consumer_config.mjs', import.meta.url);
const configUrl = new URL('../../config.toml', import.meta.url);

test('scheduled consumer SQL is an inert, Vault-backed HMAC template with no privileged client key', async () => {
  const template = await readFile(templateUrl, 'utf8');
  const activeLines = template.split(/\r?\n/u).filter((line) => line.trim() && !line.trimStart().startsWith('--'));
  assert.deepEqual(activeLines, [], 'the example must not execute when passed to psql');
  assert.match(template, /MANUAL TEMPLATE ONLY/u);
  assert.match(template, /'\*\/10 \* \* \* \*'/u);
  assert.match(template, /1 event every 10 minutes/u);
  assert.match(template, /catalog_consumer_project_url/u);
  assert.match(template, /catalog_consumer_publishable_key/u);
  assert.match(template, /catalog_consumer_hmac_secret/u);
  assert.match(template, /\/functions\/v1\/consume-catalog-outbox/u);
  assert.match(template, /catalog-outbox-consumer-v1/u);
  assert.match(template, /x-catalog-run-signature/u);
  assert.match(template, /body\s*:=\s*'\{\}'::jsonb/iu);
  assert.match(template, /timeout_milliseconds\s*:=\s*140000/iu);
  assert.doesNotMatch(template, /service_role|SUPABASE_SERVICE_ROLE_KEY|FIREBASE_SERVICE_ACCOUNT_JSON/iu);
  assert.doesNotMatch(template, /vault\.create_secret\s*\(/iu,
    'real secret provisioning must stay outside a versioned SQL template');
});

test('hosted entrypoint stays fail-closed and bounds one run below the Free runtime ceiling', async () => {
  const entrypoint = await readFile(entrypointUrl, 'utf8');
  const configHelper = await readFile(configHelperUrl, 'utf8');
  const config = await readFile(configUrl, 'utf8');
  const denoConfig = JSON.parse(await readFile(new URL('../deno.json', entrypointUrl), 'utf8'));
  assert.match(configHelper, /env\.CATALOG_CONSUMER_ENABLED\s*!==\s*"true"/u);
  assert.match(entrypoint, /FIREBASE_SERVICE_ACCOUNT_JSON/u);
  assert.match(entrypoint, /FIREBASE_PROJECT_ID/u);
  assert.match(entrypoint, /resolveCatalogOutboxConsumerConfig/u);
  assert.doesNotMatch(entrypoint, /const projectId\s*=\s*["']tudo-aqui-macacu/u,
    'the consumer must not silently select the production project');
  assert.match(entrypoint, /SUPABASE_CATALOG_DATABASE_URL/u);
  assert.match(entrypoint, /createCatalogPostgresRpcDriver/u);
  assert.match(entrypoint, /import postgres from ["']postgres["']/u);
  assert.equal(denoConfig.imports.postgres, 'npm:postgres@3.4.7');
  assert.doesNotMatch(entrypoint, /SUPABASE_SERVICE_ROLE_KEY|createSupabaseCatalogRpcRestClient/u,
    'the consumer must not retain a service_role/PostgREST fallback');
  assert.match(entrypoint, /CATALOG_CONSUMER_HMAC_SECRET/u);
  assert.match(entrypoint, /requestTimeoutMs:\s*3_000/u);
  assert.match(entrypoint, /timeoutMs:\s*5_000/u);
  assert.match(entrypoint, /pageSize:\s*1/gu);
  assert.match(entrypoint, /leaseDurationMs:\s*120_000/u);
  assert.match(entrypoint, /scanPageSize:\s*25/u);
  assert.match(entrypoint, /maxScanPages:\s*4/u);
  assert.match(entrypoint, /createCatalogOutboxScanCheckpoint/u);
  assert.match(entrypoint, /createCatalogOutboxScanRunner/u);
  assert.match(entrypoint,
    /onMetric:\s*\(metric(?::\s*Record<string,\s*unknown>)?\)\s*=>\s*console\.log\(JSON\.stringify\(metric\)\)/u);
  assert.doesNotMatch(entrypoint, /serviceAccountJson\s*:\s*['"`]/u,
    'a service-account key must come from the server secret store');
  assert.match(config, /\[functions\.consume-catalog-outbox\]\s*\nverify_jwt\s*=\s*false/iu);
});
