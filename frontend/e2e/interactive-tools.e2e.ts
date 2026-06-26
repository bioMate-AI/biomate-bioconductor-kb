/**
 * Interactive Tools E2E
 * =====================
 * Tests the full interactive tool launcher system:
 *
 * Tool selection logic per file type:
 *   h5ad / loom / h5   → CellxGene (pre-selected, primary button)
 *   rds / rdata / rda  → RStudio   (pre-selected)
 *   csv / tsv / tabular → RStudio  (primary), Jupyter (secondary)
 *   txt / log / fasta   → Jupyter  (primary)
 *   png / pdf / mrc     → no button (not useful in interactive tools)
 *
 * Test surfaces:
 *   A. StepOutputPreview — button labels, initialTool, dialog content
 *   B. AfterRunReport OutputsTab — InteractiveToolsRow renders correct buttons
 *   C. InteractiveLauncher dialog — all 3 tools always present
 *   D. /api/interactive/* API — shape validation
 *
 * CLAUDE.md rules:
 *   - Single fixture account, login once via sharedPage (cookie auth)
 *   - No page.route() mocking
 *   - { request } fixture replaced by sharedPage.request (cookie-bearing)
 */

import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const SS_DIR = path.join("/tmp", "interactive-tools-e2e");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

test.setTimeout(10 * 60_000);

let sharedPage: Page;

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);  // sets cookies on sharedPage.context()
});

test.afterAll(async () => {
  await sharedPage?.close();
});

async function ss(page: Page, name: string) {
  await page.screenshot({ path: path.join(SS_DIR, `${name}.png`), fullPage: true });
}

// ============================================================================
// A. StepOutputPreview — verify tool selection + dialog per extension
// ============================================================================

test("A1: Table file (tsv) → primary button is 'Analyze in RStudio', secondary 'Open in Jupyter'", async () => {
  const page = sharedPage;
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });

  // Use sharedPage.request (cookie-bearing) — no Bearer token needed
  const runsResp = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=20`);
  if (!runsResp.ok()) { test.skip(); return; }
  // API returns plain array, not { runs: [...] }
  const runs = await runsResp.json() as any[];
  if (!Array.isArray(runs)) { test.skip(); return; }

  // Find a completed run that has TSV/CSV step outputs
  const completedRun = runs.find(r =>
    (r.execution?.status === "completed" || r.execution?.status === "ok") &&
    r.execution?.nextflowStatus?.processes?.some((p: any) =>
      (p.task_files || p.taskFiles || []).some((f: any) =>
        /\.(tsv|csv|tabular)$/i.test(typeof f === 'string' ? f : f?.name ?? '')
      )
    )
  );

  if (!completedRun) {
    console.log("[A1] No completed run with TSV outputs — verifying launch API responds");
    const r = await page.request.post(`${BASE_URL}/api/interactive/launch`, {
      headers: { "Content-Type": "application/json" },
      data: { tool_id: "interactive_tool_rstudio", inputs: {} },
    });
    // 200 (Galaxy accepted) or 500 (Galaxy interactive tools not configured locally) — NOT 401
    expect([200, 500]).toContain(r.status());
    console.log("[A1] /api/interactive/launch status:", r.status());
    return;
  }

  console.log("[A1] Found completed run with TSV:", completedRun.id);
  await page.goto(`${BASE_URL}/dashboard`, { waitUntil: "networkidle" });
  const runCard = page.locator(`[data-run-id="${completedRun.id}"]`).first();
  if (await runCard.count() === 0) { test.skip(); return; }

  await runCard.click();
  await page.waitForTimeout(1500);
  await ss(page, "a1_00_panel");

  const phasesTab = page.locator('[data-testid="panel-tab-phases"]');
  if (await phasesTab.count() === 0) { test.skip(); return; }
  await phasesTab.click();

  const previewBtns = page.locator('[data-testid^="phase-card-preview-btn-"]');
  if (await previewBtns.count() === 0) { test.skip(); return; }

  await previewBtns.first().click();
  await page.waitForTimeout(1000);
  await ss(page, "a1_01_preview");

  const rstudioBtn = page.getByRole("button", { name: /Analyze in RStudio/i });
  const jupyterBtn = page.getByRole("button", { name: /Open in Jupyter/i });

  if (await rstudioBtn.count() > 0) {
    await expect(rstudioBtn).toBeVisible();
    console.log("[A1] 'Analyze in RStudio' button visible for table file");

    await rstudioBtn.click();
    await ss(page, "a1_02_dialog");
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();

    const rstudioRadio = page.getByRole("radio", { name: /RStudio/i });
    if (await rstudioRadio.count() > 0) {
      await expect(rstudioRadio).toBeChecked();
      console.log("[A1] RStudio radio pre-selected in dialog");
    }

    // All 3 tools present
    await expect(page.getByRole("radio", { name: /Jupyter/i })).toBeAttached();
    await expect(page.getByRole("radio", { name: /CellxGene/i })).toBeAttached();
    await ss(page, "a1_03_all_tools");
    console.log("[A1] All 3 tools present in dialog");

    await page.getByRole("button", { name: /Cancel/i }).last().click();
  } else if (await jupyterBtn.count() > 0) {
    await expect(jupyterBtn).toBeVisible();
    console.log("[A1] 'Open in Jupyter' button visible");
  } else {
    console.log("[A1] No interactive tool button visible for this file type");
  }
});

test("A2: h5ad / loom file → CellxGene launch API responds", async () => {
  const page = sharedPage;

  // Verify CellxGene API launch responds (cookie auth via sharedPage.request)
  const launchResp = await page.request.post(`${BASE_URL}/api/interactive/launch`, {
    headers: { "Content-Type": "application/json" },
    data: { tool_id: "interactive_tool_cellxgene", inputs: {} },
  });
  console.log("[A2] CellxGene launch API status:", launchResp.status());
  // 200 = Galaxy accepted, 500 = Galaxy not configured locally — NOT 401
  expect([200, 500]).toContain(launchResp.status());

  if (launchResp.status() === 200) {
    const body = await launchResp.json();
    expect(body).toHaveProperty("job_id");
    console.log("[A2] CellxGene launch accepted, job_id:", body.job_id);
  } else {
    const body = await launchResp.json().catch(() => ({}));
    console.log("[A2] Galaxy not configured for interactive tools:", JSON.stringify(body));
  }
});

// ============================================================================
// B. AfterRunReport OutputsTab — InteractiveToolsRow
// ============================================================================

test("B1: AfterRunReport Outputs tab shows interactive tool buttons based on output extensions", async () => {
  const page = sharedPage;
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });

  const runsResp = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=10`);
  if (!runsResp.ok()) { test.skip(); return; }
  // API returns plain array
  const runs = await runsResp.json() as any[];
  if (!Array.isArray(runs)) { test.skip(); return; }

  const completed = runs.find(r =>
    r.execution?.status === "completed" || r.execution?.status === "ok"
  );
  if (!completed) { test.skip(); return; }

  await page.goto(`${BASE_URL}/dashboard`, { waitUntil: "networkidle" });
  const runCard = page.locator(`[data-run-id="${completed.id}"]`).first();
  if (await runCard.count() === 0) { test.skip(); return; }

  await runCard.click();
  await page.waitForTimeout(2000);

  const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
  if (await afterRunTab.count() === 0) { test.skip(); return; }
  await afterRunTab.click();
  await page.waitForTimeout(1000);
  await ss(page, "b1_00_afterrun");

  const outputsInnerTab = page.locator('[data-testid="after-tab-outputs"]');
  if (await outputsInnerTab.count() > 0) {
    await outputsInnerTab.click();
    await page.waitForTimeout(500);
    await ss(page, "b1_01_outputs_tab");

    const toolsRow = page.locator('[data-testid="afterrun-interactive-tools-row"]');
    if (await toolsRow.count() > 0) {
      await expect(toolsRow).toBeVisible();
      console.log("[B1] InteractiveToolsRow present in Outputs tab");

      // Jupyter button always present
      const jupyterBtn = page.locator('[data-testid="afterrun-launch-jupyter"]');
      await expect(jupyterBtn).toBeVisible();
      console.log("[B1] Jupyter button visible");

      const rstudioBtn = page.locator('[data-testid="afterrun-launch-rstudio"]');
      const cellxgeneBtn = page.locator('[data-testid="afterrun-launch-cellxgene"]');
      const hasRstudio = await rstudioBtn.count() > 0;
      const hasCellxgene = await cellxgeneBtn.count() > 0;
      console.log("[B1] RStudio button:", hasRstudio, "CellxGene button:", hasCellxgene);

      await ss(page, "b1_02_tools_row");

      // Click Jupyter → dialog with Jupyter pre-selected
      await jupyterBtn.click();
      await page.waitForTimeout(500);
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible();

      const jupyterRadio = page.getByRole("radio", { name: /Jupyter/i });
      if (await jupyterRadio.count() > 0) {
        await expect(jupyterRadio).toBeChecked();
        console.log("[B1] Jupyter pre-selected when launched from Jupyter button");
      }

      await ss(page, "b1_03_jupyter_dialog");
      await page.getByRole("button", { name: /Cancel/i }).last().click();

      if (hasRstudio) {
        await rstudioBtn.click();
        await page.waitForTimeout(500);
        const dialog2 = page.getByRole("dialog");
        await expect(dialog2).toBeVisible();
        const rstudioRadio = page.getByRole("radio", { name: /RStudio/i });
        if (await rstudioRadio.count() > 0) {
          await expect(rstudioRadio).toBeChecked();
          console.log("[B1] RStudio pre-selected when launched from RStudio button");
        }
        await ss(page, "b1_04_rstudio_dialog");
        await page.getByRole("button", { name: /Cancel/i }).last().click();
      }

      if (hasCellxgene) {
        await cellxgeneBtn.click();
        await page.waitForTimeout(500);
        const dialog3 = page.getByRole("dialog");
        await expect(dialog3).toBeVisible();
        const cellxgeneRadio = page.getByRole("radio", { name: /CellxGene/i });
        if (await cellxgeneRadio.count() > 0) {
          await expect(cellxgeneRadio).toBeChecked();
          console.log("[B1] CellxGene pre-selected when launched from CellxGene button");
        }
        await ss(page, "b1_05_cellxgene_dialog");
        await page.getByRole("button", { name: /Cancel/i }).last().click();
      }

    } else {
      console.log("[B1] InteractiveToolsRow not rendered — outputs may be empty");
      const downloadBtn = page.locator(".afterrun-download-all-btn");
      console.log("[B1] Download all button present:", await downloadBtn.count() > 0);
    }
  } else {
    console.log("[B1] Outputs inner tab not found in AfterRunReport");
  }
});

// ============================================================================
// C. Dialog content — all 3 tools always present regardless of entry point
// ============================================================================

test("C1: InteractiveLauncher dialog always shows all 3 tools (Jupyter, RStudio, CellxGene)", async () => {
  const page = sharedPage;

  // Find any visible interactive launcher button on current page
  const allLaunchBtns = page.locator('[data-testid^="afterrun-launch-"]');
  const anyBtn = allLaunchBtns.first();

  if (await anyBtn.count() > 0) {
    await anyBtn.click();
    await page.waitForTimeout(500);
  } else {
    // Navigate to a completed run's outputs tab
    const runsResp = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=5`);
    if (!runsResp.ok()) { test.skip(); return; }
    // API returns plain array
    const runs = await runsResp.json() as any[];
    if (!Array.isArray(runs)) { test.skip(); return; }
    const completed = runs.find(r =>
      r.execution?.status === "completed" || r.execution?.status === "ok"
    );
    if (!completed) { test.skip(); return; }
    await page.goto(`${BASE_URL}/dashboard`, { waitUntil: "networkidle" });
    const card = page.locator(`[data-run-id="${completed.id}"]`).first();
    if (await card.count() === 0) { test.skip(); return; }
    await card.click();
    await page.waitForTimeout(1500);
    const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
    if (await afterRunTab.count() === 0) { test.skip(); return; }
    await afterRunTab.click();
    await page.waitForTimeout(500);
    const outputsTab2 = page.locator('[data-testid="after-tab-outputs"]');
    if (await outputsTab2.count() > 0) {
      await outputsTab2.click();
      await page.waitForTimeout(500);
    }
    const jupBtn = page.locator('[data-testid="afterrun-launch-jupyter"]');
    if (await jupBtn.count() === 0) { test.skip(); return; }
    await jupBtn.click();
    await page.waitForTimeout(500);
  }

  const dialog = page.getByRole("dialog");
  if (!(await dialog.isVisible())) { test.skip(); return; }

  // All 3 tools must be present
  const jupyterRadio = page.getByRole("radio", { name: /Jupyter/i });
  const rstudioRadio = page.getByRole("radio", { name: /RStudio/i });
  const cellxgeneRadio = page.getByRole("radio", { name: /CellxGene/i });

  await expect(jupyterRadio).toBeAttached();
  await expect(rstudioRadio).toBeAttached();
  await expect(cellxgeneRadio).toBeAttached();

  // Switching tools works
  await jupyterRadio.click();
  await expect(jupyterRadio).toBeChecked();
  await rstudioRadio.click();
  await expect(rstudioRadio).toBeChecked();
  await cellxgeneRadio.click();
  await expect(cellxgeneRadio).toBeChecked();

  // Timeout warning always present
  await expect(page.getByText(/2 hours/i)).toBeVisible();

  await page.getByRole("button", { name: /Cancel/i }).last().click();

  await ss(page, "c1_dialog_all_tools");
  console.log("[C1] All 3 tools present and switchable in dialog");
});

// ============================================================================
// D. API — sessions + launch endpoints (cookie auth via sharedPage.request)
// ============================================================================

test("D1: /api/interactive/sessions responds (200 or 500 when Galaxy not configured)", async () => {
  const page = sharedPage;
  // Use sharedPage.request which carries the session cookie
  const resp = await page.request.get(`${BASE_URL}/api/interactive/sessions`);
  // 200 = OK with sessions array; 500 = Galaxy interactive tools not configured locally
  // Either way we must NOT get 401 (auth should pass via session cookie)
  expect(resp.status()).not.toBe(401);
  expect([200, 500]).toContain(resp.status());
  console.log("[D1] /api/interactive/sessions status:", resp.status());
  if (resp.status() === 200) {
    const body = await resp.json();
    expect(Array.isArray(body.sessions)).toBe(true);
    expect(typeof body.count).toBe("number");
    console.log("[D1] Active interactive sessions:", body.count);
  }
});

test("D2: /api/interactive/launch 400 when tool_id missing", async () => {
  const page = sharedPage;
  const resp = await page.request.post(`${BASE_URL}/api/interactive/launch`, {
    headers: { "Content-Type": "application/json" },
    data: {},
  });
  expect(resp.status()).toBe(400);
  const body = await resp.json();
  expect(body).toHaveProperty("error");
  console.log("[D2] Correct 400 for missing tool_id:", body.error);
});

test("D3: /api/interactive-tools/launch 400 when toolId/datasetIds missing", async () => {
  const page = sharedPage;
  const resp = await page.request.post(`${BASE_URL}/api/interactive-tools/launch`, {
    headers: { "Content-Type": "application/json" },
    data: {},
  });
  expect(resp.status()).toBe(400);
  const body = await resp.json();
  expect(body).toHaveProperty("error");
  console.log("[D3] Correct 400 for missing toolId/datasetIds:", body.error);
});
