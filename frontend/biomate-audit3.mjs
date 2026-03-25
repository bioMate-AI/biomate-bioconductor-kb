/**
 * Focused audit: verify markdown rendering, download button, message buttons
 * Uses content-length stability to detect streaming completion (not typing indicator)
 */
import { chromium } from 'playwright';

const BASE_URL = 'http://localhost:5415';
const DIR = '/tmp/biomate-audit-screenshots';

async function shot(page, name) {
  await page.screenshot({ path: `${DIR}/${name}.png`, fullPage: false });
  console.log(`  📸 ${name}.png`);
}

async function waitForContentStable(page, timeout = 90000) {
  let prevLen = -1;
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const len = await page.evaluate(() => {
      const msgs = document.querySelectorAll('[class*="prose"], [class*="message"] p, [class*="card"] p');
      let total = 0;
      msgs.forEach(m => total += (m.textContent || '').length);
      return total;
    });
    if (len === prevLen && len > 100) {
      // Content stable for one iteration
      return true;
    }
    prevLen = len;
    await page.waitForTimeout(2000);
  }
  return false;
}

async function main() {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  const errors = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text().slice(0, 100)); });

  // 1. Load home (already logged in)
  console.log('[1] Loading...');
  await page.goto(BASE_URL, { waitUntil: 'networkidle' });
  await shot(page, 'B1-home');

  // 2. New chat
  const newChat = page.locator('button:has-text("New Chat")').first();
  if (await newChat.count() > 0) await newChat.click();
  await page.waitForTimeout(800);

  // 3. Send a research query
  console.log('[2] Sending research query...');
  const input = page.locator('textarea').first();
  await input.fill('Explain RNA-seq differential expression analysis. What are the key statistical methods used?');
  await input.press('Enter');

  // 4. Wait 3s and capture streaming state
  await page.waitForTimeout(3000);
  await shot(page, 'B2-streaming-3s');

  const typingIndicators = await page.locator('text=/BioMate is typing/i').count();
  console.log(`  Typing indicators at 3s: ${typingIndicators} ${typingIndicators === 1 ? '✅' : typingIndicators === 0 ? '(already content)' : '❌ DOUBLE!'}`);

  // 5. Wait for content to stabilize
  console.log('[3] Waiting for response to stabilize (up to 90s)...');
  const stable = await waitForContentStable(page, 90000);
  console.log(stable ? '  ✅ Content stabilized' : '  ⚠️ Timeout - taking screenshot anyway');
  await page.waitForTimeout(1000);
  await shot(page, 'B3-response-done');

  // 6. Verify markdown rendered properly (no raw # or ** visible)
  console.log('[4] Checking markdown rendering...');
  const rawMarkdown = await page.evaluate(() => {
    const allText = document.body.innerText;
    const rawH1 = (allText.match(/^# .+$/m) || []).length;
    const rawH2 = (allText.match(/^## .+$/m) || []).length;
    const rawBold = (allText.match(/\*\*[^*]+\*\*/g) || []).length;
    const hasH1Rendered = document.querySelectorAll('h1, h2, h3').length > 0;
    return { rawH1, rawH2, rawBold, hasH1Rendered };
  });
  console.log('  Markdown check:', rawMarkdown);
  if (!rawMarkdown.hasH1Rendered && rawMarkdown.rawH1 > 0) {
    console.log('  ❌ Markdown NOT rendered - showing raw # symbols');
    errors.push('Markdown not rendered');
  } else if (rawMarkdown.hasH1Rendered) {
    console.log('  ✅ Headings rendered as HTML elements');
  } else {
    console.log('  ℹ️  No headings in this response (may be prose-only)');
  }

  // 7. Check action buttons
  console.log('[5] Checking action buttons...');
  const btns = await page.evaluate(() => {
    const all = [...document.querySelectorAll('button')];
    return all.map(b => b.getAttribute('aria-label') || b.title || b.textContent?.trim()).filter(Boolean);
  });
  const hasDownload = btns.some(b => b?.toLowerCase().includes('save') || b?.toLowerCase().includes('file'));
  const hasCopy = btns.some(b => b?.toLowerCase().includes('copy'));
  console.log(`  Copy button: ${hasCopy ? '✅' : '❌'}`);
  console.log(`  Save/Download button: ${hasDownload ? '✅' : '❌'}`);

  // 8. Try clicking the download button
  console.log('[6] Testing download button...');
  const saveBtn = page.locator('button[aria-label="Save response as file"]').first();
  if (await saveBtn.count() > 0) {
    await saveBtn.hover();
    await page.waitForTimeout(200);
    await saveBtn.click();
    await page.waitForTimeout(500);
    await shot(page, 'B4-download-dropdown');
    const txtOpt = page.locator('text=/Save as .txt/i, text=/.txt/').first();
    console.log(`  .txt option visible: ${await txtOpt.count() > 0 ? '✅' : '❌'}`);
  } else {
    console.log('  ❌ Save button not found');
    errors.push('Save button not found');
  }

  // 9. Close dropdown and scroll to see full response
  await page.keyboard.press('Escape');
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(300);
  await shot(page, 'B5-full-response');

  // 10. Check response content quality
  const responseText = await page.evaluate(() => {
    const msgs = document.querySelectorAll('[class*="prose"]');
    return [...msgs].map(m => m.textContent?.slice(0, 500)).join('\n');
  });
  console.log('\n[7] Response preview:');
  console.log(responseText.slice(0, 300) || '(no prose content found)');

  // Summary
  console.log('\n' + '='.repeat(50));
  console.log(`Console errors: ${errors.length === 0 ? '✅ None' : errors.join('; ')}`);
  console.log('Screenshots:', DIR);
  await browser.close();
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });
