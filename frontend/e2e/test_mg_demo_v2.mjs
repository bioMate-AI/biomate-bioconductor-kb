/**
 * MG Tutorial Demo — Full End-to-End Test (real user flow)
 *
 * Models the actual conference demo experience:
 *   Turn 1: User uploads local CSV files via DatasetBrowser (+), asks for DESeq2
 *   Turn 2: User says "Yes" to enrichGO suggestion
 *   Turn 3: User provides iptacopan SMILES, ADMET executes end-to-end
 *
 * Does NOT upload to S3 directly — all file handling goes through the BioMate UI.
 */
import { chromium } from '@playwright/test';
import path from 'path';
import { existsSync } from 'fs';

const DEV_URL = 'https://dev-public.biomate.ai';
const EMAIL = 'lifeifei163361@163.com';
const PASSWORD = 'WpmFixture!2026';
const IPTACOPAN_SMILES = 'CCO[C@H]1CCN(Cc2c(OC)cc(C)c3[nH]ccc23)[C@H](c2ccc(C(=O)O)cc2)C1';
const SCRATCHPAD = '/private/tmp/claude-501/-Users-kky-biomate/c836965b-5f0d-4e49-8f13-a2e9857bc900/scratchpad/mg_data';
const SCREENSHOT_DIR = '/Users/kky/biomate/reference/claude_design/biomate/screenshots_conference';

const PASS = '✅ PASS';
const FAIL = '❌ FAIL';
const SKIP = '⚠️ SKIP';
const results = [];

function record(label, ok, detail = '') {
  const status = ok === null ? SKIP : (ok ? PASS : FAIL);
  console.log(`${status}  ${label}${detail ? ' — ' + detail : ''}`);
  results.push({ label, ok, detail });
}

async function screenshot(page, name) {
  const p = `${SCREENSHOT_DIR}/mg_e2e_${name}.png`;
  await page.screenshot({ path: p, fullPage: false }).catch(() => {});
  console.log(`  📷 ${p}`);
}

// ── helpers ────────────────────────────────────────────────────────────────

async function login(page) {
  await page.goto(`${DEV_URL}/login`);
  await page.waitForLoadState('networkidle');
  await page.locator('input[type="email"]').fill(EMAIL);
  await page.locator('input[type="password"]').fill(PASSWORD);
  await page.keyboard.press('Enter');
  await page.waitForTimeout(4000);
  const url = page.url();
  if (url.includes('/login')) {
    record('Login', false, `still on login page: ${url}`);
    throw new Error('Login failed — stopping test');
  }
  record('Login', true, url);
}

async function startFreshChat(page) {
  await page.goto(`${DEV_URL}/`);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1500);
  const btn = page.locator('[data-testid="new-chat"], button:has-text("New Chat")').first();
  if (await btn.isVisible({ timeout: 3000 })) {
    await btn.click();
    await page.waitForTimeout(1000);
  }
}

async function sendMessage(page, msg) {
  const ta = page.locator('[data-testid="chat-input"], textarea').first();
  await ta.waitFor({ state: 'visible', timeout: 10000 });
  await ta.click();
  await ta.fill(msg);
  await page.waitForTimeout(300);
  const sendBtn = page.locator('[data-testid="chat-send-button"]').first();
  if (await sendBtn.isVisible({ timeout: 2000 })) {
    await sendBtn.click();
  } else {
    await page.keyboard.press('Enter');
  }
}

async function uploadFilesViaBrowser(page, filePaths) {
  // 1. Click "+" to open DatasetBrowser
  const plusBtn = page.locator('button[title="Add data"]').first();
  await plusBtn.waitFor({ state: 'visible', timeout: 10000 });
  await plusBtn.click();

  // 2. Wait for dialog to open
  await page.waitForSelector('[role="dialog"]', { timeout: 8000 });
  console.log('  DatasetBrowser opened');

  // 3. Use the hidden file input — Playwright can set files on hidden inputs
  const fileInput = page.locator('[role="dialog"] input[type="file"]').first();
  await fileInput.setInputFiles(filePaths);
  console.log(`  Uploading ${filePaths.length} files: ${filePaths.map(p => path.basename(p)).join(', ')}`);

  // 4. Wait for "Uploading…" to disappear (all files processed)
  try {
    await page.waitForSelector('[role="dialog"]', { state: 'hidden', timeout: 60000 });
    console.log('  Upload complete — dialog closed (files auto-selected)');
  } catch {
    // Dialog might stay open if upload took long — try to close it
    console.log('  Dialog still open — checking upload status');
    const uploading = await page.locator('text=Uploading').count();
    if (uploading === 0) {
      // Upload done, close dialog
      await page.keyboard.press('Escape');
    }
  }

  // 5. Check that dataset chips appeared in the chat input (by count indicator or page text)
  const attachedCount = await page.locator('[data-testid="chat-input-attached-count"]').count();
  const bodyText = await page.textContent('body').catch(() => '');
  const hasChips = attachedCount > 0 || bodyText.includes('counts_matrix');
  return hasChips;
}

async function waitForWorkflowCard(page, msgsBefore = 0, timeoutMs = 90000) {
  // msgsBefore: count of AI messages before this turn was sent.
  // We wait until that count increases (a new AI message arrived), then read
  // the workflow name from the CHAT-EMBEDDED card (NOT the right panel, which
  // keeps showing the previously-opened workflow until the user clicks "Open").
  const aiMsgSel = '[class*="assistant"], .assistant-message';
  const deadline = Date.now() + timeoutMs;
  let aiMsgCount = 0;
  while (Date.now() < deadline) {
    aiMsgCount = await page.locator(aiMsgSel).count();
    if (aiMsgCount > msgsBefore) break;
    await page.waitForTimeout(1000);
  }

  if (aiMsgCount <= msgsBefore) {
    console.log(`  No new AI message after ${timeoutMs / 1000}s (had ${msgsBefore}, now ${aiMsgCount})`);
    return { found: false, name: null, aiText: '', total: aiMsgCount };
  }

  // Wait for streaming to finish — check that the stop button is gone
  try {
    await page.waitForSelector('[data-testid="chat-stop-button"]', { state: 'hidden', timeout: timeoutMs });
  } catch { /* streaming may have already ended */ }
  await page.waitForTimeout(2000);

  // The NEW workflow is embedded in the LAST assistant message as a .wf-panel element.
  // We must NOT use the right panel (data-testid="workflow-right-panel") because it keeps
  // showing the previously-opened workflow until the user manually opens the new one.
  //
  // Each AI message is an element matching aiMsgSel. The message at index msgsBefore
  // is the first new message from this turn. We look for .panel-name inside it.
  const newMsg = page.locator(aiMsgSel).nth(msgsBefore);
  const newMsgPanelName = await newMsg.locator('.panel-name').first()
    .textContent({ timeout: 5000 }).catch(() => null);
  if (newMsgPanelName && newMsgPanelName.trim() && newMsgPanelName.trim() !== 'Untitled') {
    const newMsgPanelSub = await newMsg.locator('.panel-sub').first()
      .textContent().catch(() => null);
    const name = [newMsgPanelName.trim(), newMsgPanelSub?.trim()].filter(Boolean).join(' — ');
    return { found: true, name, total: aiMsgCount };
  }

  // Fallback: wf-chip-name is visible in the new message when it was already opened in the panel
  const chipName = await newMsg.locator('.wf-chip-name').first()
    .textContent().catch(() => null);
  if (chipName && chipName.trim()) {
    return { found: true, name: chipName.trim(), total: aiMsgCount };
  }

  // Last resort: read the AI text itself to extract the workflow name
  const text = await newMsg.textContent().catch(() => '');
  const cleaned = text.replace(/^BioMate\s*/i, '').trim();
  return { found: !!cleaned, name: cleaned.slice(0, 150) || null, total: aiMsgCount };
}

function routingMatches(card, keyword) {
  return card.found && (card.name || '').toLowerCase().includes(keyword.toLowerCase());
}

async function clickRun(page) {
  const runBtn = page.locator([
    'button:has-text("Confirm & Run")',
    'button:has-text("Run Workflow")',
    '[data-testid="run-workflow"]',
  ].join(', ')).first();
  try {
    await runBtn.waitFor({ state: 'visible', timeout: 8000 });
    await runBtn.click();
    return true;
  } catch {
    return false;
  }
}

async function waitForCompletion(page, timeoutMs = 300000) {
  // Wait for the workflow panel's overall status badge (not individual steps).
  // "Run again" = completed, "Restart" = failed. These only appear after the
  // FULL workflow finishes, not when a single step hits data-status="completed".
  const runAgainSel = 'button:has-text("Run again"), button:has-text("Run Again")';
  const restartSel = 'button:has-text("Restart")';
  // Fallback: the overall workflow badge with data-status (not a step badge)
  const wfBadgeSel = '.workflow-status-badge[data-status="completed"], .workflow-status-badge[data-status="failed"]';
  const combinedDone = `${runAgainSel}, ${restartSel}, ${wfBadgeSel}`;
  try {
    await page.waitForSelector(combinedDone, { timeout: timeoutMs });
    const hasRunAgain = await page.locator(runAgainSel).count() > 0;
    const hasRestart = await page.locator(restartSel).count() > 0;
    const hasBadge = await page.locator(wfBadgeSel).count() > 0;
    const failBadge = await page.locator('.workflow-status-badge[data-status="failed"]').count() > 0;
    return {
      completed: hasRunAgain || (hasBadge && !failBadge),
      failed: hasRestart || failBadge,
    };
  } catch {
    return { completed: false, failed: false, timeout: true };
  }
}

// ── main ───────────────────────────────────────────────────────────────────

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  page.on('console', m => m.type() === 'error' && console.log(`[app] ${m.text().slice(0, 100)}`));

  try {
    // ── LOGIN ──────────────────────────────────────────────────────────────
    console.log('\n══ Login ══');
    await login(page);

    // Navigate to home page to check chip (BEFORE starting a chat thread,
    // since the chip only appears in the home page empty state)
    await page.goto(`${DEV_URL}/`);
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);

    // ── CHIP CHECK ────────────────────────────────────────────────────────
    console.log('\n══ Chip Check ══');
    const mgChip = page.locator('button, [role="button"]').filter({ hasText: /MG patient stratification/i }).first();
    const chipVisible = await mgChip.count() > 0;
    record('Home page — MG chip visible', chipVisible);
    if (chipVisible) {
      await mgChip.click();
      await page.waitForTimeout(500);
      const ta = page.locator('textarea').first();
      const val = await ta.inputValue().catch(() => '');
      const turn1Only = val.includes('GSE227835') && !val.toLowerCase().includes('admet') && !val.includes('SMILES');
      record('Chip — fills Turn 1 only (no ADMET/SMILES chaining)', turn1Only, `"${val.slice(0, 80)}"`);
      // Clear the textarea — we'll do the real flow below
      await ta.fill('');
    }
    await screenshot(page, '01_chip_check');

    // Start a fresh chat thread for the actual demo flow
    await startFreshChat(page);
    await screenshot(page, '02_empty_chat');

    // ── TURN 1: upload files + DESeq2 query ───────────────────────────────
    console.log('\n══ Turn 1 — File upload + DESeq2 ══');
    const filePaths = [
      `${SCRATCHPAD}/counts_matrix.csv`,
      `${SCRATCHPAD}/sample_metadata.csv`,
      `${SCRATCHPAD}/contrasts.csv`,
    ];

    // Check files exist locally
    const allExist = filePaths.every(fp => existsSync(fp));
    record('Local data files exist', allExist, filePaths.map(p => path.basename(p)).join(', '));

    const chipsAppeared = await uploadFilesViaBrowser(page, filePaths);
    record('Turn 1 — Files uploaded via DatasetBrowser UI', chipsAppeared,
      chipsAppeared ? '3 dataset chips in input area' : 'no chips detected (may be in hidden form)');
    await screenshot(page, '03_after_upload');

    const aiMsgSel = '[class*="assistant"], .assistant-message';

    // Send DESeq2 query — files already attached as chips
    const turn1Msg = 'Run differential expression on these AChR+ myasthenia gravis PBMC files (10 MG patients vs 10 healthy controls) — identify the key complement pathway drivers.';
    console.log(`  Sending: "${turn1Msg}"`);
    const msgs0 = await page.locator(aiMsgSel).count();
    await sendMessage(page, turn1Msg);

    const card1 = await waitForWorkflowCard(page, msgs0, 90000);
    record('Turn 1 — workflow card appears', card1.found, (card1.name || card1.aiText || '').slice(0, 60));

    const deseq2Routed = routingMatches(card1, 'differential') || routingMatches(card1, 'deseq2') || routingMatches(card1, 'abundance');
    record('Turn 1 — routes to DESeq2 / differentialabundance', deseq2Routed, `"${(card1.name || '').slice(0, 60)}"`);
    await screenshot(page, '04_turn1_deseq2_card');

    // ── TURN 2: enrichGO ──────────────────────────────────────────────────
    console.log('\n══ Turn 2 — enrichGO ══');
    const turn2Msg = 'Yes, run pathway enrichment on the DE gene list — find the top complement GO terms.';
    console.log(`  Sending: "${turn2Msg}"`);
    const msgs1 = await page.locator(aiMsgSel).count();
    await sendMessage(page, turn2Msg);

    const card2 = await waitForWorkflowCard(page, msgs1, 90000);
    record('Turn 2 — workflow card appears', card2.found, (card2.name || card2.aiText || '').slice(0, 60));

    const enrichgoRouted = routingMatches(card2, 'clusterprofiler') || routingMatches(card2, 'enrichgo') ||
      routingMatches(card2, 'pathway') || routingMatches(card2, 'enrichment') || routingMatches(card2, 'gene ontology');
    record('Turn 2 — routes to enrichGO / clusterProfiler', enrichgoRouted, `"${(card2.name || '').slice(0, 60)}"`);
    await screenshot(page, '05_turn2_enrichgo_card');

    // ── TURN 3: ADMET (full execution) ────────────────────────────────────
    console.log('\n══ Turn 3 — ADMET execution ══');
    const turn3Msg = `Screen iptacopan for ADMET properties. SMILES: ${IPTACOPAN_SMILES}`;
    console.log(`  Sending: "${turn3Msg.slice(0, 80)}..."`);
    const msgs2 = await page.locator(aiMsgSel).count();
    await sendMessage(page, turn3Msg);

    const card3 = await waitForWorkflowCard(page, msgs2, 90000);
    record('Turn 3 — workflow card appears', card3.found, (card3.name || card3.aiText || '').slice(0, 60));

    const admetRouted = routingMatches(card3, 'admet') || routingMatches(card3, 'predict') ||
      routingMatches(card3, 'properties') || routingMatches(card3, 'iptacopan');
    record('Turn 3 — routes to ADMET workflow', admetRouted, `"${(card3.name || '').slice(0, 60)}"`);
    await screenshot(page, '06_turn3_admet_card');

    if (admetRouted || card3.found) {
      console.log('  Clicking Run...');
      const clicked = await clickRun(page);
      record('Turn 3 — Run button clicked', clicked);

      if (clicked) {
        await screenshot(page, '07_admet_running');
        console.log('  Waiting for ADMET completion (up to 5 min)...');
        const exec = await waitForCompletion(page, 300000);

        record('Turn 3 — ADMET completes', exec.completed,
          exec.timeout ? 'timed out 5 min' : exec.failed ? 'workflow failed' : 'success');
        await screenshot(page, '08_admet_done');

        if (exec.completed) {
          // Check for no "undefined" in page
          const body = await page.textContent('body').catch(() => '');
          record('No "undefined" text in page', !/\bundefined\b/.test(body));

          // Check output: after a completed run the "After run" tab shows ADMET results.
          // The download button has data-testid="button-download-all-workflow-panel".
          const dlBtn = page.locator([
            '[data-testid="button-download-all-workflow-panel"]',
            '[data-testid="button-download-methods-report"]',
            'button:has-text("Download all")',
            'a:has-text("Download")',
          ].join(', ')).first();
          const hasDl = await dlBtn.count() > 0;
          record('Turn 3 — Download all button visible', hasDl);

          // Check that the after-run section has some content (ADMET results table)
          const afterRunContent = await page.locator('[data-testid="download-commands-panel"], .admet-table, table').first()
            .textContent().catch(() => '');
          const hasRunData = afterRunContent.length > 20;
          record('Turn 3 — ADMET results data visible', hasRunData, afterRunContent.slice(0, 60));

          await screenshot(page, '09_admet_findings');
        }
      }
    }

  } catch (err) {
    console.error('\nFatal test error:', err.message);
    await screenshot(page, 'fatal_error').catch(() => {});
  } finally {
    await browser.close();
  }

  // ── SUMMARY ────────────────────────────────────────────────────────────
  console.log('\n══════════════ RESULTS ══════════════');
  let pass = 0, fail = 0, skip = 0;
  for (const r of results) {
    const st = r.ok === null ? SKIP : (r.ok ? PASS : FAIL);
    console.log(`${st}  ${r.label}${r.detail ? ' — ' + r.detail : ''}`);
    if (r.ok === true) pass++;
    else if (r.ok === false) fail++;
    else skip++;
  }
  console.log(`\n${pass} passed · ${fail} failed · ${skip} skipped`);
  process.exit(fail > 0 ? 1 : 0);
})();
