import { chromium } from 'playwright';
import { writeFileSync } from 'fs';

const BASE_URL = 'http://localhost:5415';
const SCREENSHOTS_DIR = '/tmp/biomate-audit-screenshots';
const errors = [];

async function screenshot(page, name) {
  const path = `${SCREENSHOTS_DIR}/${name}.png`;
  await page.screenshot({ path, fullPage: false });
  console.log(`  [screenshot] ${name}.png`);
  return path;
}

async function logError(label, msg) {
  errors.push(`[${label}] ${msg}`);
  console.error(`  ❌ ${label}: ${msg}`);
}

async function main() {
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  // Collect console errors
  const consoleErrors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', err => consoleErrors.push(`PAGE ERROR: ${err.message}`));

  // ─── 1. HOME PAGE ──────────────────────────────────────────────
  console.log('\n[1] Loading home page...');
  await page.goto(BASE_URL, { waitUntil: 'networkidle' });
  await screenshot(page, '01-home');

  // ─── 2. NAVIGATE TO LOGIN ──────────────────────────────────────
  console.log('\n[2] Navigating to login...');
  const loginBtn = page.locator('a[href="/login"], button:has-text("Login"), button:has-text("Sign in"), a:has-text("Login")');
  if (await loginBtn.count() > 0) {
    await loginBtn.first().click();
    await page.waitForLoadState('networkidle');
  } else {
    await page.goto(`${BASE_URL}/login`, { waitUntil: 'networkidle' });
  }
  await screenshot(page, '02-login-page');

  // ─── 3. LOGIN ──────────────────────────────────────────────────
  console.log('\n[3] Logging in...');
  const emailInput = page.locator('input[type="email"], input[name="email"], input[placeholder*="email" i]').first();
  const pwInput = page.locator('input[type="password"]').first();

  if (await emailInput.count() === 0) {
    await logError('Login', 'Email input not found');
  } else {
    await emailInput.fill('testuser@biomate.org');
    await pwInput.fill('password123');
    await screenshot(page, '03-login-filled');
    await page.keyboard.press('Enter');
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(1500);
    await screenshot(page, '04-after-login');
    console.log('  Current URL:', page.url());
  }

  // ─── 4. FIND CHAT INTERFACE ────────────────────────────────────
  console.log('\n[4] Looking for chat interface...');
  await page.waitForTimeout(1000);
  const currentUrl = page.url();
  if (!currentUrl.includes('/chat') && !currentUrl.includes('/app') && !currentUrl.includes('/dashboard')) {
    // Try navigating directly
    for (const path of ['/chat', '/app', '/']) {
      await page.goto(`${BASE_URL}${path}`, { waitUntil: 'networkidle' });
      const chatInput = page.locator('textarea, input[placeholder*="Ask" i], input[placeholder*="message" i], input[placeholder*="question" i]').first();
      if (await chatInput.count() > 0) {
        console.log(`  Found chat at ${path}`);
        break;
      }
    }
  }
  await screenshot(page, '05-chat-interface');

  // ─── 5. SEND RESEARCH QUERY ────────────────────────────────────
  console.log('\n[5] Sending research query...');
  const chatInput = page.locator('textarea, input[placeholder*="Ask" i], input[placeholder*="message" i], input[placeholder*="question" i]').first();

  if (await chatInput.count() === 0) {
    await logError('Chat', 'No chat input found — cannot test chat');
    await screenshot(page, '06-no-chat-input');
  } else {
    await chatInput.click();
    await chatInput.fill('What are the best practices for single-particle cryo-EM data collection? Please cite key references.');

    await screenshot(page, '06-query-typed');

    // Submit
    const sendBtn = page.locator('button[type="submit"], button:has-text("Send"), button[aria-label*="send" i]').first();
    if (await sendBtn.count() > 0) {
      await sendBtn.click();
    } else {
      await chatInput.press('Enter');
    }

    // Wait for response streaming to start
    console.log('  Waiting for response to start...');
    await page.waitForTimeout(2000);
    await screenshot(page, '07-response-streaming');

    // Check typing indicator
    const typingIndicator = page.locator('text=/BioMate is typing/i, text=/typing/i').first();
    if (await typingIndicator.count() > 0) {
      console.log('  ✅ Typing indicator visible');
      await screenshot(page, '07b-typing-indicator');
    } else {
      console.log('  ℹ️  Typing indicator not visible at this moment (may have completed already)');
    }

    // Wait up to 60s for response to complete
    console.log('  Waiting for full response (up to 60s)...');
    try {
      await page.waitForFunction(() => {
        const indicators = document.querySelectorAll('[class*="typing"], [class*="loading"]');
        return indicators.length === 0;
      }, { timeout: 60000 });
    } catch (e) {
      console.log('  (Timeout waiting for typing to stop — taking screenshot anyway)');
    }
    await page.waitForTimeout(1000);
    await screenshot(page, '08-response-complete');

    // ─── 6. CHECK INLINE CITATIONS ───────────────────────────────
    console.log('\n[6] Checking inline citations...');
    const citations = await page.locator('a[href*="#ref-"]').count();
    if (citations > 0) {
      console.log(`  ✅ Found ${citations} citation anchor links`);
    } else {
      await logError('Citations', 'No anchor citation links [1] found in response');
    }

    // ─── 7. CHECK REFERENCES SECTION ─────────────────────────────
    console.log('\n[7] Checking references section...');
    const refs = await page.locator('text=/References verified/i, [id^="ref-"]').count();
    if (refs > 0) {
      console.log(`  ✅ References section found`);
    } else {
      console.log('  ℹ️  References section not visible (may be non-research response)');
    }

    // Scroll to bottom to see full response
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(500);
    await screenshot(page, '09-scrolled-bottom');

    // ─── 8. CHECK DOWNLOAD BUTTON ─────────────────────────────────
    console.log('\n[8] Checking download button...');
    // Look for download button (FileDown icon)
    const downloadBtn = page.locator('button[aria-label*="download" i], button:has([data-lucide="file-down"]), button:has(svg)').last();

    // Find the message actions area
    const messageActions = page.locator('[class*="message"] button, [class*="chat"] button').all();
    const allButtons = await page.locator('button').all();
    console.log(`  Total buttons on page: ${allButtons.length}`);

    // Try to find download button by hovering over a message
    const assistantMsg = page.locator('[class*="assistant"], [class*="ai-message"], [class*="bot-message"]').first();
    if (await assistantMsg.count() > 0) {
      await assistantMsg.hover();
      await page.waitForTimeout(500);
      await screenshot(page, '10-hover-message');
    }

    // Look for the download dropdown specifically
    const fileDownBtn = page.locator('button').filter({ hasText: '' }).all();
    // Get all visible buttons after hover
    const visibleBtns = await page.locator('button:visible').count();
    console.log(`  Visible buttons after hover: ${visibleBtns}`);
    await screenshot(page, '10b-buttons-visible');

    // ─── 9. CHECK "CONTINUE" SUGGESTION ──────────────────────────
    console.log('\n[9] Checking for Continue suggestion...');
    const continueBtn = await page.locator('button:has-text("Continue"), [class*="suggestion"]:has-text("Continue")').count();
    if (continueBtn > 0) {
      console.log('  ✅ Continue suggestion button found');
      await screenshot(page, '11-continue-button');
    } else {
      console.log('  ℹ️  No Continue button (response may not have been truncated)');
    }

    // ─── 10. CHECK COPY BUTTON ────────────────────────────────────
    console.log('\n[10] Checking copy button...');
    const copyBtn = await page.locator('button[aria-label*="copy" i], button:has-text("Copy")').count();
    if (copyBtn > 0) {
      console.log('  ✅ Copy button found');
    } else {
      console.log('  ℹ️  Copy button not visible (may need hover)');
    }
  }

  // ─── 11. CONSOLE ERRORS ───────────────────────────────────────
  console.log('\n[11] Console errors during session:');
  if (consoleErrors.length === 0) {
    console.log('  ✅ No console errors');
  } else {
    for (const e of consoleErrors) {
      console.log(`  ❌ ${e}`);
      errors.push(`[Console] ${e}`);
    }
  }

  // ─── SUMMARY ──────────────────────────────────────────────────
  console.log('\n' + '='.repeat(60));
  console.log('AUDIT SUMMARY');
  console.log('='.repeat(60));
  if (errors.length === 0) {
    console.log('✅ All checks passed');
  } else {
    console.log(`❌ ${errors.length} issues found:`);
    errors.forEach((e, i) => console.log(`  ${i+1}. ${e}`));
  }
  console.log('\nScreenshots saved to:', SCREENSHOTS_DIR);

  await browser.close();

  writeFileSync('/tmp/audit-errors.json', JSON.stringify(errors, null, 2));
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
