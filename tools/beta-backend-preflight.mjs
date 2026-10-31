#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const targetProject = 'macacu-beta-261030-cf4a81';
const functions = Object.freeze([
  'listPublicContent',
  'getPublicContentDetail',
  'searchPublicContent',
  'syncBetaSearchEstablishments',
  'syncBetaSearchRoutes',
  'syncBetaSearchEvents',
]);
const lockPath = path.join(root, 'functions/beta-backend-release-lock.json');
const requiredLockedFiles = Object.freeze([
  'firebase.json',
  'firebase.search-emulator.json',
  'firestore.rules',
  'firestore.indexes.json',
  'firestore.search-local.indexes.json',
  'functions/index.js',
  'functions/secure_beta_environment.js',
  'functions/public_content.js',
  'functions/beta_public_search.js',
  'functions/beta_search_backfill.js',
  'functions/business_search.js',
  'functions/business_search_firestore.js',
  'functions/content_visibility.js',
  'functions/public_content_projection.js',
  'functions/package.json',
  'functions/package-lock.json',
  'lib/core/content/secure_backend.dart',
  'lib/core/content/public_content_detail_repository.dart',
  'lib/features/search/pages/universal_search_page.dart',
  'lib/features/search/repositories/beta_public_search_repository.dart',
  'lib/redesigned_app.dart',
]);
const rateLimitTtlFields = Object.freeze([
  ['public_content_rate_limits', 'expiresAt'],
  ['public_content_detail_rate_limits', 'expiresAt'],
  ['business_search_rate_limits', 'expiresAt'],
]);

function fail(message) {
  console.error(`NO-GO: ${message}`);
  process.exitCode = 1;
  return false;
}

function main() {
const args = new Map();
for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg === '--project' || arg === '--preflight-only') {
    if (args.has(arg)) return fail(`duplicate ${arg}`);
    args.set(arg, arg === '--preflight-only' ? true : process.argv[++i]);
  } else {
    return fail(`unsupported option ${arg}; this runner never deploys`);
  }
}
if (args.get('--project') !== targetProject || args.get('--preflight-only') !== true) {
  return fail(`explicit --project ${targetProject} and --preflight-only are required`);
}

let lock;
try {
  lock = JSON.parse(fs.readFileSync(lockPath, 'utf8'));
} catch {
  return fail('release hash lock is missing or invalid');
}
if (lock.projectId !== targetProject || JSON.stringify(lock.functions) !== JSON.stringify(functions)) {
  return fail('release lock project/function allowlist differs');
}

const errors = [];
const hashes = {};
for (const [relativePath, expectedHash] of Object.entries(lock.files || {})) {
  const absolutePath = path.resolve(root, relativePath);
  if (!absolutePath.startsWith(`${root}${path.sep}`)) {
    errors.push(`locked path escapes repository: ${relativePath}`);
    continue;
  }
  try {
    const digest = crypto.createHash('sha256').update(fs.readFileSync(absolutePath)).digest('hex');
    hashes[relativePath] = digest;
    if (digest !== expectedHash) errors.push(`SHA-256 mismatch: ${relativePath}`);
  } catch {
    errors.push(`locked file missing: ${relativePath}`);
  }
}
if (Object.keys(hashes).length !== Object.keys(lock.files || {}).length) {
  errors.push('release lock file list is empty or incomplete');
}
for (const requiredPath of requiredLockedFiles) {
  if (!Object.hasOwn(lock.files || {}, requiredPath)) {
    errors.push(`release hash lock omits required Beta search file: ${requiredPath}`);
  }
}

try {
  const firebase = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'), 'utf8'));
  if ((firebase.functions?.[0]?.source || firebase.functions?.source) !== 'functions' ||
      firebase.firestore?.rules !== 'firestore.rules' ||
      firebase.firestore?.indexes !== 'firestore.indexes.json') {
    errors.push('Firebase release configuration differs from the locked target files');
  }
} catch {
  errors.push('firebase.json is invalid');
}

const entry = fs.readFileSync(path.join(root, 'functions/index.js'), 'utf8');
if (!entry.includes("registerBetaPublicContent({ admin, onCall, HttpsError })") ||
    !entry.includes("registerBetaPublicSearch({") ||
    !entry.includes('else if (!stagingContext && !betaContext && require(\'./secure_backend_environment\').secureBackendAllowed())')) {
  errors.push('Beta entrypoint is not isolated from the normal backend surface');
}
const publicSource = fs.readFileSync(path.join(root, 'functions/public_content.js'), 'utf8');
if ((publicSource.match(/enforceAppCheck:\s*true/g) || []).length < 2 ||
    (publicSource.match(/if \(!request\.app\?\.appId\)/g) || []).length < 2 ||
    !publicSource.includes('rateLimitPrincipal(request)') ||
    !publicSource.includes('PUBLIC_RESPONSE_MAX_BYTES = 256 * 1024') ||
    !publicSource.includes("net.isIP(ip) !== 0 ? ip : 'shared'")) {
  errors.push('public callables must retain App Check, visitor quotas, valid IP checks, and response ceiling');
}
try {
  const searchSource = fs.readFileSync(path.join(root, 'functions/beta_public_search.js'), 'utf8');
  for (const required of [
    'enforceAppCheck: true',
    'backend.searchPublic(request)',
    "requireAppCheck: true",
    "'establishments'",
    "'routes'",
    "'events'",
    'if (!backendAllowed())',
  ]) {
    if (!searchSource.includes(required)) errors.push(`Beta search control is missing: ${required}`);
  }
} catch {
  errors.push('Beta public search registrar is missing');
}
try {
  const backfillSource = fs.readFileSync(path.join(root, 'functions/beta_search_backfill.js'), 'utf8');
  for (const required of [
    'BETA_BACKFILL_MAX_DOCUMENTS = 500',
    'BETA_BACKFILL_MAX_PAGE_SIZE = 100',
    'await synchronize(collection, item.id)',
    'checkpoint: rawCheckpoint',
    'createFirestoreSourcePageReader',
  ]) {
    if (!backfillSource.includes(required)) errors.push(`Beta initial-indexing safeguard is missing: ${required}`);
  }
  if (entry.includes('runBetaSearchBackfill') || entry.includes('createFirestoreSourcePageReader')) {
    errors.push('Beta initial-indexing helper must remain manual and unregistered; no automatic backfill is authorized');
  }
} catch {
  errors.push('Beta initial-indexing helper is missing');
}
try {
  const firestoreIndexes = JSON.parse(fs.readFileSync(path.join(root, 'firestore.indexes.json'), 'utf8'));
  for (const [collectionGroup, fieldPath] of rateLimitTtlFields) {
    const ttl = (firestoreIndexes.fieldOverrides || []).find(field =>
      field.collectionGroup === collectionGroup && field.fieldPath === fieldPath && field.ttl === true);
    if (!ttl) errors.push(`Firestore TTL is not configured for ${collectionGroup}.${fieldPath}`);
  }
  const publicSearchIndex = (firestoreIndexes.indexes || []).some(index =>
    index.collectionGroup === 'business_search_index' &&
    index.fields?.some(field => field.fieldPath === 'prefixes' && field.arrayConfig === 'CONTAINS') &&
    index.fields?.some(field => field.fieldPath === 'type' && field.order === 'ASCENDING'));
  if (!publicSearchIndex) errors.push('Firestore composite index for public tourism/event search is missing');
} catch {
  errors.push('firestore.indexes.json is invalid or missing');
}
const rules = fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8');
if (rules.includes('match /business_search_index') ||
    rules.includes('match /business_search_rate_limits')) {
  errors.push('Internal search index/rate-limit documents must remain inaccessible to clients');
}

if (errors.length) {
  for (const error of errors) console.error(`NO-GO: ${error}`);
  process.exitCode = 1;
} else {
  console.log(JSON.stringify({
    result: 'PASS — local preflight only; no Firebase CLI/network/deploy invoked',
    project: targetProject,
    functions,
    lockedFiles: Object.keys(hashes).sort(),
    requiredFirestoreTtlFields: rateLimitTtlFields.map(([collectionGroup, fieldPath]) =>
      `${collectionGroup}.${fieldPath}`),
    requiredFirestoreCompositeIndexes: ['business_search_index(prefixes ARRAY_CONTAINS, group ASCENDING)',
      'business_search_index(prefixes ARRAY_CONTAINS, type ASCENDING)'],
    hashes,
    plannedCommand: `firebase deploy --only firestore:indexes,${functions.map(name => `functions:${name}`).join(',')} --project ${targetProject}`,
  }, null, 2));
}
}

main();
