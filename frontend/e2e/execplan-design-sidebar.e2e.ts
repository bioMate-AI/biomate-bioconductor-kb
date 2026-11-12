/**
 * Exec-plan harness — Design & Generate / Search & Evidence / Sidebar
 * against LIVE dev (https://dev-public.biomate.ai).
 *
 * Source of truth: docs/20260909_TESTPLAN_DESIGN_SEARCH_SIDEBAR.md (41 UCs).
 *
 * Discipline (CLAUDE.md §E2E):
 *  - NO mocking. Real backend only. Single canonical fixture
 *    (lifeifei163361@163.com) via loginAsFixture. Login ONCE per worker.
 *  - Covers UI-observable UCs. SKIPs (with an explicit flag) any UC that
 *    needs a real design/generation run or a live search-answer to populate
 *    citations — those cannot be observed without a backend run and are out
 *    of scope for a route/pre-run/nav harness.
 *
 * Scope covered here:
 *  - Surface A (Design & Generate): entry-route chips (A01-A03, real nav),
 *    constraints composer + all pre-run controls (A04-A08), run-button
 *    pre-run state. Post-run result UCs (A09-A18) SKIPPED (need a live run).
 *  - Surface B (Search/citation): SKIPPED — CitationPanel renders null
 *    without a live answer carrying citations; no standalone route.
 *  - Surface C (Sidebar): the REAL deployed entries + navigation (C01-C13).
 *    Billing / Recent-Tools rewire is committed-not-deployed → asserted as
 *    "fixed-not-yet-deployed" (absent on dev is expected, NOT a fail).
 *
 * Screenshots → frontend/e2e/execshots/design-sidebar/
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const SHOT_DIR = path.join(__dirname, "execshots", "design-sidebar");
fs.mkdirSync(SHOT_DIR, { recursive: true });

const CALL_TIMEOUT = 90_000;

// Honest result ledger — printed at the end and used to produce the table.
type Verdict = "PASS" | "FAIL" | "SKIP";
const ledger: {
  uc: string;
  check: string;
  verdict: Verdict;
  reason: string;
  shot: string;
  note: string;
}[] = [];
function record(
  uc: string,
  check: string,
  verdict: Verdict,
  shot: string,
  note = "",
  reason = ""
) {
  ledger.push({ uc, check, verdict, reason, shot, note });
}

async function shot(page: Page, name: string): Promise<string> {
  const file = path.join(SHOT_DIR, `${name}.png`);
  await page.screenshot({ path: file, fullPage: false }).catch(() => {});
  return path.basename(file);
}

/** Navigate to a route on dev; return the final pathname. */
async function goto(page: Page, route: string): Promise<void> {
  await page.goto(`${BASE_URL}${route}`, {
    waitUntil: "domcontentloaded",
    timeout: CALL_TIMEOUT,
  });
  // Give the SPA a beat to mount the authenticated shell.
  await page.waitForTimeout(2500);
}

test.describe("Exec-plan: Design & Generate / Sidebar (live dev)", () => {
  test.setTimeout(600_000);

  test.beforeAll(() => {
    // eslint-disable-next-line no-console
    console.log(`[execplan] BASE_URL=${BASE_URL}`);
  });

  test("full harness", async ({ page }) => {
    await loginAsFixture(page);

    // ---------------------------------------------------------------
    // SURFACE A — Design & Generate  (/design)
    // ---------------------------------------------------------------
    await goto(page, "/design");
    const composer = page.getByTestId("design-generate");
    const composerVisible = await composer
      .isVisible()
      .catch(() => false);
    const s_mount = await shot(page, "A00-design-mount");
    if (!composerVisible) {
      record(
        "A00",
        "/design mounts DesignGenerate (design-generate container)",
        "FAIL",
        s_mount,
        "design-generate container not visible on dev",
        "component did not render"
      );
      // If the surface didn't mount, the A-UCs below can't run; still try sidebar.
    } else {
      record(
        "A00",
        "/design mounts DesignGenerate container",
        "PASS",
        s_mount
      );

      // --- UC-A04: constraints composer + seed SMILES editable ---
      const constraints = page.getByTestId("constraints-composer");
      const seed = page.getByTestId("dg-seed-smiles");
      let ok =
        (await constraints.isVisible().catch(() => false)) &&
        (await seed.isVisible().catch(() => false));
      if (ok) {
        await seed.fill("CC(=O)Oc1ccccc1C(=O)O");
        const v = await seed.inputValue().catch(() => "");
        ok = v === "CC(=O)Oc1ccccc1C(=O)O";
      }
      const s_a04 = await shot(page, "A04-constraints-composer");
      record(
        "A04",
        "constraints-composer renders; dg-seed-smiles editable",
        ok ? "PASS" : "FAIL",
        s_a04,
        ok ? "seed value reflected" : "composer/seed missing or not editable"
      );

      // --- UC-A05: scaffold policy toggle (stay/hop/grow) ---
      const policyStrip = page.getByTestId("dg-scaffold-policy");
      const policyVisible = await policyStrip.isVisible().catch(() => false);
      let policyOk = policyVisible;
      if (policyVisible) {
        // policy buttons carry label text stay/hop/grow (capitalized). Click Hop then Grow.
        const hop = policyStrip.getByRole("button", { name: /hop/i });
        const grow = policyStrip.getByRole("button", { name: /grow/i });
        const hopExists = await hop.count();
        const growExists = await grow.count();
        if (hopExists && growExists) {
          await hop.click().catch(() => {});
          await page.waitForTimeout(200);
          await grow.click().catch(() => {});
          await page.waitForTimeout(200);
          policyOk = true;
        } else {
          policyOk = false;
        }
      }
      const s_a05 = await shot(page, "A05-scaffold-policy");
      record(
        "A05",
        "scaffold policy strip renders; hop/grow clickable",
        policyOk ? "PASS" : "FAIL",
        s_a05,
        policyOk ? "toggled hop→grow" : "policy strip or buttons missing"
      );

      // --- UC-A06: property envelope MW/logP/TPSA edit ---
      const envelope = page.getByTestId("dg-envelope");
      const mw = page.getByTestId("dg-mw");
      const logp = page.getByTestId("dg-logp");
      const tpsa = page.getByTestId("dg-tpsa");
      let envOk = await envelope.isVisible().catch(() => false);
      if (envOk) {
        await mw.fill("450").catch(() => (envOk = false));
        await logp.fill("4").catch(() => (envOk = false));
        await tpsa.fill("120").catch(() => (envOk = false));
        const vals = await Promise.all([
          mw.inputValue().catch(() => ""),
          logp.inputValue().catch(() => ""),
          tpsa.inputValue().catch(() => ""),
        ]);
        envOk = vals[0] === "450" && vals[1] === "4" && vals[2] === "120";
      }
      const s_a06 = await shot(page, "A06-property-envelope");
      record(
        "A06",
        "property envelope MW/logP/TPSA editable",
        envOk ? "PASS" : "FAIL",
        s_a06,
        envOk ? "450/4/120 reflected" : "envelope inputs missing/not editable"
      );

      // --- UC-A07: exclusions SMARTS + seed series textareas ---
      const excl = page.getByTestId("dg-exclusions");
      const series = page.getByTestId("dg-seed-series");
      let listOk =
        (await excl.isVisible().catch(() => false)) &&
        (await series.isVisible().catch(() => false));
      if (listOk) {
        await excl.fill("[N+](=O)[O-]");
        await series.fill("CCO\nCCC");
        listOk =
          (await excl.inputValue()) === "[N+](=O)[O-]" &&
          (await series.inputValue()) === "CCO\nCCC";
      }
      const s_a07 = await shot(page, "A07-exclusions-series");
      record(
        "A07",
        "exclusions + seed-series textareas render & accept input",
        listOk ? "PASS" : "FAIL",
        s_a07,
        listOk ? "both textareas filled" : "exclusions/series missing"
      );

      // --- UC-A08: count + virtual library size + compute cost hint ---
      const count = page.getByTestId("dg-count");
      const ngen = page.getByTestId("dg-ngenerate");
      const cost = page.getByTestId("dg-cost");
      let costOk = await cost.isVisible().catch(() => false);
      let costText = "";
      if (costOk) {
        const initialCost = (await cost.textContent()) || "";
        // defaults count=20, nGenerate=200 → round((200+20)/50)=round(4.4)=4
        await count.fill("40").catch(() => {});
        await ngen.fill("400").catch(() => {});
        await page.waitForTimeout(300);
        costText = (await cost.textContent()) || "";
        // 40+400 → round(440/50)=round(8.8)=9 compute units
        const m = costText.match(/~\s*(\d+)\s+compute unit/);
        costOk = !!m && parseInt(m[1], 10) === 9;
        if (!costOk) costText = `initial="${initialCost}" after="${costText}"`;
      }
      const s_a08 = await shot(page, "A08-cost-hint");
      record(
        "A08",
        "compute-cost hint recomputes (40+400 → ~9 compute units)",
        costOk ? "PASS" : "FAIL",
        s_a08,
        costOk ? "formula matches (~9 units)" : `cost text: ${costText}`
      );

      // --- UC-A09/A12: run button pre-run state (idle badge, enabled) ---
      const runBtn = page.getByTestId("dg-run");
      const statusBadge = page.getByTestId("dg-status");
      const runVisible = await runBtn.isVisible().catch(() => false);
      const badgeStatus = await statusBadge
        .getAttribute("data-status")
        .catch(() => null);
      const runDisabled = await runBtn.isDisabled().catch(() => true);
      const s_a09 = await shot(page, "A09-run-prerun");
      // Pre-run: badge should be idle/absent-status and run button enabled.
      const preRunOk =
        runVisible && !runDisabled && badgeStatus !== "running";
      record(
        "A09",
        "run button present + enabled pre-run; status not 'running'",
        preRunOk ? "PASS" : "FAIL",
        s_a09,
        `runVisible=${runVisible} disabled=${runDisabled} status=${badgeStatus}`
      );
      record(
        "A09-run",
        "actual /api/generate run + running→completed states",
        "SKIP",
        s_a09,
        "",
        "requires a real design generation run (backend job) — out of scope for pre-run harness"
      );
      // A10-A18 (results, notes, hitgrid, pareto, rejection, order-sheet,
      // predicted-vs-measured, error banner) all need a completed run.
      for (const [uc, what] of [
        ["A10", "poll→completed status/notes/generator line"],
        ["A11", "HitGrid + multi-objective view (no composite)"],
        ["A12", "editable criteria re-rank WITHOUT re-run"],
        ["A13", "export order-sheet CSV"],
        ["A14", "per-row why? drill-in"],
        ["A15", "pareto / trade-off view"],
        ["A16", "rejection profile + rejected set visible"],
        ["A17", "honest empty state (no candidates)"],
        ["A17b", "predicted-vs-measured contradiction flag"],
        ["A18", "backend-failure error banner"],
      ] as const) {
        record(
          uc,
          what,
          "SKIP",
          "",
          "",
          "needs a real completed/failed generation run to render — deferred per task scope"
        );
      }
    }

    // --- UC-A01/A02/A03: entry-route chips navigate (real URL change) ---
    // Re-navigate to /design fresh for a clean strip, then click each chip.
    // (Chip click navigates AWAY, so re-mount /design between each.)
    async function testEntryRoute(
      uc: string,
      chipTestId: string,
      expectPath: string,
      expectSearch: string
    ) {
      await goto(page, "/design");
      const chip = page.getByTestId(chipTestId);
      const chipVisible = await chip.isVisible().catch(() => false);
      if (!chipVisible) {
        const s = await shot(page, `${uc}-entry-missing`);
        record(
          uc,
          `${chipTestId} navigates to ${expectPath}?${expectSearch}`,
          "FAIL",
          s,
          "entry chip not visible"
        );
        return;
      }
      await chip.click().catch(() => {});
      // wouter navigation is synchronous-ish; wait for URL.
      await page
        .waitForFunction(
          (p) => window.location.pathname === p,
          expectPath,
          { timeout: 10_000 }
        )
        .catch(() => {});
      await page.waitForTimeout(800);
      const url = new URL(page.url());
      const ok =
        url.pathname === expectPath &&
        url.search.includes(expectSearch);
      const s = await shot(page, `${uc}-after-nav`);
      record(
        uc,
        `${chipTestId} → ${expectPath}?${expectSearch}`,
        ok ? "PASS" : "FAIL",
        s,
        `landed at ${url.pathname}${url.search}`
      );
    }
    await testEntryRoute("A01", "design-entry-dataset", "/files", "from=design");
    await testEntryRoute("A02", "design-entry-models", "/models", "from=design");
    await testEntryRoute("A03", "design-entry-search", "/", "from=design");

    // ---------------------------------------------------------------
    // SURFACE B — Search & Evidence (citation-panel + source-reader)
    // ---------------------------------------------------------------
    // CitationPanel returns null unless a live answer carries citations,
    // and has NO standalone route. Cannot be observed without a real
    // research-answer run → SKIP whole surface, flagged.
    for (const [uc, what] of [
      ["B01", "citation panel collapse/expand + tool-count badge"],
      ["B02", "conflict row (sources disagree)"],
      ["B03", "citation locus + recency"],
      ["B04", "per-source open ▸ / Read → source reader pane"],
      ["B05", "source reader prev/next"],
      ["B06", "save-to-notes SUCCESS (real POST)"],
      ["B07", "save-to-notes FAILURE toast"],
      ["B08", "save-to-notes disabled (no project)"],
      ["B09", "make-instruction honestly disabled"],
      ["B10", "export BibTeX"],
      ["B11", "methods section tab"],
    ] as const) {
      record(
        uc,
        what,
        "SKIP",
        "",
        "",
        "CitationPanel renders null without a live answer + populated citations; no standalone route — needs a real search/research answer run"
      );
    }

    // ---------------------------------------------------------------
    // SURFACE C — Sidebar (app-sidebar.tsx) — REAL deployed entries
    // ---------------------------------------------------------------
    // Land on root so the authenticated shell (sidebar) mounts.
    await goto(page, "/");
    const s_sidebar = await shot(page, "C00-sidebar");

    // Helper: check a sidebar testid is present + visible.
    async function present(testId: string): Promise<boolean> {
      return page
        .getByTestId(testId)
        .first()
        .isVisible()
        .catch(() => false);
    }

    // UC-C01 New Chat — moved to the collapsed icon rail (founder request). Collapse
    // first, then assert the rail entry is present + clickable (handler is app-level).
    {
      await page.getByTestId("button-sidebar-toggle").first().click().catch(() => {});
      await page.waitForTimeout(300);
      const ok = await present("button-new-chat");
      if (ok) await page.getByTestId("button-new-chat").first().click().catch(() => {});
      const s = await shot(page, "C01-new-chat");
      record("C01", "New Chat entry present + clickable (collapsed rail)", ok ? "PASS" : "FAIL", s);
    }

    // UC-C02 Workflows → WorkflowHistoryDialog
    {
      await goto(page, "/");
      const ok = await present("button-workflows-nav");
      let dialogOpened = false;
      if (ok) {
        await page.getByTestId("button-workflows-nav").first().click().catch(() => {});
        await page.waitForTimeout(1500);
        dialogOpened = await page
          .getByRole("dialog")
          .first()
          .isVisible()
          .catch(() => false);
      }
      const s = await shot(page, "C02-workflows-dialog");
      record(
        "C02",
        "Workflows entry present → opens a dialog (WorkflowHistoryDialog)",
        ok && dialogOpened ? "PASS" : ok ? "FAIL" : "FAIL",
        s,
        `present=${ok} dialogOpened=${dialogOpened}`
      );
      await page.keyboard.press("Escape").catch(() => {});
    }

    // UC-C03 Connectors → ConnectorsDialog
    {
      await goto(page, "/");
      const ok = await present("button-connectors-nav");
      let dialogOpened = false;
      if (ok) {
        await page.getByTestId("button-connectors-nav").first().click().catch(() => {});
        await page.waitForTimeout(1500);
        dialogOpened = await page
          .getByRole("dialog")
          .first()
          .isVisible()
          .catch(() => false);
      }
      const s = await shot(page, "C03-connectors-dialog");
      record(
        "C03",
        "Connectors entry present → opens ConnectorsDialog",
        ok && dialogOpened ? "PASS" : "FAIL",
        s,
        `present=${ok} dialogOpened=${dialogOpened}`
      );
      await page.keyboard.press("Escape").catch(() => {});
    }

    // UC-C04 IND Report → /ind-report
    async function navEntry(
      uc: string,
      testId: string,
      expectPath: string
    ) {
      await goto(page, "/");
      const ok = await present(testId);
      if (!ok) {
        const s = await shot(page, `${uc}-missing`);
        record(uc, `${testId} present`, "FAIL", s, "entry not visible");
        return;
      }
      await page.getByTestId(testId).first().click().catch(() => {});
      await page
        .waitForFunction((p) => window.location.pathname === p, expectPath, {
          timeout: 12_000,
        })
        .catch(() => {});
      await page.waitForTimeout(1000);
      const landed = new URL(page.url()).pathname;
      const s = await shot(page, `${uc}-nav`);
      record(
        uc,
        `${testId} → ${expectPath}`,
        landed === expectPath ? "PASS" : "FAIL",
        s,
        `landed at ${landed}`
      );
    }
    // C04 button-ind-report hidden from sidebar 2026-09-22 (per request); route still exists via direct URL.
    // await navEntry("C04", "button-ind-report", "/ind-report");
    await navEntry("C05", "button-data-nav", "/files");
    await navEntry("C06", "button-models-nav", "/models");
    await navEntry("C07", "button-design-generate-nav", "/design");

    // UC-C08 Projects section toggle
    {
      await goto(page, "/");
      const ok = await present("button-projects-section");
      if (ok)
        await page
          .getByTestId("button-projects-section")
          .first()
          .click()
          .catch(() => {});
      await page.waitForTimeout(800);
      const s = await shot(page, "C08-projects-section");
      record(
        "C08",
        "Projects section toggle present + clickable",
        ok ? "PASS" : "FAIL",
        s
      );
    }

    // UC-C09 New project
    {
      const ok = await present("button-new-project");
      const s = await shot(page, "C09-new-project");
      record(
        "C09",
        "New project entry present",
        ok ? "PASS" : "FAIL",
        s
      );
    }

    // UC-C11 Settings (sidebar entry + footer gear)
    {
      await goto(page, "/");
      const okSide = await present("button-settings-sidebar");
      let dialogOpened = false;
      if (okSide) {
        await page
          .getByTestId("button-settings-sidebar")
          .first()
          .click()
          .catch(() => {});
        await page.waitForTimeout(1200);
        dialogOpened = await page
          .getByRole("dialog")
          .first()
          .isVisible()
          .catch(() => false);
        await page.keyboard.press("Escape").catch(() => {});
      }
      const okFooter = await present("button-settings");
      const s = await shot(page, "C11-settings");
      record(
        "C11",
        "Settings entry (sidebar) present → opens SettingsDialog; footer gear present",
        okSide && dialogOpened && okFooter ? "PASS" : "FAIL",
        s,
        `sidebar=${okSide} dialog=${dialogOpened} footerGear=${okFooter}`
      );
    }

    // UC-C12 Collapse toggle
    {
      await goto(page, "/");
      const ok = await present("button-sidebar-toggle");
      if (ok)
        await page
          .getByTestId("button-sidebar-toggle")
          .first()
          .click()
          .catch(() => {});
      await page.waitForTimeout(800);
      const s = await shot(page, "C12-collapse");
      record(
        "C12",
        "Collapse toggle present + clickable",
        ok ? "PASS" : "FAIL",
        s
      );
    }

    // UC-C13 Logout — assert present. (Do NOT click: it would kill the session
    // and cost a re-login; presence + wiring is the observable check.)
    {
      await goto(page, "/");
      const ok = await present("button-logout");
      const s = await shot(page, "C13-logout");
      record(
        "C13",
        "Logout entry present (not clicked — would end session)",
        ok ? "PASS" : "FAIL",
        s,
        "presence-only to preserve session"
      );
    }

    // UC-C: committed-not-yet-deployed rewire — Billing + Recent Tools.
    // Source in this repo HAS button-billing-nav / button-recent-tools, but
    // the plan says they're NOT yet deployed on dev. Assert ACTUAL dev state
    // and flag as "fixed-not-yet-deployed" (absent → expected, not a fail).
    {
      await goto(page, "/");
      const billingPresent = await present("button-billing-nav");
      const recentToolsPresent = await present("button-recent-tools");
      const s = await shot(page, "C-drift-billing-recenttools");
      record(
        "C-drift-billing",
        "Billing sidebar entry (committed-not-deployed rewire)",
        "SKIP",
        s,
        billingPresent
          ? "PRESENT on dev — rewire IS deployed"
          : "ABSENT on dev — expected (fixed-not-yet-deployed)",
        "fixed-not-yet-deployed: source has button-billing-nav; dev may not"
      );
      record(
        "C14",
        "Recent Tools reachable from sidebar (spec-drift; dialog unwired historically)",
        "SKIP",
        s,
        recentToolsPresent
          ? "button-recent-tools PRESENT on dev — rewire IS deployed"
          : "ABSENT on dev — expected (fixed-not-yet-deployed)",
        "fixed-not-yet-deployed"
      );
    }

    // ---------------------------------------------------------------
    // Emit the results table.
    // ---------------------------------------------------------------
    const lines: string[] = [];
    lines.push("\n================ EXEC-PLAN RESULTS ================");
    lines.push("UC-id | check | verdict | screenshot | note");
    for (const r of ledger) {
      const v =
        r.verdict === "SKIP" && r.reason
          ? `SKIP(${r.reason})`
          : r.verdict;
      lines.push(
        `${r.uc} | ${r.check} | ${v} | ${r.shot || "-"} | ${r.note || r.reason || ""}`
      );
    }
    const counts = ledger.reduce(
      (acc, r) => {
        acc[r.verdict] = (acc[r.verdict] || 0) + 1;
        return acc;
      },
      {} as Record<string, number>
    );
    lines.push(
      `\nCOUNTS: PASS=${counts.PASS || 0} FAIL=${counts.FAIL || 0} SKIP=${counts.SKIP || 0} TOTAL=${ledger.length}`
    );
    const out = lines.join("\n");
    // eslint-disable-next-line no-console
    console.log(out);
    fs.writeFileSync(path.join(SHOT_DIR, "RESULTS.txt"), out);
  });
});
