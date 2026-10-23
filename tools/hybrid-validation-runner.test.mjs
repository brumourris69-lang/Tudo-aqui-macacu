import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildValidationPlan,
  parseTestSummary,
  sanitizeTestEnvironment,
  validateDenoExecutable,
  validateIntegrationEnvironment,
} from './hybrid-validation-runner.mjs';

test('default plan contains only local checks and never starts services or deployment', () => {
  const plan = buildValidationPlan({ root: 'C:/repo' });
  const labels = plan.map((step) => step.name);

  assert.deepEqual(labels, [
    'functions-tests',
    'functions-syntax',
    'script-tests',
    'orchestrator-harness-tests',
    'supabase-shared-tests',
    'python-regression-tests',
    'android-static-check',
    'flutter-analyze',
    'flutter-standard-tests',
    'flutter-search-local-tests',
    'flutter-app-check-tests',
    'git-diff-check',
  ]);
  assert.equal(plan.some((step) => /deploy|emulators:start|docker run|supabase start/iu.test(
    `${step.executable} ${step.args.join(' ')}`)), false);
});

test('runner executes its own safety tests as a normal offline stage', () => {
  const plan = buildValidationPlan({ root: 'C:/repo' });
  const step = plan.find((item) => item.name === 'orchestrator-harness-tests');

  assert.ok(step);
  assert.equal(step.executable, process.execPath);
  assert.deepEqual(step.args, ['--test', 'tools/hybrid-validation-runner.test.mjs',
    'tools/edge-runtime-consumer-probe.test.mjs']);
});

test('Edge Runtime probe is opt-in and stays isolated in its own helper', () => {
  const defaultPlan = buildValidationPlan({ root: 'C:/repo' });
  assert.equal(defaultPlan.some((step) => step.name === 'supabase-edge-runtime-probe'), false);
  const optedIn = buildValidationPlan({ root: 'C:/repo', includeEdgeRuntimeProbe: true });
  const step = optedIn.find((item) => item.name === 'supabase-edge-runtime-probe');
  assert.deepEqual(step.args, ['tools/edge-runtime-consumer-probe.mjs']);
  assert.equal(step.executable, process.execPath);
});

test('integration is opt-in and only receives explicit loopback emulator settings', () => {
  const plan = buildValidationPlan({ root: 'C:/repo', includeLocalIntegration: true, env: {
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:18087',
    CATALOG_POSTGRES_TEST_CONTAINER: 'macacu-0755-pg-localvalidation',
  } });
  const integration = plan.find((step) => step.name === 'firestore-postgres-integration');
  assert.equal(plan.at(-2).name, 'firestore-postgres-integration');
  assert.deepEqual(integration.env, {
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:18087',
    CATALOG_POSTGRES_TEST_CONTAINER: 'macacu-0755-pg-localvalidation',
  });
});

test('test child environment strips credentials and hosted endpoint variables', () => {
  const safe = sanitizeTestEnvironment({
    PATH: 'safe-path',
    SystemRoot: 'C:/Windows',
    FIREBASE_SERVICE_ACCOUNT_JSON: 'private',
    GOOGLE_APPLICATION_CREDENTIALS: 'private-file',
    SUPABASE_SERVICE_ROLE_KEY: 'private',
    CATALOG_POSTGREST_API_KEY: 'synthetic-local-key',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:18087',
    RANDOM_ACCESS_TOKEN: 'private',
    NODE_OPTIONS: '--require C:/private-hook.js',
  });

  assert.deepEqual(safe, { PATH: 'safe-path', SystemRoot: 'C:/Windows' });
});

test('integration preflight rejects remote endpoints, missing values, and non-disposable containers', () => {
  assert.throws(() => validateIntegrationEnvironment({}), { code: 'integration-preflight-failed' });
  assert.throws(() => validateIntegrationEnvironment({
    FIRESTORE_EMULATOR_HOST: 'firestore.googleapis.com:8087',
    CATALOG_POSTGRES_TEST_CONTAINER: 'production-db',
  }), { code: 'integration-preflight-failed' });
  assert.deepEqual(validateIntegrationEnvironment({
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:18087',
    CATALOG_POSTGRES_TEST_CONTAINER: 'macacu-0755-pg-localvalidation',
  }), {
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:18087',
    CATALOG_POSTGRES_TEST_CONTAINER: 'macacu-0755-pg-localvalidation',
  });
});

test('failure output redacts bearer tokens, JWTs, and email addresses', async () => {
  const { sanitizeOutput } = await import('./hybrid-validation-runner.mjs');
  const safe = sanitizeOutput('Bearer abc.def ghi eyJabcdefghijk.abcdefghijk.abcdefghijk user@example.invalid');
  assert.equal(safe.includes('abc.def'), false);
  assert.equal(safe.includes('abcdefghijk'), false);
  assert.equal(safe.includes('user@example.invalid'), false);
});

test('TAP summary keeps skipped integration tests visible instead of counting them as passes', () => {
  assert.deepEqual(parseTestSummary('ℹ tests 153\nℹ pass 151\nℹ fail 0\nℹ skipped 2'), {
    tests: 153, passed: 151, failed: 0, skipped: 2,
  });
});

test('Deno test summary counts runtime tests without hiding failures', () => {
  assert.deepEqual(parseTestSummary('ok | 2 passed | 0 failed (29ms)'), {
    tests: 2, passed: 2, failed: 0, skipped: 0,
  });
});

test('Deno Edge typecheck is opt-in and uses cached dependencies only', () => {
  const deno = validateDenoExecutable('C:/tools/deno.exe');
  const plan = buildValidationPlan({ root: 'C:/repo', denoExecutable: deno });
  const step = plan.find((item) => item.name === 'deno-edge-typecheck');
  assert.equal(step.executable.replaceAll('\\', '/'), 'C:/tools/deno.exe');
  assert.deepEqual(step.args, ['check', '--cached-only', 'supabase/functions/consume-catalog-outbox/index.ts']);
  assert.deepEqual(plan.find((item) => item.name === 'deno-edge-handler-tests').args,
    ['test', '--cached-only', 'supabase/functions/_shared/catalog_outbox_consumer.deno.test.ts']);
  assert.deepEqual(plan.find((item) => item.name === 'deno-handler-format').args,
    ['fmt', '--check', 'supabase/functions/_shared/catalog_outbox_consumer.deno.test.ts']);
  assert.throws(() => validateDenoExecutable('deno.exe'), { code: 'deno-preflight-failed' });
});
