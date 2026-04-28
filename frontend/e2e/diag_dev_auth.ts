import { chromium } from 'playwright';

const BASE_URL = 'https://dev-public.biomate.ai';
const E2E_TOKEN = 'biomate-e2e-bypass-token-dev-only';

(async () => {
  // Step 1: Register/login to get JWT
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext();
  const page = await ctx.newPage();

  console.log('Step 1: Get JWT from dev platform...');
  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    data: { fullName: 'Diag User', email: 'e2e_diag_auth_check@biomate.test', password: 'TestPass123!', termsAccepted: true },
    headers: { 'X-E2E-Test-Token': E2E_TOKEN }
  });
  const body = await resp.json().catch(() => ({}));
  const jwt = body.token || null;
  console.log('JWT obtained:', jwt ? jwt.substring(0, 30) + '...' : 'NONE');
  console.log('Register HTTP:', resp.status());

  if (!jwt) {
    // Try login
    const loginResp = await page.request.post(`${BASE_URL}/api/auth/login`, {
      data: { email: 'e2e_diag_auth_check@biomate.test', password: 'TestPass123!' },
      headers: { 'X-E2E-Test-Token': E2E_TOKEN }
    });
    const loginBody = await loginResp.json().catch(() => ({}));
    console.log('Login HTTP:', loginResp.status(), 'token:', loginBody.token ? 'found' : 'missing');
  }

  // Step 2: Inject cookie
  if (jwt) {
    const u = new URL(BASE_URL);
    await ctx.addCookies([{ name: 'biomate_token', value: jwt, domain: u.hostname, path: '/', httpOnly: true, sameSite: 'Strict', secure: true }]);
    console.log('Cookie injected for domain:', u.hostname);
  }

  // Step 3: Navigate and check
  page.on('console', msg => console.log('CONSOLE:', msg.type(), msg.text().substring(0, 100)));
  page.on('pageerror', err => console.log('PAGE ERROR:', err.message.substring(0, 200)));

  console.log('Step 3: Navigate to', BASE_URL);
  await page.goto(BASE_URL, { waitUntil: 'networkidle', timeout: 30000 }).catch(e => console.log('goto error:', e.message));
  await page.waitForTimeout(3000);

  const url = page.url();
  const title = await page.title();
  const hasTextarea = await page.locator('textarea').count();
  const bodyText = await page.locator('body').textContent().catch(() => '');

  console.log('Final URL:', url);
  console.log('Title:', title);
  console.log('Textareas:', hasTextarea);
  console.log('Body preview:', bodyText?.substring(0, 200).replace(/\s+/g, ' '));

  // Check /api/auth/me
  const meResp = await page.request.get(`${BASE_URL}/api/auth/me`);
  const meBody = await meResp.json().catch(() => ({}));
  console.log('Auth/me:', meResp.status(), 'user:', meBody.user?.email || 'NOT AUTHENTICATED');

  await page.screenshot({ path: '/tmp/diag_screenshot.png', fullPage: false });
  console.log('Screenshot saved to /tmp/diag_screenshot.png');

  await browser.close();
})().catch(console.error);
