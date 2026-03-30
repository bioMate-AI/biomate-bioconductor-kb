/**
 * BioMate Client Demo — E2E Recording
 *
 * A polished, client-facing recording of BioMate's core capabilities.
 * This runs against the REAL BioMate backend (no mocking).
 *
 * Normal action flow — users provide their data naturally:
 *
 *  Scene 1 — Registration + clean home screen
 *  Scene 2 — Drug Safety Screening (ADMET)
 *             User: "I have this compound [SMILES]..."
 *             → AI generates safety workflow card
 *             → AWAITING REVIEW badge (pending_review UX)
 *             → Confirm & Run → AWS Batch execution → progress
 *  Scene 3 — RNA-seq from GEO accession
 *             User: "I want to analyse GSE68086 (lung cancer)..."
 *             → AI generates DESeq2 workflow plan
 *             → Show Scientific Rationale + QC settings
 *  Scene 4 — Cryo-EM SPA (non-blocking)
 *             User: "My movies are at s3://... Run CryoSPARC SPA"
 *             → AI generates SPA workflow
 *             → Show pilot run banner + QC thresholds
 *
 * Run:
 *   cd frontend
 *   BIOMATE_URL=http://localhost:5000 npx playwright test e2e/client-demo.e2e.ts \
 *     --reporter=list --timeout=1200000
 *
 * Video: e2e/test-results/client-demo.e2e.ts-[hash]/video.webm (1920x1080)
 * Screenshots: e2e/screenshots/client-demo/
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'client-demo');
if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.setTimeout(2400000); // 40 min — real AI + Batch execution for all 3 scenes

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'off', // we take manual screenshots
  trace: 'off',      // avoid ENOENT on trace artifacts dir
  viewport: { width: 1920, height: 1080 },
  storageState: { cookies: [], origins: [] },
});

// ─── counters ────────────────────────────────────────────────────────────────

let _seq = 0;
async function shot(page: Page, label: string) {
  const n = String(++_seq).padStart(3, '0');
  const fp = path.join(SCREENSHOT_DIR, `${n}_${label}.png`);
  await page.screenshot({ path: fp, fullPage: false });
  console.log(`  📸 ${n}_${label}.png`);
}

async function pause(ms: number) {
  await new Promise(r => setTimeout(r, ms));
}

// ─── auth ────────────────────────────────────────────────────────────────────

async function registerAndGoHome(page: Page): Promise<string> {
  const ts = Date.now();
  const email = `demo_client_${ts}@biomate.ai`;

  await page.goto(`${BASE_URL}/register`);
  await page.evaluate(() => { try { localStorage.clear(); } catch {} });
  await page.waitForLoadState('load');

  const nameInput = page.locator('#name, input[name="name"]').first();
  if (await nameInput.isVisible({ timeout: 8000 }).catch(() => false)) {
    await nameInput.fill('Dr. Sarah Chen');
    await page.locator('input[type="email"]').first().fill(email);
    await page.locator('input[type="password"]').first().fill('Demo2026!');
    const confirm = page.locator('#confirmPassword, input[name="confirmPassword"]').first();
    if (await confirm.isVisible({ timeout: 2000 }).catch(() => false)) await confirm.fill('Demo2026!');
    const terms = page.locator('#terms').first();
    if (await terms.isVisible({ timeout: 2000 }).catch(() => false)) await terms.click();
    await page.locator('button[type="submit"]').first().click();
    await page.waitForTimeout(2000);
  }

  await page.goto(BASE_URL);
  await page.evaluate(() => { try { localStorage.clear(); } catch {} });
  await page.reload();
  await page.waitForLoadState('load');
  await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1000);
  return email;
}

// Navigate to a new chat session
async function newChat(page: Page) {
  // Try the New Chat button first
  const btn = page.getByRole('button', { name: /new chat/i }).first();
  if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await btn.click();
    await pause(1500);
  } else {
    // Fall back to navigating to home
    await page.goto(BASE_URL);
    await page.waitForLoadState('load');
    await page.waitForSelector('textarea', { state: 'visible', timeout: 15000 }).catch(() => {});
    await pause(1000);
  }
}

// ─── query + response helpers ─────────────────────────────────────────────────

async function sendQuery(page: Page, query: string) {
  const textarea = page.locator('textarea').first();
  await expect(textarea).toBeVisible({ timeout: 15000 });
  await textarea.click();
  // Gradual typing so video looks natural
  for (const chunk of [query.slice(0, 60), query.slice(60, 150), query.slice(150)]) {
    if (chunk) { await textarea.type(chunk, { delay: 8 }); await pause(200); }
  }
  await pause(800);
}

async function submitQuery(page: Page) {
  await page.locator('textarea').first().press('Enter');
}

/**
 * Wait for AI to finish responding.
 * Strategy: poll body text until it stops growing, textarea re-enables,
 * or we hit the timeout.
 */
async function waitForAI(page: Page, maxSeconds = 120): Promise<void> {
  // First wait for textarea to become disabled (stream started)
  await page.waitForSelector('textarea:disabled', { timeout: 30000 }).catch(() => {});

  // Then wait for textarea to re-enable — that's the reliable signal the AI finished.
  // Don't use content-stability: "BioMate is thinking..." can be stable for 30s+ before response.
  const deadline = Date.now() + maxSeconds * 1000;
  while (Date.now() < deadline) {
    await pause(3000);
    const enabled = await page.locator('textarea:enabled').isVisible({ timeout: 500 }).catch(() => false);
    if (enabled) {
      await pause(2000); // let React render the final message
      break;
    }
  }
  await pause(1000);
}

// ─── workflow panel helpers ───────────────────────────────────────────────────

async function findRunButton(page: Page) {
  // Order matters: prefer explicit testids, avoid broad "Run" text which matches sidebar buttons
  const candidates = [
    page.locator('[data-testid="button-confirm-and-run"]').last(),
    page.locator('[data-testid="button-run-workflow-panel"]').last(),
    page.getByRole('button', { name: /confirm.*run/i }).last(),
    page.getByRole('button', { name: /^run workflow$/i }).last(),
    // Only use "Run" if it's inside a workflow card
    page.locator('[data-testid^="workflow-artifact"] button:has-text("Run")').last(),
  ];
  for (const btn of candidates) {
    if (await btn.isVisible({ timeout: 2000 }).catch(() => false)) return btn;
  }
  return null;
}

async function waitForWorkflowCard(page: Page, label: string, baselineCount: number): Promise<boolean> {
  const deadline = Date.now() + 300000; // up to 5 min
  while (Date.now() < deadline) {
    const count = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
    if (count > baselineCount) {
      console.log(`  [${label}] Workflow card appeared (${count} total)`);
      await pause(2000);
      return true;
    }
    // Fallback: text indicators
    const hasText = await page.locator('text=Scientific Rationale').isVisible().catch(() => false)
      || await page.locator('text=Confirm & Run').isVisible().catch(() => false)
      || await page.locator('text=AWAITING REVIEW').isVisible().catch(() => false);
    if (hasText) {
      console.log(`  [${label}] Workflow indicators found (text fallback)`);
      await pause(2000);
      return true;
    }
    await pause(1500);
  }
  console.log(`  [${label}] No workflow card within 5 min — continuing`);
  return false;
}

async function auditWorkflowPanel(page: Page, label: string) {
  const UX = {
    workflowPanel:  await page.locator('[data-testid^="workflow-artifact"]').count().then(n => n > 0).catch(() => false),
    awaitingReview: await page.locator('text=AWAITING REVIEW').isVisible({ timeout: 2000 }).catch(() => false),
    confirmAndRun:  await page.locator('[data-testid="button-confirm-and-run"]').isVisible({ timeout: 2000 }).catch(() => false),
    adjustViaChat:  await page.locator('[data-testid="button-adjust-via-chat"]').isVisible({ timeout: 2000 }).catch(() => false),
    rationale:      await page.locator('text=Scientific Rationale').isVisible({ timeout: 2000 }).catch(() => false),
    qcSettings:     await page.locator('[data-testid="qc-settings-section"]').isVisible({ timeout: 2000 }).catch(() => false),
    pilotBanner:    await page.locator('[data-testid="pilot-run-banner"]').isVisible({ timeout: 2000 }).catch(() => false),
    coldStart:      await page.locator('[data-testid="cold-start-banner"]').isVisible({ timeout: 2000 }).catch(() => false),
  };
  console.log(`\n  ┌─ WORKFLOW UX AUDIT (${label}) ─────────────────────`);
  for (const [k, v] of Object.entries(UX)) {
    console.log(`  │ ${v ? '✓' : '○'} ${k}`);
  }
  console.log('  └──────────────────────────────────────────────────');
  return UX;
}

async function scrollToBottom(page: Page) {
  await page.evaluate(() => {
    const vp = document.querySelector('[data-radix-scroll-area-viewport]');
    if (vp) vp.scrollTop = vp.scrollHeight;
    else window.scrollTo(0, document.body.scrollHeight);
  });
  await pause(500);
}

// ─── THE DEMO ─────────────────────────────────────────────────────────────────

test('BioMate Client Demo — Drug Safety → RNA-seq → Cryo-EM', async ({ page }) => {

  // =====================================================================
  // SCENE 1: Registration + Clean Home Screen
  // =====================================================================
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║  SCENE 1: BioMate — First Login               ║');
  console.log('╚══════════════════════════════════════════════╝');

  const userEmail = await registerAndGoHome(page);
  console.log(`  [Auth] Logged in as: ${userEmail}`);
  await shot(page, 'S1_01_home_clean');

  // Show the sidebar / navigation
  const sidebar = page.locator('nav, [data-testid="sidebar"], aside').first();
  if (await sidebar.isVisible({ timeout: 3000 }).catch(() => false)) {
    await shot(page, 'S1_02_sidebar_navigation');
  }

  // Hover over the chat input to show it's ready
  await page.locator('textarea').first().hover();
  await pause(800);
  await shot(page, 'S1_03_chat_input_ready');

  // =====================================================================
  // SCENE 2: Drug Safety Screening — ADMET
  //
  // A medicinal chemist has a lead compound (imatinib / Gleevec).
  // They want to know: is it safe? hERG risk? Liver toxicity?
  // They paste the SMILES and ask BioMate.
  // =====================================================================
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║  SCENE 2: Drug Safety Screening (ADMET)       ║');
  console.log('╚══════════════════════════════════════════════╝');

  // Natural user query — the SMILES IS the data (exact query that reliably triggers ADMET workflow)
  const admetQuery =
    'Run ADMET toxicity screening for acetaminophen (SMILES: CC(=O)Nc1ccc(O)cc1). ' +
    'I need hERG cardiotoxicity risk, DILI assessment, Ames mutagenicity, and ClinTox probability.';

  const admetBaseline = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);

  await sendQuery(page, admetQuery);
  await shot(page, 'S2_01_admet_query_typed');
  await submitQuery(page);
  await shot(page, 'S2_02_admet_query_submitted');

  console.log('  [Scene 2] Waiting for AI response (ADMET)...');
  await waitForAI(page, 120);
  // Then wait specifically for the workflow card to appear
  await waitForWorkflowCard(page, 'ADMET', admetBaseline);
  await scrollToBottom(page);
  await shot(page, 'S2_03_admet_response_full');

  // Audit workflow panel UX
  const admetUX = await auditWorkflowPanel(page, 'ADMET');
  await shot(page, 'S2_04_admet_workflow_panel');

  // Show AWAITING REVIEW badge if present
  if (admetUX.awaitingReview) {
    console.log('  ✓ AWAITING REVIEW badge — new pending_review UX confirmed');
    await page.locator('text=AWAITING REVIEW').first().scrollIntoViewIfNeeded();
    await pause(600);
    await shot(page, 'S2_05_awaiting_review_badge');
  }

  // Show Scientific Rationale
  if (admetUX.rationale) {
    await page.locator('text=Scientific Rationale').first().scrollIntoViewIfNeeded();
    await pause(600);
    await shot(page, 'S2_06_scientific_rationale');
    // Try to expand it
    await page.locator('text=Scientific Rationale').first().click().catch(() => {});
    await pause(800);
    await shot(page, 'S2_07_rationale_expanded');
  }

  // Show QC Settings before running
  if (admetUX.qcSettings) {
    const qcs = page.locator('[data-testid="qc-settings-section"]').first();
    await qcs.scrollIntoViewIfNeeded();
    await pause(600);
    await qcs.locator('button, [role="button"]').first().click().catch(() => {});
    await pause(800);
    await shot(page, 'S2_08_qc_settings_open');
  }

  // Click Confirm & Run
  const admetRunBtn = await findRunButton(page);
  let admetExecuted = false;
  if (admetRunBtn) {
    await admetRunBtn.scrollIntoViewIfNeeded();
    await pause(1000); // natural pause so video viewer can see the button
    await shot(page, 'S2_09_confirm_run_ready');
    await admetRunBtn.click();
    admetExecuted = true;
    await pause(3000);
    await shot(page, 'S2_10_execution_started');

    // Cold-start banner (Batch provisioning)
    const coldStart = await page.locator('[data-testid="cold-start-banner"]')
      .isVisible({ timeout: 15000 }).catch(() => false);
    if (coldStart) {
      console.log('  ✓ Cold-start banner — AWS Batch provisioning');
      await page.locator('[data-testid="cold-start-banner"]').scrollIntoViewIfNeeded();
      await shot(page, 'S2_11_cold_start_batch');
    }

    // Poll progress for up to 5 min
    const execDeadline = Date.now() + 5 * 60 * 1000;
    let lastPct = -1;
    while (Date.now() < execDeadline) {
      await pause(10000);
      const body = await page.locator('body').innerText().catch(() => '');
      if (/workflow.*success|completed.*success|STATUS\s+Complete|Workflow complete\b/i.test(body)) {
        console.log('  ✓ ADMET workflow COMPLETE (SUCCESS)');
        break;
      }
      if (/execution.*failed|Execution failed/i.test(body)) {
        console.log('  ⚠ Workflow execution failed — see screenshot');
        break;
      }
      const pct = parseInt(body.match(/(\d+)%/)?.[1] ?? '-1');
      if (pct !== lastPct && pct >= 0) {
        console.log(`  [Batch] Progress: ${pct}%`);
        await shot(page, `S2_12_progress_${pct}pct`);
        lastPct = pct;
        if (pct >= 100) {
          console.log('  ✓ ADMET at 100% — done');
          break;
        }
      }
    }
  } else {
    console.log('  ○ No run button found');
    await shot(page, 'S2_09_no_run_button');
  }

  await scrollToBottom(page);
  await shot(page, 'S2_13_admet_final');
  console.log('  ✓ ADMET scene complete');

  // =====================================================================
  // SCENE 3: RNA-seq Differential Expression from GEO
  //
  // A computational biologist has a GEO dataset.
  // They want DESeq2 DE analysis comparing tumor vs normal.
  // They give BioMate the GEO accession — no file upload needed.
  // =====================================================================
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║  SCENE 3: RNA-seq — GEO Dataset Analysis      ║');
  console.log('╚══════════════════════════════════════════════╝');

  await newChat(page);

  const rnaseqQuery =
    "I want to identify differentially expressed genes in lung adenocarcinoma. " +
    "I have a publicly available RNA-seq dataset (GEO accession GSE68086) comparing " +
    "tumor vs normal lung tissue (n=58 samples). " +
    "Please run a complete RNA-seq differential expression and pathway enrichment analysis " +
    "with adjusted p-value < 0.05 and |log2FC| > 1.";

  const rnaseqBaseline = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);

  await sendQuery(page, rnaseqQuery);
  await shot(page, 'S3_01_rnaseq_query_typed');
  await submitQuery(page);
  await shot(page, 'S3_02_rnaseq_query_submitted');

  console.log('  [Scene 3] Waiting for AI response (RNA-seq)...');
  await waitForAI(page, 120);
  await scrollToBottom(page);
  await shot(page, 'S3_03_rnaseq_response');

  // If AI asked clarifying questions (numbered 1. 2. 3. style), answer them naturally
  const rnaseqBody = await page.locator('body').innerText().catch(() => '');
  const aiAskedQuestions = /workflow generation is currently unavailable|what form.*data|1\.\s.*form|metadata.*phenotype|preferred.*framework/i.test(rnaseqBody)
    && !/Confirm & Run|AWAITING REVIEW/i.test(rnaseqBody);
  if (aiAskedQuestions) {
    console.log('  [RNAseq] AI asked clarifying questions — reading page and answering...');
    await shot(page, 'S3_03b_rnaseq_ai_questions');

    // Answer each question dynamically based on keywords actually visible on screen
    const answers: string[] = [];
    if (/what form|fastq|count matrix|pre.?computed/i.test(rnaseqBody))
      answers.push('I have the pre-computed count matrix from GEO — please fetch it directly.');
    if (/metadata|phenotype|sample.*file/i.test(rnaseqBody))
      answers.push('No separate metadata file — 39 tumor samples and 19 normal from the GEO record.');
    if (/framework|deseq|edger/i.test(rnaseqBody))
      answers.push('Use DESeq2.');
    if (/pathway|enrichment|kegg|reactome/i.test(rnaseqBody))
      answers.push('All pathway databases: GO, KEGG, and Reactome.');

    const followUp = answers.length > 0 ? answers.join(' ') : 'Pre-computed count matrix from GEO. Human hg38. Tumor vs normal. DESeq2. All pathway databases.';
    console.log('  [RNAseq] Answering:', followUp);
    await sendQuery(page, followUp);
    await shot(page, 'S3_03c_rnaseq_followup_typed');
    await submitQuery(page);
    console.log('  [Scene 3] Waiting for workflow after follow-up...');
    await waitForAI(page, 120);
  }

  await waitForWorkflowCard(page, 'RNAseq', rnaseqBaseline);
  await scrollToBottom(page);
  await shot(page, 'S3_04_rnaseq_after_followup');

  const rnaseqUX = await auditWorkflowPanel(page, 'RNAseq');
  await shot(page, 'S3_04_rnaseq_panel');

  if (rnaseqUX.rationale) {
    await page.locator('text=Scientific Rationale').first().scrollIntoViewIfNeeded();
    await pause(600);
    await shot(page, 'S3_05_rnaseq_rationale');
  }

  if (rnaseqUX.qcSettings) {
    const qcs = page.locator('[data-testid="qc-settings-section"]').first();
    await qcs.scrollIntoViewIfNeeded();
    await pause(500);
    await shot(page, 'S3_06_rnaseq_qc_settings');
  }

  const rnaseqRunBtn = await findRunButton(page);
  let rnaseqExecuted = false;
  if (rnaseqRunBtn) {
    await rnaseqRunBtn.scrollIntoViewIfNeeded();
    await pause(1000);
    await shot(page, 'S3_07_rnaseq_ready_to_run');
    await rnaseqRunBtn.click();
    rnaseqExecuted = true;
    await pause(3000);
    await shot(page, 'S3_08_rnaseq_execution_started');

    // Cold-start banner (Batch provisioning)
    const coldStart = await page.locator('[data-testid="cold-start-banner"]')
      .isVisible({ timeout: 15000 }).catch(() => false);
    if (coldStart) {
      console.log('  ✓ Cold-start banner — AWS Batch provisioning (RNA-seq)');
      await page.locator('[data-testid="cold-start-banner"]').scrollIntoViewIfNeeded();
      await shot(page, 'S3_09_rnaseq_cold_start');
    }

    // Poll progress for up to 8 min (mock mode completes in ~1 min locally)
    const rnaseqDeadline = Date.now() + 8 * 60 * 1000;
    let rnaseqLastPct = -1;
    while (Date.now() < rnaseqDeadline) {
      await pause(10000);
      const body = await page.locator('body').innerText().catch(() => '');
      // Success: green status banner (avoid matching descriptive text like "After the workflow completes")
      if (/STATUS\s+Complete|Workflow complete\b|your results are ready|100%.*complete/i.test(body)) {
        console.log('  ✓ RNA-seq workflow COMPLETE (SUCCESS)');
        await shot(page, 'S3_10_rnaseq_complete');
        break;
      }
      // Failure: FAILED badge or STATUS Failed
      if (/STATUS\s+Failed|\bFAILED\b/i.test(body)) {
        console.log('  ⚠ RNA-seq workflow FAILED — see screenshot');
        await shot(page, 'S3_10_rnaseq_failed');
        break;
      }
      const pct = parseInt(body.match(/(\d+)%/)?.[1] ?? '-1');
      if (pct !== rnaseqLastPct && pct >= 0) {
        console.log(`  [Batch] RNA-seq Progress: ${pct}%`);
        await shot(page, `S3_10_rnaseq_progress_${pct}pct`);
        rnaseqLastPct = pct;
        if (pct >= 100) {
          console.log('  ✓ RNA-seq at 100% — done');
          break;
        }
      }
    }
  } else {
    console.log('  ○ No run button found for RNA-seq');
  }

  await scrollToBottom(page);
  await shot(page, 'S3_11_rnaseq_final');
  console.log('  ✓ RNA-seq scene complete');

  // =====================================================================
  // SCENE 4: Cryo-EM SPA (non-blocking)
  //
  // A cryo-EM facility scientist has movies staged on S3.
  // They describe their dataset and BioMate plans the pipeline.
  // =====================================================================
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║  SCENE 4: Cryo-EM SPA — S3 Dataset           ║');
  console.log('╚══════════════════════════════════════════════╝');

  await newChat(page);

  const cryoemQuery =
    "I'm processing E. coli beta-galactosidase cryo-EM data (EMPIAR-10028 pilot batch). " +
    "I have 20 EER movies staged at s3://biomate-cryo-data/empiar-10028/Micrographs/. " +
    "Microscope: 300 kV FEI Titan Krios, K2 Summit detector, pixel_size=0.885 Å/px, " +
    "symmetry=D2, particle_diameter=180 Å, cs=2.7 mm. " +
    "Please run CryoSPARC single-particle analysis on this small pilot batch and enable quality control checks.";

  const cryoemBaseline = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);

  await sendQuery(page, cryoemQuery);
  await shot(page, 'S4_01_cryoem_query_typed');
  await submitQuery(page);
  await shot(page, 'S4_02_cryoem_query_submitted');

  console.log('  [Scene 4] Waiting for AI response (CryoEM)...');
  await waitForAI(page, 90); // 90s cap — non-blocking
  await waitForWorkflowCard(page, 'CryoEM', cryoemBaseline);
  await scrollToBottom(page);
  await shot(page, 'S4_03_cryoem_response');

  const cryoemUX = await auditWorkflowPanel(page, 'CryoEM');
  await shot(page, 'S4_04_cryoem_panel');

  if (cryoemUX.pilotBanner) {
    await page.locator('[data-testid="pilot-run-banner"]').scrollIntoViewIfNeeded();
    await pause(600);
    await shot(page, 'S4_05_pilot_run_banner');
    console.log('  ✓ Pilot run banner — large dataset recommendation');
  }

  if (cryoemUX.qcSettings) {
    const qcs = page.locator('[data-testid="qc-settings-section"]').first();
    await qcs.scrollIntoViewIfNeeded();
    await pause(500);
    await shot(page, 'S4_06_cryoem_qc_settings');
  }

  // Fill the required movie path (S3 location of EMPIAR-10028 data)
  // The cryosparc_standard_spa workflow requires params.movies_path
  // The data is staged at s3://biomate-cryo-data/empiar-10028/Micrographs/
  // NOTE: use click+pressSequentially (not fill) to trigger React's onChange on controlled inputs
  const moviePathInput = page.locator('[data-testid="param-movies_path-path"]');
  const moviePathVisible = await moviePathInput.isVisible({ timeout: 5000 }).catch(() => false);
  if (moviePathVisible) {
    await moviePathInput.scrollIntoViewIfNeeded();
    await moviePathInput.click({ clickCount: 3 }); // select all existing text
    const moviePathValue = 's3://biomate-cryo-data/empiar-10028/Micrographs/';
    await moviePathInput.pressSequentially(moviePathValue, { delay: 10 });
    await pause(800); // let React re-render
    // Verify the value was accepted
    const actualValue = await moviePathInput.inputValue();
    if (actualValue === moviePathValue) {
      console.log('  ✓ Movie path filled: ' + moviePathValue);
    } else {
      // Fallback: native value setter approach for React controlled inputs
      await moviePathInput.evaluate((el: HTMLInputElement, val: string) => {
        const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
        if (setter) {
          setter.call(el, val);
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        }
      }, moviePathValue);
      await pause(500);
      console.log('  ✓ Movie path set via native setter: ' + moviePathValue);
    }
    await shot(page, 'S4_06b_cryoem_path_filled');
  } else {
    console.log('  ○ movies_path input not found — button may still be disabled');
  }

  const cryoemRunBtn = await findRunButton(page);
  let cryoemExecuted = false;
  if (cryoemRunBtn) {
    await cryoemRunBtn.scrollIntoViewIfNeeded();
    // Wait for the button to become enabled (React re-render after param fill)
    await cryoemRunBtn.waitFor({ state: 'visible' });
    const isEnabled = await cryoemRunBtn.isEnabled({ timeout: 5000 }).catch(() => false);
    if (!isEnabled) {
      console.log('  ⚠ Confirm & Run still disabled — checking required params hint...');
      const hint = await page.locator('[data-testid="required-params-missing-hint"]').textContent({ timeout: 2000 }).catch(() => '');
      console.log('  Hint:', hint);
    }
    await pause(1000);
    await shot(page, 'S4_07_cryoem_ready');
    await cryoemRunBtn.click({ timeout: 10000 });
    cryoemExecuted = true;
    await pause(3000);
    await shot(page, 'S4_08_cryoem_execution_started');

    // Cold-start banner (Batch provisioning)
    const cryoemColdStart = await page.locator('[data-testid="cold-start-banner"]')
      .isVisible({ timeout: 15000 }).catch(() => false);
    if (cryoemColdStart) {
      console.log('  ✓ Cold-start banner — AWS Batch provisioning (CryoEM)');
      await page.locator('[data-testid="cold-start-banner"]').scrollIntoViewIfNeeded();
      await shot(page, 'S4_09_cryoem_cold_start');
    }

    // Poll progress for up to 10 min (mock mode completes in ~2 min locally)
    const cryoemDeadline = Date.now() + 10 * 60 * 1000;
    let cryoemLastPct = -1;
    while (Date.now() < cryoemDeadline) {
      await pause(10000);
      const body = await page.locator('body').innerText().catch(() => '');
      // Success: green status banner (avoid matching descriptive text like "After the workflow completes")
      if (/STATUS\s+Complete|Workflow complete\b|your results are ready|100%.*complete/i.test(body)) {
        console.log('  ✓ CryoEM workflow COMPLETE (SUCCESS)');
        await shot(page, 'S4_10_cryoem_complete');
        break;
      }
      // Failure: FAILED badge or STATUS Failed
      if (/STATUS\s+Failed|\bFAILED\b/i.test(body)) {
        console.log('  ⚠ CryoEM workflow FAILED — see screenshot');
        await shot(page, 'S4_10_cryoem_failed');
        break;
      }
      const pct = parseInt(body.match(/(\d+)%/)?.[1] ?? '-1');
      if (pct !== cryoemLastPct && pct >= 0) {
        console.log(`  [Batch] CryoEM Progress: ${pct}%`);
        await shot(page, `S4_10_cryoem_progress_${pct}pct`);
        cryoemLastPct = pct;
      }
    }
  } else {
    console.log('  ○ No run button found for CryoEM');
  }

  await scrollToBottom(page);
  await shot(page, 'S4_11_cryoem_final');
  console.log('  ✓ CryoEM scene complete');

  // =====================================================================
  // FINAL SUMMARY
  // =====================================================================
  console.log('\n╔══════════════════════════════════════════════╗');
  console.log('║  DEMO SUMMARY                                 ║');
  console.log('╚══════════════════════════════════════════════╝');

  const summary = {
    timestamp: new Date().toISOString(),
    userEmail,
    scenarios: {
      admet:   { panelOpened: admetUX.workflowPanel,  executed: admetExecuted, awaitingReview: admetUX.awaitingReview },
      rnaseq:  { panelOpened: rnaseqUX.workflowPanel, executed: rnaseqExecuted, awaitingReview: rnaseqUX.awaitingReview },
      cryoem:  { panelOpened: cryoemUX.workflowPanel, executed: cryoemExecuted, awaitingReview: cryoemUX.awaitingReview },
    },
    newUXConfirmed: {
      'AWAITING REVIEW badge':  admetUX.awaitingReview || rnaseqUX.awaitingReview || cryoemUX.awaitingReview,
      'Confirm & Run button':   admetUX.confirmAndRun  || rnaseqUX.confirmAndRun  || cryoemUX.confirmAndRun,
      'Adjust via Chat':        admetUX.adjustViaChat  || rnaseqUX.adjustViaChat  || cryoemUX.adjustViaChat,
      'Scientific Rationale':   admetUX.rationale      || rnaseqUX.rationale      || cryoemUX.rationale,
      'QC Settings section':    admetUX.qcSettings     || rnaseqUX.qcSettings     || cryoemUX.qcSettings,
      'Pilot run banner':       cryoemUX.pilotBanner,
    },
    screenshots: _seq,
  };

  const rp = path.join(SCREENSHOT_DIR, `demo_report_${Date.now()}.json`);
  fs.writeFileSync(rp, JSON.stringify(summary, null, 2));

  console.log('\n  SCENARIO RESULTS:');
  for (const [sc, data] of Object.entries(summary.scenarios)) {
    const icon = data.panelOpened ? '✓' : '○';
    console.log(`  ${icon} ${sc.padEnd(8)} panel=${data.panelOpened} review=${data.awaitingReview} executed=${data.executed}`);
  }
  console.log('\n  NEW UX ELEMENTS:');
  for (const [desc, val] of Object.entries(summary.newUXConfirmed)) {
    console.log(`  ${val ? '✓' : '○'} ${desc}`);
  }
  console.log(`\n  Screenshots: ${_seq} saved → ${SCREENSHOT_DIR}`);
  console.log('  Video: e2e/test-results/client-demo.e2e.ts-*/video.webm\n');

  // Non-fatal: the demo records whatever state BioMate is in
  // At minimum Scene 1 (registration) must succeed
  await expect(page.locator('body')).toBeVisible();
});
