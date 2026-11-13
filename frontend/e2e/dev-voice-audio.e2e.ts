/** Real dev + ElevenLabs; synthetic audio enters Chrome's fake microphone device. */
import { test, expect, chromium } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { loginAsFixture, BASE_URL } from './_fixture-login';
test.use({ screenshot: 'off' }); // The actual voice page is a separately launched microphone-enabled browser.

test('dev voice: dictation, live review, reply playback and Chinese UI', async ({ page }) => {
  test.setTimeout(180_000);
  expect(new URL(BASE_URL).hostname).toBe('dev-public.biomate.ai');
  const output = path.resolve(`../docs/qa/20261108-voice/audio-${Date.now()}`);
  mkdirSync(output, { recursive: true });
  await loginAsFixture(page);
  await page.context().setExtraHTTPHeaders({}); // Exercise cookie auth; don't forward fixture headers to ElevenLabs.
  const status = await page.request.get(`${BASE_URL}/api/voice/status`);
  expect(await status.json()).toEqual({ available: true, liveAvailable: true });
  const checks: Record<string, unknown> = {};
  for (const [lang, text] of [['en', 'Please repeat BRCA1 and TP53.'], ['zh', '请检查 BRCA1 和 TP53。']]) {
    const speech = await page.request.post(`${BASE_URL}/api/voice/speak`, { data: { text } });
    expect(speech.ok()).toBe(true);
    expect(speech.headers()['content-type']).toContain('audio/');
    const bytes = await speech.body();
    writeFileSync(path.join(output, `${lang}.mp3`), bytes);
    const transcript = await page.request.post(`${BASE_URL}/api/voice/transcribe`, { data: bytes, headers: { 'Content-Type': 'audio/mpeg' } });
    expect(transcript.ok()).toBe(true);
    const body = await transcript.json();
    expect(body.text).toMatch(/BRCA\s*1/i); expect(body.text).toMatch(/TP\s*53/i);
    checks[`${lang}ProviderRoundTrip`] = { bytes: bytes.length, transcript: body.text };
    console.log(`${lang} real provider round trip passed`);
  }
  const wav = path.join(output, 'microphone.wav');
  execFileSync(process.env.FFMPEG || '/Users/kky/opt/anaconda3/bin/ffmpeg', ['-y','-loglevel','error','-i',path.join(output,'en.mp3'),'-af','adelay=1000,apad=pad_dur=20','-ar','48000','-ac','1',wav]);
  const session = `voice-acceptance-${crypto.randomUUID()}`;
  const saved = await page.request.post(`${BASE_URL}/api/sessions`, { data: { session_id: session, title: 'Voice acceptance — synthetic test', messages: [{ id: crypto.randomUUID(), role: 'assistant', content: 'Voice acceptance test. BRCA1 and TP53 are gene symbols.', timestamp: new Date().toISOString() }] } });
  expect(saved.ok()).toBe(true);
  const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream',`--use-file-for-fake-audio-capture=${wav}`] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, locale: 'en-US', permissions: ['microphone'] });
  await context.addCookies(await page.context().cookies());
  await context.addInitScript(() => {
    localStorage.setItem('biomate-user-settings', JSON.stringify({
      id: 'e2e-voice', voiceEnabled: true, voiceHandsFree: false, updatedAt: new Date().toISOString(),
    }));
    const capture = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    (window as any).__voiceStreams = [];
    navigator.mediaDevices.getUserMedia = async constraints => {
      const stream = await capture(constraints); (window as any).__voiceStreams.push(stream); return stream;
    };
    const play = HTMLMediaElement.prototype.play;
    (window as any).__voicePlays = 0;
    HTMLMediaElement.prototype.play = async function () {
      await play.call(this); (window as any).__voicePlays++;
    };
  });
  const voice = await context.newPage();
  const voiceRequests: Array<{ path: string; status: number }> = [];
  voice.on('response', response => {
    const pathname = new URL(response.url()).pathname;
    if (pathname.startsWith('/api/voice/')) voiceRequests.push({ path: pathname, status: response.status() });
  });
  try {
    await voice.goto(`${BASE_URL}/?session=${session}`, { waitUntil: 'domcontentloaded' });
    await expect(voice.getByTestId('chat-input')).toBeVisible();
    console.log('Voice test conversation loaded');
    await voice.getByRole('button', { name: 'Speak', exact: true }).click();
    await expect(voice.getByRole('button', { name: 'Stop', exact: true })).toBeVisible();
    await voice.waitForTimeout(7500); // Allow the real synthetic microphone sentence to complete.
    await voice.getByRole('button', { name: 'Stop', exact: true }).click();
    await expect(voice.getByTestId('chat-input')).toHaveValue(/BRCA\s*1.*TP\s*53/i, { timeout: 45_000 });
    checks.batchDictation = await voice.getByTestId('chat-input').inputValue();
    console.log('Browser microphone dictation passed');
    await voice.getByTestId('chat-input').fill('');
    await voice.getByRole('button', { name: 'Start voice', exact: true }).click();
    await expect(voice.getByTestId('composer-voice-live')).toHaveAttribute('data-voice-state', 'listening', { timeout: 30_000 });
    await expect(voice.getByTestId('chat-input')).toHaveValue(/BRCA\s*1.*TP\s*53/i, { timeout: 35_000 });
    checks.liveDraft = await voice.getByTestId('chat-input').inputValue();
    console.log('Live microphone transcript reached composer for review');
    await voice.getByRole('button', { name: 'Mute', exact: true }).click();
    await expect(voice.getByRole('button', { name: 'Mute', exact: true })).toHaveAttribute('aria-pressed', 'true');
    await voice.getByTestId('chat-send-button').click();
    await expect.poll(() => voice.evaluate(() => (window as any).__voicePlays), { timeout: 60_000 }).toBeGreaterThan(0);
    checks.replyPlayback = true;
    await voice.getByRole('button', { name: 'End voice', exact: true }).click();
    expect(await voice.evaluate(() => (window as any).__voiceStreams.every((s: MediaStream) => s.getTracks().every(t => t.readyState === 'ended')))).toBe(true);
    checks.microphoneReleased = true;
    await voice.screenshot({ path: path.join(output, 'english-voice.png') });
    await voice.evaluate(() => localStorage.setItem('biomate-user-settings', JSON.stringify({ language: 'chinese' })));
    await voice.reload({ waitUntil: 'domcontentloaded' });
    await expect(voice.getByRole('button', { name: '开始语音', exact: true })).toBeVisible();
    await expect(voice.getByRole('button', { name: '语音输入', exact: true })).toBeVisible();
    checks.chineseControls = true;
    await voice.screenshot({ path: path.join(output, 'chinese-voice.png') });
  } catch (error) {
    checks.failure = error instanceof Error ? error.message : String(error);
    checks.voiceRequests = voiceRequests;
    console.log('Voice browser check failed:', checks.failure);
    await voice.screenshot({ path: path.join(output, 'failure.png'), timeout: 5000 }).catch(() => {});
    throw error;
  } finally {
    await browser.close();
    const deleted = await page.request.delete(`${BASE_URL}/api/sessions/${session}`);
    checks.cleanedUp = deleted.ok();
    writeFileSync(path.join(output, 'audio-results.json'), JSON.stringify({ timestamp: new Date().toISOString(), fixture: 'synthetic Chrome microphone; not physical microphone or acoustic listening certification', checks }, null, 2));
    expect(deleted.ok()).toBe(true);
  }
});
