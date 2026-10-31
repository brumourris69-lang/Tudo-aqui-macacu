import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { readFileSync, lstatSync, realpathSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  STAGING_RULES_BACKUP_EXPECTED,
  verifyStagingRulesBackup,
} from './staging-rules-backup-preflight.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const REQUIRE = createRequire(resolve(ROOT, 'functions/package.json'));
const PRODUCTION_IDS = new Set(['tudo-aqui-macacu']);
const REQUIRED_ACTIONS = Object.freeze([
  'create-delete-synthetic-auth-users',
  'create-delete-synthetic-firestore-documents',
  'run-client-sdk-rules-checks',
]);
const EXPECTED_CREDENTIAL_EMAIL =
  'firestore-rules-homologation@macacu-staging-261022.iam.gserviceaccount.com';
const IAM_TOKEN_MINTER_ROLE = 'projects/macacu-staging-261022/roles/stagingServiceAccountTokenMinter';
const IAM_GRANT_EXPIRES_AT = '2026-11-05T19:32:11Z';
const STAGING_PROJECT_NUMBER = '672692860147';
const TEMPORARY_PROJECT_ROLE_BINDINGS = Object.freeze([
  {
    role: 'projects/macacu-staging-261022/roles/stagingFirestoreRulesPublisher',
    member: 'serviceAccount:firestore-rules-publisher@macacu-staging-261022.iam.gserviceaccount.com',
    expression: `request.time < timestamp('${IAM_GRANT_EXPIRES_AT}')`,
  },
  {
    role: 'projects/macacu-staging-261022/roles/stagingRulesHomologationApi',
    member: 'serviceAccount:firestore-rules-homologation@macacu-staging-261022.iam.gserviceaccount.com',
    expression: `request.time < timestamp('${IAM_GRANT_EXPIRES_AT}')`,
  },
  {
    role: 'projects/macacu-staging-261022/roles/stagingRulesHomologationFirestore',
    member: 'serviceAccount:firestore-rules-homologation@macacu-staging-261022.iam.gserviceaccount.com',
    expression: `request.time < timestamp('${IAM_GRANT_EXPIRES_AT}') && resource.name == "projects/macacu-staging-261022/databases/(default)"`,
  },
]);
const READ_ONLY_ALLOWED_PERMISSIONS = Object.freeze([
  'firebase.projects.get',
  'firebaseauth.configs.get',
  'firebaseauth.users.create',
  'firebaseauth.users.delete',
  'firebaseauth.users.get',
  'firebaseauth.users.update',
  'firebaseappcheck.services.get',
  'firebaserules.releases.get',
  'firebaserules.rulesets.get',
]);
const READ_ONLY_DENIED_PERMISSIONS = Object.freeze([
  'firebaseauth.configs.update',
  'firebaseappcheck.services.update',
  'firebaserules.releases.update',
  'firebaserules.rulesets.create',
  'iam.serviceAccounts.getAccessToken',
  'iam.serviceAccounts.signBlob',
  'iam.serviceAccounts.signJwt',
  'iam.serviceAccountKeys.create',
  'iam.serviceAccounts.create',
  'datastore.entities.create',
  'datastore.entities.get',
  'datastore.entities.update',
  'datastore.entities.delete',
  'resourcemanager.projects.setIamPolicy',
]);
const RULES_PUBLICATION_PERMISSIONS = Object.freeze([
  'firebaserules.rulesets.create',
  'firebaserules.releases.update',
  'firebaserules.releases.create',
  'firebaserules.releases.delete',
]);

export function findBindingsWithPermissions(bindings, permissionByRole, requiredPermissions) {
  return (bindings ?? []).flatMap((binding) => {
    const permissions = permissionByRole.get(binding.role) ?? [];
    const matchingPermissions = requiredPermissions.filter((permission) => permissions.includes(permission));
    return matchingPermissions.length ? [{ binding, permissions: matchingPermissions }] : [];
  });
}

const RULES_PUBLICATION_METHOD_PATTERN = /(?:CreateRuleset|UpdateRelease|CreateRelease|DeleteRelease|DeleteRuleset)/i;

function classifyAuditClient(userAgent = '') {
  const value = String(userAgent).toLowerCase();
  if (/firebase-tools|firebase-cli/.test(value)) return 'firebase-cli';
  if (/gcloud|google-cloud-sdk/.test(value)) return 'gcloud';
  if (/mozilla|chrome|safari|firefox/.test(value)) return 'browser-or-console';
  if (value) return 'api-client-or-service';
  return 'unknown';
}

export function summarizeRulesPublicationAudit(entries = []) {
  return entries.flatMap((entry) => {
    const payload = entry?.protoPayload ?? {};
    const methodName = String(payload.methodName ?? '');
    if (!RULES_PUBLICATION_METHOD_PATTERN.test(methodName)) return [];
    const auth = payload.authenticationInfo ?? {};
    const delegation = (auth.serviceAccountDelegationInfo ?? [])
      .map((item) => item.firstPartyPrincipal?.principalEmail ?? item.thirdPartyPrincipal?.principalEmail)
      .filter((email) => typeof email === 'string');
    return [{
      timestamp: entry.timestamp ?? null,
      methodName,
      principalEmail: auth.principalEmail ?? null,
      delegatedBy: delegation,
      resourceName: payload.resourceName ?? null,
      client: classifyAuditClient(auth.userAgent),
    }];
  });
}

export function summarizeEffectivePublisherBindings(policyResults = []) {
  const bindings = [];
  for (const result of policyResults) {
    const resource = result.fullResourceName ?? result.resource ?? null;
    const policies = result.policyInfo ?? result.policies ?? (result.bindings ? [result] : []);
    for (const policy of policies) {
      for (const binding of policy.policy?.bindings ?? policy.bindings ?? []) {
        const permissions = binding.permissionSet?.permissions ?? binding.permissions ?? [];
        const canPublish = RULES_PUBLICATION_PERMISSIONS.filter((permission) => permissions.includes(permission));
        const canChangeIam = permissions.includes('resourcemanager.projects.setIamPolicy');
        if (!canPublish.length && !canChangeIam) continue;
        bindings.push({
          resource: policy.attachedResource ?? resource,
          role: binding.role ?? null,
          members: binding.members ?? [],
          permissions: [...canPublish, ...(canChangeIam ? ['resourcemanager.projects.setIamPolicy'] : [])],
          condition: binding.condition?.expression ?? null,
          memberType: binding.members?.some((member) => member.startsWith('group:')) ? 'includes-group' : 'direct-principals',
        });
      }
    }
  }
  return bindings;
}

export function summarizeEffectiveIamPolicyResponse(response = {}) {
  const results = response.policyResults ?? response.results ?? [];
  return {
    policies: summarizeEffectivePublisherBindings(results),
    resultCount: results.length,
    unresolved: results.flatMap((result) => result.errors ?? []).map((error) => ({
      code: error.code ?? null,
      cause: error.cause ?? null,
    })),
  };
}

export const STAGING_RULES_HOMOLOGATION_EXPECTED = Object.freeze({
  ...STAGING_RULES_BACKUP_EXPECTED,
  projectNumber: STAGING_PROJECT_NUMBER,
  serviceAccountEmail: EXPECTED_CREDENTIAL_EMAIL,
  candidateRulesSha256: 'ddc454413e66107a2087265c3bc9012f7343f90e67a491c353e64e49a75d13b8',
  candidateRulesPath: resolve(ROOT, 'firestore.rules'),
  mirrorRulesPath: resolve(ROOT, 'firestore.claims-local.rules'),
});

function equal(actual, expected, label) {
  if (actual !== expected) throw new Error(`Staging homologation blocked: ${label} mismatch`);
}

function failUnless(condition, label) {
  if (!condition) throw new Error(`Staging homologation blocked: ${label}`);
}

export function assertTemporaryImpersonationGrant({ policy, principalEmail, now = Date.now() }) {
  const expectedExpression = `request.time < timestamp('${IAM_GRANT_EXPIRES_AT}')`;
  const binding = policy?.bindings?.find((candidate) =>
    candidate.role === IAM_TOKEN_MINTER_ROLE &&
    candidate.members?.includes(`user:${principalEmail}`) &&
    candidate.condition?.expression === expectedExpression);
  failUnless(binding, 'current Firebase CLI principal lacks the exact temporary impersonation grant');
  const expiresAt = Date.parse(IAM_GRANT_EXPIRES_AT);
  failUnless(Number.isFinite(expiresAt) && now < expiresAt, 'temporary impersonation grant has expired');
  return { ok: true, expiresAt: IAM_GRANT_EXPIRES_AT };
}

export function assertTemporaryProjectRoleBindings({ policy, now = Date.now() }) {
  failUnless(now < Date.parse(IAM_GRANT_EXPIRES_AT), 'temporary project IAM role bindings have expired');
  for (const expected of TEMPORARY_PROJECT_ROLE_BINDINGS) {
    const matches = (policy?.bindings ?? []).filter((candidate) =>
      candidate.role === expected.role && candidate.members?.includes(expected.member));
    failUnless(matches.length === 1, `temporary binding ${expected.role.split('/').pop()} is missing or duplicated`);
    equal(matches[0].condition?.expression, expected.expression, `temporary binding condition ${expected.role.split('/').pop()}`);
  }
  return { ok: true, expiresAt: IAM_GRANT_EXPIRES_AT };
}

export function assertImpersonatedAccessToken({ response, now = Date.now(), grantExpiresAt = IAM_GRANT_EXPIRES_AT }) {
  const expiresAt = Date.parse(response?.expireTime ?? '');
  const grantDeadline = Date.parse(grantExpiresAt);
  failUnless(typeof response?.accessToken === 'string' && response.accessToken.length > 20, 'IAM Credentials did not return a short-lived access token');
  failUnless(Number.isFinite(expiresAt) && expiresAt > now && expiresAt <= now + 10 * 60 * 1000 + 5000, 'impersonated access token lifetime is invalid');
  failUnless(Number.isFinite(grantDeadline) && expiresAt <= grantDeadline, 'impersonated access token would outlive its IAM grant');
  return { ok: true, expiresAt: new Date(expiresAt).toISOString(), expiresInSeconds: Math.floor((expiresAt - now) / 1000) };
}

export function validateIdentityPermissionProbe({ granted, expectedGranted, expectedDenied }) {
  const actual = new Set(granted ?? []);
  const allowlist = new Set(expectedGranted);
  for (const permission of expectedGranted) {
    failUnless(actual.has(permission), `dedicated identity lacks ${permission}`);
  }
  for (const permission of actual) {
    failUnless(allowlist.has(permission), `dedicated identity has unexpected ${permission}`);
  }
  for (const permission of expectedDenied) {
    failUnless(!actual.has(permission), `dedicated identity unexpectedly has ${permission}`);
  }
  return { ok: true };
}

export function validateReadOnlyIdentityEnvironment(environment) {
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  equal(environment?.STAGING_HOMOLOGATION_PROJECT_ID, expected.projectId, 'explicit staging project ID');
  equal(environment?.STAGING_HOMOLOGATION_CONFIRM, expected.projectId, 'staging confirmation');
  failUnless(!PRODUCTION_IDS.has(environment.STAGING_HOMOLOGATION_PROJECT_ID), 'production project is forbidden');
  for (const key of [
    'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'GOOGLE_APPLICATION_CREDENTIALS',
    'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE', 'CLOUDSDK_AUTH_ACCESS_TOKEN',
    'FIREBASE_TOKEN', 'FIREBASE_CONFIG', 'FIRESTORE_EMULATOR_HOST',
    'FIREBASE_AUTH_EMULATOR_HOST', 'FIREBASE_DATABASE_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST', 'FIREBASE_FUNCTIONS_EMULATOR_HOST',
    'FIREBASE_APPCHECK_DEBUG_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY',
    'http_proxy', 'https_proxy', 'all_proxy', 'NODE_USE_ENV_PROXY',
    'NODE_TLS_REJECT_UNAUTHORIZED', 'NODE_EXTRA_CA_CERTS', 'SSL_CERT_FILE',
    'SSL_CERT_DIR', 'GRPC_DEFAULT_SSL_ROOTS_FILE_PATH', 'NODE_OPTIONS', 'NODE_PATH',
  ]) {
    failUnless(!environment[key], `unexpected ${key} override`);
  }
  return { ok: true, projectId: expected.projectId };
}

function firebaseCliAuthModuleCandidates() {
  const candidates = [];
  try { candidates.push(REQUIRE.resolve('firebase-tools/lib/auth')); } catch {}
  if (process.env.APPDATA) {
    candidates.push(join(process.env.APPDATA, 'npm', 'node_modules', 'firebase-tools', 'lib', 'auth.js'));
  }
  if (process.env.LOCALAPPDATA) {
    const npxRoot = join(process.env.LOCALAPPDATA, 'npm-cache', '_npx');
    try {
      for (const entry of readdirSync(npxRoot, { withFileTypes: true })) {
        if (entry.isDirectory()) candidates.push(join(npxRoot, entry.name, 'node_modules', 'firebase-tools', 'lib', 'auth.js'));
      }
    } catch {}
  }
  return [...new Set(candidates)];
}

function loadFirebaseCliAuthLibrary() {
  for (const authPath of firebaseCliAuthModuleCandidates()) {
    try {
      const packagePath = resolve(dirname(authPath), '..', 'package.json');
      const packageInfo = JSON.parse(readFileSync(packagePath, 'utf8'));
      if (packageInfo.version !== '15.32.1') continue;
      const authLibrary = REQUIRE(authPath);
      if (typeof authLibrary.getGlobalDefaultAccount === 'function' &&
          typeof authLibrary.getAccessToken === 'function') return authLibrary;
    } catch {}
  }
  throw new Error('Staging homologation blocked: authenticated Firebase CLI 15.32.1 library is unavailable');
}

function loadFirebaseCliOAuthClient() {
  const candidates = firebaseCliAuthModuleCandidates().map((authPath) => resolve(dirname(authPath), 'api.js'));
  for (const apiPath of [...new Set(candidates)]) {
    try {
      const packageInfo = JSON.parse(readFileSync(resolve(dirname(apiPath), '..', 'package.json'), 'utf8'));
      if (packageInfo.version !== '15.32.1') continue;
      const api = REQUIRE(apiPath);
      if (typeof api.clientId === 'function' && typeof api.clientSecret === 'function') return api;
    } catch {}
  }
  throw new Error('Staging homologation blocked: Firebase CLI 15.32.1 OAuth client is unavailable');
}

async function safeJsonRequest({ fetchImpl, url, method = 'GET', token, body, expectedHost }) {
  const target = new URL(url);
  equal(target.protocol, 'https:', 'hosted API TLS');
  equal(target.hostname, expectedHost, 'hosted API host');
  const response = await fetchImpl(target, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(20000),
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/json',
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (!response.ok) throw new Error(`Staging API ${method} ${target.hostname}${target.pathname} failed with HTTP ${response.status}`);
  return response.json();
}

export async function getFirebaseCliReadOnlySession({
  authLibrary = loadFirebaseCliAuthLibrary(),
  apiLibrary = loadFirebaseCliOAuthClient(),
  fetchImpl = fetch,
} = {}) {
  const account = await authLibrary.getGlobalDefaultAccount();
  const principalEmail = account?.user?.email ?? account?.email;
  const refreshToken = account?.tokens?.refresh_token;
  failUnless(typeof principalEmail === 'string' && principalEmail.includes('@'), 'authenticated Firebase CLI account is unavailable');
  failUnless(typeof refreshToken === 'string' && refreshToken.length > 20, 'Firebase CLI refresh credential is unavailable');
  const accessToken = await exchangeFirebaseCliRefreshToken({ apiLibrary, refreshToken, fetchImpl });
  return { principalEmail, accessToken };
}

async function executeStagingRulesPublisherInventory() {
  const environment = process.env;
  validateReadOnlyIdentityEnvironment(environment);
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const { principalEmail, accessToken } = await getFirebaseCliReadOnlySession();
  const iamRequest = (url, method = 'GET', body) => safeJsonRequest({
    fetchImpl: fetch,
    url,
    method,
    token: accessToken,
    body,
    expectedHost: 'iam.googleapis.com',
  });
  const projectRequest = (url, method = 'GET', body) => safeJsonRequest({
    fetchImpl: fetch,
    url,
    method,
    token: accessToken,
    body,
    expectedHost: 'cloudresourcemanager.googleapis.com',
  });
  const projectName = `projects/${expected.projectId}`;
  const projectPolicy = await projectRequest(
    `https://cloudresourcemanager.googleapis.com/v1/${projectName}:getIamPolicy`,
    'POST', { options: { requestedPolicyVersion: 3 } },
  );
  const roles = new Map();
  const listedRoles = new Map();
  const roleResolutionSources = new Map();
  const loadListedRole = async (rolePath) => {
    const isProjectRole = rolePath.startsWith('projects/');
    const key = isProjectRole ? 'project-custom' : 'predefined';
    if (!listedRoles.has(key)) {
      const base = isProjectRole
        ? `https://iam.googleapis.com/v1/${projectName}/roles`
        : 'https://iam.googleapis.com/v1/roles';
      let pageToken;
      const found = new Map();
      do {
        const query = new URLSearchParams({ view: 'FULL', pageSize: '1000' });
        if (pageToken) query.set('pageToken', pageToken);
        const page = await iamRequest(`${base}?${query}`);
        for (const role of page.roles ?? []) found.set(role.name, role.includedPermissions ?? []);
        pageToken = page.nextPageToken;
      } while (pageToken);
      listedRoles.set(key, found);
    }
    return listedRoles.get(key).get(rolePath);
  };
  const rolePermissions = async (roleName) => {
    if (!roles.has(roleName)) {
      const rolePath = roleName.startsWith('projects/') || roleName.startsWith('organizations/') || roleName.startsWith('roles/')
        ? roleName
        : `roles/${roleName}`;
      let permissions;
      try {
        const role = await iamRequest(`https://iam.googleapis.com/v1/${rolePath}`);
        permissions = role.includedPermissions ?? [];
        roleResolutionSources.set(roleName, 'IAM REST API');
      } catch (error) {
        if (!String(error?.message).includes('HTTP 404')) throw error;
        permissions = await loadListedRole(rolePath);
        if (Array.isArray(permissions)) {
          roleResolutionSources.set(roleName, 'IAM REST API role listing');
        } else if (roleName === 'roles/firebase.managementServiceAgent' || roleName === 'roles/firebase.sdkAdminServiceAgent') {
          // The official Google role catalog documents this service-agent role
          // as having Firebase Rules publish permissions, though the IAM API
          // does not return its role definition to this caller.
          permissions = RULES_PUBLICATION_PERMISSIONS;
          roleResolutionSources.set(roleName, 'official Google Cloud IAM role catalog; IAM API definition returned 404 and was not listed');
        } else if (roleName === 'roles/firebaserules.system') {
          // Google documents this hidden system role as data-plane support;
          // it is not a Rules publication role.
          permissions = [];
          roleResolutionSources.set(roleName, 'official Google Cloud IAM role catalog describes data-plane support; IAM API definition returned 404 and was not listed');
        } else if (roleName === 'roles/firestore.serviceAgent') {
          permissions = [];
          roleResolutionSources.set(roleName, 'official Google Cloud Firestore role catalog; IAM API definition returned 404 and was not listed');
        } else {
          permissions = [];
          roleResolutionSources.set(roleName, 'unresolved: IAM API returned 404 and role was not listed');
        }
      }
      roles.set(roleName, permissions);
    }
    return roles.get(roleName);
  };
  const bindings = [];
  const projectIamAdminBindings = [];
  const unresolvedProjectRoleBindings = [];
  for (const binding of projectPolicy.bindings ?? []) {
    const permissions = await rolePermissions(binding.role);
    if (roleResolutionSources.get(binding.role)?.startsWith('unresolved:')) {
      unresolvedProjectRoleBindings.push({ role: binding.role, members: binding.members ?? [], condition: binding.condition?.expression ?? null });
    }
    const canPublish = RULES_PUBLICATION_PERMISSIONS.filter((permission) => permissions.includes(permission));
    if (canPublish.length) {
      bindings.push({
        scope: 'project', role: binding.role, members: binding.members ?? [],
        permissions: canPublish,
        condition: binding.condition?.expression ?? null,
      });
    }
    const canChangeProjectIam = permissions.includes('resourcemanager.projects.setIamPolicy');
    if (canChangeProjectIam) {
      projectIamAdminBindings.push({
        scope: 'project', role: binding.role, members: binding.members ?? [],
        permissions: ['resourcemanager.projects.setIamPolicy'],
        condition: binding.condition?.expression ?? null,
      });
    }
  }
  const serviceAccounts = [];
  let pageToken;
  do {
    const query = new URLSearchParams({ pageSize: '100' });
    if (pageToken) query.set('pageToken', pageToken);
    const page = await iamRequest(`https://iam.googleapis.com/v1/${projectName}/serviceAccounts?${query}`);
    serviceAccounts.push(...(page.accounts ?? []));
    pageToken = page.nextPageToken;
  } while (pageToken);

  const impersonationPaths = [];
  const unresolvedServiceAccountBindings = [];
  for (const account of serviceAccounts) {
    const email = account.email;
    const name = account.name;
    if (!email || !name) continue;
    const policy = await iamRequest(`https://iam.googleapis.com/v1/${name}:getIamPolicy`, 'POST', {
      options: { requestedPolicyVersion: 3 },
    });
    const accountBindings = [];
    for (const binding of policy.bindings ?? []) {
      const permissions = await rolePermissions(binding.role);
      if (roleResolutionSources.get(binding.role)?.startsWith('unresolved:')) {
        unresolvedServiceAccountBindings.push({ serviceAccount: email, role: binding.role, members: binding.members ?? [] });
      }
      if (permissions.includes('iam.serviceAccounts.getAccessToken') && binding.members?.length) {
        accountBindings.push({
          role: binding.role,
          members: binding.members,
          condition: binding.condition?.expression ?? null,
        });
      }
    }
    if (accountBindings.length) impersonationPaths.push({ serviceAccount: email, disabled: account.disabled === true, bindings: accountBindings });
  }
  return {
    ok: true,
    mode: 'read-only-rules-publisher-inventory',
    projectId: expected.projectId,
    projectNumber: expected.projectNumber,
    queriedAs: principalEmail,
    directProjectPublisherBindings: bindings,
    projectIamAdministratorBindings: projectIamAdminBindings,
    unresolvedProjectRoleBindings,
    unresolvedServiceAccountBindings,
    inventoryComplete: unresolvedProjectRoleBindings.length === 0 && unresolvedServiceAccountBindings.length === 0,
    roleResolutionSources: Object.fromEntries(roles.keys().map((role) => [role, roleResolutionSources.get(role)])),
    serviceAccountsWithTokenMintBindings: impersonationPaths,
    unresolvedGroupMembers: [...new Set([
      ...bindings.flatMap((binding) => binding.members),
      ...impersonationPaths.flatMap((item) => item.bindings.flatMap((binding) => binding.members)),
    ].filter((member) => member.startsWith('group:')))],
    scopeLimit: 'Project policy and service-account policies only; organization/folder inheritance and group membership are not expanded.',
    rulesPublicationPossibleWithoutRunnerLock: bindings.length > 0 || projectIamAdminBindings.length > 0 ||
      impersonationPaths.some((item) => !item.disabled) || unresolvedProjectRoleBindings.length > 0 ||
      unresolvedServiceAccountBindings.length > 0,
  };
}

async function executeStagingRulesPublicationAudit() {
  validateReadOnlyIdentityEnvironment(process.env);
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const { principalEmail, accessToken } = await getFirebaseCliReadOnlySession();
  const loggingRequest = (url, body) => safeJsonRequest({
    fetchImpl: fetch, url, method: 'POST', token: accessToken, body,
    expectedHost: 'logging.googleapis.com',
  });
  const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const auditFilter = [
    `logName="projects/${expected.projectId}/logs/cloudaudit.googleapis.com%2Factivity"`,
    'protoPayload.serviceName="firebaserules.googleapis.com"',
    `timestamp >= "${since}"`,
  ].join(' AND ');
  const entries = [];
  let pageToken;
  do {
    const page = await loggingRequest('https://logging.googleapis.com/v2/entries:list', {
      resourceNames: [`projects/${expected.projectId}`],
      filter: auditFilter,
      orderBy: 'timestamp desc',
      pageSize: 1000,
      ...(pageToken ? { pageToken } : {}),
    });
    entries.push(...(page.entries ?? []));
    pageToken = page.nextPageToken;
  } while (pageToken);

  const currentRelease = await safeJsonRequest({
    fetchImpl: fetch,
    url: `https://firebaserules.googleapis.com/v1/projects/${expected.projectId}/releases/cloud.firestore`,
    token: accessToken,
    expectedHost: 'firebaserules.googleapis.com',
  });
  return {
    ok: true,
    mode: 'read-only-rules-publication-audit',
    projectId: expected.projectId,
    projectNumber: expected.projectNumber,
    queriedAs: principalEmail,
    auditWindowStart: since,
    auditWindowEnd: new Date().toISOString(),
    matchingAuditEntries: entries.length,
    observedPublicationActivity: summarizeRulesPublicationAudit(entries),
    effectiveIamStatus: 'Not verified by Cloud Asset Policy Analyzer: project-scoped analyzeIamPolicy request returned HTTP 404. No API was enabled and no broader parent policy was queried.',
    release: {
      name: currentRelease.name,
      rulesetName: currentRelease.rulesetName,
      createTime: currentRelease.createTime ?? null,
      updateTime: currentRelease.updateTime ?? null,
    },
    activityVsCapability: 'Audit entries show observed API activity in this 90-day window; IAM analysis shows effective capability, not proof of use.',
  };
}

async function executeStagingEffectiveRulesIamRead() {
  validateReadOnlyIdentityEnvironment(process.env);
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const { principalEmail, accessToken } = await getFirebaseCliReadOnlySession();
  const response = await safeJsonRequest({
    fetchImpl: fetch,
    url: `https://cloudasset.googleapis.com/v1/projects/${expected.projectId}/effectiveIamPolicies:batchGet`,
    method: 'POST',
    token: accessToken,
    body: {
      names: [`//cloudresourcemanager.googleapis.com/projects/${expected.projectNumber}`],
    },
    expectedHost: 'cloudasset.googleapis.com',
  });
  return {
    ok: true,
    mode: 'read-only-staging-effective-iam',
    projectId: expected.projectId,
    queriedAs: principalEmail,
    ...summarizeEffectiveIamPolicyResponse(response),
    groupMembersExpanded: false,
    note: 'Only the effective policy for the staging project resource was requested; no ancestor-wide inventory was requested.',
  };
}

async function executeStagingCloudAssetServiceStatus() {
  validateReadOnlyIdentityEnvironment(process.env);
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const { principalEmail, accessToken } = await getFirebaseCliReadOnlySession();
  const service = await safeJsonRequest({
    fetchImpl: fetch,
    url: `https://serviceusage.googleapis.com/v1/projects/${expected.projectNumber}/services/cloudasset.googleapis.com`,
    token: accessToken,
    expectedHost: 'serviceusage.googleapis.com',
  });
  return {
    ok: true,
    mode: 'read-only-cloud-asset-api-status',
    projectId: expected.projectId,
    queriedAs: principalEmail,
    serviceName: service.name,
    state: service.state ?? null,
  };
}

export async function exchangeFirebaseCliRefreshToken({ apiLibrary, refreshToken, fetchImpl = fetch }) {
  const clientId = apiLibrary.clientId();
  const clientSecret = apiLibrary.clientSecret();
  failUnless(typeof clientId === 'string' && clientId.length > 10, 'Firebase CLI OAuth client ID is unavailable');
  failUnless(typeof clientSecret === 'string' && clientSecret.length > 10, 'Firebase CLI OAuth client secret is unavailable');
  const form = new URLSearchParams({
    refresh_token: refreshToken,
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: 'refresh_token',
    scope: '',
  });
  const response = await fetchImpl('https://www.googleapis.com/oauth2/v3/token', {
    method: 'POST',
    redirect: 'error',
    signal: AbortSignal.timeout(20000),
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  if (!response.ok) throw new Error(`Firebase CLI OAuth refresh failed with HTTP ${response.status}`);
  const result = await response.json();
  failUnless(typeof result?.access_token === 'string' && result.access_token.length > 20, 'Firebase CLI did not return a temporary OAuth access token');
  return result.access_token;
}

export async function createStagingImpersonatedCredential({
  environment = process.env,
  now = Date.now,
  authLibrary = loadFirebaseCliAuthLibrary(),
  apiLibrary = loadFirebaseCliOAuthClient(),
  fetchImpl = fetch,
} = {}) {
  validateReadOnlyIdentityEnvironment(environment);
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const refreshAccount = async () => {
    const account = await authLibrary.getGlobalDefaultAccount();
    const principalEmail = account?.user?.email ?? account?.email;
    const refreshToken = account?.tokens?.refresh_token;
    failUnless(typeof principalEmail === 'string' && principalEmail.includes('@'), 'authenticated Firebase CLI account is unavailable');
    failUnless(typeof refreshToken === 'string' && refreshToken.length > 20, 'Firebase CLI refresh credential is unavailable');
    return { principalEmail, refreshToken };
  };
  const serviceAccountName = `projects/${expected.projectId}/serviceAccounts/${expected.serviceAccountEmail}`;
  const credentialServiceAccountName = `projects/-/serviceAccounts/${expected.serviceAccountEmail}`;
  let cachedToken;
  let cachedExpiry = 0;

  async function mint() {
    const timestamp = now();
    failUnless(timestamp < Date.parse(IAM_GRANT_EXPIRES_AT), 'temporary impersonation grant has expired');
    const { principalEmail, refreshToken } = await refreshAccount();
    const sourceToken = await exchangeFirebaseCliRefreshToken({ apiLibrary, refreshToken, fetchImpl });
    const publisherAccount = `projects/${expected.projectId}/serviceAccounts/firestore-rules-publisher@${expected.projectId}.iam.gserviceaccount.com`;
    const publisherPolicy = await safeJsonRequest({
      fetchImpl,
      url: `https://iam.googleapis.com/v1/${publisherAccount}:getIamPolicy`,
      method: 'POST',
      token: sourceToken,
      body: { options: { requestedPolicyVersion: 3 } },
      expectedHost: 'iam.googleapis.com',
    });
    assertTemporaryImpersonationGrant({ policy: publisherPolicy, principalEmail, now: timestamp });
    const projectPolicy = await safeJsonRequest({
      fetchImpl,
      url: `https://cloudresourcemanager.googleapis.com/v1/projects/${expected.projectId}:getIamPolicy`,
      method: 'POST',
      token: sourceToken,
      body: { options: { requestedPolicyVersion: 3 } },
      expectedHost: 'cloudresourcemanager.googleapis.com',
    });
    assertTemporaryProjectRoleBindings({ policy: projectPolicy, now: timestamp });
    for (const email of [
      `firestore-rules-publisher@${expected.projectId}.iam.gserviceaccount.com`,
      expected.serviceAccountEmail,
    ]) {
      const accountName = `projects/${expected.projectId}/serviceAccounts/${email}`;
      const [accountInfo, userManagedKeys] = await Promise.all([
        safeJsonRequest({
          fetchImpl,
          url: `https://iam.googleapis.com/v1/${accountName}`,
          token: sourceToken,
          expectedHost: 'iam.googleapis.com',
        }),
        safeJsonRequest({
          fetchImpl,
          url: `https://iam.googleapis.com/v1/${accountName}/keys?keyTypes=USER_MANAGED`,
          token: sourceToken,
          expectedHost: 'iam.googleapis.com',
        }),
      ]);
      equal(accountInfo.email, email, 'temporary service account identity');
      failUnless(!accountInfo.disabled, 'temporary service account is disabled');
      equal(userManagedKeys.keys?.length ?? 0, 0, 'temporary service account user-managed key count');
    }
    const policy = await safeJsonRequest({
      fetchImpl,
      url: `https://iam.googleapis.com/v1/${serviceAccountName}:getIamPolicy`,
      method: 'POST',
      token: sourceToken,
      body: { options: { requestedPolicyVersion: 3 } },
      expectedHost: 'iam.googleapis.com',
    });
    assertTemporaryImpersonationGrant({ policy, principalEmail, now: timestamp });
    const impersonation = await safeJsonRequest({
      fetchImpl,
      url: `https://iamcredentials.googleapis.com/v1/${credentialServiceAccountName}:generateAccessToken`,
      method: 'POST',
      token: sourceToken,
      body: {
        scope: ['https://www.googleapis.com/auth/cloud-platform'],
        lifetime: '600s',
      },
      expectedHost: 'iamcredentials.googleapis.com',
    });
    const tokenEvidence = assertImpersonatedAccessToken({
      response: impersonation,
      now: timestamp,
    });
    cachedToken = impersonation.accessToken;
    cachedExpiry = Date.parse(tokenEvidence.expiresAt);
  }

  await mint();
  const credential = {
    async getAccessToken() {
      const timestamp = now();
      failUnless(timestamp < Date.parse(IAM_GRANT_EXPIRES_AT), 'temporary impersonation grant has expired');
      if (!cachedToken || cachedExpiry - timestamp <= 60_000) await mint();
      return {
        access_token: cachedToken,
        expires_in: Math.floor((cachedExpiry - timestamp) / 1000),
      };
    },
  };
  return {
    credential,
    serviceAccountEmail: expected.serviceAccountEmail,
    projectId: expected.projectId,
    grantExpiresAt: IAM_GRANT_EXPIRES_AT,
    temporaryBindingsVerified: true,
    tokenExpiresAt: new Date(cachedExpiry).toISOString(),
  };
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function normalizeFixtureValue(value) {
  if (value instanceof Date) return { $timestamp: value.toISOString() };
  if (value && typeof value.toDate === 'function') return { $timestamp: value.toDate().toISOString() };
  if (Array.isArray(value)) return value.map(normalizeFixtureValue);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, normalizeFixtureValue(value[key])]),
    );
  }
  return value;
}

export function fingerprintFixture(value) {
  return sha256(Buffer.from(JSON.stringify(normalizeFixtureValue(value)), 'utf8'));
}

export function buildIamPermissionProbeDocument(runId, createdAt = new Date()) {
  failUnless(/^[a-f0-9-]{36}$/.test(runId), 'IAM probe run ID must be a UUID');
  return {
    runId,
    purpose: 'temporary synthetic IAM permission check',
    synthetic: true,
    createdAt: new Date(createdAt).toISOString(),
  };
}

export function buildIamPermissionProbeUpdate(runId) {
  failUnless(/^[a-f0-9-]{36}$/.test(runId), 'IAM probe update run ID must be a UUID');
  return { updateMarker: `iam-probe-updated-${runId}`, revision: 2 };
}

export function isIamPermissionProbeDocument(document, expected, expectedFingerprint) {
  const fields = document?.fields;
  if (!fields || Object.keys(fields).sort().join(',') !== Object.keys(expected).sort().join(',')) return false;
  const actual = {};
  for (const [key, value] of Object.entries(expected)) {
    if (key === 'createdAt' && typeof value === 'string') actual[key] = fields[key]?.timestampValue;
    else if (typeof value === 'string') actual[key] = fields[key]?.stringValue;
    else if (typeof value === 'boolean') actual[key] = fields[key]?.booleanValue;
    else if (Number.isSafeInteger(value)) actual[key] = Number(fields[key]?.integerValue);
    else return false;
  }
  return fingerprintFixture(actual) === expectedFingerprint && fingerprintFixture(expected) === expectedFingerprint;
}

export function isUnchangedOwnedFixture(runId, data, expectedFingerprint) {
  return data?.stagingRunId === runId && fingerprintFixture(data) === expectedFingerprint;
}

export function isUnchangedSyntheticUser(user, expected) {
  return user?.email === expected.email &&
    user.email.endsWith('@example.invalid') &&
    user.displayName === expected.displayName &&
    user.emailVerified === expected.emailVerified &&
    user.disabled === expected.disabled &&
    fingerprintFixture(user.customClaims ?? {}) === fingerprintFixture(expected.customClaims);
}

export function verifyObservedLiveRelease(release, ruleset, approval) {
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  equal(release?.name, expected.releaseName, 'active Release name');
  equal(release?.rulesetName, approval?.expectedRulesetName, 'active Release Ruleset');
  equal(release?.createTime, approval?.expectedReleaseCreateTime, 'active Release create time');
  equal(release?.updateTime, approval?.expectedReleaseUpdateTime, 'active Release update time');
  equal(ruleset?.name, approval?.expectedRulesetName, 'Ruleset resource name');
  equal(ruleset?.sourceSha256, expected.candidateRulesSha256, 'active Ruleset content hash');
  return { ok: true, releaseName: release.name, rulesetName: ruleset.name, sha256: ruleset.sourceSha256 };
}

export function assertReleaseSnapshotUnchanged(actual, expected) {
  equal(actual?.name, expected?.name, 'Firestore Release name changed');
  equal(actual?.rulesetName, expected?.rulesetName, 'Firestore Release Ruleset changed');
  equal(actual?.createTime, expected?.createTime, 'Firestore Release creation timestamp changed');
  equal(actual?.updateTime, expected?.updateTime, 'Firestore Release update timestamp changed');
  return { ok: true };
}

export function validateStagingRunnerPreflight({ environment, approval, credentials, now = Date.now() }) {
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  equal(environment?.STAGING_HOMOLOGATION_PROJECT_ID, expected.projectId, 'explicit project ID');
  equal(environment?.STAGING_HOMOLOGATION_CONFIRM, expected.projectId, 'execution confirmation');
  failUnless(!PRODUCTION_IDS.has(environment.STAGING_HOMOLOGATION_PROJECT_ID), 'production project is forbidden');
  failUnless(/^AIza[0-9A-Za-z_-]{30,}$/.test(environment?.STAGING_FIREBASE_API_KEY ?? ''), 'staging Firebase API key is required');
  failUnless(/^1:\d{6,20}:(web|android|ios):[A-Za-z0-9_-]{6,}$/.test(environment?.STAGING_FIREBASE_APP_ID ?? ''), 'registered staging Firebase App ID is required');
  equal(approval?.schemaVersion, 1, 'approval schema version');
  equal(approval?.status, 'APPROVED', 'explicit authorization status');
  equal(approval?.projectId, expected.projectId, 'approval project ID');
  equal(approval?.databaseId, expected.databaseId, 'approval database ID');
  failUnless(/^\d{6,20}$/.test(approval?.projectNumber ?? ''), 'staging project number is required');
  equal(approval?.appId, environment.STAGING_FIREBASE_APP_ID, 'approved app ID');
  failUnless(environment.STAGING_FIREBASE_APP_ID.startsWith(`1:${approval.projectNumber}:`), 'App ID project number');
  equal(approval?.candidateRulesSha256, expected.candidateRulesSha256, 'approved candidate Rules hash');
  equal(approval?.expectedReleaseName, expected.releaseName, 'approved active Release name');
  failUnless(
    typeof approval?.expectedRulesetName === 'string' &&
      /^projects\/macacu-staging-261022\/rulesets\/[A-Za-z0-9-]+$/.test(approval.expectedRulesetName),
    'approved staging Ruleset resource name',
  );
  failUnless(approval.expectedRulesetName !== expected.rulesetName, 'candidate Rules must be published and independently identified before tests');
  failUnless(typeof approval.expectedReleaseCreateTime === 'string' && Number.isFinite(Date.parse(approval.expectedReleaseCreateTime)), 'approved Release create time');
  failUnless(typeof approval.expectedReleaseUpdateTime === 'string' && Number.isFinite(Date.parse(approval.expectedReleaseUpdateTime)), 'approved Release update time');
  const approvedAt = Date.parse(approval?.approvedAt ?? '');
  const expiresAt = Date.parse(approval?.expiresAt ?? '');
  failUnless(Number.isFinite(approvedAt) && Number.isFinite(expiresAt), 'approval timestamps');
  failUnless(approvedAt <= now && expiresAt > now && expiresAt - approvedAt <= 2 * 60 * 60 * 1000, 'approval must be current and expire within two hours');
  for (const action of REQUIRED_ACTIONS) {
    failUnless(approval?.authorizedActions?.includes(action), `approval action ${action}`);
  }
  equal(approval?.authEmailPasswordEnabled, true, 'email/password provider approval');
  equal(approval?.appCheckFirestoreEnforcement, 'UNENFORCED', 'Firestore App Check state approval');
  equal(approval?.appCheckAuthEnforcement, 'UNENFORCED', 'Auth App Check state approval');
  equal(credentials?.projectId, expected.projectId, 'credential project ID');
  equal(credentials?.type, 'impersonated_service_account', 'credential type; long-lived service-account keys are rejected');
  equal(credentials?.serviceAccountEmail, expected.serviceAccountEmail, 'dedicated staging service account identity');

  const blockedEnvironmentKeys = [
    'GCLOUD_PROJECT', 'GOOGLE_CLOUD_PROJECT', 'GOOGLE_APPLICATION_CREDENTIALS',
    'CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE', 'CLOUDSDK_AUTH_ACCESS_TOKEN',
    'FIREBASE_TOKEN', 'FIREBASE_CONFIG',
    'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_DATABASE_EMULATOR_HOST', 'FIREBASE_STORAGE_EMULATOR_HOST',
    'FIREBASE_FUNCTIONS_EMULATOR_HOST', 'FIREBASE_APPCHECK_DEBUG_TOKEN',
    'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY',
    'http_proxy', 'https_proxy', 'all_proxy',
    'NODE_USE_ENV_PROXY', 'NODE_TLS_REJECT_UNAUTHORIZED', 'NODE_EXTRA_CA_CERTS',
    'SSL_CERT_FILE', 'SSL_CERT_DIR', 'GRPC_DEFAULT_SSL_ROOTS_FILE_PATH',
  ];
  for (const key of blockedEnvironmentKeys) {
    failUnless(!environment[key], `unexpected ${key} override`);
  }
  failUnless(!environment.NODE_OPTIONS, 'Node runtime override');
  failUnless(!environment.NODE_PATH, 'Node module search path override');
  return { ok: true, projectId: expected.projectId, databaseId: expected.databaseId };
}

function assertOutsideRepository(pathValue, label) {
  failUnless(isAbsolute(pathValue), `${label} path must be absolute`);
  const suppliedStat = lstatSync(pathValue);
  failUnless(suppliedStat.isFile() && !suppliedStat.isSymbolicLink(), `${label} must be a regular file, not a link`);
  const realPath = realpathSync(pathValue);
  const fromRoot = relative(ROOT, realPath);
  failUnless(fromRoot === '..' || fromRoot.startsWith(`..${sep}`) || isAbsolute(fromRoot), `${label} must be outside the repository`);
  return realPath;
}

function loadApproval(pathValue) {
  const path = assertOutsideRepository(resolve(pathValue), 'approval file');
  failUnless(lstatSync(path).isFile() && !lstatSync(path).isSymbolicLink(), 'approval must be a regular file, not a link');
  return JSON.parse(readFileSync(path, 'utf8'));
}

function verifyApprovalFilePath(env, approvalPath) {
  failUnless(approvalPath, 'an explicit approval file is required for hosted execution');
  failUnless(env.STAGING_HOMOLOGATION_APPROVAL_FILE, 'STAGING_HOMOLOGATION_APPROVAL_FILE must identify the approval file');
  equal(resolve(env.STAGING_HOMOLOGATION_APPROVAL_FILE), resolve(approvalPath), 'approval file path confirmation');
}

async function authenticatedGet(url, credential, expectedHost) {
  const target = new URL(url);
  equal(target.protocol, 'https:', 'hosted endpoint protocol');
  equal(target.hostname, expectedHost, 'hosted endpoint host');
  const tokenResult = await credential.getAccessToken();
  failUnless(typeof tokenResult?.access_token === 'string' && tokenResult.access_token.length > 20, 'staging access token');
  const response = await fetch(target, {
    method: 'GET',
    redirect: 'error',
    signal: AbortSignal.timeout(20000),
    headers: { authorization: `Bearer ${tokenResult.access_token}`, accept: 'application/json' },
  });
  failUnless(response.ok, `read-only preflight GET failed with HTTP ${response.status}`);
  return response.json();
}

async function readHostedState(credential, approval) {
  const project = await authenticatedGet(
    'https://firebase.googleapis.com/v1beta1/projects/macacu-staging-261022',
    credential,
    'firebase.googleapis.com',
  );
  equal(project.projectId, STAGING_RULES_HOMOLOGATION_EXPECTED.projectId, 'hosted Firebase project ID');
  equal(String(project.projectNumber), approval.projectNumber, 'hosted Firebase project number');

  const release = await authenticatedGet(
    'https://firebaserules.googleapis.com/v1/projects/macacu-staging-261022/releases/cloud.firestore',
    credential,
    'firebaserules.googleapis.com',
  );
  equal(release.name, STAGING_RULES_HOMOLOGATION_EXPECTED.releaseName, 'hosted Release name');
  equal(release.rulesetName, approval.expectedRulesetName, 'hosted active Ruleset name');
  equal(release.updateTime, approval.expectedReleaseUpdateTime, 'hosted Release update time');

  const ruleset = await authenticatedGet(
    `https://firebaserules.googleapis.com/v1/${approval.expectedRulesetName}`,
    credential,
    'firebaserules.googleapis.com',
  );
  const files = ruleset?.source?.files;
  failUnless(ruleset.name === approval.expectedRulesetName && Array.isArray(files) && files.length === 1, 'hosted Ruleset structure');
  equal(files[0]?.name, 'firestore.rules', 'hosted Rules source filename');
  failUnless(typeof files[0]?.content === 'string', 'hosted Rules source content');
  const liveRuleset = { name: ruleset.name, sourceSha256: sha256(Buffer.from(files[0].content, 'utf8')) };
  verifyObservedLiveRelease(release, liveRuleset, approval);

  const authConfig = await authenticatedGet(
    'https://identitytoolkit.googleapis.com/admin/v2/projects/macacu-staging-261022/config',
    credential,
    'identitytoolkit.googleapis.com',
  );
  equal(authConfig.name, 'projects/macacu-staging-261022/config', 'hosted Auth config project');
  equal(authConfig.signIn?.email?.enabled, true, 'hosted email/password provider enabled');
  equal(authConfig.signIn?.email?.passwordRequired, true, 'hosted password sign-in enabled');

  for (const serviceId of ['firestore.googleapis.com', 'identitytoolkit.googleapis.com']) {
    const service = await authenticatedGet(
      `https://firebaseappcheck.googleapis.com/v1/projects/${approval.projectNumber}/services/${serviceId}`,
      credential,
      'firebaseappcheck.googleapis.com',
    );
    equal(service.name, `projects/${approval.projectNumber}/services/${serviceId}`, `App Check ${serviceId} resource`);
    equal(service.enforcementMode, 'UNENFORCED', `App Check ${serviceId} enforcement`);
  }
  return { project, release, ruleset };
}

async function executeReadOnlyIdentityCheck() {
  const environment = process.env;
  validateReadOnlyIdentityEnvironment(environment);
  const localState = verifyLocalSources();
  const impersonation = await createStagingImpersonatedCredential({ environment });
  const credential = impersonation.credential;
  const token = await credential.getAccessToken();
  const permissionProbe = await safeJsonRequest({
    fetchImpl: fetch,
    url: `https://cloudresourcemanager.googleapis.com/v1/projects/${STAGING_RULES_HOMOLOGATION_EXPECTED.projectId}:testIamPermissions`,
    method: 'POST',
    token: token.access_token,
    body: { permissions: [...READ_ONLY_ALLOWED_PERMISSIONS, ...READ_ONLY_DENIED_PERMISSIONS] },
    expectedHost: 'cloudresourcemanager.googleapis.com',
  });
  validateIdentityPermissionProbe({
    granted: permissionProbe.permissions ?? [],
    expectedGranted: READ_ONLY_ALLOWED_PERMISSIONS,
    expectedDenied: READ_ONLY_DENIED_PERMISSIONS,
  });

  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const project = await authenticatedGet(
    `https://firebase.googleapis.com/v1beta1/projects/${expected.projectId}`,
    credential,
    'firebase.googleapis.com',
  );
  equal(project.projectId, expected.projectId, 'impersonated Firebase project ID');
  equal(String(project.projectNumber), expected.projectNumber, 'impersonated Firebase project number');

  const authConfig = await authenticatedGet(
    `https://identitytoolkit.googleapis.com/admin/v2/projects/${expected.projectId}/config`,
    credential,
    'identitytoolkit.googleapis.com',
  );
  equal(authConfig.name, `projects/${expected.projectNumber}/config`, 'impersonated Auth config project number');

  const release = await authenticatedGet(
    `https://firebaserules.googleapis.com/v1/${expected.releaseName}`,
    credential,
    'firebaserules.googleapis.com',
  );
  equal(release.name, expected.releaseName, 'read-only active Firestore Release');
  equal(release.rulesetName, expected.rulesetName, 'read-only active original Ruleset');
  equal(release.createTime, expected.releaseCreateTime, 'read-only active Release creation time');
  equal(release.updateTime, expected.releaseUpdateTime, 'read-only active Release update time');

  const ruleset = await authenticatedGet(
    `https://firebaserules.googleapis.com/v1/${expected.rulesetName}`,
    credential,
    'firebaserules.googleapis.com',
  );
  const files = ruleset?.source?.files;
  failUnless(ruleset.name === expected.rulesetName && Array.isArray(files) && files.length === 1, 'original Ruleset structure');
  equal(files[0]?.name, expected.sourceName, 'original Ruleset source filename');
  failUnless(typeof files[0]?.content === 'string', 'original Ruleset source content');
  const sourceBytes = Buffer.from(files[0].content, 'utf8');
  const remoteHash = sha256(sourceBytes);
  equal(remoteHash, localState.backupSha256, 'impersonated original Ruleset backup hash');

  return {
    ok: true,
    mode: 'read-only-identity-check',
    projectId: expected.projectId,
    projectNumber: expected.projectNumber,
    identity: impersonation.serviceAccountEmail,
    emailPasswordEnabled: authConfig.signIn?.email?.enabled === true,
    grantExpiresAt: impersonation.grantExpiresAt,
    tokenExpiresAt: impersonation.tokenExpiresAt,
    temporaryBindingsVerified: impersonation.temporaryBindingsVerified,
    allowedPermissions: READ_ONLY_ALLOWED_PERMISSIONS,
    deniedPermissions: READ_ONLY_DENIED_PERMISSIONS,
    firestoreRelease: release.name,
    activeRuleset: ruleset.name,
    originalRulesetSha256: remoteHash,
    candidateSha256: localState.candidateSha256,
    hostedWrites: false,
  };
}

async function firestoreProbeRequest({ method, url, credential, body }) {
  const target = new URL(url);
  equal(target.protocol, 'https:', 'Firestore probe TLS');
  equal(target.hostname, 'firestore.googleapis.com', 'Firestore probe host');
  const access = await credential.getAccessToken();
  const response = await fetch(target, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(20000),
    headers: {
      authorization: `Bearer ${access.access_token}`,
      accept: 'application/json',
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  if (method === 'GET' && response.status === 404) return null;
  if (!response.ok) throw new Error(`Firestore IAM probe ${method} failed with HTTP ${response.status}`);
  if (method === 'DELETE' || response.status === 204) return { ok: true };
  return response.json();
}

async function executeFirestoreIamPermissionCheck() {
  const environment = process.env;
  validateReadOnlyIdentityEnvironment(environment);
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const localState = verifyLocalSources();
  const impersonation = await createStagingImpersonatedCredential({ environment });
  const credential = impersonation.credential;
  const projectAccess = await credential.getAccessToken();
  const permissionProbe = await safeJsonRequest({
    fetchImpl: fetch,
    url: `https://cloudresourcemanager.googleapis.com/v1/projects/${expected.projectId}:testIamPermissions`,
    method: 'POST',
    token: projectAccess.access_token,
    body: { permissions: [...READ_ONLY_ALLOWED_PERMISSIONS, ...READ_ONLY_DENIED_PERMISSIONS] },
    expectedHost: 'cloudresourcemanager.googleapis.com',
  });
  validateIdentityPermissionProbe({
    granted: permissionProbe.permissions ?? [],
    expectedGranted: READ_ONLY_ALLOWED_PERMISSIONS,
    expectedDenied: READ_ONLY_DENIED_PERMISSIONS,
  });

  const project = await authenticatedGet(
    `https://firebase.googleapis.com/v1beta1/projects/${expected.projectId}`,
    credential,
    'firebase.googleapis.com',
  );
  equal(project.projectId, expected.projectId, 'Firestore probe project ID');
  equal(String(project.projectNumber), expected.projectNumber, 'Firestore probe project number');
  const releaseUrl = `https://firebaserules.googleapis.com/v1/${expected.releaseName}`;
  const rulesetUrl = `https://firebaserules.googleapis.com/v1/${expected.rulesetName}`;
  const readOriginalRelease = async () => {
    const release = await authenticatedGet(releaseUrl, credential, 'firebaserules.googleapis.com');
    equal(release.name, expected.releaseName, 'active Firestore Release');
    equal(release.rulesetName, expected.rulesetName, 'original Firestore Ruleset remains active');
    equal(release.createTime, expected.releaseCreateTime, 'active Release create time');
    equal(release.updateTime, expected.releaseUpdateTime, 'active Release update time');
    const ruleset = await authenticatedGet(rulesetUrl, credential, 'firebaserules.googleapis.com');
    const files = ruleset?.source?.files;
    failUnless(ruleset.name === expected.rulesetName && Array.isArray(files) && files.length === 1, 'original Ruleset source shape');
    equal(files[0]?.name, expected.sourceName, 'original Ruleset source name');
    const hash = sha256(Buffer.from(files[0]?.content ?? '', 'utf8'));
    equal(hash, localState.backupSha256, 'original Ruleset and local backup hash');
    return { release, ruleset, hash };
  };
  const beforeRelease = await readOriginalRelease();

  const runId = randomUUID();
  const documentId = `run-${runId}`;
  const collection = 'staging_iam_permission_checks';
  const documentUrl = `https://firestore.googleapis.com/v1/projects/${expected.projectId}/databases/(default)/documents/${collection}/${documentId}`;
  const createUrl = `https://firestore.googleapis.com/v1/projects/${expected.projectId}/databases/(default)/documents/${collection}?documentId=${encodeURIComponent(documentId)}`;
  const data = buildIamPermissionProbeDocument(runId);
  const expectedFingerprint = fingerprintFixture(data);
  const updateData = buildIamPermissionProbeUpdate(runId);
  const updatedData = { ...data, ...updateData };
  const updatedFingerprint = fingerprintFixture(updatedData);
  const firestoreFields = (value) => ({
    runId: { stringValue: value.runId },
    purpose: { stringValue: value.purpose },
    synthetic: { booleanValue: value.synthetic },
    createdAt: { timestampValue: value.createdAt },
  });
  const updatedFields = {
    updateMarker: { stringValue: updateData.updateMarker },
    revision: { integerValue: String(updateData.revision) },
  };
  let createAttempted = false;
  let absenceConfirmedBeforeCreate = false;
  let createdAndRead = false;
  let updateSucceeded = false;
  let cleanupComplete = false;
  let pendingFailure;

  try {
    const existing = await firestoreProbeRequest({ method: 'GET', url: documentUrl, credential });
    failUnless(existing === null, 'exclusive synthetic document ID already exists; no write attempted');
    absenceConfirmedBeforeCreate = true;
    createAttempted = true;
    await firestoreProbeRequest({
      method: 'POST', url: createUrl, credential,
      body: { fields: firestoreFields(data) },
    });
    const observed = await firestoreProbeRequest({ method: 'GET', url: documentUrl, credential });
    failUnless(isIamPermissionProbeDocument(observed, data, expectedFingerprint), 'created Firestore document did not exactly match the synthetic fixture');
    createdAndRead = true;
    const updateMask = new URLSearchParams();
    updateMask.append('updateMask.fieldPaths', 'updateMarker');
    updateMask.append('updateMask.fieldPaths', 'revision');
    await firestoreProbeRequest({
      method: 'PATCH', url: `${documentUrl}?${updateMask.toString()}`, credential,
      body: { fields: updatedFields },
    });
    const updated = await firestoreProbeRequest({ method: 'GET', url: documentUrl, credential });
    failUnless(isIamPermissionProbeDocument(updated, updatedData, updatedFingerprint), 'updated Firestore document did not exactly match the expected synthetic state');
    updateSucceeded = true;
  } catch (error) {
    pendingFailure = error;
  } finally {
    if (createAttempted) {
      try {
        const current = await firestoreProbeRequest({ method: 'GET', url: documentUrl, credential });
        if (current !== null) {
          failUnless(
            isIamPermissionProbeDocument(current, data, expectedFingerprint) ||
              isIamPermissionProbeDocument(current, updatedData, updatedFingerprint),
            'synthetic document changed; preserving it instead of deleting unknown data',
          );
          await firestoreProbeRequest({ method: 'DELETE', url: documentUrl, credential });
        }
        const remaining = await firestoreProbeRequest({ method: 'GET', url: documentUrl, credential });
        cleanupComplete = remaining === null;
        failUnless(cleanupComplete, 'synthetic document still exists after cleanup');
      } catch (error) {
        if (!pendingFailure) pendingFailure = error;
      }
    } else {
      cleanupComplete = absenceConfirmedBeforeCreate;
    }
  }

  const afterRelease = await readOriginalRelease();
  equal(afterRelease.release.rulesetName, beforeRelease.release.rulesetName, 'Release Ruleset changed during IAM probe');
  equal(afterRelease.release.updateTime, beforeRelease.release.updateTime, 'Release changed during IAM probe');
  if (pendingFailure) throw new Error(`Firestore IAM probe failed for ${collection}/${documentId}; cleanup ${cleanupComplete ? 'confirmed' : 'not confirmed or document was pre-existing and preserved'}: ${pendingFailure.message}`);

  return {
    ok: true,
    mode: 'single-document-firestore-iam-probe',
    projectId: expected.projectId,
    databaseId: expected.databaseId,
    identity: impersonation.serviceAccountEmail,
    temporaryIamBindingsVerified: impersonation.temporaryBindingsVerified,
    grantExpiresAt: impersonation.grantExpiresAt,
    activeRuleset: afterRelease.release.rulesetName,
    rulesetBackupSha256: afterRelease.hash,
    fixturePath: `${collection}/${documentId}`,
    createAndReadSucceeded: createdAndRead,
    updateAndReadSucceeded: updateSucceeded,
    deleteConfirmed: cleanupComplete,
    projectScopeDeniedPermissions: READ_ONLY_DENIED_PERMISSIONS,
    note: 'Firestore REST OAuth operations validate IAM and can bypass Firestore Rules; no Rules authorization is inferred.',
    hostedWrites: true,
    hostedDocumentsCreated: 1,
    hostedDocumentsRemaining: 0,
  };
}

function verifyLocalSources() {
  const expected = STAGING_RULES_HOMOLOGATION_EXPECTED;
  const candidate = readFileSync(expected.candidateRulesPath);
  const mirror = readFileSync(expected.mirrorRulesPath);
  equal(sha256(candidate), expected.candidateRulesSha256, 'local approved candidate hash');
  equal(sha256(mirror), expected.candidateRulesSha256, 'local Rules mirror hash');
  failUnless(candidate.equals(mirror), 'candidate and tested mirror must be byte-identical');
  const manifest = JSON.parse(readFileSync(resolve(ROOT, 'tools/staging-rules-preflight.json'), 'utf8'));
  equal(manifest.stagingProjectId, expected.projectId, 'local preflight staging target');
  equal(manifest.testProjectId, 'demo-universal-search', 'local preflight demo project');
  equal(manifest.defaultProjectId, 'tudo-aqui-macacu', 'local default project guard');
  failUnless(manifest.productionProjectIds?.includes('tudo-aqui-macacu'), 'production project denylist');
  equal(manifest.rulesSourcePath, 'firestore.rules', 'local candidate path');
  equal(manifest.rulesMirrorPath, 'firestore.claims-local.rules', 'local Rules mirror path');
  equal(manifest.rulesSha256, expected.candidateRulesSha256, 'local candidate manifest hash');
  const backupMetadataPath = resolve(ROOT, 'docs/staging-backups/macacu-staging-261022-firestore-default-ruleset-5c2d69e4-20261028.metadata.json');
  const backupMetadata = JSON.parse(readFileSync(backupMetadataPath, 'utf8'));
  const backup = readFileSync(resolve(dirname(backupMetadataPath), backupMetadata.sourceFile.backupFile));
  verifyStagingRulesBackup(backupMetadata, backup);
  return { candidateSha256: sha256(candidate), backupSha256: sha256(backup) };
}

function denied(error, label) {
  assert.ok(error, `${label}: expected permission denial`);
  const code = error.code ?? error.message;
  assert.ok(/permission-denied|PERMISSION_DENIED/i.test(String(code)), `${label}: unexpected error code ${String(code)}`);
}

function syntheticIdentity(role, runId) {
  const email = `staging-rules-${role}+${runId}@example.invalid`;
  return { email, password: randomBytes(32).toString('base64url'), displayName: `Synthetic ${role}` };
}

function randomEventData({ published, active, deleted = false, deletedAt = false }, runId) {
  return {
    title: `Fixture ${runId}`,
    name: `Fixture ${runId}`,
    description: 'Dados sintéticos temporários para homologação de Rules.',
    category: 'homologation-fixture',
    published,
    active,
    deleted,
    featured: false,
    stagingRunId: runId,
    ...(deletedAt ? { deletedAt: new Date() } : {}),
  };
}

async function executeClientChecks(approval, credential) {
  const adminAppSdk = REQUIRE('firebase-admin/app');
  const adminAuthSdk = REQUIRE('firebase-admin/auth');
  const adminFirestoreSdk = REQUIRE('firebase-admin/firestore');
  const clientAppSdk = REQUIRE('firebase/app');
  const clientAuthSdk = REQUIRE('firebase/auth');
  const clientFirestoreSdk = REQUIRE('firebase/firestore');
  const runId = randomUUID();
  const adminApp = adminAppSdk.initializeApp({
    credential,
    projectId: STAGING_RULES_HOMOLOGATION_EXPECTED.projectId,
  }, `staging-rules-${runId}`);
  const serverAuth = adminAuthSdk.getAuth(adminApp);
  const serverDb = adminFirestoreSdk.getFirestore(adminApp);
  const createdUsers = new Map();
  const createdPaths = new Map();
  const clientApps = [];
  const clients = {};
  let checks = 0;

  function pass(name) {
    checks += 1;
    process.stdout.write(`PASS ${name}\n`);
  }

  async function expectDenied(operation, name) {
    try {
      await operation();
    } catch (error) {
      denied(error, name);
      pass(name);
      return;
    }
    throw new Error(`Security check failed: ${name} was allowed`);
  }

  async function createSyntheticAccount(role, adminVersion) {
    const identity = syntheticIdentity(role, runId);
    const record = await serverAuth.createUser({
      email: identity.email,
      password: identity.password,
      displayName: identity.displayName,
      disabled: false,
    });
    createdUsers.set(record.uid, {
      email: identity.email,
      displayName: identity.displayName,
      emailVerified: false,
      disabled: false,
      customClaims: adminVersion ? { admin: true, adminVersion } : {},
    });
    if (adminVersion) {
      await serverAuth.setCustomUserClaims(record.uid, { admin: true, adminVersion });
      const path = `admin_authorizations/${record.uid}`;
      const fixture = { enabled: true, pending: false, version: adminVersion, stagingRunId: runId };
      await serverDb.doc(path).create(fixture);
      createdPaths.set(path, fingerprintFixture(fixture));
    }
    const clientApp = clientAppSdk.initializeApp({
      apiKey: process.env.STAGING_FIREBASE_API_KEY,
      appId: process.env.STAGING_FIREBASE_APP_ID,
      authDomain: 'macacu-staging-261022.firebaseapp.com',
      projectId: STAGING_RULES_HOMOLOGATION_EXPECTED.projectId,
    }, `staging-rules-client-${role}-${runId}`);
    clientApps.push(clientApp);
    const auth = clientAuthSdk.getAuth(clientApp);
    const credential = await clientAuthSdk.signInWithEmailAndPassword(auth, identity.email, identity.password);
    if (adminVersion) await clientAuthSdk.getIdToken(credential.user, true);
    clients[role] = { app: clientApp, auth, db: clientFirestoreSdk.getFirestore(clientApp), user: credential.user };
    return record.uid;
  }

  try {
    const adminVersion = `homologation-${runId}`;
    const adminUid = await createSyntheticAccount('admin', adminVersion);
    const commonUid = await createSyntheticAccount('common', null);
    await createSyntheticAccount('other-common', null);
    const revokedVersion = `revoked-${runId}`;
    const revokedUid = await createSyntheticAccount('revoked-admin', revokedVersion);
    const revokedAuthorizationPath = `admin_authorizations/${revokedUid}`;
    await serverDb.doc(revokedAuthorizationPath).update({ enabled: false });
    pass('prepared four synthetic Auth identities and revoked-admin state');

    const publishedId = `staging-${runId}-published`;
    const draftId = `staging-${runId}-draft`;
    const inactiveId = `staging-${runId}-inactive`;
    const deletedId = `staging-${runId}-deleted`;
    const deletedAtId = `staging-${runId}-deleted-at`;
    for (const [id, state] of [
      [publishedId, { published: true, active: true }],
      [draftId, { published: false, active: true }],
      [inactiveId, { published: true, active: false }],
      [deletedId, { published: true, active: true, deleted: true }],
      [deletedAtId, { published: true, active: true, deletedAt: true }],
    ]) {
      const path = `events/${id}`;
      const fixture = randomEventData(state, runId);
      await serverDb.doc(path).create(fixture);
      createdPaths.set(path, fingerprintFixture(fixture));
    }
    const favoritePath = `users/${commonUid}/favorites/event::${publishedId}`;
    const favorite = {
      type: 'event', targetId: publishedId, name: `Fixture ${runId}`, stagingRunId: runId,
    };
    await serverDb.doc(favoritePath).create(favorite);
    createdPaths.set(favoritePath, fingerprintFixture(favorite));
    const businessFavoritePath = `users/${commonUid}/favorites/business::staging-${runId}`;
    const businessFavorite = {
      type: 'business', targetId: `staging-${runId}`, name: `Fixture business ${runId}`, stagingRunId: runId,
    };
    await serverDb.doc(businessFavoritePath).create(businessFavorite);
    createdPaths.set(businessFavoritePath, fingerprintFixture(businessFavorite));

    const adminWriteId = `staging-${runId}-admin-write`;
    const adminWritePath = `events/${adminWriteId}`;
    const adminWriteRef = clientFirestoreSdk.doc(clients.admin.db, adminWritePath);
    const adminWriteFixture = randomEventData({ published: false, active: true }, runId);
    await clientFirestoreSdk.runTransaction(clients.admin.db, async (transaction) => {
      const existing = await transaction.get(adminWriteRef);
      if (existing.exists()) throw new Error('Synthetic event ID collision; refusing to overwrite existing content.');
      transaction.set(adminWriteRef, adminWriteFixture);
    });
    createdPaths.set(adminWritePath, fingerprintFixture(adminWriteFixture));
    pass('authorized Admin client can create a synthetic draft event');
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.admin.db, `events/${draftId}`))).exists(), true);
    pass('authorized Admin can read existing draft content');
    await clientFirestoreSdk.updateDoc(clientFirestoreSdk.doc(clients.admin.db, adminWritePath), {
      published: true,
    });
    createdPaths.set(adminWritePath, fingerprintFixture({ ...adminWriteFixture, published: true }));
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.common.db, adminWritePath))).exists(), true);
    pass('Admin can publish and ordinary user can read the published event');

    const publicDb = clients.common.db;
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(publicDb, `events/${publishedId}`))).exists(), true);
    pass('ordinary user can read a published, active event');
    for (const [id, label] of [
      [draftId, 'ordinary user cannot read a draft event'],
      [inactiveId, 'ordinary user cannot read an inactive event'],
      [deletedId, 'ordinary user cannot read a deleted event'],
      [deletedAtId, 'ordinary user cannot read a tombstoned event'],
    ]) {
      await expectDenied(
        () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(publicDb, `events/${id}`)),
        label,
      );
    }
    await expectDenied(
      () => clientFirestoreSdk.setDoc(clientFirestoreSdk.doc(publicDb, `events/${publishedId}`), randomEventData({ published: true, active: true }, runId)),
      'ordinary user cannot overwrite a public event',
    );
    await expectDenied(
      () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(publicDb, `admin_authorizations/${adminUid}`)),
      'ordinary user cannot read administrative authorization',
    );
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(publicDb, favoritePath))).exists(), true);
    assert.equal((await clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(publicDb, businessFavoritePath))).exists(), true);
    pass('favorite owner can read their own business favorite and event agenda entry');
    await expectDenied(
      () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients['other-common'].db, favoritePath)),
      'another account cannot read this user agenda entry',
    );
    await expectDenied(
      () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients['other-common'].db, businessFavoritePath)),
      'another account cannot read this user business favorite',
    );
    await expectDenied(
      () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.admin.db, favoritePath)),
      'Admin cannot read another account agenda entry',
    );
    await expectDenied(
      () => clientFirestoreSdk.getDoc(clientFirestoreSdk.doc(clients.admin.db, businessFavoritePath)),
      'Admin cannot read another account business favorite',
    );
    await expectDenied(
      () => clientFirestoreSdk.setDoc(clientFirestoreSdk.doc(publicDb, favoritePath), {
        type: 'event', targetId: `forged-${runId}`, stagingRunId: runId,
      }),
      'client cannot mutate favorite or agenda entry directly',
    );

    await expectDenied(
      () => clientFirestoreSdk.updateDoc(clientFirestoreSdk.doc(clients['revoked-admin'].db, `events/${draftId}`), {
        published: true,
      }),
      'revoked Admin cannot publish an event',
    );
    await expectDenied(
      () => clientFirestoreSdk.getDocs(clientFirestoreSdk.collection(publicDb, 'events')),
      'ordinary user cannot list Events bypassing public list policy',
    );
    pass(`all ${checks} SDK-client security assertions passed`);
    return { passed: checks, fixtureCount: createdPaths.size, syntheticAccounts: createdUsers.size };
  } finally {
    const cleanupFailures = [];
    const appResults = await Promise.all([...clientApps].map((app) => clientAppSdk.deleteApp(app).then(() => true, () => false)));
    if (appResults.includes(false)) cleanupFailures.push('client SDK app disposal');
    for (const [path, expectedFingerprint] of createdPaths) {
      try {
        const ref = serverDb.doc(path);
        const current = await ref.get();
        if (!current.exists) continue;
        const currentData = current.data();
        if (!isUnchangedOwnedFixture(runId, currentData, expectedFingerprint)) {
          cleanupFailures.push('a recorded fixture changed after creation; it was preserved');
          continue;
        }
        await ref.delete();
      } catch {
        cleanupFailures.push('recorded synthetic Firestore fixture cleanup');
      }
    }
    for (const [uid, expectedUser] of createdUsers) {
      try {
        const current = await serverAuth.getUser(uid);
        if (!isUnchangedSyntheticUser(current, expectedUser)) {
          cleanupFailures.push('a synthetic Auth account changed identity after creation; it was preserved');
          continue;
        }
        await serverAuth.deleteUser(uid);
      } catch (error) {
        if (error?.code !== 'auth/user-not-found') cleanupFailures.push('created synthetic Auth account cleanup');
      }
    }
    try { await adminAppSdk.deleteApp(adminApp); } catch { cleanupFailures.push('Admin SDK app disposal'); }
    process.stdout.write(`CLEANUP attempted only ${createdUsers.size} unchanged synthetic users and ${createdPaths.size} unchanged recorded fixture paths.\n`);
    if (cleanupFailures.length) throw new Error(`Cleanup incomplete: ${cleanupFailures.join(', ')}`);
  }
}

async function executeHosted(approvalPath) {
  const env = process.env;
  verifyApprovalFilePath(env, approvalPath);
  const approval = loadApproval(approvalPath);
  const localState = verifyLocalSources();
  const credentialDescriptor = {
    projectId: STAGING_RULES_HOMOLOGATION_EXPECTED.projectId,
    type: 'impersonated_service_account',
    serviceAccountEmail: STAGING_RULES_HOMOLOGATION_EXPECTED.serviceAccountEmail,
  };
  validateStagingRunnerPreflight({ environment: env, approval, credentials: credentialDescriptor });
  const impersonation = await createStagingImpersonatedCredential({ environment: env });
  process.stdout.write(`Local checks passed for project ${STAGING_RULES_HOMOLOGATION_EXPECTED.projectId}; candidate ${localState.candidateSha256}; rollback backup ${localState.backupSha256}.\n`);

  const adminAppSdk = REQUIRE('firebase-admin/app');
  const adminApp = adminAppSdk.initializeApp({
    credential: impersonation.credential,
    projectId: STAGING_RULES_HOMOLOGATION_EXPECTED.projectId,
  }, `staging-rules-preflight-${randomUUID()}`);
  try {
    const credential = adminApp.options.credential;
    const hosted = await readHostedState(credential, approval);
    // Re-read the active Release immediately before the first hosted write.
    const releaseAgain = await authenticatedGet(
      'https://firebaserules.googleapis.com/v1/projects/macacu-staging-261022/releases/cloud.firestore',
      credential,
      'firebaserules.googleapis.com',
    );
    assertReleaseSnapshotUnchanged(releaseAgain, hosted.release);
    process.stdout.write('Read-only project, Auth, App Check, Release, Ruleset and content checks passed. Beginning explicitly approved synthetic fixtures.\n');
    let checksResult;
    let checksError;
    try {
      checksResult = await executeClientChecks(approval, impersonation.credential);
    } catch (error) {
      checksError = error;
    }
    const releaseAfterChecks = await authenticatedGet(
      'https://firebaserules.googleapis.com/v1/projects/macacu-staging-261022/releases/cloud.firestore',
      credential,
      'firebaserules.googleapis.com',
    );
    try {
      assertReleaseSnapshotUnchanged(releaseAfterChecks, hosted.release);
    } catch {
      throw new Error('Firestore Release changed during hosted checks; runner stopped after fixture cleanup and did not attempt Rules rollback.');
    }
    if (checksError) throw checksError;
    return { ...checksResult, releaseSnapshotChecks: 3, rulesRollbackAttempted: false };
  } finally {
    await adminAppSdk.deleteApp(adminApp).catch(() => {});
  }
}

async function run() {
  const mode = process.argv[2];
  if (mode === '--preflight' && process.argv.length === 3) {
    const localState = verifyLocalSources();
    process.stdout.write(`${JSON.stringify({
      ok: true,
      mode: 'local-only',
      hostedAccess: false,
      projectId: STAGING_RULES_HOMOLOGATION_EXPECTED.projectId,
      candidateSha256: localState.candidateSha256,
      originalRulesetSha256: localState.backupSha256,
    }, null, 2)}\n`);
    return;
  }
  if (mode === '--identity-check' && process.argv.length === 3) {
    const result = await executeReadOnlyIdentityCheck();
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }
  if (mode === '--firestore-iam-check' && process.argv.length === 3) {
    const result = await executeFirestoreIamPermissionCheck();
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }
  if (mode === '--rules-publisher-inventory' && process.argv.length === 3) {
    const result = await executeStagingRulesPublisherInventory();
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }
  if (mode === '--rules-publication-audit' && process.argv.length === 3) {
    const result = await executeStagingRulesPublicationAudit();
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }
  if (mode === '--effective-rules-iam' && process.argv.length === 3) {
    const result = await executeStagingEffectiveRulesIamRead();
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }
  if (mode === '--cloud-asset-api-status' && process.argv.length === 3) {
    const result = await executeStagingCloudAssetServiceStatus();
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }
  if (mode === '--execute' && process.argv.length === 4) {
    const result = await executeHosted(process.argv[3]);
    process.stdout.write(`${JSON.stringify({ ok: true, ...result }, null, 2)}\n`);
    return;
  }
  throw new Error('Usage: node tools/staging-rules-client-homologation.mjs --preflight | --identity-check | --firestore-iam-check | --rules-publisher-inventory | --rules-publication-audit | --effective-rules-iam | --cloud-asset-api-status | --execute <approved-file-outside-repository.json>');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : 'Staging Rules homologation failed'}\n`);
    process.exitCode = 1;
  });
}
