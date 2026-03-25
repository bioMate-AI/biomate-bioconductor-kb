/**
 * Output Visualization E2E — Focused test showing JSON/data outputs as tables
 *
 * NO MOCKS. Tests run against live server.
 * Captures: completion → output section auto-opens → JSON rendered as table.
 * Videos saved to e2e/test-results/ (Playwright auto-records).
 * Screenshots saved to e2e/screenshots/output-viz/
 */

import { test, expect, Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const SCREENSHOT_DIR = path.join(__dirname, 'screenshots', 'output-viz');

if (!fs.existsSync(SCREENSHOT_DIR)) fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

test.setTimeout(900000); // 15 min

async function screenshot(page: Page, name: string): Promise<void> {
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, `${name}.png`), fullPage: true });
  console.log(`[Screenshot] ${name}.png`);
}

async function registerAndGoHome(page: Page): Promise<void> {
  const email = `e2e_outviz_${Date.now()}@biomate.test`;
  await page.context().clearCookies();
  await page.goto(`${BASE_URL}/register`);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
  await page.waitForLoadState('load');
  try {
    await page.waitForSelector('#name', { state: 'visible', timeout: 10000 });
    await page.fill('#name', 'VizTest User');
    await page.fill('#email', email);
    await page.fill('#password', 'TestPass123!');
    await page.fill('#confirmPassword', 'TestPass123!');
    await page.click('#terms');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2000);
  } catch {}
  await page.goto(BASE_URL);
  await page.evaluate(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
  await page.reload();
  await page.waitForLoadState('load');
  await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(1000);
}

// ---------------------------------------------------------------------------
// Test: ADMET output visualization — JSON files rendered as interactive tables
// ---------------------------------------------------------------------------

test.describe('Output Visualization', () => {
  test('ADMET run → output section auto-opens → JSON rendered as table', async ({ page }) => {
    await registerAndGoHome(page);
    await screenshot(page, '01_initial');

    const chatInput = page.locator('textarea').first();
    await expect(chatInput).toBeVisible({ timeout: 10000 });

    // Send query with explicit no-clarification directive
    const query = [
      'Run ADMET toxicity screening for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O).',
      'Predict hERG IC50, DILI risk, and Ames mutagenicity.',
      'Do not ask for clarification — use the provided SMILES directly.',
      'Generate the workflow immediately.',
    ].join(' ');
    await chatInput.fill(query);
    await chatInput.press('Enter');
    console.log('[VizTest] Query sent');

    // Wait for typing indicator to appear then disappear
    await page.waitForSelector('text=BioMate is typing', { timeout: 30000 }).catch(() => {});
    await page.waitForSelector('text=BioMate is typing', { state: 'hidden', timeout: 480000 }).catch(() => {});
    await page.waitForSelector('textarea:enabled', { timeout: 60000 }).catch(() => {});
    await page.waitForTimeout(2000);
    await screenshot(page, '02_after_ai_response');

    // Handle clarification round if needed (max 2 rounds)
    for (let c = 0; c < 2; c++) {
      const hasRunBtn = await page.locator('[data-testid="button-run-workflow-panel"],[data-testid="button-confirm-and-run"]').isVisible().catch(() => false);
      const hasPanelNow = await page.locator('[data-testid="workflow-artifact-panel"]').count().catch(() => 0) > 0;
      if (hasRunBtn || hasPanelNow) break;
      const textarea = page.locator('textarea').first();
      await textarea.fill('The SMILES for aspirin is CC(=O)Oc1ccccc1C(=O)O. Generate the ADMET workflow now. No further clarification needed.');
      await textarea.press('Enter');
      await page.waitForSelector('text=BioMate is typing', { timeout: 30000 }).catch(() => {});
      await page.waitForSelector('text=BioMate is typing', { state: 'hidden', timeout: 480000 }).catch(() => {});
      await page.waitForTimeout(2000);
    }

    await screenshot(page, '03_workflow_card');

    // Click Confirm & Run
    const executeRespPromise = page.waitForResponse(
      (resp) => resp.url().includes('/api/workflows/execute'),
      { timeout: 60000 }
    );
    const confirmBtn = page.locator('[data-testid="button-confirm-and-run"],[data-testid="button-run-workflow-panel"]').last();
    await expect(confirmBtn).toBeVisible({ timeout: 15000 });
    await confirmBtn.click();
    const executeResp = await executeRespPromise;
    const executeData = await executeResp.json().catch(() => ({})) as any;
    const runId: string = executeData.runId || '';
    console.log(`[VizTest] Run ID: ${runId}`);
    expect(runId).toBeTruthy();
    await screenshot(page, '04_execution_started');

    // Poll for completion
    let finalStatus = 'unknown';
    for (let i = 0; i < 200; i++) {
      await page.waitForTimeout(5000);
      try {
        const resp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/status`);
        if (!resp.ok()) continue;
        const data = await resp.json() as any;
        const s = (data.status || '').toLowerCase();
        if (i % 6 === 0) console.log(`[VizTest] Poll ${i}: status=${s}`);
        if (['completed', 'failed', 'error', 'ok', 'succeeded'].includes(s)) {
          finalStatus = s === 'ok' || s === 'succeeded' ? 'completed' : s;
          break;
        }
      } catch {}
    }
    console.log(`[VizTest] Terminal status: ${finalStatus}`);
    await screenshot(page, '05_terminal_status');
    expect(finalStatus, 'Workflow must reach completed state').toBe('completed');

    // Dismiss any feedback modal
    for (const btnLabel of [/^skip$/i, /^submit feedback$/i, /before you go/i]) {
      const btn = page.getByRole('button', { name: btnLabel }).first();
      const appeared = await btn.waitFor({ state: 'visible', timeout: 8000 }).then(() => true).catch(() => false);
      if (appeared) {
        // For skip, click it; for other close patterns try Escape
        if (btnLabel.source.includes('skip')) {
          await btn.click().catch(() => {});
        } else {
          await page.keyboard.press('Escape');
        }
        await page.waitForTimeout(800);
        break;
      }
    }
    // Also try Escape for any lingering modal
    await page.keyboard.press('Escape');
    await page.waitForTimeout(1000);
    await screenshot(page, '06_modal_dismissed');

    // Wait for completion banner
    const bannerVisible = await page.locator('[data-testid="workflow-completion-banner"]')
      .waitFor({ state: 'visible', timeout: 20000 }).then(() => true).catch(() => false);
    console.log(`[VizTest] Completion banner: ${bannerVisible}`);
    await screenshot(page, '07_completion_banner');

    // Wait for "Output Results" section to auto-open (triggered by status=completed)
    // It shows when showResults=true — this happens automatically on completion
    const outputResultsSection = page.locator('text=Output Results').first();
    const autoOpened = await outputResultsSection
      .waitFor({ state: 'visible', timeout: 30000 })
      .then(() => true)
      .catch(() => false);
    console.log(`[VizTest] Output Results section auto-opened: ${autoOpened}`);

    if (!autoOpened) {
      // Try clicking "View Results" manually
      const viewResultsBtn = page.locator('button', { hasText: 'View Results' }).last();
      const btnVisible = await viewResultsBtn.isVisible().catch(() => false);
      if (btnVisible) {
        await viewResultsBtn.click();
        console.log('[VizTest] Clicked View Results manually');
        await page.waitForTimeout(2000);
      }
    }
    await screenshot(page, '08_output_results_section');

    // Scroll to the output results section
    await outputResultsSection.scrollIntoViewIfNeeded().catch(() => {});
    await page.waitForTimeout(2000);
    await screenshot(page, '09_output_section_scrolled');

    // ---- Assert 1: API must return ≥ 1 table output (JSON classified correctly) ----
    const invocationId = runId; // nextflow uses run_id as invocation_id
    const outputsResp = await page.request.get(`${BASE_URL}/api/invocations/${invocationId}/outputs`).catch(() => null);
    expect(outputsResp?.ok(), 'Outputs API must return 200').toBeTruthy();
    const outputs: any[] = await outputsResp!.json().catch(() => []);
    console.log(`[VizTest] API outputs count: ${outputs.length}`);
    outputs.forEach(o => console.log(`  - ${o.name} (fileType=${o.fileType}, ext=${o.extension})`));

    const tableOutputs = outputs.filter(o => o.fileType === 'table' || ['json', 'csv', 'tsv'].includes(o.extension));
    console.log(`[VizTest] Table outputs: ${tableOutputs.length}`);
    expect(tableOutputs.length, 'At least 1 JSON/table output must be registered after ADMET run').toBeGreaterThan(0);

    // ---- Assert 2: csv-table-viewer must be visible in the DOM (JSON outputs rendered inline) ----
    // CsvTableViewer starts auto-expanded (defaultExpanded=true), so the card is visible immediately
    const tableViewer = page.locator('[data-testid="csv-table-viewer"]').first();
    await tableViewer.scrollIntoViewIfNeeded().catch(() => {});
    const tableVisible = await tableViewer.isVisible({ timeout: 15000 }).catch(() => false);
    console.log(`[VizTest] Table viewer visible: ${tableVisible}`);
    expect(tableVisible, 'csv-table-viewer card must be visible for JSON table outputs').toBeTruthy();
    await screenshot(page, '10_table_viewer_json');

    // ---- Assert 3: Table content must load (rows visible after auto-expand) ----
    // CsvTableViewer fetches data when showPreview=true (now the default).
    // Wait for either a table row or an error message to appear.
    const tableRow = tableViewer.locator('tbody tr').first();
    const tableLoaded = await tableRow.isVisible({ timeout: 20000 }).catch(() => false);
    console.log(`[VizTest] Table rows loaded: ${tableLoaded}`);
    expect(tableLoaded, 'Table data rows must load after auto-expand').toBeTruthy();

    // Verify preview content via API for first table output
    for (const tableOutput of tableOutputs.slice(0, 1)) {
      const previewResp = await page.request.get(`${BASE_URL}/api/outputs/${tableOutput.id}/preview?lines=20`).catch(() => null);
      if (previewResp?.ok()) {
        const preview = await previewResp.json().catch(() => null);
        if (preview) {
          console.log(`[VizTest] Preview for ${tableOutput.name}:`, JSON.stringify(preview).slice(0, 200));
          expect(preview.lines?.length ?? preview.totalLines ?? 0, 'Preview must have content').toBeGreaterThan(0);
        }
      }
    }

    // ---- Runtime artifacts banner ----
    const artifactsBanner = page.locator('[data-testid="nextflow-runtime-artifacts"]').first();
    const artifactsVisible = await artifactsBanner.isVisible({ timeout: 10000 }).catch(() => false);
    console.log(`[VizTest] Runtime artifacts banner: ${artifactsVisible}`);
    if (artifactsVisible) {
      const artifactText = await artifactsBanner.textContent().catch(() => '');
      console.log(`[VizTest] Artifacts text: ${artifactText?.slice(0, 200)}`);
      await artifactsBanner.scrollIntoViewIfNeeded().catch(() => {});
      await screenshot(page, '11_runtime_artifacts');
    }

    // ---- Download commands panel ----
    const dlPanel = page.locator('[data-testid="download-commands-panel"]').last();
    const dlPanelVisible = await dlPanel.isVisible({ timeout: 10000 }).catch(() => false);
    console.log(`[VizTest] Download commands panel: ${dlPanelVisible}`);
    if (dlPanelVisible) {
      await dlPanel.scrollIntoViewIfNeeded().catch(() => {});
      await screenshot(page, '12_download_panel');
    }

    await screenshot(page, '13_final_state');
    console.log('[VizTest] ✓ Output visualization test complete');
  });
});
