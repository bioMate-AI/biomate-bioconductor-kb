/**
 * BioMate Drug Development Demo v2
 * Shows: "thinking" indicator, clickable citations, reference list,
 *        workflow with provided dataset + Run button clicked
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BASE_URL  = process.env.BIOMATE_URL || 'http://localhost:5000';
const DEMO_EMAIL    = process.env.DEMO_EMAIL    || 'demo@biomate.dev';
const DEMO_PASSWORD = process.env.DEMO_PASSWORD || 'DemoBioMate2026';
const OUT_DIR  = path.join(__dirname, '..', 'demo_videos', 'drug_dev_v2_' + Date.now());
const SS_DIR   = path.join(OUT_DIR, 'screenshots');
fs.mkdirSync(SS_DIR, { recursive: true });

async function shot(page, name) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: false });
  console.log(`  📸 ${name}.png`);
}

/** Type a string character-by-character at human speed */
async function typeSlowly(locator, text, msPerChar = 40) {
  await locator.click();
  for (const ch of text) {
    await locator.pressSequentially(ch);
    await new Promise(r => setTimeout(r, msPerChar + Math.random() * 15));
  }
}

/** Click the send button or press Enter */
async function send(page) {
  const btn = page.locator('[data-testid="chat-send-button"]').first();
  if (await btn.count() > 0) await btn.click();
  else await page.keyboard.press('Enter');
}

/**
 * Wait until the chat response content is stable for `requiredStable` consecutive polls.
 * Polls every `pollMs`. Requires accumulated text to be >= minLen.
 * This reliably detects SSE stream completion even for 60-90s research responses.
 */
async function waitContentStable(page, minLen = 200, timeout = 150000, pollMs = 5000, requiredStable = 2) {
  let prev = -1;
  let stableCount = 0;
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const len = await page.evaluate(() => {
      // Broad selector: count ALL text inside the messages area to catch any response format
      const area = document.querySelector('[data-testid="chat-messages"]');
      if (area) return (area.textContent || '').length;
      // Fallback: all paragraph-like elements on the page
      const nodes = document.querySelectorAll('p, li, h2, h3, td, span[class*="message"]');
      return [...nodes].reduce((s, n) => s + (n.textContent || '').length, 0);
    });
    if (len >= minLen && len === prev) {
      stableCount++;
      if (stableCount >= requiredStable) return len;
    } else {
      stableCount = 0;
    }
    prev = len;
    await page.waitForTimeout(pollMs);
  }
  return prev; // timed out
}

/** Wait for workflow panel Run button (or Confirm & Run) to appear */
async function waitWorkflow(page, timeout = 25000) {
  try {
    await page.waitForSelector(
      '[data-testid="button-run-workflow-panel"], [data-testid="button-confirm-and-run"]',
      { timeout }
    );
    return true;
  } catch { return false; }
}

// ── PROMPTS ──────────────────────────────────────────────────────────────

// Part 1: Pure research query — shows citations + reference list
const RESEARCH_QUERY =
  "What are the key mechanisms of acquired resistance to KRAS G12C covalent inhibitors like soterasib, and what does recent literature say about combination strategies to overcome this?";

// Part 2: Workflow request with inline dataset — shows Run button + execution
const WORKFLOW_QUERY =
  "Run differential expression analysis on RNA-seq data from GSE68086. " +
  "The dataset has 6 samples: SRR1039508, SRR1039509, SRR1039510 (control/untreated) " +
  "and SRR1039513, SRR1039514, SRR1039516 (treated with dexamethasone). " +
  "Use DESeq2 with FDR threshold 0.05 and log2FC cutoff 1.5. " +
  "I want a volcano plot and a heatmap of the top 50 differentially expressed genes.";

// ── MAIN ─────────────────────────────────────────────────────────────────
async function main() {
  console.log(`🎬 BioMate Demo v2  —  ${BASE_URL}`);
  console.log(`📁 Output: ${OUT_DIR}\n`);

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    recordVideo: { dir: OUT_DIR, size: { width: 1440, height: 900 } },
  });
  const page = await ctx.newPage();

  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 100)); });

  // Capture workflow execute responses
  const capture = { runId: null };
  page.on('response', async (resp) => {
    if (!resp.url().includes('/api/workflows/execute') && !resp.url().includes('/api/nextflow/execute')) return;
    try {
      const json = await resp.json();
      capture.runId = json?.runId || json?.run_id || null;
    } catch { /* ignore */ }
  });

  try {
    // ── 0. Login ────────────────────────────────────────────────────────
    console.log('[0] Logging in as demo user...');
    await page.goto(`${BASE_URL}/login`, { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(800);
    await shot(page, '00-login-page');

    // Fill credentials (use fill() for React controlled inputs)
    const emailInput = page.locator('#email').first();
    const passInput  = page.locator('#password').first();
    await emailInput.waitFor({ state: 'visible', timeout: 10000 });
    await emailInput.fill(DEMO_EMAIL);
    await passInput.fill(DEMO_PASSWORD);
    await shot(page, '00b-credentials-filled');

    // Submit — wait for redirect away from /login
    const loginBtn = page.locator('button[type="submit"]').first();
    await loginBtn.click();
    await page.waitForURL(/^(?!.*\/login)/, { timeout: 30000 });
    await page.waitForTimeout(1000);
    await shot(page, '00c-dashboard');
    console.log(`  ✅ Logged in as ${DEMO_EMAIL}, redirected to ${page.url().replace(process.env.BIOMATE_URL || 'http://localhost:5000', '')}`);

    // Navigate to chat interface at /
    await page.goto(`${BASE_URL}/`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 15000 });
    await page.waitForTimeout(800);
    await shot(page, '00d-chat-ready');
    console.log('  ✅ Chat interface ready');

    // New chat
    const newChat = page.locator('button:has-text("New Chat")').first();
    if (await newChat.count() > 0) { await newChat.click(); await page.waitForTimeout(500); }

    const input = page.locator('[data-testid="chat-input"], textarea').first();
    await input.waitFor({ state: 'visible', timeout: 10000 });

    // ═══════════════════════════════════════════════════════════════════
    // PART 1: RESEARCH QUERY — citations + reference list
    // ═══════════════════════════════════════════════════════════════════
    console.log('\n[1] Sending KRAS G12C research query...');
    await typeSlowly(input, RESEARCH_QUERY);
    await shot(page, '01-research-typed');
    await send(page);

    // Capture "thinking" indicator
    await page.waitForTimeout(1500);
    const thinkingCount = await page.locator('text=/BioMate is thinking/i').count();
    console.log(`  Thinking indicator: ${thinkingCount > 0 ? '✅ visible' : '⚠️ not found'}`);
    await shot(page, '02-thinking-indicator');

    // Wait for research response to FULLY COMPLETE by content stability.
    // The stream takes ~60s; content grows throughout and only stabilizes at the end.
    // We poll every 5s and require 2 consecutive equal readings at >= 4000 chars.
    console.log('  Waiting for full research response (up to 150s, needs stable 4k+ chars)...');
    const resLen = await waitContentStable(page, 4000, 150000, 5000, 2);
    // Extra buffer: let React finish committing final state after stream ends
    await page.waitForTimeout(4000);
    console.log(`  Response length: ~${resLen} chars`);
    await shot(page, '03-research-response-top');

    // Scroll to end to check for reference list
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(1000);
    await shot(page, '04-reference-list');

    // Check for citation links and reference anchors
    const citationLinks = await page.locator('a[href^="#ref-"]').count();
    const refAnchors    = await page.locator('[id^="ref-"]').count();
    console.log(`  Citation links ([1], [2]...): ${citationLinks}`);
    console.log(`  Reference anchors (id=ref-N): ${refAnchors}`);

    // ── Click first citation link ──────────────────────────────────────
    console.log('\n[2] Clicking first citation link...');
    const firstCite = page.locator('a[href^="#ref-"]').first();
    if (await firstCite.count() > 0) {
      // Scroll back to top to make the click on a citation in the body visible
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(600);
      await shot(page, '05-before-citation-click');

      // Highlight the link by hovering
      await firstCite.scrollIntoViewIfNeeded();
      await firstCite.hover();
      await page.waitForTimeout(400);
      await shot(page, '06-citation-hovered');

      // Click it — should scroll to the References section
      await firstCite.click();
      await page.waitForTimeout(800);
      await shot(page, '07-after-citation-click');
      console.log('  ✅ Clicked citation link, scrolled to reference entry');
    } else {
      console.log('  ⚠️  No citation links found in response (response may not have cited papers)');
      await shot(page, '05-no-citation-links');
    }

    // Scroll to show the full References section
    await page.evaluate(() => {
      const refs = [...document.querySelectorAll('h2, h3')].find(h => /references/i.test(h.textContent || ''));
      if (refs) refs.scrollIntoView({ behavior: 'instant', block: 'start' });
    });
    await page.waitForTimeout(600);
    await shot(page, '08-references-section');

    // ═══════════════════════════════════════════════════════════════════
    // PART 2: WORKFLOW WITH DATASET + RUN
    // ═══════════════════════════════════════════════════════════════════
    console.log('\n[3] Sending RNA-seq workflow query with dataset...');
    // Wait until input is enabled (first stream fully complete + React settled)
    await page.waitForFunction(
      () => { const el = document.querySelector('[data-testid="chat-input"]'); return el && !el.disabled; },
      { timeout: 15000 }
    ).catch(() => console.log('  ⚠️  Input still gated — proceeding anyway'));
    await page.waitForTimeout(1000);
    // Re-locate input for second query
    const input2 = page.locator('[data-testid="chat-input"]').first();
    await input2.waitFor({ state: 'visible', timeout: 10000 });
    // Use fill() first to clear, then pressSequentially to trigger React onChange events
    await input2.click({ force: true });
    await page.waitForTimeout(300);
    await input2.pressSequentially(WORKFLOW_QUERY, { delay: 20 });
    await page.waitForTimeout(500);
    await shot(page, '09-workflow-typed');
    // Check send button exists
    const sendBtn = page.locator('[data-testid="chat-send-button"]').first();
    const sendBtnCount = await sendBtn.count();
    console.log(`  Send button found: ${sendBtnCount > 0 ? '✅' : '❌'}`);
    if (sendBtnCount > 0) {
      const sendBtnEnabled = await sendBtn.isEnabled().catch(() => false);
      console.log(`  Send button enabled: ${sendBtnEnabled ? '✅' : '❌'}`);
    }
    await send(page);

    // Thinking indicator for workflow query
    await page.waitForTimeout(1500);
    await shot(page, '10-workflow-thinking');

    // Wait briefly for thinking indicator to confirm message was sent
    await page.waitForTimeout(2500);
    const wfThinking = await page.locator('text=/BioMate is thinking/i').count();
    console.log(`  Thinking indicator: ${wfThinking > 0 ? '✅ visible' : '⚠️ NOT visible — message may not have sent'}`);

    // For workflow query: wait directly for the workflow panel (up to 120s)
    console.log('  Waiting for workflow panel Run button (up to 120s)...');
    const hasPanel = await waitWorkflow(page, 120000);

    await page.waitForTimeout(2000);
    // Scroll the chat's scroll container (not just window) to the bottom
    await page.evaluate(() => {
      // Try ScrollArea viewport first, then fall back to window
      const scroller =
        document.querySelector('[data-testid="chat-messages"] > div') ||
        document.querySelector('[data-radix-scroll-area-viewport]') ||
        document.documentElement;
      scroller.scrollTop = scroller.scrollHeight;
      window.scrollTo(0, document.body.scrollHeight);
    });
    await page.waitForTimeout(800);
    await shot(page, '11-workflow-panel');

    // ── Show the workflow panel clearly ───────────────────────────────
    // Fresh workflows use 'pending_review' status → "Confirm & Run" button
    const runBtn = page.locator(
      '[data-testid="button-run-workflow-panel"], [data-testid="button-confirm-and-run"]'
    ).first();
    const runBtnVisible = await runBtn.isVisible().catch(() => false);
    const runBtnText = runBtnVisible ? await runBtn.textContent().catch(() => '?') : '—';
    console.log(`  Run button visible: ${runBtnVisible ? '✅' : '❌'} (${runBtnText?.trim()})`);

    if (runBtnVisible) {
      // Scroll Run button into view and screenshot it
      await runBtn.scrollIntoViewIfNeeded();
      await page.waitForTimeout(500);
      await shot(page, '12-run-button-visible');

      // Click Run / Confirm & Run
      console.log('  Clicking Run...');
      await runBtn.click();
      await page.waitForTimeout(2000);
      await shot(page, '13-run-clicked');

      // Wait for execution progress
      console.log('  Waiting for execution progress (up to 90s)...');
      try {
        await page.waitForSelector(
          '[data-testid="workflow-last-update"], text=/running/i, text=/RUNNING/i, text=/completed/i',
          { timeout: 90000 }
        );
      } catch { /* timeout OK */ }
      await page.waitForTimeout(2000);
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(800);
      await shot(page, '14-execution-progress');

    } else {
      // Panel exists but maybe behind a scroll, check for content stability
      await waitContentStable(page, 200, 80000);
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(800);
      await shot(page, '12-workflow-no-run-btn');
      console.log('  ⚠️  Run button not found — captured workflow response');
    }

    // Final state
    await page.waitForTimeout(1000);
    await shot(page, '15-final');

    // ── Summary ──────────────────────────────────────────────────────
    console.log('\n' + '═'.repeat(60));
    console.log('✅ DEMO v2 COMPLETE');
    console.log(`📸 ${SS_DIR}`);
    console.log(`Console errors: ${errors.length === 0 ? 'none' : errors.slice(0, 3).join('; ')}`);
    console.log(`Citation links found: ${citationLinks}`);
    console.log(`Reference anchors found: ${refAnchors}`);
    console.log(`Run button appeared: ${runBtnVisible} (${runBtnText?.trim()})`);

  } catch (err) {
    console.error('❌ Demo failed:', err.message);
    await shot(page, 'ERROR-state').catch(() => {});
    throw err;
  } finally {
    const video = page.video();
    await ctx.close();
    if (video) {
      const vp = path.join(OUT_DIR, 'biomate_demo_v2.webm');
      try { await video.saveAs(vp); console.log(`📹 Video: ${vp}`); } catch (e) { console.warn('Video save:', e.message); }
    }
    await browser.close();
  }
}

main().catch(err => { console.error(err); process.exit(1); });
