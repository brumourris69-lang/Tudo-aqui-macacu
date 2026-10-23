'use strict';

const admin = require('firebase-admin');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');
const { provisionSearchLocalAdmin, requireSearchLocalEnvironment } = require('../local_demo_environment');
const { changeAdminClaim } = require('../admin_claim_management');

async function main() {
  const env = process.env;
  const demo = readDemoEmulatorEnvironment(env);
  requireSearchLocalEnvironment(env, env.LOCAL_DEMO_CONFIRM);
  if (!env.LOCAL_DEMO_ADMIN_EMAIL || !env.LOCAL_DEMO_ADMIN_PASSWORD) {
    throw new Error('Provide local Admin credentials through the protected setup prompt.');
  }
  admin.initializeApp({ projectId: demo.project });
  const result = await provisionSearchLocalAdmin({
    auth: admin.auth(),
    db: admin.firestore(),
    env,
    email: env.LOCAL_DEMO_ADMIN_EMAIL,
    password: env.LOCAL_DEMO_ADMIN_PASSWORD,
    confirmation: env.LOCAL_DEMO_CONFIRM,
    grantAdmin: changeAdminClaim,
  });
  console.log(JSON.stringify({ project: result.project, adminVersioned: result.adminVersioned }));
}

main().catch((error) => {
  const email = process.env.LOCAL_DEMO_ADMIN_EMAIL || '';
  const password = process.env.LOCAL_DEMO_ADMIN_PASSWORD || '';
  let message = typeof error?.message === 'string' ? error.message : 'unknown local setup error';
  if (email) message = message.replaceAll(email, '[email]');
  if (password) message = message.replaceAll(password, '[credential]');
  console.error(`Local Admin setup stopped safely: ${message}`);
  process.exitCode = 1;
});
