'use strict';

const admin = require('firebase-admin');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');
const { seedSearchLocalFixtures, requireSearchLocalEnvironment } = require('../local_demo_environment');

async function main() {
  const env = process.env;
  const demo = readDemoEmulatorEnvironment(env);
  requireSearchLocalEnvironment(env, env.LOCAL_DEMO_CONFIRM);
  admin.initializeApp({ projectId: demo.project });
  const result = await seedSearchLocalFixtures({
    db: admin.firestore(), env, confirmation: env.LOCAL_DEMO_CONFIRM,
  });
  console.log(JSON.stringify({ project: demo.project, ...result }));
}

main().catch((error) => {
  console.error(`Local demo fixture setup stopped safely: ${error.message}`);
  process.exitCode = 1;
});
