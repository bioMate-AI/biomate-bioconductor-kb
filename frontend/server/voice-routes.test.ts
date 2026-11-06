import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import { request } from 'node:http';
import type { Server } from 'node:http';
import { registerVoiceRoutes } from './voice-routes';

let server: Server;
let port: number;
let upstream = vi.fn();
async function call(path: string, body?: string | Buffer, type = 'application/json', auth = true, extra = {}) {
  return new Promise<{ status: number; body: string }>((resolve, reject) => {
    const req = request({ port, host: '127.0.0.1', path: `/api/voice/${path}`, method: body === undefined ? 'GET' : 'POST', headers: {
      'Content-Type': type, ...(auth ? { authorization: 'unit-user' } : {}), ...extra,
    } }, res => { const chunks: Buffer[] = []; res.on('data', x => chunks.push(x)); res.on('end', () => resolve({ status: res.statusCode!, body: Buffer.concat(chunks).toString() })); });
    req.on('error', reject); req.end(body);
  });
}
beforeEach(async () => {
  vi.stubEnv('BIOMATE_LIVE_VOICE_ENABLED', 'false'); vi.stubEnv('BIOMATE_VOICE_ENABLED', 'true'); vi.stubEnv('ELEVENLABS_API_KEY', 'test-secret'); vi.stubEnv('ELEVENLABS_VOICE_ID', 'voice');
  upstream = vi.fn(); vi.stubGlobal('fetch', upstream);
  const app = express();
  registerVoiceRoutes(app, (req, res, next) => {
    if (!req.headers.authorization) { res.status(401).end(); return; }
    req.user = { id: req.headers.authorization } as any; next();
  });
  app.use((err: any, _req: any, res: any, _next: any) => res.status(err.status || 500).json({ error: 'request_rejected' }));
  await new Promise<void>(resolve => { server = app.listen(0, '127.0.0.1', resolve); });
  port = (server.address() as any).port;
});
afterEach(async () => { await new Promise<void>(r => server.close(() => r())); vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
describe('authenticated voice adapter', () => {
  it('gates live tokens independently and returns only the short-lived token', async () => {
    expect((await call('live-token', '')).status).toBe(503);
    vi.stubEnv('BIOMATE_LIVE_VOICE_ENABLED', 'true');
    upstream.mockResolvedValue(new Response(JSON.stringify({ token: 'single-use-token', internal: 'hidden' })));
    const result = await call('live-token', '');
    expect(result.status).toBe(200);
    expect(JSON.parse(result.body)).toEqual({ token: 'single-use-token' });
    expect(upstream.mock.calls[0][0]).toBe('https://api.elevenlabs.io/v1/single-use-token/realtime_scribe');
    expect((await call('live-token', '')).status).toBe(429);
  });
  it('requires authentication even for availability and never returns secrets', async () => {
    expect((await call('status', undefined, undefined, false)).status).toBe(401);
    expect(JSON.parse((await call('status')).body)).toEqual({ available: true, liveAvailable: false });
    expect(upstream).not.toHaveBeenCalled();
  });
  it('fails closed when disabled or missing a voice', async () => {
    vi.stubEnv('BIOMATE_VOICE_ENABLED', 'false');
    expect((await call('speak', '{"text":"hello"}')).status).toBe(503);
    vi.stubEnv('BIOMATE_VOICE_ENABLED', 'true'); vi.stubEnv('ELEVENLABS_VOICE_ID', '');
    expect(JSON.parse((await call('status')).body).available).toBe(false);
    expect(upstream).not.toHaveBeenCalled();
  });
  it('rejects cross-site requests, unsupported audio, empty and overlong text', async () => {
    expect((await call('speak', '{"text":"hi"}', 'application/json', true, { 'sec-fetch-site': 'cross-site' })).status).toBe(403);
    expect((await call('transcribe', 'data', 'text/plain')).status).toBe(415);
    for (const text of ['', 'x'.repeat(5001)]) expect((await call('speak', JSON.stringify({ text }))).status).toBe(400);
    expect(upstream).not.toHaveBeenCalled();
  });
  it('rejects oversized audio before the provider call', async () => {
    expect((await call('transcribe', Buffer.alloc(6 * 1024 * 1024 + 1), 'audio/webm')).status).toBe(413);
    expect(upstream).not.toHaveBeenCalled();
  });
  it('passes bilingual text unchanged and returns audio', async () => {
    upstream.mockResolvedValue(new Response(new Uint8Array([1, 2]), { headers: { 'content-type': 'audio/mpeg' } }));
    expect((await call('speak', JSON.stringify({ text: '检查 BRCA1 和 TP53。' }))).status).toBe(200);
    expect(JSON.parse(upstream.mock.calls[0][1].body).text).toBe('检查 BRCA1 和 TP53。');
    expect(upstream.mock.calls[0][1].headers['xi-api-key']).toBe('test-secret');
  });
  it('returns only transcript text, not provider metadata', async () => {
    upstream.mockResolvedValue(new Response(JSON.stringify({ text: '  检查 TP53  ', words: [], private: 'omit' })));
    const r = await call('transcribe', Buffer.from([1, 2, 3]), 'audio/webm');
    expect(r.status).toBe(200); expect(JSON.parse(r.body)).toEqual({ text: '检查 TP53' });
  });
  it('handles silence and conceals provider errors', async () => {
    upstream.mockResolvedValueOnce(new Response('{"text":" "}'));
    expect((await call('transcribe', Buffer.from([1]), 'audio/webm')).status).toBe(422);
    upstream.mockResolvedValueOnce(new Response('secret upstream detail', { status: 401 }));
    const result = await call('speak', '{"text":"hello"}');
    expect(result.status).toBe(502); expect(result.body).not.toContain('secret');
  });
  it('limits paid requests per authenticated user', async () => {
    upstream.mockResolvedValue(new Response('error', { status: 503 }));
    for (let i = 0; i < 12; i++) await call('speak', '{"text":"hello"}');
    expect((await call('speak', '{"text":"hello"}')).status).toBe(429);
    expect(upstream).toHaveBeenCalledTimes(12);
  });
});
