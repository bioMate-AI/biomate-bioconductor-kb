import { chromium } from 'playwright';

const BASE_URL = 'http://localhost:5000';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

// Register
await page.goto(`${BASE_URL}/register`);
const email = `debug2_${Date.now()}@biomate.test`;
await page.fill('#name', 'Debug2').catch(() => {});
await page.fill('#email', email).catch(() => {});
await page.fill('#password', 'TestPass123!').catch(() => {});
await page.fill('#confirmPassword', 'TestPass123!').catch(() => {});
const terms = page.locator('#terms');
if (await terms.isVisible({ timeout: 2000 }).catch(() => false)) await terms.click();
await page.click('button[type="submit"]');
await page.waitForTimeout(2000);
await page.goto(BASE_URL);
await page.waitForLoadState('load');
await page.waitForTimeout(1500);

// Try cryo-EM query
const textarea = page.locator('textarea').first();
await textarea.fill('Run CryoSPARC single-particle analysis cryo-EM workflow');
await textarea.press('Enter');
console.log('[DEBUG2] Message sent');

// Wait for response
await page.waitForFunction(() => {
  const latest = document.querySelector('[data-is-latest-assistant="true"]');
  if (!latest) return false;
  const text = latest.textContent ?? '';
  return text.trim().length > 30 && !text.includes('thinking') && !text.includes('Analyzing');
}, { timeout: 90000 }).catch(() => console.log('[DEBUG2] waitForFunction timed out'));

await page.waitForTimeout(3000);

const panelVisible = await page.getByTestId('workflow-artifact-panel').isVisible({ timeout: 5000 }).catch(() => false);
const btnVisible = await page.getByTestId('button-run-workflow-panel').isVisible({ timeout: 5000 }).catch(() => false);
const qcVisible = await page.getByTestId('qc-settings-section').isVisible({ timeout: 3000 }).catch(() => false);
console.log('[DEBUG2] workflow-artifact-panel:', panelVisible);
console.log('[DEBUG2] button-run-workflow-panel:', btnVisible);
console.log('[DEBUG2] qc-settings-section:', qcVisible);

const latestText = await page.locator('[data-is-latest-assistant="true"]').textContent().catch(() => '');
console.log('[DEBUG2] Assistant message (first 300):', latestText?.slice(0, 300));

const testids = await page.evaluate(() => {
  const els = document.querySelectorAll('[data-testid]');
  return Array.from(els).map(el => el.getAttribute('data-testid')).filter(id => id?.includes('workflow') || id?.includes('qc'));
});
console.log('[DEBUG2] QC/workflow testids:', testids.join(', '));

await browser.close();
