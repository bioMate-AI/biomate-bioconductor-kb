/**
 * IND Module — Design Audit
 *
 * Executes the test matrix in docs/20260528_IND_MODULE_DESIGN_AUDIT_PLAN.md.
 * Uses the existing demo data (BM-0042 in_progress, BM-0038 signed,
 * BM-0029 blocked) + URL knobs to walk every surface and verify against
 * reference/claude_design/IND_design/.
 *
 * Run with:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test frontend/e2e/ind-design-audit.e2e.ts
 *
 * Screenshots land in /tmp/ind-design-audit/.
 * Final console table summarizes per-row verdicts.
 */

import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { BASE_URL, setupTestUser } from "./helpers.js";

const SHOTS = "/tmp/ind-design-audit";
if (!fs.existsSync(SHOTS)) fs.mkdirSync(SHOTS, { recursive: true });

type Verdict = "match" | "deviation" | "regression" | "acknowledged-omission";
const results: Array<{ id: string; what: string; verdict: Verdict; detail: string }> = [];

function record(id: string, what: string, verdict: Verdict, detail = "") {
  results.push({ id, what, verdict, detail });
}

async function shot(p: Page, name: string) {
  await p.screenshot({ path: path.join(SHOTS, `${name}.png`), fullPage: false });
}

test.describe("IND module design audit", () => {
  test.setTimeout(180_000);

  test("Full surface walk against Claude design reference", async ({ page }) => {
    // ---- A. Shell + LeftNav ---------------------------------------------------

    await setupTestUser(page, `audit_${Date.now()}`);
    await page.goto(`${BASE_URL}/ind-report?onboarding=0`, { waitUntil: "domcontentloaded" });
    await expect(page.locator(".ind-shell").first()).toBeVisible({ timeout: 15000 });
    await shot(page, "A_shell_loaded");

    // A-1 shell grid
    const shellExists = await page.locator(".ind-shell").count();
    record("A-1", "Shell 3-col grid", shellExists ? "match" : "regression",
      `.ind-shell count=${shellExists}`);

    // A-2/3 LeftNav present + + button
    const leftNav = page.locator(".ind-left").first();
    record("A-2", "LeftNav present", (await leftNav.count()) ? "match" : "regression");

    const newProjectBtn = page.locator(".ind-new-project").first();
    record("A-3", "+ New project button exists",
      (await newProjectBtn.count()) ? "match" : "regression");

    // A-4 Project list — should show 3 demo projects
    const projectRows = await page.locator(".ind-project").count();
    record("A-4", "Project list rows", projectRows >= 1 ? "match" : "deviation",
      `rendered ${projectRows} rows`);

    // ---- B. TopBar ----------------------------------------------------------

    const breadcrumb = page.locator(".ind-crumb");
    const breadcrumbText = (await breadcrumb.first().textContent()) ?? "";
    record("B-1", "Breadcrumb text",
      /IND Report.*§2\.6/.test(breadcrumbText) ? "match" : "deviation",
      `text="${breadcrumbText.trim()}"`);

    const regionChips = await page.locator(".ind-topbar .r-chip").count();
    record("B-2", "Region chips in TopBar",
      regionChips >= 1 ? "match" : "deviation", `count=${regionChips}`);

    // B-3 + B-4 tutorial + user avatar are commented out
    const tutorialBtn = await page.locator(".tut-btn").count();
    const userAvatar = await page.locator(".ind-topbar .user").count();
    record("B-3", "Tutorial button (intentionally absent)",
      tutorialBtn === 0 ? "acknowledged-omission" : "deviation");
    record("B-4", "User avatar (intentionally absent)",
      userAvatar === 0 ? "acknowledged-omission" : "deviation");

    await shot(page, "B_topbar");

    // ---- C/D/E/F/G. PipelineCenter steps -----------------------------------

    const stepCount = await page.locator(".ind-step").count();
    record("C-1..G-1", "All 5 pipeline steps render",
      stepCount === 5 ? "match" : "regression", `step count=${stepCount}`);
    await shot(page, "C_pipeline_steps");

    // ---- H. DocPanel header + region selector ---------------------------------

    const docPanel = page.locator(".ind-doc-panel").first();
    record("H-1", "Doc panel mounted",
      (await docPanel.count()) ? "match" : "regression");

    // H-3: header sub reflects active project, not hardcoded BM-0042 (when on BM-0038)
    const headerSub = (await page.locator(".ind-doc-sub").first().textContent()) ?? "";
    record("H-3", "Doc header sub-line",
      headerSub.length > 0 ? "match" : "deviation", `text="${headerSub.trim()}"`);

    // H-5: region select — EMA/NMPA/PMDA options should be DISABLED
    const regionSelect = page.locator(".ind-doc-region select").first();
    const emaDisabled = await regionSelect.locator("option[value='EMA']").getAttribute("disabled");
    const nmpaDisabled = await regionSelect.locator("option[value='NMPA']").getAttribute("disabled");
    const pmdaDisabled = await regionSelect.locator("option[value='PMDA']").getAttribute("disabled");
    record("H-5", "EMA/NMPA/PMDA disabled in region selector (P1-4)",
      emaDisabled !== null && nmpaDisabled !== null && pmdaDisabled !== null
        ? "match" : "regression",
      `EMA=${emaDisabled} NMPA=${nmpaDisabled} PMDA=${pmdaDisabled}`);

    // H-6: cosmetic note replaced with honest beta string
    const regionRow = (await page.locator(".ind-doc-region").first().textContent()) ?? "";
    record("H-6", "Region cosmetic note shows beta string",
      /beta|coming soon/i.test(regionRow) ? "match" : "deviation",
      `text="${regionRow.replace(/\s+/g, " ").trim().slice(0, 120)}"`);

    // H-7: section tabs render coverage markers
    const tabMarkers = await page.locator(".ind-doc-tabs .marker").count();
    record("H-7", "Section tabs with coverage markers", tabMarkers >= 6 ? "match" : "deviation",
      `markers count=${tabMarkers}`);

    await shot(page, "H_docpanel_header");

    // ---- J. DocPanel footer — real SHA-256 ---------------------------------

    const footerText = (await page.locator(".ind-doc-foot").first().textContent()) ?? "";
    // P2-2: should contain at least 8 hex chars (not the "(computing…)" stub or empty)
    const shaMatch = footerText.match(/SHA-256:\s*([0-9a-f]{8,})/i);
    record("J-1", "Real SHA-256 in footer (P2-2)",
      shaMatch ? "match" : "deviation",
      `prefix=${shaMatch ? shaMatch[1].slice(0, 12) : "(missing)"}`);

    // J-5: footer action buttons present
    const footerHasSign = /sign|freeze/i.test(footerText);
    const footerHasDownload = /\.md|markdown|download/i.test(footerText);
    record("J-5", "Footer actions (Sign + Download)",
      footerHasSign && footerHasDownload ? "match" : "deviation");

    await shot(page, "J_docpanel_footer");

    // ---- L. Audit overlay (must mount INSIDE doc panel, P0-2) --------------

    const auditTriggerCandidates = page
      .locator("button")
      .filter({ hasText: /^\s*(Audit|🛡)/i });
    const auditTrigger = (await auditTriggerCandidates.count()) ? auditTriggerCandidates.first() : null;
    if (auditTrigger) {
      await auditTrigger.click();
      const auditOverlay = page.locator(".ind-audit-overlay").first();
      try {
        await expect(auditOverlay).toBeVisible({ timeout: 5000 });
        // L-1: must be a descendant of .ind-doc-panel for the slide-in to work
        const insideDocPanel = await page.evaluate(() => {
          const overlay = document.querySelector(".ind-audit-overlay");
          const panel = document.querySelector(".ind-doc-panel");
          return overlay && panel ? panel.contains(overlay) : false;
        });
        record("L-1", "Audit overlay hosted INSIDE doc panel (P0-2)",
          insideDocPanel ? "match" : "regression");

        const sevChips = await page.locator(".ind-audit-meta .audit-chip, .ind-audit-overlay .audit-chip").count();
        record("L-3", "Severity counter chips", sevChips >= 1 ? "match" : "deviation",
          `count=${sevChips}`);

        const findings = await page.locator("[data-testid^='audit-finding-']").count();
        record("L-5", "Audit findings rendered", findings >= 1 ? "match" : "deviation",
          `count=${findings}`);

        await shot(page, "L_audit_overlay");

        // Close overlay
        const closeBtn = page.locator(".ind-audit-overlay button").filter({ hasText: /^\s*Close/i }).first();
        if (await closeBtn.count()) await closeBtn.click();
        await page.waitForTimeout(500);
      } catch (e) {
        record("L-1", "Audit overlay opens", "regression", `error: ${(e as Error).message}`);
      }
    } else {
      record("L-1", "Audit button found", "regression", "no Audit button visible");
    }

    // ---- M. Version history popover (P2-6 frontend) ------------------------

    const verChip = page.locator(".ver-chip").first();
    if (await verChip.count()) {
      await verChip.click();
      const popover = page.locator(".version-popover").first();
      try {
        await expect(popover).toBeVisible({ timeout: 5000 });
        const popText = (await popover.textContent()) ?? "";
        // Should NOT show the old fake "Dr. Jane Smith · Sig 8f2a3c…"
        const stillHardcoded = /Sig 8f2a3c|Jane Smith/.test(popText);
        record("M-2", "Version popover fetches real data (no fake v1/v2 from reference)",
          stillHardcoded ? "regression" : "match",
          stillHardcoded ? "still shows hardcoded Jane Smith" : "real fetch path");

        // Empty state OR a real version row should be present
        const hasCurrent = /Current/i.test(popText);
        record("M-3", "Current version badge", hasCurrent ? "match" : "deviation");
        await shot(page, "M_version_popover");

        await page.locator("body").click({ position: { x: 1, y: 1 } });
      } catch (e) {
        record("M-2", "Version popover opens", "deviation", `error: ${(e as Error).message}`);
      }
    } else {
      record("M-1", "Version chip exists", "deviation", "no .ver-chip");
    }

    // ---- P1-7 sanity: no data-tour attributes left in rendered DOM ---------

    const dataTourCount = await page.evaluate(() =>
      document.querySelectorAll("[data-tour]").length
    );
    record("P1-7", "Stripped data-tour attributes (no dead hooks)",
      dataTourCount === 0 ? "match" : "deviation",
      `${dataTourCount} data-tour attrs still in DOM`);

    // ---- N. EmptyState (?onboarding=1) -------------------------------------

    await page.goto(`${BASE_URL}/ind-report?onboarding=1`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(500);
    const emptyStart = await page.locator("button").filter({ hasText: /Start/i }).count();
    const refChips = await page.locator(".ind-ref-chip, [data-testid^='ref-chip']").count();
    record("N-1", "Empty state Start button", emptyStart ? "match" : "deviation");
    record("N-2", "Reference compound chips visible", refChips >= 1 ? "match" : "deviation",
      `count=${refChips}`);
    await shot(page, "N_empty_state");

    // ---- D-2 Running step 2 (?state=running) -------------------------------

    await page.goto(`${BASE_URL}/ind-report?state=running`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(500);
    const progressBar = await page.locator(".ind-progress .bar, .ind-progress").count();
    record("D-2", "Step 2 running state shows progress",
      progressBar ? "match" : "deviation");
    await shot(page, "D2_step2_running");

    // ---- E-3 PBPK fail (?state=pbpk-fail) ----------------------------------

    await page.goto(`${BASE_URL}/ind-report?state=pbpk-fail`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(500);
    const pbpkFailMarker = (await page.locator("text=/criterion NOT met|⚠ Failed/i").count()) > 0;
    record("E-3", "Step 3 PBPK fail state shows red box",
      pbpkFailMarker ? "match" : "deviation");
    await shot(page, "E3_pbpk_fail");

    // ---- D-3 imported-from-chat (?imported=1) ------------------------------

    await page.goto(`${BASE_URL}/ind-report?imported=1`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(500);
    const importedBanner = (await page.locator("text=/Imported from chat/i").count()) > 0;
    record("D-3", "Imported from chat banner",
      importedBanner ? "match" : "deviation");
    await shot(page, "D3_imported_banner");

    // ---- O. Mobile FAB (≤1024px viewport) ---------------------------------

    await page.setViewportSize({ width: 800, height: 900 });
    await page.goto(`${BASE_URL}/ind-report`, { waitUntil: "domcontentloaded" });
    await page.waitForTimeout(500);
    const fabVisible = await page.locator(".ind-doc-fab").isVisible().catch(() => false);
    record("O-1", "Mobile FAB visible at ≤1024px",
      fabVisible ? "match" : "deviation");
    if (fabVisible) {
      await page.locator(".ind-doc-fab").click();
      const mobileModal = await page.locator("[data-testid='ind-doc-mobile-modal']").count();
      record("O-2", "Mobile FAB opens DocPanelMobileModal",
        mobileModal ? "match" : "regression");
      await shot(page, "O_mobile_fab_modal");
    }
    await page.setViewportSize({ width: 1440, height: 900 });

    // ---- Summary table -----------------------------------------------------

    console.log("\n=== IND DESIGN AUDIT RESULTS ===");
    console.log("ID         | Verdict                    | What");
    console.log("-----------|----------------------------|---------------------------------");
    const counts: Record<Verdict, number> = {
      match: 0, deviation: 0, regression: 0, "acknowledged-omission": 0,
    };
    for (const r of results) {
      const icon = r.verdict === "match" ? "✅"
        : r.verdict === "acknowledged-omission" ? "🟢"
        : r.verdict === "deviation" ? "🟡" : "🔴";
      console.log(`${r.id.padEnd(10)} | ${icon} ${r.verdict.padEnd(23)} | ${r.what}${r.detail ? ` — ${r.detail}` : ""}`);
      counts[r.verdict]++;
    }
    console.log(`\nMatches: ${counts.match}  Acknowledged: ${counts["acknowledged-omission"]}  Deviations: ${counts.deviation}  Regressions: ${counts.regression}`);
    console.log(`Screenshots in: ${SHOTS}`);

    // The test passes when there are ZERO regressions.
    expect(counts.regression).toBe(0);
  });
});
