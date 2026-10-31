'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

const runner = path.join(__dirname, '../../tools/beta-backend-preflight.mjs');
const node = process.execPath;

test('Beta backend preflight accepts only the explicit Beta project in preflight-only mode', () => {
  const result = spawnSync(node, [runner, '--project', 'macacu-beta-261030-cf4a81', '--preflight-only'],
    { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /no Firebase CLI\/network\/deploy invoked/u);
  assert.match(result.stdout, /listPublicContent/u);
  assert.match(result.stdout, /getPublicContentDetail/u);
  assert.match(result.stdout, /searchPublicContent/u);
  assert.match(result.stdout, /syncBetaSearchEstablishments/u);
  assert.match(result.stdout, /syncBetaSearchRoutes/u);
  assert.match(result.stdout, /syncBetaSearchEvents/u);
  assert.match(result.stdout, /public_content_rate_limits\.expiresAt/u);
  assert.match(result.stdout, /public_content_detail_rate_limits\.expiresAt/u);
  assert.match(result.stdout, /business_search_rate_limits\.expiresAt/u);
  assert.match(result.stdout, /business_search_index/u);
  assert.match(result.stdout, /firestore:indexes,functions:listPublicContent/u);
  assert.match(result.stdout, /--project macacu-beta-261030-cf4a81/u);
  assert.match(result.stdout, /functions\/beta_public_search\.js/u);
  assert.match(result.stdout, /functions\/beta_search_backfill\.js/u);
  assert.match(result.stdout, /business_search_index/u);
  assert.match(result.stdout, /lib\/features\/search\/repositories\/beta_public_search_repository\.dart/u);
});

test('Beta backend preflight rejects missing/wrong project and deployment options', () => {
  for (const args of [
    [],
    ['--project', 'tudo-aqui-macacu', '--preflight-only'],
    ['--project', 'macacu-staging-261022', '--preflight-only'],
    ['--project', 'macacu-beta-261030-cf4a81'],
    ['--project', 'macacu-beta-261030-cf4a81', '--preflight-only', '--deploy'],
  ]) {
    const result = spawnSync(node, [runner, ...args], { encoding: 'utf8' });
    assert.notEqual(result.status, 0, args.join(' '));
    assert.match(result.stderr, /NO-GO/u);
  }
});
