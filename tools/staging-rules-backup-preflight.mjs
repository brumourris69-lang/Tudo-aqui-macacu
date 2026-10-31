import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

export const STAGING_RULES_BACKUP_EXPECTED = Object.freeze({
  projectId: 'macacu-staging-261022',
  databaseId: '(default)',
  releaseName: 'projects/macacu-staging-261022/releases/cloud.firestore',
  rulesetName:
    'projects/macacu-staging-261022/rulesets/5c2d69e4-283a-444b-93f1-9e2204e095f5',
  releaseCreateTime: '2026-10-28T14:24:38.111069Z',
  releaseUpdateTime: '2026-10-28T14:24:38.111069Z',
  rulesetCreateTime: '2026-10-28T14:24:35.703989Z',
  sourceName: 'firestore.rules',
  backupFile:
    'macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.rules',
  byteLength: 163,
  sha256: 'ecf30f940747dcc3c5ba4993093e9a11ac9fc5df7e14b2a1512d2446923d84eb',
});

function requireEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(`Staging Rules backup mismatch: ${label}`);
  }
}

export function verifyStagingRulesBackup(metadata, sourceBytes) {
  const expected = STAGING_RULES_BACKUP_EXPECTED;
  requireEqual(metadata?.schemaVersion, 1, 'metadata schema');
  requireEqual(metadata?.projectId, expected.projectId, 'project ID');
  requireEqual(metadata?.databaseId, expected.databaseId, 'database ID');
  requireEqual(metadata?.release?.name, expected.releaseName, 'Release name');
  requireEqual(metadata?.release?.rulesetName, expected.rulesetName, 'Release Ruleset');
  requireEqual(metadata?.release?.createTime, expected.releaseCreateTime, 'Release create time');
  requireEqual(metadata?.release?.updateTime, expected.releaseUpdateTime, 'Release update time');
  requireEqual(metadata?.ruleset?.name, expected.rulesetName, 'Ruleset name');
  requireEqual(metadata?.ruleset?.createTime, expected.rulesetCreateTime, 'Ruleset create time');
  requireEqual(metadata?.ruleset?.sourceFileCount, 1, 'Ruleset source file count');
  requireEqual(metadata?.sourceFile?.name, expected.sourceName, 'source filename');
  requireEqual(metadata?.sourceFile?.backupFile, expected.backupFile, 'backup filename');
  requireEqual(metadata?.sourceFile?.byteLength, expected.byteLength, 'metadata byte length');
  requireEqual(metadata?.sourceFile?.sha256, expected.sha256, 'metadata SHA-256');
  if (!Buffer.isBuffer(sourceBytes)) {
    throw new Error('Staging Rules backup mismatch: source bytes are not a Buffer');
  }
  requireEqual(sourceBytes.byteLength, expected.byteLength, 'source byte length');
  const actualHash = createHash('sha256').update(sourceBytes).digest('hex');
  requireEqual(actualHash, expected.sha256, 'source SHA-256');
  return {
    ok: true,
    projectId: expected.projectId,
    databaseId: expected.databaseId,
    releaseName: expected.releaseName,
    rulesetName: expected.rulesetName,
    byteLength: sourceBytes.byteLength,
    sha256: actualHash,
  };
}

export function verifyObservedStagingRelease(snapshot) {
  const expected = STAGING_RULES_BACKUP_EXPECTED;
  requireEqual(snapshot?.projectId, expected.projectId, 'observed project ID');
  requireEqual(snapshot?.databaseId, expected.databaseId, 'observed database ID');
  requireEqual(snapshot?.release?.name, expected.releaseName, 'observed Release name');
  requireEqual(snapshot?.release?.rulesetName, expected.rulesetName, 'observed Release Ruleset');
  requireEqual(
    snapshot?.release?.createTime,
    expected.releaseCreateTime,
    'observed Release create time',
  );
  requireEqual(
    snapshot?.release?.updateTime,
    expected.releaseUpdateTime,
    'observed Release update time',
  );
  requireEqual(snapshot?.ruleset?.name, expected.rulesetName, 'observed Ruleset name');
  requireEqual(
    snapshot?.ruleset?.createTime,
    expected.rulesetCreateTime,
    'observed Ruleset create time',
  );
  requireEqual(snapshot?.ruleset?.sourceFileCount, 1, 'observed Ruleset source file count');
  requireEqual(snapshot?.sourceFile?.name, expected.sourceName, 'observed source filename');
  requireEqual(snapshot?.sourceFile?.byteLength, expected.byteLength, 'observed source byte length');
  requireEqual(snapshot?.sourceFile?.sha256, expected.sha256, 'observed Ruleset SHA-256');
  return {
    ok: true,
    projectId: expected.projectId,
    databaseId: expected.databaseId,
    releaseName: expected.releaseName,
    rulesetName: expected.rulesetName,
    sha256: expected.sha256,
  };
}

function runCli() {
  const toolsDir = dirname(fileURLToPath(import.meta.url));
  const repoRoot = resolve(toolsDir, '..');
  const metadataPath = resolve(
    repoRoot,
    'docs/staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.metadata.json',
  );
  const backupDir = resolve(repoRoot, 'docs/staging-backups');
  const metadata = JSON.parse(readFileSync(metadataPath, 'utf8'));
  const filename = metadata?.sourceFile?.backupFile;
  if (typeof filename !== 'string' || basename(filename) !== filename) {
    throw new Error('Staging Rules backup mismatch: unsafe backup filename');
  }
  const backupPath = resolve(backupDir, filename);
  if (dirname(backupPath) !== backupDir) {
    throw new Error('Staging Rules backup mismatch: backup path escaped its directory');
  }
  const sourceBytes = readFileSync(backupPath);
  const evidence = verifyStagingRulesBackup(metadata, sourceBytes);
  process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] === '--verify-release-snapshot') {
      const snapshotFile = process.argv[3];
      if (!snapshotFile || process.argv.length !== 4) {
        throw new Error('Usage: node tools/staging-rules-backup-preflight.mjs --verify-release-snapshot <read-only-get-snapshot.json>');
      }
      const snapshot = JSON.parse(readFileSync(resolve(process.cwd(), snapshotFile), 'utf8'));
      process.stdout.write(`${JSON.stringify(verifyObservedStagingRelease(snapshot), null, 2)}\n`);
    } else if (process.argv.length === 2) {
      runCli();
    } else {
      throw new Error('Usage: node tools/staging-rules-backup-preflight.mjs [--verify-release-snapshot <read-only-get-snapshot.json>]');
    }
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : 'Staging Rules backup verification failed'}\n`);
    process.exitCode = 1;
  }
}
