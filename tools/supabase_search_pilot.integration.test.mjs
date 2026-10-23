import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const migrationPath = path.join(root, 'supabase/migrations/20261019000100_search_public_establishments.sql');

async function migration() {
  return readFile(migrationPath, 'utf8');
}

test('pilot schema contains only approved public fields and secure RLS', async () => {
  const sql = await migration();
  assert.match(sql, /create table public\.public_search_establishments/i);
  assert.match(sql, /function public\.search_pilot_document_text\s*\([\s\S]*immutable/i);
  assert.doesNotMatch(sql, /concat_ws\s*\(/i, 'index/search expressions avoid stable concat_ws');
  assert.match(sql, /enable row level security/i);
  assert.match(sql, /force row level security/i);
  assert.match(sql, /published\s*=\s*true[\s\S]*active\s*=\s*true/i);
  assert.match(sql, /grant select\s*\(\s*id\s*,\s*name\s*,\s*summary\s*,\s*category\s*,\s*subcategory\s*,\s*image_url\s*\)\s*on public\.public_search_establishments to anon/i);
  assert.doesNotMatch(sql, /service_role|firebase(?:io|app|functions)|firestore/i);
  assert.doesNotMatch(sql, /phone|email|whatsapp|address|admin|private|salary/i);
});

test('pilot RPCs have bounded explicit projections and deterministic cursor policy', async () => {
  const sql = await migration();
  assert.match(sql, /function public\.search_public_establishments\s*\(/i);
  assert.match(sql, /function public\.get_public_establishment\s*\(/i);
  assert.match(sql, /p_page_size\s+not between\s+1\s+and\s+20/i);
  assert.match(sql, /array_length\s*\([^)]*,\s*1\s*\)\s+not between\s+1\s+and\s+4/i);
  assert.match(sql, /order by[\s\S]*rank[\s\S]*id/i);
  assert.match(sql, /grant execute on function public\.search_public_establishments/i);
  assert.match(sql, /grant execute on function public\.get_public_establishment/i);
  assert.doesNotMatch(sql, /to_jsonb\s*\(|row_to_json\s*\(/i);
});

test('database test suite covers visibility, validation, pagination, and detail boundaries', async () => {
  const sql = await readFile(path.join(root, 'supabase/tests/database/search_public_establishments.sql'), 'utf8');
  const hardeningSql = await readFile(path.join(root, 'supabase/tests/database/catalog_security_hardening.sql'), 'utf8');
  const plan = sql.match(/select plan\((\d+)\)/i);
  assert.ok(plan, 'database test plan is declared');
  const assertionCount = [...sql.matchAll(/^select (?:is|ok|throws_ok)\(/gim)].length;
  assert.equal(Number(plan[1]), assertionCount, 'declared pgTAP plan matches assertion count');
  for (const scenario of [
    'table schema contains the approved pilot fields and lifecycle controls',
    'document text helper is declared immutable',
    'accent normalization helper is declared immutable',
    'search returns all matching published and active fixtures',
    'cannot read publication control columns directly',
    'unsupported category is rejected',
    'page size below one is rejected',
    'page size above twenty is rejected',
    'empty search query is rejected',
    'longer than eighty characters is rejected',
    'more than four search terms are rejected',
    'shorter than two characters are rejected',
    'longer than twenty-four characters are rejected',
    'malformed cursor is rejected',
    'cursor from a different query is rejected',
    'cursor from a different category is rejected',
    'unpublished and inactive records are absent from search',
    'unpublished detail is unavailable',
    'inactive detail is unavailable',
    'published detail is available by its stable ID',
    'malformed detail ID is rejected',
  ]) {
    assert.ok(sql.includes(scenario), `missing database scenario: ${scenario}`);
  }
  assert.match(hardeningSql, /pg_get_function_result\([\s\S]*?search_public_establishments[\s\S]*?TABLE\(id text, name text, summary text, category text, subcategory text, [\s\S]*?image_url text, has_more boolean\)/i,
    'search RPC has an explicit public response projection assertion');
  assert.match(hardeningSql, /pg_get_function_result\([\s\S]*?get_public_establishment[\s\S]*?TABLE\(id text, name text, summary text, category text, subcategory text, image_url text\)/i,
    'detail RPC has an explicit public response projection assertion');
  assert.match(sql, /begin;[\s\S]*rollback;/i, 'fixtures are wrapped in a rollback transaction');
});

test('Android pilot flavor is debug-only and bypasses Firebase configuration', async () => {
  const entrypoint = await readFile(path.join(root, 'lib/main_supabase_pilot.dart'), 'utf8');
  const gradle = await readFile(path.join(root, 'android/app/build.gradle.kts'), 'utf8');
  assert.doesNotMatch(entrypoint, /Firebase\.initializeApp|firebase_core/i);
  assert.match(entrypoint, /kDebugMode/);
  assert.match(entrypoint, /SUPABASE_PILOT_PROJECT_REF/);
  assert.match(entrypoint, /appFlavor/);
  assert.match(entrypoint, /flavor\s*!=\s*'supabasePilot'/);
  assert.match(entrypoint, /trackBusinessShareMetrics:\s*false/);
  assert.match(gradle, /create\("supabasePilot"\)/);
  assert.match(gradle, /applicationIdSuffix\s*=\s*"\.supabasepilot"/);
  assert.match(gradle, /it\.buildType != "debug"\) it\.enable = false/);
  assert.match(gradle, /name\.contains\("SupabasePilot"\)[\s\S]*GoogleServices/);
  assert.match(gradle, /check\(!supabasePilotRequested\).*Release proibida/);
});

test('hosted URL validation accepts only the exact approved pilot origin', () => {
  assert.equal(approvedHostedPilotBase('https://zzxvcunuwbhglzzklsrl.supabase.co').origin,
    'https://zzxvcunuwbhglzzklsrl.supabase.co');

  for (const url of [
    'https://abcdefghijklmnopqrst.supabase.co',
    'https://zzxvcunuwbhglzzklsrl.supabase.co.attacker.example',
    'https://zzxvcunuwbhglzzklsrl.supabase.co.attacker.example.supabase.co',
    'https://zzxvcunuwbhglzzklsrl.supabase.co/extra',
    'https://zzxvcunuwbhglzzklsrl.supabase.co?project=other',
    'https://zzxvcunuwbhglzzklsrl.supabase.co#other',
    'https://zzxvcunuwbhglzzklsrl.supabase.co/',
  ]) {
    assert.throws(() => approvedHostedPilotBase(url), `must reject ${url}`);
  }
});

const approvedPilotOrigin = 'https://zzxvcunuwbhglzzklsrl.supabase.co';

function approvedHostedPilotBase(value) {
  let base;
  try {
    base = new URL(value);
  } catch {
    throw new Error('SUPABASE_PILOT_URL must be the exact approved pilot origin');
  }
  if (value !== approvedPilotOrigin || base.origin !== approvedPilotOrigin) {
    throw new Error('SUPABASE_PILOT_URL must be the exact approved pilot origin');
  }
  return base;
}

const pilotUrl = process.env.SUPABASE_PILOT_URL;
const pilotKey = process.env.SUPABASE_PILOT_ANON_KEY;

test('hosted pilot exposes only the fictional public contract', {
  skip: !pilotUrl || !pilotKey,
}, async (t) => {
  const base = approvedHostedPilotBase(pilotUrl);

  const search = async ({ query = 'exemplo', category = 'all', pageSize = 10, cursorId = null } = {}) => {
    const response = await fetch(new URL('/rest/v1/rpc/search_public_establishments', base), {
      method: 'POST',
      headers: {
        apikey: pilotKey,
        authorization: `Bearer ${pilotKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        p_query: query,
        p_category: category,
        p_page_size: pageSize,
        p_cursor_id: cursorId,
      }),
    });
    return response;
  };

  const allowedSearch = ['id', 'name', 'summary', 'category', 'subcategory', 'image_url', 'has_more'].sort();
  const allowedDetail = allowedSearch.filter((key) => key !== 'has_more');
  const firstResponse = await search({ pageSize: 1 });
  assert.equal(firstResponse.status, 200);
  const first = await firstResponse.json();
  assert.ok(Array.isArray(first) && first.length === 1);
  assert.deepEqual(Object.keys(first[0]).sort(), allowedSearch);
  assert.match(first[0].id, /^pilot-[a-z0-9-]+$/);
  assert.equal(typeof first[0].has_more, 'boolean');

  if (first[0].has_more) {
    const secondResponse = await search({ pageSize: 1, cursorId: first[0].id });
    assert.equal(secondResponse.status, 200);
    const second = await secondResponse.json();
    assert.equal(second.length, 1);
    assert.notEqual(second[0].id, first[0].id);
  }

  for (const category of ['commerce', 'services']) {
    const response = await search({ category });
    assert.equal(response.status, 200);
    for (const item of await response.json()) {
      assert.deepEqual(Object.keys(item).sort(), allowedSearch);
      assert.equal(category === 'services'
        ? ['Serviços', 'Profissionais'].includes(item.category)
        : !['Serviços', 'Profissionais'].includes(item.category), true);
    }
  }

  const detailResponse = await fetch(new URL('/rest/v1/rpc/get_public_establishment', base), {
    method: 'POST',
    headers: {
      apikey: pilotKey,
      authorization: `Bearer ${pilotKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ p_id: first[0].id }),
  });
  assert.equal(detailResponse.status, 200);
  const detail = await detailResponse.json();
  assert.equal(detail.length, 1);
  assert.deepEqual(Object.keys(detail[0]).sort(), allowedDetail);

  const hidden = await fetch(new URL('/rest/v1/rpc/get_public_establishment', base), {
    method: 'POST',
    headers: {
      apikey: pilotKey,
      authorization: `Bearer ${pilotKey}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ p_id: 'pilot-hidden-unpublished' }),
  });
  assert.equal(hidden.status, 200);
  assert.deepEqual(await hidden.json(), []);

  const invalid = await search({ query: 'x' });
  assert.ok(invalid.status >= 400 && invalid.status < 500);

  const deniedColumn = await fetch(new URL('/rest/v1/public_search_establishments?select=published', base), {
    headers: { apikey: pilotKey, authorization: `Bearer ${pilotKey}` },
  });
  assert.ok(deniedColumn.status === 401 || deniedColumn.status === 403);

  const directPublicRows = await fetch(new URL(
    '/rest/v1/public_search_establishments?select=id,name,summary,category,subcategory,image_url&order=id',
    base,
  ), {
    headers: { apikey: pilotKey, authorization: `Bearer ${pilotKey}` },
  });
  assert.equal(directPublicRows.status, 200);
  const publicRows = await directPublicRows.json();
  assert.equal(publicRows.length, 3, 'RLS exposes only published and active fictional rows');
  for (const row of publicRows) {
    assert.deepEqual(Object.keys(row).sort(), allowedDetail);
    assert.match(row.id, /^pilot-[a-z0-9-]+$/);
  }
  t.diagnostic('Hosted assertions used only public RPC responses and the anonymous key.');
});
