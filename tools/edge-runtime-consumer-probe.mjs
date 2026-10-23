#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { basename, join, resolve, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

export const EDGE_RUNTIME_IMAGE = 'public.ecr.aws/supabase/edge-runtime:v1.77.4';
const projectRoot = resolve(join(fileURLToPath(new URL('.', import.meta.url)), '..'));
const runtimeFunction = 'consume-catalog-outbox';
const timeoutMs = 35_000;

export function buildContainerCreateArgs({ tempRoot, containerName }) {
  const normalizedRoot = resolve(tempRoot).replaceAll('\\', '/');
  if (!/^[a-z0-9-]{1,100}$/u.test(containerName) ||
      !normalizedRoot.toLowerCase().startsWith(`${resolve(tmpdir()).toLowerCase().replaceAll('\\', '/')}/macacu-edge-runtime-probe-`)) {
    throw new Error('probe-preflight-failed');
  }
  return [
    'create', '--name', containerName,
    '--label', 'codex.task=macacu-edge-runtime-validation',
    '--network', 'none', '--read-only', '--user', '10001:10001',
    '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
    '--memory', '768m', '--cpus', '1', '--pids-limit', '64',
    '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=96m',
    '--mount', `type=bind,source=${normalizedRoot},target=/opt/runtime,readonly`,
    '--env', 'HOME=/tmp', '--env', 'DENO_DIR=/tmp/deno',
    EDGE_RUNTIME_IMAGE, 'start', '--main-service=/opt/runtime/main',
    '--ip=127.0.0.1', '--port=9000', '--policy=per_worker',
  ];
}

export function validateContainerIsolation(container) {
  const host = container?.HostConfig;
  const config = container?.Config;
  const mounts = container?.Mounts;
  const noBindings = Object.keys(host?.PortBindings ?? {}).length === 0 &&
    Object.keys(container?.NetworkSettings?.Ports ?? {}).length === 0;
  const safe = host?.NetworkMode === 'none' && noBindings && host?.ReadonlyRootfs === true &&
    config?.Image === EDGE_RUNTIME_IMAGE && config?.User === '10001:10001' &&
    host?.CapDrop?.includes('ALL') === true && host?.SecurityOpt?.includes('no-new-privileges:true') === true &&
    host?.Memory === 768 * 1024 * 1024 && host?.NanoCpus === 1_000_000_000 && host?.PidsLimit === 64 &&
    Array.isArray(mounts) && mounts.length === 1 && mounts[0]?.Destination === '/opt/runtime' && mounts[0]?.RW === false;
  return Object.freeze({ ok: safe });
}

export function cleanupProbeContainer(dockerCommand, containerName, created) {
  if (!created) return;
  if (typeof dockerCommand !== 'function' ||
      !/^macacu-edge-runtime-[0-9]+-[a-z0-9]+$/u.test(containerName)) {
    throw new Error('edge-runtime-container-cleanup-failed');
  }
  try {
    dockerCommand(['rm', '--force', containerName]);
  } catch {
    throw new Error('edge-runtime-container-cleanup-failed');
  }
}

export function parseRuntimeProbeOutput(output) {
  const line = String(output).split(/\r?\n/u).find((item) => item.startsWith('EDGE_RUNTIME_HTTP_RESULT '));
  if (!line) return null;
  try {
    const parsed = JSON.parse(line.slice('EDGE_RUNTIME_HTTP_RESULT '.length));
    const probe = parsed?.report;
    const statuses = probe?.results?.map((item) => item?.status);
    const expectedStatuses = [405, 503, 401, 401, 400, 200];
    if (parsed.status !== 200 || probe?.passed !== expectedStatuses.length || probe?.failed !== 0 ||
        JSON.stringify(statuses) !== JSON.stringify(expectedStatuses)) return null;
    return Object.freeze({ passed: expectedStatuses.length, failed: 0, statuses: Object.freeze(statuses) });
  } catch {
    return null;
  }
}

const mainSource = `const runtime = EdgeRuntime;
const functionPath = "/opt/runtime/functions/consume-catalog-outbox";
const probeFunctionPath = "/opt/runtime/functions/consumer-probe";
const probeSecret = "synthetic-edge-runtime-hmac-secret-0123456789";
const probeSeconds = 1_798_240_800;
const workerOptions = {
  servicePath: functionPath, memoryLimitMb: 192, workerTimeoutMs: 15000,
  noModuleCache: false, noNpm: true, envVars: [], forceCreate: false,
  customModuleRoot: "", cpuTimeSoftLimitMs: 1000, cpuTimeHardLimitMs: 2000,
  decoratorType: "tc39", maybeEntrypoint: "file://" + functionPath + "/index.ts",
  context: { useReadSyncFileAPI: true }, staticPatterns: [],
};
async function runProbe(tagSource) {
  const worker = await Promise.race([
    runtime.userWorkers.create(workerOptions),
    new Promise((_, reject) => setTimeout(() => reject(new Error("worker-timeout")), 20000)),
  ]);
  const results = [];
  for (const [name, method, status] of [
    ["consumer-rejects-non-post", "GET", 405],
    ["consumer-disabled-without-server-secrets", "POST", 503],
  ]) {
    const request = new Request("http://user-worker.local/consume", { method });
    runtime.applySupabaseTag(tagSource, request);
    const response = await worker.fetch(request);
    if (response.status !== status) throw new Error("unexpected-status:" + name);
    if (method === "POST" && (await response.json())?.error !== "consumer_unavailable") {
      throw new Error("unexpected-body:" + name);
    }
    results.push({ name, status: response.status });
  }
  const authenticatedWorker = await Promise.race([
    runtime.userWorkers.create({ ...workerOptions, servicePath: probeFunctionPath,
      maybeEntrypoint: "file://" + probeFunctionPath + "/index.ts" }),
    new Promise((_, reject) => setTimeout(() => reject(new Error("worker-timeout")), 20000)),
  ]);
  const send = async (signature, body) => {
    const headers = signature === null ? {} : { "x-catalog-run-signature": signature };
    const request = new Request("http://user-worker.local/consume", {
      method: "POST", headers, ...(body === undefined ? {} : { body }),
    });
    runtime.applySupabaseTag(tagSource, request);
    const response = await authenticatedWorker.fetch(request);
    const text = await response.text();
    return { status: response.status, text };
  };
  for (const [name, result, expectedStatus] of [
    ["consumer-rejects-missing-signature", await send(null), 401],
    ["consumer-rejects-invalid-signature", await send(probeSeconds + ".invalid"), 401],
    ["consumer-rejects-body", await send(await makeSignature("/consume"), "{}"), 400],
    ["consumer-accepts-synthetic-signature", await send(await makeSignature("/consume")), 200],
  ]) {
    if (result.status !== expectedStatus) throw new Error("unexpected-status:" + name);
    if (result.text.includes("PRIVATE_SENTINEL") || result.text.includes(probeSecret)) {
      throw new Error("sensitive-output:" + name);
    }
    if (name === "consumer-accepts-synthetic-signature" && result.text !==
      '{"ok":true,"processed":1,"states":{"synced":1},"hasMore":false}') {
      throw new Error("unexpected-sanitized-response");
    }
    results.push({ name, status: result.status });
  }
  console.log("EDGE_RUNTIME_PROBE " + JSON.stringify({ version: "v1.77.4", passed: 6, failed: 0, results }));
  return { passed: 6, failed: 0, results };
}
async function makeSignature(pathname) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(probeSecret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const message = "catalog-outbox-consumer-v1\\nPOST\\n" + pathname + "\\n" + probeSeconds;
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
  const encoded = btoa(String.fromCharCode(...signature)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
  return probeSeconds + "." + encoded;
}
const server = Deno.serve({ hostname: "127.0.0.1", port: 9000 }, async (request) => {
  if (new URL(request.url).pathname !== "/run-tests") return new Response("not-found", { status: 404 });
  try { return Response.json(await runProbe(request)); }
  catch { console.error("EDGE_RUNTIME_PROBE failed: sanitized runtime or handler failure"); return Response.json({ passed: 0, failed: 1 }, { status: 500 }); }
});
try {
  const response = await fetch("http://127.0.0.1:9000/run-tests", { signal: AbortSignal.timeout(25000) });
  const report = await response.json();
  console.log("EDGE_RUNTIME_HTTP_RESULT " + JSON.stringify({ status: response.status, report }));
  if (response.status !== 200 || report?.failed !== 0 || report?.passed !== 6) throw new Error("runtime-tests-failed");
} finally { await server.shutdown(); }
`;

function docker(args, timeout = 15_000) {
  const result = spawnSync('docker', args, {
    encoding: 'utf8', timeout, windowsHide: true, maxBuffer: 1024 * 1024,
    env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, TEMP: process.env.TEMP, TMP: process.env.TMP },
  });
  if (result.error || result.status !== 0) {
    throw new Error(`docker-${args[0]}-failed:${result.error?.code ?? result.status ?? 'unknown'}`);
  }
  return result.stdout.trim();
}

async function runProbe() {
  const image = JSON.parse(docker(['image', 'inspect', EDGE_RUNTIME_IMAGE]))[0];
  if (image?.Id !== 'sha256:ad45164b7548bf5820ed7be714789c17ac2865edce79a09cfb4c3756c3d365a8') {
    throw new Error('edge-runtime-image-digest-mismatch');
  }
  const tempRoot = mkdtempSync(join(tmpdir(), 'macacu-edge-runtime-probe-'));
  const containerName = `macacu-edge-runtime-${process.pid}-${Date.now().toString(36)}`;
  let created = false;
  try {
    const functionDir = join(tempRoot, 'functions', runtimeFunction);
    const probeFunctionDir = join(tempRoot, 'functions', 'consumer-probe');
    const sharedDir = join(tempRoot, 'functions', '_shared');
    const mainDir = join(tempRoot, 'main');
    mkdirSync(functionDir, { recursive: true });
    mkdirSync(probeFunctionDir, { recursive: true });
    mkdirSync(sharedDir, { recursive: true });
    mkdirSync(mainDir, { recursive: true });
    cpSync(join(projectRoot, 'supabase', 'functions', runtimeFunction, 'index.ts'), join(functionDir, 'index.ts'));
    const sharedSource = join(projectRoot, 'supabase', 'functions', '_shared');
    for (const entry of readdirSync(sharedSource, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.mjs')) cpSync(join(sharedSource, entry.name), join(sharedDir, entry.name));
    }
    writeFileSync(join(mainDir, 'index.ts'), mainSource, { encoding: 'utf8', flag: 'wx' });
    writeFileSync(join(probeFunctionDir, 'index.ts'), `import { createCatalogOutboxConsumerHandler } from "../_shared/catalog_outbox_consumer.mjs";
const secret = "synthetic-edge-runtime-hmac-secret-0123456789";
Deno.serve(createCatalogOutboxConsumerHandler({ enabled: true, secret, pageSize: 25,
  now: () => 1_798_240_800_000,
  processPage: async (request: { limit: number; cursor: string | null }) => {
    if (request.limit !== 25 || request.cursor !== null) throw new Error("unexpected-bounds");
    return { results: [{ eventId: "PRIVATE_SENTINEL", state: "synced" }] };
  },
}));
`, { encoding: 'utf8', flag: 'wx' });

    docker(buildContainerCreateArgs({ tempRoot, containerName }));
    created = true;
    const inspect = JSON.parse(docker(['inspect', containerName]))[0];
    if (!validateContainerIsolation(inspect).ok) throw new Error('edge-runtime-isolation-rejected');
    docker(['start', containerName]);

    const deadline = Date.now() + timeoutMs;
    let output = '';
    while (Date.now() < deadline) {
      output = docker(['logs', containerName]);
      const summary = parseRuntimeProbeOutput(output);
      if (summary) {
        const state = JSON.parse(docker(['inspect', containerName]))[0]?.State?.Status;
        process.stdout.write(`${JSON.stringify({ image: EDGE_RUNTIME_IMAGE, digest: image.Id, isolation: 'verified', ...summary, containerStateBeforeCleanup: state })}\n`);
        return 0;
      }
      const state = JSON.parse(docker(['inspect', containerName]))[0]?.State?.Status;
      if (state === 'exited' || state === 'dead') throw new Error('edge-runtime-probe-exited-without-valid-result');
      await new Promise((resolvePromise) => setTimeout(resolvePromise, 500));
    }
    throw new Error('edge-runtime-probe-timeout');
  } finally {
    const tempPrefix = join(tmpdir(), 'macacu-edge-runtime-probe-').toLowerCase();
    const normalizedTemp = resolve(tempRoot).toLowerCase();
    try {
      cleanupProbeContainer(docker, containerName, created);
    } finally {
      if (normalizedTemp.startsWith(tempPrefix) && basename(normalizedTemp).startsWith('macacu-edge-runtime-probe-')) {
        rmSync(tempRoot, { recursive: true, force: true });
      }
    }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runProbe().then((code) => { process.exitCode = code; }).catch((error) => {
    const safeErrors = new Set(['edge-runtime-isolation-rejected', 'edge-runtime-container-cleanup-failed']);
    process.stderr.write(`${safeErrors.has(error.message) ? error.message : 'edge-runtime-probe-failed'}\n`);
    process.exitCode = 1;
  });
}
