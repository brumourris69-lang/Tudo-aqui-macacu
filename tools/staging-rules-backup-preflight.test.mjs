import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import {
  STAGING_RULES_BACKUP_EXPECTED as expected,
  verifyStagingRulesBackup,
  verifyObservedStagingRelease,
} from './staging-rules-backup-preflight.mjs';

const metadataPath = new URL('../docs/staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.metadata.json', import.meta.url);
const sourcePath = new URL('../docs/staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.rules', import.meta.url);
const baseline = JSON.parse(readFileSync(metadataPath, 'utf8'));
const source = readFileSync(sourcePath);
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
const altered = (path, value) => {
  const result = structuredClone(baseline);
  let target = result;
  for (const key of path.slice(0, -1)) target = target[key];
  target[path.at(-1)] = value;
  return result;
};

test('accepts only the pinned staging release, Ruleset, and exact backup bytes', () => {
  assert.deepEqual(verifyStagingRulesBackup(baseline, source), {
    ok: true,
    projectId: expected.projectId,
    databaseId: expected.databaseId,
    releaseName: expected.releaseName,
    rulesetName: expected.rulesetName,
    byteLength: expected.byteLength,
    sha256: expected.sha256,
  });
});

test('blocks a different project, database, release, or Ruleset', () => {
  for (const [path, value] of [
    [['projectId'], 'tudo-aqui-macacu'],
    [['databaseId'], 'other-db'],
    [['release', 'name'], 'projects/macacu-staging-261022/releases/other'],
    [['release', 'rulesetName'], 'projects/macacu-staging-261022/rulesets/other'],
    [['ruleset', 'name'], 'projects/macacu-staging-261022/rulesets/other'],
  ]) {
    assert.throws(() => verifyStagingRulesBackup(altered(path, value), source));
  }
});

test('blocks modified source bytes even when metadata is unchanged', () => {
  assert.throws(() => verifyStagingRulesBackup(baseline, Buffer.concat([source, Buffer.from('// changed\n')])));
});

test('blocks a changed digest, byte length, or backup filename', () => {
  for (const [path, value] of [
    [['sourceFile', 'sha256'], '0'.repeat(64)],
    [['sourceFile', 'byteLength'], 1],
    [['sourceFile', 'backupFile'], 'another.rules'],
  ]) {
    assert.throws(() => verifyStagingRulesBackup(altered(path, value), source));
  }
  assert.notEqual(sha256(source), '0'.repeat(64));
});

test('blocks altered release or Ruleset timestamps and source identity metadata', () => {
  for (const [path, value] of [
    [['release', 'createTime'], '2026-10-28T00:00:00Z'],
    [['release', 'updateTime'], '2026-10-28T00:00:00Z'],
    [['ruleset', 'createTime'], '2026-10-28T00:00:00Z'],
    [['sourceFile', 'name'], 'other.rules'],
    [['ruleset', 'sourceFileCount'], 2],
    [['schemaVersion'], 2],
  ]) {
    assert.throws(() => verifyStagingRulesBackup(altered(path, value), source));
  }
});


test('accepts only a fresh observed release snapshot matching the pinned staging target', () => {
  assert.equal(verifyObservedStagingRelease(baseline).ok, true);
});

test('blocks observed project, database, Release, Ruleset, or content mismatch', () => {
  const wrongContent = structuredClone(baseline);
  wrongContent.sourceFile.sha256 = '0'.repeat(64);
  for (const snapshot of [
    altered(['projectId'], 'tudo-aqui-macacu'),
    altered(['databaseId'], '(named-db)'),
    altered(['release', 'name'], 'projects/macacu-staging-261022/releases/other'),
    altered(['release', 'rulesetName'], 'projects/macacu-staging-261022/rulesets/other'),
    altered(['ruleset', 'name'], 'projects/macacu-staging-261022/rulesets/other'),
    wrongContent,
  ]) {
    assert.throws(() => verifyObservedStagingRelease(snapshot));
  }
});
