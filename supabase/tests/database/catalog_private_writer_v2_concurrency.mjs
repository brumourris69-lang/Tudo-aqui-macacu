import { randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';

// Run against the disposable PostgreSQL container after applying migrations:
// node catalog_private_writer_v2_concurrency.mjs --container <container-name>
// The harness refuses containers with network access or published ports.

const argv = process.argv.slice(2);
const containerIndex = argv.indexOf('--container');
const containerName = containerIndex >= 0 ? argv[containerIndex + 1] : '';
const plan = 11;
const results = [];
const activeSessions = new Set();
const suffix = randomUUID().replaceAll('-', '').slice(0, 12);

function record(passed, description) {
  results.push({ passed: Boolean(passed), description });
}

function dockerResult(args, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error('local container command timed out'));
    }, timeoutMs);
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once('close', (code) => {
      clearTimeout(timer);
      resolve({ code, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });
}

function startPsqlSession(applicationName) {
  const args = [
    'exec', '--interactive', '--env', `PGAPPNAME=${applicationName}`, containerName,
    'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose',
    '-U', 'supabase_admin', '-d', 'postgres',
  ];
  const child = spawn('docker', args, { windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let closed = false;
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const exit = new Promise((resolve, reject) => {
    child.once('error', (error) => {
      closed = true;
      activeSessions.delete(session);
      resolve({ code: null, signal: null, stdout, stderr: '', errorCode: error.code });
    });
    child.once('close', (code, signal) => {
      closed = true;
      activeSessions.delete(session);
      resolve({ code, signal, stdout, stderr });
    });
  });
  const session = {
    child,
    exit,
    applicationName,
    get closed() { return closed; },
    get stdout() { return stdout; },
    get stderr() { return stderr; },
    sendLine(line) {
      if (closed || child.stdin.destroyed || !child.stdin.writable) return false;
      return child.stdin.write(`${line}\n`);
    },
  };
  activeSessions.add(session);
  return session;
}

function startPsqlCommand(sql, applicationName) {
  const args = [
    'exec', '--env', `PGAPPNAME=${applicationName}`, containerName,
    'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose',
    '-U', 'supabase_admin', '-d', 'postgres', '-c', sql,
  ];
  const child = spawn('docker', args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let closed = false;
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const exit = new Promise((resolve) => {
    child.once('error', (error) => {
      closed = true;
      activeSessions.delete(session);
      resolve({ code: null, signal: null, stdout, stderr: '', errorCode: error.code });
    });
    child.once('close', (code, signal) => {
      closed = true;
      activeSessions.delete(session);
      resolve({ code, signal, stdout, stderr });
    });
  });
  const session = {
    child,
    exit,
    get closed() { return closed; },
    get stdout() { return stdout; },
    get stderr() { return stderr; },
  };
  activeSessions.add(session);
  return session;
}

async function waitFor(predicate, timeoutMs = 6000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return true;
    await new Promise((resolve) => setTimeout(resolve, 75));
  }
  return false;
}

async function runPsql(sql, applicationName = `writer074-${suffix}`) {
  const args = [
    'exec', '--env', `PGAPPNAME=${applicationName}`, containerName,
    'psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose',
    '-U', 'supabase_admin', '-d', 'postgres', '-c', sql,
  ];
  return dockerResult(args, 15000);
}

async function waitForOutput(session, text, timeoutMs = 6000) {
  return waitFor(() => session.stdout.includes(text) || session.closed, timeoutMs)
    .then(() => session.stdout.includes(text) && !session.closed);
}

async function waitForExit(session, timeoutMs = 15000) {
  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve(null), timeoutMs);
  });
  const result = await Promise.race([session.exit, timeout]);
  clearTimeout(timer);
  if (result === null) {
    session.child.kill();
    throw new Error('concurrent PostgreSQL session timed out');
  }
  return result;
}

function projection(id, version, operationId, name) {
  return {
    id,
    content_kind: 'establishment',
    category_group: 'commerce',
    name,
    summary: 'Disposable concurrency fixture',
    category: 'Comércio',
    subcategory: 'Market',
    location: 'Cachoeiras de Macacu',
    artwork: 0,
    image_url: '',
    logo_url: '',
    gallery_urls: [],
    featured: false,
    is_open: true,
    maps_url: '',
    hours: '',
    services: [],
    products: [],
    additional_info: '',
    promotion_title: '',
    promotion_description: '',
    public_contact_approved: false,
    phone: null,
    whatsapp: null,
    instagram: null,
    published: true,
    active: true,
    expires_at: null,
    deleted_at: null,
    catalog_version: version,
    outbox_operation_id: operationId,
  };
}

function applySql(entry) {
  return `select public.apply_establishment_projection_v2($catalog$${JSON.stringify(entry)}$catalog$::jsonb);`;
}

async function readState(id) {
  const query = `select catalog_version || '|' || outbox_operation_id::text || '|' || name from public.public_establishment_catalog_v2 where id = '${id}';`;
  const result = await runPsql(query);
  if (result.code !== 0) throw new Error('could not read disposable catalog state');
  return result.stdout;
}

async function observeAcquiredAdvisoryLock(backendPid) {
  const query = `select count(*) from pg_catalog.pg_locks where pid = ${backendPid} and locktype = 'advisory' and granted;`;
  const result = await runPsql(query);
  return result.code === 0 && Number(result.stdout) > 0;
}

async function observeAdvisoryWait(waiterPid, winnerPid) {
  const query = `
    select count(*)
    from pg_catalog.pg_stat_activity waiter
    join pg_catalog.pg_locks waiting_lock
      on waiting_lock.pid = waiter.pid and waiting_lock.locktype = 'advisory' and not waiting_lock.granted
    join pg_catalog.pg_locks held_lock
      on held_lock.locktype = waiting_lock.locktype
      and held_lock.database is not distinct from waiting_lock.database
      and held_lock.classid is not distinct from waiting_lock.classid
      and held_lock.objid is not distinct from waiting_lock.objid
      and held_lock.objsubid is not distinct from waiting_lock.objsubid
      and held_lock.pid = ${winnerPid} and held_lock.granted
    where waiter.pid = ${waiterPid}
      and waiter.state = 'active'
      and waiter.wait_event_type = 'Lock'
      and waiter.wait_event = 'advisory';`;
  const result = await runPsql(query);
  return result.code === 0 && Number(result.stdout) > 0;
}

async function observeWait(applicationName, eventType, eventName) {
  const query = `select count(*) from pg_catalog.pg_stat_activity where application_name = '${applicationName}' and state = 'active' and wait_event_type = '${eventType}' and wait_event = '${eventName}';`;
  const result = await runPsql(query);
  return result.code === 0 && Number(result.stdout) > 0;
}

function markerPid(output, marker) {
  const match = output.match(new RegExp(`${marker}=([0-9]+)`));
  return match ? Number(match[1]) : null;
}

async function main() {
  if (!/^[A-Za-z0-9_.-]{1,120}$/.test(containerName)) {
    throw new Error('provide a valid disposable container with --container');
  }

  const inspect = await dockerResult([
    'inspect', '--format', '{{.State.Running}}|{{.HostConfig.NetworkMode}}|{{json .HostConfig.PortBindings}}|{{json .NetworkSettings.Ports}}',
    containerName,
  ]);
  if (inspect.code !== 0 || inspect.stdout !== 'true|none|{}|{}') {
    throw new Error('container must run with network=none and no published ports');
  }

  const writerReady = await runPsql("select to_regprocedure('public.apply_establishment_projection_v2(jsonb)') is not null;");
  if (writerReady.code !== 0 || writerReady.stdout !== 't') {
    throw new Error('private projection writer is not available in the disposable database');
  }

  // Session A applies v1 and holds the transaction-scoped per-ID lock. Session B
  // concurrently attempts the same version with a different operation UUID.
  const winnerId = `writer-race-${suffix}`;
  const winnerOp = randomUUID();
  const loserOp = randomUUID();
  const winnerApp = `writer074-a-${suffix}`;
  const loserApp = `writer074-b-${suffix}`;
  const winner = startPsqlSession(winnerApp);
  winner.sendLine('begin;');
  winner.sendLine('set role catalog_writer_v2;');
  winner.sendLine("select 'WINNER_BACKEND_PID=' || pg_catalog.pg_backend_pid();");
  const winnerPidReady = await waitForOutput(winner, 'WINNER_BACKEND_PID=');
  const winnerPid = markerPid(winner.stdout, 'WINNER_BACKEND_PID');
  if (!winnerPidReady || !winnerPid) throw new Error('first PostgreSQL session did not report its backend PID');

  winner.sendLine(applySql(projection(winnerId, 1, winnerOp, 'Race winner')));
  winner.sendLine("select 'WINNER_LOCK_HELD=' || pg_catalog.pg_backend_pid();");
  const winnerApplied = await waitForOutput(winner, 'WINNER_LOCK_HELD=');
  const winnerLockHeld = winnerApplied && await observeAcquiredAdvisoryLock(winnerPid);
  record(winnerLockHeld, 'session A applies v1 and retains a granted advisory lock in its open transaction');
  if (!winnerLockHeld) throw new Error('first writer did not retain its advisory lock in an open transaction');

  const loser = startPsqlSession(loserApp);
  loser.sendLine('set role catalog_writer_v2;');
  loser.sendLine("select 'WAITER_BACKEND_PID=' || pg_catalog.pg_backend_pid();");
  const waiterPidReady = await waitForOutput(loser, 'WAITER_BACKEND_PID=');
  const waiterPid = markerPid(loser.stdout, 'WAITER_BACKEND_PID');
  if (!waiterPidReady || !waiterPid) throw new Error('second PostgreSQL session did not report its backend PID');
  const distinctBackends = waiterPid !== winnerPid;
  loser.sendLine(applySql(projection(winnerId, 1, loserOp, 'Race loser')));
  const loserBlocked = distinctBackends
    && await waitFor(() => observeAdvisoryWait(waiterPid, winnerPid));
  record(loserBlocked, 'distinct session B waits on the advisory lock held by session A');
  if (!loserBlocked) throw new Error('second writer did not enter the observed advisory-lock wait');

  winner.sendLine("commit;");
  winner.sendLine("select 'WINNER_COMMITTED=' || pg_catalog.pg_backend_pid();");
  const winnerCommitted = await waitForOutput(winner, 'WINNER_COMMITTED=');
  winner.sendLine('\\q');
  const winnerExit = await waitForExit(winner);
  record(winnerCommitted && winnerExit.code === 0, 'session A commits successfully after session B is observed waiting');
  const loserExit = await waitForExit(loser);
  record(loserExit.code !== 0 && /23514/.test(loserExit.stderr), 'same-version different-operation write is rejected after serialization');
  record(
    (await readState(winnerId)) === `1|${winnerOp}|Race winner`,
    'persisted state retains the winning version, operation, and content',
  );
  const loserPersisted = await runPsql(
    `select count(*) from public.public_establishment_catalog_v2 where outbox_operation_id = '${loserOp}';`,
  );
  record(loserPersisted.code === 0 && loserPersisted.stdout === '0', 'losing operation identifier was not persisted');

  // A delayed older session is alive while a separate session commits v3. When
  // the delayed session resumes and submits v2, the writer must reject it.
  const staleId = `writer-stale-race-${suffix}`;
  const seedOp = randomUUID();
  const staleOp = randomUUID();
  const newerOp = randomUUID();
  const seed = await runPsql(`set role catalog_writer_v2; ${applySql(projection(staleId, 1, seedOp, 'Seed v1'))}`);
  record(seed.code === 0 && seed.stdout === 'applied', 'second race starts from a persisted v1 fixture');
  if (seed.code !== 0) throw new Error('could not seed second concurrency fixture');

  const staleApp = `writer074-stale-${suffix}`;
  const stale = startPsqlCommand(
    `begin; set role catalog_writer_v2; select pg_sleep(4); ${applySql(projection(staleId, 2, staleOp, 'Delayed v2'))} commit;`,
    staleApp,
  );
  const staleIsWaiting = await waitFor(() => observeWait(staleApp, 'Timeout', 'PgSleep'));
  record(staleIsWaiting, 'older v2 session is active and delayed before its write');
  if (!staleIsWaiting) throw new Error('delayed stale session did not enter its wait');

  const newer = await runPsql(`set role catalog_writer_v2; ${applySql(projection(staleId, 3, newerOp, 'Committed v3'))}`);
  record(newer.code === 0 && newer.stdout === 'applied', 'independent session commits v3 while v2 remains delayed');
  const staleExit = await waitForExit(stale);
  record(staleExit.code !== 0 && /23514/.test(staleExit.stderr), 'delayed v2 write is rejected as stale');
  record(
    (await readState(staleId)) === `3|${newerOp}|Committed v3`,
    'persisted state remains at the newer v3 operation after the stale attempt',
  );
}

try {
  await main();
} catch (error) {
  const reason = error?.code === 'ENOENT' ? 'required local executable unavailable' : 'setup or concurrent session failed';
  process.stderr.write(`[concurrency harness] ${reason}\n`);
} finally {
  const remainingSessions = [...activeSessions];
  for (const session of remainingSessions) {
    if (typeof session.sendLine === 'function') session.sendLine('\\q');
  }
  await Promise.race([
    Promise.all(remainingSessions.map((session) => session.exit)),
    new Promise((resolve) => setTimeout(resolve, 1500)),
  ]);
  for (const session of activeSessions) session.child.kill();
}

while (results.length < plan) {
  results.push({ passed: false, description: 'not run because an earlier concurrency step failed' });
}

process.stdout.write('TAP version 13\n');
process.stdout.write(`1..${plan}\n`);
results.forEach(({ passed, description }, index) => {
  process.stdout.write(`${passed ? 'ok' : 'not ok'} ${index + 1} - ${description}\n`);
});
if (results.some(({ passed }) => !passed)) process.exitCode = 1;
