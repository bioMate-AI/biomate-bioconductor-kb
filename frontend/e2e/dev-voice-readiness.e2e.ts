import { test, expect } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { loginAsFixture, BASE_URL } from './_fixture-login';

test('dev voice availability and authenticated UI', async ({ page, playwright }) => {
  test.setTimeout(120_000);
  expect(new URL(BASE_URL).hostname).toBe('dev-public.biomate.ai');
  const output = path.resolve(`../docs/qa/20261108-voice/dev-${Date.now()}`);
  mkdirSync(output, { recursive: true });
  const anon = await playwright.request.newContext();
  const denied = await anon.get(`${BASE_URL}/api/voice/status`);
  await anon.dispose();
  expect(denied.status()).toBe(401);
  await loginAsFixture(page);
  const build = await page.request.get(`${BASE_URL}/build-info.json`);
  const status = await page.request.get(`${BASE_URL}/api/voice/status`);
  expect(status.ok()).toBe(true);
  const availability = await status.json();
  expect(typeof availability.available).toBe('boolean');
  expect(typeof availability.liveAvailable).toBe('boolean');
  // Voice chrome is opt-in via Settings → Chat → Voice (compact composer icons).
  await page.addInitScript(() => {
    localStorage.setItem('biomate-user-settings', JSON.stringify({
      id: 'e2e-voice', voiceEnabled: true, voiceHandsFree: false, updatedAt: new Date().toISOString(),
    }));
  });
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  await expect(page.getByTestId('chat-input')).toBeVisible({ timeout: 45_000 });
  const speak = page.getByRole('button', { name: 'Speak', exact: true });
  const live = page.getByRole('button', { name: 'Start voice', exact: true });
  if (availability.available) await expect(speak).toBeVisible(); else await expect(speak).toHaveCount(0);
  if (availability.liveAvailable) await expect(live).toBeVisible(); else await expect(live).toHaveCount(0);
  await page.screenshot({ path: path.join(output, 'voice-workbench.png') });
  const result = { timestamp: new Date().toISOString(), build: await build.json(), availability, anonymousStatus: denied.status(), uiMatchesAvailability: true, audioFlow: 'not exercised by readiness check' };
  writeFileSync(path.join(output, 'readiness.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
});
