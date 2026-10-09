const test = require('node:test');
const assert = require('node:assert/strict');
const { randomBytes, createHash } = require('node:crypto');
const { uploadHomeImage, signParameters, MAX_IMAGE_BYTES, HOME_FOLDER } = require('../home_image_upload');

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
const id = '00000000-0000-4000-8000-000000000001';
const auth = { uid: 'admin-test', token: { admin: true } };
const request = (user = auth, data = {}) => ({ auth: user, data: { purpose: 'home_logo', imageBase64: png.toString('base64'), ...data } });
const result = (overrides = {}) => ({
  secure_url: `https://res.cloudinary.com/test-cloud/image/upload/v1/${HOME_FOLDER}/${id}.png`,
  public_id: `${HOME_FOLDER}/${id}`, resource_type: 'image', type: 'upload',
  version: 1, format: 'png', width: 1, height: 1, bytes: png.length, ...overrides,
});

function fixture(overrides = {}) {
  // Ephemeral test material, never a credential or a stored secret.
  const config = { cloudName: 'test-cloud', apiKey: '123456', apiSecret: randomBytes(32).toString('hex'), folderMode: 'dynamic' };
  const calls = [];
  return {
    config, calls,
    options: { authorize: async () => true, getConfig: () => config, uuid: () => id, now: () => 1000,
      fetchImpl: async (url, options) => {
        calls.push({ url, ...options });
        return { ok: true, json: async () => result() };
      }, ...overrides },
  };
}

test('unauthenticated is rejected before config or transport', async () => {
  let accessed = false;
  await assert.rejects(uploadHomeImage(request(null), { getConfig: () => { accessed = true; } }), { code: 'unauthenticated' });
  assert.equal(accessed, false);
});
test('ordinary user and Firestore-like role cannot authorize', async () => {
  const f = fixture();
  for (const token of [{}, { admin: 'true' }, { role: 'user' }, { email: 'legacy-admin@example.com', email_verified: false }]) {
    await assert.rejects(uploadHomeImage(request({ uid: 'user', token }), f.options), { code: 'permission-denied' });
  }
  assert.equal(f.calls.length, 0);
});
test('only admin claim plus current authorization can upload', async () => {
  const f = fixture();
  assert.equal((await uploadHomeImage(request(), f.options)).publicId, `${HOME_FOLDER}/${id}`);
  for (const token of [{ role: 'admin' }, { email: 'legacy-admin@example.com', email_verified: true }]) {
    await assert.rejects(uploadHomeImage(request({ uid: 'admin', token }), f.options), { code: 'permission-denied' });
  }
  assert.equal(f.calls.length, 1);
});

test('client cannot supply folder, identifier, overwrite or resource type', async () => {
  const f = fixture();
  for (const extra of [{ folder: 'other' }, { public_id: 'old' }, { overwrite: true }, { resource_type: 'raw' }, { transformation: 'anything' }, { purpose: 'business' }]) {
    await assert.rejects(uploadHomeImage(request(auth, extra), f.options), { code: 'invalid-argument' });
  }
  assert.equal(f.calls.length, 0);
});
test('format comes from bytes, not the file extension or MIME type', async () => {
  const f = fixture();
  for (const input of [Buffer.from('not an image'), Buffer.from('GIF89a'), Buffer.from('....ftypheic')]) {
    await assert.rejects(uploadHomeImage(request(auth, { imageBase64: input.toString('base64') }), f.options), { code: 'invalid-argument' });
  }
  assert.equal(f.calls.length, 0);
});
test('JPEG and WebP travel only to the image endpoint with allowed formats', async () => {
  for (const input of [Buffer.from([255, 216, 255, 0]), Buffer.from('RIFF1234WEBP')]) {
    const f = fixture();
    await uploadHomeImage(request(auth, { imageBase64: input.toString('base64') }), f.options);
    assert.equal(f.calls[0].body.get('allowed_formats'), 'jpg,png,webp');
    assert.match(f.calls[0].url, /\/image\/upload$/);
  }
});
test('oversize and noncanonical base64 are rejected before transport', async () => {
  const f = fixture();
  for (const encoded of ['', '!!!!', png.toString('base64') + '\n', Buffer.alloc(MAX_IMAGE_BYTES + 1).toString('base64')]) {
    await assert.rejects(uploadHomeImage(request(auth, { imageBase64: encoded }), f.options), { code: 'invalid-argument' });
  }
  assert.equal(f.calls.length, 0);
});
test('signature uses the official sorted SHA256 payload', () => {
  const secret = randomBytes(32).toString('hex');
  const params = { timestamp: '1', public_id: 'new', overwrite: 'false' };
  const expected = createHash('sha256').update(`overwrite=false&public_id=new&timestamp=1${secret}`).digest('hex');
  assert.equal(signParameters(params, secret), expected);
  assert.equal(signParameters({ overwrite: 'false', timestamp: '1', public_id: 'new' }, secret), expected);
});
test('destination is controlled, no overwrite, no credentials in result', async () => {
  const f = fixture();
  const output = await uploadHomeImage(request(), f.options);
  const sent = f.calls[0].body;
  assert.equal(f.calls[0].method, 'POST');
  assert.equal(f.calls.length, 1);
  assert.equal(sent.get('public_id'), `${HOME_FOLDER}/${id}`);
  assert.equal(sent.get('asset_folder'), HOME_FOLDER);
  assert.equal(sent.get('overwrite'), 'false');
  assert.equal(sent.get('timestamp'), '1');
  assert.equal(sent.get('file').name, 'image.png');
  assert.equal(JSON.stringify(output).includes(f.config.apiSecret), false);
  assert.deepEqual(Object.keys(output).sort(), ['bytes', 'format', 'height', 'publicId', 'secureUrl', 'width']);
});
test('fixed folder mode keeps public id namespace without dynamic parameter', async () => {
  const f = fixture();
  f.config.folderMode = 'fixed';
  await uploadHomeImage(request(), f.options);
  assert.equal(f.calls[0].body.get('asset_folder'), null);
  assert.equal(f.calls[0].body.get('public_id'), `${HOME_FOLDER}/${id}`);
});
test('missing configuration fails closed', async () => {
  const f = fixture({ getConfig: () => ({}) });
  await assert.rejects(uploadHomeImage(request(), f.options), { code: 'failed-precondition' });
  assert.equal(f.calls.length, 0);
});
test('transport failure is sanitized and a second explicit request can succeed', async () => {
  const f = fixture({ fetchImpl: async () => { throw new Error('private transport detail'); } });
  await assert.rejects(uploadHomeImage(request(), f.options), { code: 'unavailable', message: 'Não foi possível enviar. Tente novamente.' });
  const retry = fixture();
  assert.equal((await uploadHomeImage(request(), retry.options)).format, 'png');
});
test('provider errors do not disclose response body', async () => {
  const f = fixture({ fetchImpl: async () => ({ ok: false, status: 400 }) });
  await assert.rejects(uploadHomeImage(request(), f.options), { code: 'invalid-argument' });
});
test('invalid provider URL, resource, identifier, size and metadata are rejected', async () => {
  for (const overrides of [{ secure_url: 'http://res.cloudinary.com/file.png' }, { secure_url: 'https://evil.example/file.png' },
    { public_id: 'other' }, { resource_type: 'raw' }, { bytes: MAX_IMAGE_BYTES + 1 }, { format: 'gif' }, { width: 0 }, { type: 'private' }]) {
    const f = fixture({ fetchImpl: async () => ({ ok: true, json: async () => result(overrides) }) });
    await assert.rejects(uploadHomeImage(request(), f.options), { code: 'data-loss' });
  }
});
test('invalid JSON is rejected', async () => {
  const f = fixture({ fetchImpl: async () => ({ ok: true, json: async () => { throw new SyntaxError(); } }) });
  await assert.rejects(uploadHomeImage(request(), f.options), { code: 'data-loss' });
});
