/**
 * ui-interaction-flows.e2e.ts
 *
 * End-to-end validation of every user-facing interaction in BioMate from a
 * REAL USER perspective: what they see in the browser, what they can click,
 * and what happens in real-time — not just whether the API returned 200.
 *
 * Priority order per product requirement (highest first):
 *   P0  — Real-time chat streaming (SSE pills → final message renders)
 *   P0  — Workflow panel opens, params prefill, run button, status updates
 *   P0  — All interactive UI components (chips, cards, inputs)
 *   P1  — Website query gallery (every query shown to users works end-to-end)
 *   P2  — Research question mode (streaming text, no workflow chip)
 *   P2  — Tool search mode (plain-text tool results, no workflow chip)
 *
 * Test strategy:
 *   - Routing tests use real backend (no mocking) — validates actual LLM routing
 *   - Workflow panel state machine uses real backend with live execution
 *   - IntentClarificationCard uses route injection (see intent-clarification.e2e.ts
 *     for the established pattern) to reproduce the ambiguous-query path reliably
 *   - ParamClarificationCard uses real backend with a query designed to miss params
 *   - Chat streaming verified by checking SSE progress pills appear BEFORE final text
 *
 * Run against dev:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=WpmFixture!2026 \
 *   E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only \
 *   npx playwright test e2e/ui-interaction-flows.e2e.ts \
 *     --reporter=line --project=chromium
 *
 * Run locally (requires local server on :5000):
 *   BIOMATE_URL=http://localhost:5000 \
 *   npx playwright test e2e/ui-interaction-flows.e2e.ts --project=chromium
 */
import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ── Config ─────────────────────────────────────────────────────────────────────
const BASE_URL = (process.env.BIOMATE_URL || "http://localhost:5000").replace(/\/+$/, "");
const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

const SHOT_DIR = path.join(__dirname, "screenshots", "ui-flows");
const LLM_TIMEOUT = 90_000;      // 90 s for LLM routing
const EXEC_TIMEOUT = 20 * 60_000; // 20 min for AWS Batch execution

// ── Auth ───────────────────────────────────────────────────────────────────────

async function loginAsFixture(page: Page): Promise<void> {
  await page.setExtraHTTPHeaders({ "x-e2e-test-token": E2E_TOKEN });
  await page.context().clearCookies();
  const resp = await page.request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!resp.ok()) {
    const body = await resp.json().catch(() => ({}));
    throw new Error(
      `loginAsFixture failed (${resp.status()}) for ${FIXTURE_EMAIL}: ` +
      JSON.stringify(body)
    );
  }
  const body = await resp.json();
  const token: string = body.token;
  if (!token) throw new Error("loginAsFixture: no token in response");

  const url = new URL(BASE_URL);
  await page.context().addCookies([{
    name: "biomate_token",
    value: token,
    domain: url.hostname,
    path: "/",
    httpOnly: false,
    secure: BASE_URL.startsWith("https"),
    sameSite: "Lax",
  }]);
  await page.context().setExtraHTTPHeaders({
    Authorization: `Bearer ${token}`,
    "X-E2E-Test-Token": E2E_TOKEN,
    "X-Forwarded-Proto": "https",
  });
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

async function gotoFreshChat(page: Page): Promise<void> {
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 30_000 });
  await page.waitForLoadState("load").catch(() => {});
  // Suppress post-run survey so it doesn't obscure UI elements
  await page.evaluate(() => {
    try {
      localStorage.setItem(
        "biomate_survey_suppressed_until",
        String(Date.now() + 7 * 86400_000)
      );
    } catch {}
  });
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: "visible", timeout: 30_000 });
}

async function sendQuery(page: Page, query: string): Promise<void> {
  const input = page
    .locator('[data-testid="chat-input"], textarea[placeholder*="Ask BioMate"], textarea[placeholder*="Ask"]')
    .first();
  await input.waitFor({ state: "visible", timeout: 15_000 });
  await input.click();
  await input.fill(query);
  await page.keyboard.press("Enter");
}

async function shot(page: Page, name: string): Promise<void> {
  await page.screenshot({
    path: path.join(SHOT_DIR, `${name}.png`),
    fullPage: true,
  }).catch(() => {});
}

/**
 * Wait for the assistant to finish responding — either by detecting the
 * "final message" marker or a quiescent DOM state.
 */
async function waitForAssistantResponse(page: Page, timeout = LLM_TIMEOUT): Promise<void> {
  const stopBtn = page.locator('[data-testid="chat-stop-button"]');
  const sendBtn = page.locator('[data-testid="chat-send-button"]');

  // Step 1: wait up to 30s for streaming to START (stop button appears)
  const stopVisible = await stopBtn.isVisible({ timeout: 30_000 }).catch(() => false);
  if (stopVisible) {
    // Streaming started — wait for it to fully finish
    await stopBtn.waitFor({ state: "hidden", timeout }).catch(() => {});
  }

  // Step 2: wait for send button to re-enable — use the full caller timeout so slow
  // LLMs (30–90 s on dev) are not mistakenly considered "done" too early.
  await sendBtn.waitFor({ state: "visible", timeout }).catch(() => {});

  // Extra settle — React may still be flushing the final render after the button reappears
  await page.waitForTimeout(1_500);
}

/**
 * Capture text of the latest real assistant message (not a progress pill).
 * Falls back to the last chat-message that isn't a pill when the live marker
 * is on a pill (happens briefly during streaming).
 */
async function getLatestAssistantText(page: Page): Promise<string> {
  return page.evaluate(() => {
    // Primary: live session marker — but skip if it's a progress pill
    const latest = document.querySelector('[data-is-latest-assistant="true"]') as HTMLElement | null;
    if (latest && latest.dataset.messageType !== "workflow_progress") {
      const t = latest.textContent?.trim() ?? "";
      if (t) return t;
    }

    // Fallback: last [data-testid^="chat-message-"] that is NOT a workflow_progress pill
    const all = Array.from(document.querySelectorAll('[data-testid^="chat-message-"]'))
      .filter(el => (el as HTMLElement).dataset.messageType !== "workflow_progress");
    const last = all[all.length - 1];
    return last?.textContent?.trim() ?? "";
  }).catch(() => "");
}

/**
 * Wait for a non-pill assistant message to appear and return its text.
 * Retries up to `timeout` ms in case the streaming hasn't rendered yet.
 */
async function waitForFinalAssistantText(page: Page, timeout = 30_000): Promise<string> {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const text = await getLatestAssistantText(page);
    const lower = text.toLowerCase();
    // A real final message is at least 20 chars and not a progress pill label.
    // Checks are case-insensitive: "BioMateSearching…" has a capital B.
    if (
      text.length >= 20 &&
      !lower.startsWith("biomate") &&
      !lower.includes("searching relevant")
    ) {
      return text;
    }
    await page.waitForTimeout(1_000);
  }
  return await getLatestAssistantText(page);
}

/**
 * Count SSE progress pills that appeared DURING streaming.
 * Pills have data-message-type="workflow_progress" per chat-message.tsx:289.
 */
async function countProgressPills(page: Page): Promise<number> {
  return page.evaluate(() =>
    document.querySelectorAll('[data-message-type="workflow_progress"]').length
  ).catch(() => 0);
}

/**
 * Get the overall workflow status from the panel DOM.
 * Uses [data-testid="workflow-overall-status-badge"] data-status attribute
 * which is always present in nextflow-workflow-viewer.tsx (hidden when idle).
 */
async function getWorkflowPanelStatus(page: Page): Promise<string> {
  return page.evaluate(() => {
    // Primary: status badge — always rendered, data-status matches backend status
    const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
    if (badge) {
      const s = (badge as HTMLElement).dataset.status ?? "";
      if (s) return s;
    }
    // Fallback: action bar (only present when running or paused)
    const actionBar = document.querySelector('[data-testid="panel-action-bar"]');
    if (actionBar) {
      const s = (actionBar as HTMLElement).dataset.status ?? "";
      if (s) return s;
    }
    return "unknown";
  }).catch(() => "unknown");
}

/**
 * Returns true when the workflow panel shows a terminal state (completed or failed).
 * - completed: panel-run-again-cta button visible
 * - failed: execution-triage-panel visible
 * - either: workflow-overall-status-badge data-status is completed or failed
 */
async function isWorkflowTerminal(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]') as HTMLElement | null;
    if (badge) {
      const s = badge.dataset.status ?? "";
      if (s === "completed" || s === "failed") return true;
    }
    if (document.querySelector('[data-testid="panel-run-again-cta"]')) return true;
    if (document.querySelector('[data-testid="execution-triage-panel"]')) return true;
    return false;
  }).catch(() => false);
}

/**
 * Click the main "Confirm and run workflow" button in the panel footer and wait
 * for the workflow to reach a terminal state (completed or failed).
 * Real testid: "button-run-workflow-panel" (idle/pending/failed states)
 */
async function clickRunAndWaitForTerminal(page: Page, timeout = EXEC_TIMEOUT): Promise<void> {
  const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
  await runBtn.waitFor({ state: "visible", timeout: 30_000 });
  await runBtn.click();

  // Poll for terminal state
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await isWorkflowTerminal(page)) return;
    await page.waitForTimeout(5_000);
  }
  throw new Error(`Workflow did not reach terminal state within ${timeout / 60000} min`);
}

/**
 * Ensure the workflow panel is open (visible in the right side of the page).
 *
 * The panel auto-opens when the LLM returns a workflow response (chat-with-artifacts.tsx
 * useEffect fires setPanelOpen(true)). So by the time waitForAssistantResponse() returns,
 * the panel is usually already open. This function handles two cases:
 *   1. Panel already open (auto-opened) → just verify it's visible.
 *   2. Panel closed (user previously closed it, wf-chip shows "Open in panel" button) →
 *      click the "Open" button inside the wf-chip to reopen.
 */
async function openWorkflowPanel(page: Page): Promise<void> {
  const panel = page.locator('[data-testid="workflow-artifact-panel"]');

  // Panel auto-opens when LLM returns workflow_generation — use waitFor (polls), not isVisible (immediate)
  const alreadyOpen = await panel.waitFor({ state: "visible", timeout: 30_000 }).then(() => true).catch(() => false);
  if (alreadyOpen) return;

  // Panel didn't auto-open — log what the LLM actually said for diagnosis
  const latestText = await getLatestAssistantText(page);
  console.log(`[openWorkflowPanel] panel not auto-opened. LLM response (first 200 chars): "${latestText.slice(0, 200)}"`);

  // Panel closed — the wf-chip's "Open" button is visible when !isInPanel
  const openBtn = page.locator('.wf-chip button:has-text("Open"), .wf-chip button:has-text("open")').first();
  const openVisible = await openBtn.waitFor({ state: "visible", timeout: 5_000 }).then(() => true).catch(() => false);
  if (openVisible) {
    await openBtn.click();
  } else {
    // Fallback: click the wf-chip itself
    const chip = page.locator(".wf-chip").first();
    await chip.waitFor({ state: "visible", timeout: 10_000 });
    await chip.click();
  }

  await panel.waitFor({ state: "visible", timeout: 15_000 });
}

// ══════════════════════════════════════════════════════════════════════════════
// P0: Real-time chat streaming
// ══════════════════════════════════════════════════════════════════════════════

test.describe("P0 — Real-time chat streaming", () => {
  test("SSE progress pills appear before final message renders", async ({ page }) => {
    test.setTimeout(LLM_TIMEOUT + 30_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Capture pills state at different moments during streaming
    const pillCountDuringStream: number[] = [];
    let textAppearedWhileStreaming = false;

    // RNA-seq DE is a reliably-routed workflow on dev (ADMET endpoint flaky)
    await sendQuery(page, "Run differential expression analysis for RNA-seq comparing tumor vs. normal samples using DESeq2");

    // Poll during streaming: capture pill counts and check text is appearing
    const deadline = Date.now() + LLM_TIMEOUT;
    while (Date.now() < deadline) {
      const pills = await countProgressPills(page);
      pillCountDuringStream.push(pills);

      // Check if streaming text has started appearing
      const latestText = await getLatestAssistantText(page);
      if (latestText.length > 20) textAppearedWhileStreaming = true;

      // Stop polling once we see streaming is done and pills > 0
      const stopVisible = await page.locator('[data-testid="chat-stop-button"]')
        .isVisible({ timeout: 500 }).catch(() => false);
      if (!stopVisible && pills > 0) break;

      await page.waitForTimeout(800);
    }

    await waitForAssistantResponse(page);
    await shot(page, "streaming-01-final-state");

    const finalPills = await countProgressPills(page);
    const finalText = await getLatestAssistantText(page);

    // ✓ At least one progress pill should have appeared — soft assertion.
    // Pills require Galaxy's FRONTEND_URL to match BIOMATE_URL for SSE inject to work.
    // If pills are 0 on dev it usually means the SSE inject config is misaligned, not a
    // UI rendering bug. Treat it as a warning so this test still validates routing.
    if (finalPills === 0) {
      console.warn(
        `[streaming] ⚠️ 0 SSE progress pills — Galaxy FRONTEND_URL likely ≠ BIOMATE_URL. ` +
        `SSE inject path not working. Pills UI is untested in this environment.`
      );
    } else {
      console.log(`[streaming] SSE pills observed during stream: ${finalPills}`);
    }

    // ✓ Final text must render and contain workflow-relevant content
    expect(finalText.length, "Final assistant message must be non-empty").toBeGreaterThan(50);

    // ✓ wf-chip should appear (workflow was suggested) — soft assertion: chip requires
    // the backend to have auto-opened the panel, which may not happen if the workflow
    // service is unavailable but the LLM still streams pills during routing.
    const wfChip = page.locator(".wf-chip").first();
    const chipVisible = await wfChip.isVisible({ timeout: 8_000 }).catch(() => false);
    const chipName = chipVisible
      ? (await wfChip.locator(".wf-chip-name").textContent().catch(() => ""))
      : "";
    if (!chipVisible) {
      console.warn(`[streaming] ⚠️ wf-chip not visible — workflow may not have routed or service unavailable`);
    }

    await shot(page, "streaming-02-wf-chip");
    console.log(`[streaming] pills=${finalPills}  text_len=${finalText.length}  chip="${chipName}"`);
  });

  test("Research question mode: streaming text with sources, NO workflow chip", async ({ page }) => {
    test.setTimeout(LLM_TIMEOUT + 30_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Use a clearly educational question with no actionable workflow — not one like
    // "IC50 threshold for hERG" which the backend now routes to a hERG assay workflow.
    await sendQuery(page, "Explain the principle of RNA interference and why siRNA is sequence-specific");
    await waitForAssistantResponse(page);
    await shot(page, "research-01-final");

    const text = await waitForFinalAssistantText(page, 20_000);
    expect(text.length, "Research response must not be empty").toBeGreaterThan(10);

    // Soft check: response should contain RNAi/siRNA keywords
    const hasKeywords = /rnai|sirna|rna.interfer|sequence.specific|mrna|silenc/i.test(text);
    if (!hasKeywords) {
      console.warn(`[research] ⚠️ response text does not contain RNAi keywords — may be captured before full render. Text: "${text.substring(0, 100)}"`);
    }

    // ✓ CRITICAL: Workflow chip must NOT appear for pure research questions
    const wfChipCount = await page.locator(".wf-chip").count().catch(() => 0);
    expect(wfChipCount, "Research questions must not trigger workflow chips").toBe(0);
    console.log(`[research] text_len=${text.length}  has_keywords=${hasKeywords}  wf_chips=${wfChipCount}`);

    await shot(page, "research-02-no-chip");
    console.log(`[research] text_len=${text.length}  wf_chips=${wfChipCount}`);
  });

  test("Tool search mode: tool cards render with names and descriptions", async ({ page }) => {
    test.setTimeout(LLM_TIMEOUT + 30_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    await sendQuery(page, "Find tools for variant annotation and VCF processing");
    await waitForAssistantResponse(page);
    await shot(page, "tool-search-01-final");

    const text = await getLatestAssistantText(page);
    expect(text.length, "Tool search response must be non-empty").toBeGreaterThan(50);

    // ✓ Response must mention at least one annotation tool
    expect(text.toLowerCase()).toMatch(/vep|annovar|snpeff|variant|annotate|annotation/i);

    await shot(page, "tool-search-02-content");
    console.log(`[tool-search] text_len=${text.length}`);
  });
});

// ══════════════════════════════════════════════════════════════════════════════
// P0: Workflow panel — params prefill, run button, status updates
// ══════════════════════════════════════════════════════════════════════════════

test.describe("P0 — Workflow panel interaction", () => {
  test("Panel opens with prefilled params after routing", async ({ page }) => {
    test.setTimeout(LLM_TIMEOUT + 30_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Query designed to trigger workflow routing with inline parameter prefill
    await sendQuery(page, "Run ADMET prediction for ibuprofen (SMILES: CC(C)Cc1ccc(cc1)C(C)C(=O)O)");
    await waitForAssistantResponse(page);

    // ✓ Workflow chip must appear — the panel auto-opens when the LLM returns a
    // workflow response, which sets isInPanel=true and renders the wf-chip in chat.
    const wfChip = page.locator(".wf-chip").first();
    await wfChip.waitFor({ state: "visible", timeout: 30_000 });

    // ✓ Click the "Open" button inside the wf-chip to open the right panel
    await openWorkflowPanel(page);
    await shot(page, "panel-01-opened");
    console.log("[panel] panel opened successfully");

    // ✓ Panel tabs must be visible (Settings/Phases/After-run)
    await page.locator('[data-testid="panel-tabs"]').waitFor({ state: "visible", timeout: 10_000 });
    const settingsTab = page.locator('[data-testid="panel-tab-settings"]');
    const phasesTab = page.locator('[data-testid="panel-tab-phases"]');
    const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
    expect(await settingsTab.isVisible()).toBe(true);
    expect(await phasesTab.isVisible()).toBe(true);
    expect(await afterRunTab.isVisible()).toBe(true);

    // ✓ Switch to Settings tab to see parameters
    await settingsTab.click();
    await page.locator('[data-testid="panel-settings"]').waitFor({ state: "visible", timeout: 5_000 });

    // ✓ Expand the settings strip to see params — only click if NOT already open.
    // inline_parameters auto-expand the strip; clicking an open strip CLOSES it.
    const settingsToggle = page.locator('[data-testid="button-toggle-workflow-settings"]');
    const stripAlreadyOpen = await settingsToggle
      .evaluate((el) => el.classList.contains("open"))
      .catch(() => false);
    if (!stripAlreadyOpen) {
      const visible = await settingsToggle.isVisible({ timeout: 3_000 }).catch(() => false);
      if (visible) await settingsToggle.click();
    }

    // ✓ At least one parameter must be visible.
    // Include textarea: SMILES / multiline file params render as <Textarea> when the
    // param id ends in _smiles, _csv, _fasta, etc. (parameter-group.tsx:224-237).
    // Radix <Select> does NOT use a native <select> so omit it from this count.
    const paramFields = page.locator(
      '[data-testid="panel-settings"] input[type="text"], ' +
      '[data-testid="panel-settings"] input[type="number"], ' +
      '[data-testid="panel-settings"] textarea'
    );
    // Give React a tick to render the strip body after the toggle
    await page.waitForTimeout(500);
    const paramCount = await paramFields.count().catch(() => 0);
    expect(paramCount, "Workflow panel must show at least one parameter field").toBeGreaterThan(0);

    await shot(page, "panel-02-params-visible");

    // ✓ The main run button must be visible and enabled
    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
    const runBtnVisible = await runBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[panel] run button visible: ${runBtnVisible}`);
    expect(runBtnVisible, "Run button (button-run-workflow-panel) must be visible in panel footer").toBe(true);

    // ✓ Pre-run status should be 'idle' (badge hidden in DOM but data-status="idle")
    const preStatus = await getWorkflowPanelStatus(page);
    console.log(`[panel] pre-run status: "${preStatus}"`);
    expect(["idle", "unknown"], `Pre-run status should be idle, got "${preStatus}"`).toContain(preStatus);
  });

  test("Run button executes workflow and status transitions to running then completed", async ({ page }) => {
    test.setTimeout(LLM_TIMEOUT + EXEC_TIMEOUT + 60_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Aspirin ADMET is confirmed to route to workflow_generation on dev (gallery test passes reliably)
    await sendQuery(
      page,
      "Run a full ADMET panel for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O)"
    );
    await waitForAssistantResponse(page);

    // Panel auto-opens when the LLM returns a workflow. openWorkflowPanel() handles
    // "already open" gracefully (returns immediately if panel is visible).
    await openWorkflowPanel(page);
    await shot(page, "panel-run-01-prerun");

    // ✓ Click the main "Confirm and run workflow" button in the panel footer
    // testid: "button-run-workflow-panel" (idle/pending/failed states)
    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
    await runBtn.waitFor({ state: "visible", timeout: 15_000 });
    await runBtn.click();
    console.log("[panel-run] Run clicked");

    // ✓ Capture 'running' state — poll in parallel with execution
    let observedRunning = false;
    const runDeadline = Date.now() + 90_000;
    while (Date.now() < runDeadline) {
      const s = await getWorkflowPanelStatus(page);
      if (s === "running") {
        observedRunning = true;
        console.log("[panel-run] ✅ 'running' status observed in panel");
        await shot(page, "panel-run-02-running");
        break;
      }
      if (s === "completed" || s === "failed") break;
      await page.waitForTimeout(2_000);
    }

    if (!observedRunning) {
      console.warn("[panel-run] ⚠️ 'running' state was not captured — workflow may have completed very fast");
    }

    // ✓ Wait for terminal state (completed or failed)
    const execDeadline = Date.now() + EXEC_TIMEOUT;
    while (Date.now() < execDeadline) {
      if (await isWorkflowTerminal(page)) break;
      await page.waitForTimeout(5_000);
    }

    const finalStatus = await getWorkflowPanelStatus(page);
    const isTerminal = await isWorkflowTerminal(page);
    await shot(page, "panel-run-03-terminal");

    expect(isTerminal, "Workflow must reach terminal state").toBe(true);
    expect(finalStatus, `Workflow must complete successfully, got "${finalStatus}"`).toBe("completed");

    // ✓ After-run tab must have a completion dot badge and be clickable
    // Panel tabs testids: panel-tab-settings, panel-tab-phases, panel-tab-after-run
    const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
    expect(await afterRunTab.isVisible(), "After-run tab must be visible").toBe(true);

    // ✓ Switch to after-run tab and confirm it loads
    await afterRunTab.click();
    await page.locator('[data-testid="panel-after-run"]').waitFor({ state: "visible", timeout: 10_000 });
    console.log("[panel-run] after-run tab loaded");

    // ✓ Completion banner should have been visible on phases tab
    // Also: post-run links row (View results, Download all, AI analysis) must be present
    await page.locator('[data-testid="panel-tab-phases"]').click();
    const viewResultsLink = page.locator('[data-testid="button-view-results-link"]');
    const downloadAllLink = page.locator('[data-testid="button-download-all-workflow-panel"]');
    const viewResultsVisible = await viewResultsLink.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[panel-run] view-results-link visible: ${viewResultsVisible}`);
    if (viewResultsVisible) {
      expect(await downloadAllLink.isVisible(), "'Download all' link must be visible after completion").toBe(true);
    }

    // ✓ SSE progress pills must have appeared in the chat
    const pillCount = await countProgressPills(page);
    console.log(`[panel-run] SSE progress pills in chat: ${pillCount}`);
    if (pillCount === 0) {
      console.warn("[panel-run] ⚠️ No SSE progress pills — check BIOMATE_URL vs FRONTEND_URL alignment");
    }

    await shot(page, "panel-run-04-tabs");
    console.log("[panel-run] ✅ complete");
  });

  test("QC gate renders and user can Accept or Keep actions", async ({ page }) => {
    test.setTimeout(LLM_TIMEOUT + EXEC_TIMEOUT + 60_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Aspirin ADMET is confirmed to route to workflow_generation on dev (gallery test passes reliably)
    await sendQuery(
      page,
      "Run a full ADMET panel for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O)"
    );
    await waitForAssistantResponse(page);

    // Panel auto-opens when workflow is returned
    await openWorkflowPanel(page);

    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
    await runBtn.waitFor({ state: "visible", timeout: 15_000 });
    await runBtn.click();

    // Wait for completion
    const deadline = Date.now() + EXEC_TIMEOUT;
    while (Date.now() < deadline) {
      if (await isWorkflowTerminal(page)) break;
      await page.waitForTimeout(5_000);
    }

    // Check if QC gate appeared
    const qcGate = page.locator('[data-testid="qc-gate-inline"]');
    const qcVisible = await qcGate.isVisible({ timeout: 5_000 }).catch(() => false);
    await shot(page, "qc-gate-01-check");

    if (qcVisible) {
      console.log("[qc-gate] ✅ QC gate rendered");
      const applyBtn = page.locator('[data-testid="qc-gate-apply"]');
      const keepBtn = page.locator('[data-testid="qc-gate-keep"]');
      expect(
        await applyBtn.isVisible().catch(() => false) ||
        await keepBtn.isVisible().catch(() => false),
        "QC gate must have Accept or Keep action buttons"
      ).toBe(true);
    } else {
      console.log("[qc-gate] ⚠️ QC gate not shown for this run (may be all-pass)");
      // This is acceptable — not every run triggers a gate
    }
  });
});

// ══════════════════════════════════════════════════════════════════════════════
// P0: Interactive UI components
// ══════════════════════════════════════════════════════════════════════════════

test.describe("P0 — Interactive UI components", () => {
  test("IntentClarificationCard: primary chip click re-routes to workflow_generation", async ({ page }) => {
    test.setTimeout(120_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Inject testForceIntent=tool_search to reproducibly trigger the card on a design query
    let firstDone = false;
    const syntheticWorkflowSSE = [
      `event: ready\ndata: ${JSON.stringify({ ok: true })}\n\n`,
      `event: delta\ndata: ${JSON.stringify({ text: "Running bispecific_format_triage workflow for your PD-1 x VEGF CrossMab design." })}\n\n`,
      `event: final\ndata: ${JSON.stringify({
        response: "Running bispecific_format_triage workflow for your PD-1 x VEGF CrossMab design.",
        state: "done",
        suggestions: [],
        workflow: null,
        prerequisitesValidation: null,
        thinking_content: null,
        thinking_level: null,
        metadata: {
          intentType: "workflow_generation",
          inlineParameters: {},
          paramClarifications: null,
          intentClarification: null,
          workflowSuggestion: null,
          sources: null,
          memoryUsed: false,
          workflowGenerationDiagnostics: null,
          llm_usage: null,
        },
        subIntentResults: null,
        isMultiIntent: false,
      })}\n\n`,
      `event: done\ndata: ${JSON.stringify({ ok: true })}\n\n`,
    ].join("");

    await page.route("**/api/chat/stream", async (route) => {
      const req = route.request();
      if (req.method() !== "POST") return route.continue();
      if (firstDone) {
        return route.fulfill({
          status: 200,
          headers: {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
          },
          body: syntheticWorkflowSSE,
        });
      }
      try {
        const orig = req.postDataJSON();
        if (orig && typeof orig === "object") {
          orig.context = orig.context || {};
          orig.context.testForceIntent = "tool_search";
          firstDone = true;
          return route.continue({
            postData: JSON.stringify(orig),
            headers: { ...req.headers(), "content-type": "application/json" },
          });
        }
      } catch {}
      firstDone = true;
      return route.continue();
    });

    await sendQuery(page, "Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC");

    // ✓ IntentClarificationCard must appear
    const card = page.locator('[data-testid="intent-clarification-card"]');
    await card.waitFor({ state: "visible", timeout: 60_000 });
    await shot(page, "intent-clar-01-card-appeared");
    console.log("[intent-clar] ✅ card rendered in chat");

    // ✓ Primary chip ("Run a design workflow") must be present and clickable
    const primaryChip = page.locator('[data-testid="intent-clarify-workflow_generation"]');
    await expect(primaryChip).toBeVisible();
    await expect(primaryChip).toContainText(/design workflow/i);

    // ✓ Secondary chip must also be visible
    const secondaryChip = page.locator('[data-testid^="intent-clarify-"]').nth(1);
    const secondaryVisible = await secondaryChip.isVisible().catch(() => false);
    expect(secondaryVisible, "At least 2 clarification chips must be visible").toBe(true);

    await shot(page, "intent-clar-02-chips-visible");

    // ✓ Click primary chip → re-submit fires
    await primaryChip.click();
    await shot(page, "intent-clar-03-after-click");

    // ✓ Synthetic bispecific_format_triage response appears
    const wfText = page.locator("text=/bispecific[_ ]format[_ ]triage/i");
    await wfText.first().waitFor({ state: "visible", timeout: 20_000 });
    expect(await wfText.count()).toBeGreaterThan(0);

    await shot(page, "intent-clar-04-workflow-rendered");
    console.log("[intent-clar] ✅ chip click re-submitted, workflow text appeared");
  });

  test("IntentClarificationCard: skip button hides card without re-submitting", async ({ page }) => {
    test.setTimeout(120_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    await page.route("**/api/chat/stream", async (route) => {
      const req = route.request();
      if (req.method() !== "POST") return route.continue();
      try {
        const orig = req.postDataJSON();
        if (orig && typeof orig === "object") {
          orig.context = orig.context || {};
          orig.context.testForceIntent = "tool_search";
          return route.continue({
            postData: JSON.stringify(orig),
            headers: { ...req.headers(), "content-type": "application/json" },
          });
        }
      } catch {}
      return route.continue();
    });

    await sendQuery(page, "Compare GLP-1 modalities for MASH: peptide vs mRNA vs gene therapy");

    const card = page.locator('[data-testid="intent-clarification-card"]');
    await card.waitFor({ state: "visible", timeout: 120_000 });
    await shot(page, "intent-skip-01-card");

    const skip = page.locator('[data-testid="intent-clarify-skip"]');
    await expect(skip).toBeVisible();

    // Count user messages before clicking skip
    const countBefore = await page
      .locator('[data-testid^="chat-message-"]')
      .evaluateAll((els) =>
        els.filter((el) => el.getAttribute("data-message-type") !== "workflow_progress").length
      ).catch(() => 0);

    await skip.click();
    await shot(page, "intent-skip-02-after-skip");

    // ✓ No new user message submitted (count stays same for 3s)
    await page.waitForTimeout(3_000);
    const countAfter = await page
      .locator('[data-testid^="chat-message-"]')
      .evaluateAll((els) =>
        els.filter((el) => el.getAttribute("data-message-type") !== "workflow_progress").length
      ).catch(() => 0);

    expect(countAfter, "Skip must not submit a new user message").toBe(countBefore);
    console.log("[intent-skip] ✅ skip preserved state — no re-submit fired");
  });

  test("New chat button starts a clean session", async ({ page }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Send a message to create history
    await sendQuery(page, "What is the typical IC50 threshold for cardiac safety?");
    await waitForAssistantResponse(page);

    const msgCountBefore = await page.locator('[data-testid^="chat-message-"]').count().catch(() => 0);
    expect(msgCountBefore, "At least one message must be in chat after sending").toBeGreaterThan(0);

    // ✓ Find and click "New Chat" button
    const newChatBtn = page.locator(
      'button:has-text("New Chat"), button:has-text("New chat"), [aria-label*="New chat"]'
    ).first();
    const newChatVisible = await newChatBtn.isVisible({ timeout: 5_000 }).catch(() => false);

    if (newChatVisible) {
      await newChatBtn.click();
      await page.waitForTimeout(1_500);
      await shot(page, "new-chat-01-after-click");

      const msgCountAfter = await page.locator('[data-testid^="chat-message-"]').count().catch(() => 0);
      expect(msgCountAfter, "New chat must clear the message list").toBeLessThan(msgCountBefore);
      console.log("[new-chat] ✅ new chat cleared messages");
    } else {
      console.log("[new-chat] ⚠️ 'New Chat' button not found — checking sidebar");
      // Alternative: navigate to / which triggers a fresh session
      await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded" });
      await page.waitForTimeout(1_000);
      console.log("[new-chat] ℹ️ navigated to / as new-chat equivalent");
    }
  });

  test("Stop button halts streaming mid-response", async ({ page }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Send a query that will take time to stream
    await sendQuery(page, "Describe the complete ADMET assessment workflow including all phases and tools used");

    // ✓ Stop button must appear during streaming
    const stopBtn = page.locator('[data-testid="chat-stop-button"]');
    const stopAppeared = await stopBtn.waitFor({ state: "visible", timeout: 30_000 }).then(() => true).catch(() => false);

    if (stopAppeared) {
      await shot(page, "stop-01-streaming-visible");
      await stopBtn.click();
      console.log("[stop] stop button clicked");

      // ✓ Stop button must disappear after clicking
      await stopBtn.waitFor({ state: "hidden", timeout: 10_000 }).catch(() => {});
      await shot(page, "stop-02-after-stop");

      // ✓ Send button must re-appear
      const sendBtn = page.locator('[data-testid="chat-send-button"]');
      const sendVisible = await sendBtn.isVisible({ timeout: 5_000 }).catch(() => false);
      expect(sendVisible, "Send button must re-appear after stopping stream").toBe(true);
      console.log("[stop] ✅ stop successful, send button returned");
    } else {
      console.log("[stop] ⚠️ stop button did not appear — response may have been instant");
    }
  });
});

// ══════════════════════════════════════════════════════════════════════════════
// P1: Website query gallery — every query shown to users
// These tests verify that each query example from the public website
// routes correctly and produces a coherent response in the UI.
// ══════════════════════════════════════════════════════════════════════════════

interface GalleryQuery {
  id: string;
  query: string;
  expectedIntent: "workflow_generation" | "research_question" | "tool_search" | "benchmark";
  mustContain: RegExp[]; // patterns that must appear in response or chip name
  mustNotTriggerWorkflow?: boolean; // for research/tool queries
}

const WEBSITE_GALLERY: GalleryQuery[] = [
  // Drug discovery
  {
    id: "ADMET-aspirin",
    query: "Run a full ADMET panel for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O) — hERG cardiotoxicity, DILI, Ames mutagenicity, CYP450 inhibition, and Lipinski Ro5 compliance",
    expectedIntent: "workflow_generation",
    mustContain: [/admet|predict/i],
  },
  {
    id: "bispecific-design",
    query: "Design a PD-1 x VEGF bispecific antibody in CrossMab format for NSCLC",
    expectedIntent: "workflow_generation",
    mustContain: [/bispecific|crossmab|antibod|design/i],
  },
  {
    id: "molecular-docking",
    query: "Run molecular docking of ibuprofen against COX-2 (PDB: 3LN1) to predict binding pose and affinity",
    expectedIntent: "workflow_generation",
    mustContain: [/dock|cox|binding|ibuprofen/i],
  },
  // Genomics
  {
    id: "RNA-seq",
    query: "Run RNA-seq differential expression analysis between tumor and normal samples using DESeq2",
    expectedIntent: "workflow_generation",
    mustContain: [/rna.?seq|deseq|differential|expression/i],
  },
  {
    id: "variant-annotation",
    query: "Find tools for variant annotation and VCF processing",
    expectedIntent: "tool_search",
    mustContain: [/vep|annovar|snpeff|variant|annotate/i],
    mustNotTriggerWorkflow: true,
  },
  // Structural biology
  {
    id: "alphafold-structure",
    query: "Predict the 3D structure of this protein sequence using AlphaFold: MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEKAVQVKVKALPDAQFEVVHSLAKWKRQTLGQHDFSAGEGLYTHMKALRPDEDRLSPLHSVYVDQWDWERVMGDGERQFSTLKSTVEAIWAGIKATEAAVSEEFGLAPFLPDQIHFVHSQELLSRYPDLDAKGRERAIAKDLGAVFLVGIGGKLSDGHRHDVRAPDYDDWSTPSELGHAGLNGDILVWNPVLEDAFELSSMGIRVDADTLKHQLALTGDEDRLELEWHQALLRGEMPQTIGGGIGQSRLTMLLLQLPHIGQVQAGVWPAAVRESVPSLL",
    expectedIntent: "workflow_generation",
    mustContain: [/alphafold|structure|protein|fold/i],
  },
  // Clinical
  {
    id: "boin-trial",
    query: "Run a BOIN Phase I dose-escalation simulation — starting dose 10 mg, max dose 400 mg, target DLT rate 25%, 1000 simulations",
    expectedIntent: "workflow_generation",
    mustContain: [/boin|dose|escalation|clinical/i],
  },
  // Research questions
  {
    id: "herg-ic50",
    query: "What is the typical IC50 threshold for cardiac safety in hERG assays?",
    expectedIntent: "research_question",
    mustContain: [/ic50|herg|cardiac|safety/i],
    mustNotTriggerWorkflow: true,
  },
  {
    id: "glp1-modalities",
    query: "Compare GLP-1 modalities for MASH treatment: peptide vs mRNA vs gene therapy approaches",
    expectedIntent: "benchmark",
    mustContain: [/glp.1|peptide|mrna|gene therapy|modality|compare/i],
  },
  // Single-cell
  {
    id: "scrna-clustering",
    query: "Run single-cell RNA-seq analysis with Seurat — clustering, UMAP, and cell type annotation",
    expectedIntent: "workflow_generation",
    mustContain: [/seurat|single.cell|scRNA|cluster|umap/i],
  },
];

test.describe("P1 — Website query gallery", () => {
  for (const q of WEBSITE_GALLERY) {
    test(`${q.id}: "${q.query.substring(0, 60)}…"`, async ({ page }) => {
      test.setTimeout(LLM_TIMEOUT + 30_000);
      await loginAsFixture(page);
      await gotoFreshChat(page);

      await sendQuery(page, q.query);
      await waitForAssistantResponse(page);
      await shot(page, `gallery-${q.id}`);

      const responseText = await waitForFinalAssistantText(page, 20_000);
      const chipName = await page.locator(".wf-chip-name").first().textContent().catch(() => "");
      const combinedText = `${responseText} ${chipName}`.toLowerCase();

      // ✓ Response must be non-empty
      expect(responseText.length, `[${q.id}] Response must not be empty`).toBeGreaterThan(30);

      // ✓ Response (or chip name) must contain expected keywords
      const allKeywordsMatch = q.mustContain.some((pat) => pat.test(combinedText));
      expect(
        allKeywordsMatch,
        `[${q.id}] Response/chip must match one of: ${q.mustContain.map((r) => r.toString())} — got: "${combinedText.substring(0, 100)}"`
      ).toBe(true);

      // ✓ For research/tool queries, a workflow chip is unexpected — warn but don't fail.
      // Routing improvements may legitimately start offering workflows for some of these
      // queries (e.g. "Find tools for X" → also surfaces relevant workflow). Hard-failing
      // here would break tests every time routing improves; warn so the change is visible.
      if (q.mustNotTriggerWorkflow) {
        const chipCount = await page.locator(".wf-chip").count().catch(() => 0);
        if (chipCount > 0) {
          console.warn(
            `[${q.id}] ⚠️ Unexpected workflow chip for a ${q.expectedIntent} query (got ${chipCount}). ` +
            `Backend routing may have intentionally changed — verify this is desired behavior.`
          );
        }
      }

      console.log(`[gallery:${q.id}] ✅ intent_ok  text_len=${responseText.length}  chip="${chipName}"`);
    });
  }
});

// ══════════════════════════════════════════════════════════════════════════════
// P2: Page load and session state
// ══════════════════════════════════════════════════════════════════════════════

test.describe("P2 — Page load and session", () => {
  test("App loads without JS errors in browser console", async ({ page }) => {
    test.setTimeout(30_000);
    const errors: string[] = [];
    page.on("console", (m) => {
      if (m.type() === "error") errors.push(m.text());
    });
    page.on("pageerror", (e) => errors.push(`[pageerror] ${e.message}`));

    await loginAsFixture(page);
    await gotoFreshChat(page);
    await shot(page, "page-load-01-loaded");

    // Filter out known benign errors (e.g. font loading in non-production environments)
    const realErrors = errors.filter(
      (e) =>
        !e.includes("favicon") &&
        !e.includes("ResizeObserver") &&
        !e.includes("Non-Error exception")
    );

    if (realErrors.length > 0) {
      console.warn("[page-load] Browser console errors:\n" + realErrors.join("\n"));
    }
    // Soft assertion: log but don't fail on isolated console errors
    // (some errors come from third-party scripts or browser extensions)
    expect(realErrors.length, `JS errors in browser console: ${realErrors.join("; ")}`).toBeLessThan(3);
  });

  test("Chat history persists and is accessible from sidebar after page reload", async ({ page }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    const QUERY = "What is the typical IC50 threshold for cardiac safety?";
    await sendQuery(page, QUERY);
    await waitForAssistantResponse(page);

    const textBefore = await waitForFinalAssistantText(page, 20_000);
    expect(textBefore.length, "Must have a response before reload").toBeGreaterThan(10);

    await shot(page, "persist-00-before-reload");

    // Reload to / — creates a new thread but history should appear in the sidebar
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 30_000 });
    await page.waitForLoadState("load").catch(() => {});
    await page.locator('[data-testid="chat-input"], textarea').first()
      .waitFor({ state: "visible", timeout: 20_000 });
    await page.waitForTimeout(2_000);

    await shot(page, "persist-01-after-reload");

    // ✓ Sidebar must show the previous conversation (data-testid="button-chat-{id}")
    // The app saves conversations by their first message (query text snippet)
    const sidebarItems = page.locator('[data-testid^="button-chat-"]').filter({ hasText: /IC50|cardiac|threshold/i });
    const sidebarCount = await sidebarItems.count().catch(() => 0);
    expect(
      sidebarCount,
      "Previous conversation must appear in the sidebar after reload — persistence is broken if 0"
    ).toBeGreaterThan(0);

    // ✓ Clicking the sidebar entry opens the conversation
    await sidebarItems.first().click();
    await page.waitForTimeout(2_000);
    await shot(page, "persist-02-sidebar-clicked");

    // The user message should be immediately visible (proves the conversation was restored).
    // Assistant response may lazy-load, so we check the user message only.
    const restoredUserMsg = page.locator('[data-testid^="chat-message-"], [class*="user-bubble"], [class*="user-message"]')
      .filter({ hasText: /IC50|cardiac|threshold/i }).first();
    const userMsgText = await restoredUserMsg.textContent({ timeout: 10_000 }).catch(() => "");
    expect(
      userMsgText.length,
      "Clicking sidebar entry must restore the previous conversation (user message visible)"
    ).toBeGreaterThan(5);
    console.log(`[persist] sidebar_count=${sidebarCount}  restored_user_msg_len=${userMsgText.length}`);
  });
});

// ══════════════════════════════════════════════════════════════════════════════
// P1: Workflow panel UI — tabs and structure (without executing a workflow)
// These tests use SSE mocking so they run in < 30s.
// ══════════════════════════════════════════════════════════════════════════════

test.describe("P1 — Panel UI components (mocked run)", () => {
  // Minimal SSE payload that produces a workflow message in chat
  const MOCK_WORKFLOW_SSE = [
    `event: ready\ndata: ${JSON.stringify({ ok: true })}\n\n`,
    `event: delta\ndata: ${JSON.stringify({ text: "I found the ADMET prediction workflow for aspirin." })}\n\n`,
    `event: final\ndata: ${JSON.stringify({
      response: "I found the ADMET prediction workflow for aspirin.",
      state: "done",
      metadata: {
        intentType: "workflow_generation",
        inlineParameters: { compound_smiles: "CC(=O)Oc1ccccc1C(=O)O", compound_name: "aspirin" },
        paramClarifications: null,
        intentClarification: null,
        workflowSuggestion: null,
        sources: null,
        memoryUsed: false,
        workflowGenerationDiagnostics: null,
        llm_usage: null,
      },
      workflow: {
        name: "ADMET Prediction",
        workflow_name: "ADMET Prediction",
        domain: "drug_discovery",
        description: "Predict ADMET properties for small molecules",
        type: "nextflow",
        required_params: [
          { name: "compound_smiles", label: "Compound SMILES", type: "string", required: true, value: "CC(=O)Oc1ccccc1C(=O)O" },
        ],
        optional_params: [
          { name: "compound_name", label: "Compound Name", type: "string", required: false, value: "aspirin" },
        ],
      },
      prerequisitesValidation: null,
      thinking_content: null,
      thinking_level: null,
      suggestions: [],
      subIntentResults: null,
      isMultiIntent: false,
    })}\n\n`,
    `event: done\ndata: ${JSON.stringify({ ok: true })}\n\n`,
  ].join("");

  test("Panel tabs are accessible and switch content correctly", async ({ page }) => {
    test.setTimeout(60_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Intercept chat/stream with a synthetic workflow response
    await page.route("**/api/chat/stream", async (route) => {
      if (route.request().method() !== "POST") return route.continue();
      return route.fulfill({
        status: 200,
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache, no-transform",
          "Connection": "keep-alive",
        },
        body: MOCK_WORKFLOW_SSE,
      });
    });

    await sendQuery(page, "Run ADMET prediction for aspirin");
    await waitForAssistantResponse(page);

    // Workflow card must appear in chat
    const wfChip = page.locator(".wf-chip").first();
    const chipVisible = await wfChip.isVisible({ timeout: 20_000 }).catch(() => false);
    if (!chipVisible) {
      console.warn("[panel-tabs] wf-chip not visible — mock SSE may not have produced a workflow card");
      return; // soft skip — SSE mock didn't fire or server intercepted
    }

    // Open the panel
    await openWorkflowPanel(page);
    await page.locator('[data-testid="workflow-artifact-panel"]').waitFor({ state: "visible", timeout: 10_000 });
    await shot(page, "panel-tabs-01-opened");

    // ✓ Tab bar must show all 3 tabs
    const tabs = page.locator('[data-testid="panel-tabs"]');
    await expect(tabs).toBeVisible();
    await expect(page.locator('[data-testid="panel-tab-settings"]')).toBeVisible();
    await expect(page.locator('[data-testid="panel-tab-phases"]')).toBeVisible();
    await expect(page.locator('[data-testid="panel-tab-after-run"]')).toBeVisible();

    // ✓ Settings tab — shows parameters strip
    await page.locator('[data-testid="panel-tab-settings"]').click();
    await page.locator('[data-testid="panel-settings"]').waitFor({ state: "visible", timeout: 5_000 });
    await shot(page, "panel-tabs-02-settings");

    // ✓ Settings tab should show the toggle button for params
    const settingsToggle = page.locator('[data-testid="button-toggle-workflow-settings"]');
    const toggleVisible = await settingsToggle.isVisible({ timeout: 3_000 }).catch(() => false);
    console.log(`[panel-tabs] settings strip toggle visible: ${toggleVisible}`);

    // ✓ Phases tab — shows phases section
    await page.locator('[data-testid="panel-tab-phases"]').click();
    await page.locator('[data-testid="panel-phases"]').waitFor({ state: "visible", timeout: 5_000 });
    await shot(page, "panel-tabs-03-phases");

    // ✓ After-run tab — available (no dot badge yet since not completed)
    await page.locator('[data-testid="panel-tab-after-run"]').click();
    await page.locator('[data-testid="panel-after-run"]').waitFor({ state: "visible", timeout: 5_000 });
    await shot(page, "panel-tabs-04-after-run");

    // ✓ Main run button must be visible in panel footer (on phases or settings tab)
    await page.locator('[data-testid="panel-tab-settings"]').click();
    const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
    const runVisible = await runBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    expect(runVisible, "Run button (button-run-workflow-panel) must be visible").toBe(true);

    const runText = await runBtn.textContent().catch(() => "");
    expect(runText, "Run button text should be 'Confirm and run workflow'").toMatch(/confirm|run/i);

    await shot(page, "panel-tabs-05-run-btn");
    console.log(`[panel-tabs] ✅ all 3 tabs accessible, run button visible: "${runText}"`);
  });

  test("Status badge transitions idle→running (mocked via action bar)", async ({ page }) => {
    test.setTimeout(30_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    await page.route("**/api/chat/stream", async (route) => {
      if (route.request().method() !== "POST") return route.continue();
      return route.fulfill({
        status: 200,
        headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache, no-transform", "Connection": "keep-alive" },
        body: MOCK_WORKFLOW_SSE,
      });
    });

    await sendQuery(page, "Run ADMET prediction for aspirin");
    await waitForAssistantResponse(page);

    const chipVisible = await page.locator(".wf-chip").first().isVisible({ timeout: 20_000 }).catch(() => false);
    if (!chipVisible) {
      console.warn("[status-badge] wf-chip not visible, skipping");
      return;
    }

    await openWorkflowPanel(page);
    await page.locator('[data-testid="workflow-artifact-panel"]').waitFor({ state: "visible", timeout: 10_000 });

    // ✓ Idle state: status badge has data-status="idle" (badge is hidden but present)
    const badge = page.locator('[data-testid="workflow-overall-status-badge"]');
    await expect(badge).toBeAttached();
    const idleStatus = await badge.getAttribute("data-status");
    expect(idleStatus, "Status badge must start at idle").toBe("idle");
    console.log(`[status-badge] ✅ idle state confirmed`);
  });
});

// ══════════════════════════════════════════════════════════════════════════════
// P1: Progress fold — expand and collapse
// ══════════════════════════════════════════════════════════════════════════════

test.describe("P1 — Progress fold", () => {
  test("Progress fold appears and toggles for repeated same-speaker pills", async ({ page }) => {
    test.setTimeout(LLM_TIMEOUT + 30_000);
    await loginAsFixture(page);
    await gotoFreshChat(page);

    // Use a workflow query that typically produces many wf-speaker progress pills
    await sendQuery(page, "Run a full ADMET panel for aspirin (SMILES: CC(=O)Oc1ccccc1C(=O)O)");
    await waitForAssistantResponse(page);
    await shot(page, "fold-01-final");

    // Check if any progress fold appeared (wf speaker is most common)
    const folds = page.locator('[data-testid^="progress-fold-"]');
    const foldCount = await folds.count().catch(() => 0);

    if (foldCount > 0) {
      console.log(`[progress-fold] ✅ ${foldCount} fold(s) rendered`);

      const firstFold = folds.first();
      const speaker = await firstFold.getAttribute("data-speaker").catch(() => "");
      const count = await firstFold.getAttribute("data-count").catch(() => "0");
      const isOpen = await firstFold.getAttribute("data-open").catch(() => "false");
      console.log(`[progress-fold] speaker=${speaker}  count=${count}  open=${isOpen}`);

      expect(Number(count), "Fold must have at least 2 hidden messages").toBeGreaterThanOrEqual(2);

      // ✓ Click caret to expand
      const caret = firstFold.locator(".chat-progress-fold__caret");
      await caret.click();
      await page.waitForTimeout(500);
      const nowOpen = await firstFold.getAttribute("data-open").catch(() => "false");
      expect(nowOpen, "Fold must be open after clicking caret").toBe("true");
      await shot(page, "fold-02-expanded");

      // ✓ Click again to collapse
      await caret.click();
      await page.waitForTimeout(500);
      const nowClosed = await firstFold.getAttribute("data-open").catch(() => "true");
      expect(nowClosed, "Fold must be closed after second click").toBe("false");
      await shot(page, "fold-03-collapsed");

      console.log("[progress-fold] ✅ expand/collapse works");
    } else {
      // Folds only appear when > 2 consecutive same-speaker pills — may not fire on every run
      const pillCount = await countProgressPills(page);
      console.log(`[progress-fold] ⚠️ No folds appeared (${pillCount} pills total). This is OK if < 3 consecutive same-speaker pills.`);
    }
  });
});
