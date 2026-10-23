'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const originalPath = path.join(root, 'firestore.rules');
const candidatePath = path.join(root, 'firestore.hybrid-outbox-candidate.rules');
const candidateV2Path = path.join(root, 'firestore.hybrid-outbox-v2-candidate.rules');
const emulatorHarnessPath = path.join(root, 'functions/integration/catalog_outbox_rules_emulator.js');
const authenticatedHarnessPath = path.join(root, 'functions/integration/catalog_outbox_auth_rules_emulator.mjs');

function source(pathname) {
  return fs.readFileSync(pathname, 'utf8').replace(/\r\n/g, '\n');
}

test('candidate exists separately and leaves the primary Rules files untouched', () => {
  assert.ok(fs.existsSync(candidatePath));
  assert.ok(fs.existsSync(path.join(root, 'firestore.claims-local.rules')));
  assert.notEqual(candidatePath, originalPath);
});

test('V2 Rules validate the full event on the source side and keep the outbox binding bounded', () => {
  assert.ok(fs.existsSync(candidateV2Path));
  const v1 = source(candidatePath);
  const v2 = source(candidateV2Path);
  assert.match(v1, /event\.schemaVersion == 1/);
  assert.doesNotMatch(v1, /'workerId', 'leaseToken'/);
  const afterCheck = /function outboxAfterEventMatches\([\s\S]*?^    \}/m.exec(v2)?.[0];
  const createCheck = /function outboxCreatePaired\([\s\S]*?^    \}/m.exec(v2)?.[0];
  assert.ok(afterCheck);
  assert.ok(createCheck);
  assert.match(afterCheck, /event\.keys\(\)\.hasOnly\(/);
  assert.doesNotMatch(afterCheck, /event\.keys\(\)\.hasAll\(/);
  assert.match(afterCheck, /event\.schemaVersion == 2/);
  for (const field of ['workerId', 'leaseToken', 'leaseExpiresAt', 'nextAttemptAt', 'lastErrorCode', 'syncedAt']) {
    const fieldPattern = new RegExp(`'${field}'`);
    const nullPattern = new RegExp(`event\\.${field} == null`);
    assert.match(afterCheck, fieldPattern);
    assert.match(afterCheck, nullPattern);
  }
  assert.match(createCheck, /event\.schemaVersion == 2/);
  assert.match(createCheck, /event\.authorUid == request\.auth\.uid/);
  assert.match(createCheck, /sourceAfterMatchesOutbox\(sourcePath, operationId, event\.version\)/);
  assert.doesNotMatch(createCheck, /event\.keys\(\)\.hasOnly\(|event\.keys\(\)\.hasAll\(/);
  assert.doesNotMatch(/function outboxCreatePaired\([\s\S]*?^    \}/m.exec(v1)?.[0] ?? '', /event\.keys\(\)\.hasOnly\(|event\.keys\(\)\.hasAll\(/);
  assert.match(v2, /allow read, update, delete: if false;/);
  assert.match(v2, /outboxAfterMatchesSource\(operationId, establishmentId, version\)/);
  assert.match(v2, /outboxCreatePaired\(operationId\)/);
});

test('candidate preserves the existing versioned Admin authorization helper', () => {
  const original = source(originalPath);
  const candidate = source(candidatePath);
  const helper = /function admin\(\)\s*\{[\s\S]*?^    \}/m.exec(original)?.[0];
  assert.ok(helper);
  assert.ok(candidate.includes(helper));
  assert.match(candidate, /state\.version == request\.auth\.token\.adminVersion/);
  assert.match(candidate, /state\.enabled == true && state\.pending == false/);
});

test('optional string validation uses a default while changed strings avoid redundant key lookups', () => {
  for (const pathname of [candidatePath, candidateV2Path]) {
    const candidate = source(pathname);
    const optional = /function str\(field, max\)\s*\{[\s\S]*?^    \}/m.exec(candidate)?.[0];
    const changed = /function validEstablishmentUpdateValues\(changed\)\s*\{[\s\S]*?^    \}/m.exec(candidate)?.[0];
    assert.ok(optional && changed);
    assert.match(optional, /let value = request\.resource\.data\.get\(field, ''\)/);
    assert.match(optional, /value is string && value\.size\(\) <= max/);
    assert.doesNotMatch(optional, /keys\(\)\.hasAny/);
    assert.match(changed, /str\('imageUrl', 2048\)/);
    assert.doesNotMatch(candidate, /function strPresent\(/);
  }
});

test('V2 updates validate changed fields and keep tombstones permanently unpublished', () => {
  const candidate = source(candidateV2Path);
  const update = /function establishmentUpdatePaired\([\s\S]*?^    \}/m.exec(candidate)?.[0];
  const validator = /function validEstablishmentUpdateValues\(changed\)\s*\{[\s\S]*?^    \}/m.exec(candidate)?.[0];
  assert.ok(update);
  assert.ok(validator);
  assert.match(update, /let changes = request\.resource\.data\.diff\(resource\.data\)/);
  assert.match(update, /validEstablishmentUpdateValues\(changed\)/);
  assert.doesNotMatch(update, /validEstablishmentValues\(\)/);
  assert.match(validator, /!changed\.hasAny\(\['imageUrl'\]\)\s*\|\|\s*str\('imageUrl', 2048\)/);
  assert.match(validator, /request\.resource\.data\.deletedAt is timestamp/);
  assert.match(validator, /request\.resource\.data\.published == false/);
  assert.match(validator, /request\.resource\.data\.active == false/);
});

test('only an Admin may read their minimal authorization record; clients cannot mutate it', () => {
  const candidate = source(candidatePath);
  assert.match(candidate, /match \/admin_authorizations\/\{uid\}[\s\S]*?allow get: if signedIn\(\)[\s\S]*?request\.auth\.uid == uid[\s\S]*?keys\(\)\.hasOnly\(\['enabled', 'pending', 'version', 'operationId', 'updatedAt'\]\)[\s\S]*?allow list, write: if false;/);
  assert.match(candidate, /keys\(\)\.hasAll\(\['enabled', 'pending', 'version', 'operationId', 'updatedAt'\]\)/);
});

test('establishment create and update require the reciprocal after-state outbox event', () => {
  const candidate = source(candidatePath);
  assert.match(candidate, /function outboxAfterMatchesSource\([\s\S]*?getAfter\(/);
  assert.match(candidate, /match \/establishments\/\{establishmentId\}[\s\S]*?allow write: if request\.resource != null && admin\(\)[\s\S]*?resource == null[\s\S]*?establishmentCreatePaired\(establishmentId\)[\s\S]*?establishmentUpdatePaired\(establishmentId\)[\s\S]*?allow delete: if false;/);
  assert.match(candidate, /match \/establishments\/\{establishmentId\}[\s\S]*?allow get: if admin\(\);\s*allow list: if admin\(\);/);
  assert.match(candidate, /match \/catalog_outbox\/\{operationId\}[\s\S]*?allow create: if admin\(\)[\s\S]*?outboxCreatePaired\(operationId\)[\s\S]*?allow read, update, delete: if false;/);
  assert.match(candidate, /existsAfter\(/);
  assert.match(candidate, /request\.resource\.data\.catalogVersion == priorVersion \+ 1/);
});

test('public root policies use explicit matches and cannot overlap the catalog source or outbox', () => {
  const candidate = source(candidatePath);
  const original = source(originalPath);
  assert.doesNotMatch(candidate, /match \/\{collection\}\/\{document\}/);
  assert.match(candidate, /function genericGet\(collection\)[\s\S]*?collection != 'jobs' && visibleDocument\(collection\)/);
  assert.match(candidate, /function genericWrite\(\)[\s\S]*?admin\(\) && validPublicContent\(\)/);
  const publicList = /function publicCollection\(collection\) \{([\s\S]*?)\n    \}/.exec(original)?.[1];
  assert.ok(publicList);
  const expected = [...publicList.matchAll(/'([a-z_]+)'/gu)].map((match) => match[1])
    .filter((name) => name !== 'establishments');
  const explicit = /\/\/ Explicit root matches[\s\S]*?(?=\n  \})/.exec(candidate)?.[0];
  assert.ok(explicit);
  const actual = [...explicit.matchAll(/^    match \/([a-z_]+)\/\{document\} \{/gmu)].map((match) => match[1]);
  assert.deepEqual(actual, expected);
  assert.ok(!actual.includes('catalog_outbox'));
});

test('paired outbox checks bind each after-state document once and compare the source ID in the helper', () => {
  const candidate = source(candidatePath);
  const eventCheck = /function outboxAfterMatchesSource\([\s\S]*?\n    \}/.exec(candidate)?.[0];
  assert.ok(eventCheck);
  assert.match(eventCheck, /existsAfter\(eventPath\)[\s\S]*getAfter\(eventPath\)\.data/);
  assert.equal((eventCheck.match(/getAfter\(/g) ?? []).length, 1);
  const eventValues = /function outboxAfterEventMatches\([\s\S]*?\n    \}/.exec(candidate)?.[0];
  assert.ok(eventValues);
  assert.match(eventValues, /event\.entityId == establishmentId/);
  assert.match(eventValues, /event\.operationId == operationId/);
  const sourceCheck = /function sourceAfterMatchesOutbox\([\s\S]*?\n    \}/.exec(candidate)?.[0];
  assert.ok(sourceCheck);
  assert.match(sourceCheck, /let source = getAfter\(sourcePath\)\.data/);
  assert.equal((sourceCheck.match(/getAfter\(/g) ?? []).length, 1);
});

test('candidate updates reject replay, version skips and tombstone resurrection before field validation', () => {
  for (const pathname of [candidatePath, candidateV2Path]) {
    const candidate = source(pathname);
    const update = /function establishmentUpdatePaired\([\s\S]*?^    \}/m.exec(candidate)?.[0];
    assert.ok(update);
    const versionCheck = update.indexOf('request.resource.data.catalogVersion == priorVersion + 1');
    const operationCheck = update.indexOf("request.resource.data.outboxOperationId != resource.data.get('outboxOperationId', '')");
    const validatorCheck = update.indexOf('validEstablishment');
    assert.ok(versionCheck >= 0 && operationCheck >= 0 && validatorCheck >= 0);
    assert.ok(versionCheck < validatorCheck && operationCheck < validatorCheck);
    if (pathname === candidateV2Path) {
      assert.ok(update.indexOf("resource.data.get('deletedAt', null) == null") < validatorCheck);
    }
  }
});

test('client outbox events are pending-only reconciliation signals with a strict schema', () => {
  const candidate = source(candidatePath);
  assert.match(candidate, /event\.entityType == 'establishment'/);
  assert.match(candidate, /event\.operation == 'reconcile'/);
  assert.match(candidate, /event\.state == 'pending'/);
  assert.match(candidate, /event\.attemptCount == 0/);
  assert.match(candidate, /event\.authorUid == request\.auth\.uid/);
  assert.match(candidate, /event\.createdAt == request\.time/);
  assert.match(candidate, /event\.updatedAt == request\.time/);
  assert.ok(candidate.includes("matches('^[A-Za-z0-9_-]{16,100}$')"));
});

test('generic collection permissions cannot bypass the establishment-specific policy', () => {
  const candidate = source(candidatePath);
  assert.doesNotMatch(candidate, /match \/\{collection\}\/\{document\}/);
  assert.match(candidate, /match \/establishments\/\{establishmentId\}/);
  assert.match(candidate, /match \/catalog_outbox\/\{operationId\}/);
  assert.match(candidate, /match \/ads\/\{document\}/);
});

test('all rules outside the explicitly replaced authorization and establishment matches are preserved', () => {
  const original = source(originalPath);
  let candidate = source(candidatePath);
  candidate = candidate.replace(
    /\n\n    \/\/ The first hybrid catalog projection[\s\S]*?\n    function visibleDocument\(/,
    '\n    // Lists cannot prove optional field constraints. Public lists are served by\n    // the local authenticated/App Check backend with current-source validation.\n    // Missing optional active/expiry keeps legacy semantics; malformed denies.\n    function visibleDocument(',
  );
  candidate = candidate.replace(
    /\n    function genericGet\(collection\) \{[\s\S]*?\n    function validPublicContent\(/,
    `\n${/    function publicCollection\(collection\) \{[\s\S]*?\n    \}/.exec(original)?.[0]}\n    function validPublicContent(`,
  );
  candidate = candidate.replace(
    /\n    \/\/ Firestore remains the private source[\s\S]*?\n    match \/catalog_outbox\/\{operationId\} \{[\s\S]*?\n    \}/,
    '',
  );
  candidate = candidate.replace(
    /match \/admin_authorizations\/\{uid\} \{[\s\S]*?^    \}/m,
    "match /admin_authorizations/{uid} {\n      allow get: if signedIn() && request.auth.uid == uid &&\n        request.auth.token.get('admin', false) == true;\n      allow list, write: if false;\n    }",
  );
  candidate = candidate.replace(
    '    // Rules cannot field-mask a document response. The record schema is kept\n    // to the five capability fields and only its owner may get it.\n',
    '',
  );
  const originalStr = /function str\(field, max\) \{[\s\S]*?^    \}/m.exec(original)?.[0];
  assert.ok(originalStr);
  candidate = candidate.replace(/function str\(field, max\) \{[\s\S]*?^    \}/m, originalStr);
  candidate = candidate.replace(/\n    function strPresent\(field, max\) \{[\s\S]*?^    \}/m, '');
  const originalGeneric = /match \/\{collection\}\/\{document\} \{[\s\S]*?^    \}/m.exec(original)?.[0];
  const candidateGeneric = /\n    \/\/ Explicit root matches[\s\S]*?\n    match \/public_places\/\{document\} \{[\s\S]*?\n    \}/m.exec(candidate)?.[0];
  assert.ok(originalGeneric && candidateGeneric);
  candidate = candidate.replace(candidateGeneric, `\n    ${originalGeneric}`);
  candidate = candidate.replace(/\n\n    match \/\{collection\}\/\{document\}/, '\n    match /{collection}/{document}');
  assert.equal(candidate, original);
});

test('Emulator harness is pinned to the demo project and separate loopback ports, with scoped cleanup', () => {
  const harness = source(emulatorHarnessPath);
  assert.match(harness, /const PROJECT_ID = 'demo-universal-search'/);
  assert.match(harness, /const EXPECTED_FIRESTORE = '127\.0\.0\.1:18087'/);
  assert.match(harness, /const EXPECTED_AUTH = '127\.0\.0\.1:19097'/);
  assert.match(harness, /emulator\/v1\/projects\/\$\{PROJECT_ID\}:securityRules/);
  assert.match(harness, /for \(const pathname of createdDocs\) await db\.doc\(pathname\)\.delete\(\)/);
  assert.match(harness, /for \(const uid of createdUsers\) await auth\.deleteUser\(uid\)/);
  assert.doesNotMatch(harness, /\/emulator\/v1\/projects\/\$\{PROJECT_ID\}\/databases\/\(default\)\/documents:delete/);
  assert.doesNotMatch(harness, /\.firebaseapp\.com|\.firebasedatabase\.app|firebase deploy|supabase link/);
  assert.doesNotMatch(harness, /DELETE_ALL|wipeDatabase|delete\?namespace=/);
});

test('Emulator harness supports explicit V1 or V2 candidate validation without changing the V1 default', () => {
  const harness = source(emulatorHarnessPath);
  assert.match(harness, /CATALOG_OUTBOX_SCHEMA_VERSION \|\| '1'/);
  assert.match(harness, /!\['1', '2'\]\.includes\(OUTBOX_SCHEMA_VERSION\)/);
  assert.match(harness, /schemaVersion: Number\(OUTBOX_SCHEMA_VERSION\)/);
  assert.match(harness, /OUTBOX_SCHEMA_VERSION === '2'/);
  assert.match(harness, /workerId: null, leaseToken: null, leaseExpiresAt: null, nextAttemptAt: null/);
  assert.match(harness, /FIRESTORE_RULES_CANDIDATE_PATH/);
});

test('authenticated Emulator harness captures redacted per-group Rules coverage without raw evaluated values', () => {
  const harness = source(authenticatedHarnessPath);
  assert.match(harness, /async function readRuleCoverage\(/);
  assert.match(harness, /function summarizeRuleCoverage\(/);
  assert.match(harness, /function coverageDelta\(/);
  assert.match(harness, /nodes: delta\.length/);
  assert.doesNotMatch(harness, /console\.log\(JSON\.stringify\(coverage/);
});

test('Emulator harness rejects version-mismatched and inactive Admin authorization states', () => {
  const harness = source(emulatorHarnessPath);
  assert.match(harness, /async function createAdminFixture\(/);
  assert.match(harness, /async function assertAdminWriteDenied\(/);
  assert.match(harness, /Admin claims with a divergent version are rejected/);
  assert.match(harness, /missing, pending and disabled Admin authorization states are rejected/);
  assert.match(harness, /Admin authorization revoked after token issuance rejects the stale token/);
  assert.match(harness, /authorization: \{ pending: true \}/);
  assert.match(harness, /authorization: \{ enabled: false \}/);
  assert.match(harness, /recordVersion: crypto\.randomUUID\(\)/);
  assert.match(harness, /admin_authorizations\/\$\{user\.uid\}/);
  assert.match(harness, /status, 403, `\$\{label\}: invalid Admin state must deny a paired write\.`/);
  assert.match(harness, /establishments\/\$\{establishmentId\}/);
  assert.match(harness, /catalog_outbox\/\$\{operationId\}/);
});

test('Emulator harness covers replay of a previously committed paired operation', () => {
  const harness = source(emulatorHarnessPath);
  assert.match(harness, /a committed operation cannot be replayed to duplicate a source or outbox event/);
  assert.match(harness, /const replay = await pairedCreate\(id, op, adminToken, administrator\.uid\)/);
  assert.match(harness, /assertDocumentAbsent\('catalog_outbox', operationId\)/);
});

test('denied outbox reads assert a Rules denial even when the fixture document is absent', () => {
  const harness = source(emulatorHarnessPath);
  assert.match(harness, /async function assertDocumentAbsent\(collection, id\)/);
  assert.match(harness, /await assertDocumentAbsent\('catalog_outbox', operationId\)/);
  assert.match(harness, /await assertDocumentAbsent\('catalog_outbox', badOp\)/);
  assert.match(harness, /assert\.equal\(await readStatus\(`catalog_outbox\/\$\{op\}`, adminToken\), 403\)/);
});

test('authenticated Emulator harness uses Firebase client SDK for Rules and real Admin SDK token verification', () => {
  const harness = source(authenticatedHarnessPath);
  assert.match(harness, /connectAuthEmulator/);
  assert.match(harness, /connectFirestoreEmulator/);
  assert.match(harness, /deleteDoc\(doc\(adminClient\.db, 'establishments', id\)\)/);
  assert.match(harness, /physical deletion cannot replace a tombstone/);
  assert.match(harness, /writeBatch\(/);
  assert.match(harness, /getDoc\(/);
  assert.match(harness, /getIdToken\(/);
  assert.match(harness, /adminAuth\.verifyIdToken\(/);
  assert.match(harness, /firestore\.hybrid-outbox-candidate\.rules/);
  assert.match(harness, /firestore\.hybrid-outbox-v2-candidate\.rules/);
  assert.doesNotMatch(harness, /\/databases\/\(default\)\/documents:commit/);
  assert.doesNotMatch(harness, /firebase deploy|supabase link|serviceAccountKey\.json/);
});
