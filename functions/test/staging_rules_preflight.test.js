'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { validateStagingRulesPreflight } = require('../../tools/staging-rules-preflight.mjs');

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'macacu-staging-rules-'));
  const rules = 'rules_version = \'2\';\nservice cloud.firestore {}\n';
  const digest = crypto.createHash('sha256').update(rules).digest('hex');
  const manifest = {
    schemaVersion: 1,
    testProjectId: 'demo-universal-search',
    stagingProjectId: 'macacu-staging-261022',
    productionProjectIds: ['tudo-aqui-macacu'],
    defaultProjectId: 'tudo-aqui-macacu',
    rulesSourcePath: 'firestore.rules',
    rulesMirrorPath: 'firestore.claims-local.rules',
    rulesSha256: digest,
    releaseConfigPath: 'firebase.json',
    emulatorConfigPath: 'firebase.search-emulator.json',
    emulatorPorts: { auth: 9097, firestore: 8087 },
    stagingDeployment: {
      configPath: 'firebase.json',
      projectId: 'macacu-staging-261022',
      requiresExplicitProjectFlag: true,
    },
  };
  const releaseConfig = { firestore: { rules: 'firestore.rules', indexes: 'firestore.indexes.json' } };
  const emulatorConfig = {
    firestore: { rules: 'firestore.rules' },
    emulators: {
      auth: { host: '127.0.0.1', port: 9097 },
      firestore: { host: '127.0.0.1', port: 8087 },
      hub: { host: '127.0.0.1', port: 4407 },
      logging: { host: '127.0.0.1', port: 4507 },
      ui: { enabled: false },
      singleProjectMode: true,
    },
  };
  fs.mkdirSync(path.join(root, 'tools'));
  fs.writeFileSync(path.join(root, 'tools/staging-rules-preflight.json'), JSON.stringify(manifest));
  fs.writeFileSync(path.join(root, 'firestore.rules'), rules);
  fs.writeFileSync(path.join(root, 'firestore.claims-local.rules'), rules);
  fs.writeFileSync(path.join(root, 'firebase.json'), JSON.stringify(releaseConfig));
  fs.writeFileSync(path.join(root, 'firebase.search-emulator.json'), JSON.stringify(emulatorConfig));
  fs.writeFileSync(path.join(root, '.firebaserc'), JSON.stringify({ projects: { default: 'tudo-aqui-macacu' } }));
  return { root, manifest, releaseConfig, emulatorConfig };
}

test('accepts only matching tested Rules, loopback emulator config and distinct staging target', () => {
  const f = fixture();
  try {
    const result = validateStagingRulesPreflight(f.root);
    assert.equal(result.ok, true, result.errors.join('\n'));
    assert.equal(result.details.testProjectId, 'demo-universal-search');
    assert.equal(result.details.stagingProjectId, 'macacu-staging-261022');
  } finally {
    fs.rmSync(f.root, { recursive: true, force: true });
  }
});

test('rejects changed Rules bytes after local validation', () => {
  const f = fixture();
  try {
    fs.appendFileSync(path.join(f.root, 'firestore.rules'), '// changed\n');
    const result = validateStagingRulesPreflight(f.root);
    assert.equal(result.ok, false);
    assert.ok(result.errors.some((error) => error.includes('Rules SHA-256 mismatch')));
  } finally {
    fs.rmSync(f.root, { recursive: true, force: true });
  }
});

test('rejects emulator rules that point to any file other than the tested source', () => {
  const f = fixture();
  try {
    f.emulatorConfig.firestore.rules = 'firestore.claims-local.rules';
    fs.writeFileSync(path.join(f.root, 'firebase.search-emulator.json'), JSON.stringify(f.emulatorConfig));
    const result = validateStagingRulesPreflight(f.root);
    assert.equal(result.ok, false);
    assert.ok(result.errors.some((error) => error.includes('Emulator config Rules path')));
  } finally {
    fs.rmSync(f.root, { recursive: true, force: true });
  }
});

test('rejects emulator listeners outside loopback', () => {
  const f = fixture();
  try {
    f.emulatorConfig.emulators.firestore.host = '0.0.0.0';
    fs.writeFileSync(path.join(f.root, 'firebase.search-emulator.json'), JSON.stringify(f.emulatorConfig));
    const result = validateStagingRulesPreflight(f.root);
    assert.equal(result.ok, false);
    assert.ok(result.errors.some((error) => error.includes('must bind to 127.0.0.1')));
  } finally {
    fs.rmSync(f.root, { recursive: true, force: true });
  }
});

test('rejects a staging target that collides with production or the default alias', () => {
  const f = fixture();
  try {
    f.manifest.stagingProjectId = 'tudo-aqui-macacu';
    fs.writeFileSync(path.join(f.root, 'tools/staging-rules-preflight.json'), JSON.stringify(f.manifest));
    const result = validateStagingRulesPreflight(f.root);
    assert.equal(result.ok, false);
    assert.ok(result.errors.some((error) => error.includes('Test, staging, and production project IDs must be distinct')));
  } finally {
    fs.rmSync(f.root, { recursive: true, force: true });
  }
});

test('rejects a manifest changed to a different non-production staging project', () => {
  const f = fixture();
  try {
    f.manifest.stagingProjectId = 'unreviewed-staging-project';
    f.manifest.stagingDeployment.projectId = 'unreviewed-staging-project';
    fs.writeFileSync(path.join(f.root, 'tools/staging-rules-preflight.json'), JSON.stringify(f.manifest));
    const result = validateStagingRulesPreflight(f.root);
    assert.equal(result.ok, false);
    assert.ok(result.errors.some((error) => error.includes('pinned staging project')));
  } finally {
    fs.rmSync(f.root, { recursive: true, force: true });
  }
});

test('rejects a changed mirror Rules file and default Firebase project alias', () => {
  const f = fixture();
  try {
    fs.appendFileSync(path.join(f.root, 'firestore.claims-local.rules'), '// drift\n');
    fs.writeFileSync(path.join(f.root, '.firebaserc'), JSON.stringify({ projects: { default: 'macacu-staging-261022' } }));
    const result = validateStagingRulesPreflight(f.root);
    assert.equal(result.ok, false);
    assert.ok(result.errors.some((error) => error.includes('Rules mirror differs')));
    assert.ok(result.errors.some((error) => error.includes('default Firebase project alias')));
  } finally {
    fs.rmSync(f.root, { recursive: true, force: true });
  }
});
