import { test } from '@playwright/test';

const BASE_URL = 'http://localhost:5000';
const E2E_TOKEN = 'biomate-e2e-bypass-token-dev-only';

test('Take comparison screenshots', async ({ page }) => {
  test.setTimeout(120000);
  page.on('pageerror', e => console.error('PAGE ERR:', e.message));

  const email = `screenshot_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ 'x-e2e-test-token': E2E_TOKEN });
  await page.context().clearCookies();

  // Register
  await page.goto(`${BASE_URL}/register`);
  await page.waitForSelector('#name', { timeout: 8000 }).catch(() => {});
  await page.fill('#name', 'SS User').catch(() => page.fill('#fullName', 'SS User').catch(() => {}));
  await page.fill('#email', email);
  await page.fill('#password', 'Test2026!');
  await page.fill('#confirmPassword', 'Test2026!').catch(() => {});
  await page.click('#terms').catch(() => {});
  await page.click('button[type="submit"]');
  await page.waitForTimeout(2500);
  await page.goto(BASE_URL);
  await page.waitForSelector('textarea', { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(1500);

  // Screenshot 1: Welcome/empty chat state
  await page.screenshot({ path: '/tmp/app_01_welcome.png' });
  console.log('SS1: welcome');

  // Click genomics domain
  await page.locator('[data-testid="onboarding-domain-btn-genomics"]').click().catch(() => {});
  await page.waitForTimeout(500);
  await page.screenshot({ path: '/tmp/app_02_domain_selected.png' });
  console.log('SS2: domain selected');

  // Send a query
  await page.locator('textarea').first().fill('Run ADMET property prediction for aspirin. SMILES: CC(=O)Oc1ccccc1C(=O)O. Do not ask for clarification.');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(1500);
  await page.screenshot({ path: '/tmp/app_03_after_send.png' });
  console.log('SS3: after send');

  // Wait for AI response
  await page.waitForFunction(() => {
    const el = document.querySelector('[data-is-latest-assistant="true"]');
    return el && (el.textContent?.length ?? 0) > 30;
  }, { timeout: 90000 });
  await page.waitForTimeout(1000);
  await page.screenshot({ path: '/tmp/app_04_ai_response.png' });
  console.log('SS4: AI responded');

  // Wait for workflow panel to open
  const panelOpen = await page.waitForSelector('[data-testid="workflow-artifact-panel"]', { timeout: 60000 }).then(() => true).catch(() => false);
  if (panelOpen) {
    await page.waitForTimeout(1000);
    await page.screenshot({ path: '/tmp/app_05_panel_open.png' });
    console.log('SS5: panel open with workflow');
  }

  console.log('Screenshots complete');
});
