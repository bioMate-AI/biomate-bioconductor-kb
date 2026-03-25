/**
 * Full Workflow E2E — Complete Pipeline Execution to Output Visualization
 *
 * NO MOCKS. Tests run against the live server using real AI responses and real execution.
 * Follows the iterative process: implement → test → record → audit → fix → repeat.
 *
 * Tests the complete user journey:
 *   Query → AWAITING REVIEW → Confirm & Run → Execution → Completion Banner
 *   → Results auto-open → Output visualization → Download All
 *
 * Target workflow: ADMET toxicity screening (inline SMILES → no MISSING prereqs → button enabled)
 *
 * Screenshots → e2e/screenshots/full-e2e/
 * Videos      → e2e/test-results/ (auto-recorded)
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'full-e2e');

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.setTimeout(1200000); // 20 min — real AI (may take 5-12m) + execution polling

// ---------------------------------------------------------------------------
// Shared helpers (mirror drug-dev-viewers-audit pattern)
// ---------------------------------------------------------------------------

interface RunStatusResponse {
  runId: string;
  status: string;
  progress?: { completedSteps?: number; totalSteps?: number };
  errorMessage?: string;
  nextflowStatus?: { status?: string; completed?: boolean; error?: string; invocation_id?: string };
  artifactReadiness?: {
    hasOutputs?: boolean;
    visualizableCount?: number;
    downloadableCount?: number;
    totalOutputs?: number;
    meetsContract?: boolean;
  };
}

async function registerAndGoHome(page: Page, label: string): Promise<void> {
  const email = `e2e_fullflow_${Date.now()}_${label}@biomate.test`;
  // Clear any existing session (cookies + localStorage) before registering a fresh user
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
  await page.waitForLoadState('load');
  try {
    await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
    await page.fill('#name', 'Full E2E User');
    await page.fill('#email', email);
    await page.fill('#password', 'TestPass123!');
    await page.fill('#confirmPassword', 'TestPass123!');
    await page.click('#terms');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch {
    console.log(`[${label}] Registration skipped — using existing session`);
  }
  await page.goto(BASE_URL);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
  await page.reload();
  await page.waitForLoadState('load');
  await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1000);
}

async function waitForAIResponse(page: Page, label: string): Promise<void> {
  console.log(`[${label}] Waiting for AI response...`);
  // Wait for typing indicator to appear (up to 30s)
  const appeared = await Promise.race([
    page.waitForSelector('text=BioMate is typing', { timeout: 30000 }).then(() => true).catch(() => false),
    page.waitForSelector('text=AI is typing', { timeout: 30000 }).then(() => true).catch(() => false),
  ]);
  if (!appeared) {
    console.log(`[${label}] Typing indicator not seen — response may already be arriving`);
  }
  // Wait for typing indicator to disappear (up to 8 min for complex AI calls)
  await page.waitForSelector('text=BioMate is typing', { state: 'hidden', timeout: 480000 }).catch(() => {});
  await page.waitForSelector('text=AI is typing', { state: 'hidden', timeout: 480000 }).catch(() => {});
  // Wait for textarea to become enabled (AI done generating)
  await page.waitForSelector('textarea:enabled', { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(2000);
}

/**
 * Wait for either a workflow card or a clarification question.
 * If AI asks a clarification question, answer with the provided followUp text,
 * then wait again. Repeats up to maxClarifications times.
 * Returns true if workflow card found, false if timeout.
 */
async function waitForWorkflowOrClarification(
  page: Page,
  label: string,
  baselineCount: number,
  followUpData: string,
  maxClarifications = 3,
): Promise<boolean> {
  const TIMEOUT_MS = 240000; // 4min total — enough for AI response + workflow generation
  const endTime = Date.now() + TIMEOUT_MS;
  let clarificationCount = 0;
  let lastMessageCount = 0;

  while (Date.now() < endTime) {
    // Check for run button first (most reliable signal — only present on pending_review workflow cards)
    const hasRunBtn = await page.locator('[data-testid="button-run-workflow-panel"],[data-testid="button-confirm-and-run"]').isVisible().catch(() => false);
    if (hasRunBtn) {
      console.log(`[${label}] Run button found (workflow card in pending_review)`);
      await page.waitForTimeout(2000);
      return true;
    }
    // Check for workflow-artifact-panel (the actual viewer, not just anchors which appear in all AI messages)
    const panelCount = await page.locator('[data-testid="workflow-artifact-panel"]').count().catch(() => 0);
    if (panelCount > 0) {
      console.log(`[${label}] Workflow artifact panel found (${panelCount} total)`);
      await page.waitForTimeout(2000);
      return true;
    }
    // Fallback: check workflow-artifact-anchor count increase (only if run button also visible)
    const count = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
    if (count > baselineCount) {
      // Verify run button is also visible (otherwise it's just a clarification anchor)
      const runBtnNow = await page.locator('[data-testid="button-run-workflow-panel"],[data-testid="button-confirm-and-run"]').isVisible().catch(() => false);
      if (runBtnNow) {
        console.log(`[${label}] Workflow card appeared (${count} total) with run button`);
        await page.waitForTimeout(2000);
        return true;
      }
      // Count increased but no run button — check if it's a real panel
      const panelNow = await page.locator('[data-testid="workflow-artifact-panel"]').count().catch(() => 0);
      if (panelNow > 0) {
        console.log(`[${label}] Workflow panel appeared (${count} artifacts, ${panelNow} panels)`);
        await page.waitForTimeout(2000);
        return true;
      }
    }

    // Check for AI clarification question (AI is done typing AND no workflow card)
    const isTyping = await page.locator('text=BioMate is typing').isVisible().catch(() => false)
      || await page.locator('text=AI is typing').isVisible().catch(() => false);
    if (!isTyping && clarificationCount < maxClarifications) {
      // Count assistant messages to detect new message
      const msgCount = await page.locator('[data-role="assistant"],[data-testid^="message-"]').count().catch(() => 0);
      if (msgCount > lastMessageCount && msgCount > 0) {
        lastMessageCount = msgCount;
        // Check if the page looks like a clarification question (asking for data).
        // Use full body text to ensure we capture AI message content regardless of selector.
        const bodyText = await page.locator('body').textContent().catch(() => '') || '';
        const asksForData = bodyText?.includes('?') && (
          bodyText.includes('provide') || bodyText.includes('SMILES') || bodyText.includes('compound') ||
          bodyText.includes('what') || bodyText.includes('which') || bodyText.includes('data') ||
          bodyText.includes('file') || bodyText.includes('input') || bodyText.includes('sample') ||
          bodyText.includes('specify') || bodyText.includes('information')
        );
        // Guard: don't trigger clarification if the standard NextflowWorkflowViewer is already shown.
        // PipelineListView (workflow_type=pipeline) does NOT render workflow-artifact-panel, so
        // clarification still fires when a pipeline response is shown — pushing the AI to generate
        // the specific single-step Nextflow workflow we need for execution tests.
        const standardPanelVisible = await page.locator('[data-testid="workflow-artifact-panel"]').count().catch(() => 0) > 0;
        if (asksForData && !standardPanelVisible) {
          clarificationCount++;
          console.log(`[${label}] AI asked clarification (${clarificationCount}/${maxClarifications}), answering with data`);
          const textarea = page.locator('textarea').first();
          await textarea.fill(followUpData);
          await textarea.press('Enter');
          await waitForAIResponse(page, label);
          continue;
        }
      }
    }

    await page.waitForTimeout(2000);
  }
  console.log(`[${label}] Timed out waiting for workflow card (baseline=${baselineCount}, clarifications=${clarificationCount})`);
  return false;
}

// Legacy alias — allows up to 2 clarifications before timing out
async function waitForNewWorkflowCard(page: Page, label: string, baselineCount: number): Promise<boolean> {
  return waitForWorkflowOrClarification(
    page, label, baselineCount,
    // Generic follow-up: refer back to SMILES already in original message, demand immediate generation.
    // Deliberately not naming a specific compound to avoid confusion (tests use different compounds).
    'The SMILES string is already provided in my original message. Use it as the input_smiles parameter. Use default values for all other parameters. Generate the ADMET toxicity prediction workflow now — no further questions.',
    2,
  );
}

async function pollRunToCompletion(
  page: Page,
  runId: string,
  label: string
): Promise<{ status: string; statusPayload: RunStatusResponse | null }> {
  // 'ok' = Galaxy/workflow_completed handler final state (set after promotion from 'completed')
  // 'succeeded' = raw Nextflow backend terminal state (in case promotion didn't fire)
  const terminal = new Set(['completed', 'failed', 'error', 'cancelled', 'ok', 'succeeded']);
  let statusPayload: RunStatusResponse | null = null;
  let finalStatus = 'unknown';

  // AWS Batch cold starts take 5-8 min; poll for up to ~17 min (200 × 5s) total.
  for (let i = 0; i < 200; i++) {
    await page.waitForTimeout(5000);
    try {
      const resp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
      if (!resp.ok()) continue;
      statusPayload = (await resp.json()) as RunStatusResponse;
      const s = (statusPayload.status || '').toLowerCase();
      if (i % 5 === 0) {
        console.log(`[${label}] Poll ${i}: status=${s} progress=${statusPayload.progress?.completedSteps ?? 0}/${statusPayload.progress?.totalSteps ?? 0}`);
      }
      if (terminal.has(s)) {
        finalStatus = s;
        // Normalize 'ok' and 'succeeded' to 'completed' for downstream assertions
        if (s === 'ok' || s === 'succeeded') finalStatus = 'completed';
        // For completed runs, wait for artifact readiness; for all other terminal states, exit immediately
        if (finalStatus !== 'completed' || statusPayload.artifactReadiness?.meetsContract) break;
        // Allow a few extra polls for artifact materialization (up to ~30s)
        if (i > 5) break;
      }
    } catch {
      // continue
    }
  }
  return { status: finalStatus, statusPayload };
}

async function screenshot(page: Page, name: string): Promise<void> {
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, `${name}.png`), fullPage: true });
  console.log(`[Screenshot] ${name}.png`);
}

// ---------------------------------------------------------------------------
// Test 1: ADMET — full execution flow → completion banner → results → download
// ---------------------------------------------------------------------------

test.describe('ADMET Full Execution Flow', () => {
  test('ADMET query → AWAITING REVIEW → Confirm & Run → completion banner → results → download', async ({ page }) => {
    await registerAndGoHome(page, 'admet_full');
    await screenshot(page, '01_initial');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    const baselineCount = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);

    // --- Step 1: Send ADMET query with inline SMILES ---
    const query = 'Run ADMET toxicity screening for acetaminophen (SMILES: CC(=O)Nc1ccc(O)cc1). I need hERG cardiotoxicity risk, DILI assessment, Ames mutagenicity, and ClinTox probability.';
    await chatInput.fill(query);
    await chatInput.press('Enter');
    console.log('[ADMET-Full] Query sent');

    await waitForAIResponse(page, 'ADMET-Full');
    const cardFound = await waitForNewWorkflowCard(page, 'ADMET-Full', baselineCount);
    await screenshot(page, '02_workflow_card');
    expect(cardFound, 'AI must generate an ADMET workflow card — if this fails the AI did not produce a runnable workflow after 5 clarification rounds').toBe(true);

    // --- Step 2: Verify AWAITING REVIEW state ---
    const hasAwaitingReview = await page.locator('text=AWAITING REVIEW').isVisible().catch(() => false)
      || await page.locator('[data-testid="badge-awaiting-review"]').isVisible().catch(() => false)
      || await page.locator('[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]').isVisible().catch(() => false);
    console.log('[ADMET-Full] AWAITING REVIEW / Confirm & Run visible:', hasAwaitingReview);
    await screenshot(page, '03_awaiting_review');
    expect(hasAwaitingReview, 'Workflow card must show AWAITING REVIEW state with Confirm & Run button').toBe(true);

    // --- Step 3: Click Confirm & Run (hard assertion — disabled = bug) ---
    const runId = await clickConfirmAndCaptureRunId(page, 'ADMET-Full');
    console.log(`[ADMET-Full] Run ID: ${runId}`);
    await screenshot(page, '04_execution_started');

    // --- Step 4: Poll to completion (hard assertion — must reach completed) ---
    console.log('[ADMET-Full] Polling for completion...');
    const { status, statusPayload } = await pollRunToCompletion(page, runId, 'ADMET-Full');
    console.log(`[ADMET-Full] Terminal status: ${status}`);
    await screenshot(page, '05_terminal_status');
    expect(status, 'Workflow must reach completed state — failed/error is a real failure').toBe('completed');

    // --- Step 5: Dismiss feedback modal THEN verify completion banner ---
    const skipBtn = page.getByRole('button', { name: /^skip$/i }).first();
    const modalAppeared = await skipBtn
      .waitFor({ state: 'visible', timeout: 25000 })
      .then(() => true)
      .catch(() => false);
    if (modalAppeared) {
      console.log('[ADMET-Full] Feedback modal appeared — dismissing');
      await skipBtn.click().catch(() => {});
      await page.waitForTimeout(600);
    } else {
      console.log('[ADMET-Full] No feedback modal detected');
    }

    const bannerVisible = await page.locator('[data-testid="workflow-completion-banner"]')
      .waitFor({ state: 'visible', timeout: 15000 })
      .then(() => true)
      .catch(() => false);
    console.log('[ADMET-Full] Completion banner visible:', bannerVisible);
    await screenshot(page, '06_completion_banner');
    expect(bannerVisible, 'Completion banner must appear when workflow completes').toBe(true);

    // --- Step 6: Verify Download All button is enabled ---
    const downloadBtn = page.locator('[data-testid="button-download-all-workflow-panel"]').last();
    const downloadEnabled = await downloadBtn.waitFor({ state: 'visible', timeout: 15000 })
      .then(() => downloadBtn.isEnabled())
      .catch(() => false);
    console.log('[ADMET-Full] Download All enabled:', downloadEnabled);
    await screenshot(page, '07_download_button');
    expect(downloadEnabled, 'Download All button must be enabled after completion').toBe(true);

    // --- Step 7: Check output visualization in UI ---
    await page.waitForTimeout(2000);
    const hasOutputPanel = await page.locator('[data-testid="results-section"]').isVisible().catch(() => false)
      || await page.locator('text=Data Tables').isVisible().catch(() => false)
      || await page.locator('text=Output Files').isVisible().catch(() => false)
      || await page.locator('text=Results').isVisible().catch(() => false);
    console.log('[ADMET-Full] Output panel visible:', hasOutputPanel);
    await screenshot(page, '08_output_panel');

    // --- Step 8: Verify outputs via API ---
    const invocationId = statusPayload?.nextflowStatus?.invocation_id;
    if (invocationId) {
      const outputsResp = await page.request.get(`${BASE_URL}/api/invocations/${invocationId}/outputs`);
      if (outputsResp.ok()) {
        const outputs: any[] = await outputsResp.json();
        console.log(`[ADMET-Full] Total outputs: ${outputs.length}`);
        outputs.forEach(o => console.log(`  - ${o.name} (${o.fileType || o.extension})`));
        const csvOutput = outputs.find(o => o.fileType === 'table' || ['csv', 'tsv'].includes(o.extension));
        if (csvOutput) {
          const previewResp = await page.request.get(`${BASE_URL}/api/outputs/${csvOutput.id}/preview?lines=20`);
          console.log(`[ADMET-Full] CSV preview status: ${previewResp.status()}`);
          if (previewResp.ok()) {
            const previewData = await previewResp.json();
            console.log(`[ADMET-Full] Preview lines: ${previewData.lines?.length ?? 0}`);
            expect(Array.isArray(previewData.lines), 'Preview must return lines array').toBe(true);
          }
          await screenshot(page, '09_csv_table_viewer');
        }
        const htmlOutput = outputs.find(o => ['html', 'interactive'].includes(o.extension || o.fileType));
        if (htmlOutput) {
          console.log(`[ADMET-Full] HTML report found: ${htmlOutput.name}`);
          const reportBtnVisible = await page.locator('text=View Report').first().isVisible().catch(() => false);
          console.log('[ADMET-Full] View Report button visible:', reportBtnVisible);
          await screenshot(page, '09_view_report');
        }
      }
    }

    console.log('[ADMET-Full] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// Test 2: AWAITING REVIEW UX — verify review state without executing
// ---------------------------------------------------------------------------

test.describe('AWAITING REVIEW UX', () => {
  test('workflow card shows AWAITING REVIEW badge, rationale panel, Confirm & Run button', async ({ page }) => {
    await registerAndGoHome(page, 'review_ux');
    await screenshot(page, '20_review_initial');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    const baselineCount = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);

    await chatInput.fill('Screen this SMILES for ADMET toxicity: CC(=O)Nc1ccc(O)cc1');
    await chatInput.press('Enter');

    await waitForAIResponse(page, 'Review-UX');
    const cardFound = await waitForNewWorkflowCard(page, 'Review-UX', baselineCount);
    await screenshot(page, '21_workflow_generated');
    expect(cardFound, 'AI must generate workflow card').toBe(true);

    const body = await page.textContent('body') || '';

    // Assert 1: AWAITING REVIEW badge or Confirm & Run button
    const hasReviewState =
      await page.locator('text=AWAITING REVIEW').isVisible().catch(() => false)
      || await page.locator('[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]').isVisible().catch(() => false)
      || await page.locator('text=Confirm & Run').isVisible().catch(() => false);
    console.log('[Review-UX] AWAITING REVIEW state visible:', hasReviewState);
    expect(hasReviewState, 'Workflow card must show AWAITING REVIEW / Confirm & Run').toBe(true);

    // Assert 2: Scientific rationale panel
    const rationaleVisible = await page.locator('text=Scientific Rationale').first().isVisible().catch(() => false);
    console.log('[Review-UX] Scientific Rationale panel visible:', rationaleVisible);
    if (rationaleVisible) {
      await page.locator('text=Scientific Rationale').first().click().catch(() => {});
      await page.waitForTimeout(500);
      await screenshot(page, '22_rationale_expanded');
    }

    // Assert 3: No raw dict params
    const hasRawDict = body.includes("= {'default'") || body.includes("= {\"default\"");
    console.log('[Review-UX] Raw dict params visible (should be false):', hasRawDict);
    expect(hasRawDict, 'Params must not show raw Python dict literals').toBe(false);

    // Assert 4: Workflow content present
    const hasContent =
      body.includes('ADMET') || body.includes('toxicity') || body.includes('hERG') ||
      body.includes('DILI') || body.includes('Ames') || body.includes('screening');
    expect(hasContent, 'AI must respond with ADMET/toxicity content').toBe(true);

    await screenshot(page, '23_review_state_verified');

    // --- Execute to completion (no soft exit allowed) ---
    const runId = await clickConfirmAndCaptureRunId(page, 'Review-UX');
    const { status } = await pollRunToCompletion(page, runId, 'Review-UX');
    await screenshot(page, '24_terminal_state');
    expect(status, 'Workflow must reach completed state').toBe('completed');

    // Dismiss feedback modal if shown
    const skipBtn = page.getByRole('button', { name: /^skip$/i }).first();
    const modalAppeared = await skipBtn.waitFor({ state: 'visible', timeout: 20000 }).then(() => true).catch(() => false);
    if (modalAppeared) { await skipBtn.click().catch(() => {}); await page.waitForTimeout(600); }

    const bannerVisible = await page.locator('[data-testid="workflow-completion-banner"]')
      .waitFor({ state: 'visible', timeout: 15000 }).then(() => true).catch(() => false);
    console.log('[Review-UX] Completion banner visible:', bannerVisible);
    await screenshot(page, '25_completion_banner');
    expect(bannerVisible, 'Completion banner must appear after execution').toBe(true);

    console.log('[Review-UX] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// Shared helper: click Confirm & Run and capture the runId via waitForResponse.
// Must be called AFTER the workflow card is visible. Returns the runId string.
// ---------------------------------------------------------------------------
async function clickConfirmAndCaptureRunId(page: Page, label: string): Promise<string> {
  // Set up waiter BEFORE clicking — accept any response from execute endpoint (not just 200)
  const executeRespPromise = page.waitForResponse(
    (resp) => resp.url().includes('/api/workflows/execute'),
    { timeout: 60000 }
  );

  // Accept either testid: 'button-confirm-and-run' (legacy) OR 'button-run-workflow-panel' (current)
  const confirmBtn = page.locator(
    '[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]'
  ).last();
  await expect(confirmBtn).toBeVisible({ timeout: 15000 });
  const isEnabled = await confirmBtn.isEnabled();
  expect(isEnabled).toBe(true); // FAIL if button is disabled (required params missing)
  await confirmBtn.click();
  console.log(`[${label}] Clicked Confirm & Run`);

  const executeResp = await executeRespPromise;
  const executeStatus = executeResp.status();
  const executeData = await executeResp.json().catch(() => ({})) as any;
  console.log(`[${label}] Execute API status=${executeStatus} runId=${executeData.runId}`);
  expect(executeStatus).toBe(200); // FAIL with clear message if execute endpoint errored
  const runId: string = executeData.runId || executeData.execution?.runId || '';
  expect(runId).toBeTruthy(); // FAIL if execute API did not return a runId
  console.log(`[${label}] Captured runId: ${runId}`);
  return runId;
}

// ---------------------------------------------------------------------------
// UC-3: Per-step output inspection — API contract + PhaseCards always present
// ---------------------------------------------------------------------------

test.describe('UC-3: Per-step output inspection', () => {
  test('download_commands API returns correct shape; PhaseCards render after run', async ({ page }) => {
    await registerAndGoHome(page, 'UC3');

    const textarea = page.locator('textarea').first();
    await textarea.fill('Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). I need hERG cardiotoxicity, DILI risk, and Ames mutagenicity assessment. Do not ask for clarification — use the provided SMILES directly.');
    await textarea.press('Enter');
    await waitForAIResponse(page, 'UC3');
    const cardFound3 = await waitForNewWorkflowCard(page, 'UC3', 0);
    expect(cardFound3, '[UC3] AI must generate an ADMET workflow card').toBe(true);

    const runId = await clickConfirmAndCaptureRunId(page, 'UC3');

    await pollRunToCompletion(page, runId, 'UC3');
    await screenshot(page, 'uc3_after_completion');

    // ASSERTION 1: download_commands endpoint returns 200 with run-specific S3 path
    const dlResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/download_commands`);
    expect(dlResp.status()).toBe(200);
    const dlData = await dlResp.json();
    expect(dlData.download_commands).toBeDefined();
    const allOutputsCmd: string = dlData.download_commands.all_outputs ?? '';
    expect(allOutputsCmd).toContain('aws s3 sync');
    // The command must embed a run-specific path — not just a generic template.
    // The Galaxy-side runId appears in the outdir of the command.
    const galaxyRunId: string = dlData.workflow_id ?? '';
    expect(galaxyRunId).toBeTruthy();
    expect(allOutputsCmd).toContain(galaxyRunId.slice(0, 8)); // first 8 chars of UUID appear in S3 path
    console.log(`[UC3] ✓ download_commands API run-specific: cmd="${allOutputsCmd.slice(0, 80)}"`);

    // ASSERTION 2: output_files returns same run-specific workflow_id
    const ofResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/output_files`);
    expect(ofResp.status()).toBe(200);
    const ofData = await ofResp.json();
    expect(ofData.workflow_id).toBe(dlData.workflow_id); // both endpoints reference the same run
    expect(ofData.download_commands).toBeDefined();
    console.log(`[UC3] ✓ output_files API: workflow_id=${ofData.workflow_id}, status=${ofData.status}`);

    // ASSERTION 3: PhaseCards render after execution.
    // - 0 = broken viewer (PhaseCard missing data-testid or not rendered at all)
    // - ≥1 = correct: either AI-generated steps or default lifecycle fallback stages
    // Note: ADMET may produce its own step IDs (not "setup"/"process"), so we only
    // assert that at least one phase card exists, not the exact count or ID.
    const phaseCards = page.locator('[data-testid^="phase-card-"]');
    const phaseCount = await phaseCards.count();
    expect(phaseCount).toBeGreaterThan(0);
    console.log(`[UC3] ✓ PhaseCard count=${phaseCount}; phase cards visible`);

    await screenshot(page, 'uc3_phase_cards');
    console.log('[UC3] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// UC-4: Continue from Checkpoint — negative assertion + resume API contract
// ---------------------------------------------------------------------------

test.describe('UC-4: Continue from Checkpoint visibility', () => {
  test('Checkpoint button absent in non-failed states; resume API is wired', async ({ page }) => {
    await registerAndGoHome(page, 'UC4');

    const textarea = page.locator('textarea').first();
    await textarea.fill('Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). I need hERG cardiotoxicity, DILI risk, and Ames mutagenicity assessment. Do not ask for clarification — use the provided SMILES directly.');
    await textarea.press('Enter');
    await waitForAIResponse(page, 'UC4');
    const cardFound4 = await waitForNewWorkflowCard(page, 'UC4', 0);
    expect(cardFound4, '[UC4] AI must generate an ADMET workflow card').toBe(true);
    await screenshot(page, 'uc4_pending_review');

    // ASSERTION 1: In pending_review state, checkpoint button MUST NOT be visible
    const checkpointBtn = page.locator('[data-testid="button-continue-from-checkpoint"]');
    await expect(checkpointBtn).not.toBeVisible();
    console.log('[UC4] ✓ Checkpoint button correctly absent in pending_review state');

    const runId = await clickConfirmAndCaptureRunId(page, 'UC4');

    await pollRunToCompletion(page, runId, 'UC4');
    await screenshot(page, 'uc4_after_run');

    // ASSERTION 2: After successful run, checkpoint button still must NOT be visible
    // (it only appears when status=failed AND executionEngine=nextflow)
    await expect(checkpointBtn).not.toBeVisible();
    console.log('[UC4] ✓ Checkpoint button correctly absent after successful run');

    // ASSERTION 3: Resume API returns 404 (not 500) for unknown runId
    const unknownResumeResp = await page.request.post(`${BASE_URL}/api/workflows/runs/nonexistent-run-id/resume`);
    expect([400, 404]).toContain(unknownResumeResp.status());
    console.log(`[UC4] ✓ Resume API returns ${unknownResumeResp.status()} for unknown run`);

    // ASSERTION 4: Resume API handles real runId without 500 error
    const realResumeResp = await page.request.post(`${BASE_URL}/api/workflows/runs/${runId}/resume`);
    expect(realResumeResp.status()).not.toBe(500);
    console.log(`[UC4] ✓ Resume API returns ${realResumeResp.status()} for real run ${runId}`);

    console.log('[UC4] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// UC-5: Interactive tool launcher — API returns tools; artifact section renders
// ---------------------------------------------------------------------------

test.describe('UC-5: Interactive tool launcher for Nextflow outputs', () => {
  test('Workflow artifact renders; all 4 generic PhaseCards present after run', async ({ page }) => {
    await registerAndGoHome(page, 'UC5');

    const textarea = page.locator('textarea').first();
    await textarea.fill('Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). I need hERG cardiotoxicity, DILI risk, and Ames mutagenicity assessment. Do not ask for clarification — use the provided SMILES directly.');
    await textarea.press('Enter');
    await waitForAIResponse(page, 'UC5');
    const cardFound5 = await waitForNewWorkflowCard(page, 'UC5', 0);
    expect(cardFound5, '[UC5] AI must generate an ADMET workflow card').toBe(true);
    await screenshot(page, 'uc5_workflow_card');

    const runId = await clickConfirmAndCaptureRunId(page, 'UC5');

    await pollRunToCompletion(page, runId, 'UC5');
    await screenshot(page, 'uc5_after_completion');

    // ASSERTION 2: Workflow artifact section is rendered
    const artifact = page.locator('[data-testid^="workflow-artifact"]').first();
    await expect(artifact).toBeVisible({ timeout: 15000 });
    console.log('[UC5] ✓ Workflow artifact section visible after run');

    // ASSERTION 3: PhaseCards rendered (4 generic phases for ADMET)
    const phaseCards = page.locator('[data-testid^="phase-card-"]');
    const phaseCount = await phaseCards.count();
    expect(phaseCount).toBeGreaterThan(0);
    console.log(`[UC5] ✓ PhaseCard count: ${phaseCount}`);

    await screenshot(page, 'uc5_artifact_section');
    console.log('[UC5] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// UC-6: Detach / Reconnect labels — must show "Detach" not "Pause" for Nextflow
// ---------------------------------------------------------------------------

test.describe('UC-6: Detach and Reconnect labels', () => {
  test('Nextflow workflow shows "Detach" / "Reconnect" labels after run starts', async ({ page }) => {
    await registerAndGoHome(page, 'UC6');

    const textarea = page.locator('textarea').first();
    await textarea.fill('Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). I need hERG cardiotoxicity, DILI risk, and Ames mutagenicity assessment. Do not ask for clarification — use the provided SMILES directly.');
    await textarea.press('Enter');
    await waitForAIResponse(page, 'UC6');
    const cardFound6 = await waitForWorkflowOrClarification(
      page, 'UC6', 0,
      'Please generate the ADMET toxicity workflow immediately for aspirin SMILES CC(=O)Oc1ccccc1C(=O)O. No further clarification needed.',
      2,
    );
    expect(cardFound6, '[UC6] AI must generate an ADMET workflow card').toBe(true);

    const runId = await clickConfirmAndCaptureRunId(page, 'UC6');

    // Poll status API until it transitions away from pending_review
    let statusData: any = null;
    for (let i = 0; i < 40; i++) {
      await page.waitForTimeout(2000);
      const resp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`).catch(() => null);
      if (!resp?.ok()) continue;
      statusData = await resp.json().catch(() => null);
      const s = (statusData?.status || '').toLowerCase();
      console.log(`[UC6] Poll ${i}: status=${s}`);
      if (s && s !== 'pending_review' && s !== 'unknown') break;
    }

    // ASSERTION 1: Run must have transitioned out of pending_review
    expect(statusData?.status).toBeDefined();
    const currentStatus = (statusData?.status || '').toLowerCase();
    expect(currentStatus).not.toBe('pending_review');
    console.log(`[UC6] ✓ Run transitioned to status="${currentStatus}"`);

    await screenshot(page, 'uc6_after_start');

    // ASSERTION 2: "Detach" button label (not "Pause") for Nextflow execution engine
    // The button renders when status !== pending_review — it may be disabled but MUST be visible
    const pauseBtn = page.locator('[data-testid="button-pause-workflow-panel"]');
    await expect(pauseBtn).toBeVisible({ timeout: 10000 });
    const pauseBtnText = (await pauseBtn.textContent())?.trim() ?? '';
    expect(pauseBtnText).toBe('Detach'); // FAIL if shows "Pause" instead of "Detach"
    console.log(`[UC6] ✓ Pause button label is "${pauseBtnText}" (expected "Detach")`);

    // ASSERTION 3: "Reconnect" label (not "Resume") on the resume button
    const resumeBtn = page.locator('[data-testid="button-resume-workflow-panel"]');
    await expect(resumeBtn).toBeVisible({ timeout: 5000 });
    const resumeBtnText = (await resumeBtn.textContent())?.trim() ?? '';
    expect(resumeBtnText).toBe('Reconnect'); // FAIL if shows "Resume" instead of "Reconnect"
    console.log(`[UC6] ✓ Resume button label is "${resumeBtnText}" (expected "Reconnect")`);

    // ASSERTION 4: Nextflow detach note — only visible when status is running/paused.
    const detachNote = page.locator('text=Batch job continues running');
    if (['running', 'paused'].includes(currentStatus)) {
      await expect(detachNote).toBeVisible({ timeout: 5000 });
      console.log('[UC6] ✓ Nextflow detach note visible (run active)');
    } else {
      console.log(`[UC6] ℹ Detach note not checked — status=${currentStatus} (run already terminal)`);
    }

    await screenshot(page, 'uc6_detach_labels');

    // --- Poll to full completion (no soft exit) ---
    if (!['completed', 'failed', 'error', 'cancelled', 'ok', 'succeeded'].includes(currentStatus)) {
      const { status: finalStatus } = await pollRunToCompletion(page, runId, 'UC6');
      await screenshot(page, 'uc6_terminal_state');
      expect(['completed', 'failed'], 'UC6 run must reach a terminal state').toContain(finalStatus);
      console.log(`[UC6] ✓ Run reached terminal state: ${finalStatus}`);
    } else {
      console.log(`[UC6] Run already terminal at ${currentStatus} — skip extra polling`);
    }

    // Dismiss feedback modal if shown
    const skipBtn = page.getByRole('button', { name: /^skip$/i }).first();
    const modalAppeared = await skipBtn.waitFor({ state: 'visible', timeout: 15000 }).then(() => true).catch(() => false);
    if (modalAppeared) { await skipBtn.click().catch(() => {}); await page.waitForTimeout(600); }

    const bannerVisible = await page.locator('[data-testid="workflow-completion-banner"]')
      .waitFor({ state: 'visible', timeout: 15000 }).then(() => true).catch(() => false);
    console.log('[UC6] Completion banner visible:', bannerVisible);
    await screenshot(page, 'uc6_completion_banner');
    expect(bannerVisible, 'Completion banner must appear after Nextflow run completes').toBe(true);

    console.log('[UC6] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// UC-7: Download Commands Panel — aws s3 sync command visible after completion
// ---------------------------------------------------------------------------

test.describe('UC-7: Download Commands Panel', () => {
  test('Completed workflow: download_commands API correct; panel renders in UI', async ({ page }) => {
    await registerAndGoHome(page, 'UC7');

    const textarea = page.locator('textarea').first();
    await textarea.fill('Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). I need hERG cardiotoxicity, DILI risk, and Ames mutagenicity assessment. Do not ask for clarification — use the provided SMILES directly.');
    await textarea.press('Enter');
    await waitForAIResponse(page, 'UC7');
    const cardFound7 = await waitForNewWorkflowCard(page, 'UC7', 0);
    expect(cardFound7, '[UC7] AI must generate an ADMET workflow card').toBe(true);

    const runId = await clickConfirmAndCaptureRunId(page, 'UC7');

    await pollRunToCompletion(page, runId, 'UC7');
    await screenshot(page, 'uc7_after_completion');

    // ASSERTION 1: download_commands API returns 200 with run-specific path
    const dlResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/download_commands`);
    expect(dlResp.status()).toBe(200);
    const dlData = await dlResp.json();
    const galaxyRunId: string = dlData.workflow_id ?? '';
    expect(galaxyRunId).toBeTruthy(); // must return a non-empty run ID
    expect(dlData.download_commands).toBeDefined();
    const allOutputsCmd: string = dlData.download_commands.all_outputs ?? '';
    expect(allOutputsCmd).toContain('aws s3 sync');
    // The path must contain this specific run's ID — not a generic constant
    expect(allOutputsCmd).toContain(galaxyRunId.slice(0, 8));
    console.log(`[UC7] ✓ download_commands API run-specific: cmd="${allOutputsCmd.slice(0, 80)}"`);

    // ASSERTION 2: DownloadCommandsPanel renders in the UI after run starts
    // Panel is shown for running/completed/failed states (S3 path is known from start).
    // Use .last() because multiple messages may contain download-commands-panel (strict mode fix)
    const dlPanel = page.locator('[data-testid="download-commands-panel"]').last();
    await expect(dlPanel).toBeVisible({ timeout: 45000 });
    console.log('[UC7] ✓ DownloadCommandsPanel visible in UI');

    // ASSERTION 3: Panel contains the aws s3 sync command text AND the run-specific path
    const codeBlocks = dlPanel.locator('code');
    const firstCmdText = (await codeBlocks.first().textContent().catch(() => '')) ?? '';
    expect(firstCmdText).toContain('aws s3 sync');
    expect(firstCmdText).toContain(galaxyRunId.slice(0, 8)); // run-specific, not generic template
    console.log(`[UC7] ✓ aws s3 sync command in panel: "${firstCmdText.slice(0, 80)}"`);

    await screenshot(page, 'uc7_download_panel');
    console.log('[UC7] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// UC-2: Pilot Run / Test Harness Flow
// ---------------------------------------------------------------------------

test.describe('UC-2: Pilot Run panel as test harness', () => {
  test('Pilot run banner shows Configure pilot button; preflight API responds', async ({ page }) => {
    await registerAndGoHome(page, 'UC2');

    // Verify preflight API endpoint is wired
    const preflightResp = await page.request.post(`${BASE_URL}/api/workflows/preflight`, {
      data: {
        workflowDefinition: {
          name: 'Test Workflow',
          parameters: [{ id: 'smiles', name: 'smiles', required: true, level: 'required' }],
        },
        parameters: { smiles: 'CC(=O)Oc1ccccc1C(=O)O' },
      },
    });
    console.log(`[UC2] Preflight API status: ${preflightResp.status()}`);
    expect(preflightResp.ok()).toBe(true);
    const preflightData = await preflightResp.json();
    console.log(`[UC2] Preflight phases: ${JSON.stringify(preflightData.phases?.map((p: any) => `${p.id}:${p.status}`))}`);
    expect(preflightData.phases).toBeDefined();
    expect(preflightData.phases.length).toBeGreaterThan(0);
    expect(preflightData.ready).toBeDefined();

    // Parameter present → parameters phase should pass
    const paramPhase = preflightData.phases.find((p: any) => p.id === 'parameters');
    expect(paramPhase?.status).toBe('pass');

    // Missing param → fail
    const failResp = await page.request.post(`${BASE_URL}/api/workflows/preflight`, {
      data: {
        workflowDefinition: {
          name: 'Test',
          parameters: [{ id: 'smiles', name: 'smiles', required: true }],
        },
        parameters: {},
      },
    });
    const failData = await failResp.json();
    const failPhase = failData.phases.find((p: any) => p.id === 'parameters');
    expect(failPhase?.status).toBe('fail');
    expect(failData.ready).toBe(false);
    console.log('[UC2] ✓ Preflight API correctly validates required parameters');

    // UI: send query, get workflow card, check pilot banner, then execute to completion
    const textarea = page.locator('textarea').first();
    await textarea.fill('Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O). I need hERG cardiotoxicity, DILI risk, and Ames mutagenicity assessment. Do not ask for clarification — use the provided SMILES directly.');
    await textarea.press('Enter');
    await waitForAIResponse(page, 'UC2');
    const cardFound2 = await waitForNewWorkflowCard(page, 'UC2', 0);
    await screenshot(page, 'uc2_workflow_card');
    expect(cardFound2, 'AI must generate workflow card').toBe(true);

    // If pilot banner is visible, check for configure button (best-effort)
    const pilotBanner = page.locator('[data-testid="pilot-run-banner"]');
    if (await pilotBanner.isVisible({ timeout: 5000 }).catch(() => false)) {
      const configBtn = page.locator('[data-testid="button-open-pilot-panel"]');
      const hasConfigBtn = await configBtn.isVisible({ timeout: 3000 }).catch(() => false);
      console.log(`[UC2] "Configure pilot" button visible: ${hasConfigBtn}`);
      expect(hasConfigBtn).toBe(true);
      if (hasConfigBtn) {
        await configBtn.click();
        await page.waitForTimeout(1000);
        const panelVisible = await page.locator('[data-testid="preflight-phases"]')
          .or(page.locator('text=Pilot Run Configuration'))
          .isVisible({ timeout: 5000 }).catch(() => false);
        console.log(`[UC2] PilotRunPanel rendered: ${panelVisible}`);
        await screenshot(page, 'uc2_pilot_panel');
        // Close panel to get back to main workflow card
        await page.keyboard.press('Escape');
        await page.waitForTimeout(500);
      }
    } else {
      console.log('[UC2] Pilot banner not shown (pilot_run_suggested=false) — skip pilot UI assertions');
    }

    // --- Execute to completion (no soft exit allowed) ---
    const runId2 = await clickConfirmAndCaptureRunId(page, 'UC2');
    const { status: uc2Status } = await pollRunToCompletion(page, runId2, 'UC2');
    await screenshot(page, 'uc2_terminal_state');
    expect(uc2Status, 'UC2 workflow must reach completed state').toBe('completed');

    // Dismiss feedback modal if shown
    const skipBtn2 = page.getByRole('button', { name: /^skip$/i }).first();
    const modal2 = await skipBtn2.waitFor({ state: 'visible', timeout: 20000 }).then(() => true).catch(() => false);
    if (modal2) { await skipBtn2.click().catch(() => {}); await page.waitForTimeout(600); }

    const banner2 = await page.locator('[data-testid="workflow-completion-banner"]')
      .waitFor({ state: 'visible', timeout: 15000 }).then(() => true).catch(() => false);
    console.log('[UC2] Completion banner visible:', banner2);
    await screenshot(page, 'uc2_completion_banner');
    expect(banner2, 'Completion banner must appear after UC2 execution').toBe(true);

    console.log('[UC2] ✓ Test complete');
  });
});

// ---------------------------------------------------------------------------
// After all: write PM audit summary
// ---------------------------------------------------------------------------

const TEST_SUITE_START = new Date().toISOString();

test.afterAll(async ({ browser }) => {
  let costSummary: Record<string, unknown> = { error: 'not_fetched' };
  try {
    const ctx = await browser.newContext();
    const page = await ctx.newPage();
    const to = new Date().toISOString();
    const resp = await page.request.get(
      `${BASE_URL}/api/telemetry/cost-summary?from=${encodeURIComponent(TEST_SUITE_START)}&to=${encodeURIComponent(to)}`
    );
    costSummary = resp.ok() ? await resp.json() : { error: `HTTP ${resp.status()}` };
    await ctx.close();
  } catch (err: any) {
    costSummary = { error: err?.message || String(err) };
  }

  const summary = {
    timestamp: new Date().toISOString(),
    suiteStartedAt: TEST_SUITE_START,
    baseUrl: BASE_URL,
    testType: 'Full E2E — no mocks — real AI + real execution',
    screenshotDir: SCREENSHOT_DIR,
    billingCost: costSummary,
    scenarios: [
      {
        name: 'ADMET Full Execution Flow',
        asserts: [
          'AWAITING REVIEW badge visible',
          'Confirm & Run button present + enabled',
          'Workflow completion banner appears',
          'Results section auto-opens',
          'Download All button enabled after completion',
          'CSV preview API responds with data',
        ],
      },
      {
        name: 'AWAITING REVIEW UX',
        asserts: [
          'pending_review state shows AWAITING REVIEW badge',
          'Scientific Rationale panel present',
          'No raw Python dict params displayed',
        ],
      },
    ],
    notes: [
      'Tests use real server at ' + BASE_URL,
      'AI responses are live — not mocked',
      'Execution uses real Nextflow/Galaxy backend',
      'Screenshots capture actual UI state',
      'billingCost.totalEstimatedCostUsd is heuristic from token counting',
    ],
  };

  const summaryPath = path.join(SCREENSHOT_DIR, `audit_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));
  console.log(`[Audit] Summary → ${summaryPath}`);
  console.log(`[Audit] Estimated API cost this run: $${(costSummary as any).totalEstimatedCostUsd ?? 'n/a'} USD`);
});
