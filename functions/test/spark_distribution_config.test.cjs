const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..', '..');

test('Spark distribution Firebase config selects only the approved Rules file', () => {
  const config = JSON.parse(
    readFileSync(join(root, 'firebase.spark-distribution.json'), 'utf8'),
  );

  assert.deepEqual(config, {
    firestore: { rules: 'firestore.beta.rules' },
  });
  assert.equal(config.functions, undefined);
  assert.equal(config.hosting, undefined);
  assert.equal(config.storage, undefined);
});
