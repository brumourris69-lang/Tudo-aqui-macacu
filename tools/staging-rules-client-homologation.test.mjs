import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  STAGING_RULES_HOMOLOGATION_EXPECTED as expected,
  buildIamPermissionProbeDocument,
  buildIamPermissionProbeUpdate,
  fingerprintFixture,
  isUnchangedOwnedFixture,
  isUnchangedSyntheticUser,
  isIamPermissionProbeDocument,
  assertTemporaryImpersonationGrant,
  assertTemporaryProjectRoleBindings,
  assertImpersonatedAccessToken,
  exchangeFirebaseCliRefreshToken,
  validateIdentityPermissionProbe,
  validateReadOnlyIdentityEnvironment,
  validateStagingRunnerPreflight,
  verifyObservedLiveRelease,
  findBindingsWithPermissions,
  summarizeRulesPublicationAudit,
  summarizeEffectivePublisherBindings,
  summarizeEffectiveIamPolicyResponse,
  assertReleaseSnapshotUnchanged,
} from './staging-rules-client-homologation.mjs';

const now = Date.parse('2026-10-28T18:00:00.000Z');

test('publisher inventory identifies direct publishing and IAM-administration grants', () => {
  const bindings = [
    { role: 'roles/owner', members: ['user:owner@example.test'] },
    { role: 'roles/viewer', members: ['user:reader@example.test'] },
  ];
  const permissionByRole = new Map([
    ['roles/owner', ['resourcemanager.projects.setIamPolicy', 'firebaserules.releases.update']],
    ['roles/viewer', ['resourcemanager.projects.get']],
  ]);
  assert.deepEqual(
    findBindingsWithPermissions(bindings, permissionByRole, ['firebaserules.releases.update']),
    [{ binding: bindings[0], permissions: ['firebaserules.releases.update'] }],
  );
  assert.deepEqual(
    findBindingsWithPermissions(bindings, permissionByRole, ['resourcemanager.projects.setIamPolicy']),
    [{ binding: bindings[0], permissions: ['resourcemanager.projects.setIamPolicy'] }],
  );
});

test('Rules audit summary retains only publication methods and sanitizes client identity', () => {
  assert.deepEqual(summarizeRulesPublicationAudit([
    { timestamp: '2026-10-29T10:00:00Z', protoPayload: {
      serviceName: 'firebaserules.googleapis.com', methodName: 'google.firebaserules.v1.FirestoreRulesService.UpdateRelease',
      resourceName: 'projects/macacu-staging-261022/releases/cloud.firestore',
      authenticationInfo: { principalEmail: 'operator@example.test', userAgent: 'Firebase-Tools/15.32.1' },
    } },
    { timestamp: '2026-10-29T09:00:00Z', protoPayload: {
      methodName: 'google.firestore.v1.Firestore.GetDocument', authenticationInfo: { principalEmail: 'reader@example.test' },
    } },
  ]), [{
    timestamp: '2026-10-29T10:00:00Z',
    methodName: 'google.firebaserules.v1.FirestoreRulesService.UpdateRelease',
    principalEmail: 'operator@example.test',
    delegatedBy: [],
    resourceName: 'projects/macacu-staging-261022/releases/cloud.firestore',
    client: 'firebase-cli',
  }]);
});

test('effective IAM summary distinguishes inherited target policies and group principals', () => {
  assert.deepEqual(summarizeEffectivePublisherBindings([{
    fullResourceName: '//cloudresourcemanager.googleapis.com/projects/672692860147',
    policies: [{
      attachedResource: '//cloudresourcemanager.googleapis.com/folders/123456',
      bindings: [{
        role: 'roles/owner',
        members: ['group:firebase-ops@example.test'],
        permissions: ['firebaserules.releases.update', 'resourcemanager.projects.setIamPolicy'],
      }],
    }],
  }]), [{
    resource: '//cloudresourcemanager.googleapis.com/folders/123456',
    role: 'roles/owner',
    members: ['group:firebase-ops@example.test'],
    permissions: ['firebaserules.releases.update', 'resourcemanager.projects.setIamPolicy'],
    condition: null,
    memberType: 'includes-group',
  }]);
});

test('effective IAM batch summary reports only relevant policy bindings and partial errors', () => {
  assert.deepEqual(summarizeEffectiveIamPolicyResponse({ policyResults: [{
    attachedResource: '//cloudresourcemanager.googleapis.com/organizations/999',
    bindings: [{
      role: 'roles/owner', members: ['user:owner@example.test'],
      permissions: ['firebaserules.releases.update'],
    }],
    errors: [{ code: 7, cause: 'group expansion denied' }],
  }] }), {
    policies: [{
      resource: '//cloudresourcemanager.googleapis.com/organizations/999',
      role: 'roles/owner', members: ['user:owner@example.test'],
      permissions: ['firebaserules.releases.update'], condition: null,
      memberType: 'direct-principals',
    }],
    resultCount: 1,
    unresolved: [{ code: 7, cause: 'group expansion denied' }],
  });
});

test('Release snapshot guard fails closed on third-party changes; runner has no automatic Rules rollback', () => {
  const snapshot = {
    name: expected.releaseName,
    rulesetName: 'projects/macacu-staging-261022/rulesets/candidate-fixture-id',
    createTime: '2026-10-28T14:24:38.111069Z',
    updateTime: '2026-10-29T18:00:00.000Z',
  };
  assert.equal(assertReleaseSnapshotUnchanged({ ...snapshot }, snapshot).ok, true);
  assert.throws(() => assertReleaseSnapshotUnchanged({ ...snapshot, rulesetName: expected.rulesetName }, snapshot));
  assert.throws(() => assertReleaseSnapshotUnchanged({ ...snapshot, updateTime: '2026-10-29T18:01:00.000Z' }, snapshot));
  const source = readFileSync(new URL('./staging-rules-client-homologation.mjs', import.meta.url), 'utf8');
  assert.match(source, /did not attempt Rules rollback/);
  assert.doesNotMatch(source, /firebaserules\.googleapis\.com\/v1\/projects\/[^`]+\/releases\/cloud\.firestore[\s\S]{0,240}?method:\s*['"]PATCH/i);
});
const env = () => ({
  STAGING_HOMOLOGATION_PROJECT_ID: expected.projectId,
  STAGING_HOMOLOGATION_CONFIRM: expected.projectId,
  STAGING_FIREBASE_API_KEY: `AIza${'a'.repeat(35)}`,
  STAGING_FIREBASE_APP_ID: '1:123456789:web:abcdef123456',
});
const credentials = () => ({
  projectId: expected.projectId,
  type: 'impersonated_service_account',
  serviceAccountEmail: expected.serviceAccountEmail,
});
const approval = () => ({
  schemaVersion: 1,
  status: 'APPROVED',
  projectId: expected.projectId,
  databaseId: expected.databaseId,
  projectNumber: '123456789',
  appId: '1:123456789:web:abcdef123456',
  candidateRulesSha256: expected.candidateRulesSha256,
  expectedReleaseName: expected.releaseName,
  expectedRulesetName: 'projects/macacu-staging-261022/rulesets/candidate-fixture-id',
  expectedReleaseCreateTime: '2026-10-28T14:24:38.111069Z',
  expectedReleaseUpdateTime: '2026-10-28T17:55:00.000Z',
  approvedAt: '2026-10-28T17:59:00.000Z',
  expiresAt: '2026-10-28T18:30:00.000Z',
  authorizedActions: [
    'create-delete-synthetic-auth-users',
    'create-delete-synthetic-firestore-documents',
    'run-client-sdk-rules-checks',
  ],
  authEmailPasswordEnabled: true,
  appCheckFirestoreEnforcement: 'UNENFORCED',
  appCheckAuthEnforcement: 'UNENFORCED',
});

function mustReject(mutator) {
  const values = { environment: env(), approval: approval(), credentials: credentials() };
  mutator(values);
  assert.throws(() => validateStagingRunnerPreflight({ ...values, now }));
}

test('accepts only explicit staging, synthetic-run approval, and staging impersonation identity', () => {
  assert.equal(validateStagingRunnerPreflight({
    environment: env(), approval: approval(), credentials: credentials(), now,
  }).ok, true);
});

test('rejects production or any other project, database, and non-staging credentials', () => {
  mustReject(({ environment }) => { environment.STAGING_HOMOLOGATION_PROJECT_ID = 'tudo-aqui-macacu'; });
  mustReject(({ approval: value }) => { value.projectId = 'tudo-aqui-macacu'; });
  mustReject(({ approval: value }) => { value.databaseId = '(production)'; });
  mustReject(({ credentials: value }) => { value.projectId = 'tudo-aqui-macacu'; });
  mustReject(({ credentials: value }) => { value.serviceAccountEmail = 'owner@example.com'; });
});

test('rejects Emulator, App Check debug, default-project, proxy, or missing confirmation environments', () => {
  for (const variable of [
    'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_APPCHECK_DEBUG_TOKEN', 'GCLOUD_PROJECT', 'FIREBASE_CONFIG',
    'HTTPS_PROXY', 'ALL_PROXY', 'NODE_TLS_REJECT_UNAUTHORIZED',
    'NODE_EXTRA_CA_CERTS', 'SSL_CERT_FILE', 'GRPC_DEFAULT_SSL_ROOTS_FILE_PATH',
  ]) {
    mustReject(({ environment }) => { environment[variable] = 'unexpected'; });
  }
  mustReject(({ environment }) => { environment.NODE_OPTIONS = '--require=unexpected.js'; });
  mustReject(({ environment }) => { environment.NODE_PATH = 'unexpected'; });
  mustReject(({ environment }) => { delete environment.STAGING_HOMOLOGATION_CONFIRM; });
  mustReject(({ environment }) => { environment.STAGING_HOMOLOGATION_CONFIRM = 'tudo-aqui-macacu'; });
});

test('rejects missing, expired, overlong, or incomplete authorization', () => {
  mustReject(({ approval: value }) => { value.status = 'NOT_APPROVED_TEMPLATE'; });
  mustReject(({ approval: value }) => { value.expiresAt = '2026-10-28T17:59:00.000Z'; });
  mustReject(({ approval: value }) => { value.expiresAt = '2026-10-29T00:00:00.000Z'; });
  mustReject(({ approval: value }) => { value.authorizedActions = []; });
  mustReject(({ approval: value }) => { value.authEmailPasswordEnabled = false; });
  mustReject(({ approval: value }) => { value.appCheckFirestoreEnforcement = 'UNKNOWN'; });
  mustReject(({ approval: value }) => { value.appCheckAuthEnforcement = 'ENFORCED'; });
  mustReject(({ approval: value }) => { value.candidateRulesSha256 = '0'.repeat(64); });
  mustReject(({ approval: value }) => { value.expectedRulesetName = expected.rulesetName; });
  mustReject(({ credentials: value }) => { value.type = 'service_account'; });
});

test('rejects a Release or Ruleset that changed after the approved read snapshot', () => {
  const value = approval();
  const liveRelease = {
    name: value.expectedReleaseName,
    rulesetName: value.expectedRulesetName,
    createTime: value.expectedReleaseCreateTime,
    updateTime: value.expectedReleaseUpdateTime,
  };
  const liveRuleset = {
    name: value.expectedRulesetName,
    sourceSha256: expected.candidateRulesSha256,
  };
  assert.equal(verifyObservedLiveRelease(liveRelease, liveRuleset, value).ok, true);
  assert.throws(() => verifyObservedLiveRelease({ ...liveRelease, updateTime: '2026-10-28T17:56:00Z' }, liveRuleset, value));
  assert.throws(() => verifyObservedLiveRelease({ ...liveRelease, rulesetName: 'projects/macacu-staging-261022/rulesets/third-party' }, liveRuleset, value));
  assert.throws(() => verifyObservedLiveRelease(liveRelease, { ...liveRuleset, sourceSha256: '0'.repeat(64) }, value));
});

test('cleanup recognizes only unchanged fixture data created by this run', () => {
  const runId = 'synthetic-run-id';
  const fixture = { stagingRunId: runId, title: 'fixture', nested: { active: true } };
  const expectedHash = fingerprintFixture(fixture);
  assert.equal(isUnchangedOwnedFixture(runId, { ...fixture }, expectedHash), true);
  assert.equal(isUnchangedOwnedFixture(runId, { ...fixture, title: 'third-party change' }, expectedHash), false);
  assert.equal(isUnchangedOwnedFixture('other-run', fixture, expectedHash), false);
});

test('cleanup refuses changed synthetic users', () => {
  const user = {
    email: 'staging-rules-common+run@example.invalid',
    displayName: 'Synthetic common',
    emailVerified: false,
    disabled: false,
    customClaims: {},
  };
  const expectedUser = { ...user };
  assert.equal(isUnchangedSyntheticUser(user, expectedUser), true);
  assert.equal(isUnchangedSyntheticUser({ ...user, customClaims: { admin: true } }, expectedUser), false);
  assert.equal(isUnchangedSyntheticUser({ ...user, email: 'different@example.invalid' }, expectedUser), false);
});

test('impersonation grant must bind the current CLI principal and expire at the approved deadline', () => {
  const policy = { bindings: [{
    role: 'projects/macacu-staging-261022/roles/stagingServiceAccountTokenMinter',
    members: ['user:operator@example.invalid'],
    condition: { expression: "request.time < timestamp('2026-11-05T19:32:11Z')" },
  }] };
  assert.equal(assertTemporaryImpersonationGrant({
    policy, principalEmail: 'operator@example.invalid', now: Date.parse('2026-10-29T12:00:00Z'),
  }).expiresAt, '2026-11-05T19:32:11Z');
  assert.throws(() => assertTemporaryImpersonationGrant({
    policy, principalEmail: 'other@example.invalid', now: Date.parse('2026-10-29T12:00:00Z'),
  }));
  assert.throws(() => assertTemporaryImpersonationGrant({
    policy, principalEmail: 'operator@example.invalid', now: Date.parse('2026-11-05T19:32:11Z'),
  }));
  assert.throws(() => assertTemporaryImpersonationGrant({
    policy: { bindings: [{ ...policy.bindings[0], condition: { expression: 'true' } }] },
    principalEmail: 'operator@example.invalid', now: Date.parse('2026-10-29T12:00:00Z'),
  }));
});

test('all temporary project roles retain exact service accounts and resource/time conditions', () => {
  const expiry = "request.time < timestamp('2026-11-05T19:32:11Z')";
  const policy = { bindings: [
    {
      role: 'projects/macacu-staging-261022/roles/stagingFirestoreRulesPublisher',
      members: ['serviceAccount:firestore-rules-publisher@macacu-staging-261022.iam.gserviceaccount.com'],
      condition: { expression: expiry },
    },
    {
      role: 'projects/macacu-staging-261022/roles/stagingRulesHomologationApi',
      members: ['serviceAccount:firestore-rules-homologation@macacu-staging-261022.iam.gserviceaccount.com'],
      condition: { expression: expiry },
    },
    {
      role: 'projects/macacu-staging-261022/roles/stagingRulesHomologationFirestore',
      members: ['serviceAccount:firestore-rules-homologation@macacu-staging-261022.iam.gserviceaccount.com'],
      condition: { expression: `${expiry} && resource.name == "projects/macacu-staging-261022/databases/(default)"` },
    },
  ] };
  assert.equal(assertTemporaryProjectRoleBindings({ policy, now: Date.parse('2026-10-29T12:00:00Z') }).ok, true);
  assert.throws(() => assertTemporaryProjectRoleBindings({ policy, now: Date.parse('2026-11-05T19:32:11Z') }));
  assert.throws(() => assertTemporaryProjectRoleBindings({
    policy: { bindings: policy.bindings.slice(0, 2) }, now: Date.parse('2026-10-29T12:00:00Z'),
  }));
  assert.throws(() => assertTemporaryProjectRoleBindings({
    policy: { bindings: policy.bindings.map((b) => b.role.endsWith('HomologationFirestore') ? { ...b, condition: { expression: expiry } } : b) },
    now: Date.parse('2026-10-29T12:00:00Z'),
  }));
});

test('impersonated token is short-lived and cannot outlive the IAM grant', () => {
  const now = Date.parse('2026-10-29T12:00:00Z');
  assert.equal(assertImpersonatedAccessToken({
    response: { accessToken: 'opaque-temporary-token', expireTime: '2026-10-29T12:10:00Z' },
    now,
  }).expiresInSeconds, 600);
  assert.throws(() => assertImpersonatedAccessToken({
    response: { accessToken: '', expireTime: '2026-10-29T12:10:00Z' }, now,
  }));
  assert.throws(() => assertImpersonatedAccessToken({
    response: { accessToken: 'opaque-temporary-token', expireTime: '2026-10-29T12:20:00Z' }, now,
  }));
});

test('identity permission probe requires the dedicated allowlist and explicit denials', () => {
  const granted = ['firebase.projects.get', 'firebaserules.releases.get', 'firebaserules.rulesets.get'];
  assert.equal(validateIdentityPermissionProbe({
    granted, expectedGranted: granted,
    expectedDenied: ['resourcemanager.projects.setIamPolicy'],
  }).ok, true);
  assert.throws(() => validateIdentityPermissionProbe({
    granted: [...granted, 'resourcemanager.projects.setIamPolicy'], expectedGranted: granted,
    expectedDenied: ['resourcemanager.projects.setIamPolicy'],
  }));
  assert.throws(() => validateIdentityPermissionProbe({
    granted: granted.slice(0, 2), expectedGranted: granted,
    expectedDenied: ['resourcemanager.projects.setIamPolicy'],
  }));
});

test('read-only identity mode requires explicit staging and rejects credential fallbacks', () => {
  const environment = {
    STAGING_HOMOLOGATION_PROJECT_ID: expected.projectId,
    STAGING_HOMOLOGATION_CONFIRM: expected.projectId,
  };
  assert.equal(validateReadOnlyIdentityEnvironment(environment).ok, true);
  assert.throws(() => validateReadOnlyIdentityEnvironment({
    ...environment, STAGING_HOMOLOGATION_PROJECT_ID: 'tudo-aqui-macacu',
  }));
  assert.throws(() => validateReadOnlyIdentityEnvironment({
    ...environment, GOOGLE_APPLICATION_CREDENTIALS: 'unexpected.json',
  }));
});

test('Firebase CLI OAuth refresh uses an in-memory HTTPS form exchange and sanitizes failures', async () => {
  let request;
  const token = await exchangeFirebaseCliRefreshToken({
    apiLibrary: { clientId: () => 'public-client-id', clientSecret: () => 'oauth-client-secret' },
    refreshToken: 'synthetic-refresh-token',
    fetchImpl: async (url, options) => {
      request = { url: String(url), options };
      return { ok: true, json: async () => ({ access_token: 'synthetic-access-token' }) };
    },
  });
  const body = new URLSearchParams(request.options.body);
  assert.equal(request.url, 'https://www.googleapis.com/oauth2/v3/token');
  assert.equal(request.options.method, 'POST');
  assert.equal(request.options.redirect, 'error');
  assert.equal(body.get('refresh_token'), 'synthetic-refresh-token');
  assert.equal(token, 'synthetic-access-token');

  await assert.rejects(() => exchangeFirebaseCliRefreshToken({
    apiLibrary: { clientId: () => 'public-client-id', clientSecret: () => 'oauth-client-secret' },
    refreshToken: 'synthetic-refresh-token',
    fetchImpl: async () => ({ ok: false, status: 401, json: async () => ({ error_description: 'sensitive response' }) }),
  }), (error) => !error.message.includes('sensitive response') && !error.message.includes('synthetic-refresh-token'));
});

test('single IAM probe fixture is synthetic and cleanup accepts only its exact fingerprint', () => {
  const runId = '12345678-1234-4234-8234-123456789abc';
  const value = buildIamPermissionProbeDocument(runId, '2026-10-29T12:00:00.000Z');
  const doc = { fields: {
    runId: { stringValue: value.runId },
    purpose: { stringValue: value.purpose },
    synthetic: { booleanValue: value.synthetic },
    createdAt: { timestampValue: value.createdAt },
  } };
  const fingerprint = fingerprintFixture(value);
  assert.equal(isIamPermissionProbeDocument(doc, value, fingerprint), true);
  assert.equal(isIamPermissionProbeDocument({ fields: { ...doc.fields, extra: { stringValue: 'other' } } }, value, fingerprint), false);
  assert.equal(isIamPermissionProbeDocument({ fields: { ...doc.fields, purpose: { stringValue: 'changed' } } }, value, fingerprint), false);
  const updated = { ...value, ...buildIamPermissionProbeUpdate(runId) };
  const updatedDoc = { fields: {
    ...doc.fields,
    updateMarker: { stringValue: updated.updateMarker },
    revision: { integerValue: String(updated.revision) },
  } };
  assert.equal(isIamPermissionProbeDocument(updatedDoc, updated, fingerprintFixture(updated)), true);
  assert.equal(isIamPermissionProbeDocument(updatedDoc, value, fingerprint), false);
});
