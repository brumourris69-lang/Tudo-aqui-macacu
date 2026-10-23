const assert = require('node:assert/strict');
const http = require('node:http');
const net = require('node:net');
const { once } = require('node:events');
const test = require('node:test');

const {
  createDiagnosticProxy,
  classifyTransportError,
  normalizeMethod,
  normalizeRoute,
  parseProjectArgument,
} = require('./auth-emulator-diagnostic-proxy.cjs');

function listen(server) {
  server.listen(0, '127.0.0.1');
  return once(server, 'listening').then(() => server.address().port);
}

function close(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

function sendRawRequest(port, { method, path, headers, body }) {
  return new Promise((resolve, reject) => {
    const request = http.request({
      host: '127.0.0.1',
      port,
      method,
      path,
      headers,
      agent: false,
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => resolve({
        status: response.statusCode,
        headers: response.rawHeaders,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    request.on('error', reject);
    request.end(body);
  });
}

function sendLiteralRequest(port, { path, headers, body }) {
  return new Promise((resolve, reject) => {
    const socket = net.connect(port, '127.0.0.1');
    const response = [];
    socket.on('connect', () => {
      socket.write(`POST ${path} HTTP/1.1\r\n${headers}\r\n\r\n${body}`);
    });
    socket.on('data', (chunk) => response.push(chunk));
    socket.on('end', () => resolve(Buffer.concat(response).toString('utf8')));
    socket.on('error', reject);
  });
}

function rawHeaderValues(rawHeaders, wantedName) {
  const values = [];
  for (let index = 0; index < rawHeaders.length; index += 2) {
    if (rawHeaders[index].toLowerCase() === wantedName.toLowerCase()) {
      values.push(rawHeaders[index + 1]);
    }
  }
  return values;
}

test('forwards Auth HTTP semantics and logs only sanitized metadata', async (t) => {
  const received = [];
  const events = [];
  const upstream = http.createServer((request, response) => {
    const chunks = [];
    request.on('data', (chunk) => chunks.push(chunk));
    request.on('end', () => {
      received.push({
        method: request.method,
        url: request.url,
        rawHeaders: request.rawHeaders,
        body: Buffer.concat(chunks).toString('utf8'),
      });
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end('{"ok":true,"private":"response-sentinel"}');
    });
  });
  const upstreamPort = await listen(upstream);
  t.after(() => close(upstream));

  const proxy = createDiagnosticProxy({
    listenHost: '127.0.0.1',
    listenPort: 0,
    upstreamHost: '127.0.0.1',
    upstreamPort,
    projectId: 'demo-universal-search',
    logger: (event) => events.push(event),
  });
  proxy.listen(0, '127.0.0.1');
  await once(proxy, 'listening');
  t.after(() => close(proxy));

  const port = proxy.address().port;
  const privateSentinel = 'sensitive-token-sentinel-71d5';
  const body = JSON.stringify({ token: privateSentinel, email: 'private@example.invalid' });
  const requestPath = '/identitytoolkit.googleapis.com/v1/accounts:lookup?key=private-api-key&mode=private-query';
  const incomingHeaders = [
    `Host: 127.0.0.1:${port}`,
    'Content-Type: application/json',
    `X-Diagnostic-Secret: ${privateSentinel}`,
    'X-Duplicate: first',
    'X-Duplicate: second',
    `Content-Length: ${Buffer.byteLength(body)}`,
    'Connection: close',
  ].join('\r\n');
  const rawResponse = await sendLiteralRequest(port, {
    path: requestPath,
    headers: incomingHeaders,
    body,
  });

  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(events[0].route, 'accounts.lookup');
  assert.match(rawResponse, /^HTTP\/1\.1 200/);
  assert.match(rawResponse, /response-sentinel/);
  assert.equal(received.length, 1);
  assert.equal(received[0].method, 'POST');
  assert.equal(received[0].url, requestPath);
  assert.equal(received[0].body, body);
  assert.deepEqual(received[0].rawHeaders, [
    'Host', `127.0.0.1:${port}`,
    'Content-Type', 'application/json',
    'X-Diagnostic-Secret', privateSentinel,
    'X-Duplicate', 'first',
    'X-Duplicate', 'second',
    'Content-Length', String(Buffer.byteLength(body)),
    'Connection', 'close',
  ]);
  assert.deepEqual(rawHeaderValues(received[0].rawHeaders, 'x-duplicate'), ['first', 'second']);
  assert.deepEqual(rawHeaderValues(received[0].rawHeaders, 'x-diagnostic-secret'), [privateSentinel]);

  assert.equal(events.length, 1);
  assert.deepEqual(Object.keys(events[0]).sort(), [
    'durationMs', 'errorClass', 'method', 'route', 'status', 'timestamp',
  ]);
  assert.equal(events[0].method, 'POST');
  assert.equal(events[0].route, 'accounts.lookup');
  assert.equal(events[0].status, 200);
  assert.equal(events[0].errorClass, null);
  assert.ok(Number.isFinite(events[0].durationMs));
  assert.ok(!JSON.stringify(events).includes(privateSentinel));
  assert.ok(!JSON.stringify(events).includes('private@example.invalid'));
  assert.ok(!JSON.stringify(events).includes('private-api-key'));
  assert.ok(!JSON.stringify(events).includes('private-query'));
  assert.ok(!JSON.stringify(events).includes('response-sentinel'));
});

test('normalizes unrecognized methods and routes without retaining input', () => {
  assert.equal(normalizeMethod('CONNECT'), 'OTHER');
  assert.equal(
    normalizeRoute('/identitytoolkit.googleapis.com/v1/accounts:lookup?key=secret'),
    'accounts.lookup',
  );
  assert.equal(normalizeRoute('/arbitrary/private-path?email=private'), 'other');
});

test('classifies connection failures without exposing the raw error', () => {
  const classified = classifyTransportError(Object.assign(
    new Error('contains private response text'),
    { code: 'ECONNREFUSED', path: 'private-path' },
  ));
  assert.equal(classified, 'connect_refused');
  assert.ok(!String(classified).includes('private'));
});

test('requires demo project and loopback endpoints', () => {
  assert.throws(() => createDiagnosticProxy({
    listenHost: '0.0.0.0', listenPort: 0,
    upstreamHost: '127.0.0.1', upstreamPort: 9097,
    projectId: 'demo-universal-search', logger: () => {},
  }));
  assert.throws(() => createDiagnosticProxy({
    listenHost: '127.0.0.1', listenPort: 0,
    upstreamHost: '127.0.0.1', upstreamPort: 9097,
    projectId: 'tudo-aqui-macacu', logger: () => {},
  }));
  assert.equal(
    parseProjectArgument(
      ['--project', 'demo-universal-search'],
      {
        GCLOUD_PROJECT: 'demo-universal-search',
        GOOGLE_CLOUD_PROJECT: 'demo-universal-search',
        FIREBASE_CONFIG: '{"projectId":"demo-universal-search"}',
      },
    ),
    'demo-universal-search',
  );
  assert.throws(() => parseProjectArgument(['--project', 'tudo-aqui-macacu']));
  assert.throws(() => parseProjectArgument(
    ['--project', 'demo-universal-search'],
    {
      GCLOUD_PROJECT: 'tudo-aqui-macacu',
      GOOGLE_CLOUD_PROJECT: 'tudo-aqui-macacu',
      FIREBASE_CONFIG: '{"projectId":"tudo-aqui-macacu"}',
    },
  ));
  assert.throws(() => parseProjectArgument([
    '--project', 'demo-universal-search', '--listen-host', '0.0.0.0',
  ]));
});

test('reports an upstream connection failure using only a safe class', async (t) => {
  const events = [];
  const reserve = http.createServer();
  const upstreamPort = await listen(reserve);
  await close(reserve);
  const proxy = createDiagnosticProxy({
    listenHost: '127.0.0.1', listenPort: 0,
    upstreamHost: '127.0.0.1', upstreamPort,
    projectId: 'demo-universal-search', logger: (event) => events.push(event),
  });
  proxy.listen(0, '127.0.0.1');
  await once(proxy, 'listening');
  t.after(() => close(proxy));

  const result = await sendRawRequest(proxy.address().port, {
    method: 'POST', path: '/securetoken.googleapis.com/v1/token?secret=never-log',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: 'refresh_token=private-refresh-sentinel',
  });

  assert.equal(result.status, 502);
  assert.equal(events.length, 1);
  assert.equal(events[0].status, 502);
  assert.equal(events[0].route, 'securetoken.token');
  assert.equal(events[0].errorClass, 'connect_refused');
  assert.ok(!JSON.stringify(events).includes('never-log'));
  assert.ok(!JSON.stringify(events).includes('private-refresh-sentinel'));
});

test('logs an allowlisted Auth refresh error code and forwards the original response', async (t) => {
  const events = [];
  const body = JSON.stringify({
    error: {
      code: 400,
      message: 'INVALID_REFRESH_TOKEN : ((private-body-sentinel))',
    },
  });
  const upstream = http.createServer((_request, response) => {
    response.writeHead(400, {
      'content-type': 'application/json',
      'x-response-secret': 'private-header-sentinel',
    });
    response.end(body);
  });
  const upstreamPort = await listen(upstream);
  t.after(() => close(upstream));
  const proxy = createDiagnosticProxy({
    listenHost: '127.0.0.1', listenPort: 0,
    upstreamHost: '127.0.0.1', upstreamPort,
    projectId: 'demo-universal-search', logger: (event) => events.push(event),
  });
  proxy.listen(0, '127.0.0.1');
  await once(proxy, 'listening');
  t.after(() => close(proxy));

  const requestBody = 'refresh_token=private-refresh-sentinel';
  const response = await sendRawRequest(proxy.address().port, {
    method: 'POST',
    path: '/securetoken.googleapis.com/v1/token?key=private-query-sentinel',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: requestBody,
  });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(response.status, 400);
  assert.equal(response.body, body);
  assert.deepEqual(
    rawHeaderValues(response.headers, 'x-response-secret'),
    ['private-header-sentinel'],
  );
  assert.equal(events.length, 1);
  assert.equal(events[0].authErrorCode, 'INVALID_REFRESH_TOKEN');
  const log = JSON.stringify(events);
  for (const sensitive of [
    'private-body-sentinel', 'private-header-sentinel',
    'private-refresh-sentinel', 'private-query-sentinel',
  ]) assert.ok(!log.includes(sensitive));
});

test('does not log unknown Auth response messages or their contents', async (t) => {
  const events = [];
  const body = JSON.stringify({
    error: { code: 400, message: 'PRIVATE_UNKNOWN_EMAIL_SENTINEL@example.invalid' },
  });
  const upstream = http.createServer((_request, response) => {
    response.writeHead(400, { 'content-type': 'application/json' });
    response.end(body);
  });
  const upstreamPort = await listen(upstream);
  t.after(() => close(upstream));
  const proxy = createDiagnosticProxy({
    listenHost: '127.0.0.1', listenPort: 0,
    upstreamHost: '127.0.0.1', upstreamPort,
    projectId: 'demo-universal-search', logger: (event) => events.push(event),
  });
  proxy.listen(0, '127.0.0.1');
  await once(proxy, 'listening');
  t.after(() => close(proxy));

  const response = await sendRawRequest(proxy.address().port, {
    method: 'POST',
    path: '/securetoken.googleapis.com/v1/token',
    headers: { 'content-type': 'application/json' },
    body: '{"refreshToken":"private-refresh-sentinel"}',
  });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(response.status, 400);
  assert.equal(response.body, body);
  assert.equal(events.length, 1);
  assert.equal(Object.hasOwn(events[0], 'authErrorCode'), false);
  const log = JSON.stringify(events);
  assert.ok(!log.includes('PRIVATE_UNKNOWN_EMAIL_SENTINEL'));
  assert.ok(!log.includes('private-refresh-sentinel'));
});

test('ignores malformed Auth error bodies without changing the response', async (t) => {
  const events = [];
  const body = '{"error":{"message":"PRIVATE_MALFORMED_SENTINEL@example.invalid"';
  const upstream = http.createServer((_request, response) => {
    response.writeHead(400, { 'content-type': 'application/json' });
    response.end(body);
  });
  const upstreamPort = await listen(upstream);
  t.after(() => close(upstream));
  const proxy = createDiagnosticProxy({
    listenHost: '127.0.0.1', listenPort: 0,
    upstreamHost: '127.0.0.1', upstreamPort,
    projectId: 'demo-universal-search', logger: (event) => events.push(event),
  });
  proxy.listen(0, '127.0.0.1');
  await once(proxy, 'listening');
  t.after(() => close(proxy));

  const response = await sendRawRequest(proxy.address().port, {
    method: 'POST',
    path: '/securetoken.googleapis.com/v1/token',
    headers: { 'content-type': 'application/json' },
    body: '{"refreshToken":"private-refresh-sentinel"}',
  });
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(response.status, 400);
  assert.equal(response.body, body);
  assert.equal(events.length, 1);
  assert.equal(Object.hasOwn(events[0], 'authErrorCode'), false);
  const log = JSON.stringify(events);
  assert.ok(!log.includes('PRIVATE_MALFORMED_SENTINEL'));
  assert.ok(!log.includes('private-refresh-sentinel'));
});
