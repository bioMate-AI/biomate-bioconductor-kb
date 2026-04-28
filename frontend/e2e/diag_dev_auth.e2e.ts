import { test, expect } from '@playwright/test';

const BASE_URL = 'https://dev-public.biomate.ai';
const E2E_TOKEN = 'biomate-e2e-bypass-token-dev-only';

test('verify dev platform renders chat', async ({ page, context }) => {
  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    data: { fullName: 'Diag', email: `e2e_diag_${Date.now()}@biomate.test`, password: 'TestPass123!', termsAccepted: true },
    headers: { 'X-E2E-Test-Token': E2E_TOKEN }
  });
  const body = await resp.json().catch(() => ({}));
  const jwt = body.token;
  if (jwt) {
    await context.addCookies([{ name: 'biomate_token', value: jwt, domain: 'dev-public.biomate.ai', path: '/', httpOnly: true, sameSite: 'Strict', secure: true }]);
  }
  console.log('JWT:', jwt ? 'found' : 'MISSING');

  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(5000);

  const url = page.url();
  const hasTextarea = await page.locator('textarea').count();
  const bodyText = (await page.locator('body').textContent().catch(() => ''))?.substring(0, 200).replace(/\s+/g, ' ');

  console.log('URL:', url);
  console.log('Textareas:', hasTextarea);
  console.log('Body:', bodyText);

  await page.screenshot({ path: '/tmp/diag_final.png' });
});
