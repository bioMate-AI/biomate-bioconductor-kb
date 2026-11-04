import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { GalaxyAPIProxy, isRejectedGalaxyKey } from './galaxy-api-proxy';

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
    if (key === NEW) return res.end(JSON.stringify({ ok: true, url: req.url }));
    res.statusCode = 401;
    res.end(JSON.stringify({ err_msg: 'Provided API key is not valid.', err_code: 401001 }));
  });
  await new Promise<void>(r => server.listen(0, '127.0.0.1', () => r()));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => new Promise<void>(r => server.close(() => r())));

const admin = () => {
  const p = Object.create(GalaxyAPIProxy.prototype) as GalaxyAPIProxy;
  (p as any).galaxyUrl = base;
  return p;
};
// The suite's global setup is jsdom; pin axios to the Node http adapter the server really uses
// (jsdom's XHR adapter would add a CORS preflight that a real server-side call never sends).
const client = (p: GalaxyAPIProxy) => { const c = (p as any).client; c.defaults.adapter = 'http'; return c; };

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
