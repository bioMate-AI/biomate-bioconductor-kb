// @vitest-environment node
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { GalaxyAPIProxy, fetchGalaxyWithKeyRecovery, isRejectedGalaxyKey } from './galaxy-api-proxy';

// Mid-session key recovery (2026-11-03). A per-user Galaxy key was only validated at login,
// so when Galaxy started rejecting it during a session every request failed with 401
// "Provided API key is not valid." until the next login. A real axios client against a local
// HTTP server that behaves like Galaxy: OLD key rejected (401001), NEW key accepted.
const OLD = 'a'.repeat(32);
const NEW = 'b'.repeat(32);
let server: http.Server;
let base = '';
const seen: string[] = [];

beforeAll(async () => {
  server = http.createServer((req, res) => {
    const key = String(req.headers['x-api-key'] || '');
    seen.push(`${req.url}:${key.slice(0, 1)}`);
    res.setHeader('content-type', 'application/json');
    if (req.url === '/api/forbidden') {
      res.statusCode = 401;
      return res.end(JSON.stringify({ err_msg: 'You must be logged in', err_code: 401000 }));
    }
    if (key === NEW) {
      const chunks: Buffer[] = [];
      req.on('data', c => chunks.push(c));
      return req.on('end', () => res.end(JSON.stringify({ ok: true, url: req.url, body: Buffer.concat(chunks).toString() })));
    }
    // like a real server, read the request before answering (an unread upload stalls the sender)
    req.resume();
    req.on('end', () => {
      res.statusCode = 401;
      res.end(JSON.stringify({ err_msg: 'Provided API key is not valid.', err_code: 401001 }));
    });
  });
  await new Promise<void>(r => server.listen(0, '127.0.0.1', () => r()));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => new Promise<void>(r => { server.closeAllConnections(); server.close(() => r()); }));

const admin = () => {
  const p = Object.create(GalaxyAPIProxy.prototype) as GalaxyAPIProxy;
  (p as any).galaxyUrl = base;
  return p;
};
// Node environment (top of file): the real fetch / FormData / http adapter the server uses —
// jsdom's substitutes add CORS preflights and can't be sent by Node's fetch.
const client = (p: GalaxyAPIProxy) => (p as any).client;

describe('per-user Galaxy key — mid-session recovery', () => {
  it('re-provisions once on a rejected key, retries the request, and keeps the new key', async () => {
    seen.length = 0;
    const recover = vi.fn().mockResolvedValue(NEW);
    const proxy = admin().forUser(OLD, recover);
    expect((await client(proxy).get('/api/histories')).data.ok).toBe(true);
    expect((await client(proxy).get('/api/datasets')).data.ok).toBe(true);
    expect(recover).toHaveBeenCalledTimes(1);
    // first request: OLD (rejected) then NEW (retry); second request goes straight out with NEW
    expect(seen).toEqual(['/api/histories:a', '/api/histories:b', '/api/datasets:b']);
  });

  it('surfaces the original error when recovery yields no new key (no retry loop)', async () => {
    for (const fresh of [null, OLD]) {
      const recover = vi.fn().mockResolvedValue(fresh);
      const proxy = admin().forUser(OLD, recover);
      await expect(client(proxy).get('/api/histories')).rejects.toMatchObject({ status_code: 401 });
      expect(recover).toHaveBeenCalledTimes(1);
    }
  });

  it('does not treat other 401s as a rejected key', async () => {
    const recover = vi.fn().mockResolvedValue(NEW);
    const proxy = admin().forUser(NEW, recover);
    await expect(client(proxy).get('/api/forbidden')).rejects.toMatchObject({ status_code: 401 });
    expect(recover).not.toHaveBeenCalled();
  });

  it('without a recovery hook behaves exactly as before', async () => {
    const proxy = admin().forUser(OLD);
    await expect(client(proxy).get('/api/histories')).rejects.toMatchObject({ status_code: 401 });
  });

  it('isRejectedGalaxyKey matches both Galaxy wordings of 401001 only', () => {
    const e = (status: number, data: any) => ({ response: { status, data } });
    expect(isRejectedGalaxyKey(e(401, { err_code: 401001, err_msg: 'Provided API key is not valid.' }))).toBe(true);
    expect(isRejectedGalaxyKey(e(401, { err_msg: 'Provided API key has expired.' }))).toBe(true);
    expect(isRejectedGalaxyKey(e(401, { err_code: 401000, err_msg: 'You must be logged in' }))).toBe(false);
    expect(isRejectedGalaxyKey(e(403, { err_code: 401001 }))).toBe(false);
    expect(isRejectedGalaxyKey({ code: 'ECONNREFUSED' })).toBe(false);
  });
});

// The routes that call Galaxy with fetch() directly (drug-discovery / ind-report / regulatory /
// grounded / DL passthroughs, IND attachment upload) use the same recovery.
describe('fetchGalaxyWithKeyRecovery — direct-fetch routes', () => {
  it('recovers a rejected user key, retries, and the returned body is readable', async () => {
    const recover = vi.fn().mockResolvedValue(NEW);
    const resp = await fetchGalaxyWithKeyRecovery(`${base}/api/regulatory/x`, { method: 'POST',
      headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ q: 1 }) }, OLD, 'admin-key', recover);
    expect(resp.status).toBe(200);
    expect((await resp.json()).body).toBe('{"q":1}');
    expect(recover).toHaveBeenCalledTimes(1);
  });

  it('re-sends a multipart (FormData) body intact on the retry', async () => {
    const fd = new FormData();
    fd.append('file', new Blob(['ATTACHMENT-BYTES']), 'a.txt');
    const resp = await fetchGalaxyWithKeyRecovery(`${base}/api/ind-report/projects/p/attachments`,
      { method: 'POST', body: fd }, OLD, 'admin-key', async () => NEW);
    expect(resp.status).toBe(200);
    expect((await resp.json()).body).toContain('ATTACHMENT-BYTES');
  });

  it('returns the original 401 (readable) when recovery yields nothing new', async () => {
    for (const fresh of [null, OLD]) {
      const resp = await fetchGalaxyWithKeyRecovery(`${base}/api/x`, {}, OLD, 'admin-key', async () => fresh);
      expect(resp.status).toBe(401);
      expect((await resp.json()).err_code).toBe(401001);
    }
  });

  it('never recovers the shared admin key or other 401s', async () => {
    const recover = vi.fn().mockResolvedValue(NEW);
    expect((await fetchGalaxyWithKeyRecovery(`${base}/api/x`, {}, null, OLD, recover)).status).toBe(401);
    expect((await fetchGalaxyWithKeyRecovery(`${base}/api/forbidden`, {}, NEW, 'admin-key', recover)).status).toBe(401);
    expect(recover).not.toHaveBeenCalled();
  });
});
