import { chromium } from 'playwright';

const BASE_URL = 'http://localhost:5000';
const page = await chromium.launch({ headless: true }).then(b => b.newPage());

// Register
await page.goto(`${BASE_URL}/register`);
await page.waitForLoadState('load');
const email = `debug_${Date.now()}@biomate.test`;
await page.fill('#name', 'Debug User').catch(() => {});
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

// Send GATK query
const textarea = page.locator('textarea').first();
await textarea.fill('Perform variant calling on whole genome sequencing data using GATK');
await textarea.press('Enter');
console.log('[DEBUG] Message sent');

// Wait for response
await page.waitForSelector('[data-testid="chat-response-pending"],[data-is-latest-assistant="true"]', { timeout: 30000 }).catch(() => {});
await page.waitForFunction(() => {
  const latest = document.querySelector('[data-is-latest-assistant="true"]');
  if (!latest) return false;
  const text = latest.textContent ?? '';
  return text.trim().length > 30 && !text.includes('thinking') && !text.includes('Analyzing');
}, { timeout: 120000 }).catch(() => console.log('[DEBUG] waitForFunction timed out'));

await page.waitForTimeout(2000);

// Check testids
const testids = await page.evaluate(() => {
  const els = document.querySelectorAll('[data-testid]');
  return Array.from(els).map(el => el.getAttribute('data-testid'));
});
console.log('[DEBUG] data-testids:', testids.join(', '));

// Check for workflow panel
const panelVisible = await page.getByTestId('workflow-artifact-panel').isVisible({ timeout: 5000 }).catch(() => false);
const btnVisible = await page.getByTestId('button-run-workflow-panel').isVisible({ timeout: 5000 }).catch(() => false);
const qcVisible = await page.getByTestId('qc-settings-section').isVisible({ timeout: 3000 }).catch(() => false);
console.log('[DEBUG] workflow-artifact-panel visible:', panelVisible);
console.log('[DEBUG] button-run-workflow-panel visible:', btnVisible);
console.log('[DEBUG] qc-settings-section visible:', qcVisible);

// Check latest assistant message
const latestText = await page.locator('[data-is-latest-assistant="true"]').textContent().catch(() => '');
console.log('[DEBUG] Latest assistant message (first 500):', latestText?.slice(0, 500));

await page.screenshot({ path: '/tmp/debug-qc-final.png' });
await page.context().browser()?.close();
