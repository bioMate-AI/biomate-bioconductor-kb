/**
 * BioMate Demo — Cryo-EM Researcher
 * Records a Playwright video of a cryo-EM researcher using BioMate to:
 *   1. Search literature on cryo-EM single-particle analysis
 *   2. Ask about best practices for sample preparation
 *   3. Generate a full SPA workflow protocol
 *
 * Usage:
 *   cd /home/yzhang/biomate/frontend
 *   node demo_cryoem_researcher.mjs
 *
 * Output:
 *   demo_videos/cryoem_researcher_<timestamp>/  — screenshots
 *   demo_videos/cryoem_researcher_<timestamp>.webm  — video
 */

import { chromium } from 'playwright';
import { existsSync, mkdirSync, writeFileSync } from 'fs';
import { join } from 'path';

const BASE_URL   = 'http://localhost:5415';
const EMAIL      = 'testuser@biomate.org';
const PASSWORD   = 'password123';
const TS         = Date.now();
const VIDEO_DIR  = join(import.meta.dirname ?? '.', 'demo_videos');
const SHOT_DIR   = join(VIDEO_DIR, `cryoem_researcher_${TS}`);

mkdirSync(SHOT_DIR, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function shot(page, name) {
  const p = join(SHOT_DIR, name);
  await page.screenshot({ path: p, fullPage: false });
  console.log(`  📸 ${name}`);
  return p;
}

async function typeSlowly(page, selector, text, delay = 40) {
  await page.click(selector);
  await page.type(selector, text, { delay });
}

async function sendMessage(page, message) {
  const input = page.locator('[data-testid="chat-input"]');
  await input.waitFor({ state: 'visible', timeout: 15000 });
  await input.click();
  await input.fill('');
  await page.type('[data-testid="chat-input"]', message, { delay: 35 });
  await sleep(600);
  await shot(page, `msg_typed_${Date.now()}.png`);
  await page.click('[data-testid="chat-send-button"]');
  console.log(`  ✉️  Sent: "${message.slice(0, 60)}..."`);
}

async function waitForResponse(page, timeoutMs = 120000) {
  // Wait for typing indicator to appear, then disappear
  const typingText = 'Analyzing request';
  try {
    await page.waitForSelector(`text=${typingText}`, { state: 'attached', timeout: 10000 });
  } catch { /* may not appear for fast responses */ }
  // Poll until all typing indicators are gone
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const typing = await page.locator(`text=${typingText}`).count()
      + await page.locator('text=AI is typing').count()
      + await page.locator('[data-testid="chat-response-pending"]').count();
    if (typing === 0) break;
    await sleep(1000);
  }
  await sleep(1500);
}

async function main() {
  console.log('\n🎬  BioMate — Cryo-EM Researcher Demo\n' + '─'.repeat(50));

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });

  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    recordVideo: {
      dir: VIDEO_DIR,
      size: { width: 1440, height: 900 },
    },
    ignoreHTTPSErrors: true,
  });

  const page = await context.newPage();

  try {
    // ── STEP 0: Load app ─────────────────────────────────────────────────────
    console.log('\n[0] Loading BioMate...');
    await page.goto(BASE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await sleep(2000);
    await shot(page, '00_landing.png');

    // ── STEP 1: Login ────────────────────────────────────────────────────────
    console.log('\n[1] Logging in...');
    const loginLink = page.locator('a[href*="login"], button:has-text("Sign in"), button:has-text("Log in")').first();
    if (await loginLink.isVisible().catch(() => false)) {
      await loginLink.click();
      await sleep(1000);
    } else {
      await page.goto(`${BASE_URL}/login`, { waitUntil: 'domcontentloaded' });
      await sleep(1000);
    }
    await shot(page, '01_login_page.png');

    const emailInput = page.locator('input[type="email"], input[name="email"]').first();
    const passInput  = page.locator('input[type="password"]').first();
    if (await emailInput.isVisible().catch(() => false)) {
      await emailInput.fill(EMAIL);
      await passInput.fill(PASSWORD);
      await shot(page, '01b_login_filled.png');
      await passInput.press('Enter');
      await page.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 15000 }).catch(() => {});
      await sleep(2000);
    }
    await shot(page, '01c_after_login.png');

    // ── STEP 2: Start a fresh chat ────────────────────────────────────────────
    console.log('\n[2] Starting a new chat...');
    // Navigate directly to the chat page (login redirects to /dashboard, chat is at /)
    await page.goto(BASE_URL + '/', { waitUntil: 'domcontentloaded', timeout: 15000 });
    await sleep(2000);
    await shot(page, '02a_chat_page.png');

    // Click "New Chat" to ensure a fresh session (clear any prior conversation)
    const newChatBtn = page.locator('[data-testid="button-new-chat"]').first();
    if (await newChatBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
      await newChatBtn.click();
      await sleep(2000);
      console.log('  ✓ Clicked New Chat');
    } else {
      console.log('  ⚠ New Chat button not found, continuing...');
    }

    // Confirm chat input is visible
    const chatInput = page.locator('[data-testid="chat-input"]');
    await chatInput.waitFor({ state: 'visible', timeout: 20000 });
    await sleep(500);
    await shot(page, '02_chat_ready.png');

    // ── STEP 3: Literature search query ──────────────────────────────────────
    console.log('\n[3] Literature search — cryo-EM SPA best practices...');
    await sendMessage(page,
      'What does the recent literature say about best practices for cryo-EM single-particle analysis? ' +
      'Focus on sample vitrification, data collection parameters, and resolution benchmarks from 2022–2025.'
    );
    await shot(page, '03a_literature_query_sent.png');
    console.log('  ⏳ Waiting for literature response...');
    await waitForResponse(page, 90000);
    await shot(page, '03b_literature_response.png');
    await sleep(2000);
    // Scroll to see full response
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await sleep(500);
    await shot(page, '03c_literature_response_scrolled.png');

    // ── STEP 4: Sample prep protocol question ─────────────────────────────────
    console.log('\n[4] Sample preparation protocol question...');
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await sendMessage(page,
      'Based on those findings, what is the recommended protocol for preparing a membrane protein sample ' +
      'for cryo-EM? Include detergent screening, grid type selection, and blotting conditions.'
    );
    await shot(page, '04a_protocol_query_sent.png');
    console.log('  ⏳ Waiting for protocol response...');
    await waitForResponse(page, 90000);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await sleep(500);
    await shot(page, '04b_protocol_response.png');

    // ── STEP 5: Generate full SPA workflow ────────────────────────────────────
    console.log('\n[5] Generating full SPA Nextflow workflow...');
    await sendMessage(page,
      'Generate a complete single-particle analysis workflow for my cryo-EM dataset. ' +
      'I have 5000 micrographs collected on a Titan Krios at 300 kV, pixel size 0.85 Å/px, ' +
      'targeting a ~300 kDa soluble protein complex. Include motion correction, CTF estimation, ' +
      'particle picking, 2D/3D classification, and final refinement steps.'
    );
    await shot(page, '05a_workflow_query_sent.png');
    console.log('  ⏳ Waiting for workflow generation...');
    await waitForResponse(page, 120000);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await sleep(1000);
    await shot(page, '05b_workflow_generated.png');

    // Scroll up to show workflow artifact if visible
    await page.evaluate(() => window.scrollTo(0, 0));
    await sleep(500);
    await shot(page, '05c_workflow_artifact_top.png');
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight / 2));
    await shot(page, '05d_workflow_artifact_mid.png');
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await shot(page, '05e_workflow_artifact_bottom.png');

    // ── STEP 6: Ask about QC thresholds ──────────────────────────────────────
    console.log('\n[6] QC threshold question...');
    await sendMessage(page,
      'What CTF fit resolution and astigmatism thresholds should I use for quality control ' +
      'in this pipeline? What are the RELION-recommended values?'
    );
    console.log('  ⏳ Waiting for QC response...');
    await waitForResponse(page, 60000);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await sleep(500);
    await shot(page, '06_qc_thresholds.png');

    // ── STEP 7: Final overview ────────────────────────────────────────────────
    console.log('\n[7] Final state...');
    await sleep(2000);
    await page.evaluate(() => window.scrollTo(0, 0));
    await shot(page, '07_final_overview.png');
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await shot(page, '07b_final_scrolled.png');

    console.log('\n✅  All steps complete!');

  } catch (err) {
    console.error('\n❌  Error:', err.message);
    await shot(page, `ERROR_${Date.now()}.png`).catch(() => {});
  } finally {
    await context.close();
    await browser.close();
  }

  // ── Post-processing ────────────────────────────────────────────────────────
  console.log('\n' + '─'.repeat(50));
  console.log('📁  Screenshots:', SHOT_DIR);
  console.log('📹  Video:       ', VIDEO_DIR, '(*.webm)');
  console.log('\n── Compile to MP4 ──');
  console.log(`ffmpeg -framerate 1/4 -pattern_type glob -i '${SHOT_DIR}/*.png' \\`);
  console.log(`  -vf "scale=1440:900:force_original_aspect_ratio=decrease,pad=1440:900:(ow-iw)/2:(oh-ih)/2" \\`);
  console.log(`  -c:v libx264 -pix_fmt yuv420p -y \\`);
  console.log(`  ${VIDEO_DIR}/cryoem_demo_${TS}.mp4`);
  console.log('\n── Or use the .webm directly ──');
  console.log(`  ${VIDEO_DIR}/*.webm`);
}

main().catch(err => { console.error(err); process.exit(1); });
