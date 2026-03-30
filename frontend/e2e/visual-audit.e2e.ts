/**
 * Visual Screenshot Audit — 2026-03-22
 * Verifies: chain plan card, real PhaseCard process names, output file cards, chain API
 */

import { test, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = 'http://localhost:5000';
const DIR = path.join(__dirname, 'screenshots', 'audit_2026-03-22');
fs.mkdirSync(DIR, { recursive: true });

const ss = async (page: Page, name: string) => {
  await page.screenshot({ path: path.join(DIR, name), fullPage: false });
  console.log(`[screenshot] ${name}`);
};

const waitAI = async (page: Page, ms = 90_000) => {
  // Count current assistant messages BEFORE waiting, so we know when a NEW one arrives
  const before = await page.locator('[data-is-latest-assistant="true"], [data-message-role="assistant"]').count();

  // Wait for a new assistant message to appear beyond the current count
  await page.waitForFunction(
    (beforeCount: number) => {
      const msgs = document.querySelectorAll('[data-is-latest-assistant="true"], [data-message-role="assistant"]');
      return msgs.length > beforeCount;
    },
    before,
    { timeout: ms }
  ).catch(() => {});

  // Wait for the typing/analysis indicator to disappear
  await page.waitForFunction(
    () => !document.querySelector('[data-testid="chat-analysis-status"]'),
    { timeout: ms }
  ).catch(() => {});

  // Extra wait for SSE stream to finish and React to render
  await page.waitForTimeout(3000);
};

// ── helpers ───────────────────────────────────────────────────────────────────

async function login(page: Page) {
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(800);

  // Already logged in?
  if (await page.locator('textarea').isVisible({ timeout: 3000 }).catch(() => false)) return;

  // Click Sign In link / button
  const signIn = page.getByRole('link', { name: /sign in/i })
    .or(page.getByRole('button', { name: /sign in/i }));
  await signIn.first().click();
  await page.waitForTimeout(600);

  await page.locator('input[type="email"]').fill('researcher@biomate.ai');
  await page.locator('input[type="password"]').fill('ResearchPass123!');
  await page.getByRole('button', { name: /sign in|log in|submit/i }).click();
  await page.waitForTimeout(2000);
}

async function newChat(page: Page) {
  const btn = page.getByRole('button', { name: /new chat/i });
  if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await btn.click();
    await page.waitForTimeout(800);
  }
}

async function sendMessage(page: Page, msg: string) {
  const ta = page.locator('textarea').first();
  await ta.waitFor({ state: 'visible', timeout: 10000 });
  await ta.fill(msg);
  await ta.press('Enter');
}

// ── tests ─────────────────────────────────────────────────────────────────────

test.describe('Visual Audit 2026-03-22', () => {
  test.setTimeout(420_000);

  test('A: Login', async ({ page }) => {
    await login(page);
    await ss(page, '00_logged_in.png');
  });

  // ── CHAIN PLAN CARD ────────────────────────────────────────────────────────
  test('B: WorkflowChainPlan for RNA-seq DE', async ({ page }) => {
    await login(page);
    await newChat(page);
    await ss(page, '01_empty_chat.png');

    await sendMessage(page, 'I need to run bulk RNA-seq differential expression analysis');
    await ss(page, '02_after_send.png');

    await waitAI(page, 90_000);
    await ss(page, '03_chain_response_full.png');

    // Wait up to 15s for the workflow card anchor to appear (SSE delivers it last)
    const chainCard = page.locator('[data-testid^="workflow-artifact-anchor"]').first();
    await chainCard.waitFor({ state: 'visible', timeout: 15_000 }).catch(() => {});
    if (await chainCard.isVisible({ timeout: 1000 }).catch(() => false)) {
      await chainCard.scrollIntoViewIfNeeded();
      await page.waitForTimeout(1000);
    }
    await ss(page, '04_chain_card_scrolled.png');

    // Check for WorkflowChainPlan component markers
    const isPipelinePlan = await page.locator('text=/Pipeline Plan|pipeline plan/i').isVisible({ timeout: 2000 }).catch(() => false);
    const isStepConnected = await page.locator('text=/Step 1|step 1/i').isVisible({ timeout: 2000 }).catch(() => false);
    const hasArrow = await page.locator('text=/→/').isVisible({ timeout: 2000 }).catch(() => false);
    const hasRunWorkflow = await page.locator('button:has-text("Run Workflow"), button:has-text("Run Pipeline")').isVisible({ timeout: 2000 }).catch(() => false);

    console.log(`[B] isPipelinePlan=${isPipelinePlan} isStepConnected=${isStepConnected} hasArrow=${hasArrow} hasRunButton=${hasRunWorkflow}`);
  });

  // ── ADMET workflow + execution panel ──────────────────────────────────────
  test('C: ADMET workflow card and execution panel', async ({ page }) => {
    await login(page);
    await newChat(page);

    await sendMessage(page, 'Run ADMET toxicity screening for acetaminophen');
    await waitAI(page, 60_000);
    await ss(page, '05_admet_response.png');

    // Scroll to workflow card
    const wfCard = page.locator('[data-testid^="workflow-artifact-anchor"]').first();
    if (await wfCard.isVisible({ timeout: 3000 }).catch(() => false)) {
      await wfCard.scrollIntoViewIfNeeded();
      await page.waitForTimeout(400);
    }
    await ss(page, '06_admet_workflow_card.png');

    // Check execution checklist / right panel
    const execPanel = page.locator('text=/Execution Progress|Execution Checklist/i').first();
    if (await execPanel.isVisible({ timeout: 3000 }).catch(() => false)) {
      await execPanel.scrollIntoViewIfNeeded();
      await ss(page, '07_execution_panel.png');
    }

    // Click Run Workflow
    const runBtn = page.getByTestId('button-run-workflow-panel')
      .or(page.getByRole('button', { name: /run workflow/i })).first();
    if (await runBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await runBtn.click();
      await page.waitForTimeout(8000);
      await ss(page, '08_after_run_click.png');
    }
  });

  // ── PhaseCard process names ────────────────────────────────────────────────
  test('D: PhaseCard — real process names from trace', async ({ page }) => {
    await login(page);
    // Look at the most recent running/completed workflow in Run Manager
    await page.goto(BASE_URL + '/runs', { waitUntil: 'domcontentloaded' }).catch(() => {});
    await page.waitForTimeout(1000);
    await ss(page, '09_run_manager.png');

    // Go back to main chat, find any workflow card that may be mid-run
    await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1000);

    // Check if there is any running workflow visible
    const runningBadge = page.locator('text=/RUNNING|COMPLETED|FAILED/').first();
    if (await runningBadge.isVisible({ timeout: 4000 }).catch(() => false)) {
      await runningBadge.scrollIntoViewIfNeeded();
      await ss(page, '10_phase_card_with_status.png');
    } else {
      await ss(page, '10_no_running_workflow.png');
    }

    // Also check the execution progress side panel for step cards
    const stepCard = page.locator('[data-testid^="button-run-step-"]').first();
    if (await stepCard.isVisible({ timeout: 3000 }).catch(() => false)) {
      await stepCard.scrollIntoViewIfNeeded();
      await ss(page, '11_step_run_buttons.png');
    }
  });

  // ── Chain API via browser ──────────────────────────────────────────────────
  test('E: Chain catalog API in browser', async ({ page }) => {
    // Use the frontend proxy (requires auth so test via API request directly)
    await page.goto('http://localhost:5000', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(500);

    // Call chain catalog via fetch in page context (logged in session)
    const result = await page.evaluate(async () => {
      const resp = await fetch('/api/workflow-chains', { credentials: 'include' });
      return { status: resp.status, body: await resp.json() };
    }).catch((e: any) => ({ status: 0, body: null, error: String(e) }));

    console.log(`[E] chains status=${result.status} total=${result.body?.total}`);
    result.body?.chains?.slice(0, 4).forEach((c: any) => console.log(`  ${c.name} (${c.domain}) — ${c.steps?.length} steps`));
    await ss(page, '12_chain_api_result.png');
  });

  // ── Output cards after run ─────────────────────────────────────────────────
  test('F: Output cards and View Results panel', async ({ page }) => {
    await login(page);
    await page.waitForTimeout(1000);

    // Look at any existing chat that has outputs
    const viewResultsLink = page.locator('text=/View Results/i').first();
    if (await viewResultsLink.isVisible({ timeout: 4000 }).catch(() => false)) {
      await viewResultsLink.scrollIntoViewIfNeeded();
      await viewResultsLink.click().catch(() => {});
      await page.waitForTimeout(2000);
      await ss(page, '13_view_results_panel.png');

      // Look for output file cards
      const outputCard = page.locator('[data-testid^="output-card-"]').first()
        .or(page.locator('text=/multiqc|report\\.html|\\.(tsv|csv)/i').first());
      if (await outputCard.isVisible({ timeout: 3000 }).catch(() => false)) {
        await outputCard.scrollIntoViewIfNeeded();
        await ss(page, '14_output_file_cards.png');
      } else {
        await ss(page, '14_no_output_cards_yet.png');
      }
    } else {
      await ss(page, '13_no_view_results.png');
    }
  });
});
