// @vitest-environment node
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import http from 'node:http';
import { mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import type { AddressInfo } from 'node:net';
import { GalaxyAPIProxy } from './galaxy-api-proxy';

// Every chat upload failed to create its Galaxy dataset: uploadDataset did require('form-data')
// (throws "Dynamic require ... is not supported" in the ESM server bundle) AND posted a multipart
// file to POST /api/histories/{id}/contents, a JSON-only endpoint. The fix (upload1 tool on
// POST /api/tools, global fetch+FormData) was made 2026-08-10 on side branches but never reached
// this lineage — no test pinned it. Node environment: real fetch/FormData/http.
let server: http.Server;
let base = '';
const calls: Array<{ url: string; body: string }> = [];

beforeAll(async () => {
  server = http.createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      calls.push({ url: req.url || '', body: Buffer.concat(chunks).toString('latin1') });
      res.setHeader('content-type', 'application/json');
      if (req.url === '/api/tools') return res.end(JSON.stringify({ outputs: [{ id: 'hda-123' }] }));
      res.statusCode = 400;
      res.end(JSON.stringify({ err_msg: 'not a file upload endpoint' }));
    });
  });
  await new Promise<void>(r => server.listen(0, '127.0.0.1', () => r()));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => new Promise<void>(r => { server.closeAllConnections(); server.close(() => r()); }));

describe('GalaxyAPIProxy.uploadDataset', () => {
  it('uploads through the upload1 tool on POST /api/tools and returns the new dataset id', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'up-'));
    const file = join(dir, 'stored-name.csv');
    writeFileSync(file, 'compound,ic50\nA,1.2\n');
    const proxy = Object.create(GalaxyAPIProxy.prototype) as any;
    proxy.galaxyUrl = base;
    proxy.apiKey = 'k'.repeat(32);
    calls.length = 0;
    expect(await proxy.uploadDataset(file, 'hist-9', 'predicted_measured.csv')).toBe('hda-123');
    expect(calls.map(c => c.url)).toEqual(['/api/tools']);
    const body = calls[0].body;
    for (const part of ['name="tool_id"', 'upload1', 'name="history_id"', 'hist-9',
                        'name="files_0|file_data"', 'filename="predicted_measured.csv"', 'compound,ic50']) {
      expect(body, part).toContain(part);
    }
    expect(body).toContain('"files_0|NAME":"predicted_measured.csv"');
  });
});

describe('ESM server bundle: no dynamic require()', () => {
  // esbuild --format=esm turns every runtime require() into a throw ("Dynamic require of X is not
  // supported"), which is how uploadDataset failed silently for months. Use static imports.
  it('no server source file calls require()', () => {
    const root = resolve(__dirname);
    const offenders: string[] = [];
    const walk = (d: string) => {
      for (const n of readdirSync(d)) {
        const p = join(d, n);
        if (statSync(p).isDirectory()) { if (n !== 'node_modules') walk(p); continue; }
        if (!/\.ts$/.test(n) || /\.test\.ts$/.test(n)) continue;
        readFileSync(p, 'utf8').split('\n').forEach((line, i) => {
          if (/^\s*(\/\/|\*)/.test(line)) return;
          if (/(^|[^.\w])require\(/.test(line) && !/createRequire/.test(line)) offenders.push(`${p.slice(root.length + 1)}:${i + 1}`);
        });
      }
    };
    walk(root);
    expect(offenders).toEqual([]);
  });
});
