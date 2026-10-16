'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');

const EXPECTED = Object.freeze({
  projectId: 'tudo-aqui-macacu',
  releaseName: 'projects/tudo-aqui-macacu/releases/cloud.firestore',
  rulesetName:
    'projects/tudo-aqui-macacu/rulesets/8673e159-262a-41de-9d1c-7aed38f21bac',
  releaseCreateTime: '2026-09-13T03:43:03.572633Z',
  contentSha256:
    '34d0acf0958489b193e737e922a26a38b22138483dc97ec00e75366c40266262',
});

function replaceOnce(source, before, after, description) {
  const first = source.indexOf(before);
  if (first < 0 || source.indexOf(before, first + before.length) >= 0) {
    throw new Error(`Snapshot does not contain one expected ${description} clause.`);
  }
  return source.slice(0, first) + after + source.slice(first + before.length);
}

function loadVerifiedSnapshot(snapshotPath) {
  if (!snapshotPath) throw new Error('Snapshot path is required.');

  let snapshot;
  try {
    snapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));
  } catch {
    throw new Error('Snapshot is missing or is not valid JSON.');
  }

  const file = snapshot.files?.length === 1 ? snapshot.files[0] : null;
  if (
    snapshot.projectId !== EXPECTED.projectId ||
    snapshot.release?.name !== EXPECTED.releaseName ||
    snapshot.release?.rulesetName !== EXPECTED.rulesetName ||
    snapshot.release?.createTime !== EXPECTED.releaseCreateTime ||
    file?.name !== 'firestore.rules' ||
    typeof file.content !== 'string'
  ) {
    throw new Error('Snapshot origin metadata does not match the authorized release.');
  }

  // The wrapper's legacy contentSha256 field uses the old composite convention;
  // the authorized reference is the SHA-256 of the raw UTF-8 Rules content.
  const rawSha256 = crypto.createHash('sha256').update(file.content, 'utf8').digest('hex');
  if (rawSha256 !== EXPECTED.contentSha256) {
    throw new Error('Snapshot raw content SHA-256 does not match the authorized value.');
  }

  return { content: file.content, rawSha256, sourceFile: file.name };
}

function deriveCandidate(source) {
  let candidate = replaceOnce(
    source,
    'allow read: if admin() || resource.data.published == true || resource.data.active == true;',
    'allow read: if admin();',
    'utilities read',
  );

  candidate = replaceOnce(
    candidate,
    "allow read: if collection in ['ads', 'establishments', 'offers', 'coupons', 'alerts', 'routes', 'polls', 'jobs', 'news', 'events', 'links', 'notifications'] && (signedIn() || resource.data.published == true);",
    "allow read: if collection in ['ads', 'establishments', 'offers', 'coupons', 'alerts', 'routes', 'polls', 'jobs', 'news', 'events', 'links', 'notifications'] && (admin() || ((collection != 'establishments' && collection != 'routes' && collection != 'utilities' && collection != 'jobs') && (signedIn() || resource.data.published == true)));",
    'generic read',
  );

  // Replace the generic write clause in its enclosing match only, because the
  // published file has the same Admin clause in other collection matches.
  const genericMatch = "match /{collection}/{document} {";
  const genericStart = candidate.indexOf(genericMatch);
  if (genericStart < 0 || candidate.indexOf(genericMatch, genericStart + genericMatch.length) >= 0) {
    throw new Error('Snapshot does not contain one expected generic match.');
  }
  const genericEnd = candidate.indexOf('\n  }', genericStart);
  if (genericEnd < 0) throw new Error('Generic match block is not structurally recognizable.');
  const genericBlock = candidate.slice(genericStart, genericEnd);
  const oldWrite = 'allow create, update, delete: if admin();';
  if (genericBlock.split(oldWrite).length !== 2) {
    throw new Error('Generic match does not contain one expected write clause.');
  }
  const updatedBlock = genericBlock.replace(
    oldWrite,
    "allow create, update, delete: if collection != 'job_private' && admin();",
  );
  candidate = candidate.slice(0, genericStart) + updatedBlock + candidate.slice(genericEnd);

  return candidate;
}

function verifyCandidate(snapshotPath, candidatePath) {
  if (!candidatePath) throw new Error('Candidate path is required.');
  const snapshot = loadVerifiedSnapshot(snapshotPath);
  let candidate;
  try {
    candidate = fs.readFileSync(candidatePath, 'utf8');
  } catch {
    throw new Error('Candidate file is missing or unreadable.');
  }

  if (candidate !== deriveCandidate(snapshot.content)) {
    throw new Error('Candidate contains changes beyond the authorized Rules transformation.');
  }
  return { rawSha256: snapshot.rawSha256, candidateSha256: crypto.createHash('sha256').update(candidate, 'utf8').digest('hex') };
}

module.exports = { EXPECTED, deriveCandidate, loadVerifiedSnapshot, verifyCandidate };
