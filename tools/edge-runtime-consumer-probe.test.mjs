import assert from 'node:assert/strict';
import test from 'node:test';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import {
  buildContainerCreateArgs,
  cleanupProbeContainer,
  parseRuntimeProbeOutput,
  validateContainerIsolation,
} from './edge-runtime-consumer-probe.mjs';

const tempRoot = resolve(join(tmpdir(), 'macacu-edge-runtime-probe-fixture'));
const name = 'macacu-edge-runtime-probe-test';

test('container creation is pinned, isolated, read-only, and has no published port or credentials', () => {
  const args = buildContainerCreateArgs({ tempRoot, containerName: name });
  assert.equal(args[args.indexOf('--network') + 1], 'none');
  assert.ok(args.includes('--read-only'));
  assert.ok(args.includes('--cap-drop') && args.includes('ALL'));
  assert.ok(args.includes('--security-opt') && args.includes('no-new-privileges:true'));
  assert.ok(args.includes('--pids-limit') && args.includes('64'));
  assert.ok(args.includes('--mount'));
  assert.ok(args.some((arg) => arg.includes('target=/opt/runtime,readonly')));
  assert.equal(args.includes('-p') || args.includes('--publish'), false);
  assert.equal(args.some((arg) => /SERVICE_ROLE|PRIVATE_KEY|TOKEN|SECRET/iu.test(arg)), false);
});

test('inspect validation rejects any network, published port, writable mount, or privileged process', () => {
  const base = {
    HostConfig: {
      NetworkMode: 'none', PortBindings: {}, ReadonlyRootfs: true, CapDrop: ['ALL'],
      SecurityOpt: ['no-new-privileges:true'], Memory: 805306368, NanoCpus: 1_000_000_000,
      PidsLimit: 64,
    },
    Config: { Image: 'public.ecr.aws/supabase/edge-runtime:v1.77.4', User: '10001:10001' },
    Mounts: [{ Destination: '/opt/runtime', RW: false }],
    NetworkSettings: { Ports: {} },
  };
  assert.equal(validateContainerIsolation(base).ok, true);
  assert.equal(validateContainerIsolation({ ...base, HostConfig: { ...base.HostConfig, NetworkMode: 'bridge' } }).ok, false);
  assert.equal(validateContainerIsolation({ ...base, HostConfig: { ...base.HostConfig, PortBindings: { '9000/tcp': [] } } }).ok, false);
  assert.equal(validateContainerIsolation({ ...base, Mounts: [{ Destination: '/opt/runtime', RW: true }] }).ok, false);
  assert.equal(validateContainerIsolation({ ...base, Config: { ...base.Config, User: '0:0' } }).ok, false);
});

test('runtime output parser accepts only the expected sanitized 2xx probe result', () => {
  const output = 'EDGE_RUNTIME_PROBE {"version":"v1.77.4","passed":6,"failed":0,"results":[{"name":"consumer-rejects-non-post","status":405},{"name":"consumer-disabled-without-server-secrets","status":503},{"name":"consumer-rejects-missing-signature","status":401},{"name":"consumer-rejects-invalid-signature","status":401},{"name":"consumer-rejects-body","status":400},{"name":"consumer-accepts-synthetic-signature","status":200}]}\nEDGE_RUNTIME_HTTP_RESULT {"status":200,"report":{"passed":6,"failed":0,"results":[{"status":405},{"status":503},{"status":401},{"status":401},{"status":400},{"status":200}]}}';
  assert.deepEqual(parseRuntimeProbeOutput(output), { passed: 6, failed: 0, statuses: [405, 503, 401, 401, 400, 200] });
  assert.equal(parseRuntimeProbeOutput('EDGE_RUNTIME_HTTP_RESULT {"status":500,"report":{"passed":0,"failed":1}}'), null);
});

test('cleanup removes only a container created by the probe and fails visibly if removal fails', () => {
  const calls = [];
  cleanupProbeContainer((args) => calls.push(args), 'macacu-edge-runtime-123-abc', true);
  cleanupProbeContainer((args) => calls.push(args), 'must-not-remove', false);
  assert.deepEqual(calls, [['rm', '--force', 'macacu-edge-runtime-123-abc']]);
  assert.throws(() => cleanupProbeContainer(() => { throw new Error('docker unavailable'); },
    'macacu-edge-runtime-123-abc', true), { message: 'edge-runtime-container-cleanup-failed' });
  assert.throws(() => cleanupProbeContainer((args) => calls.push(args), 'preexisting-container', true),
    { message: 'edge-runtime-container-cleanup-failed' });
});
