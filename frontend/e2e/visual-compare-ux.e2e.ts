/**
 * Visual UX Comparison — Reference Design vs Real BioMate
 * Captures screenshots of the Claude reference design and real BioMate at
 * matching states for side-by-side audit.
 *
 * Part 1: Reference design — all 4 scenarios × idle/running/completed/failed
 * Part 2: Real BioMate — idle param form for each scenario type
 * Part 3: Real BioMate — ADMET run to completion (running → completed)
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { loadRef, switchTweaks } from './demo-ref-helpers.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
const OUT = path.join(__dirname, 'screenshots', 'visual-compare');
fs.mkdirSync(OUT, { recursive: true });

function ss(page: Page, name: string) {
  const file = path.join(OUT, `${name}.png`);
  return page.screenshot({ path: file, fullPage: false }).then(() => {
    console.log(`[screenshot] ${name}.png`);
    return file;
  });
}

// ── Reference design helpers ─────────────────────────────────────────────────

const REF_SCENARIOS = ['nfcore', 'gatk', 'cryosparc', 'admet'] as const;
const REF_STATES = ['idle', 'running', 'completed', 'failed'] as const;

// ── BioMate auth helpers ─────────────────────────────────────────────────────

async function bioLogin(page: Page): Promise<void> {
  const email = `compare_ux_${Date.now()}@biomate.test`;
  await page.setExtraHTTPHeaders({ 'x-e2e-test-token': E2E_TOKEN });
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`, { waitUntil: 'domcontentloaded' });
  await page.evaluate(() => { try { localStorage.clear(); } catch {} });

  try {
    await page.waitForSelector('#name', { state: 'visible', timeout: 12_000 });
    await page.fill('#name', 'Compare UX User');
    await page.fill('#email', email);
    await page.fill('#password', 'TestPass123!');
    await page.fill('#confirmPassword', 'TestPass123!');
    await page.click('#terms');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch {}

  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });

  // Dismiss survey
  const skip = page.locator('button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later")').first();
  if (await skip.isVisible({ timeout: 3000 }).catch(() => false)) {
    await skip.click({ force: true });
    await page.waitForTimeout(500);
  }
  await page.waitForSelector('textarea', { state: 'visible', timeout: 20_000 });
  await page.waitForTimeout(800);
  console.log(`[auth] Logged in as ${email}`);
}

async function sendMsg(page: Page, msg: string, waitMs = 90_000): Promise<void> {
  const ta = page.locator('textarea').first();
  await ta.waitFor({ state: 'visible', timeout: 10_000 });
  await ta.fill(msg);
  await ta.press('Enter');

  // Wait for response to arrive (look for workflow panel or new assistant message)
  await page.waitForFunction(() => {
    return !!(
      document.querySelector('[data-testid="nextflow-workflow-viewer"]') ||
      document.querySelector('[data-tour="panel-header"]') ||
      document.querySelector('.wf-panel')
    );
  }, { timeout: waitMs }).catch(() => {});
  await page.waitForTimeout(2000);
}

async function waitForPanel(page: Page, ms = 30_000): Promise<boolean> {
  try {
    await page.waitForSelector('[data-tour="panel-header"], .wf-panel, [data-testid="nextflow-workflow-viewer"]',
      { state: 'visible', timeout: ms });
    await page.waitForTimeout(1500);
    return true;
  } catch {
    return false;
  }
}

async function newChat(page: Page): Promise<void> {
  const btn = page.getByRole('button', { name: /new chat/i });
  if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await btn.click();
    await page.waitForTimeout(800);
  }
}

async function openPanel(page: Page): Promise<void> {
  // Panel may open automatically; also try clicking workflow card "View Details" or "Open Panel"
  const detailsBtn = page.locator('[data-testid="button-open-workflow-panel"], [data-testid="button-view-workflow"], button:has-text("View Details"), button:has-text("Open Panel")').first();
  if (await detailsBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await detailsBtn.click();
    await page.waitForTimeout(1000);
  }
  // If panel is already open via auto-open, nothing to do
  await page.waitForTimeout(500);
}

// ── PART 1: Reference design screenshots ─────────────────────────────────────

test.describe('Part 1 — Reference Design Screenshots', () => {
  test.setTimeout(480_000);

  test('REF-1: all 4 scenarios × 4 states', async ({ page }) => {
    for (const scenario of REF_SCENARIOS) {
      for (const runState of REF_STATES) {
        // qcHalt only applies when running; skip for other states
        const extras: Record<string, unknown> = {};
        if (runState === 'running') extras.speed = 900;

        await loadRef(page, { scenario, runState, ...extras });
        await ss(page, `ref_${scenario}_${runState}`);

        // Also capture panel-only crop by extracting the .wf-panel bounding box
        const panelBox = await page.locator('.wf-panel').boundingBox().catch(() => null);
        if (panelBox) {
          await page.screenshot({
            path: path.join(OUT, `ref_${scenario}_${runState}_panel.png`),
            clip: {
              x: panelBox.x,
              y: panelBox.y,
              width: Math.min(panelBox.width, 560),
              height: Math.min(panelBox.height, 800),
            },
          });
          console.log(`[screenshot] ref_${scenario}_${runState}_panel.png`);
        }

        await page.waitForTimeout(500);
      }
    }

    // Also capture qcHalt (nfcore running)
    await loadRef(page, { scenario: 'nfcore', runState: 'running', qcHalt: true });
    await ss(page, 'ref_nfcore_qcHalt');

    // Blocked + licenseGate
    await loadRef(page, { scenario: 'nfcore', runState: 'idle', blocked: true, licenseGate: true });
    await ss(page, 'ref_nfcore_blocked_license');

    // Disambiguation
    await loadRef(page, { scenario: 'nfcore', runState: 'idle', disambig: true });
    await ss(page, 'ref_disambiguation');

    console.log('[REF-1] ✅ All reference screenshots done');
  });
});

// ── PART 2: Real BioMate — idle state per scenario ───────────────────────────

const SCENARIO_QUERIES: Record<string, string> = {
  nfcore: 'I need to run nf-core fastp quality control on FASTQ sequencing files',
  gatk:   'Run GATK germline variant calling pipeline for whole-genome sequencing',
  cryosparc: 'Run CryoSPARC single-particle analysis pipeline for cryo-EM data',
  admet:  'Run ADMET toxicity and pharmacokinetics screening for aspirin. SMILES: CC(=O)Oc1ccccc1C(=O)O',
};

test.describe('Part 2 — Real BioMate Idle State', () => {
  test.setTimeout(300_000);

  for (const scenario of ['nfcore', 'gatk', 'cryosparc', 'admet'] as const) {
    test(`REAL-idle-${scenario}`, async ({ page }) => {
      await bioLogin(page);
      await newChat(page);

      console.log(`[${scenario}] Sending chat query...`);
      const ta = page.locator('textarea').first();
      await ta.fill(SCENARIO_QUERIES[scenario]);
      await ta.press('Enter');

      // Wait for AI response + workflow panel
      await page.waitForTimeout(3000);
      await ss(page, `real_${scenario}_query_sent`);

      // Wait for workflow panel or workflow card
      const panelVisible = await page.waitForSelector(
        '[data-tour="panel-header"], .wf-panel, [data-testid="nextflow-workflow-viewer"], [data-testid^="workflow-artifact-anchor"]',
        { state: 'visible', timeout: 90_000 }
      ).then(() => true).catch(() => false);

      await page.waitForTimeout(2000);
      await ss(page, `real_${scenario}_ai_response`);

      if (!panelVisible) {
        console.log(`[${scenario}] WARNING: Panel not visible after 90s`);
        return;
      }

      // Open panel if not already open
      await openPanel(page);
      await page.waitForTimeout(3000); // allow lazy-steps fetch to complete

      const panelOpen = await page.locator('[data-tour="panel-header"]').isVisible({ timeout: 5000 }).catch(() => false);
      if (!panelOpen) {
        // Try clicking the workflow card button
        const runBtn = page.locator('[data-testid="button-run-workflow-panel"], [data-testid="button-confirm-run"]').first();
        if (await runBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
          await ss(page, `real_${scenario}_run_btn_visible`);
        }
      }

      await ss(page, `real_${scenario}_idle`);

      // Crop to panel if visible
      const panelEl = page.locator('[data-tour="panel-header"]').first();
      const panelBox = await panelEl.boundingBox().catch(() => null);
      if (panelBox) {
        // Expand crop to include the full panel
        await page.screenshot({
          path: path.join(OUT, `real_${scenario}_idle_panel.png`),
          clip: {
            x: Math.max(0, panelBox.x - 10),
            y: Math.max(0, panelBox.y - 10),
            width: Math.min(600, 1920 - panelBox.x),
            height: Math.min(900, 1080 - panelBox.y),
          },
        });
        console.log(`[screenshot] real_${scenario}_idle_panel.png`);
      }

      console.log(`[REAL-idle-${scenario}] ✅ Done`);
    });
  }
});

// ── PART 3: Real BioMate — ADMET running → completed ─────────────────────────

test.describe('Part 3 — Real BioMate ADMET Run Lifecycle', () => {
  test.setTimeout(600_000);

  test('REAL-admet-lifecycle', async ({ page }) => {
    await bioLogin(page);
    await newChat(page);

    // Trigger ADMET workflow
    const ta = page.locator('textarea').first();
    await ta.fill(SCENARIO_QUERIES.admet);
    await ta.press('Enter');

    await page.waitForSelector('[data-tour="panel-header"], .wf-panel, [data-testid^="workflow-artifact-anchor"]',
      { state: 'visible', timeout: 90_000 }).catch(() => {});
    await page.waitForTimeout(2000);
    await ss(page, 'real_admet_idle_before_run');

    // Open panel to see full idle state
    await openPanel(page);
    await page.waitForTimeout(1000);
    await ss(page, 'real_admet_panel_idle');

    // Click Confirm & Run
    const runBtn = page.locator(
      '[data-testid="button-confirm-run"], [data-testid="button-run-workflow-panel"], button:has-text("Confirm & Run"), button:has-text("Run Workflow")'
    ).first();

    if (!(await runBtn.isVisible({ timeout: 8000 }).catch(() => false))) {
      console.log('[ADMET] Run button not visible — skipping execution phase');
      return;
    }

    console.log('[ADMET] Clicking run...');
    await runBtn.click();
    await page.waitForTimeout(3000);
    await ss(page, 'real_admet_just_started');

    // Wait for RUNNING status
    const runningBadge = page.locator('[data-testid="workflow-overall-status-badge"]:has-text("RUNNING"), [class*="chip run"]:has-text("RUNNING"), .chip.run:has-text("RUNNING")');
    await runningBadge.waitFor({ state: 'visible', timeout: 60_000 }).catch(() => {});
    await ss(page, 'real_admet_running');

    // Crop running panel
    const panelEl = page.locator('[data-tour="panel-header"]').first();
    const runningBox = await panelEl.boundingBox().catch(() => null);
    if (runningBox) {
      await page.screenshot({
        path: path.join(OUT, 'real_admet_running_panel.png'),
        clip: { x: Math.max(0, runningBox.x - 10), y: Math.max(0, runningBox.y - 10), width: Math.min(600, 1920), height: Math.min(900, 1080) },
      });
      console.log('[screenshot] real_admet_running_panel.png');
    }

    // Poll for terminal state
    console.log('[ADMET] Waiting for completion...');
    const start = Date.now();
    let finalStatus = 'unknown';
    while (Date.now() - start < 480_000) {
      const badge = await page.locator('[data-testid="workflow-overall-status-badge"]').textContent({ timeout: 3000 }).catch(() => '');
      const statusText = badge?.toUpperCase() || '';
      if (statusText.includes('COMPLETED') || statusText.includes('FAILED')) {
        finalStatus = statusText.includes('COMPLETED') ? 'completed' : 'failed';
        break;
      }
      // Also check chip classes
      const chipOk = await page.locator('.chip.ok').isVisible({ timeout: 1000 }).catch(() => false);
      const chipErr = await page.locator('.chip.err').isVisible({ timeout: 1000 }).catch(() => false);
      if (chipOk) { finalStatus = 'completed'; break; }
      if (chipErr) { finalStatus = 'failed'; break; }
      await page.waitForTimeout(8000);
    }

    console.log(`[ADMET] Final status: ${finalStatus}`);
    await ss(page, `real_admet_${finalStatus}`);

    // Crop final panel
    const finalEl = page.locator('[data-tour="panel-header"]').first();
    const finalBox = await finalEl.boundingBox().catch(() => null);
    if (finalBox) {
      await page.screenshot({
        path: path.join(OUT, `real_admet_${finalStatus}_panel.png`),
        clip: { x: Math.max(0, finalBox.x - 10), y: Math.max(0, finalBox.y - 10), width: Math.min(600, 1920), height: Math.min(900, 1080) },
      });
      console.log(`[screenshot] real_admet_${finalStatus}_panel.png`);
    }

    // Scroll through completed panel to capture all sections
    if (finalStatus === 'completed') {
      // metrics-strip
      const metricsEl = page.locator('.metrics-strip').first();
      if (await metricsEl.isVisible({ timeout: 3000 }).catch(() => false)) {
        await metricsEl.scrollIntoViewIfNeeded();
        await page.waitForTimeout(800);
        await ss(page, 'real_admet_completed_metrics');
      }
      // results section
      const resultsEl = page.locator('.results-links').first();
      if (await resultsEl.isVisible({ timeout: 3000 }).catch(() => false)) {
        await resultsEl.scrollIntoViewIfNeeded();
        await page.waitForTimeout(800);
        await ss(page, 'real_admet_completed_results');
      }
    }

    expect(finalStatus).toMatch(/completed|failed/);
    console.log('[REAL-admet-lifecycle] ✅ Done');
  });
});

// ── PART 4: Panel section close-ups on reference design ──────────────────────

test.describe('Part 4 — Reference Design Close-ups', () => {
  test.setTimeout(180_000);

  test('REF-closeup: panel sections per state', async ({ page }) => {
    const clips: Array<{ name: string; selector: string }> = [
      { name: 'panel-head',   selector: '[data-tour="panel-header"], .panel-head' },
      { name: 'phase-list',   selector: '[data-tour="phase-list"], .phase-list' },
      { name: 'run-footer',   selector: '[data-tour="run-footer"], .panel-foot' },
    ];

    for (const scenario of ['nfcore', 'cryosparc', 'admet'] as const) {
      for (const runState of ['idle', 'running', 'completed'] as const) {
        await loadRef(page, { scenario, runState, speed: 400 });

        for (const clip of clips) {
          const el = page.locator(clip.selector).first();
          if (!(await el.isVisible({ timeout: 3000 }).catch(() => false))) continue;
          const box = await el.boundingBox().catch(() => null);
          if (!box) continue;

          await page.screenshot({
            path: path.join(OUT, `ref_${scenario}_${runState}_${clip.name}.png`),
            clip: { x: box.x, y: box.y, width: box.width, height: Math.min(box.height, 600) },
          });
          console.log(`[screenshot] ref_${scenario}_${runState}_${clip.name}.png`);
        }
      }
    }

    // Special: running with progress bar
    await loadRef(page, { scenario: 'nfcore', runState: 'running', speed: 200 });
    await page.waitForTimeout(2000); // let progress animate
    const runBar = page.locator('.run-bar').first();
    if (await runBar.isVisible({ timeout: 3000 }).catch(() => false)) {
      const box = await runBar.boundingBox().catch(() => null);
      if (box) {
        await page.screenshot({
          path: path.join(OUT, 'ref_nfcore_running_progress_bar.png'),
          clip: { x: Math.max(0, box.x - 20), y: Math.max(0, box.y - 20), width: box.width + 40, height: box.height + 40 },
        });
        console.log('[screenshot] ref_nfcore_running_progress_bar.png');
      }
    }

    console.log('[REF-closeup] ✅ Done');
  });
});
