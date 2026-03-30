import { chromium } from 'playwright';
import { mkdirSync } from 'fs';

const DIR = '/tmp/biomate-check';
mkdirSync(DIR, { recursive: true });
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const consoleLogs = [];
page.on('console', msg => {
  const text = msg.text();
  if (text.includes('ChatInterface') || text.includes('workflowSuccess') || text.includes('metadataType') || text.includes('isWorkflow')) {
    consoleLogs.push(`[${msg.type()}] ${text.slice(0, 300)}`);
  }
});

// Register
await page.goto('http://localhost:5000', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1000);

const url = page.url();
if (url.includes('/auth') || url.includes('/login')) {
  const email = `audit_check_${Date.now()}@test.com`;
  const tab = page.locator('button:has-text("Register"), [role="tab"]:has-text("Register")').first();
  if (await tab.count()) await tab.click();
  await page.fill('input[type="email"]', email);
  const pwFields = await page.locator('input[type="password"]').all();
  for (const f of pwFields) await f.fill('Test1234!');
  await page.click('button[type="submit"]');
  await page.waitForTimeout(2000);
}

// Send query
const textarea = page.locator('textarea').first();
await textarea.fill('Run a cryo-EM single particle analysis pipeline on my raw micrographs');
await textarea.press('Enter');

// Wait up to 60s
for (let i = 0; i < 30; i++) {
  await page.waitForTimeout(2000);
  const spinners = await page.locator('[class*="animate-spin"]').count();
  if (spinners === 0 && i > 3) break;
}
await page.waitForTimeout(2000);

await page.screenshot({ path: `${DIR}/result.png` });

// Check DOM for workflow viewer
const workflowViewer = await page.evaluate(() => {
  const nfViewer = document.querySelector('[class*="space-y-6"]');
  const cards = document.querySelectorAll('[class*="Card"], [data-testid*="phase"]');
  const awaiting = document.body.innerHTML.includes('AWAITING REVIEW');
  const confirmBtn = document.body.innerHTML.includes('Confirm');
  const runBtn = document.body.innerHTML.includes('Run Workflow');
  return { 
    nfViewerFound: !!nfViewer,
    cardCount: cards.length,
    awaitingReview: awaiting,
    confirmBtn,
    runBtn,
    bodySnippet: document.body.innerHTML.slice(15000, 16000)
  };
});

console.log('=== DOM CHECK ===');
console.log(JSON.stringify(workflowViewer, null, 2));

console.log('\n=== CONSOLE LOGS ===');
consoleLogs.forEach(l => console.log(l));

await browser.close();
