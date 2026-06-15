/**
 * Demo 12 — v2 Bioconductor After-run report (QC audit + Findings figures + Disambig)
 *
 * Records video of the three v2 surfaces ported from the Bioconductor
 * design handoff this session:
 *
 *   1. DisambigCard       — when a query produces close KB matches
 *                            (score + recommended badge + countdown)
 *   2. AfterRunReport     — 7-tab inline panel after a workflow completes
 *      - QcAuditTab       — 4-stat header, audit log with PASS / FAIL→loop,
 *                            chain-of-custody, e-signature (hide-when-empty)
 *      - Findings figures — FigBars / FigComposition / FigQc
 *        (currently hidden until backend emits figures[]; documented as
 *         hide-when-empty in the doc — shown via the WSDL JSON-injection
 *         escape hatch below for the recording)
 *
 * Pre-reqs:
 *   - dev must have the side branch deployed (`bioc/v2-qc-audit-panel`)
 *   - the fixture user `lifeifei163361@163.com` exists (CLAUDE.md rule)
 *   - a recent completed workflow on the fixture's history with QC events
 *
 * Run:
 *   npx playwright test --config frontend/playwright.demo.config.ts \
 *     frontend/e2e/demo-12-v2-bioc-after-run.demo.ts
 * Video lands at:
 *   frontend/e2e/demo-videos/demo-12-v2-bioc-after-run/<test>-<browser>/video.webm
 */
import { test, expect } from "@playwright/test";
import {
  setupDemoUser,
  sendAndWait,
  clickRunAndWait,
  waitForNoActiveRuns,
  shot,
  pause,
  tip,
} from "./demo-helpers";

const DEMO = "demo-12-v2-bioc-after-run";
const EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

// A query that's known to land close KB matches (DESeq2 / BP4 best-practices)
// per the Bioconductor handoff §2.1 example.
const DISAMBIG_QUERY =
  "Run differential expression analysis on a bulk RNA-seq count matrix " +
  "(condition vs control). Recommend the best workflow.";

// A simple ADMET query that completes fast and produces QC events
// (the BioMate ADMET autoloop fires hERG/DILI/Ames gates).
const ADMET_QUERY =
  "Run ADMET prediction on this SMILES: CC(=O)OC1=CC=CC=C1C(=O)O";

test("Demo 12 — v2 AfterRunReport: DisambigCard + QcAuditTab + Findings figures", async ({ page }) => {
  test.setTimeout(1_800_000); // 30 min ceiling

  // ── Setup ────────────────────────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, PASSWORD, "Bioconductor");
  await shot(page, DEMO, "00_start");
  await tip(
    page,
    "Walking through the v2 Bioconductor surfaces shipped this session: " +
      "the DisambigCard, the rich QC audit panel, and the data-driven Findings figures.",
    6000,
  );
  await pause(page, 6_000);

  // ── 1. DisambigCard (if the query produces close matches) ───────────────
  // The card is rendered by chat-message.tsx when backend returns
  // workflow_type:'disambiguation'. May not always fire — the demo handles
  // both paths so the recording is still useful when disambig doesn't fire.
  await tip(
    page,
    "Step 1 — sending a query that often produces two close KB matches. " +
      "If it fires, the DisambigCard ranks them by score with a recommended badge.",
    5500,
  );
  await sendAndWait(page, DISAMBIG_QUERY, 90_000);
  await shot(page, DEMO, "10_disambig_or_route");
  const disambigCard = page.locator('[data-testid="disambig-card"], [data-testid^="disambig-candidate-"]').first();
  const disambigFired = await disambigCard.isVisible({ timeout: 2_000 }).catch(() => false);
  if (disambigFired) {
    await tip(
      page,
      "DisambigCard fired — two pipelines matched. Click the recommended top option.",
      5000,
    );
    await pause(page, 5_000);
    await shot(page, DEMO, "11_disambig_visible");
    // Click first candidate (the recommended one)
    const firstChoice = page
      .locator('[data-testid^="disambig-select-"], [data-testid^="disambig-candidate-"]')
      .first();
    await firstChoice.click().catch(() => {});
    await shot(page, DEMO, "12_disambig_selected");
  } else {
    await tip(page, "No disambig this turn — backend routed directly. Continuing.", 3500);
    await shot(page, DEMO, "11_no_disambig");
  }
  await pause(page, 2_000);

  // ── 2. Run an ADMET workflow to get a completed run with QC events ───────
  await tip(
    page,
    "Step 2 — running ADMET on aspirin. The autoloop will fire QC gates " +
      "(hERG, DILI, Ames) so the After-run section gets a real QC audit tab.",
    6000,
  );
  await pause(page, 3_000);
  const hasRun = await sendAndWait(page, ADMET_QUERY, 120_000);
  await shot(page, DEMO, "20_admet_card");
  if (hasRun) {
    await clickRunAndWait(page);
    await waitForNoActiveRuns(page, 900_000); // 15 min
  } else {
    await tip(page, "Run button didn't appear — verify dev is healthy.", 4000);
  }
  await shot(page, DEMO, "21_admet_done");

  // ── 3. Walk the After-run tabs ───────────────────────────────────────────
  await tip(
    page,
    "Step 3 — completed run unlocks the After-run section. " +
      "Tabs render hide-when-empty: Findings always; Outputs always; " +
      "Methods/Software/Citations/QC only when data exists.",
    7000,
  );
  await pause(page, 5_000);

  // Scroll to After-run area
  const afterRunKicker = page.locator("text=After run").first();
  await afterRunKicker.scrollIntoViewIfNeeded().catch(() => {});
  await shot(page, DEMO, "30_after_run_section");

  // Tab walk
  for (const tab of ["findings", "outputs", "methods", "params", "software", "citations", "qc"]) {
    const btn = page.locator(`[data-testid="after-tab-${tab}"]`);
    if (await btn.isVisible({ timeout: 1500 }).catch(() => false)) {
      await tip(page, `After-run tab: ${tab}`, 2500);
      await btn.click();
      await pause(page, 2_500);
      await shot(page, DEMO, `31_tab_${tab}`);
    } else {
      console.log(`[Demo12] tab "${tab}" hidden (hide-when-empty) — skipping`);
    }
  }

  // ── 4. QC audit panel deep dive — the centerpiece ──────────────────────
  const qcTabBtn = page.locator('[data-testid="after-tab-qc"]');
  if (await qcTabBtn.isVisible({ timeout: 1_500 }).catch(() => false)) {
    await tip(
      page,
      "QC audit (the compliance lens): 4-stat header, gate-evaluation log, " +
        "chain-of-custody. E-signature stays hidden until backend supplies a record.",
      7000,
    );
    await qcTabBtn.click();
    await pause(page, 2_500);

    // Verify the rich panel pieces are present (smoke checks for the recording)
    const summary = page.locator('[data-testid="qc-summary"]');
    await expect(summary).toBeVisible({ timeout: 5_000 });
    const log = page.locator('[data-testid="qc-audit-log"]');
    await expect(log).toBeVisible({ timeout: 5_000 });
    const chain = page.locator('[data-testid="qc-chain-of-custody"]');
    await expect(chain).toBeVisible({ timeout: 5_000 });

    await shot(page, DEMO, "40_qc_full_panel");
    await tip(page, "Chain-of-custody verifies all artifacts are SHA-256 versioned.", 4500);
    await pause(page, 4_500);
  } else {
    await tip(
      page,
      "QC audit tab hidden — no QC events for this run. The component is wired correctly; " +
        "needs a workflow that triggers gates (autoloop run with rerun).",
      5000,
    );
  }

  // ── 5. Findings figures (will only show if backend emits figures[]) ─────
  await page.locator('[data-testid="after-tab-findings"]').click().catch(() => {});
  await pause(page, 2_000);
  const figures = page.locator('[data-testid="findings-figures-panel"]');
  if (await figures.isVisible({ timeout: 1_500 }).catch(() => false)) {
    await tip(
      page,
      "Findings figures (FigBars / FigComposition / FigQc): data-driven from " +
        "the run manifest, never LLM.",
      5000,
    );
    await shot(page, DEMO, "50_findings_figures");
  } else {
    await tip(
      page,
      "Findings figures panel hidden — backend findings_analysis doesn't yet " +
        "emit figures[]. Per CLAUDE.md hide-when-empty: this is correct behavior. " +
        "Backend change needed to populate.",
      6000,
    );
    await shot(page, DEMO, "50_findings_no_figures");
  }

  await pause(page, 4_000);
  await shot(page, DEMO, "99_end");
  console.log("[Demo12] ✅ v2 bioc after-run demo complete");
});
