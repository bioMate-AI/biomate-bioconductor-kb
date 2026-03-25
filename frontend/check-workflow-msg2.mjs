import { chromium } from 'playwright';
import { mkdirSync } from 'fs';

const DIR = '/tmp/biomate-check2';
mkdirSync(DIR, { recursive: true });
const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

const allLogs = [];
page.on('console', msg => allLogs.push(`[${msg.type()}] ${msg.text().slice(0, 400)}`));
page.on('pageerror', err => allLogs.push(`[PAGE_ERROR] ${err.message}`));
page.on('requestfailed', req => allLogs.push(`[REQ_FAIL] ${req.url()} — ${req.failure()?.errorText}`));

// Listen for network responses for /api/chat/stream
page.on('response', async res => {
  if (res.url().includes('/api/chat/stream') || res.url().includes('/api/chat')) {
    allLogs.push(`[NET] ${res.status()} ${res.url()}`);
  }
});

await page.goto('http://localhost:5000', { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1000);
const url = page.url();
if (url.includes('/auth')) {
  const email = `audit2_${Date.now()}@test.com`;
  const tab = page.locator('[role="tab"]:has-text("Register"), button:has-text("Register")').first();
  if (await tab.count()) await tab.click();
  await page.fill('input[type="email"]', email);
  const pwFields = await page.locator('input[type="password"]').all();
  for (const f of pwFields) await f.fill('Test1234!');
  await page.click('button[type="submit"]');
  await page.waitForTimeout(2000);
}

const textarea = page.locator('textarea').first();
await textarea.fill('Run cryo-EM single particle analysis');
await textarea.press('Enter');
await page.waitForTimeout(3000);

// Wait up to 60s for response
for (let i = 0; i < 30; i++) {
  await page.waitForTimeout(2000);
  const spinners = await page.locator('[class*="animate-spin"]').count();
  if (spinners === 0 && i > 5) break;
}
await page.waitForTimeout(3000);

await page.screenshot({ path: `${DIR}/result.png` });

// Check messages in storage
const msgInfo = await page.evaluate(() => {
  const keys = Object.keys(localStorage);
  const chatKeys = keys.filter(k => k.includes('chat') || k.includes('session'));
  const data = {};
  for (const k of chatKeys) {
    try { data[k] = JSON.parse(localStorage.getItem(k) || '{}'); } catch { data[k] = 'parse error'; }
  }
  return data;
});

// Look specifically for workflow in messages
const workflowInfo = await page.evaluate(() => {
  const keys = Object.keys(localStorage);
  for (const k of keys) {
    try {
      const val = JSON.parse(localStorage.getItem(k) || '{}');
      if (val && val.messages) {
        const wfMsgs = val.messages.filter((m) => m.metadata && m.metadata.type === 'workflow');
        if (wfMsgs.length > 0) {
          return { found: true, key: k, count: wfMsgs.length, first: JSON.stringify(wfMsgs[0].metadata).slice(0, 500) };
        }
        const allMsgs = val.messages.map((m) => ({ role: m.role, type: m.metadata?.type, hasWorkflow: !!m.metadata?.workflow }));
        return { found: false, key: k, messages: allMsgs };
      }
    } catch {}
  }
  return { found: false, msg: 'no sessions found' };
});

console.log('=== WORKFLOW IN STORAGE ===');
console.log(JSON.stringify(workflowInfo, null, 2));

console.log('\n=== ALL LOGS (filtered) ===');
allLogs.filter(l => 
  l.includes('ChatInterface') || l.includes('Error') || l.includes('NET') || 
  l.includes('final') || l.includes('workflow') || l.includes('PAGE_ERROR') ||
  l.includes('REQ_FAIL') || l.includes('mutation') || l.includes('onSuccess')
).forEach(l => console.log(l));

await browser.close();
