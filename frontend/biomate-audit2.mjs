import { chromium } from 'playwright';

const BASE_URL = 'http://localhost:5415';
const SCREENSHOTS_DIR = '/tmp/biomate-audit-screenshots';

async function shot(page, name) {
  const path = `${SCREENSHOTS_DIR}/${name}.png`;
  await page.screenshot({ path, fullPage: false });
  console.log(`  📸 ${name}.png`);
}

async function main() {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  const consoleErrors = [];
  page.on('console', msg => { if (msg.type() === 'error') consoleErrors.push(msg.text()); });
  page.on('pageerror', err => consoleErrors.push(`PAGE ERROR: ${err.message}`));

  // 1. Load app - should already be logged in as John Doe (from previous session)
  console.log('\n[1] Loading app...');
  await page.goto(BASE_URL, { waitUntil: 'networkidle' });
  await shot(page, 'A1-home');
  console.log('  URL:', page.url());

  // 2. Click "New Chat" to start fresh
  console.log('\n[2] Starting new chat...');
  const newChat = page.locator('button:has-text("New Chat"), a:has-text("New Chat")').first();
  if (await newChat.count() > 0) {
    await newChat.click();
    await page.waitForTimeout(1000);
    await shot(page, 'A2-new-chat');
  }

  // 3. Find chat input and send research query
  console.log('\n[3] Sending research query...');
  const chatInput = page.locator('textarea').first();
  if (await chatInput.count() === 0) {
    console.log('  ❌ No textarea found');
    await shot(page, 'A3-no-input');
    await browser.close();
    return;
  }

  await chatInput.click();
  await chatInput.fill('What are the best practices for single-particle cryo-EM data collection? Cite key papers.');
  await shot(page, 'A3-typed');

  // Submit
  const sendBtn = page.locator('button[type="submit"], button[aria-label*="send" i]').first();
  if (await sendBtn.count() > 0) {
    await sendBtn.click();
  } else {
    await chatInput.press('Enter');
  }

  // 4. Capture streaming state (2s in)
  console.log('\n[4] Capturing streaming state...');
  await page.waitForTimeout(2000);
  await shot(page, 'A4-streaming-2s');

  // Check for double indicator at 2s
  const emptyBubbles = await page.evaluate(() => {
    const assistantMsgs = document.querySelectorAll('[class*="assistant"] [class*="bubble"], [class*="ai"] p, [class*="message"]');
    const emptyOnes = [];
    assistantMsgs.forEach(el => {
      if (el.textContent?.trim() === '' && !el.children.length) emptyOnes.push(el.className);
    });
    return emptyOnes.length;
  });
  console.log(`  Empty message bubbles visible: ${emptyBubbles}`);

  const typingCount = await page.locator('text=/BioMate is typing/i').count();
  console.log(`  "BioMate is typing" indicators: ${typingCount}`);
  if (typingCount > 1) {
    console.log('  ❌ DOUBLE typing indicator bug still present!');
  } else if (typingCount === 1) {
    console.log('  ✅ Single typing indicator (correct)');
  }

  // 5. Wait for streaming to complete (up to 120s for research query)
  console.log('\n[5] Waiting for response to complete (up to 120s)...');
  try {
    await page.waitForFunction(() => {
      const typingEls = document.querySelectorAll('[class*="typing-indicator"], [class*="typing_indicator"]');
      const typingText = [...document.querySelectorAll('*')].some(el =>
        el.children.length === 0 && el.textContent?.trim().includes('BioMate is typing')
      );
      return !typingText && typingEls.length === 0;
    }, { timeout: 120000 });
    console.log('  ✅ Streaming complete');
  } catch {
    console.log('  ⚠️ Timeout waiting for streaming (response may still be incomplete)');
  }
  await page.waitForTimeout(1000);
  await shot(page, 'A5-response-complete');

  // 6. Check for citations
  console.log('\n[6] Checking for inline citations...');
  const citationLinks = await page.locator('a[href^="#ref-"]').count();
  console.log(`  Citation anchor links found: ${citationLinks}`);
  if (citationLinks > 0) {
    console.log('  ✅ Inline citations with anchor links present');
  } else {
    console.log('  ❌ No anchor citation links found');
    // Check if there's any citation text without links
    const bracketCitations = await page.evaluate(() => {
      const body = document.body.innerText;
      const matches = body.match(/\[\d+\]/g);
      return matches ? matches.length : 0;
    });
    console.log(`  Bracket citations in text (not linked): ${bracketCitations}`);
  }

  // 7. Check for references section
  console.log('\n[7] Checking references section...');
  const refSection = await page.locator('[id^="ref-"]').count();
  const refsVerified = await page.locator('text=/verified from/i').count();
  console.log(`  Reference items (id="ref-N"): ${refSection}`);
  console.log(`  "verified from" text: ${refsVerified}`);

  // Scroll to see full response
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(500);
  await shot(page, 'A6-scrolled-bottom');

  // 8. Check message action buttons
  console.log('\n[8] Checking message buttons...');
  const copyBtns = await page.locator('button[aria-label*="copy" i], button:has-text("Copy")').count();
  const downloadBtns = await page.locator('button[aria-label*="download" i], button[title*="download" i]').count();
  console.log(`  Copy buttons: ${copyBtns}`);
  console.log(`  Download buttons: ${downloadBtns}`);

  // Check the last assistant message's action buttons
  await page.evaluate(() => {
    const msgs = document.querySelectorAll('[data-testid*="message"], [class*="message-container"]');
    if (msgs.length > 0) {
      const last = msgs[msgs.length - 1];
      last.scrollIntoView();
    }
  });
  await shot(page, 'A7-message-buttons');

  // Try hovering over the last message to see buttons
  const lastAssistantMsg = page.locator('[class*="prose"], [class*="message-content"]').last();
  if (await lastAssistantMsg.count() > 0) {
    await lastAssistantMsg.hover();
    await page.waitForTimeout(300);
    await shot(page, 'A8-message-hover');
  }

  // 9. Look for download dropdown
  console.log('\n[9] Looking for download dropdown...');
  const downloadIcon = page.locator('svg[class*="download"], button:has(svg)').last();
  const allButtonTexts = await page.evaluate(() => {
    const btns = [...document.querySelectorAll('button')];
    return btns.map(b => ({ text: b.textContent?.trim().slice(0, 30), aria: b.getAttribute('aria-label'), title: b.title })).filter(b => b.text || b.aria || b.title);
  });
  console.log('  All visible buttons:', JSON.stringify(allButtonTexts.slice(-10), null, 2));

  // 10. Check "Continue" button
  console.log('\n[10] Checking for Continue suggestion...');
  const continueBtns = await page.locator('button:has-text("Continue")').count();
  console.log(`  Continue buttons: ${continueBtns}`);

  // 11. Console errors summary
  console.log('\n[11] Console errors:');
  if (consoleErrors.length === 0) {
    console.log('  ✅ No console errors');
  } else {
    consoleErrors.slice(0, 5).forEach(e => console.log(`  ❌ ${e.slice(0, 100)}`));
  }

  // Final summary screenshot - scroll up to see full response
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(300);
  await shot(page, 'A9-full-page-top');

  console.log('\n' + '='.repeat(50));
  console.log('AUDIT COMPLETE - Screenshots in:', SCREENSHOTS_DIR);
  await browser.close();
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
