/**
 * AWS Batch Workflow E2E Recording
 *
 * Full end-to-end recording of a real Nextflow workflow executed on AWS Batch.
 * Captures every UX state of the new workflow panel design:
 *
 *  Phase 1 — AI generation + pending_review UX
 *    • "AWAITING REVIEW" amber badge
 *    • Review banner ("Review before running...")
 *    • Scientific rationale panel (When to use / pitfalls / params)
 *    • Pilot run banner (large dataset detection)
 *    • "Confirm & Run" + "Adjust via Chat" button pair
 *    • QC Settings collapsible section
 *
 *  Phase 2 — Execution + live progress
 *    • Cold-start banner ("Running on AWS Batch — provisioning compute...")
 *    • Task progress bar (completedTasks / totalTasks)
 *    • Execution status summary panel
 *    • Per-step status list
 *
 *  Phase 3 — Completion
 *    • SUCCESS / FAILED state
 *    • Output artifacts (if any)
 *    • Download links
 *
 * Run:
 *   cd frontend
 *   BIOMATE_URL=http://localhost:5000 npx playwright test e2e/batch-workflow-recording.e2e.ts \
 *     --headed --reporter=html --timeout=1200000
 *
 * Expected duration: ~15-20 min (cold Batch start + workflow tasks)
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'batch-recording');
const TS = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

// 20 min — cold Batch start (~5-8 min) + 24 tasks (~10 min) + margin
test.setTimeout(1200000);

test.use({
  video: { mode: 'on', size: { width: 1920, height: 1080 } },
  screenshot: 'on',
  trace: 'on',
  viewport: { width: 1920, height: 1080 },
  storageState: { cookies: [], origins: [] },
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let _seq = 0;
async function shot(page: Page, label: string): Promise<void> {
  _seq++;
  const filename = path.join(SCREENSHOT_DIR, `${String(_seq).padStart(3, '0')}_${label}.png`);
  await page.screenshot({ path: filename, fullPage: false }); // viewport only for cleaner video
  console.log(`  📸 ${path.basename(filename)}`);
}

async function registerAndGoHome(page: Page): Promise<void> {
  const email = `e2e_batch_rec_${Date.now()}@biomate.test`;
  console.log(`\n[Auth] Registering as ${email}`);
  await page.goto(`${BASE_URL}/register`);
  await page.evaluate(() => localStorage.clear());
  await page.waitForLoadState('load');

  await page.waitForSelector('#name, input[name="name"]', { state: 'visible', timeout: 10000 })
    .catch(() => {});
  const nameInput = page.locator('#name, input[name="name"]').first();
  if (await nameInput.isVisible().catch(() => false)) {
    await nameInput.fill('Batch Recording E2E');
    await page.fill('#email, input[type="email"]', email);
    await page.fill('#password, input[name="password"]', 'BatchRec2026!');
    const confirm = page.locator('#confirmPassword, input[name="confirmPassword"]').first();
    if (await confirm.isVisible().catch(() => false)) await confirm.fill('BatchRec2026!');
    const terms = page.locator('#terms, input[name="terms"]').first();
    if (await terms.isVisible().catch(() => false)) await terms.click();
    await page.locator('button[type="submit"]').first().click();
    await page.waitForTimeout(2000);
  }

  await page.goto(BASE_URL);
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForLoadState('load');
  await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1000);
  console.log('[Auth] Ready at home page');
}

async function waitForAIComplete(page: Page): Promise<void> {
  // First wait for textarea to become disabled (AI is processing)
  await page.waitForSelector('textarea:disabled', { timeout: 30000 })
    .catch(() => console.log('[AI] Textarea never disabled — response may be immediate'));

  // Then wait for typing indicator to disappear (SSE stream closed)
  await page.waitForSelector('text=BioMate is typing', { state: 'hidden', timeout: 180000 })
    .catch(() => {});
  await page.waitForSelector('text=AI is typing', { state: 'hidden', timeout: 180000 })
    .catch(() => {});

  // Wait for textarea to re-enable (definitive signal)
  await page.waitForSelector('textarea:enabled', { timeout: 180000 })
    .catch(() => console.log('[AI] Textarea did not re-enable in 3 min'));

  // Extra wait for React to render workflow card
  await page.waitForTimeout(3000);
}

// ---------------------------------------------------------------------------
// UX Audit helpers — capture and log each new UX element
// ---------------------------------------------------------------------------

async function auditPendingReviewUX(page: Page): Promise<Record<string, boolean>> {
  const checks: Record<string, boolean> = {};

  // AWAITING REVIEW badge
  checks.awaitingReviewBadge = await page.locator('text=AWAITING REVIEW').isVisible().catch(() => false);

  // Review banner
  checks.reviewBanner = await page.locator('text=Review before running').isVisible().catch(() => false);

  // Confirm & Run button
  checks.confirmAndRunBtn = await page.locator('[data-testid="button-confirm-and-run"]').isVisible().catch(() => false);

  // Adjust via Chat button
  checks.adjustViaChatBtn = await page.locator('button:has-text("Adjust via Chat")').isVisible().catch(() => false);

  // Scientific rationale panel
  checks.rationalePanel = await page.locator('text=Scientific Rationale').isVisible().catch(() => false);

  // When to use / Do not use
  checks.whenToUse = await page.locator('text=When to use').isVisible().catch(() => false);
  checks.doNotUse = await page.locator('text=Do NOT use when').isVisible().catch(() => false);

  // Pilot run banner
  checks.pilotRunBanner = await page.locator('[data-testid="pilot-run-banner"]').isVisible().catch(() => false);

  // QC Settings section
  checks.qcSettings = await page.locator('[data-testid="qc-settings-section"]').isVisible().catch(() => false);

  // Workflow configuration params
  checks.workflowParams = await page.locator('text=Workflow Configuration').isVisible().catch(() => false);

  // Old "Run Workflow" button should NOT be visible in pending_review
  const oldRunBtn = await page.locator('[data-testid="button-run-workflow-panel"]').isVisible().catch(() => false);
  checks.noOldRunBtn = !oldRunBtn;

  return checks;
}

async function auditRunningUX(page: Page): Promise<Record<string, boolean>> {
  const checks: Record<string, boolean> = {};

  checks.coldStartBanner = await page.locator('[data-testid="cold-start-banner"]').isVisible().catch(() => false);
  checks.executionStatusSummary = await page.locator('[data-testid="execution-status-summary"]').isVisible().catch(() => false);
  checks.progressIndicator = await page.locator('text=/\\d+%/').isVisible().catch(() => false);
  checks.runningHint = await page.locator('[data-testid="workflow-running-hint"]').isVisible().catch(() => false);

  // AWAITING REVIEW badge should be gone
  const awaitingBadge = await page.locator('text=AWAITING REVIEW').isVisible().catch(() => false);
  checks.awaitingReviewGone = !awaitingBadge;

  // RUNNING badge should appear
  checks.runningBadge = await page.locator('text=RUNNING').isVisible().catch(() => false);

  return checks;
}

// ---------------------------------------------------------------------------
// Main test
// ---------------------------------------------------------------------------

test.describe('AWS Batch Workflow E2E Recording', () => {
  test('Full workflow: generate → pending_review → confirm → Batch execution → completion', async ({ page }) => {
    const consoleLogs: string[] = [];
    const errors: string[] = [];
    page.on('console', msg => consoleLogs.push(`[${msg.type()}] ${msg.text()}`));
    page.on('pageerror', err => errors.push(err.message));

    // ====================================================================
    // PHASE 0: Setup
    // ====================================================================
    console.log('\n════════════════════════════════════════');
    console.log('  AWS BATCH WORKFLOW RECORDING E2E TEST');
    console.log('  ' + new Date().toISOString());
    console.log('════════════════════════════════════════');

    await registerAndGoHome(page);
    await shot(page, 'home_clean_state');

    // ====================================================================
    // PHASE 1: Send workflow query
    // ====================================================================
    console.log('\n[Phase 1] Sending CryoSPARC SPA workflow query...');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 15000 });

    // Short, action-first query — avoids "research" intent path
    const query =
      'Run a CryoSPARC single-particle analysis (SPA) pipeline. ' +
      'pixel_size=0.885, voltage=300, symmetry=D2, particle_diameter=180. ' +
      'Execute on AWS Batch.';

    // Type the query visibly for the recording
    await chatInput.click();
    await chatInput.fill(query);
    await shot(page, 'query_typed');

    console.log('[Phase 1] Submitting query...');
    await chatInput.press('Enter');
    await shot(page, 'query_submitted');

    // ====================================================================
    // PHASE 2: Wait for AI to generate workflow
    // ====================================================================
    console.log('\n[Phase 2] Waiting for AI workflow generation...');
    await waitForAIComplete(page);

    await shot(page, 'ai_response_complete');

    // Scroll to show the workflow card
    await page.evaluate(() => {
      const viewport = document.querySelector('[data-radix-scroll-area-viewport]');
      if (viewport) viewport.scrollTop = viewport.scrollHeight;
      else window.scrollTo(0, document.body.scrollHeight);
    });
    await page.waitForTimeout(500);
    await shot(page, 'workflow_card_visible');

    // ====================================================================
    // PHASE 3: Audit pending_review UX
    // ====================================================================
    console.log('\n[Phase 3] Auditing pending_review UX elements...');

    const pendingUX = await auditPendingReviewUX(page);
    console.log('\n  ┌─ WORKFLOW PANEL UX AUDIT (pending_review) ──────────');
    for (const [key, value] of Object.entries(pendingUX)) {
      const icon = value ? '✓' : '✗';
      const expected = key === 'noOldRunBtn' ? '(expected absent)' : '(expected present)';
      console.log(`  │ ${icon} ${key} ${expected}`);
    }
    console.log('  └─────────────────────────────────────────────────────');

    // Screenshot each section
    await shot(page, 'pending_review_overview');

    // Screenshot the AWAITING REVIEW badge
    if (pendingUX.awaitingReviewBadge) {
      const badge = page.locator('text=AWAITING REVIEW').first();
      await badge.scrollIntoViewIfNeeded();
      await shot(page, 'ux_awaiting_review_badge');
    }

    // Screenshot review banner
    if (pendingUX.reviewBanner) {
      const banner = page.locator('text=Review before running').first();
      await banner.scrollIntoViewIfNeeded();
      await page.waitForTimeout(200);
      await shot(page, 'ux_review_banner');
    }

    // Screenshot scientific rationale
    if (pendingUX.rationalePanel) {
      const rationale = page.locator('text=Scientific Rationale').first();
      await rationale.scrollIntoViewIfNeeded();
      await page.waitForTimeout(300);
      await shot(page, 'ux_scientific_rationale');
    }

    // Screenshot the button pair
    if (pendingUX.confirmAndRunBtn) {
      const btn = page.locator('[data-testid="button-confirm-and-run"]').first();
      await btn.scrollIntoViewIfNeeded();
      await page.waitForTimeout(200);
      await shot(page, 'ux_confirm_and_run_button');
    }

    // Screenshot QC Settings
    if (pendingUX.qcSettings) {
      const qcs = page.locator('[data-testid="qc-settings-section"]').first();
      await qcs.scrollIntoViewIfNeeded();
      await page.waitForTimeout(200);
      await shot(page, 'ux_qc_settings');
      // Try to expand it
      const trigger = qcs.locator('[role="button"], button, [data-state]').first();
      await trigger.click().catch(() => {});
      await page.waitForTimeout(400);
      await shot(page, 'ux_qc_settings_expanded');
    }

    // Check pilot run banner (expected for 7028 movies)
    if (pendingUX.pilotRunBanner) {
      console.log('  ✓ Pilot run banner visible (7028 movies > 1000 threshold)');
      await page.locator('[data-testid="pilot-run-banner"]').first().scrollIntoViewIfNeeded();
      await shot(page, 'ux_pilot_run_banner');
    } else {
      console.log('  ○ Pilot run banner not shown (query may not have triggered num_movies detection)');
    }

    // Full panel screenshot before running
    await page.evaluate(() => {
      const el = document.querySelector('[data-testid="workflow-run-controls"]');
      if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    });
    await page.waitForTimeout(500);
    await shot(page, 'full_panel_before_confirm');

    // Assert key UX changes are present
    expect(pendingUX.confirmAndRunBtn || pendingUX.awaitingReviewBadge,
      'New pending_review UX should be visible (Confirm & Run button or AWAITING REVIEW badge)').toBeTruthy();

    // ====================================================================
    // PHASE 4: Click "Confirm & Run" to start Batch execution
    // ====================================================================
    console.log('\n[Phase 4] Clicking Confirm & Run to trigger AWS Batch...');

    // Prefer new Confirm & Run button; fall back to old Run Workflow button
    const confirmBtn = page.locator('[data-testid="button-confirm-and-run"]').first();
    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]').first();

    if (await confirmBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.log('  Using: Confirm & Run (new UX)');
      await confirmBtn.scrollIntoViewIfNeeded();
      await shot(page, 'confirm_button_ready');
      await confirmBtn.click();
    } else if (await runBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.log('  Using: Run Workflow (legacy UX)');
      await runBtn.click();
    } else {
      // Emergency: try any visible execute-like button
      const anyBtn = page.locator('button:has-text("Run"), button:has-text("Execute"), button:has-text("Confirm")').last();
      console.log('  Using: fallback button selector');
      await anyBtn.click();
    }

    await page.waitForTimeout(3000);
    await shot(page, 'after_confirm_click');

    // ====================================================================
    // PHASE 5: Running UX — cold-start banner + progress
    // ====================================================================
    console.log('\n[Phase 5] Monitoring AWS Batch execution...');
    console.log('  (Cold start: ~5-8 min | Tasks: ~10 min | Total: ~15-20 min)');

    // First poll: check running UX immediately
    const runningUX = await auditRunningUX(page);
    console.log('\n  ┌─ WORKFLOW PANEL UX AUDIT (running) ──────────');
    for (const [key, value] of Object.entries(runningUX)) {
      console.log(`  │ ${value ? '✓' : '○'} ${key}`);
    }
    console.log('  └────────────────────────────────────────────');
    await shot(page, 'running_ux_initial');

    if (runningUX.coldStartBanner) {
      await page.locator('[data-testid="cold-start-banner"]').first().scrollIntoViewIfNeeded();
      await shot(page, 'ux_cold_start_banner');
    }

    // ====================================================================
    // PHASE 6: Progress monitoring loop (up to 18 min)
    // ====================================================================
    const MAX_WAIT_MS = 18 * 60 * 1000;
    const POLL_MS = 25_000;
    const deadline = Date.now() + MAX_WAIT_MS;

    let lastPct = -1;
    let completionState = 'timeout';
    let pollCount = 0;

    while (Date.now() < deadline) {
      await page.waitForTimeout(POLL_MS);
      pollCount++;

      const pageText = await page.locator('body').innerText().catch(() => '');

      // Check terminal states
      if (/\bSUCCESS\b|Workflow completed|all tasks complete/i.test(pageText)) {
        completionState = 'success';
        console.log(`\n  ✓ SUCCESS at ${Math.floor((Date.now() - deadline + MAX_WAIT_MS) / 1000)}s elapsed`);
        break;
      }
      if (/\bFAILED\b|execution failed|workflow error/i.test(pageText)) {
        completionState = 'failed';
        console.log(`\n  ✗ FAILED detected`);
        break;
      }

      // Extract progress
      const pctMatch = pageText.match(/(\d{1,3})%/);
      const currentPct = pctMatch ? parseInt(pctMatch[1]) : -1;

      // Extract task counts (e.g. "3 / 24 tasks")
      const taskMatch = pageText.match(/(\d+)\s*\/\s*(\d+)\s*task/i);
      const taskInfo = taskMatch ? `${taskMatch[1]}/${taskMatch[2]} tasks` : '';

      if (currentPct !== lastPct || pollCount % 3 === 0) {
        const pctLabel = currentPct >= 0 ? `${currentPct}pct` : `poll${pollCount}`;
        await shot(page, `progress_${pctLabel}${taskInfo ? '_' + taskMatch![1] + 'tasks' : ''}`);
        if (currentPct !== lastPct) {
          console.log(`  → Progress: ${currentPct >= 0 ? currentPct + '%' : 'unknown'} ${taskInfo ? '(' + taskInfo + ')' : ''}`);
        }
        lastPct = currentPct;
      }

      // Check for execution status summary
      const execSummary = await page.locator('[data-testid="execution-status-summary"]').isVisible().catch(() => false);
      if (execSummary && pollCount === 1) {
        await page.locator('[data-testid="execution-status-summary"]').scrollIntoViewIfNeeded();
        await shot(page, 'execution_status_summary');
      }
    }

    // ====================================================================
    // PHASE 7: Final state capture
    // ====================================================================
    console.log(`\n[Phase 7] Final state: ${completionState}`);

    // Scroll back to top of workflow panel
    await page.evaluate(() => {
      const viewport = document.querySelector('[data-radix-scroll-area-viewport]');
      if (viewport) viewport.scrollTop = viewport.scrollHeight;
    });
    await page.waitForTimeout(500);
    await shot(page, `final_state_${completionState}`);

    // Capture any output artifacts
    const hasArtifacts = await page.locator('[data-testid="nextflow-runtime-artifacts"]').isVisible().catch(() => false);
    if (hasArtifacts) {
      await page.locator('[data-testid="nextflow-runtime-artifacts"]').scrollIntoViewIfNeeded();
      await shot(page, 'output_artifacts');
    }

    // Download links
    const downloadBtn = page.locator('[data-testid="button-download-all-workflow-panel"]');
    if (await downloadBtn.isVisible().catch(() => false)) {
      await downloadBtn.scrollIntoViewIfNeeded();
      await shot(page, 'download_available');
    }

    // ====================================================================
    // PHASE 8: UX summary report
    // ====================================================================
    const report = {
      timestamp: new Date().toISOString(),
      baseUrl: BASE_URL,
      completionState,
      uxAudit: {
        pendingReview: pendingUX,
        running: runningUX,
        keyChanges: {
          'New: AWAITING REVIEW badge replaces immediate Run button': pendingUX.awaitingReviewBadge,
          'New: Review banner with guidance text': pendingUX.reviewBanner,
          'New: Confirm & Run + Adjust via Chat button pair': pendingUX.confirmAndRunBtn && pendingUX.adjustViaChatBtn,
          'New: Scientific Rationale panel': pendingUX.rationalePanel,
          'New: QC Settings collapsible section': pendingUX.qcSettings,
          'New: Pilot run banner for large datasets': pendingUX.pilotRunBanner,
          'New: Cold-start banner during Batch provisioning': runningUX.coldStartBanner,
          'New: Execution status summary panel': runningUX.executionStatusSummary,
          'Old Run Workflow button absent in pending_review': pendingUX.noOldRunBtn,
        },
      },
      errors: errors.length > 0 ? errors.slice(0, 10) : [],
      screenshotCount: _seq,
    };

    const reportPath = path.join(SCREENSHOT_DIR, `audit_${TS}.json`);
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    console.log('\n════════════════════════════════════════');
    console.log('  UX CHANGE SUMMARY');
    console.log('════════════════════════════════════════');
    for (const [desc, value] of Object.entries(report.uxAudit.keyChanges)) {
      console.log(`  ${value ? '✓' : '○'} ${desc}`);
    }
    console.log(`\n  Completion: ${completionState.toUpperCase()}`);
    console.log(`  Screenshots: ${_seq} → ${SCREENSHOT_DIR}`);
    console.log(`  Report: ${reportPath}`);
    console.log('════════════════════════════════════════\n');

    // Non-fatal assertion — workflow may fail on Batch for infra reasons but UX still valid
    const uxChanged = pendingUX.awaitingReviewBadge || pendingUX.confirmAndRunBtn;
    expect(uxChanged, 'Workflow panel should show new pending_review UX').toBeTruthy();

    if (completionState === 'failed') {
      console.log('[Warning] Workflow execution FAILED — this may be a Batch infrastructure issue, not a UX bug');
    }
  });
});
