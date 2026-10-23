'use strict';

const http = require('node:http');

const DEMO_PROJECT = 'demo-universal-search';
const LOCAL_HOST = '127.0.0.1';
const PROXY_PORT = 9197;
const AUTH_EMULATOR_PORT = 9097;
const MAX_AUTH_ERROR_BODY_BYTES = 16 * 1024;

const AUTH_REFRESH_ERROR_CODES = new Set([
  'INVALID_REFRESH_TOKEN',
  'MISSING_GRANT_TYPE',
  'INVALID_GRANT_TYPE',
  'MISSING_REFRESH_TOKEN',
  'TENANT_ID_MISMATCH',
  'USER_DISABLED',
  'INVALID_ARGUMENT',
  'UNKNOWN',
  'INTERNAL',
]);

const METHODS = new Set([
  'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS',
]);

const ROUTES = new Map([
  ['/identitytoolkit.googleapis.com/v1/accounts:lookup', 'accounts.lookup'],
  ['/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword', 'accounts.sign_in'],
  ['/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken', 'accounts.sign_in'],
  ['/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp', 'accounts.sign_in'],
  ['/identitytoolkit.googleapis.com/v1/accounts:signUp', 'accounts.sign_up'],
  ['/identitytoolkit.googleapis.com/v1/accounts:update', 'accounts.update'],
  ['/identitytoolkit.googleapis.com/v1/accounts:delete', 'accounts.delete'],
  ['/identitytoolkit.googleapis.com/v1/accounts:sendOobCode', 'accounts.send_oob_code'],
  ['/identitytoolkit.googleapis.com/v1/accounts:resetPassword', 'accounts.reset_password'],
  ['/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode', 'accounts.send_verification_code'],
  ['/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber', 'accounts.sign_in_phone'],
  ['/securetoken.googleapis.com/v1/token', 'securetoken.token'],
  ['/identitytoolkit/v3/relyingparty/getAccountInfo', 'accounts.lookup'],
  ['/identitytoolkit/v3/relyingparty/verifyAssertion', 'accounts.sign_in'],
  ['/identitytoolkit/v3/relyingparty/signupNewUser', 'accounts.sign_up'],
]);

function normalizeMethod(method) {
  const candidate = typeof method === 'string' ? method.toUpperCase() : '';
  return METHODS.has(candidate) ? candidate : 'OTHER';
}

function normalizeRoute(requestTarget) {
  if (typeof requestTarget !== 'string') return 'other';
  const pathname = requestTarget.split('?', 1)[0];
  return ROUTES.get(pathname) || 'other';
}

function classifyTransportError(error) {
  switch (error && error.code) {
    case 'ECONNREFUSED': return 'connect_refused';
    case 'ETIMEDOUT':
    case 'ESOCKETTIMEDOUT': return 'timeout';
    case 'ECONNRESET': return 'connection_reset';
    case 'EHOSTUNREACH':
    case 'ENETUNREACH': return 'unreachable';
    case 'EPIPE': return 'pipe_closed';
    case 'HPE_INVALID_CONSTANT':
    case 'HPE_INVALID_HEADER_TOKEN':
    case 'HPE_INVALID_STATUS':
    case 'HPE_UNEXPECTED_CONTENT_LENGTH': return 'http_protocol';
    default: return 'transport_error';
  }
}

function extractSafeAuthErrorCode(body) {
  try {
    const parsed = JSON.parse(body.toString('utf8'));
    const error = parsed && typeof parsed === 'object' ? parsed.error : null;
    if (!error || typeof error !== 'object') return null;

    for (const value of [error.message, error.status]) {
      if (typeof value !== 'string') continue;
      const code = value.trim().split(/\s+:\s+/, 1)[0];
      if (AUTH_REFRESH_ERROR_CODES.has(code)) return code;
    }
  } catch {
    // Malformed or non-JSON Auth responses are forwarded without diagnostics.
  }
  return null;
}

function createDiagnosticProxy({
  listenHost,
  listenPort,
  upstreamHost,
  upstreamPort,
  projectId,
  logger,
}) {
  if (listenHost !== LOCAL_HOST || upstreamHost !== LOCAL_HOST) {
    throw new Error('Diagnostic proxy endpoints must use IPv4 loopback.');
  }
  if (projectId !== DEMO_PROJECT) {
    throw new Error('Diagnostic proxy is restricted to the demo project.');
  }
  if (!Number.isInteger(listenPort) || (listenPort !== 0 && listenPort !== PROXY_PORT)) {
    throw new Error('Diagnostic proxy port is not allowed.');
  }
  if (!Number.isInteger(upstreamPort) || upstreamPort < 1 || upstreamPort > 65535) {
    throw new Error('Diagnostic proxy upstream port is invalid.');
  }
  if (typeof logger !== 'function') {
    throw new Error('Diagnostic proxy requires a sanitized event logger.');
  }

  const server = http.createServer((incoming, outgoing) => {
    const startedAt = process.hrtime.bigint();
    const method = normalizeMethod(incoming.method);
    const route = normalizeRoute(incoming.url);
    let logged = false;
    let responseStatus = null;

    const log = (status, errorClass = null, authErrorCode = null) => {
      if (logged) return;
      logged = true;
      const elapsed = Number(process.hrtime.bigint() - startedAt) / 1e6;
      const event = Object.freeze({
        timestamp: new Date().toISOString(),
        method,
        route,
        status: Number.isInteger(status) ? status : null,
        durationMs: Math.max(0, Math.round(elapsed * 100) / 100),
        errorClass: errorClass || null,
        ...(authErrorCode ? { authErrorCode } : {}),
      });
      try {
        logger(event);
      } catch {
        // A diagnostic sink must never affect Auth traffic or emit its error.
      }
    };

    // Firebase Auth uses origin-form request targets. Reject other forms so a
    // caller cannot turn the fixed local forwarder into an open proxy.
    if (
      typeof incoming.url !== 'string' ||
      !incoming.url.startsWith('/') ||
      incoming.url.startsWith('//')
    ) {
      outgoing.writeHead(400, { 'content-length': '0' });
      outgoing.once('finish', () => log(400));
      outgoing.end();
      return;
    }

    let forwarded;
    try {
      forwarded = http.request(
        {
          hostname: upstreamHost,
          port: upstreamPort,
          method: incoming.method,
          path: incoming.url,
          headers: incoming.rawHeaders,
          setHost: false,
          agent: false,
        },
        (upstream) => {
          responseStatus = upstream.statusCode || 502;
          let errorBodyChunks = [];
          let errorBodyBytes = 0;
          let errorBodyOverflow = false;
          let authErrorCode = null;
          const discardErrorBody = () => {
            for (const chunk of errorBodyChunks) chunk.fill(0);
            errorBodyChunks = [];
            errorBodyBytes = 0;
          };
          try {
            outgoing.writeHead(
              responseStatus,
              upstream.statusMessage,
              upstream.rawHeaders,
            );
          } catch (error) {
            log(502, classifyTransportError(error));
            upstream.destroy();
            outgoing.destroy();
            return;
          }
          if (route === 'securetoken.token' && responseStatus >= 400) {
            upstream.on('data', (chunk) => {
              if (errorBodyOverflow) return;
              if (errorBodyBytes + chunk.length > MAX_AUTH_ERROR_BODY_BYTES) {
                errorBodyOverflow = true;
                discardErrorBody();
                return;
              }
              errorBodyChunks.push(Buffer.from(chunk));
              errorBodyBytes += chunk.length;
            });
            upstream.once('end', () => {
              if (!errorBodyOverflow) {
                const body = Buffer.concat(errorBodyChunks, errorBodyBytes);
                try {
                  authErrorCode = extractSafeAuthErrorCode(body);
                } finally {
                  body.fill(0);
                  discardErrorBody();
                }
              }
            });
          }
          upstream.on('error', (error) => {
            discardErrorBody();
            log(responseStatus, classifyTransportError(error));
            outgoing.destroy();
          });
          upstream.pipe(outgoing);
          outgoing.once('finish', () => log(responseStatus, null, authErrorCode));
          outgoing.once('close', () => discardErrorBody());
        },
      );
    } catch (error) {
      outgoing.writeHead(502, { 'content-length': '0' });
      outgoing.once('finish', () => log(502, classifyTransportError(error)));
      outgoing.end();
      return;
    }

    forwarded.on('error', (error) => {
      const errorClass = incoming.aborted
        ? 'client_closed'
        : classifyTransportError(error);
      if (!outgoing.headersSent && !outgoing.destroyed) {
        outgoing.writeHead(502, { 'content-length': '0' });
        outgoing.end();
      }
      log(502, errorClass);
    });

    incoming.on('aborted', () => {
      forwarded.destroy();
      log(responseStatus, 'client_closed');
    });
    outgoing.on('close', () => {
      if (!outgoing.writableEnded) {
        forwarded.destroy();
        log(responseStatus, 'client_closed');
      }
    });

    incoming.pipe(forwarded);
  });

  return server;
}

function parseProjectArgument(args, environment = process.env) {
  if (args.length !== 2 || args[0] !== '--project' || args[1] !== DEMO_PROJECT) {
    throw new Error('Expected only --project demo-universal-search.');
  }
  let firebaseConfig;
  try {
    firebaseConfig = JSON.parse(environment.FIREBASE_CONFIG || '{}');
  } catch {
    throw new Error('The local Firebase project context is not valid.');
  }
  if (environment.GCLOUD_PROJECT !== DEMO_PROJECT ||
      environment.GOOGLE_CLOUD_PROJECT !== DEMO_PROJECT ||
      firebaseConfig.projectId !== DEMO_PROJECT) {
    throw new Error('The local Firebase project context is not the approved demo.');
  }
  return args[1];
}

if (require.main === module) {
  try {
    const projectId = parseProjectArgument(process.argv.slice(2));
    const server = createDiagnosticProxy({
      listenHost: LOCAL_HOST,
      listenPort: PROXY_PORT,
      upstreamHost: LOCAL_HOST,
      upstreamPort: AUTH_EMULATOR_PORT,
      projectId,
      logger: (event) => process.stdout.write(`${JSON.stringify(event)}\n`),
    });
    server.listen(PROXY_PORT, LOCAL_HOST);
    const shutdown = () => server.close(() => process.exit(0));
    process.once('SIGINT', shutdown);
    process.once('SIGTERM', shutdown);
    server.on('error', () => process.exitCode = 1);
  } catch {
    process.exitCode = 1;
  }
}

module.exports = {
  createDiagnosticProxy,
  classifyTransportError,
  normalizeMethod,
  normalizeRoute,
  parseProjectArgument,
};
