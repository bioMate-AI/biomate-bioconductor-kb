/**
 * Shared helpers for BioMate publication demo recordings.
 *
 * All demos use a fixed per-demo account so billing accumulates in one
 * Lago customer record and the delta is clean.  Registration is attempted
 * first; if the account already exists (repeat run), we fall back to login.
 *
 * Pacing conventions:
 *   typeMessage()   — pressSequentially with 45 ms/char, readable in video
 *   pause()         — explicit camera pause (replaces waitForTimeout calls)
 *   shot()          — named screenshot into demo-specific folder
 */

import { Page, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/**
 * Register (or login if already exists) a fixed demo account.
 * Uses in-browser fetch so httpOnly Set-Cookie lands in the browser jar.
 */
export async function setupDemoUser(
  page: Page,
  email: string,
  password = 'DemoPass123!',
  surveyDomain?: string   // e.g. "Drug Discovery", "Genomics", "Cryo-EM"
): Promise<void> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');

  // Attempt registration
  const regResult = await page.evaluate(
    async ({ baseUrl, email, password, token }: { baseUrl: string; email: string; password: string; token: string }) => {
      const r = await fetch(`${baseUrl}/api/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-E2E-Test-Token': token },
        credentials: 'include',
        body: JSON.stringify({ name: 'BioMate Demo', email, password, terms_accepted: true }),
      });
      return { ok: r.ok, status: r.status };
    },
    { baseUrl: BASE_URL, email, password, token: E2E_TOKEN }
  );

  if (!regResult.ok) {
    // Account exists — login instead
    await page.evaluate(
      async ({ baseUrl, email, password, token }: { baseUrl: string; email: string; password: string; token: string }) => {
        await fetch(`${baseUrl}/api/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-E2E-Test-Token': token },
          credentials: 'include',
          body: JSON.stringify({ email, password }),
        });
      },
      { baseUrl: BASE_URL, email, password, token: E2E_TOKEN }
    );
  }

  // Reload so auth-context reads /api/auth/me
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');

  // Suppress the post-run feedback survey for 7 days so it doesn't cover workflow results
  await page.evaluate(() => {
    try {
      localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 24 * 60 * 60 * 1000));
    } catch { /* ignore */ }
  });

  // Wait for authenticated chat UI
  await page.locator('[data-testid="chat-input"], textarea').first()
    .isVisible({ timeout: 15_000 })
    .catch(() => null);
  await pause(page, 800);

  // Dismiss onboarding domain-selection survey if present
  await dismissSurvey(page, surveyDomain);

  // Always start a fresh chat so prior session results don't appear on screen
  // while the demo is typing the first query.
  const newChatBtn = page.locator('button', { hasText: /new chat/i }).first();
  if (await newChatBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await newChatBtn.click();
    await pause(page, 1_000);
  }
}

/**
 * Dismiss the onboarding survey (may be multi-step).
 * Step 1: domain grid ("What would you like to analyze?")
 *   – optionally clicks the domain tile that matches `domain`
 *   – then clicks Continue / Next / Skip
 * Step 2+: sub-topic pages ("Which topics interest you?" / "Next — Enter BioMate")
 *   – clicks Next / Continue / Skip on each remaining step
 *
 * Loops up to 5 times to handle multi-step surveys.
 */
export async function dismissSurvey(page: Page, domain?: string): Promise<void> {
  for (let step = 0; step < 5; step++) {
    // Survey is gone when the textarea input is directly usable (no overlay)
    const surveyGone = !(
      await page.locator('text=What would you like to analyze?').isVisible({ timeout: 800 }).catch(() => false) ||
      await page.locator('text=Which topics interest you?').isVisible({ timeout: 800 }).catch(() => false) ||
      await page.locator('text=Enter BioMate').isVisible({ timeout: 800 }).catch(() => false)
    );
    if (surveyGone) break;

    // On first step, click the domain tile if requested
    if (step === 0 && domain) {
      const tile = page.locator(`text=${domain}`).first();
      if (await tile.isVisible({ timeout: 1_500 }).catch(() => false)) {
        await tile.click();
        await pause(page, 500);
      }
    }

    // Find and click the advance button (any variant) — must be enabled
    let clicked = false;
    for (const pattern of [/next.*enter biomate/i, /enter biomate/i, /next/i, /skip/i, /continue/i]) {
      const btn = page.getByRole('button', { name: pattern }).first();
      const visible = await btn.isVisible({ timeout: 800 }).catch(() => false);
      if (!visible) continue;
      const enabled = await btn.isEnabled({ timeout: 500 }).catch(() => false);
      if (!enabled) continue;
      await btn.click();
      clicked = true;
      await pause(page, 700);
      break;
    }
    if (!clicked) break; // no enabled button found — survey gone or unrecognised
  }

  await pause(page, 500);
}

// ---------------------------------------------------------------------------
// Chat / pacing
// ---------------------------------------------------------------------------

/**
 * Wait until there are no active runs.  Polls phase-card data-status attributes
 * inside the workflow panel — does NOT reference the removed active-runs-status-bar.
 */
export async function waitForNoActiveRuns(page: Page, timeoutMs = 1_200_000): Promise<void> {
  console.log('[demo] Waiting for all active runs to complete...');
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await pause(page, 8_000);
    const allIdle = await page.evaluate(() => {
      const panel = document.querySelector('[data-testid="workflow-panel"], [data-testid="nextflow-workflow-viewer"]');
      if (!panel) return true; // no panel = nothing running
      const phaseCards = panel.querySelectorAll('[data-testid^="phase-card-"]');
      if (phaseCards.length === 0) return true;
      return !Array.from(phaseCards).some(el =>
        ['running', 'queued'].includes((el as HTMLElement).dataset.status ?? '')
      );
    }).catch(() => true);
    if (allIdle) {
      console.log('[demo] All runs idle (no running/queued phase cards)');
      break;
    }
  }
  await pause(page, 2_000);
}

/**
 * Type a chat message for demo video recording.
 * Short messages (≤120 chars): typed character-by-character at 45 ms/char so
 * viewers can read the query forming naturally.
 * Long messages (>120 chars, e.g. SMILES batches): pasted instantly then held
 * on screen for 3 s — mimics a researcher copy-pasting from a database.
 */
export async function typeMessage(page: Page, message: string): Promise<void> {
  const input = page.locator('textarea').first();
  await expect(input).toBeVisible({ timeout: 15_000 });
  await input.click();
  await pause(page, 400);
  if (message.length <= 120) {
    await input.pressSequentially(message, { delay: 45 });
  } else {
    // Paste instantly — SMILES strings are always copy-pasted in practice
    await input.fill(message);
    await pause(page, 3_000); // let viewers read the pasted content
  }
  await pause(page, 600);
}

/** Submit the current message (Enter key). */
export async function submitMessage(page: Page): Promise<void> {
  await page.locator('textarea').first().press('Enter');
}

/** Explicit camera pause — lets the viewer read the screen. */
export async function pause(page: Page, ms: number): Promise<void> {
  await page.waitForTimeout(ms);
}

/** Named screenshot saved to e2e/screenshots/<dir>/. */
export async function shot(page: Page, dir: string, name: string): Promise<void> {
  const folder = path.join(__dirname, 'screenshots', dir);
  fs.mkdirSync(folder, { recursive: true });
  await page.screenshot({
    path: path.join(folder, `${name}.png`),
    fullPage: false,
  });
  console.log(`[Screenshot] ${dir}/${name}.png`);
}

// ---------------------------------------------------------------------------
// Workflow interaction
// ---------------------------------------------------------------------------

const RUN_BTN =
  '[data-testid="button-run-workflow-panel"],' +
  '[data-testid="button-confirm-and-run"],' +
  '[data-testid="pipeline-confirm-run"],' +
  '[data-testid="button-prereq-recovery"]';

/**
 * Click Run button and return immediately after the execute POST fires.
 * Does NOT wait for AWS Batch completion. Use this when the demo only needs
 * to show the "submitted, in flight" state — not the full ~3min cloud wait.
 *
 * Returns the run_id from the execute response (or null if not captured).
 */
export async function clickRunOnly(page: Page): Promise<string | null> {
  let runId: string | null = null;
  const handler = async (resp: import('@playwright/test').Response) => {
    const url = resp.url();
    if (!url.includes('/api/workflows/execute') && !url.includes('/api/nextflow/execute')) return;
    try {
      const p = await resp.json();
      runId = p?.runId || p?.run_id || p?.execution?.run?.id ||
              p?.execution?.runId || p?.galaxyInvocationId || runId;
    } catch { /* ignore */ }
  };
  page.on('response', handler);

  const btn = page.locator(RUN_BTN).first();
  await btn.waitFor({ state: 'visible', timeout: 30_000 }).catch(() => null);
  if (await btn.isVisible().catch(() => false)) {
    await btn.click({ trial: false }).catch(() => null);
  }
  // Wait briefly for the POST to fly, then return
  await page.waitForTimeout(3000);
  page.off('response', handler);
  return runId;
}

const THINKING = [
  "[data-testid='chat-response-pending']",
  "[data-testid='chat-analysis-status']",
  "text=BioMate is thinking",
  "text=Analyzing request",
];

/**
 * Send a message and wait for the AI to finish (thinking indicators gone,
 * assistant message has real content).
 * Returns true if a workflow Run button appeared.
 */
export async function sendAndWait(
  page: Page,
  message: string,
  timeoutMs = 180_000
): Promise<boolean> {
  await typeMessage(page, message);
  await submitMessage(page);

  // Wait for thinking to start
  await Promise.race(
    THINKING.map(s => page.waitForSelector(s, { state: 'visible', timeout: 30_000 }).catch(() => null))
  );
  await pause(page, 500);

  // Wait for thinking to finish
  await Promise.all(
    THINKING.map(s => page.waitForSelector(s, { state: 'hidden', timeout: timeoutMs }).catch(() => null))
  );

  // Wait for real content
  await page.waitForFunction(
    () => {
      const el = document.querySelector('[data-is-latest-assistant="true"]');
      if (!el) return false;
      const t = el.textContent ?? '';
      return t.trim().length > 30 && !t.includes('BioMate is thinking');
    },
    { timeout: timeoutMs }
  ).catch(() => {});

  await pause(page, 1200);

  return page.locator(RUN_BTN).first().isVisible({ timeout: 5_000 }).catch(() => false);
}

/**
 * Click the Run (or Confirm & Run) button, capture the runId from the
 * execute response, then poll until terminal status or timeout.
 * Returns the runId string or null.
 */
export async function clickRunAndWait(
  page: Page,
  pollTimeoutMs = 1_200_000
): Promise<string | null> {
  let runId: string | null = null;

  const handler = async (resp: import('@playwright/test').Response) => {
    const url = resp.url();
    if (!url.includes('/api/workflows/execute') && !url.includes('/api/nextflow/execute')) return;
    try {
      const p = await resp.json();
      runId = p?.runId || p?.execution?.run?.id || p?.execution?.runId || p?.galaxyInvocationId || runId;
      console.log('[demo] execute response — runId:', runId, 'status:', resp.status());
    } catch { /* ignore */ }
  };
  page.on('response', handler);

  // If another run is already active (button disabled), wait for it to finish first.
  // This prevents false "No button found" errors when an old run from a prior test attempt
  // is still in progress on AWS Batch with the same demo account.
  const initiallyDisabled = await page.evaluate((sel: string) => {
    const btn = document.querySelector(sel) as HTMLButtonElement | null;
    return btn ? btn.disabled : false;
  }, RUN_BTN).catch(() => false);

  if (initiallyDisabled) {
    console.log('[demo] Run button disabled — waiting for previous active run to complete...');
    await waitForNoActiveRuns(page, pollTimeoutMs);
    console.log('[demo] Previous run cleared — now clicking Run');
  }

  // Wait for run button to be enabled (validation can take a few seconds)
  await page.waitForFunction(
    (sel: string) => {
      const btn = document.querySelector(sel) as HTMLButtonElement | null;
      return btn && !btn.disabled;
    },
    RUN_BTN,
    { timeout: 30_000 }
  ).catch(() => null);

  // Click the first enabled run button
  const btn = page.locator(RUN_BTN).first();
  if (await btn.isEnabled({ timeout: 5_000 }).catch(() => false)) {
    await btn.click();
  } else {
    console.warn('[demo] No enabled run button found — workflow may have already started');
  }

  console.log('[demo] Workflow submitted — polling for completion...');

  // Poll for terminal status using execution-specific UI elements only.
  // Scanning body.textContent gives false positives from sidebar chat history.
  const deadline = Date.now() + pollTimeoutMs;
  while (Date.now() < deadline) {
    await pause(page, 5_000);

    const isTerminal = await page.evaluate(() => {
      // Prefer the right-side Workflow Panel which shows the CURRENT run's status.
      // Avoid checking the full document for [data-status] — old runs leave stale
      // phase cards that trigger false positives.

      // 1. Right-panel overall status badge (most reliable)
      const overallBadge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
      if (overallBadge) {
        const s = (overallBadge as HTMLElement).dataset.status ?? overallBadge.textContent ?? '';
        if (/completed|failed|errored/i.test(s)) return true;
      }

      // 2. Phase cards INSIDE the workflow viewer / workflow panel only
      const panel = document.querySelector('[data-testid="workflow-panel"], [data-testid="nextflow-workflow-viewer"]');
      if (panel) {
        // All phase cards inside the panel
        const allPhase = panel.querySelectorAll('[data-testid^="phase-card-"]');
        if (allPhase.length > 0) {
          // Only count as terminal if every phase card is non-running
          const hasRunning = Array.from(allPhase).some(el =>
            (el as HTMLElement).dataset.status === 'running' || (el as HTMLElement).dataset.status === 'queued'
          );
          const anyTerminal = Array.from(allPhase).some(el =>
            /completed|failed|errored/.test((el as HTMLElement).dataset.status ?? '')
          );
          if (anyTerminal && !hasRunning) return true;
        }
      }

      return false;
    }).catch(() => false);

    if (isTerminal) {
      console.log('[demo] Terminal status detected in execution UI');
      break;
    }

  }

  page.removeListener('response', handler);

  // Dismiss the post-run Quick Feedback survey if it appeared
  const notNowBtn = page.locator('[data-testid="survey-not-now"]').first();
  if (await notNowBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
    await notNowBtn.click();
    await pause(page, 500);
    console.log('[demo] Dismissed Quick Feedback survey');
  }

  await pause(page, 2_000);
  return runId;
}

// ---------------------------------------------------------------------------
// Billing
// ---------------------------------------------------------------------------

export interface BillingSnap {
  ts: string;
  llm_cost_usd: number;
  compute_cost_usd: number;
  total_usd: number;
  llm_tokens: number;
  error?: string;
}

/** Capture a billing snapshot via in-browser fetch. */
export async function captureBilling(page: Page, label: string): Promise<BillingSnap> {
  const ts = new Date().toISOString();
  const result = await page.evaluate(
    async ({ url, token }: { url: string; token: string }) => {
      try {
        const r = await fetch(`${url}/api/billing/usage`, {
          headers: { 'X-E2E-Test-Token': token },
          credentials: 'include',
        });
        if (!r.ok) return { ok: false, status: r.status };
        return { ok: true, data: await r.json() };
      } catch (e: any) {
        return { ok: false, error: String(e) };
      }
    },
    { url: BASE_URL, token: E2E_TOKEN }
  );

  if (!result.ok || !result.data) {
    console.log(`[Billing:${label}] unavailable — ${result.error ?? `status ${result.status}`}`);
    return { ts, llm_cost_usd: 0, compute_cost_usd: 0, total_usd: 0, llm_tokens: 0, error: 'unavailable' };
  }

  const d = result.data ?? {};
  const llm     = d.breakdown?.llm     ?? {};
  const compute = d.breakdown?.compute ?? {};
  const snap: BillingSnap = {
    ts,
    llm_cost_usd:     llm.total_usd     ?? d.llm_cost_usd     ?? 0,
    compute_cost_usd: compute.total_usd ?? d.compute_cost_usd ?? 0,
    total_usd:        d.total_usd       ?? 0,
    llm_tokens:       (llm.input_tokens ?? 0) + (llm.output_tokens ?? 0),
  };
  console.log(
    `[Billing:${label}] llm=$${snap.llm_cost_usd.toFixed(4)} ` +
    `compute=$${snap.compute_cost_usd.toFixed(4)} total=$${snap.total_usd.toFixed(4)}`
  );
  return snap;
}

/** Wait 12 s for async billing events to land, then capture. */
export async function captureBillingAfter(page: Page, label: string): Promise<BillingSnap> {
  console.log('[Billing] Waiting 12 s for async events to land...');
  await pause(page, 12_000);
  return captureBilling(page, label);
}

export function billingDelta(before: BillingSnap, after: BillingSnap) {
  return {
    llm_cost_usd:     Math.max(0, after.llm_cost_usd     - before.llm_cost_usd),
    compute_cost_usd: Math.max(0, after.compute_cost_usd - before.compute_cost_usd),
    total_usd:        Math.max(0, after.total_usd         - before.total_usd),
    llm_tokens:       Math.max(0, after.llm_tokens        - before.llm_tokens),
  };
}

/** Log billing delta to console (written into video as test log). */
export function logBillingDelta(label: string, delta: ReturnType<typeof billingDelta>) {
  console.log(
    `[Billing:${label}] delta — ` +
    `llm=$${delta.llm_cost_usd.toFixed(4)} (${delta.llm_tokens} tokens) ` +
    `compute=$${delta.compute_cost_usd.toFixed(4)} ` +
    `total=$${delta.total_usd.toFixed(4)}`
  );
}

// ---------------------------------------------------------------------------
// Tutorial helpers
// ---------------------------------------------------------------------------

/** Show a tutorial tip bubble via window.__biomate_tip (no-op if not available). */
export async function tip(page: Page, text: string, durationMs = 4000): Promise<void> {
  await page.evaluate(({ t, d }) => {
    (window as any).__biomate_tip?.(t, d);
  }, { t: text, d: durationMs }).catch(() => null);
}

/**
 * Tutorial traversal: hover key buttons to show tooltips, expand every phase card,
 * click View Results, click Analyze Results, hover Download buttons.
 * Call this after clickRunAndWait() completes.
 */
export async function exploreTutorial(page: Page, tipFn: (text: string, ms?: number) => Promise<void>): Promise<void> {
  await tipFn('Workflow complete! Let\'s explore the results.', 3000);
  await pause(page, 3_000);

  // 1. Show Phase Cards — expand each one to see step outputs
  const phaseCards = page.locator('[data-testid^="phase-card-"]');
  const count = await phaseCards.count().catch(() => 0);
  if (count > 0) {
    await tipFn(`${count} pipeline steps completed — exploring each step's outputs`, 4000);
    await pause(page, 2_000);
    for (let i = 0; i < Math.min(count, 6); i++) {
      const card = phaseCards.nth(i);
      if (await card.isVisible().catch(() => false)) {
        await card.scrollIntoViewIfNeeded().catch(() => null);
        await pause(page, 800);
        // Try to click the params/expand button for this step
        const cardId = await card.getAttribute('data-testid').catch(() => '');
        const stepId = cardId?.replace('phase-card-', '') ?? '';
        const paramsBtn = page.locator(`[data-testid="button-params-step-${stepId}"]`);
        if (await paramsBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await paramsBtn.click();
          await pause(page, 1_500);
          // click again to close
          await paramsBtn.click().catch(() => null);
          await pause(page, 500);
        }
        // Preview first output file if any
        const previewBtn = card.locator('[data-testid^="phase-card-preview-btn-"]').first();
        if (await previewBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await previewBtn.hover();
          await pause(page, 800);
          await previewBtn.click().catch(() => null);
          await pause(page, 2_000);
          // Close preview (press Escape)
          await page.keyboard.press('Escape');
          await pause(page, 500);
        }
      }
    }
  }

  // 2. View Results (output file list)
  const viewResultsBtn = page.locator('button:has-text("View Results")').first();
  if (await viewResultsBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await tipFn('View Results shows all output files from this run', 3000);
    await viewResultsBtn.hover();
    await pause(page, 1_500);
    await viewResultsBtn.click();
    await pause(page, 3_000);
  }

  // 3. Analyze Results (AI findings with citations)
  const analyzeBtn = page.locator('[data-testid="button-analyze-results"]').first();
  if (await analyzeBtn.isEnabled({ timeout: 3000 }).catch(() => false)) {
    await tipFn('Analyze Results — AI reads every output file and generates scientific findings', 4000);
    await analyzeBtn.hover();
    await pause(page, 1_500);
    await analyzeBtn.click();
    // Wait for analysis to load (up to 60s)
    await page.waitForFunction(
      () => !document.querySelector('[data-testid="button-analyze-results"]')?.textContent?.includes('Analyzing'),
      { timeout: 60_000 }
    ).catch(() => null);
    await pause(page, 4_000);
  }

  // 4. Hover Download Methods Report
  const methodsBtn = page.locator('[data-testid="button-download-methods-report"]').first();
  if (await methodsBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
    await tipFn('Download Methods Report — publication-ready Methods section auto-generated', 3500);
    await methodsBtn.hover();
    await pause(page, 2_500);
  }

  // 5. Hover Download All
  const downloadAllBtn = page.locator('[data-testid="button-download-all-workflow-panel"]').first();
  if (await downloadAllBtn.isVisible({ timeout: 2000 }).catch(() => false)) {
    await tipFn('Download All — get every output file in one ZIP', 3000);
    await downloadAllBtn.hover();
    await pause(page, 2_000);
  }
}
