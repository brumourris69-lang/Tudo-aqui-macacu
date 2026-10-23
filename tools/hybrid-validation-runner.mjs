#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { basename, dirname, isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const defaultTimeoutMs = 20 * 60 * 1_000;

export function sanitizeTestEnvironment(source) {
  const safe = {};
  for (const [name, value] of Object.entries(source)) {
    if (/(?:TOKEN|SECRET|PASSWORD|PASSWD|API[_-]?KEY|CREDENTIAL|SERVICE[_-]?ACCOUNT|PRIVATE[_-]?KEY|NODE_OPTIONS|NODE_PATH)/iu.test(name)) {
      continue;
    }
    if (/(?:^|_)(?:FIREBASE|FIRESTORE|SUPABASE|CATALOG_|GOOGLE_APPLICATION|AWS_|AZURE_|GCP_)/iu.test(name)) {
      continue;
    }
    safe[name] = value;
  }
  return safe;
}

export function validateIntegrationEnvironment(source) {
  const host = source.FIRESTORE_EMULATOR_HOST;
  const container = source.CATALOG_POSTGRES_TEST_CONTAINER;
  if (host !== '127.0.0.1:18087' ||
      typeof container !== 'string' || !/^macacu-0755-pg-[a-z0-9-]+$/u.test(container)) {
    throw integrationPreflightError();
  }

  const env = {
    FIRESTORE_EMULATOR_HOST: host,
    CATALOG_POSTGRES_TEST_CONTAINER: container,
  };
  const restValues = [source.CATALOG_POSTGREST_URL, source.CATALOG_POSTGREST_API_KEY,
    source.CATALOG_POSTGREST_TEST_CONTAINER];
  const hasRestValue = restValues.some((value) => value !== undefined);
  if (hasRestValue) {
    const [urlText, apiKey, restContainer] = restValues;
    let url;
    try {
      url = new URL(urlText);
    } catch {
      throw integrationPreflightError();
    }
    if (url.protocol !== 'http:' || !['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname) ||
        url.port !== '25432' || url.username || url.password || url.pathname !== '/' ||
        url.search || url.hash || typeof apiKey !== 'string' || apiKey.length < 32 ||
        typeof restContainer !== 'string' || !/^macacu-0755-rest-[a-z0-9-]+$/u.test(restContainer)) {
      throw integrationPreflightError();
    }
    env.CATALOG_POSTGREST_URL = url.toString();
    env.CATALOG_POSTGREST_API_KEY = apiKey;
    env.CATALOG_POSTGREST_TEST_CONTAINER = restContainer;
  }
  return env;
}

export function validateDenoExecutable(value) {
  if (typeof value !== 'string' || !isAbsolute(value) || !/^deno(?:\.exe)?$/iu.test(basename(value))) {
    throw Object.assign(new Error('Deno binary must be an absolute path to a deno executable.'), {
      code: 'deno-preflight-failed',
    });
  }
  return resolve(value);
}

export function buildValidationPlan({ root: projectRoot = root, includeLocalIntegration = false,
  includeEdgeRuntimeProbe = false, denoExecutable, env = {} } = {}) {
  const functionTests = filesUnder(resolve(projectRoot, 'functions/test'), /\.test\.js$/u)
    .map((file) => relativeTo(projectRoot, file));
  const sharedTests = filesUnder(resolve(projectRoot, 'supabase/functions/_shared'), /\.test\.mjs$/u)
    .map((file) => relativeTo(projectRoot, file));
  const scriptTests = filesUnder(resolve(projectRoot, 'scripts/test'), /\.test\.cjs$/u)
    .map((file) => relativeTo(projectRoot, file));
  const checkFiles = [
    'index.js', 'admin_job_management.js', 'home_image_upload.js', 'business_search.js',
    'business_search_firestore.js', 'business_search_functions.js',
    'integration/events_search_emulator.js', 'integration/jobs_search_emulator.js',
    'integration/admin_job_management_emulator.js',
  ].map((file) => `functions/${file}`);

  const plan = [
    nodeStep('functions-tests', ['--test', ...functionTests], projectRoot),
    nodeStep('functions-syntax', checkFiles.flatMap((file) => ['--check', file]), projectRoot),
    nodeStep('script-tests', ['--test', ...scriptTests], projectRoot),
    nodeStep('orchestrator-harness-tests', ['--test',
      'tools/hybrid-validation-runner.test.mjs', 'tools/edge-runtime-consumer-probe.test.mjs'], projectRoot),
    nodeStep('supabase-shared-tests', ['--test', ...sharedTests], projectRoot),
    pythonStep('python-regression-tests', ['-m', 'unittest', 'discover', '-s', 'scripts/test', '-p', '*_test.py'], projectRoot),
    pythonStep('android-static-check', ['scripts/android_release.py', '--static'], projectRoot),
    flutterStep('flutter-analyze', ['analyze', '--no-pub'], projectRoot),
    flutterStep('flutter-standard-tests', ['test', '--no-pub', '--exclude-tags', 'search-local'], projectRoot),
    flutterStep('flutter-search-local-tests', [
      'test', '--no-pub', '--dart-define=LOCAL_SEARCH_EMULATORS=true',
      '--dart-define=LOCAL_SEARCH_PROJECT=demo-universal-search',
      '--dart-define=LOCAL_SEARCH_HOST=127.0.0.1',
      'test/local_native_gate_test.dart', 'test/local_network_isolation_test.dart',
      'test/local_universal_search_test.dart', 'test/public_content_test.dart',
      'test/user_operations_test.dart', 'test/app_check_preparation_test.dart',
      'test/local_session_recovery_test.dart',
    ], projectRoot),
    flutterStep('flutter-app-check-tests', [
      'test', '--no-pub', '--dart-define=LOCAL_SEARCH_EMULATORS=true',
      '--dart-define=LOCAL_SEARCH_APP_CHECK=true', '--dart-define=LOCAL_SEARCH_HOST=127.0.0.1',
      'test/app_check_preparation_test.dart',
    ], projectRoot),
    { name: 'git-diff-check', executable: 'git', args: ['diff', '--check'], cwd: projectRoot,
      timeoutMs: defaultTimeoutMs, env: {} },
  ];

  if (denoExecutable) {
    const executable = validateDenoExecutable(denoExecutable);
    plan.splice(plan.length - 1, 0,
      { name: 'deno-edge-typecheck', executable,
        args: ['check', '--cached-only', 'supabase/functions/consume-catalog-outbox/index.ts'],
        cwd: projectRoot, timeoutMs: defaultTimeoutMs, env: {} },
      { name: 'deno-edge-handler-tests', executable,
        args: ['test', '--cached-only', 'supabase/functions/_shared/catalog_outbox_consumer.deno.test.ts'],
        cwd: projectRoot, timeoutMs: defaultTimeoutMs, env: {} });
    plan.splice(plan.length - 1, 0, { name: 'deno-handler-format', executable,
      args: ['fmt', '--check', 'supabase/functions/_shared/catalog_outbox_consumer.deno.test.ts'],
      cwd: projectRoot, timeoutMs: defaultTimeoutMs, env: {} });
  }
  if (includeLocalIntegration) {
    plan.splice(plan.length - 1, 0, nodeStep('firestore-postgres-integration', [
      '--test', 'supabase/functions/_shared/catalog_outbox_postgres.integration.test.mjs',
    ], projectRoot, {
      ...env,
    }));
  }
  if (includeEdgeRuntimeProbe) {
    plan.splice(plan.length - 1, 0, nodeStep('supabase-edge-runtime-probe', [
      'tools/edge-runtime-consumer-probe.mjs',
    ], projectRoot));
  }
  return plan;
}

export function sanitizeOutput(output) {
  return String(output)
    .replace(/\bBearer\s+[^\s,;]+/giu, 'Bearer [redacted]')
    .replace(/\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\b/gu, '[redacted-jwt]')
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/gu, '[redacted-email]')
    .replace(/((?:token|secret|password|api[_-]?key|credential)\s*[=:]\s*)[^\s,;]+/giu, '$1[redacted]');
}

export function parseTestSummary(output) {
  const text = String(output);
  const tap = Object.fromEntries(['tests', 'pass', 'fail', 'skipped'].map((key) => {
    const match = new RegExp(`^\\s*[ℹi]\\s+${key}\\s+(\\d+)\\s*$`, 'mu').exec(text);
    return [key, match ? Number(match[1]) : null];
  }));
  if (tap.tests !== null) {
    return { tests: tap.tests, passed: tap.pass ?? 0, failed: tap.fail ?? 0, skipped: tap.skipped ?? 0 };
  }
  const deno = /^ok\s*\|\s*(\d+)\s+passed\s*\|\s*(\d+)\s+failed(?:\s*\|\s*(\d+)\s+ignored)?/mu.exec(text);
  if (deno) {
    const passed = Number(deno[1]);
    const failed = Number(deno[2]);
    const skipped = Number(deno[3] ?? 0);
    return { tests: passed + failed + skipped, passed, failed, skipped };
  }
  const flutter = /\+(\d+): All tests passed!/u.exec(text);
  if (flutter) {
    const count = Number(flutter[1]);
    return { tests: count, passed: count, failed: 0, skipped: null };
  }
  return null;
}

async function main(args) {
  const includeLocalIntegration = args.includes('--include-local-integration');
  const includeEdgeRuntimeProbe = args.includes('--edge-runtime-probe');
  let denoExecutable;
  const unknown = [];
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === '--deno-bin') {
      if (typeof args[index + 1] !== 'string') throw Object.assign(new Error('Missing Deno binary path.'), { code: 'deno-preflight-failed' });
      denoExecutable = validateDenoExecutable(args[index + 1]);
      index += 1;
    } else if (!['--include-local-integration', '--edge-runtime-probe', '--help'].includes(args[index])) {
      unknown.push(args[index]);
    }
  }
  if (unknown.length > 0) throw new Error('Unsupported validation-runner argument.');
  if (args.includes('--help')) {
    process.stdout.write('Usage: node tools/hybrid-validation-runner.mjs [--deno-bin <absolute-path>] [--include-local-integration] [--edge-runtime-probe]\n');
    process.stdout.write('The optional Firestore/PostgreSQL integration requires already-running labeled local services. --edge-runtime-probe creates and removes one isolated container, but requires Docker and the pinned image to be available.\n');
    return 0;
  }

  let integrationEnv = {};
  if (includeLocalIntegration) integrationEnv = validateIntegrationEnvironment(process.env);
  const plan = buildValidationPlan({ root, includeLocalIntegration, includeEdgeRuntimeProbe, denoExecutable, env: integrationEnv });
  const baseEnv = sanitizeTestEnvironment(process.env);
  const results = [];
  const runStartedAt = new Date().toISOString();
  process.stdout.write(`Hybrid validation: ${plan.length} stages; external services are not started.\n`);
  for (const step of plan) {
    process.stdout.write(`RUN ${step.name}\n`);
    const startedAt = Date.now();
    const childResult = await runStep(step, { ...baseEnv, ...step.env });
    const outputSummary = parseTestSummary(childResult.stdout);
    const result = { name: step.name, status: childResult.code === 0 ? 'passed' :
      childResult.code === 130 ? 'interrupted' : 'failed',
      exitCode: childResult.code, durationMs: Date.now() - startedAt,
      ...(outputSummary ? { testSummary: outputSummary } : {}) };
    results.push(result);
    process.stdout.write(`${result.status === 'passed' ? 'PASS' : 'FAIL'} ${step.name} (${(result.durationMs / 1_000).toFixed(1)}s)\n`);
    if (childResult.code !== 0) {
      const detail = sanitizeOutput(`${childResult.stdout}\n${childResult.stderr}`).trim().split(/\r?\n/u).slice(-18).join('\n');
      if (detail) process.stdout.write(`Sanitized failure tail:\n${detail}\n`);
      break;
    }
  }
  const report = { status: results.some((result) => result.status === 'interrupted') ? 'interrupted' :
    results.every((result) => result.status === 'passed') && results.length === plan.length
      ? 'passed' : 'failed', startedAt: runStartedAt,
    steps: results };
  process.stdout.write(`REPORT ${JSON.stringify(report)}\n`);
  return report.status === 'passed' ? 0 : report.status === 'interrupted' ? 130 : 1;
}

function nodeStep(name, args, cwd, env = {}) {
  return { name, executable: process.execPath, args, cwd, timeoutMs: defaultTimeoutMs, env };
}

function pythonStep(name, args, cwd) {
  return { name, executable: 'python', args, cwd, timeoutMs: defaultTimeoutMs, env: {} };
}

function flutterStep(name, args, cwd) {
  return { name, executable: 'flutter', args, cwd, timeoutMs: defaultTimeoutMs, env: {} };
}

function filesUnder(directory, pattern) {
  try {
    return readdirSync(directory, { withFileTypes: true })
      .filter((entry) => entry.isFile() && pattern.test(entry.name))
      .map((entry) => resolve(directory, entry.name)).sort();
  } catch {
    return [];
  }
}

function relativeTo(projectRoot, file) {
  return file.slice(projectRoot.length + 1).replaceAll('\\', '/');
}

function integrationPreflightError() {
  return Object.assign(new Error('Local integration preflight rejected; no commands were started.'), {
    code: 'integration-preflight-failed',
  });
}

function runStep(step, env) {
  return new Promise((resolvePromise) => {
    const windowsCommand = process.platform === 'win32' && ['git', 'python', 'flutter'].includes(step.executable);
    const executable = windowsCommand ? (process.env.ComSpec || 'cmd.exe') : step.executable;
    const args = windowsCommand
      ? ['/d', '/s', '/c', `${step.executable} ${step.args.join(' ')}`]
      : step.args;
    const child = spawn(executable, args, { cwd: step.cwd, env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let settled = false;
    let terminationReason = null;
    const onInterrupt = () => {
      if (settled || terminationReason) return;
      terminationReason = 'interrupted';
      stopChildTree(child).then(() => finish({ code: 130, stdout, stderr: `${stderr}\nInterrupted by user.` }));
    };
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      process.removeListener('SIGINT', onInterrupt);
      resolvePromise(result);
    };
    const timer = setTimeout(() => {
      if (settled || terminationReason) return;
      terminationReason = 'timeout';
      stopChildTree(child).then(() => finish({ code: 124, stdout, stderr: `${stderr}\nRunner timeout.` }));
    }, step.timeoutMs);
    process.once('SIGINT', onInterrupt);
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.once('error', (error) => finish({ code: 127, stdout, stderr: `Could not start validation command (${error.code ?? 'unknown'}).` }));
    child.once('close', (code) => finish({
      code: terminationReason === 'timeout' ? 124 : terminationReason === 'interrupted' ? 130 : code ?? 1,
      stdout,
      stderr,
    }));
  });
}

function stopChildTree(child) {
  if (child.exitCode !== null || !Number.isInteger(child.pid)) return Promise.resolve();
  if (process.platform !== 'win32') {
    child.kill('SIGTERM');
    return Promise.resolve();
  }
  return new Promise((resolvePromise) => {
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      clearTimeout(fallback);
      child.kill();
      resolvePromise();
    };
    const fallback = setTimeout(finish, 4_000);
    const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], {
      windowsHide: true, stdio: 'ignore',
    });
    killer.once('error', finish);
    killer.once('close', finish);
  });
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; }).catch((error) => {
    process.stderr.write(`Validation runner stopped safely (${error.code ?? 'configuration-error'}): ${error.message}\n`);
    process.exitCode = 2;
  });
}
