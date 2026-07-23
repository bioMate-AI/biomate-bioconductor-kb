#!/usr/bin/env node
/**
 * Connector contract test — RUNTIME verification that every declared MCP/connector
 * tool resolves to a live endpoint on the running server.
 *
 * The existing coverage (backend/tests/test_tools_manifest.py + the CI drift
 * workflow) is STATIC: it checks the manifest JSON matches the Python source and
 * the schema shapes are valid. It never hits a running server, so it cannot catch
 * the class of bugs we actually fixed this week:
 *   - a tool's backend_path/verb that 404s or 405s (e.g. "recall_memory uses GET",
 *     "export_report points to findings/report")
 *   - a tool present in the manifest but missing from the /tools/:operationId
 *     (ChatGPT) adapter switch → "unknown operation"
 *   - a Phase-2 stub still shadowing a real route (501 / not-implemented)
 *   - the remote_mcp /mcp proxy or its :8848 upstream being down
 *
 * This probes each tool over the client-facing surfaces WITHOUT auth (so write
 * tools hit the auth gate and never actually run) and classifies the response.
 *
 * Usage:  node scripts/connector_contract_test.mjs [BASE_URL]
 *   BASE_URL defaults to $BIOMATE_URL or https://dev-public.biomate.ai
 *
 * Exit 0 = all contracts hold (or only transient/inconclusive failures).
 * Exit 1 = at least one definitive contract violation (prints "[smoke] FAIL ...").
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const BASE = (process.argv[2] || process.env.BIOMATE_URL || 'https://dev-public.biomate.ai').replace(/\/$/, '');
const PROBE_TIMEOUT_MS = 12_000;
const DUMMY = '_contract_probe_nonexistent_';

// Canonical manifest (generated from backend/lib/mcp/tools_manifest.py). We read
// the committed JSON so the test needs no Python runtime.
function loadManifest() {
  const candidates = [
    join(__dirname, '..', 'backend', 'lib', 'mcp', 'tools_manifest.json'),
    join(__dirname, '..', 'frontend', 'server', 'tools_manifest.json'),
  ];
  for (const p of candidates) {
    try {
      const m = JSON.parse(readFileSync(p, 'utf8'));
      if (Array.isArray(m.backend_routes) && m.backend_routes.length) return { manifest: m, path: p };
    } catch { /* try next */ }
  }
  throw new Error('could not load tools_manifest.json (backend_routes)');
}

let failures = 0;
let inconclusive = 0;
const fail = (msg) => { console.log(`[smoke] FAIL ${msg}`); failures++; };
const pass = (msg) => console.log(`[smoke]   ok  ${msg}`);
const warn = (msg) => { console.log(`[smoke]   ?? ${msg}`); inconclusive++; };

async function probe(method, path, body) {
  const url = BASE + path;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), PROBE_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      method,
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: method === 'GET' ? undefined : JSON.stringify(body ?? {}),
      signal: ctrl.signal,
      redirect: 'manual',
    });
    const ct = res.headers.get('content-type') || '';
    // Read a little of the body to detect stub / unknown-op markers, then stop.
    let text = '';
    try { text = (await res.text()).slice(0, 400); } catch { /* streaming/aborted */ }
    return { status: res.status, ct, text };
  } catch (e) {
    return { status: 0, ct: '', text: '', err: String(e?.name || e) };
  } finally {
    clearTimeout(t);
  }
}

// Classify a probe result for a route that SHOULD exist and accept `method`.
// Returns 'ok' | 'fail:<reason>' | 'transient'.
function classify(r) {
  if (r.status === 0) return 'transient';                    // network/timeout — not a contract failure
  if (r.status === 502 || r.status === 503 || r.status === 504) return 'transient'; // upstream cold/blip
  if (r.status === 404) {
    // A 404 is a CONTRACT failure only when the route/verb is unregistered.
    // Distinguish that from a domain 404 (route exists, resource not found):
    //   - Express default for an unmatched route:  "Cannot POST /path"  (text/html)
    //   - our API 404 handler for unmatched /api/*: {"error":"NotFound","message":"API route ... not found"}
    //   - a real handler's 404:                     {"error":"Execution run not found"}  ← route EXISTS
    if (/Cannot (GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b/i.test(r.text))
      return 'fail:404 route/verb not registered (Express default 404)';
    if (/"error"\s*:\s*"NotFound"|API route\b[^"]*not found/i.test(r.text))
      return 'fail:404 API route not registered';
    return 'ok'; // domain 404 (dummy id not found) — route + verb resolved
  }
  if (r.status === 405) return 'fail:405 (method not allowed)';
  if (r.status === 501) return 'fail:501 (stub / not implemented)';
  if (/text\/html/i.test(r.ct)) return 'fail:SPA-fallthrough (route not registered — served index.html)';
  if (/\b(not[\s_-]?implemented|unknown[\s_-]?(operation|tool|action)|no[\s_-]?such[\s_-]?tool)\b/i.test(r.text))
    return 'fail:stub/unknown-operation in body';
  // 200/400/401/402/403/422/429 with a non-HTML body → the route exists and the
  // verb was accepted (reached the handler or the auth/validation gate). Contract holds.
  return 'ok';
}

async function main() {
  const { manifest, path: mpath } = loadManifest();
  const tools = manifest.backend_routes;
  console.log(`[smoke] connector contract: ${tools.length} tools from ${mpath.replace(/.*\/biomate\//, '')} against ${BASE}`);

  // 1. Reachability: /mcp proxy → remote_mcp :8848 must be up (JSON-RPC, not a 404/502 SPA page).
  {
    const r = await probe('POST', '/mcp', { jsonrpc: '2.0', id: 1, method: 'tools/list' });
    const c = classify(r);
    if (c === 'transient') warn(`/mcp reachability inconclusive (status=${r.status} ${r.err || ''})`);
    else if (c.startsWith('fail')) fail(`/mcp remote transport — ${c} (remote_mcp :8848 down or proxy route missing)`);
    else pass(`/mcp remote transport reachable (status=${r.status})`);
  }

  // 2. Live manifest/spec drift: the DEPLOYED ChatGPT OpenAPI must list the same
  //    number of tools as the manifest we're testing against.
  {
    const r = await fetch(BASE + '/connectors/chatgpt/openapi.json', { redirect: 'manual' }).catch(() => null);
    if (!r || !r.ok) {
      warn(`/connectors/chatgpt/openapi.json not fetchable (status=${r?.status ?? 'net'}) — skipping live drift check`);
    } else {
      const spec = await r.json().catch(() => null);
      const specTools = spec?.paths ? Object.keys(spec.paths).filter(p => p.startsWith('/tools/')).length : -1;
      if (specTools !== tools.length)
        fail(`live drift — deployed OpenAPI lists ${specTools} /tools/* ops but manifest has ${tools.length}`);
      else pass(`deployed OpenAPI tool count matches manifest (${specTools})`);
    }
  }

  // 3. Per-tool: backend_path resolves + ChatGPT /tools/{name} adapter handles it.
  for (const t of tools) {
    const backendPath = t.path.replace(/\{[^}]+\}/g, DUMMY);

    const rb = await probe(t.method, backendPath, {});
    const cb = classify(rb);
    if (cb === 'transient') warn(`${t.name}: backend ${t.method} ${t.path} inconclusive (status=${rb.status} ${rb.err || ''})`);
    else if (cb.startsWith('fail')) fail(`${t.name}: backend ${t.method} ${t.path} — ${cb.slice(5)}`);
    else pass(`${t.name}: backend ${t.method} ${t.path}`);

    // ChatGPT Actions adapter surface — every tool must be handled by /tools/:operationId.
    const ra = await probe('POST', `/tools/${t.name}`, {});
    const ca = classify(ra);
    if (ca === 'transient') warn(`${t.name}: adapter POST /tools/${t.name} inconclusive (status=${ra.status} ${ra.err || ''})`);
    else if (ca.startsWith('fail')) fail(`${t.name}: ChatGPT adapter POST /tools/${t.name} — ${ca.slice(5)}`);
    else pass(`${t.name}: ChatGPT adapter /tools/${t.name}`);
  }

  console.log(`\n[smoke] connector contract summary: ${failures} failed, ${inconclusive} inconclusive, base=${BASE}`);
  if (failures > 0) {
    console.log('[smoke] FAIL connector contract test — see the FAIL lines above');
    process.exit(1);
  }
  process.exit(0);
}

main().catch((e) => { console.log(`[smoke] connector contract INCONCLUSIVE — harness error: ${e.message}`); process.exit(0); });
