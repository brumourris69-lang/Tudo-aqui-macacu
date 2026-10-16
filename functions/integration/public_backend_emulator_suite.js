'use strict';

// Run after Firebase CLI has started the isolated demo Auth, Firestore, and Functions emulators.
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');

readDemoEmulatorEnvironment();
const suites = [
  'content_visibility_emulator.js',
  'public_content_detail_emulator.js',
  'search_emulator.js',
];

for (const suite of suites) {
  const file = path.join(__dirname, suite);
  console.log(`Starting isolated integration suite: ${suite}`);
  const result = spawnSync(process.execPath, [file], { stdio: 'inherit', env: process.env });
  if (result.error) {
    console.error(`Could not start ${suite} (${result.error.name}).`);
    process.exit(1);
  }
  if (result.status !== 0) {
    console.error(`Integration suite failed: ${suite} (exit ${result.status ?? 'signal'}).`);
    process.exit(result.status || 1);
  }
}

console.log('All public backend demo integration suites passed.');
