import { chromium } from 'playwright';

const BASE_URL = 'http://localhost:5000';
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

await page.goto(`${BASE_URL}/register`);
const email = `debug3_${Date.now()}@biomate.test`;
await page.fill('#name', 'Debug3').catch(() => {});
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

const textarea = page.locator('textarea').first();
await textarea.fill('Perform variant calling on whole genome sequencing data using GATK');
await textarea.press('Enter');
console.log('[DEBUG3] GATK query sent');

await page.waitForFunction(() => {
  const latest = document.querySelector('[data-is-latest-assistant="true"]');
  if (!latest) return false;
  const text = latest.textContent ?? '';
  return text.trim().length > 30 && !text.includes('thinking') && !text.includes('Analyzing');
}, { timeout: 120000 }).catch(() => console.log('[DEBUG3] waitForFunction timed out'));

await page.waitForTimeout(3000);

const panelVisible = await page.getByTestId('workflow-artifact-panel').isVisible({ timeout: 5000 }).catch(() => false);
const btnVisible = await page.getByTestId('button-run-workflow-panel').isVisible({ timeout: 5000 }).catch(() => false);
const qcVisible = await page.getByTestId('qc-settings-section').isVisible({ timeout: 3000 }).catch(() => false);
console.log('[DEBUG3] workflow-artifact-panel:', panelVisible);
console.log('[DEBUG3] button-run-workflow-panel:', btnVisible);
console.log('[DEBUG3] qc-settings-section:', qcVisible);

const latestText = await page.locator('[data-is-latest-assistant="true"]').textContent().catch(() => '');
console.log('[DEBUG3] Assistant message (first 300):', latestText?.slice(0, 300));

await browser.close();
