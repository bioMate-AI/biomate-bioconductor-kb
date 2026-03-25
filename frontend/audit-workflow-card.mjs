import { chromium } from 'playwright';
import { mkdirSync } from 'fs';

const DIR = '/tmp/biomate-audit-card';
mkdirSync(DIR, { recursive: true });
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const logs = [];
page.on('console', msg => logs.push(`[${msg.type()}|${Date.now()}] ${msg.text().slice(0,500)}`));
page.on('pageerror', err => logs.push(`[PAGE_ERROR] ${err.message}`));
page.on('response', async res => {
  const u = res.url();
  if (u.includes('/api/chat') || u.includes('/api/workflow')) {
    logs.push(`[NET:${res.status()}] ${u.replace(/.*localhost:\d+/, '')}`);
  }
});

// Navigate and register
await page.goto('http://localhost:5000', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1500);
if (page.url().includes('/auth')) {
  const email = `card_audit_${Date.now()}@test.com`;
  const regTab = page.locator('[role="tab"]:has-text("Register"), button:has-text("Register")').first();
  if (await regTab.count()) await regTab.click();
  await page.fill('input[type="email"]', email);
  const pws = await page.locator('input[type="password"]').all();
  for (const pw of pws) await pw.fill('Test1234!');
  await page.click('button[type="submit"]');
  await page.waitForTimeout(2500);
}

await page.screenshot({ path: `${DIR}/00_home.png` });

// Send cryo-EM query
const textarea = page.locator('textarea').first();
await textarea.fill('Run cryo-EM single particle analysis');
await textarea.press('Enter');
console.log('Query sent. Waiting up to 120s for AI response...');
const start = Date.now();

// Poll every 5s, break when spinner gone AND we see workflow content
for (let i = 0; i < 24; i++) {
  await page.waitForTimeout(5000);
  const spinners = await page.locator('[class*="animate-spin"]').count();
  const hasReview = await page.locator('text=AWAITING REVIEW').count();
  const hasConfirm = await page.locator('button:has-text("Confirm")').count();
  const elapsed = Math.round((Date.now() - start) / 1000);
  console.log(`[${elapsed}s] spinners=${spinners} awaitingReview=${hasReview} confirmBtn=${hasConfirm}`);
  if (spinners === 0 && elapsed > 20 && (hasReview > 0 || hasConfirm > 0)) break;
  if (spinners === 0 && elapsed > 90) break;
}
await page.waitForTimeout(2000);

await page.screenshot({ path: `${DIR}/01_full_result.png`, fullPage: true });
console.log('Screenshot taken: 01_full_result.png');

// DOM inspection
const dom = await page.evaluate(() => {
  const awaitingReview = document.body.innerHTML.includes('AWAITING REVIEW');
  const confirmBtn = [...document.querySelectorAll('button')].some(b => b.textContent?.includes('Confirm'));
  const runBtn = [...document.querySelectorAll('button')].some(b => b.textContent?.includes('Run Workflow'));
  const phaseCards = document.querySelectorAll('[data-testid^="phase-run-count-"]');
  // Get phase card names
  const phaseNames = [...document.querySelectorAll('[data-testid^="phase-run-count-"]')]
    .map(el => el.closest('[class*="Card"], div')?.querySelector('h3,h4,[class*="font"]')?.textContent?.trim() || '?');
  // Get ALL button texts
  const allBtns = [...document.querySelectorAll('button')].map(b => b.textContent?.trim()).filter(Boolean);
  // Check for step names
  const hasImportMovies = document.body.innerHTML.includes('Import Movies');
  const hasPatchMotion = document.body.innerHTML.includes('Patch Motion');
  const has2DClass = document.body.innerHTML.includes('2D Classification');
  return { awaitingReview, confirmBtn, runBtn, phaseCardCount: phaseCards.length, phaseNames, allBtns: allBtns.slice(0,20), hasImportMovies, hasPatchMotion, has2DClass };
});

console.log('\n=== DOM CHECK ===');
console.log(JSON.stringify(dom, null, 2));

// Relevant logs
console.log('\n=== RELEVANT LOGS ===');
logs.filter(l => l.includes('ChatInterface') || l.includes('NET') || l.includes('workflow') || l.includes('PAGE_ERROR') || l.includes('onSuccess')).forEach(l => console.log(l));

await browser.close();
