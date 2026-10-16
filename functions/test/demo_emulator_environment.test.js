'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { readDemoEmulatorEnvironment } = require('../integration/demo_emulator_environment');

const validEnvironment = () => ({
  GCLOUD_PROJECT: 'demo-universal-search',
  FUNCTIONS_EMULATOR: 'true',
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:19097',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:18087',
  FUNCTIONS_EMULATOR_HOST: '127.0.0.1:15007',
  FUNCTIONS_EMULATOR_PORT: '15007',
});

test('accepts the explicit demo project and loopback emulator endpoints', () => {
  const result = readDemoEmulatorEnvironment(validEnvironment());
  assert.deepEqual(result, {
    project: 'demo-universal-search',
    authHost: '127.0.0.1:19097',
    firestoreHost: '127.0.0.1:18087',
    functionsHost: '127.0.0.1:15007',
    functionsOrigin: 'http://127.0.0.1:15007',
    functionsPort: 15007,
  });
});

test('rejects any project other than the explicitly approved demo', () => {
  assert.throws(() => readDemoEmulatorEnvironment({
    ...validEnvironment(), GCLOUD_PROJECT: 'tudo-aqui-macacu',
  }), /demo project/);
});

test('rejects absent emulator mode and non-loopback or malformed hosts', () => {
  assert.throws(() => readDemoEmulatorEnvironment({
    ...validEnvironment(), FUNCTIONS_EMULATOR: undefined,
  }), /Functions Emulator/);
  for (const host of ['localhost:18087', '10.0.0.2:18087', '127.0.0.1:0', '127.0.0.1:65536']) {
    assert.throws(() => readDemoEmulatorEnvironment({
      ...validEnvironment(), FIRESTORE_EMULATOR_HOST: host,
    }), /loopback/);
  }
});

test('rejects mismatched Functions host and port settings', () => {
  assert.throws(() => readDemoEmulatorEnvironment({
    ...validEnvironment(), FUNCTIONS_EMULATOR_PORT: '15008',
  }), /Functions Emulator endpoint/);
});
