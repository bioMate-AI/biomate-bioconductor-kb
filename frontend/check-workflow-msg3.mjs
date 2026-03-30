import { chromium } from 'playwright';
import { mkdirSync } from 'fs';

const DIR = '/tmp/biomate-check3';
mkdirSync(DIR, { recursive: true });
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const allLogs = [];
page.on('console', msg => allLogs.push(`[${msg.type()}|${Date.now()}] ${msg.text().slice(0, 400)}`));
page.on('pageerror', err => allLogs.push(`[PAGE_ERROR] ${err.message}`));

await page.goto('http://localhost:5000', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1000);
const url = page.url();
if (url.includes('/auth')) {
  const email = `audit3_${Date.now()}@test.com`;
  const tab = page.locator('[role="tab"]:has-text("Register"), button:has-text("Register")').first();
  if (await tab.count()) await tab.click();
  await page.fill('input[type="email"]', email);
  const pwFields = await page.locator('input[type="password"]').all();
  for (const f of pwFields) await f.fill('Test1234!');
  await page.click('button[type="submit"]');
  await page.waitForTimeout(2000);
}

const start = Date.now();
const textarea = page.locator('textarea').first();
await textarea.fill('Run cryo-EM single particle analysis');
await textarea.press('Enter');

// Wait 90 seconds for full AI response
console.log('Waiting 90s for AI response...');
await page.waitForTimeout(90000);
console.log(`Waited ${Date.now() - start}ms`);

await page.screenshot({ path: `${DIR}/result-90s.png`, fullPage: true });

// Check for workflow viewer
const domCheck = await page.evaluate(() => {
  const awaitingReview = document.body.innerHTML.includes('AWAITING REVIEW');
  const confirmBtn = [...document.querySelectorAll('button')].some(b => b.textContent?.includes('Confirm'));
  const runBtn = [...document.querySelectorAll('button')].some(b => b.textContent?.includes('Run Workflow'));
  const phaseCards = document.querySelectorAll('[data-testid^="phase-run-count-"]');
  const msgTypes = [];
  try {
    const keys = Object.keys(localStorage);
    for (const k of keys) {
      const v = JSON.parse(localStorage.getItem(k) || '{}');
      if (v?.messages) {
        v.messages.forEach((m) => msgTypes.push({ role: m.role, type: m.metadata?.type }));
      }
    }
  } catch {}
  return { awaitingReview, confirmBtn, runBtn, phaseCardCount: phaseCards.length, msgTypes };
});

console.log('\n=== DOM CHECK (90s) ===');
console.log(JSON.stringify(domCheck, null, 2));

const apiLogs = allLogs.filter(l => l.includes('ChatInterface') || l.includes('Error') || l.includes('workflow') || l.includes('PAGE_ERROR') || l.includes('onSuccess') || l.includes('API Response'));
console.log('\n=== RELEVANT LOGS ===');
apiLogs.forEach(l => console.log(l));

await browser.close();
