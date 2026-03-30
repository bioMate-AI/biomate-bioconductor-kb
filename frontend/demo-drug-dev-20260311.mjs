/**
 * BioMate Drug Development Demo  —  2026-03-11
 *
 * Fixes over earlier attempts:
 *  1. Stream detection: page.waitForEvent('requestfinished') instead of content-stability
 *     heuristic — avoids false positives when previous-session text already fills the area
 *  2. Radix ScrollArea: scroll [data-radix-scroll-area-viewport] not window
 *  3. Input verification: check inputValue() after pressSequentially; retry with fill()
 *  4. Citation detection: wait for [id^="ref-"] to appear AFTER stream done
 *  5. Timestamps in output directory and video filename
 *
 * Usage:
 *   node demo-drug-dev-20260311.mjs
 *   BIOMATE_URL=https://... node demo-drug-dev-20260311.mjs
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BASE_URL      = process.env.BIOMATE_URL      || 'http://localhost:5000';
const DEMO_EMAIL    = process.env.DEMO_EMAIL        || 'demo@biomate.dev';
const DEMO_PASSWORD = process.env.DEMO_PASSWORD     || 'DemoBioMate2026';

// Timestamp: YYYYMMDD_HHMM
const TS = new Date().toISOString()
  .replace(/T/, '_').replace(/:/g, '').slice(0, 13);   // e.g. "2026-03-11_1905"

const OUT_DIR = path.join(__dirname, '..', 'demo_videos', `drug_dev_${TS}`);
const SS_DIR  = path.join(OUT_DIR, 'screenshots');
fs.mkdirSync(SS_DIR, { recursive: true });

// ── Helpers ───────────────────────────────────────────────────────────────

async function shot(page, name) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: false });
  console.log(`  📸 ${name}.png`);
}

/** Type text character-by-character at a human-readable speed */
async function typeSlowly(locator, text, msPerChar = 40) {
  await locator.click();
  for (const ch of text) {
    await locator.pressSequentially(ch);
    await new Promise(r => setTimeout(r, msPerChar + Math.random() * 15));
  }
}

/** Click the Send button (or Enter as fallback) */
async function send(page) {
  const btn = page.locator('[data-testid="chat-send-button"]').first();
  if (await btn.count() > 0) await btn.click();
  else await page.keyboard.press('Enter');
}

/**
 * Prepare a one-shot listener that resolves when the next
 * POST /api/chat/stream request finishes (server closes SSE connection).
 * Must be called BEFORE send() so no event is missed.
 */
function prepareStreamWait(page, timeout = 150000) {
  return page.waitForEvent('requestfinished', {
    predicate: (req) =>
      req.url().includes('/api/chat/stream') && req.method() === 'POST',
    timeout,
  });
}

/**
 * Scroll the Radix ScrollArea chat viewport to 'top' or 'bottom'.
 * window.scrollTo() has no effect inside a Radix ScrollArea.
 */
async function scrollChat(page, to = 'bottom') {
  await page.evaluate((dir) => {
    // Chat messages uses a Radix ScrollArea; find its viewport
    const chatRoot = document.querySelector('[data-testid="chat-messages"]');
    const vp = (chatRoot && chatRoot.querySelector('[data-radix-scroll-area-viewport]'))
              || document.querySelector('[data-radix-scroll-area-viewport]');
    if (vp) vp.scrollTop = dir === 'bottom' ? vp.scrollHeight : 0;
    window.scrollTo(0, dir === 'bottom' ? document.body.scrollHeight : 0);
  }, to);
  await page.waitForTimeout(400);
}

/** Wait for workflow panel Run / Confirm & Run button */
async function waitWorkflow(page, timeout = 120000) {
  try {
    await page.waitForSelector(
      '[data-testid="button-run-workflow-panel"], [data-testid="button-confirm-and-run"]',
      { timeout }
    );
    return true;
  } catch { return false; }
}

// ── Prompts ───────────────────────────────────────────────────────────────

// Part 1 — pure research query: shows thinking indicator, citations, reference list
const RESEARCH_QUERY =
  'What are the key mechanisms of acquired resistance to KRAS G12C covalent inhibitors ' +
  'like soterasib, and what does recent literature say about combination strategies to overcome this?';

// Part 2 — workflow with inline dataset: shows prereq check, Run button, execution
const WORKFLOW_QUERY =
  'Run differential expression analysis on RNA-seq data from GSE68086. ' +
  'The dataset has 6 samples: SRR1039508, SRR1039509, SRR1039510 (control/untreated) ' +
  'and SRR1039513, SRR1039514, SRR1039516 (treated with dexamethasone). ' +
  'Use DESeq2 with FDR threshold 0.05 and log2FC cutoff 1.5. ' +
  'I want a volcano plot and a heatmap of the top 50 differentially expressed genes.';

// ── Main ──────────────────────────────────────────────────────────────────
async function main() {
  console.log(`🎬 BioMate Demo  —  ${BASE_URL}`);
  console.log(`📁 Output : ${OUT_DIR}`);
  console.log(`🕐 Run ID : ${TS}\n`);

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    recordVideo: { dir: OUT_DIR, size: { width: 1440, height: 900 } },
  });
  const page = await ctx.newPage();

  const jsErrors = [];
  page.on('console', m => {
    if (m.type() === 'error') jsErrors.push(m.text().slice(0, 120));
  });

  const capture = { runId: null };
  page.on('response', async (resp) => {
    const u = resp.url();
    if (!u.includes('/api/workflows/execute') && !u.includes('/api/nextflow/execute')) return;
    try { const j = await resp.json(); capture.runId = j?.runId || j?.run_id || null; } catch {}
  });

  let elapsed = '?';
  let citationLinks = 0;
  let refAnchors    = 0;
  let runBtnVisible = false;
  let runBtnText    = '—';

  try {
    // ── 0. Login ─────────────────────────────────────────────────────────
    console.log('[0] Login...');
    await page.goto(`${BASE_URL}/login`, { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(600);
    await shot(page, '00-login-page');

    const emailInput = page.locator('#email').first();
    const passInput  = page.locator('#password').first();
    await emailInput.waitFor({ state: 'visible', timeout: 10000 });
    await emailInput.fill(DEMO_EMAIL);
    await passInput.fill(DEMO_PASSWORD);
    await shot(page, '00b-credentials-filled');

    await page.locator('button[type="submit"]').first().click();
    await page.waitForURL(/^(?!.*\/login)/, { timeout: 30000 });
    await page.waitForTimeout(800);
    await shot(page, '00c-post-login');
    console.log(`  ✅ Logged in → ${page.url().replace(BASE_URL, '')}`);

    // Navigate to chat
    await page.goto(`${BASE_URL}/`, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForSelector('[data-testid="chat-input"]', { timeout: 15000 });
    await page.waitForTimeout(600);
    await shot(page, '00d-chat-loaded');

    // Start a fresh session so previous messages don't pollute the page
    const newChatBtn = page.locator('button:has-text("New Chat")').first();
    if (await newChatBtn.count() > 0) {
      await newChatBtn.click();
      await page.waitForTimeout(700);
    }
    await shot(page, '00e-new-chat');
    console.log('  ✅ Fresh chat session started');

    // ══════════════════════════════════════════════════════════════════
    // PART 1 — RESEARCH QUERY  (citations + reference list)
    // ══════════════════════════════════════════════════════════════════
    console.log('\n[1] Research query — KRAS G12C resistance mechanisms...');

    // Register requestfinished listener BEFORE sending the query
    const researchStreamDone = prepareStreamWait(page, 150000);

    const input = page.locator('[data-testid="chat-input"]').first();
    await input.waitFor({ state: 'visible', timeout: 10000 });
    await typeSlowly(input, RESEARCH_QUERY);
    await shot(page, '01-research-typed');
    await send(page);

    // Capture thinking indicator ~1.5 s after send
    await page.waitForTimeout(1500);
    const thinkingCount = await page.locator('text=/BioMate is thinking/i').count();
    console.log(`  Thinking indicator : ${thinkingCount > 0 ? '✅ visible' : '⚠️  not found'}`);
    await shot(page, '02-thinking-indicator');

    // ── Wait for SSE stream to FULLY COMPLETE ─────────────────────────
    // requestfinished fires when the server closes the SSE connection.
    // This is definitive — no false positives from pre-existing content.
    console.log('  Awaiting SSE stream completion (requestfinished, up to 150 s)...');
    const t0 = Date.now();
    await researchStreamDone.catch(e =>
      console.log(`  ⚠️  Stream wait: ${e.message.slice(0, 80)}`)
    );
    elapsed = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`  Stream finished in ${elapsed} s`);

    // Give React ~2 s to commit the final state (onSuccess, setIsTypingLocal, etc.)
    await page.waitForTimeout(2000);

    // Wait for at least one reference anchor to appear in the DOM
    await page.waitForFunction(
      () => document.querySelectorAll('[id^="ref-"]').length > 0,
      { timeout: 20000 }
    ).catch(() => console.log('  ⚠️  No [id^="ref-"] elements found (non-citation response?)'));

    await page.waitForTimeout(800);

    // ── Screenshots of the full research response ─────────────────────
    await scrollChat(page, 'top');
    await shot(page, '03-research-response-top');

    await scrollChat(page, 'bottom');
    await shot(page, '04-research-response-bottom');

    // Count citation elements
    citationLinks = await page.locator('a[href^="#ref-"]').count();
    refAnchors    = await page.locator('[id^="ref-"]').count();
    console.log(`  Citation links : ${citationLinks}  |  Reference anchors : ${refAnchors}`);

    // Scroll to the References card section
    await page.evaluate(() => {
      // Try to find the References heading inside the chat area
      const candidates = [...document.querySelectorAll('h2, h3, span, div')]
        .filter(el => /^references$/i.test((el.textContent || '').trim()));
      if (candidates.length > 0) {
        candidates[0].scrollIntoView({ behavior: 'instant', block: 'start' });
      }
    });
    await page.waitForTimeout(500);
    await shot(page, '05-references-section');

    // ── Click first inline citation link ─────────────────────────────
    console.log('\n[2] Citation interaction...');
    const firstCite = page.locator('a[href^="#ref-"]').first();
    if (await firstCite.count() > 0) {
      // Scroll back up so the inline citation is in view
      await scrollChat(page, 'top');
      await page.waitForTimeout(500);
      await shot(page, '06-before-citation-click');

      await firstCite.scrollIntoViewIfNeeded();
      await firstCite.hover();
      await page.waitForTimeout(400);
      await shot(page, '07-citation-hovered');

      await firstCite.click();
      await page.waitForTimeout(900);
      await shot(page, '08-after-citation-click');
      console.log('  ✅ Clicked citation → scrolled to reference entry');
    } else {
      console.log('  ⚠️  No citation anchor links found');
      await shot(page, '06-no-citation-links');
    }

    // ══════════════════════════════════════════════════════════════════
    // PART 2 — WORKFLOW QUERY  (dataset, Run button, execution)
    // ══════════════════════════════════════════════════════════════════
    console.log('\n[3] Workflow query — RNA-seq DEseq2 analysis...');

    // Confirm input is not disabled (stream is done, React settled)
    await page.waitForFunction(
      () => {
        const el = document.querySelector('[data-testid="chat-input"]');
        return el && !el.disabled;
      },
      { timeout: 20000 }
    ).catch(() => console.log('  ⚠️  Input gated; continuing anyway'));
    await page.waitForTimeout(600);

    // Scroll to bottom so input and send button are visible
    await scrollChat(page, 'bottom');
    await page.waitForTimeout(400);

    // Register requestfinished listener for the workflow stream
    const workflowStreamDone = prepareStreamWait(page, 150000);

    const input2 = page.locator('[data-testid="chat-input"]').first();
    await input2.waitFor({ state: 'visible', timeout: 10000 });
    await input2.click({ force: true });
    await page.waitForTimeout(300);
    await input2.pressSequentially(WORKFLOW_QUERY, { delay: 18 });

    // Verify the text actually made it into the controlled input
    const typedLen = await input2.inputValue().then(v => v.length).catch(() => 0);
    console.log(`  Typed ${typedLen} / ${WORKFLOW_QUERY.length} chars`);
    if (typedLen < WORKFLOW_QUERY.length * 0.9) {
      console.log('  ⚠️  Partial input detected — retrying with fill()');
      await input2.fill(WORKFLOW_QUERY);
      await page.waitForTimeout(400);
    }

    await page.waitForTimeout(400);
    await shot(page, '09-workflow-typed');

    const sendBtn2 = page.locator('[data-testid="chat-send-button"]').first();
    const sendEnabled = await sendBtn2.isEnabled().catch(() => false);
    console.log(`  Send button enabled : ${sendEnabled ? '✅' : '❌'}`);

    await send(page);

    // Thinking indicator for workflow query
    await page.waitForTimeout(1500);
    await shot(page, '10-workflow-thinking');
    const wfThinking = await page.locator('text=/BioMate is thinking/i').count();
    console.log(`  Thinking visible : ${wfThinking > 0 ? '✅' : '⚠️  not found'}`);

    // Wait for the workflow panel Run button (up to 120 s)
    console.log('  Waiting for workflow panel (up to 120 s)...');
    const hasPanel = await waitWorkflow(page, 120000);
    console.log(`  Workflow panel appeared : ${hasPanel ? '✅' : '❌'}`);

    await page.waitForTimeout(1500);
    await scrollChat(page, 'bottom');
    await page.waitForTimeout(800);
    await shot(page, '11-workflow-panel');

    // Check Run button
    const runBtn = page.locator(
      '[data-testid="button-run-workflow-panel"], [data-testid="button-confirm-and-run"]'
    ).first();
    runBtnVisible = await runBtn.isVisible().catch(() => false);
    runBtnText    = runBtnVisible ? (await runBtn.textContent().catch(() => '?')) : '—';
    const runBtnEnabled = runBtnVisible ? await runBtn.isEnabled().catch(() => false) : false;
    console.log(`  Run button: ${runBtnVisible ? '✅' : '❌'} "${runBtnText?.trim()}" enabled=${runBtnEnabled}`);

    if (runBtnVisible) {
      await runBtn.scrollIntoViewIfNeeded();
      await page.waitForTimeout(500);
      await shot(page, '12-run-button-visible');

      console.log('  Clicking Run...');
      await runBtn.click();
      await page.waitForTimeout(2000);
      await shot(page, '13-run-clicked');

      console.log('  Waiting for execution progress (up to 90 s)...');
      await page.waitForSelector(
        '[data-testid="workflow-last-update"], text=/running/i, text=/RUNNING/i, text=/completed/i',
        { timeout: 90000 }
      ).catch(() => {});
      await page.waitForTimeout(2000);
      await scrollChat(page, 'bottom');
      await page.waitForTimeout(800);
      await shot(page, '14-execution-progress');
    } else {
      await scrollChat(page, 'bottom');
      await shot(page, '12-no-run-button');
      console.log('  ⚠️  Run button not visible — captured workflow response');
    }

    await page.waitForTimeout(1000);
    await shot(page, '15-final');

    // ── Summary ──────────────────────────────────────────────────────
    console.log('\n' + '═'.repeat(62));
    console.log('✅  DEMO COMPLETE');
    console.log(`📁  ${OUT_DIR}`);
    console.log(`⏱   Research stream: ${elapsed} s`);
    console.log(`📎  Citations: ${citationLinks} links  |  ${refAnchors} ref-anchors`);
    console.log(`▶   Run button: ${runBtnVisible} — "${runBtnText?.trim()}"`);
    console.log(`🚨  JS errors: ${jsErrors.length === 0 ? 'none' : jsErrors.slice(0, 3).join('; ')}`);
    console.log('═'.repeat(62));

  } catch (err) {
    console.error('❌ Demo failed:', err.message);
    await shot(page, 'ERROR-state').catch(() => {});
    throw err;
  } finally {
    const video = page.video();
    await ctx.close();
    if (video) {
      const vp = path.join(OUT_DIR, `biomate_demo_${TS}.webm`);
      try { await video.saveAs(vp); console.log(`📹 Video: ${vp}`); }
      catch (e) { console.warn('Video save:', e.message); }
    }
    await browser.close();
  }
}

main().catch(err => { console.error(err); process.exit(1); });
