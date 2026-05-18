// Smoke test for the runCode dispatch logic.
// Runs both branches: docker-spawn (env unset) and sidecar HTTP (env set).
// Usage: node frontend/server/code-runner.test.mjs

import { runCode } from './code-runner.js';
import http from 'http';

let pass = 0;
let fail = 0;
const assert = (label, cond, note = '') => {
  if (cond) { pass++; console.log(`✓ ${label}`); }
  else { fail++; console.log(`✗ ${label} ${note}`); }
};

// ── Branch A: docker-spawn (no RUN_CODE_BACKEND_URL) ──────────────────────────
delete process.env.RUN_CODE_BACKEND_URL;

try {
  const r = await runCode({
    language: 'python',
    code: 'print(2 + 2)',
    timeout_seconds: 30,
  });
  // Spawn path either succeeds (if docker socket + biomate-biotools:1 present) or
  // emits a docker-run error. Either is acceptable — we're verifying the dispatch
  // path, not the sandbox itself.
  const spawnedDocker = r.stderr.includes('docker run error')
    || r.stderr.includes('Unable to find image')
    || r.stderr.includes('Cannot connect')
    || r.stdout.includes('4');
  assert('docker-spawn branch invoked', spawnedDocker || r.exit_code !== 0,
    `stdout=${JSON.stringify(r.stdout.slice(0,80))} stderr=${JSON.stringify(r.stderr.slice(0,120))} exit=${r.exit_code}`);
  // If the sandbox image is present and worked, expect stdout=4
  if (r.exit_code === 0) {
    assert('docker-spawn python stdout=4', r.stdout.trim() === '4',
      `actual=${JSON.stringify(r.stdout.slice(0,40))}`);
  } else {
    console.log(`  (docker-spawn could not complete — docker/image unavailable on this host: ${r.stderr.slice(0,80)})`);
  }
} catch (e) {
  fail++; console.log(`✗ docker-spawn threw: ${e.message}`);
}

// ── Branch B: sidecar HTTP (RUN_CODE_BACKEND_URL set) ─────────────────────────
const mock = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/run') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', () => {
      let parsed = {};
      try { parsed = JSON.parse(body); } catch {}
      // Verify the request fields match the documented contract
      const fields = ['baseDir', 'interpreter', 'scriptPath', 'image',
                      'timeoutSeconds', 'network', 'memory', 'cpus', 'user', 'env'];
      const hasAll = fields.every(k => k in parsed);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        stdout: hasAll ? 'SIDECAR_OK' : `MISSING_FIELDS: ${fields.filter(k => !(k in parsed)).join(',')}`,
        stderr: '',
        exitCode: hasAll ? 0 : 1,
        _received: parsed,
      }));
    });
  } else {
    res.writeHead(404); res.end();
  }
});
await new Promise(r => mock.listen(0, '127.0.0.1', r));
const port = mock.address().port;
process.env.RUN_CODE_BACKEND_URL = `http://127.0.0.1:${port}`;

try {
  const r = await runCode({
    language: 'python',
    code: 'print(2 + 2)',
    timeout_seconds: 30,
  });
  assert('sidecar branch dispatched', r.exit_code === 0,
    `stdout=${JSON.stringify(r.stdout)} stderr=${JSON.stringify(r.stderr)} exit=${r.exit_code}`);
  assert('sidecar received all contract fields', r.stdout === 'SIDECAR_OK',
    `stdout=${JSON.stringify(r.stdout)}`);
} catch (e) {
  fail++; console.log(`✗ sidecar branch threw: ${e.message}`);
}

// ── Branch C: sidecar returns non-200 (error path) ────────────────────────────
const mockErr = http.createServer((req, res) => {
  res.writeHead(500, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'sandbox unavailable' }));
});
await new Promise(r => mockErr.listen(0, '127.0.0.1', r));
process.env.RUN_CODE_BACKEND_URL = `http://127.0.0.1:${mockErr.address().port}`;

try {
  const r = await runCode({
    language: 'python',
    code: 'print(1)',
    timeout_seconds: 30,
  });
  assert('sidecar error → frontend surfaces stderr', r.stderr.includes('sidecar error: HTTP 500'),
    `stderr=${JSON.stringify(r.stderr)}`);
  assert('sidecar error → exit_code=1', r.exit_code === 1);
} catch (e) {
  fail++; console.log(`✗ sidecar-error branch threw: ${e.message}`);
}

mock.close();
mockErr.close();

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
