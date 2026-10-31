import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MANIFEST_PATH = 'tools/staging-rules-preflight.json';
const PINNED_PROJECTS = Object.freeze({
  test: 'demo-universal-search',
  staging: 'macacu-staging-261022',
  production: 'tudo-aqui-macacu',
});

function insideRoot(root, relativePath) {
  if (typeof relativePath !== 'string' || path.isAbsolute(relativePath)) return null;
  const resolved = path.resolve(root, relativePath);
  return resolved.startsWith(`${path.resolve(root)}${path.sep}`) ? resolved : null;
}

function readJson(root, relativePath, errors) {
  const resolved = insideRoot(root, relativePath);
  if (!resolved) {
    errors.push(`Unsafe or invalid relative path: ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(resolved, 'utf8'));
  } catch {
    errors.push(`Missing or invalid JSON: ${relativePath}`);
    return null;
  }
}

function readBytes(root, relativePath, errors) {
  const resolved = insideRoot(root, relativePath);
  if (!resolved) {
    errors.push(`Unsafe or invalid relative path: ${relativePath}`);
    return null;
  }
  try {
    return fs.readFileSync(resolved);
  } catch {
    errors.push(`Missing file: ${relativePath}`);
    return null;
  }
}

export function validateStagingRulesPreflight(root = DEFAULT_ROOT) {
  const errors = [];
  const manifest = readJson(root, MANIFEST_PATH, errors);
  if (!manifest) return { ok: false, errors, details: null };
  if (manifest.schemaVersion !== 1) errors.push('Unsupported preflight manifest schema version');
  if (manifest.testProjectId !== PINNED_PROJECTS.test) errors.push('Test project ID differs from the pinned demo project');
  if (manifest.stagingProjectId !== PINNED_PROJECTS.staging) errors.push('Staging project ID differs from the pinned staging project');
  if (manifest.defaultProjectId !== PINNED_PROJECTS.production) errors.push('Default project ID differs from the pinned production alias');
  if (!Array.isArray(manifest.productionProjectIds) ||
      manifest.productionProjectIds.length !== 1 ||
      manifest.productionProjectIds[0] !== PINNED_PROJECTS.production) {
    errors.push('Production project ID list differs from the pinned production project');
  }

  const expectedPaths = {
    rulesSourcePath: 'firestore.rules',
    rulesMirrorPath: 'firestore.claims-local.rules',
    releaseConfigPath: 'firebase.json',
    emulatorConfigPath: 'firebase.search-emulator.json',
  };
  for (const [key, expected] of Object.entries(expectedPaths)) {
    if (manifest[key] !== expected) errors.push(`${key} must remain ${expected}`);
  }
  if (manifest.stagingDeployment?.configPath !== manifest.releaseConfigPath) {
    errors.push('Staging must reuse the pinned release config file');
  }
  if (manifest.stagingDeployment?.projectId !== manifest.stagingProjectId ||
      manifest.stagingDeployment?.requiresExplicitProjectFlag !== true) {
    errors.push('Staging deployment must pin its project and require an explicit --project flag');
  }

  const projectIds = [manifest.testProjectId, manifest.stagingProjectId,
    ...(manifest.productionProjectIds ?? [])];
  if (projectIds.some((id) => typeof id !== 'string' || !/^[a-z][a-z0-9-]{4,29}$/.test(id))) {
    errors.push('All Firebase project IDs must be explicit valid project IDs');
  }
  if (new Set(projectIds).size !== projectIds.length) {
    errors.push('Test, staging, and production project IDs must be distinct');
  }
  if (!Array.isArray(manifest.productionProjectIds) ||
      !manifest.productionProjectIds.includes(manifest.defaultProjectId)) {
    errors.push('The current default Firebase alias must remain a known production project');
  }

  const rules = readBytes(root, manifest.rulesSourcePath, errors);
  const mirror = readBytes(root, manifest.rulesMirrorPath, errors);
  if (rules && mirror && !rules.equals(mirror)) errors.push('Rules mirror differs from the tested Rules source');
  if (rules) {
    const digest = crypto.createHash('sha256').update(rules).digest('hex');
    if (digest !== manifest.rulesSha256) errors.push(`Rules SHA-256 mismatch: ${digest}`);
  }

  const releaseConfig = readJson(root, manifest.releaseConfigPath, errors);
  const emulatorConfig = readJson(root, manifest.emulatorConfigPath, errors);
  const rulesPath = manifest.rulesSourcePath;
  if (releaseConfig?.firestore?.rules !== rulesPath) {
    errors.push('Release config Rules path differs from the tested Rules source');
  }
  if (emulatorConfig?.firestore?.rules !== rulesPath) {
    errors.push('Emulator config Rules path differs from the tested Rules source');
  }
  if (releaseConfig?.emulators) errors.push('Release config must not define local emulators');
  if (emulatorConfig?.projectId || emulatorConfig?.projects) {
    errors.push('Emulator config must not embed a project selection; pass --project explicitly');
  }

  const emulators = emulatorConfig?.emulators;
  for (const [name, emulator] of Object.entries(emulators ?? {})) {
    if (emulator && typeof emulator === 'object' && 'host' in emulator && emulator.host !== '127.0.0.1') {
      errors.push(`${name} emulator must bind to 127.0.0.1`);
    }
  }
  for (const name of ['auth', 'firestore']) {
    const emulator = emulators?.[name];
    if (emulator?.port !== manifest.emulatorPorts?.[name]) {
      errors.push(`${name} emulator port differs from the pinned test port`);
    }
  }
  if (emulators?.ui?.enabled !== false) errors.push('Emulator UI must remain disabled for the isolated test profile');

  const firebaserc = readJson(root, '.firebaserc', errors);
  if (firebaserc?.projects?.default !== manifest.defaultProjectId) {
    errors.push('The default Firebase project alias changed; stop and review target selection');
  }

  const details = {
    testProjectId: manifest.testProjectId,
    stagingProjectId: manifest.stagingProjectId,
    productionProjectIds: manifest.productionProjectIds,
    defaultProjectId: manifest.defaultProjectId,
    rulesSourcePath: manifest.rulesSourcePath,
    rulesSha256: manifest.rulesSha256,
    releaseConfigPath: manifest.releaseConfigPath,
    emulatorConfigPath: manifest.emulatorConfigPath,
  };
  return { ok: errors.length === 0, errors, details };
}

function main() {
  const result = validateStagingRulesPreflight();
  if (!result.ok) {
    console.error('NO-GO: staging Rules preflight failed. No Firebase service was contacted.');
    for (const error of result.errors) console.error(`- ${error}`);
    process.exitCode = 1;
    return;
  }
  console.log('PASS: local-only staging Rules preflight; no Firebase service was contacted.');
  console.log(`Rules: ${result.details.rulesSourcePath} SHA-256 ${result.details.rulesSha256}`);
  console.log(`Emulator project: ${result.details.testProjectId}`);
  console.log(`Staging target: ${result.details.stagingProjectId}`);
  console.log(`Production/default alias remains: ${result.details.defaultProjectId}`);
  console.log('Use an explicit --project value for every Firebase CLI command.');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
