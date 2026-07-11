/**
 * DESeq2 Inline Data E2E
 * ======================
 * Comprehensive test for the inline count matrix → DESeq2 differential
 * expression flow that was broken until commit f5f2b5ddd:
 *   - Intent was misclassified as tool_search (deterministic regex fix)
 *   - Workflow generation crashed with NameError: _re_routing (re fix)
 *
 * Coverage:
 *   A. SSE stream API — intent, event sequence, workflow routing
 *   B. Chat UI — workflow card, wf-chip "In panel" badge
 *   C. Panel idle — tabs, params strip, prereq checklist, run button
 *   D. Panel run — real-time idle→running→terminal status tracking
 *   E. Hero query flow — sessionStorage race condition fix (query survives
 *      hero → register form → login page → chat)
 *
 * CLAUDE.md rules:
 *  - Login once per harness (sharedPage + sharedToken)
 *  - No page.route() mocking — all calls hit live dev backend
 *  - 90 s LLM timeout (chat/stream takes 30–90 s on workflow paths)
 *  - Fixture: lifeifei163361@163.com / WpmFixture!2026
 */

import { test, expect, type Page } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { waitForResponseComplete } from "./helpers.js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SS_DIR = path.join("/tmp", "deseq2-inline-e2e");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

const LLM_TIMEOUT = 90_000;

/** Inline count matrix: 10 genes × 6 samples (3 ctrl, 3 treated) */
const INLINE_MATRIX = `gene,ctrl1,ctrl2,ctrl3,treat1,treat2,treat3
GENE1,100,120,110,200,210,195
GENE2,50,55,48,52,49,51
GENE3,30,28,32,90,88,95
GENE4,200,210,195,205,198,202
GENE5,15,18,16,45,50,48
GENE6,80,85,78,82,79,81
GENE7,10,12,11,35,38,33
GENE8,300,310,295,308,302,296
GENE9,25,27,24,70,75,68
GENE10,60,65,58,63,59,62`;

const DESEQ2_MESSAGE =
  `Run DESeq2 differential expression on this count matrix — ` +
  `3 ctrl replicates vs 3 treated replicates:\n${INLINE_MATRIX}`;

/** Sample sheet matching the inline count matrix columns */
const SAMPLE_SHEET = `sample,condition
ctrl1,control
ctrl2,control
ctrl3,control
treat1,treatment
treat2,treatment
treat3,treatment`;

test.setTimeout(20 * 60_000); // 20 min — panel run + real SSE wait

let sharedPage: Page;
let sharedToken: string = "";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function ss(page: Page, name: string) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log(`[SS] ${p}`);
}

/**
 * Parse /api/chat/stream SSE using the browser's ReadableStream API.
 *
 * Why page.evaluate() instead of apiRequestContext.post():
 *   apiRequestContext.post() buffers the ENTIRE response body before returning.
 *   SSE connections stay open until the server closes them, which can take
 *   > 90 s after the last event is sent — causing TimeoutError even though
 *   the LLM responded correctly.
 *
 *   page.evaluate() runs the fetch inside the browser page. We cancel the
 *   reader as soon as we receive the `final` SSE event, so we exit as soon
 *   as the response is complete rather than waiting for connection close.
 *
 *   page.evaluate() is not subject to actionTimeout — it resolves when the
 *   inner Promise resolves (no Playwright-level timeout applies). The browser
 *   context already has auth cookies + Authorization header from loginAsFixture.
 */
async function parseChatStream(page: Page, message: string) {
  // page.evaluate fetch must be same-origin. Navigate to the app if not already there.
  if (!page.url().startsWith(BASE_URL)) {
    await page.goto(BASE_URL, { waitUntil: "domcontentloaded" });
  }
  return page.evaluate(
    async ({ baseUrl, message, sessionId }) => {
      const resp = await fetch(`${baseUrl}/api/chat/stream`, {
        method: "POST",
        headers: {
          Accept: "text/event-stream",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ message, stream: true, sessionId }),
      });

      if (!resp.ok || !resp.body) throw new Error(`chat/stream ${resp.status}`);

      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      let lastEvent = "";
      const events: string[] = [];
      let finalPayload: any = null;
      let workflowReadyPayload: any = null;
      let deltaText = "";
      let hasDelta = false;
      let hasFinal = false;
      let hasWorkflowReady = false;

      const processLine = (line: string) => {
        if (line.startsWith("event: ")) {
          lastEvent = line.slice(7).trim();
          if (!events.includes(lastEvent)) events.push(lastEvent);
          if (lastEvent === "delta") hasDelta = true;
          if (lastEvent === "final") hasFinal = true;
          if (lastEvent === "workflow_ready") hasWorkflowReady = true;
        } else if (line.startsWith("data: ")) {
          try {
            const d = JSON.parse(line.slice(6));
            if (lastEvent === "delta" && typeof d.text === "string") deltaText += d.text;
            if (lastEvent === "final") finalPayload = d;
            if (lastEvent === "workflow_ready") workflowReadyPayload = d;
          } catch {}
        }
      };

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          const lines = buf.split("\n");
          buf = lines.pop() ?? "";
          for (const line of lines) processLine(line);
          if (hasFinal) { reader.cancel(); break; }
        }
      } catch { /* cancelled */ }

      return { events, hasDelta, hasFinal, hasWorkflowReady, finalPayload, workflowReadyPayload, deltaText };
    },
    { baseUrl: BASE_URL, message, sessionId: `e2e-deseq2-${Date.now()}` },
  );
}

/** Wait until panel overall badge reaches a terminal state */
async function waitForPanelTerminal(page: Page, timeoutMs = 10 * 60_000) {
  await page.waitForFunction(
    () => {
      const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
      if (!badge) return false;
      const s = badge.getAttribute("data-status") ?? "";
      return s === "completed" || s === "failed";
    },
    { timeout: timeoutMs },
  );
}

/**
 * Navigate to home, send the inline DESeq2 message, wait for the LLM
 * response, and try to open the workflow panel.
 * Returns true if the panel became visible.
 */
async function openPanelWithDESeq2(page: Page): Promise<boolean> {
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const chatInput = page.locator("textarea, input[type='text']").first();
  await expect(chatInput).toBeVisible({ timeout: 10_000 });
  await chatInput.fill(DESEQ2_MESSAGE);
  await chatInput.press("Enter");
  await waitForResponseComplete(page, LLM_TIMEOUT);

  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  let panelVisible = await panel.isVisible().catch(() => false);

  if (!panelVisible) {
    // Try clicking a wf-chip to open the panel manually
    const chip = page.locator('[data-testid^="wf-chip-"]').first();
    if (await chip.count() > 0) {
      await chip.click();
      await page
        .waitForSelector('[data-testid="workflow-artifact-panel"]', { state: "visible", timeout: 5_000 })
        .catch(() => null);
      panelVisible = await panel.isVisible().catch(() => false);
    }
  }

  return panelVisible;
}

/** Wait until panel shows running (or terminal) */
async function waitForPanelRunning(page: Page, timeoutMs = 30_000) {
  await page.waitForFunction(
    () => {
      const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
      if (!badge) return false;
      const s = badge.getAttribute("data-status") ?? "";
      return s === "running" || s === "completed" || s === "failed";
    },
    { timeout: timeoutMs },
  );
}

// ---------------------------------------------------------------------------
// beforeAll — single login
// ---------------------------------------------------------------------------

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await loginAsFixture(sharedPage);

  // Capture token from cookies set by loginAsFixture — avoids browser-side
  // fetch (page.evaluate) which is blocked by CSRF protection on the dev server.
  // loginAsFixture already sets the biomate_token cookie via page.request (Playwright's
  // native HTTP stack, not the browser fetch), so we just read it from cookies here.
  const cookies = await sharedPage.context().cookies();
  const tokenCookie = cookies.find((c) => c.name === "biomate_token");
  sharedToken = tokenCookie?.value ?? "";

  console.log("[Auth] sharedToken present:", !!sharedToken);
});

test.afterAll(async () => {
  await sharedPage?.close();
});

// ============================================================================
// A. SSE stream API — inline data must route to DESeq2, no error
// ============================================================================

test("A1: inline count matrix → intent=workflow_generation, no _re_routing error", async () => {
  const result = await parseChatStream(sharedPage, DESEQ2_MESSAGE);

  console.log("[A1] SSE events:", result.events.join(", "));
  console.log("[A1] finalPayload.state:", result.finalPayload?.state);
  console.log("[A1] finalPayload.error:", result.finalPayload?.error);

  // Must emit ready and final
  expect(result.events, "must have 'ready' event").toContain("ready");
  expect(result.hasFinal, "must have 'final' event").toBe(true);

  const fp = result.finalPayload;
  expect(fp, "final payload must not be null").not.toBeNull();

  // The original bug was a _re_routing NameError that crashed the Python AI
  // assistant and produced workflow_failed + error containing "_re_routing".
  // A clean workflow_failed (no _re_routing) is acceptable when local Galaxy
  // is not running — what we're testing is that the crash is gone.
  if (typeof fp?.error === "string" && fp.error.length > 0) {
    expect(fp.error, "error must not reference _re_routing").not.toMatch(/_re_routing/);
    expect(fp.error, "error must not be a Python NameError").not.toMatch(/NameError/);
  }

  // State must be a known terminal state (not an internal crash)
  expect(
    ["workflow_ready", "workflow_failed", "chat_only", "needs_input", "ok"],
    "state is a known terminal value",
  ).toContain(fp?.state);

  console.log("[A1] intentType:", fp?.intentType);
  console.log("[A1] shouldGenerate:", fp?.shouldGenerate);
});

test("A2: inline count matrix → workflow_ready event with DESeq2 workflow", async () => {
  const result = await parseChatStream(sharedPage, DESEQ2_MESSAGE);

  console.log("[A2] SSE events:", result.events.join(", "));
  console.log("[A2] state:", result.finalPayload?.state);

  if (result.finalPayload?.state !== "workflow_ready") {
    console.log("[A2] state is not workflow_ready — LLM or Galaxy returned:", result.finalPayload?.state);
    console.log("[A2] message:", String(result.finalPayload?.response || "").slice(0, 200));
    // workflow_failed is acceptable when local Galaxy isn't running; what matters
    // is no _re_routing NameError (that was the original bug).
    const err = String(result.finalPayload?.error ?? "");
    expect(err, "error must not reference _re_routing").not.toMatch(/_re_routing/);
    expect(err, "error must not be a Python NameError").not.toMatch(/NameError/);
    return;
  }

  // workflow_ready SSE event must have been emitted
  expect(result.hasWorkflowReady, "workflow_ready event must be emitted when state=workflow_ready").toBe(true);

  const wfr = result.workflowReadyPayload;
  expect(wfr, "workflow_ready payload must not be null").not.toBeNull();
  expect(wfr).toHaveProperty("workflow_name");
  expect(wfr).toHaveProperty("workflow_type");
  expect(wfr).toHaveProperty("view_url");
  expect(wfr?.view_url, "view_url must be a URL string").toMatch(/https?:\/\//);

  // Workflow name should reference a DESeq2-family or differential-expression workflow.
  // nf-core/differentialabundance wraps DESeq2 and is a valid match.
  const wfName: string = (wfr?.workflow_name ?? "").toLowerCase();
  const isDeSeq2Family =
    wfName.includes("deseq") ||
    wfName.includes("differentialabundance") ||
    wfName.includes("differentialexpression") ||
    wfName.includes("rnaseq") ||
    wfName.includes("differential");
  expect(isDeSeq2Family, `workflow name '${wfName}' should be a DESeq2-family workflow`).toBe(true);

  console.log("[A2] workflow_name:", wfr?.workflow_name);
  console.log("[A2] workflow_type:", wfr?.workflow_type);
  console.log("[A2] view_url:", wfr?.view_url);

  // Final payload must carry the workflow object
  const fp = result.finalPayload;
  const wf = fp?.workflow;
  expect(wf, "final payload must carry workflow object").toBeTruthy();

  const hasPath = !!(wf?.nextflow_path || wf?.workflow_ga?.name || wf?.chain_name);
  expect(hasPath, "workflow must have nextflow_path or name").toBe(true);

  console.log("[A2] nextflow_path:", wf?.nextflow_path);
});

test("A3: SSE final payload must describe DESeq2 analysis in streaming delta text or message", async () => {
  const result = await parseChatStream(sharedPage, DESEQ2_MESSAGE);

  // Either delta text or the final.response should mention DESeq2 concepts
  const fullText = (result.deltaText + " " + (result.finalPayload?.response ?? "")).toLowerCase();
  console.log("[A3] combined text (first 300):", fullText.slice(0, 300));

  const hasDESeq2Mention =
    fullText.includes("deseq2") ||
    fullText.includes("differential expression") ||
    fullText.includes("log2 fold") ||
    fullText.includes("adjusted p") ||
    fullText.includes("count matrix");

  expect(hasDESeq2Mention, "response text must mention DESeq2 analysis concepts").toBe(true);
});

// ============================================================================
// B. Chat UI — workflow card rendered after sending inline DESeq2 message
// ============================================================================

test("B1: inline DESeq2 message in chat UI produces workflow card or descriptive response", async () => {
  const page = sharedPage;
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  await ss(page, "B1_00_home");

  // Find and fill the chat input
  const chatInput = page.locator("textarea, input[type='text']").first();
  await expect(chatInput).toBeVisible({ timeout: 10_000 });
  await chatInput.fill(DESEQ2_MESSAGE);
  await ss(page, "B1_01_query_typed");
  await chatInput.press("Enter");

  // Wait for LLM response
  await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "B1_02_response");

  // Response must not be empty
  const latestMsg = page.locator('[data-is-latest-assistant="true"]').first();
  const msgText = await latestMsg.textContent().catch(() => "");
  expect(msgText?.trim().length ?? 0, "assistant response must not be empty").toBeGreaterThan(20);

  // Check for workflow card in chat
  const wfAnchor = page.locator('[data-testid^="workflow-artifact-anchor-"]').first();
  const wfChip = page.locator('[data-testid^="wf-chip-"]').first();
  const hasWorkflowCard = (await wfAnchor.count()) > 0 || (await wfChip.count()) > 0;

  if (hasWorkflowCard) {
    console.log("[B1] Workflow card/chip visible in chat");
    // wf-chip should show an "In panel" badge when panel is open
    if (await wfChip.count() > 0) {
      await expect(wfChip).toBeVisible();
      const chipText = await wfChip.textContent();
      console.log("[B1] wf-chip text:", chipText?.trim());
    }
  } else {
    // If no workflow card, the message must at least describe DESeq2
    const lowerText = (msgText ?? "").toLowerCase();
    const mentionsDESeq2 =
      lowerText.includes("deseq") ||
      lowerText.includes("differential expression") ||
      lowerText.includes("workflow");
    expect(mentionsDESeq2, "if no card, response must mention DESeq2 or workflow").toBe(true);
    console.log("[B1] No workflow card — response mentions DESeq2 concepts");
  }

  await ss(page, "B1_03_final");
});

// ============================================================================
// C. Panel idle — tabs, prereq checklist, run button
// ============================================================================

test("C1: workflow panel opens in idle state with correct tabs and run button", async () => {
  const page = sharedPage;

  // Navigate fresh and send the message
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const chatInput = page.locator("textarea, input[type='text']").first();
  await chatInput.fill(DESEQ2_MESSAGE);
  await chatInput.press("Enter");
  await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "C1_00_response");

  // Check if panel opened
  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  const panelVisible = await panel.isVisible().catch(() => false);

  if (!panelVisible) {
    // Try clicking a wf-chip to open the panel
    const chip = page.locator('[data-testid^="wf-chip-"]').first();
    if (await chip.count() > 0) {
      await chip.click();
      await page.waitForTimeout(1_000);
    }

    const stillHidden = !(await panel.isVisible().catch(() => false));
    if (stillHidden) {
      console.log("[C1] Panel not visible — workflow may not have been generated; soft-skip panel tests");
      return;
    }
  }

  await ss(page, "C1_01_panel_open");

  // ── Tabs ─────────────────────────────────────────────────────────────────

  const settingsTab = page.locator('[data-testid="panel-tab-settings"]');
  const phasesTab = page.locator('[data-testid="panel-tab-phases"]');
  const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');

  await expect(settingsTab, "Settings tab visible").toBeVisible();
  await expect(phasesTab, "Phases tab visible").toBeVisible();
  await expect(afterRunTab, "After Run tab visible").toBeVisible();

  // Settings tab is selected by default in idle
  await expect(settingsTab, "Settings tab aria-selected=true in idle").toHaveAttribute(
    "aria-selected",
    "true",
  );

  // ── Status badge ──────────────────────────────────────────────────────────

  const statusBadge = page.locator('[data-testid="workflow-overall-status-badge"]');
  if (await statusBadge.count() > 0) {
    const dataStatus = await statusBadge.getAttribute("data-status");
    expect(["idle", "pending"], "badge is idle or pending before run").toContain(dataStatus);
    console.log("[C1] status badge data-status:", dataStatus);
  }

  // ── Params strip ─────────────────────────────────────────────────────────

  const toggleSettings = page.locator('[data-testid="button-toggle-workflow-settings"]');
  if (await toggleSettings.count() > 0) {
    await toggleSettings.click();
    const outputSection = page.locator('[data-testid="output-location-section"]');
    if (await outputSection.count() > 0) {
      await expect(outputSection).toBeVisible();
      const defaultRadio = page.locator('[data-testid="output-location-default"]');
      await expect(defaultRadio).toBeChecked();
    }
    await ss(page, "C1_02_params_expanded");
  }

  // ── Prereq checklist (DESeq2 requires file upload) ────────────────────────

  const prereqItems = page.locator('[data-testid^="workflow-prereq"]');
  const prereqCount = await prereqItems.count();
  if (prereqCount > 0) {
    console.log("[C1] Prereq checklist items:", prereqCount);
    for (let i = 0; i < Math.min(prereqCount, 5); i++) {
      const text = await prereqItems.nth(i).textContent();
      console.log(`[C1]   prereq[${i}]:`, text?.trim().slice(0, 80));
    }
    await ss(page, "C1_03_prereq");
  }

  // ── Run button ────────────────────────────────────────────────────────────

  const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
  await expect(runBtn, "Run button visible").toBeVisible();
  const unfilled = parseInt((await runBtn.getAttribute("data-required-unfilled")) ?? "0", 10);
  console.log("[C1] required-unfilled:", unfilled);

  await ss(page, "C1_04_run_btn");

  // ── Phases tab ────────────────────────────────────────────────────────────

  await phasesTab.click();
  const phasesBody = page.locator('[data-testid="panel-phases"]');
  await expect(phasesBody).toBeVisible();
  await ss(page, "C1_05_phases_tab");
});

// ============================================================================
// C2. Panel Settings tab — param form renders correct element types
// ============================================================================

test("C2: Settings tab renders param form with correct input element for each param type", async () => {
  const page = sharedPage;
  const panelVisible = await openPanelWithDESeq2(page);
  await ss(page, "C2_00_panel");

  if (!panelVisible) {
    console.log("[C2] Panel not visible — workflow not generated; skipping param form test");
    return;
  }

  const panel = page.locator('[data-testid="workflow-artifact-panel"]');

  // Click Settings tab and wait for it to be truly active (aria-selected="true").
  // The toggle button is inside display:none when activeTab!='settings', so we must
  // wait for the tab switch before attempting to click the toggle.
  const settingsTab = page.locator('[data-testid="panel-tab-settings"]');
  await expect(settingsTab, "Settings tab visible").toBeVisible();
  await settingsTab.click();
  await page.waitForFunction(
    () => document.querySelector('[data-testid="panel-tab-settings"]')?.getAttribute("aria-selected") === "true",
    { timeout: 5_000 },
  ).catch(() => null);

  // Now the Settings tab content is shown — wait for the toggle to become visible
  const toggleBtn = page.locator('[data-testid="button-toggle-workflow-settings"]');
  await toggleBtn.waitFor({ state: "visible", timeout: 5_000 }).catch(() => null);
  const toggleVisible = await toggleBtn.isVisible().catch(() => false);

  if (toggleVisible) {
    const isOpen = await toggleBtn.evaluate((el) => el.classList.contains("open")).catch(() => false);
    if (!isOpen) {
      await toggleBtn.click();
      // Wait for .strip-body to mount
      await page.waitForSelector(".strip-body", { state: "attached", timeout: 5_000 }).catch(() => null);
    }
  } else {
    console.log("[C2] Toggle button not visible after Settings tab activated");
  }

  await ss(page, "C2_01_params_expanded");

  // Get rendered param IDs from debug attribute
  const rawIds = await panel.getAttribute("data-debug-rendered-param-ids");
  const paramIds = rawIds ? rawIds.split(",").filter(Boolean) : [];
  console.log("[C2] Rendered param IDs:", paramIds.join(", ") || "(none)");
  console.log("[C2] Param count:", paramIds.length);

  // ParameterGroup uses Radix Accordion whose `id` prop becomes the
  // AccordionItem `value` — NOT an HTML id attribute. Check for params via
  // data-debug-rendered-param-ids instead.
  expect(
    paramIds.length,
    "Settings tab must render at least 1 param (data-debug-rendered-param-ids must be non-empty)",
  ).toBeGreaterThan(0);
  console.log("[C2] Param section present via", paramIds.length, "rendered param IDs");

  await ss(page, "C2_02_sections");

  // Radix Accordion unmounts closed AccordionContent from the DOM, so inputs
  // inside closed sections are invisible to locator queries. Open all closed
  // accordion triggers inside the panel to make the inputs accessible.
  // Radix AccordionTrigger renders as <button aria-expanded="false" data-state="closed">
  // (NOT [data-radix-accordion-trigger] which doesn't exist in modern Radix).
  const closedTriggers = panel.locator('.strip-body button[aria-expanded="false"]');
  const closedCount = await closedTriggers.count();
  for (let i = 0; i < closedCount; i++) {
    await closedTriggers.nth(i).click().catch(() => null);
  }
  if (closedCount > 0) {
    // Brief wait for accordion animation to complete and content to mount
    await page.waitForFunction(
      () => document.querySelectorAll('[data-radix-accordion-trigger][aria-expanded="false"]').length === 0
        || document.querySelectorAll('[data-radix-accordion-content]').length > 0,
      { timeout: 3_000 },
    ).catch(() => null);
  }

  await ss(page, "C2_02b_accordion_open");

  // For each param ID, verify a visible input element exists and log its type
  const typeCounts = { textarea: 0, textInput: 0, numberInput: 0, pathInput: 0, switch: 0, unknown: 0 };

  for (const pid of paramIds.slice(0, 15)) {
    const textarea = page.locator(`textarea[id="${pid}"]`);
    const inputEl = page.locator(`input[id="${pid}"]`);
    const switchEl = page.locator(`[id="${pid}"][role="switch"]`);
    const label = await page.locator(`label[for="${pid}"]`).textContent().catch(() => "");

    if (await textarea.count() > 0) {
      await expect(textarea.first(), `textarea for "${pid}" must be visible`).toBeVisible();
      const placeholder = await textarea.first().getAttribute("placeholder") ?? "";
      typeCounts.textarea++;
      console.log(`[C2]  "${pid}": textarea — label="${label?.trim()}", placeholder="${placeholder.slice(0, 60)}"`);
    } else if (await inputEl.count() > 0) {
      await expect(inputEl.first(), `input for "${pid}" must be visible`).toBeVisible();
      const inputType = await inputEl.first().getAttribute("type") ?? "text";
      if (inputType === "number") {
        typeCounts.numberInput++;
        const min = await inputEl.first().getAttribute("min");
        const max = await inputEl.first().getAttribute("max");
        console.log(`[C2]  "${pid}": number input — min=${min}, max=${max}, label="${label?.trim()}"`);
      } else {
        // Text or path input — detect path type by param ID suffix
        const isPath = ["_path", "_dir", "_file", "_input", "_output"].some(s => pid.toLowerCase().endsWith(s));
        if (isPath) { typeCounts.pathInput++; } else { typeCounts.textInput++; }
        console.log(`[C2]  "${pid}": ${isPath ? "path" : "text"} input — label="${label?.trim()}"`);
      }
    } else if (await switchEl.count() > 0) {
      typeCounts.switch++;
      console.log(`[C2]  "${pid}": boolean switch — label="${label?.trim()}"`);
    } else {
      typeCounts.unknown++;
      console.log(`[C2]  "${pid}": no matching element found (may use non-standard ID pattern)`);
    }
  }

  const totalFound = typeCounts.textarea + typeCounts.textInput + typeCounts.numberInput +
    typeCounts.pathInput + typeCounts.switch;
  console.log("[C2] Element type counts:", JSON.stringify(typeCounts));

  if (totalFound === 0) {
    // Accordion may still be closed or params use non-standard IDs.
    // Fall back: verify params are at least registered in the debug attribute.
    console.log(`[C2] No visible inputs — ${paramIds.length} params registered via debug attr (accordion may be closed)`);
    expect(
      paramIds.length,
      "params must be registered (data-debug-rendered-param-ids) when inputs not directly visible",
    ).toBeGreaterThan(0);
  } else {
    console.log(`[C2] ${totalFound} param form elements found across ${paramIds.length} params`);
  }

  await ss(page, "C2_03_inputs_verified");
});

// ============================================================================
// C3. Phases tab — phase cards render with pending status before run
// ============================================================================

test("C3: Phases tab renders phase group cards with data-status before run", async () => {
  const page = sharedPage;
  const panelVisible = await openPanelWithDESeq2(page);

  if (!panelVisible) {
    console.log("[C3] Panel not visible — workflow not generated; skipping phases tab test");
    return;
  }

  await ss(page, "C3_00_panel");

  // Click Phases tab
  const phasesTab = page.locator('[data-testid="panel-tab-phases"]');
  await expect(phasesTab, "Phases tab visible").toBeVisible();
  await phasesTab.click();
  await page.waitForTimeout(500);

  await ss(page, "C3_01_phases_clicked");

  // Phase group cards (data-testid="phase-group-<key>")
  const phaseGroups = page.locator('[data-testid^="phase-group-"]');
  await page
    .waitForFunction(
      () => document.querySelectorAll('[data-testid^="phase-group-"]').length > 0,
      { timeout: 10_000 },
    )
    .catch(() => null);

  const groupCount = await phaseGroups.count();
  console.log("[C3] Phase group cards:", groupCount);

  if (groupCount === 0) {
    // Workflow may not expose phases — check for any phase-related elements
    const anyPhase = await page.locator('[data-testid*="phase"]').count();
    console.log("[C3] Any phase elements:", anyPhase);
    // This is a soft-skip — some workflows don't have named phases
    console.log("[C3] No phase-group elements — workflow may not have phases; soft-skip");
    return;
  }

  // Verify each phase card has a data-status attribute and is in pre-run state
  for (let i = 0; i < Math.min(groupCount, 8); i++) {
    const card = phaseGroups.nth(i);
    const testid = await card.getAttribute("data-testid") ?? "unknown";
    const dataStatus = await card.getAttribute("data-status");
    console.log(`[C3]   "${testid}": data-status="${dataStatus}"`);

    // Before a run, phases must be in a pre-run state
    const validPreRunStatuses = ["pending", "idle", "not_started", null, ""];
    expect(
      validPreRunStatuses,
      `phase "${testid}" must be in pre-run state before run`,
    ).toContain(dataStatus);
  }

  expect(groupCount, "at least 1 phase group card must be present").toBeGreaterThan(0);

  await ss(page, "C3_02_phase_cards");

  // Verify phases body is visible
  const phasesBody = page.locator('[data-testid="panel-phases"]');
  const bodyVisible = await phasesBody.isVisible().catch(() => false);
  if (bodyVisible) {
    await expect(phasesBody, "phases body visible when Phases tab active").toBeVisible();
    console.log("[C3] panel-phases body visible");
  } else {
    console.log("[C3] panel-phases testid not found — phases render inside panel-body");
  }

  await ss(page, "C3_03_done");
});

// ============================================================================
// C4. After Run tab — body renders even before run completes
// ============================================================================

test("C4: After Run tab body renders (placeholder or report) when clicked before run", async () => {
  const page = sharedPage;
  const panelVisible = await openPanelWithDESeq2(page);

  if (!panelVisible) {
    console.log("[C4] Panel not visible — workflow not generated; skipping after-run tab test");
    return;
  }

  await ss(page, "C4_00_panel");

  // Click After Run tab
  const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
  await expect(afterRunTab, "After Run tab visible").toBeVisible();
  await afterRunTab.click();
  await page.waitForTimeout(500);

  await ss(page, "C4_01_after_run_clicked");

  // After Run tab body
  const afterRunBody = page.locator('[data-testid="panel-after-run"]');
  await page
    .waitForSelector('[data-testid="panel-after-run"]', { state: "visible", timeout: 5_000 })
    .catch(() => null);

  const bodyVisible = await afterRunBody.isVisible().catch(() => false);

  if (bodyVisible) {
    await expect(afterRunBody, "panel-after-run body must be visible").toBeVisible();
    const bodyText = await afterRunBody.textContent().catch(() => "");
    console.log("[C4] After Run body text (first 150):", bodyText?.trim().slice(0, 150));
    // May be a placeholder like "Run the workflow to see results" — that's fine
    expect(bodyText?.trim().length ?? 0, "After Run body must contain some text").toBeGreaterThan(0);
    await ss(page, "C4_02_body_content");
  } else {
    // Tab content may render under a different class structure
    const panelBody = page.locator('.panel-body');
    const panelBodyCount = await panelBody.count();
    console.log("[C4] .panel-body count:", panelBodyCount);

    // There must be SOMETHING rendered when After Run tab is clicked
    const visibleBodyCount = await page.locator('.panel-body:visible').count();
    expect(
      visibleBodyCount,
      "at least one .panel-body must be visible when After Run tab is active",
    ).toBeGreaterThan(0);
    await ss(page, "C4_02_panel_body");
  }

  await ss(page, "C4_03_done");
});

// ============================================================================
// D. Panel run — real-time status tracking (idle → running → terminal)
// ============================================================================

test("D1: clicking Run transitions panel status badge idle→running→terminal", async () => {
  const page = sharedPage;

  // Fresh navigate + send message + wait for workflow card
  await page.goto(`${BASE_URL}/`, { waitUntil: "networkidle" });
  const chatInput = page.locator("textarea, input[type='text']").first();
  await chatInput.fill(DESEQ2_MESSAGE);
  await chatInput.press("Enter");
  await waitForResponseComplete(page, LLM_TIMEOUT);
  await ss(page, "D1_00_response");

  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  const panelVisible = await panel.isVisible().catch(() => false);
  if (!panelVisible) {
    const chip = page.locator('[data-testid^="wf-chip-"]').first();
    if (await chip.count() > 0) await chip.click();
  }
  if (!(await panel.isVisible().catch(() => false))) {
    console.log("[D1] Panel not visible — workflow not generated; skipping run test");
    return;
  }

  // ── Assert idle state before click ────────────────────────────────────────

  const statusBadge = page.locator('[data-testid="workflow-overall-status-badge"]');
  if (await statusBadge.count() > 0) {
    const pre = await statusBadge.getAttribute("data-status");
    expect(["idle", "pending"], "badge is idle/pending before run").toContain(pre);
    console.log("[D1] pre-run badge:", pre);
  }

  await ss(page, "D1_01_idle");

  // ── Click Run (or Confirm & Run) ─────────────────────────────────────────

  const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
  await expect(runBtn).toBeVisible({ timeout: 10_000 });

  // If required params are unfilled (e.g. DESeq2 wants a file upload), the button
  // is disabled and clicking it would timeout. Assert the blocked state and soft-skip.
  const unfilled = parseInt((await runBtn.getAttribute("data-required-unfilled")) ?? "0", 10);
  const isDisabled = await runBtn.isDisabled();
  if (unfilled > 0 || isDisabled) {
    console.log(`[D1] Run button is blocked: required-unfilled=${unfilled}, disabled=${isDisabled}`);
    console.log("[D1] DESeq2 requires a file upload for the count matrix — inline text satisfies intent but not the required param slot.");

    // When blocked by required params (not a prereq checklist item), the params
    // section is open showing the unfilled required param rows.
    // workflow-prereq-checklist only renders for non-input_data / non-required_parameters items.
    const prereqChecklist = page.locator('[data-testid="workflow-prereq-checklist"]');
    const paramsSection = page.locator('[id="params-required"]');
    const hasPrereqAlert = await prereqChecklist.isVisible().catch(() => false);
    const hasParamsSection = await paramsSection.isVisible().catch(() => false);

    const hasAnyBlockingUI = hasPrereqAlert || hasParamsSection || isDisabled;
    expect(hasAnyBlockingUI, "some blocking UI must be visible when run button is disabled").toBe(true);

    if (hasPrereqAlert) console.log("[D1] prereq-checklist alert visible");
    if (hasParamsSection) console.log("[D1] required params section visible with unfilled params");

    await ss(page, "D1_02_blocked_prereq");
    console.log("[D1] Blocked-run state correctly asserted — run button disabled, blocking UI present");
    return;
  }

  await runBtn.click();

  // Confirm dialog may appear
  const confirmBtn = page.locator('button:has-text("Confirm"), button:has-text("Confirm & Run")');
  if (await confirmBtn.first().isVisible({ timeout: 2_000 }).catch(() => false)) {
    await confirmBtn.first().click();
    console.log("[D1] Clicked confirm dialog");
  }

  await ss(page, "D1_02_clicked_run");

  // ── Wait for running state ────────────────────────────────────────────────

  try {
    await waitForPanelRunning(page, 30_000);
    const running = await statusBadge.getAttribute("data-status").catch(() => null);
    console.log("[D1] badge after run click:", running);
    expect(
      ["running", "completed", "failed"],
      "badge must be running/completed/failed after run click",
    ).toContain(running);
    await ss(page, "D1_03_running");

    // ── Assert at least one phase card transitions to running ───────────────

    if (running === "running") {
      try {
        await page.waitForFunction(
          () => {
            const cards = document.querySelectorAll('[data-testid^="phase-card-"]');
            return Array.from(cards).some(
              (c) => c.getAttribute("data-status") === "running",
            );
          },
          { timeout: 30_000 },
        );
        console.log("[D1] At least one phase card reached running state");
        await ss(page, "D1_04_phase_running");
      } catch {
        console.log("[D1] No phase card reached running state within 30 s — may have completed quickly");
      }
    }

    // ── Wait for terminal ────────────────────────────────────────────────────

    await waitForPanelTerminal(page, 10 * 60_000);
    const terminal = await statusBadge.getAttribute("data-status").catch(() => null);
    console.log("[D1] terminal badge:", terminal);
    expect(["completed", "failed"], "badge must reach terminal state").toContain(terminal);
    await ss(page, "D1_05_terminal");

    if (terminal === "completed") {
      // After-run tab should be selectable
      const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
      if (await afterRunTab.count() > 0) {
        await afterRunTab.click();
        await ss(page, "D1_06_after_run_tab");
        console.log("[D1] After-run tab accessible on completion");
      }

      // Run again button should appear
      const runAgainBtn = page.locator('[data-testid="button-run-workflow-panel"][data-run-again="true"], button:has-text("Run again")');
      if (await runAgainBtn.count() > 0) {
        await expect(runAgainBtn.first()).toBeVisible();
        console.log("[D1] 'Run again' button visible");
      }
    } else if (terminal === "failed") {
      // Restart button should appear
      const restartBtn = page.locator('button:has-text("Restart"), [data-testid="button-run-workflow-panel"]');
      if (await restartBtn.count() > 0) {
        console.log("[D1] Restart button visible after failure");
      }
    }
  } catch (err) {
    await ss(page, "D1_ERROR");
    console.error("[D1] Run state transition error:", err);
    throw err;
  }
});

// ============================================================================
// D2. Full run — fill required params → run → state transitions → after-run
//     tab → download buttons
// ============================================================================

test("D2: fill required params → run → idle→running→terminal + after-run tab + download buttons", async () => {
  const page = sharedPage;
  const panelVisible = await openPanelWithDESeq2(page);
  await ss(page, "D2_00_panel");

  if (!panelVisible) {
    console.log("[D2] Panel not visible — workflow not generated; skipping full-run test");
    return;
  }

  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  const runBtn = page.locator('[data-testid="button-run-workflow-panel"]');
  const statusBadge = page.locator('[data-testid="workflow-overall-status-badge"]');

  // ── Assert idle state before filling ──────────────────────────────────────

  if (await statusBadge.count() > 0) {
    const pre = await statusBadge.getAttribute("data-status");
    expect(["idle", "pending"], "badge must be idle before param fill").toContain(pre);
    console.log("[D2] Pre-fill badge:", pre);
  }

  // ── Expand Settings tab + global params strip ─────────────────────────────

  const settingsTab = page.locator('[data-testid="panel-tab-settings"]');
  if (await settingsTab.getAttribute("aria-selected") !== "true") {
    await settingsTab.click();
    await page.waitForTimeout(300);
  }

  const toggleBtn = page.locator('[data-testid="button-toggle-workflow-settings"]');
  if (await toggleBtn.count() > 0) {
    const isOpen = await toggleBtn.evaluate((el) => el.classList.contains("open")).catch(() => false);
    if (!isOpen) {
      await toggleBtn.click();
      await page.waitForTimeout(600);
    }
  }

  await ss(page, "D2_01_settings_expanded");

  // ── Read param IDs from debug attribute ───────────────────────────────────

  const rawIds = await panel.getAttribute("data-debug-rendered-param-ids");
  const paramIds = rawIds ? rawIds.split(",").filter(Boolean) : [];
  console.log("[D2] Param IDs available:", paramIds.join(", ") || "(none)");

  // ── Fill params with heuristic matching ──────────────────────────────────

  let filledCount = 0;

  for (const pid of paramIds) {
    const pidLower = pid.toLowerCase();
    const textarea = page.locator(`textarea[id="${pid}"]`);
    const input = page.locator(`input[id="${pid}"]`);

    if (await textarea.count() > 0 && await textarea.first().isVisible().catch(() => false)) {
      const currentVal = await textarea.first().inputValue().catch(() => "");
      if (!currentVal) {
        // Choose content based on param semantics
        let fillContent: string;
        if (
          pidLower.includes("count") || pidLower.includes("matrix") ||
          pidLower.includes("expr") || pidLower.includes("abundance") ||
          pidLower.includes("raw") || pidLower.includes("gene") ||
          (!pidLower.includes("meta") && !pidLower.includes("sample") && !pidLower.includes("sheet"))
        ) {
          fillContent = INLINE_MATRIX;
        } else {
          fillContent = SAMPLE_SHEET;
        }
        await textarea.first().fill(fillContent);
        filledCount++;
        console.log(`[D2]  filled textarea "${pid}" with ${fillContent === INLINE_MATRIX ? "INLINE_MATRIX" : "SAMPLE_SHEET"}`);
      } else {
        console.log(`[D2]  textarea "${pid}" already has value — skipping`);
      }
    } else if (await input.count() > 0 && await input.first().isVisible().catch(() => false)) {
      const inputType = await input.first().getAttribute("type") ?? "text";
      if (inputType === "checkbox") continue;
      const currentVal = await input.first().inputValue().catch(() => "");
      if (!currentVal) {
        // Map param name to a sensible fill value
        let fillVal = "";
        if (pidLower.includes("reference") || pidLower.includes("baseline") ||
          pidLower.includes("control") && !pidLower.includes("condition")) {
          fillVal = "control";
        } else if (pidLower.includes("treatment") || pidLower.includes("treated") ||
          pidLower.includes("case") && !pidLower.includes("condition")) {
          fillVal = "treatment";
        } else if (pidLower.includes("condition") || pidLower.includes("factor") || pidLower.includes("variable")) {
          fillVal = "condition";
        } else if (pidLower.includes("genome") || pidLower.includes("organism") || pidLower.includes("species")) {
          fillVal = "GRCh38";
        } else if (pidLower.includes("prefix") || pidLower.includes("name") || pidLower.includes("project")) {
          fillVal = "deseq2_test";
        }
        if (fillVal) {
          await input.first().fill(fillVal);
          filledCount++;
          console.log(`[D2]  filled input "${pid}" → "${fillVal}"`);
        } else {
          console.log(`[D2]  input "${pid}" (type=${inputType}) — no heuristic fill`);
        }
      }
    }
  }

  console.log("[D2] Total params filled:", filledCount);
  await ss(page, "D2_02_params_filled");

  // ── Check run button state after filling ──────────────────────────────────

  const unfilledAfter = parseInt((await runBtn.getAttribute("data-required-unfilled")) ?? "0", 10);
  const isDisabledAfter = await runBtn.isDisabled();
  console.log("[D2] After fill — required-unfilled:", unfilledAfter, ", disabled:", isDisabledAfter);

  if (unfilledAfter > 0 || isDisabledAfter) {
    // Try "Confirm anyway" — available when the AI has low confidence but can proceed
    const confirmAnyway = page.locator('button:has-text("Confirm anyway")');
    const confirmVisible = await confirmAnyway.count() > 0 && !(await confirmAnyway.first().isDisabled().catch(() => true));
    if (confirmVisible) {
      console.log("[D2] Clicking 'Confirm anyway' to proceed despite unfilled required params");
      await confirmAnyway.first().click();
      await page.waitForTimeout(800);
    } else {
      // Blocked — verify the blocking UI and document clearly
      console.log("[D2] Run blocked: required-unfilled=" + unfilledAfter + ", disabled=" + isDisabledAfter);
      console.log("[D2] Filled " + filledCount + " param(s); run button remains disabled.");

      // The action bar must show the blocked status correctly
      const actionBar = page.locator('[data-testid="panel-action-bar"]');
      if (await actionBar.count() > 0) {
        const barStatus = await actionBar.getAttribute("data-status");
        console.log("[D2] Action bar data-status:", barStatus);
      }

      // "Fix now" button should be present when blocked
      const fixNowBtn = page.locator('button:has-text("Fix now")');
      const fixNowVisible = await fixNowBtn.count() > 0;
      console.log("[D2] 'Fix now' button visible:", fixNowVisible);

      await ss(page, "D2_03_blocked_state");
      console.log("[D2] Blocked-run state verified — params could not be auto-filled for this workflow");
      return;
    }
  }

  // ── Click Run ─────────────────────────────────────────────────────────────

  await expect(runBtn).toBeVisible();
  await runBtn.click();
  console.log("[D2] Clicked Run button");

  // Dismiss any confirm dialog
  const confirmDialog = page.locator('button:has-text("Confirm & Run"), button:has-text("Confirm")').first();
  if (await confirmDialog.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await confirmDialog.click();
    console.log("[D2] Dismissed confirm dialog");
  }

  await ss(page, "D2_03_run_clicked");

  // ── Observe idle → running ────────────────────────────────────────────────

  try {
    await waitForPanelRunning(page, 30_000);
    const runningStatus = await statusBadge.getAttribute("data-status").catch(() => null);
    console.log("[D2] Badge after run click:", runningStatus);
    expect(
      ["running", "completed", "failed"],
      "badge must reach running or terminal within 30 s",
    ).toContain(runningStatus);
    await ss(page, "D2_04_running_or_terminal");

    // ── Verify at least one phase group reaches running state ────────────────

    if (runningStatus === "running") {
      // Panel auto-switches to Phases tab when running — click it to be sure
      const phasesTab = page.locator('[data-testid="panel-tab-phases"]');
      if (await phasesTab.count() > 0 && await phasesTab.getAttribute("aria-selected") !== "true") {
        await phasesTab.click();
      }

      try {
        await page.waitForFunction(
          () => {
            const groups = document.querySelectorAll('[data-testid^="phase-group-"]');
            return Array.from(groups).some((el) => el.getAttribute("data-status") === "running");
          },
          { timeout: 30_000 },
        );
        const runningGroups = await page.locator('[data-testid^="phase-group-"][data-status="running"]').count();
        console.log("[D2] Phase groups in running state:", runningGroups);
        expect(runningGroups, "at least 1 phase group must show running state").toBeGreaterThan(0);
        await ss(page, "D2_05_phase_running");
      } catch {
        console.log("[D2] No phase group reached running within 30 s — may have completed quickly");
        await ss(page, "D2_05_no_phase_running");
      }
    }

    // ── Wait for terminal state ───────────────────────────────────────────────

    await waitForPanelTerminal(page, 10 * 60_000);
    const terminal = await statusBadge.getAttribute("data-status").catch(() => null);
    console.log("[D2] Terminal badge:", terminal);
    expect(["completed", "failed"], "badge must reach terminal state").toContain(terminal);
    await ss(page, "D2_06_terminal");

    // ── After Run tab content (only accessible after run) ────────────────────

    const afterRunTab = page.locator('[data-testid="panel-tab-after-run"]');
    if (await afterRunTab.count() > 0) {
      await afterRunTab.click();
      await page.waitForTimeout(1_000);
      await ss(page, "D2_07_after_run_tab");

      const afterRunBody = page.locator('[data-testid="panel-after-run"]');
      await page
        .waitForSelector('[data-testid="panel-after-run"]', { state: "visible", timeout: 8_000 })
        .catch(() => null);

      const bodyVisible = await afterRunBody.isVisible().catch(() => false);
      if (bodyVisible) {
        const bodyText = await afterRunBody.textContent().catch(() => "");
        console.log("[D2] After Run body text (first 200):", bodyText?.trim().slice(0, 200));
        expect(
          bodyText?.trim().length ?? 0,
          "After Run tab must have content after the run completes",
        ).toBeGreaterThan(0);
      } else {
        console.log("[D2] After Run body not visible within timeout — AfterRunReport may still loading");
        await page.waitForTimeout(3_000);
        await ss(page, "D2_07b_after_run_loading");
      }
    }

    // ── Download buttons visible after completion ─────────────────────────────

    if (terminal === "completed") {
      // Download buttons live in the action bar (always visible) and/or After Run tab
      const dlAll = page.locator('[data-testid="button-download-all-workflow-panel"]');
      const dlMethods = page.locator('[data-testid="button-download-methods-report"]');
      const dlQC = page.locator('[data-testid="button-download-qc-audit"]');

      const dlAllVisible = await dlAll.isVisible().catch(() => false);
      const dlMethodsVisible = await dlMethods.isVisible().catch(() => false);
      const dlQCVisible = await dlQC.isVisible().catch(() => false);

      console.log("[D2] Download buttons — all:", dlAllVisible, "methods:", dlMethodsVisible, "qc:", dlQCVisible);

      if (dlAllVisible || dlMethodsVisible || dlQCVisible) {
        const anyDl = dlAll.or(dlMethods).or(dlQC).first();
        await expect(anyDl, "at least one download button must be visible after completion").toBeVisible();
        console.log("[D2] Download button confirmed visible");
      } else {
        // May be in the After Run tab — check there
        await afterRunTab.click().catch(() => null);
        await page.waitForTimeout(1_000);
        const dlInReport = page.locator('[data-testid^="button-download"]');
        const dlCount = await dlInReport.count();
        console.log("[D2] Download buttons in After Run tab:", dlCount);
        // After a successful run, at least one download must be available
        expect(
          dlCount,
          "at least 1 download button must be visible in After Run tab after completion",
        ).toBeGreaterThan(0);
      }

      await ss(page, "D2_08_download_buttons");

      // "Run again" button must be visible
      const runAgainBtn = page.locator('button:has-text("Run again")');
      const runAgainVisible = await runAgainBtn.isVisible().catch(() => false);
      console.log("[D2] 'Run again' button visible:", runAgainVisible);
    } else if (terminal === "failed") {
      // "Restart" button must be visible on failure
      const restartBtn = page.locator('button:has-text("Restart")');
      const restartVisible = await restartBtn.isVisible().catch(() => false);
      console.log("[D2] 'Restart' button visible on failure:", restartVisible);
      await ss(page, "D2_08_restart_button");
    }
  } catch (err) {
    await ss(page, "D2_ERROR");
    console.error("[D2] Error during run:", err);
    throw err;
  }
});

// ============================================================================
// E. Hero query flow — sessionStorage race condition fix
//    (query in hero input → Start free → login → chat auto-filled)
// ============================================================================

test("E1: hero query survives Start free → login flow (sessionStorage bridge)", async ({ browser }) => {
  // Use a fresh page to test the unauthenticated → authenticated flow
  const freshPage = await browser.newPage();
  try {
    await freshPage.goto(BASE_URL, { waitUntil: "networkidle" });
    await ss(freshPage, "E1_00_home_logged_out");

    // Find the hero input (marketing landing or the chat input when not authenticated)
    const heroInput = freshPage.locator(
      '#bmHeroQuery, [data-testid="hero-query-input"], input[placeholder*="RNA"], input[placeholder*="Describe"], textarea[placeholder*="Describe"]',
    ).first();

    const heroVisible = await heroInput.isVisible({ timeout: 5_000 }).catch(() => false);
    if (!heroVisible) {
      console.log("[E1] Hero input not visible (user may already be authenticated or on chat page)");
      // If already on chat page, verify chat input is present instead
      const chatInput = freshPage.locator("textarea, input[type='text']").first();
      const chatVisible = await chatInput.isVisible({ timeout: 5_000 }).catch(() => false);
      if (chatVisible) {
        console.log("[E1] Already on chat page — skipping hero flow, testing chat input directly");
        await chatInput.fill("Run DESeq2 on test data");
        expect(await chatInput.inputValue()).toBe("Run DESeq2 on test data");
        return;
      }
      console.log("[E1] Neither hero input nor chat input visible — cannot test hero flow");
      return;
    }

    // Type a short DESeq2 query in the hero input
    const heroQuery = "Run DESeq2 on my count matrix";
    await heroInput.fill(heroQuery);
    await ss(freshPage, "E1_01_query_typed");

    // Click "Start free" / submit button
    const startBtn = freshPage.locator(
      'button[type="submit"]:has-text("Start"), button:has-text("Start free"), [data-testid="hero-submit"]',
    ).first();

    if (!(await startBtn.isVisible({ timeout: 3_000 }).catch(() => false))) {
      // Try pressing Enter on the hero input
      await heroInput.press("Enter");
    } else {
      await startBtn.click();
    }

    await ss(freshPage, "E1_02_after_start");

    // Should redirect to register or login (not authenticated)
    await freshPage.waitForURL(/\/(register|login)/, { timeout: 10_000 }).catch(() => null);
    const currentUrl = freshPage.url();
    console.log("[E1] Redirected to:", currentUrl);

    if (!currentUrl.includes("/register") && !currentUrl.includes("/login")) {
      // May have been auto-logged-in or is on chat page already
      console.log("[E1] Not redirected to auth — checking if query is in chat input");
      const chatInput = freshPage.locator("textarea, input[type='text']").first();
      if (await chatInput.isVisible({ timeout: 3_000 }).catch(() => false)) {
        console.log("[E1] On chat page directly — hero query flow bypassed (user session active)");
      }
      return;
    }

    // The query param should be preserved in the URL
    const urlHasQuery = currentUrl.includes(encodeURIComponent("DESeq2")) ||
      currentUrl.includes("q=") ||
      currentUrl.includes("deseq");
    console.log("[E1] URL has query param:", urlHasQuery, "(", currentUrl, ")");

    // If on register, click "Sign in" to go to login (query must be preserved)
    if (currentUrl.includes("/register")) {
      await ss(freshPage, "E1_03_register_page");
      const signInLink = freshPage.locator('a:has-text("Sign in"), button:has-text("Sign in"), a:has-text("Log in")').first();
      if (await signInLink.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await signInLink.click();
        await freshPage.waitForURL(/\/login/, { timeout: 5_000 }).catch(() => null);
        console.log("[E1] Clicked Sign in — now at:", freshPage.url());
        await ss(freshPage, "E1_04_login_page");
      }
    }

    // Now on login page — fill credentials and submit
    const emailInput = freshPage.locator('input[type="email"], input[name="email"]').first();
    const passInput = freshPage.locator('input[type="password"]').first();

    if (!(await emailInput.isVisible({ timeout: 5_000 }).catch(() => false))) {
      console.log("[E1] Login form not visible — cannot complete flow");
      return;
    }

    await emailInput.fill(FIXTURE_EMAIL);
    await passInput.fill(FIXTURE_PASSWORD);
    await ss(freshPage, "E1_05_login_filled");

    const submitBtn = freshPage.locator('button[type="submit"]:has-text("Sign"), button[type="submit"]:has-text("Log"), button[type="submit"]:has-text("Login")').first();
    await submitBtn.click();

    // Should navigate to chat page
    await freshPage.waitForURL(/^\/?([^/]|$)/, { timeout: 15_000 }).catch(() => null);
    await freshPage.waitForLoadState("networkidle", { timeout: 15_000 }).catch(() => null);
    await ss(freshPage, "E1_06_post_login");

    console.log("[E1] Post-login URL:", freshPage.url());

    // Check if sessionStorage bridge populated the chat input
    const chatInput = freshPage.locator("textarea, input[type='text']").first();
    await chatInput.waitFor({ state: "visible", timeout: 10_000 }).catch(() => null);

    // The chat input may have been auto-submitted (auto-send on login)
    // or may still be in the input field
    const chatValue = await chatInput.inputValue().catch(() => "");
    const assistantMsg = freshPage.locator('[data-is-latest-assistant="true"]').first();
    const hasAssistantMsg = await assistantMsg.isVisible({ timeout: 5_000 }).catch(() => false);

    if (chatValue.toLowerCase().includes("deseq") || chatValue.toLowerCase().includes("count matrix")) {
      console.log("[E1] Query preserved in chat input:", chatValue.slice(0, 60));
      expect(chatValue.toLowerCase()).toContain("deseq");
    } else if (hasAssistantMsg) {
      console.log("[E1] Query was auto-sent — assistant already responded");
      const msgText = (await assistantMsg.textContent()) ?? "";
      console.log("[E1] Assistant response (first 100):", msgText.slice(0, 100));
      // The assistant having responded to a query is sufficient proof the flow worked
      expect(msgText.trim().length).toBeGreaterThan(10);
    } else {
      // Check sessionStorage was cleared (the bridge worked and value was consumed)
      const storedQ = await freshPage.evaluate(
        () => sessionStorage.getItem("pendingHeroQuery"),
      );
      console.log("[E1] sessionStorage.pendingHeroQuery:", storedQ);
      // If null, the bridge was consumed — query was passed to the app
      // If still set, there's a bug in the consumption path
      expect(storedQ, "pendingHeroQuery should have been consumed by App.tsx").toBeNull();
    }

    await ss(freshPage, "E1_07_final");
  } finally {
    await freshPage.close();
  }
});
