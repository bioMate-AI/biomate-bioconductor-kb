import express, { type Express, type RequestHandler } from 'express';
import rateLimit from 'express-rate-limit';

const AUDIO_TYPES = new Set(['audio/webm', 'audio/ogg', 'audio/mp4', 'audio/wav', 'audio/mpeg']);
const MAX_TEXT = 5000;

/** Audio only: analysis requests continue through the existing chat/approval flow. */
export function registerVoiceRoutes(app: Express, authenticate: RequestHandler) {
  const config = () => ({
    enabled: process.env.BIOMATE_VOICE_ENABLED === 'true',
    key: process.env.ELEVENLABS_API_KEY,
    voice: process.env.ELEVENLABS_VOICE_ID,
  });
  const available = () => { const c = config(); return Boolean(c.enabled && c.key && c.voice); };
  const limit = rateLimit({ windowMs: 60_000, limit: 12,
    keyGenerator: req => String(req.user!.id),
    message: { error: 'voice_rate_limited' }, standardHeaders: 'draft-8', legacyHeaders: false });
  app.get('/api/voice/status', authenticate, (_req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.json({ available: available(), liveAvailable: available() && process.env.BIOMATE_LIVE_VOICE_ENABLED === "true" });
  });
  const ready: RequestHandler = (req, res, next) => {
    res.setHeader('Cache-Control', 'no-store');
    // Cookie-authenticated audio uploads must originate from the BioMate UI.
    if (req.get('sec-fetch-site') === 'cross-site') { res.status(403).json({ error: 'voice_forbidden' }); return; }
    if (!available()) { res.status(503).json({ error: 'voice_unavailable' }); return; }
    next();
  };
  const sessionLimit = rateLimit({ windowMs: 60_000, limit: 2,
    keyGenerator: req => String(req.user!.id), message: { error: 'voice_rate_limited' }, legacyHeaders: false });
  app.post('/api/voice/live-token', authenticate, ready, sessionLimit, async (_req, res) => {
    if (process.env.BIOMATE_LIVE_VOICE_ENABLED !== 'true') { res.status(503).json({ error: 'voice_unavailable' }); return; }
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 15_000);
    const disconnect = () => { if (!res.writableEnded) abort.abort(); };
    res.on('close', disconnect);
    try {
      const upstream = await fetch('https://api.elevenlabs.io/v1/single-use-token/realtime_scribe', {
        method: 'POST', headers: { 'xi-api-key': config().key! }, signal: abort.signal,
      });
      if (!upstream.ok) { await upstream.body?.cancel(); throw new Error('Provider rejected token'); }
      const data = await upstream.json();
      if (typeof data.token !== 'string' || !data.token) throw new Error('Invalid token');
      res.json({ token: data.token });
    } catch { if (!res.destroyed) res.status(502).json({ error: 'voice_provider_unavailable' }); }
    finally { clearTimeout(timer); res.off('close', disconnect); }
  });
  const perform = (operation: (req: express.Request, signal: AbortSignal) => Promise<Response>): RequestHandler => async (req, res) => {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 45_000);
    const disconnect = () => { if (!res.writableEnded) abort.abort(); };
    res.on('close', disconnect);
    try {
      const upstream = await operation(req, abort.signal);
      if (!upstream.ok) {
        await upstream.body?.cancel();
        res.status(upstream.status === 429 ? 429 : 502).json({ error: 'voice_provider_unavailable' }); return;
      }
      if (req.path.endsWith('/transcribe')) {
        const result = await upstream.json();
        if (typeof result.text !== 'string' || !result.text.trim()) { res.status(422).json({ error: 'voice_no_speech' }); return; }
        res.json({ text: result.text.trim() });
      } else {
        if (!upstream.headers.get('content-type')?.startsWith('audio/')) throw new Error('Invalid audio');
        const audio = Buffer.from(await upstream.arrayBuffer());
        if (!audio.length) throw new Error('Empty audio');
        res.type('audio/mpeg').send(audio);
      }
    } catch {
      if (!res.destroyed) res.status(502).json({ error: 'voice_provider_unavailable' });
    } finally { clearTimeout(timer); res.off('close', disconnect); }
  };
  const audioType: RequestHandler = (req, res, next) => {
    if (!AUDIO_TYPES.has((req.get('content-type') || '').split(';')[0].trim())) {
      res.status(415).json({ error: 'voice_invalid_audio' }); return;
    }
    next();
  };
  app.post('/api/voice/transcribe', authenticate, ready, limit, audioType,
    express.raw({ type: () => true, limit: '6mb' }),
    (req, res, next) => {
      if (!Buffer.isBuffer(req.body) || !req.body.length) { res.status(400).json({ error: 'voice_invalid_audio' }); return; }
      next();
    }, perform(async (req, signal) => {
      const type = req.get('content-type')!.split(';')[0];
      const ext: Record<string, string> = { 'audio/webm': 'webm', 'audio/ogg': 'ogg', 'audio/mp4': 'm4a', 'audio/wav': 'wav', 'audio/mpeg': 'mp3' };
      const form = new FormData();
      form.append('file', new Blob([new Uint8Array(req.body)], { type }), `recording.${ext[type]}`);
      form.append('model_id', 'scribe_v2');
      form.append('tag_audio_events', 'false');
      return fetch('https://api.elevenlabs.io/v1/speech-to-text', { method: 'POST', headers: { 'xi-api-key': config().key! }, body: form, signal });
    }));
  app.post('/api/voice/speak', authenticate, ready, limit, express.json({ limit: '32kb' }),
    (req, res, next) => {
      const text = req.body?.text;
      if (typeof text !== 'string' || !text.trim() || text.length > MAX_TEXT) { res.status(400).json({ error: 'voice_invalid_text' }); return; }
      next();
    }, perform((req, signal) => fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(config().voice!)}?output_format=mp3_44100_128`, {
      method: 'POST', headers: { 'xi-api-key': config().key!, 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: req.body.text.trim(), model_id: 'eleven_multilingual_v2' }), signal,
    })));
}
