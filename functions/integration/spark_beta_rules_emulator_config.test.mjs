import assert from 'node:assert/strict';
import test from 'node:test';
import { resolveLoopbackEmulatorEndpoint } from './spark_beta_rules_emulator_config.mjs';

test('defaults preserve the existing SparkLocal Auth and Firestore ports', () => {
  assert.deepEqual(
    resolveLoopbackEmulatorEndpoint(undefined, 9097, 'Auth'),
    { host: '127.0.0.1', port: 9097, address: '127.0.0.1:9097' },
  );
  assert.deepEqual(
    resolveLoopbackEmulatorEndpoint(undefined, 8087, 'Firestore'),
    { host: '127.0.0.1', port: 8087, address: '127.0.0.1:8087' },
  );
});

test('accepts explicitly configured temporary loopback ports', () => {
  assert.deepEqual(
    resolveLoopbackEmulatorEndpoint('127.0.0.1:19273', 9097, 'Auth'),
    { host: '127.0.0.1', port: 19273, address: '127.0.0.1:19273' },
  );
});

test('rejects non-loopback hosts and malformed endpoints', () => {
  for (const invalid of [
    'localhost:9097',
    '0.0.0.0:9097',
    '8.8.8.8:9097',
    '127.0.0.1',
    '127.0.0.1:0',
    '127.0.0.1:65536',
    '127.0.0.1:abc',
  ]) {
    assert.throws(
      () => resolveLoopbackEmulatorEndpoint(invalid, 9097, 'Auth'),
      /127\.0\.0\.1|TCP port/,
      invalid,
    );
  }
});
