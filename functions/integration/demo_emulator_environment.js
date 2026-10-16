'use strict';

function loopbackHost(value, name) {
  const match = typeof value === 'string' && /^127\.0\.0\.1:(\d{1,5})$/.exec(value);
  const port = match ? Number(match[1]) : NaN;
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error(`${name} must use a valid loopback 127.0.0.1 TCP endpoint.`);
  }
  return { value, port };
}

function readDemoEmulatorEnvironment(env = process.env) {
  if (env.GCLOUD_PROJECT !== 'demo-universal-search') {
    throw new Error('Only the demo project is permitted.');
  }
  if (env.FUNCTIONS_EMULATOR !== 'true') {
    throw new Error('Functions Emulator mode is required.');
  }

  const auth = loopbackHost(env.FIREBASE_AUTH_EMULATOR_HOST, 'Auth Emulator');
  const firestore = loopbackHost(env.FIRESTORE_EMULATOR_HOST, 'Firestore Emulator');
  const functions = loopbackHost(env.FUNCTIONS_EMULATOR_HOST, 'Functions Emulator');
  const configuredPort = Number(env.FUNCTIONS_EMULATOR_PORT);
  if (!Number.isInteger(configuredPort) || configuredPort !== functions.port) {
    throw new Error('Functions Emulator endpoint and port settings must match.');
  }

  return {
    project: env.GCLOUD_PROJECT,
    authHost: auth.value,
    firestoreHost: firestore.value,
    functionsHost: functions.value,
    functionsOrigin: `http://${functions.value}`,
    functionsPort: functions.port,
  };
}

module.exports = { readDemoEmulatorEnvironment };
