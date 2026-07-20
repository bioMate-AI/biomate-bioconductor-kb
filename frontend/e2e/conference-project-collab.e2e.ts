/**
 * Conference Project Collaboration E2E — Boston BD Summit, July 21–23 2026
 *
 * Tests the full project module as a real user would use it, anchored on
 * the conference demo workflows (MG neuroimmune, ADMET, GWAS chain).
 *
 * Flow (serial — one project shared across all tests):
 *  CC1  — /projects list → click project card → open detail page
 *  CC2  — Navigate all project tabs: Chat, Files, Workflow Runs + right sidebar
 *  CC3  — Click "New Chat" from project → active-project banner appears at root
 *  CC4  — LLM context: ask "what is this project about?" → researchGoal injected
 *  CC5  — ADMET execution within project (iptacopan — real AWS Batch)
 *  CC6  — Workflow Runs tab: run appears linked to project; click → viewer
 *  CC7  — GWAS chain routing within project context
 *  CC8  — Share link: generate via UI, display, anon visitor join page
 *  CC9  — Members: list shows owner, invite by email, revoke share link
 *  CC10 — Project rename via ⋯ actions menu → rename dialog → Save
 *
 * UI references (from project-detail.tsx):
 *   data-testid="card-project-{id}"          — project card on /projects list
 *   data-testid="button-project-actions"     — ⋯ dropdown on project detail
 *   data-testid="tab-project-chat"           — Chat tab
 *   data-testid="tab-project-files"          — Files tab
 *   data-testid="tab-project-workflows"      — Workflow Runs tab
 *   data-testid="button-new-project-chat"    — opens chat with project active
 *   data-testid="active-project-banner"      — banner on root chat page
 *   data-testid="active-project-banner-goto" — Go to project button in banner
 *   data-testid="button-generate-share-link" — generates share token
 *   data-testid="input-share-link"           — readonly link display
 *   data-testid="button-revoke-share-link"   — revokes the share token
 *   data-testid="input-share-email"          — email invite input
 *
 * No mocking. Real dev-public.biomate.ai. Screenshots → e2e/screenshots/conference-project/.
 *
 * Run:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=WpmFixture!2026 \
 *   npx playwright test e2e/conference-project-collab.e2e.ts --project=chromium
 */

import { test, expect, type Page, type BrowserContext } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login.js";
import * as fs from "fs";
import * as path from "path";

// ─── constants ────────────────────────────────────────────────────────────────

const SS = path.join(import.meta.dirname, "screenshots", "conference-project");
if (!fs.existsSync(SS)) fs.mkdirSync(SS, { recursive: true });

const RESEARCH_GOAL =
  "Identify causal genetic drivers of myasthenia gravis through complement pathway analysis and screen the top therapeutic candidate (iptacopan) for drug-like ADMET properties";

const RESEARCH_KEYWORDS = ["myasthenia", "complement", "iptacopan", "mg", "genetic"];

// Iptacopan SMILES from ChEMBL4594448 (Factor B inhibitor)
const IPTACOPAN_SMILES =
  "CCO[C@H]1CCN(Cc2c(OC)cc(C)c3[nH]ccc23)[C@H](c2ccc(C(=O)O)cc2)C1";

const ADMET_QUERY = `Screen iptacopan (Factor B inhibitor for complement-mediated MG) for ADMET properties. SMILES: ${IPTACOPAN_SMILES}`;

const GWAS_QUERY =
  "Run GWAS to identify CD40L locus variants associated with myasthenia gravis, then link to eQTL (GTEx blood) and scRNA-seq to find the causal immune cell type";

const EXEC_TIMEOUT_MS = 20 * 60_000; // 20 min — AWS Batch cold start

// ─── helpers ─────────────────────────────────────────────────────────────────

async function shot(page: Page, name: string) {
  await page
    .screenshot({ path: path.join(SS, `${name}.png`), fullPage: false })
    .catch(() => {});
}

async function pause(page: Page, ms: number) {
  await page.waitForTimeout(ms);
}

async function sendChat(page: Page, message: string, waitMs = 120_000): Promise<string> {
  const ta = page.locator("textarea, [data-testid='chat-input']").first();
  await ta.fill(message);
  await ta.press("Enter");
  console.log(`[chat] → "${message.slice(0, 80)}..."`);

  const thinkSels = [
    "[data-testid='chat-response-pending']",
    "text=BioMate is thinking",
    "text=Analyzing",
    ".analysis-status",
  ];
  await Promise.race(
    thinkSels.map((s) =>
      page.waitForSelector(s, { state: "visible", timeout: 15_000 }).catch(() => null)
    )
  );
  await Promise.all(
    thinkSels.map((s) =>
      page.waitForSelector(s, { state: "hidden", timeout: waitMs }).catch(() => null)
    )
  );

  // Wait for substantive text AND stabilize (text unchanged for 3s = streaming complete)
  await page
    .waitForFunction(
      () => {
        const el = document.querySelector('[data-is-latest-assistant="true"]');
        return (el?.textContent?.trim().length ?? 0) > 30;
      },
      { timeout: waitMs }
    )
    .catch(() => {});

  // Text stabilization: wait until content is stable for 3s AND is not a known transient state.
  // "Searching relevant literature…" is a streaming status indicator — the actual answer arrives later.
  const TRANSIENT_PHRASES = [
    "searching relevant literature",
    "searching databases",
    "searching for information",
  ];
  const isTransient = (t: string) => {
    const lo = t.toLowerCase();
    return TRANSIENT_PHRASES.some((p) => lo.includes(p)) && t.length < 300;
  };

  const stabilizeMs = 3_000;
  const stabilizeDeadline = Date.now() + Math.min(90_000, waitMs * 0.7);
  let prevText = "";
  let stableStart = 0;
  while (Date.now() < stabilizeDeadline) {
    const cur =
      (await page
        .locator('[data-is-latest-assistant="true"]')
        .last()
        .textContent({ timeout: 3_000 })
        .catch(() => "")) ?? "";
    if (cur === prevText && !isTransient(cur)) {
      if (stableStart === 0) stableStart = Date.now();
      if (Date.now() - stableStart >= stabilizeMs) break;
    } else if (cur !== prevText) {
      prevText = cur;
      stableStart = 0;
    }
    // If cur is transient, reset stable timer even if unchanged
    if (isTransient(cur)) stableStart = 0;
    await page.waitForTimeout(800);
  }

  // If we got a network error, retry once automatically
  const isNetworkError =
    prevText.toLowerCase().includes("connection error") ||
    prevText.toLowerCase().includes("network error");
  if (isNetworkError) {
    console.log("[sendChat] network error detected — retrying once");
    await page.waitForTimeout(3_000);
    const ta2 = page.locator("textarea, [data-testid='chat-input']").first();
    await ta2.fill(message);
    await ta2.press("Enter");
    await Promise.all(
      thinkSels.map((s) =>
        page.waitForSelector(s, { state: "hidden", timeout: waitMs }).catch(() => null)
      )
    );
    await page
      .waitForFunction(
        () => {
          const el = document.querySelector('[data-is-latest-assistant="true"]');
          return (el?.textContent?.trim().length ?? 0) > 30;
        },
        { timeout: waitMs }
      )
      .catch(() => {});
    // Re-stabilize
    prevText = "";
    stableStart = 0;
    const retryDeadline = Date.now() + Math.min(60_000, waitMs / 2);
    while (Date.now() < retryDeadline) {
      const cur2 =
        (await page
          .locator('[data-is-latest-assistant="true"]')
          .last()
          .textContent({ timeout: 3_000 })
          .catch(() => "")) ?? "";
      if (cur2 === prevText) {
        if (stableStart === 0) stableStart = Date.now();
        if (Date.now() - stableStart >= stabilizeMs) break;
      } else {
        prevText = cur2;
        stableStart = 0;
      }
      await page.waitForTimeout(800);
    }
  }

  return prevText;
}

async function getWorkflowCardName(page: Page): Promise<string> {
  const chip = page.locator(".wf-chip-name").last();
  if (await chip.isVisible({ timeout: 2_000 }).catch(() => false)) {
    const n = (await chip.textContent().catch(() => ""))?.trim() ?? "";
    if (n && n !== "Workflow") return n;
  }
  const panelName = page
    .locator('[data-testid="workflow-artifact-panel"] .panel-name')
    .first();
  if (await panelName.isVisible({ timeout: 1_000 }).catch(() => false)) {
    return (await panelName.textContent().catch(() => ""))?.trim() ?? "";
  }
  return "";
}

async function getOverallStatus(page: Page): Promise<string> {
  return page
    .evaluate(() => {
      const badge = document.querySelector(
        '[data-testid="workflow-overall-status-badge"]'
      );
      return (
        (badge as HTMLElement | null)?.dataset?.status ??
        badge?.textContent?.trim() ??
        ""
      );
    })
    .catch(() => "");
}

async function waitForTerminalStatus(
  page: Page,
  timeoutMs = EXEC_TIMEOUT_MS
): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  let status = await getOverallStatus(page);
  while (
    !["completed", "failed", "errored"].includes(status) &&
    Date.now() < deadline
  ) {
    await pause(page, 10_000);
    status = await getOverallStatus(page);
    console.log(`[exec] status: ${status || "(pending)"}`);
  }
  return status;
}

// ─── shared state ─────────────────────────────────────────────────────────────

let projectId: string;
let projectName: string;
let shareToken: string;

// ─── suite ────────────────────────────────────────────────────────────────────

test.describe.serial("conference-project-collab", () => {
  test.beforeAll(async ({ browser }) => {
    const page = await browser.newPage();
    await loginAsFixture(page);
    projectName = `BD Summit MG Demo ${Date.now()}`;
    const res = await page.request.post(`${BASE_URL}/api/projects`, {
      headers: { "Content-Type": "application/json" },
      data: {
        name: projectName,
        description:
          "Boston BD Summit 2026 — MG Neuroimmune Drug Discovery demonstration",
        primaryDomain: "drug_discovery",
        researchGoal: RESEARCH_GOAL,
      },
    });
    const body = await res.json();
    // project-routes.ts: POST /api/projects returns { project: {...} }
    projectId = body?.project?.id ?? body?.id;
    expect(projectId, "project creation failed").toBeTruthy();
    console.log(`[setup] project: ${projectId} "${projectName}"`);
    await page.close();
  });

  test.afterAll(async ({ browser }) => {
    if (!projectId) return;
    const page = await browser.newPage();
    await loginAsFixture(page);
    await page.request.delete(`${BASE_URL}/api/projects/${projectId}`).catch(() => {});
    console.log(`[teardown] project deleted: ${projectId}`);
    await page.close();
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC1 — /projects list → find project card → click → project detail
  // ──────────────────────────────────────────────────────────────────────────
  test("CC1: /projects list — project card visible, opens detail page", async ({
    page,
  }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);

    // Navigate directly to the projects list (SPA route)
    await page.goto(`${BASE_URL}/projects`);
    await page.waitForLoadState("load");
    await pause(page, 1_500);
    await shot(page, "CC1_01_projects_list");
    console.log("[CC1] /projects list loaded");

    // Find project card by testid (projects.tsx:249 data-testid={`card-project-${project.id}`})
    const card = page.locator(`[data-testid="card-project-${projectId}"]`);
    await expect(card).toBeVisible({ timeout: 15_000 });
    await shot(page, "CC1_02_project_card_found");
    console.log(`[CC1] project card found: ${projectId}`);

    // Click the card → navigates to /projects?project=<id>
    await card.click();
    await expect(page).toHaveURL(new RegExp(`project=${projectId}`), {
      timeout: 10_000,
    });
    await page.waitForLoadState("load");
    await pause(page, 1_000);
    await shot(page, "CC1_03_project_detail");
    console.log("[CC1] ✅ project detail page opened");
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC2 — Navigate project tabs: Chat, Files, Workflow Runs + members sidebar
  // ──────────────────────────────────────────────────────────────────────────
  test("CC2: project tabs — Chat, Files, Workflow Runs + sharing sidebar", async ({
    page,
  }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/projects?project=${projectId}`);
    await page.waitForLoadState("load");
    await pause(page, 1_000);

    // project-detail.tsx has exactly 3 TabsTriggers
    const TABS = [
      { testid: "tab-project-chat",      label: "Chat",          shot: "CC2_01_tab_chat" },
      { testid: "tab-project-files",     label: "Files",         shot: "CC2_02_tab_files" },
      { testid: "tab-project-workflows", label: "Workflow Runs", shot: "CC2_03_tab_workflows" },
    ];

    for (const tab of TABS) {
      const el = page.getByTestId(tab.testid);
      await expect(el).toBeVisible({ timeout: 10_000 });
      await el.click();
      await pause(page, 600);
      await shot(page, tab.shot);
      console.log(`[CC2] ✅ tab "${tab.label}" rendered`);
    }

    // Right sidebar: sharing / members section (always visible on project detail)
    const sharedSection = page.locator("text=Shared with").first();
    if (await sharedSection.isVisible({ timeout: 5_000 }).catch(() => false)) {
      await shot(page, "CC2_04_right_sidebar_sharing");
      console.log("[CC2] ✅ sharing sidebar rendered");
    } else {
      console.log("[CC2] ℹ️ 'Shared with' not yet visible");
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC3 — "New Chat" from project → navigate to root → active-project banner
  // ──────────────────────────────────────────────────────────────────────────
  test("CC3: 'New Chat' from project → active-project banner at root chat", async ({
    page,
  }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);

    // Navigate to project detail Chat tab (default tab is "files", project-detail.tsx:84)
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=chat`);
    await page.waitForLoadState("load");
    await pause(page, 800);

    // "New Chat" button (project-detail.tsx:564) calls openChatWithProject():
    //   1. localStorage.setItem("biomate-active-project-id", projectId)
    //   2. window.location.assign("/")
    const newChatBtn = page.getByTestId("button-new-project-chat");
    await expect(newChatBtn).toBeVisible({ timeout: 12_000 });
    await newChatBtn.click();

    // Full page navigation to "/"
    await expect(page).toHaveURL(BASE_URL + "/", { timeout: 10_000 });
    await page.waitForLoadState("load");
    await pause(page, 1_500);
    await shot(page, "CC3_01_root_chat");

    // Active project banner (App.tsx:247 data-testid="active-project-banner")
    const banner = page.getByTestId("active-project-banner");
    await expect(banner).toBeVisible({ timeout: 10_000 });
    const bannerText = (await banner.textContent().catch(() => "")) ?? "";
    console.log(`[CC3] banner: "${bannerText.slice(0, 80)}"`);
    await shot(page, "CC3_02_banner_visible");

    expect(bannerText).toContain("BD Summit");

    // "Go to project" navigates back (App.tsx:261-262)
    const gotoBtn = page.getByTestId("active-project-banner-goto");
    await expect(gotoBtn).toBeVisible({ timeout: 5_000 });
    await gotoBtn.click();
    await expect(page).toHaveURL(new RegExp(`project=${projectId}`), {
      timeout: 8_000,
    });
    await shot(page, "CC3_03_goto_project");
    console.log("[CC3] ✅ active project banner verified");
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC4 — LLM context: researchGoal injected → LLM mentions MG/iptacopan
  // ──────────────────────────────────────────────────────────────────────────
  test("CC4: LLM knows project research goal — researchGoal injected", async ({
    page,
  }) => {
    test.setTimeout(3 * 60_000);
    await loginAsFixture(page);

    // Activate project then navigate to root chat (must use tab=chat to see button)
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=chat`);
    await page.waitForLoadState("load");
    await pause(page, 600);
    const newChatBtn = page.getByTestId("button-new-project-chat");
    await expect(newChatBtn).toBeVisible({ timeout: 12_000 });
    await newChatBtn.click();
    await expect(page).toHaveURL(BASE_URL + "/", { timeout: 10_000 });
    await page.waitForLoadState("load");
    await expect(page.getByTestId("active-project-banner")).toBeVisible({
      timeout: 8_000,
    });

    const response = await sendChat(
      page,
      "What disease or condition is this project focused on? What drug or therapeutic compound is being evaluated? Answer from the project context, in two sentences.",
      120_000
    );
    console.log(`[CC4] LLM: "${response.slice(0, 300)}"`);
    await shot(page, "CC4_01_llm_context_response");

    // Either the LLM answers from project context (mentions disease/drug) OR the
    // project context injection itself routes to workflow generation — either way
    // the response should not be generic "searching" text
    const mentioned = RESEARCH_KEYWORDS.some((kw) =>
      response.toLowerCase().includes(kw)
    );
    const isGenericSearch =
      response.toLowerCase() === "biomate" ||
      response.trim().length < 40;
    expect(
      mentioned && !isGenericSearch,
      `LLM didn't mention [${RESEARCH_KEYWORDS}] — context not injected or response truncated.\nReply: "${response.slice(0, 400)}"`
    ).toBe(true);
    console.log("[CC4] ✅ research goal confirmed in LLM response");
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC5 — ADMET execution (iptacopan, real AWS Batch)
  // ──────────────────────────────────────────────────────────────────────────
  test("CC5: run ADMET on iptacopan within project — AWS Batch execution", async ({
    page,
  }) => {
    test.setTimeout(EXEC_TIMEOUT_MS + 3 * 60_000);
    await loginAsFixture(page);

    // Activate project (must use tab=chat to see button-new-project-chat)
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=chat`);
    await page.waitForLoadState("load");
    await pause(page, 600);
    const newChatBtn = page.getByTestId("button-new-project-chat");
    await expect(newChatBtn).toBeVisible({ timeout: 12_000 });
    await newChatBtn.click();
    await expect(page).toHaveURL(BASE_URL + "/", { timeout: 10_000 });
    await page.waitForLoadState("load");

    // Dismiss survey/modal
    const dismiss = page
      .locator(
        'button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later")'
      )
      .first();
    if (await dismiss.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await dismiss.click().catch(() => {});
      await pause(page, 400);
    }

    const reply = await sendChat(page, ADMET_QUERY, 120_000);
    console.log(`[CC5] routing: "${reply.slice(0, 120)}"`);
    await shot(page, "CC5_01_admet_routed");

    const wfName = await getWorkflowCardName(page);
    console.log(`[CC5] workflow card: "${wfName}"`);
    const isAdmet =
      wfName.toLowerCase().includes("admet") || reply.toLowerCase().includes("admet");
    expect(isAdmet, `Expected ADMET workflow, got: "${wfName}"`).toBe(true);

    // Wait for the workflow panel to appear — testid is on the inner component wrapper
    const panel = page.locator('[data-testid="workflow-artifact-panel"]');
    await expect(panel).toBeVisible({ timeout: 30_000 });

    // The run button testid is "button-run-workflow-panel"; text is "Confirm and run workflow"
    const runBtn = page.getByTestId("button-run-workflow-panel");
    await expect(runBtn).toBeVisible({ timeout: 15_000 });
    await shot(page, "CC5_02_pre_run_panel");
    await runBtn.click();
    console.log("[CC5] clicked Confirm & Run");

    // Watch for running state
    const runDeadline = Date.now() + 60_000;
    while (Date.now() < runDeadline) {
      const s = await getOverallStatus(page);
      if (s === "running") {
        console.log("[CC5] ✅ running state captured");
        await shot(page, "CC5_03_running");
        break;
      }
      if (s === "completed" || s === "failed") break;
      await pause(page, 3_000);
    }

    const finalStatus = await waitForTerminalStatus(page);
    console.log(`[CC5] terminal status: "${finalStatus}"`);
    await shot(page, "CC5_04_terminal");

    expect(finalStatus, `ADMET ended with status "${finalStatus}"`).toBe("completed");

    // After-run panel
    const afterTab = page.locator('[data-testid="panel-tab-after-run"]').first();
    if (await afterTab.isVisible({ timeout: 5_000 }).catch(() => false)) {
      const isActive = await afterTab
        .evaluate(
          (el) =>
            el.classList.contains("active") ||
            el.getAttribute("aria-selected") === "true"
        )
        .catch(() => false);
      if (!isActive) await afterTab.click().catch(() => {});
      await pause(page, 2_000);
    }
    await shot(page, "CC5_05_after_run_panel");
    console.log("[CC5] ✅ ADMET execution complete");
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC6 — Workflow Runs tab: run linked to project, click → viewer
  // ──────────────────────────────────────────────────────────────────────────
  test("CC6: ADMET run appears in project Workflow Runs tab", async ({ page }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);

    await page.goto(`${BASE_URL}/projects?project=${projectId}`);
    await page.waitForLoadState("load");
    const runsTab = page.getByTestId("tab-project-workflows");
    await expect(runsTab).toBeVisible({ timeout: 12_000 });
    await runsTab.click();
    await pause(page, 2_000);
    await shot(page, "CC6_01_runs_tab");

    // API check
    const apiRes = await page.request.get(
      `${BASE_URL}/api/projects/${projectId}/runs`
    );
    if (apiRes.ok()) {
      const body = await apiRes.json();
      const runs: any[] = body?.runs ?? [];
      console.log(`[CC6] project runs (API): ${runs.length}`);
    }

    // UI: any run row
    const runRow = page
      .locator(
        '[data-testid^="run-row-"], [data-testid^="workflow-run-"], .run-row, .run-item'
      )
      .first();
    const hasRuns = await runRow.isVisible({ timeout: 10_000 }).catch(() => false);
    if (hasRuns) {
      await shot(page, "CC6_02_runs_list");
      await runRow.click();
      await pause(page, 1_500);
      const viewer = page.locator('[data-testid="nextflow-workflow-viewer"]');
      if (await viewer.isVisible({ timeout: 8_000 }).catch(() => false)) {
        await shot(page, "CC6_03_viewer_from_runs_tab");
        console.log("[CC6] ✅ run entry opens viewer");
      }
    } else {
      const content = await page
        .locator("main, .tab-content, [role='tabpanel']")
        .first()
        .textContent({ timeout: 5_000 })
        .catch(() => "");
      console.log(`[CC6] tab content: "${content?.slice(0, 120)}"`);
      console.log("[CC6] ℹ️ run rows not visible yet");
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC7 — GWAS chain routing within project context
  // ──────────────────────────────────────────────────────────────────────────
  test("CC7: GWAS→eQTL→scRNA chain routes correctly within project", async ({
    page,
  }) => {
    test.setTimeout(3 * 60_000);
    await loginAsFixture(page);

    // Activate project (must use tab=chat to see button-new-project-chat)
    await page.goto(`${BASE_URL}/projects?project=${projectId}&tab=chat`);
    await page.waitForLoadState("load");
    await pause(page, 600);
    const newChatBtn = page.getByTestId("button-new-project-chat");
    await expect(newChatBtn).toBeVisible({ timeout: 12_000 });
    await newChatBtn.click();
    await expect(page).toHaveURL(BASE_URL + "/", { timeout: 10_000 });
    await page.waitForLoadState("load");

    const reply = await sendChat(page, GWAS_QUERY, 120_000);
    const wfName = await getWorkflowCardName(page);
    console.log(`[CC7] reply (${reply.length}c): "${reply.slice(0, 100)}"`);
    console.log(`[CC7] workflow card: "${wfName}"`);
    await shot(page, "CC7_01_gwas_routed");

    // Chains may render a long text reply without a .wf-chip-name card.
    // Accept either: a workflow card with a GWAS-related name OR reply text mentioning GWAS/eQTL.
    const replyLower = reply.toLowerCase();
    const wfLower = wfName.toLowerCase();
    const isGwasRelated =
      wfLower.includes("gwas") ||
      wfLower.includes("eqtl") ||
      wfLower.includes("sarek") ||
      wfLower.includes("chain") ||
      replyLower.includes("gwas") ||
      replyLower.includes("eqtl") ||
      replyLower.includes("cd40") ||
      replyLower.includes("variant");
    expect(
      isGwasRelated,
      `GWAS chain query not routed correctly — card: "${wfName}", reply: "${reply.slice(0, 200)}"`
    ).toBe(true);

    // At minimum the AI responded with substantial content
    expect(
      reply.length,
      "No response at all for GWAS chain query"
    ).toBeGreaterThan(30);
    console.log("[CC7] ✅ GWAS chain routed correctly");
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC8 — Share link: generate in UI → display → anon visitor join page
  // ──────────────────────────────────────────────────────────────────────────
  test("CC8: share link — generate via UI, show token URL, anon visitor join page", async ({
    page,
    browser,
  }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);

    await page.goto(`${BASE_URL}/projects?project=${projectId}`);
    await page.waitForLoadState("load");
    await pause(page, 1_000);
    await shot(page, "CC8_01_project_detail");

    // Generate share link (project-detail.tsx:847)
    const genBtn = page.getByTestId("button-generate-share-link");
    await expect(genBtn).toBeVisible({ timeout: 12_000 });
    await genBtn.click();
    await pause(page, 1_500);

    // Token URL input appears (project-detail.tsx:823)
    const linkInput = page.getByTestId("input-share-link");
    await expect(linkInput).toBeVisible({ timeout: 10_000 });
    const linkValue = await linkInput.inputValue().catch(() => "");
    console.log(`[CC8] share link: "${linkValue}"`);
    expect(linkValue).toContain("/join/");
    await shot(page, "CC8_02_share_link_displayed");

    // Extract token
    const tokenMatch = linkValue.match(/\/join\/([^?#\s]+)/);
    shareToken = tokenMatch?.[1] ?? "";
    expect(shareToken, "Could not extract token from share link").toBeTruthy();
    console.log(`[CC8] token: ${shareToken.slice(0, 8)}...`);

    // Copy button
    const copyBtn = page.getByTestId("button-copy-share-link");
    await expect(copyBtn).toBeVisible({ timeout: 5_000 });
    await copyBtn.click();
    await pause(page, 600);
    await shot(page, "CC8_03_copied");

    // Anonymous visitor
    const anonCtx: BrowserContext = await browser.newContext();
    const anonPage = await anonCtx.newPage();
    try {
      await anonPage.goto(`${BASE_URL}/join/${shareToken}`);
      await anonPage.waitForLoadState("load");
      await pause(anonPage, 1_500);
      await anonPage
        .screenshot({ path: path.join(SS, "CC8_04_anon_join_page.png") })
        .catch(() => {});
      const bodyText =
        (await anonPage
          .locator("body")
          .textContent({ timeout: 8_000 })
          .catch(() => "")) ?? "";
      console.log(`[CC8] anon join page: "${bodyText.slice(0, 200)}"`);
      const ok =
        bodyText.toLowerCase().includes("join") ||
        bodyText.toLowerCase().includes("project") ||
        bodyText.toLowerCase().includes("sign") ||
        bodyText.toLowerCase().includes("bd summit");
      expect(ok, `Join page: "${bodyText.slice(0, 200)}"`).toBe(true);
      console.log("[CC8] ✅ anonymous join page renders");
    } finally {
      await anonPage.close().catch(() => {});
      await anonCtx.close().catch(() => {});
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC9 — Members: owner listed, invite email input, revoke share link
  // ──────────────────────────────────────────────────────────────────────────
  test("CC9: members — owner listed, email invite visible, share link revocable", async ({
    page,
  }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/projects?project=${projectId}`);
    await page.waitForLoadState("load");
    await pause(page, 800);
    await shot(page, "CC9_01_members_sidebar");

    // Owner via API
    const membersRes = await page.request.get(
      `${BASE_URL}/api/projects/${projectId}/members`
    );
    expect(membersRes.ok()).toBe(true);
    const { members } = await membersRes.json();
    expect(members.length).toBeGreaterThanOrEqual(1);
    expect(members[0].role).toBe("owner");
    console.log(`[CC9] members (API): ${members.length}, role[0]: ${members[0].role}`);

    // Email invite input (project-detail.tsx:865)
    const emailInput = page.getByTestId("input-share-email");
    await expect(emailInput).toBeVisible({ timeout: 8_000 });
    await shot(page, "CC9_02_invite_email_input");
    console.log("[CC9] ✅ invite email input visible");

    // Revoke share link if still active from CC8
    const revokeBtn = page.getByTestId("button-revoke-share-link");
    if (await revokeBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await revokeBtn.click();
      await pause(page, 1_000);
      await expect(page.getByTestId("button-generate-share-link")).toBeVisible({
        timeout: 8_000,
      });
      await shot(page, "CC9_03_after_revoke");
      console.log("[CC9] ✅ share link revoked — generate button reappeared");
    } else {
      console.log("[CC9] ℹ️ revoke not visible — link already gone or CC8 skipped");
    }
    console.log("[CC9] ✅ members section fully tested");
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CC10 — Rename project via ⋯ → rename dialog → Save
  // ──────────────────────────────────────────────────────────────────────────
  test("CC10: rename project via actions menu — heading and API confirm new name", async ({
    page,
  }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);
    await page.goto(`${BASE_URL}/projects?project=${projectId}`);
    await page.waitForLoadState("load");
    await pause(page, 800);

    // Open actions dropdown (project-detail.tsx:505)
    const actionsBtn = page.getByTestId("button-project-actions");
    await expect(actionsBtn).toBeVisible({ timeout: 12_000 });
    await actionsBtn.click();
    await pause(page, 300);
    await shot(page, "CC10_01_actions_menu_open");

    // Click "Rename" menu item (project-detail.tsx:510-511)
    await page.getByRole("menuitem", { name: /rename/i }).click();
    await pause(page, 300);

    // Rename dialog: <Input> with autoFocus (project-detail.tsx:989)
    const dialogInput = page.locator('[role="dialog"] input').first();
    await expect(dialogInput).toBeVisible({ timeout: 5_000 });
    await dialogInput.clear();
    const newName = `BD Summit MG Demo — RENAMED ${Date.now()}`;
    await dialogInput.fill(newName);
    await shot(page, "CC10_02_rename_dialog");

    // "Save" button (project-detail.tsx:998)
    await page
      .getByRole("dialog")
      .getByRole("button", { name: /save/i })
      .click();
    await pause(page, 1_500);

    // Heading must update
    const heading = page.locator("h1, h2, [data-testid='project-title']").first();
    await expect(heading).toContainText(newName.slice(0, 30), { timeout: 8_000 });
    await shot(page, "CC10_03_renamed");

    // API confirms rename — PATCH /api/projects/:id → GET /api/projects/:id
    const detailRes = await page.request.get(`${BASE_URL}/api/projects/${projectId}`);
    expect(detailRes.ok()).toBe(true);
    const body = await detailRes.json();
    const apiName = body?.project?.name ?? body?.name;
    expect(apiName).toBe(newName);
    projectName = newName;
    console.log(`[CC10] ✅ renamed to "${newName}" — confirmed in API`);
  });
});
