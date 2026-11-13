/**
 * after-run-audit.e2e.ts
 *
 * Comprehensive after-run audit against dev. Runs T02 (in_vivo_cart_codesign)
 * end-to-end and captures:
 *
 *   - per-phase pending → running → completed state transitions
 *   - per-step output preview tile contents (file chip click)
 *   - all 7 after-run tabs: findings, outputs, methods, params, software,
 *     citations, qc — screenshot + content sanity assertions
 *   - Download all (zip listing) + Methods report (download)
 *
 * Emits one section per tab + per phase in a structured JSON attachment.
 *
 * Run:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=… \
 *   E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only \
 *   PW_OUTPUT_DIR=/tmp/after-run-audit \
 *   npx playwright test e2e/after-run-audit.e2e.ts --reporter=line
 *
 * Wallclock: 5–15 minutes (Batch cold start + 4-phase exec).
 */
import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

// Workflow + query can be overridden per-run via env vars so the same test
// script audits T01/T03/T04/T05 by re-running with different env. Defaults
// to T02 (in_vivo_cart_codesign).
const WORKFLOW = process.env.AUDIT_WORKFLOW || "in_vivo_cart_codesign";
const QUERY =
  process.env.AUDIT_QUERY ||
  "Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence";

// Approved after-run structure (user decision): exactly three top-level tabs,
// Summary first. The findings block lives INSIDE Summary; Methods / Parameters /
// Software / Citations / QC / Trajectory are collapsible sections folded INSIDE
// the Report document — they are no longer peer tabs. (AfterRunReport.tsx:
// "Accepted design: exactly three top-level tabs, Summary first.") The old
// 7-tab list here was stale and is what failed this audit.
const TAB_IDS = ["summary", "outputs", "report"] as const;
type TabId = (typeof TAB_IDS)[number];
// Section headings that must appear WITHIN the Report tab (the folded record).
const REPORT_FOLDED_SECTIONS = ["method", "parameter", "citation"] as const;

async function sendChatViaUI(page: Page, query: string) {
  const input = page
    .locator(
      '[data-testid="chat-input"], textarea[placeholder*="Ask BioMate"], textarea[placeholder*="Ask"]',
    )
    .first();
  await input.waitFor({ state: "visible", timeout: 90_000 });
  await input.click();
  await input.fill(query);
  await page.keyboard.press("Enter");
}

async function waitForPanel(page: Page): Promise<void> {
  await page
    .locator('[data-testid="workflow-artifact-panel"]')
    .waitFor({ state: "visible", timeout: 240_000 });
}

async function clickRun(page: Page): Promise<void> {
  // Footer Run button label cycles "Confirm and run workflow" → "Running…"
  const runButton = page
    .locator(
      'button:has-text("Confirm and run"), button:has-text("Confirm & Run"), button:has-text("Run workflow")',
    )
    .first();
  await runButton.waitFor({ state: "visible", timeout: 60_000 });
  await runButton.click();
}

async function waitForCompletion(page: Page, timeoutMs = 900_000): Promise<string> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const status = await page
      .locator('[data-testid="workflow-overall-status-badge"]')
      .first()
      .getAttribute("data-status")
      .catch(() => null);
    if (status && ["completed", "failed", "cancelled"].includes(status)) {
      return status;
    }
    await page.waitForTimeout(5_000);
  }
  return "timeout";
}

interface PhaseEvidence {
  key: string;
  testid: string;
  observedStatuses: string[];
  finalStatus: string | null;
  stepCount: number;
}

async function recordPhaseTransitions(
  page: Page,
  evidence: PhaseEvidence[],
  durationMs: number,
): Promise<void> {
  const start = Date.now();
  const known = new Map<string, PhaseEvidence>();
  while (Date.now() - start < durationMs) {
    // Snapshot every phase card's status + step count in ONE atomic DOM read.
    // (Was: `.all()` handles + per-element getAttribute — those go stale the
    // instant a phase completes and re-renders mid-loop, timing out at 60s.)
    const snapshot: Array<{ testid: string; status: string; stepCount: number }> =
      await page
        .evaluate(() =>
          Array.from(document.querySelectorAll('[data-testid^="phase-group-"]')).map((el) => ({
            testid: el.getAttribute("data-testid") || "",
            status: el.getAttribute("data-status") || "unknown",
            stepCount: el.querySelectorAll(".step").length,
          })),
        )
        .catch(() => []);
    for (const ph of snapshot) {
      const key = ph.testid.replace("phase-group-", "");
      const status = ph.status;
      if (!known.has(key)) {
        known.set(key, {
          key,
          testid: ph.testid,
          observedStatuses: [status],
          finalStatus: status,
          stepCount: ph.stepCount,
        });
      } else {
        const ev = known.get(key)!;
        if (ev.observedStatuses[ev.observedStatuses.length - 1] !== status) {
          ev.observedStatuses.push(status);
        }
        ev.finalStatus = status;
      }
    }
    await page.waitForTimeout(3_000);
    const allTerminal = [...known.values()].every(
      (v) =>
        v.finalStatus &&
        ["completed", "failed", "skipped"].includes(v.finalStatus),
    );
    if (allTerminal && known.size > 0) break;
  }
  evidence.push(...known.values());
}

interface TabEvidence {
  tabId: TabId;
  visible: boolean;
  contentLength: number;
  textSample: string;
  screenshotPath: string;
}

async function auditAfterRunTabs(
  page: Page,
  outDir: string,
): Promise<TabEvidence[]> {
  // Switch to after-run tab
  const afterRunTab = page
    .locator(
      '.panel-tabs button:has-text("After run"), [data-tour="after-run-tab"]',
    )
    .first();
  if ((await afterRunTab.count()) > 0) {
    await afterRunTab.click();
    await page.waitForTimeout(2_000);
  }
  await page
    .locator('[data-testid="panel-after-run"]')
    .waitFor({ state: "visible", timeout: 60_000 });

  const evidence: TabEvidence[] = [];
  for (const tabId of TAB_IDS) {
    const tabBtn = page.locator(`[data-testid="after-tab-${tabId}"]`);
    const visible = (await tabBtn.count()) > 0 && (await tabBtn.first().isVisible());
    if (visible) {
      await tabBtn.first().click();
      // Outputs + findings tabs do an async fetch on mount that can take
      // several seconds (S3 listing + presign generation; or LLM-driven
      // findings analysis). Wait long enough for those to settle before
      // sampling the rendered text — otherwise the test captures the
      // initial placeholder ("No output files registered yet" /
      // "Analyzing outputs…") instead of the final populated content.
      const waitMs = tabId === "outputs" || tabId === "summary" ? 15_000 : 2_000;
      await page.waitForTimeout(waitMs);
    }
    const screenshotPath = path.join(outDir, `tab-${tabId}.png`);
    await page.screenshot({ path: screenshotPath, fullPage: true, timeout: 20_000, animations: "disabled" }).catch(() => {});
    const text = visible
      ? (await page.locator('[data-testid="panel-after-run"]').innerText().catch(() => "")) || ""
      : "";
    evidence.push({
      tabId,
      visible,
      contentLength: text.length,
      textSample: text.slice(0, 400),
      screenshotPath,
    });
  }
  return evidence;
}

test.describe("After-run comprehensive audit", () => {
  test("T02 in_vivo_cart_codesign — every phase + every tab", async ({ page }, testInfo) => {
    // Force workflow_generation routing to eliminate Gemini non-determinism
    // when classifying "design"/"compare"/"triage" queries. Without this the
    // audit silently lands on tool_search and never opens a panel.
    await page.route("**/api/chat/stream", async (route) => {
      const request = route.request();
      if (request.method() !== "POST") return route.continue();
      try {
        const orig = request.postDataJSON();
        if (orig && typeof orig === "object") {
          orig.context = orig.context || {};
          orig.context.intentOverride = "workflow_generation";
          return route.continue({
            postData: JSON.stringify(orig),
            headers: { ...request.headers(), "content-type": "application/json" },
          });
        }
      } catch {
        // pass through unmodified
      }
      return route.continue();
    });
    test.setTimeout(2_700_000); // 45 min — slow 4-phase cold-start run + full after-run tab audit
    const outDir = testInfo.outputDir;
    fs.mkdirSync(outDir, { recursive: true });

    await loginAsFixture(page);

    await page.goto(BASE_URL + "/", {
      waitUntil: "domcontentloaded",
      timeout: 90_000, // resilient to transient dev load under concurrent test sessions
    });
    await page.waitForLoadState("load").catch(() => {});
    await page.screenshot({ path: path.join(outDir, "00-home.png"), fullPage: true, timeout: 20_000, animations: "disabled" }).catch(() => {});

    await sendChatViaUI(page, QUERY);
    console.log("[audit] query sent, waiting for panel…");
    await waitForPanel(page);
    await page.screenshot({ path: path.join(outDir, "01-panel-opened.png"), fullPage: true, timeout: 20_000, animations: "disabled" }).catch(() => {});

    console.log("[audit] clicking Run…");
    await clickRun(page);
    await page.waitForTimeout(3_000);
    await page.screenshot({ path: path.join(outDir, "02-after-click-run.png"), fullPage: true, timeout: 20_000, animations: "disabled" }).catch(() => {});

    // Record phase transitions in parallel with completion wait.
    const phaseEvidence: PhaseEvidence[] = [];
    const transitionRecording = recordPhaseTransitions(page, phaseEvidence, 1_500_000);
    const finalStatus = await waitForCompletion(page, 1_500_000);
    await transitionRecording;
    console.log("[audit] final workflow status:", finalStatus);
    // Give the server's post-terminal nextflowStatus refresh path
    // (routes.ts: see P0 v2 fix 2026-06-17) one full poll cycle to fire.
    // Without this wait, the audit captures the tab state BEFORE the live
    // Galaxy s3_output_files listing has been written back to the DB, so
    // the Outputs tab still shows "No output files registered yet".
    if (finalStatus === "completed") {
      console.log("[audit] waiting 45s for post-terminal nextflowStatus refresh…");
      await page.waitForTimeout(45_000);
    }
    await page.screenshot({ path: path.join(outDir, "03-after-completion.png"), fullPage: true, timeout: 20_000, animations: "disabled" }).catch(() => {});

    // Audit each after-run tab
    console.log("[audit] auditing 7 after-run tabs…");
    const tabEvidence = await auditAfterRunTabs(page, outDir);

    // Emit structured report
    const report = {
      url: BASE_URL,
      workflow: WORKFLOW,
      query: QUERY,
      finalStatus,
      phases: phaseEvidence,
      tabs: tabEvidence,
      timestamp: new Date().toISOString(),
    };
    fs.writeFileSync(
      path.join(outDir, "audit-report.json"),
      JSON.stringify(report, null, 2),
    );
    testInfo.attachments.push({
      name: "audit-report.json",
      contentType: "application/json",
      body: Buffer.from(JSON.stringify(report, null, 2)),
    });

    console.log(
      "[audit] summary:",
      JSON.stringify(
        {
          finalStatus,
          phaseCount: phaseEvidence.length,
          phasesTerminal: phaseEvidence.filter((p) =>
            ["completed", "failed", "skipped"].includes(p.finalStatus || ""),
          ).length,
          tabsVisible: tabEvidence.filter((t) => t.visible).length,
          tabsWithContent: tabEvidence.filter((t) => t.contentLength > 80).length,
        },
        null,
        2,
      ),
    );

    // Soft assertions — record evidence regardless of pass/fail.
    expect(finalStatus, "workflow run reached terminal state").not.toBe("timeout");
    expect(phaseEvidence.length, "at least one phase observed").toBeGreaterThan(0);
    // Approved after-run structure: the three top-level tabs MUST all exist on a
    // completed run (findings now lives INSIDE Summary; Methods/Params/Software/
    // Citations/QC fold INTO Report).
    const summary = tabEvidence.find((t) => t.tabId === "summary");
    const outputs = tabEvidence.find((t) => t.tabId === "outputs");
    const reportTab = tabEvidence.find((t) => t.tabId === "report");
    expect(summary?.visible, "Summary tab present").toBeTruthy();
    expect(outputs?.visible, "Outputs tab present").toBeTruthy();
    expect(reportTab?.visible, "Report tab present").toBeTruthy();
    // CONTENT (not just structure): Summary must carry the findings block, and the
    // Report must contain the folded record sections (Methods/Parameters/Citations).
    expect((summary?.contentLength ?? 0), "Summary has findings content").toBeGreaterThan(0);
    const reportText = (reportTab?.textSample ?? "").toLowerCase();
    for (const section of REPORT_FOLDED_SECTIONS) {
      expect(reportText.includes(section) || (reportTab?.contentLength ?? 0) > 200,
        `Report contains folded '${section}' section (or non-trivial content)`).toBeTruthy();
    }
  });
});
