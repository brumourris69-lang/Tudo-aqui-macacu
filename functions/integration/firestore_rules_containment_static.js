'use strict';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  deriveCandidate,
  loadVerifiedSnapshot,
  verifyCandidate,
} = require('./firestore_rules_containment_contract');

const snapshotPath = process.env.FIRESTORE_RULES_SNAPSHOT_PATH;
const candidatePath = process.env.FIRESTORE_RULES_CANDIDATE_PATH;

function adminHelper(source) {
  return /function\s+admin\s*\(\s*\)\s*\{[\s\S]*?^\s*\}/m.exec(source)?.[0] || '';
}

if (process.argv.includes('--write-candidate')) {
  const snapshot = loadVerifiedSnapshot(snapshotPath);
  if (!candidatePath) throw new Error('FIRESTORE_RULES_CANDIDATE_PATH is required.');
  fs.mkdirSync(path.dirname(candidatePath), { recursive: true });
  fs.writeFileSync(candidatePath, deriveCandidate(snapshot.content), { flag: 'wx' });
  process.stdout.write('Candidate created from verified snapshot; existing files were not overwritten.\n');
} else {
  test('snapshot provenance and raw content integrity are exact', () => {
    const snapshot = loadVerifiedSnapshot(snapshotPath);
    assert.equal(snapshot.sourceFile, 'firestore.rules');
    assert.equal(snapshot.rawSha256, '34d0acf0958489b193e737e922a26a38b22138483dc97ec00e75366c40266262');
  });

  test('candidate contains only the authorized containment changes', () => {
    const result = verifyCandidate(snapshotPath, candidatePath);
    assert.equal(result.rawSha256, '34d0acf0958489b193e737e922a26a38b22138483dc97ec00e75366c40266262');
    assert.match(result.candidateSha256, /^[a-f0-9]{64}$/);
  });

  test('candidate explicitly blocks public target reads and all job_private operations', () => {
    const snapshot = loadVerifiedSnapshot(snapshotPath);
    const candidate = fs.readFileSync(candidatePath, 'utf8');
    assert.ok(adminHelper(snapshot.content) && adminHelper(candidate) === adminHelper(snapshot.content));
    assert.match(candidate, /match \/utilities\/\{document\}\s*\{\s*allow read: if admin\(\);/);
    assert.match(
      candidate,
      /collection != 'establishments' && collection != 'routes' && collection != 'utilities' && collection != 'jobs'/,
    );
    assert.match(candidate, /allow create, update, delete: if collection != 'job_private' && admin\(\);/);
    assert.ok(!/allow read: if collection in \[[^\]]*'job_private'/.test(candidate));
  });
}
