/**
 * BUG-HUNT: CHAT-DYNAMIC paths on LIVE dev.
 *
 * Goal: find REAL bugs in the cheap (LLM-chat-only, NO AWS-Batch) chat
 * surfaces that earlier harnesses skipped. We STOP at the generated
 * workflow card — we never click "Confirm & Run" / launch any Batch job.
 *
 * Rules (per CLAUDE.md §"E2E test user" / §"E2E plan discipline"):
 *   - BIOMATE_URL=https://dev-public.biomate.ai
 *   - ONE fixture (lifeifei163361@163.com), login ONCE, reuse
 *   - ONE project
 *   - 90 s per chat/LLM call
 *   - NO mocking (no page.route interception)
 *   - screenshots → e2e/execshots/bughunt-chat/
 *
 * Adversarial standard cited: CLAUDE.md §"Chat + Workflow Panel
 * Presentation Standard". We assert on the REAL rendered result and flag
 * "undefined"/blank names, chat↔panel name mismatch, stuck spinners,
 * empty/placeholder citations, wrong intent, missing cards.
 *
 * This file is a DIAGNOSTIC. Several tests are written to record evidence
 * even when the flow misbehaves (so we get a HONEST BUG/BLOCKED verdict,
 * not a fake PASS). Findings are logged with a "VERDICT:" prefix so the
 * run log is greppable.
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login.js";
import * as path from "path";
import * as fs from "fs";

// Playwright runs with cwd = frontend/ ; keep screenshots under e2e/execshots.
const SHOT_DIR = path.join("e2e", "execshots", "bughunt-chat");
const CHAT_TIMEOUT = 90_000;

// Structured findings collected across tests; dumped at the end.
type Verdict = "PASS" | "BUG" | "BLOCKED";
interface Finding {
  id: string;
  title: string;
  verdict: Verdict;
  evidence: string;
}
const findings: Finding[] = [];
function record(f: Finding) {
  findings.push(f);
  // eslint-disable-next-line no-console
  console.log(`\nVERDICT: [${f.verdict}] ${f.id} — ${f.title}\n  ${f.evidence}\n`);
}

async function shot(page: Page, name: string) {
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  await page.screenshot({ path: path.join(SHOT_DIR, `${name}.png`), fullPage: false });
}

async function bootApp(page: Page) {
  await loginAsFixture(page);
  await page.goto(BASE_URL);
  await page
    .locator('[data-testid="button-sidebar-toggle"]')
    .waitFor({ state: "visible", timeout: 20_000 });
}

/** The composer textarea (chat-input.tsx data-testid="chat-input"). */
function composer(page: Page) {
  return page.locator('[data-testid="chat-input"]');
}

/** Send a message via the textarea + Enter. */
async function send(page: Page, text: string) {
  const c = composer(page);
  await expect(c).toBeVisible({ timeout: 15_000 });
  await c.click();
  await c.fill(text);
  await c.press("Enter");
}

/**
 * Wait for the right-hand workflow panel to appear + read its name/kicker.
 * Returns null if no panel within timeout (that itself is a BUG for a
 * workflow request).
 */
async function waitForPanel(
  page: Page,
  timeout = CHAT_TIMEOUT
): Promise<{ name: string; kicker: string; hasPanel: boolean }> {
  const panel = page.locator('[data-testid="workflow-artifact-panel"]');
  try {
    await panel.first().waitFor({ state: "visible", timeout });
  } catch {
    return { name: "", kicker: "", hasPanel: false };
  }
  const name = (await panel.locator(".panel-name").first().textContent().catch(() => ""))?.trim() || "";
  const kicker = (await panel.locator(".kicker").first().textContent().catch(() => ""))?.trim() || "";
  return { name, kicker, hasPanel: true };
}

/**
 * Assistant messages carry a "BIOMATE" author label ("BIOMATE" kicker) whereas
 * user bubbles show "YOU · <time>". We scope text extraction to bubbles that
 * are NOT user bubbles by finding chat-message rows whose text starts with the
 * BIOMATE author line, and returning the LAST one's text. Falls back to the
 * full main text if the structure changed.
 */
async function assistantMessageTexts(page: Page): Promise<string[]> {
  const msgs = page.locator('[data-testid^="chat-message-"]');
  const mc = await msgs.count();
  const out: string[] = [];
  for (let i = 0; i < mc; i++) {
    const t = ((await msgs.nth(i).textContent().catch(() => "")) || "").trim();
    // User bubbles begin with "YOU ·"; assistant bubbles begin with "BIOMATE".
    if (/^BIOMATE/i.test(t) || (!/^YOU\s*·/i.test(t) && t.length > 0)) {
      out.push(t);
    }
  }
  return out;
}

/** Latest assistant text EXCLUDING the standing greeting. */
async function latestAssistantText(page: Page): Promise<string> {
  const texts = await assistantMessageTexts(page);
  const nonGreeting = texts.filter(
    (t) => !/Hello! I'm BioMate/i.test(t) || t.length > 120
  );
  const pool = nonGreeting.length > 0 ? nonGreeting : texts;
  return pool.length ? pool[pool.length - 1] : "";
}

/**
 * Robust "a NEW assistant answer arrived" wait. The standing greeting already
 * has a copy button, so we must wait for the copy-button COUNT to exceed the
 * pre-send baseline AND for the typing indicator (chat-response-pending) to be
 * gone. Returns true if a fresh answer completed, false on timeout.
 */
async function waitForNewAnswer(
  page: Page,
  baselineCopyCount: number,
  timeout = CHAT_TIMEOUT
): Promise<boolean> {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const copyN = await page
      .locator('[data-testid="button-copy-response-icon"]')
      .count()
      .catch(() => 0);
    const pending = await page
      .locator('[data-testid="chat-response-pending"]')
      .isVisible()
      .catch(() => false);
    const stop = await page
      .locator('[data-testid="chat-stop-button"]')
      .isVisible()
      .catch(() => false);
    // Fresh answer = more copy buttons than baseline AND no active
    // typing/stop signal (the response settled).
    if (copyN > baselineCopyCount && !pending && !stop) return true;
    await page.waitForTimeout(500);
  }
  return false;
}

async function copyButtonCount(page: Page): Promise<number> {
  return page
    .locator('[data-testid="button-copy-response-icon"]')
    .count()
    .catch(() => 0);
}

test.describe.configure({ mode: "serial" });

test.describe("BUG-HUNT chat-dynamic (live dev)", () => {
  test.setTimeout(180_000);

  // ── Case 1: Workflow-card generation — ADMET/hERG ────────────────────────
  test("BH1 ADMET hERG SMILES → workflow card w/ real name, panel match", async ({ page }) => {
    await bootApp(page);
    await send(
      page,
      "screen these SMILES for hERG liabilities and rank them: CCO, c1ccccc1"
    );

    const { name, kicker, hasPanel } = await waitForPanel(page);
    await shot(page, "bh1-admet");

    const chatText = (await latestAssistantText(page)).toLowerCase();
    const nameBad = !name || /undefined|untitled|^\s*$/i.test(name);
    const intentOk = /admet|herg|tox|cardio|screen|liabilit/i.test(chatText);

    if (!hasPanel) {
      record({
        id: "BH1",
        title: "ADMET/hERG workflow card",
        verdict: "BUG",
        evidence: `No workflow panel rendered within ${CHAT_TIMEOUT}ms for an explicit ADMET/hERG screening request. Chat intent-mention=${intentOk}.`,
      });
    } else if (nameBad) {
      record({
        id: "BH1",
        title: "ADMET/hERG workflow card",
        verdict: "BUG",
        evidence: `Panel rendered but name is blank/undefined/'Untitled': name="${name}", kicker="${kicker}".`,
      });
    } else {
      record({
        id: "BH1",
        title: "ADMET/hERG workflow card",
        verdict: intentOk ? "PASS" : "BUG",
        evidence: `Panel name="${name}", kicker="${kicker}". Chat mentions ADMET/hERG intent=${intentOk}. ${
          intentOk ? "" : "WRONG-INTENT: chat text does not reference ADMET/hERG."
        }`,
      });
    }
    // Soft assertions only for logging — do not fail the whole run so later
    // cases still execute and record their own verdicts.
    expect(hasPanel, "workflow panel should appear for ADMET request").toBeTruthy();
    expect(nameBad, `panel name blank/undefined: "${name}"`).toBeFalsy();
  });

  // ── Case 2: Workflow-card — RNA-seq (nf-core/rnaseq-style) ────────────────
  test("BH2 RNA-seq DE + GO → pipeline card, name consistent chat↔panel", async ({ page }) => {
    await bootApp(page);
    // New chat so we don't reuse BH1's panel.
    await page.locator('[data-testid="button-new-chat"]').first().click().catch(() => {});
    await send(
      page,
      "differential expression between treated and control then GO enrichment, human GRCh38"
    );

    const { name, kicker, hasPanel } = await waitForPanel(page);
    await shot(page, "bh2-rnaseq");

    const chatText = (await latestAssistantText(page)).toLowerCase();
    const nameBad = !name || /undefined|untitled|^\s*$/i.test(name);
    const rnaLike = /rna|deseq|differential|expression|enrich|rnaseq|nf-core/i.test(
      (name + " " + kicker + " " + chatText).toLowerCase()
    );

    if (!hasPanel) {
      record({
        id: "BH2",
        title: "RNA-seq DE+GO pipeline card",
        verdict: "BUG",
        evidence: `No workflow panel rendered within ${CHAT_TIMEOUT}ms for a differential-expression + GO request.`,
      });
    } else if (nameBad) {
      record({
        id: "BH2",
        title: "RNA-seq DE+GO pipeline card",
        verdict: "BUG",
        evidence: `Panel name blank/undefined: name="${name}", kicker="${kicker}".`,
      });
    } else {
      record({
        id: "BH2",
        title: "RNA-seq DE+GO pipeline card",
        verdict: rnaLike ? "PASS" : "BUG",
        evidence: `Panel name="${name}", kicker="${kicker}", rna/DE-related=${rnaLike}. ${
          rnaLike ? "" : "WRONG-INTENT: neither panel name nor chat references RNA-seq/DE/enrichment."
        }`,
      });
    }
    expect(hasPanel, "workflow panel should appear for RNA-seq request").toBeTruthy();
    expect(nameBad, `panel name blank/undefined: "${name}"`).toBeFalsy();
  });

  // ── Case 3: Research / citation surface ──────────────────────────────────
  test("BH3 knowledge Q (IL-23 psoriasis) → non-empty citation surface", async ({ page }) => {
    await bootApp(page);
    await page.locator('[data-testid="button-new-chat"]').first().click().catch(() => {});
    // Baseline copy-button count (the standing greeting already has one) so we
    // only accept a genuinely NEW assistant answer, not the greeting.
    const baseline = await copyButtonCount(page);
    await send(
      page,
      "what is the current evidence for IL-23 inhibition in psoriasis?"
    );

    // Also SAMPLE the busy signal during the research stream — this is the
    // window where progressStatus is set and displayTyping could flip off.
    let researchSawStop = false;
    let researchSendMidStream = 0;
    const sampleUntil = Date.now() + 8_000;
    while (Date.now() < sampleUntil) {
      const stop = await page.locator('[data-testid="chat-stop-button"]').isVisible().catch(() => false);
      const sendV = await page.locator('[data-testid="chat-send-button"]').isVisible().catch(() => false);
      const pending = await page.locator('[data-testid="chat-response-pending"]').isVisible().catch(() => false);
      if (stop) researchSawStop = true;
      // Assistant clearly working (pending indicator) but composer shows Send.
      if (pending && !stop && sendV) researchSendMidStream++;
      await page.waitForTimeout(400);
    }

    const answered = await waitForNewAnswer(page, baseline);
    // Give the structured References card a moment to render after text.
    await page.waitForTimeout(2500);
    await shot(page, "bh3-research");

    const answerText = (await latestAssistantText(page)) || "";
    // Structured citation surface: benchmark-evidence.tsx renders "References (N)".
    const refsMatch = answerText.match(/References?\s*\((\d+)\)/i);
    const refCount = refsMatch ? parseInt(refsMatch[1], 10) : 0;
    // Alt surface: citation-panel source-open rows.
    const sourceRows = await page.locator('[data-testid^="source-open-"]').count();
    const hasCitationSurface = refCount > 0 || sourceRows > 0;

    // Adversarial: is the answer just a generic essay with NO source list?
    const substantiveAnswer = /IL-?23|psorias|guselkumab|risankizumab|tildrakizumab|ustekinumab|PASI/i.test(
      answerText
    );

    const busyNote = `[busy-signal during research stream: sawStop=${researchSawStop}, sendVisibleWhilePending ticks=${researchSendMidStream}]`;
    if (!answered) {
      record({
        id: "BH3",
        title: "IL-23/psoriasis research citation surface",
        verdict: "BUG",
        evidence: `No NEW assistant answer completed within ${CHAT_TIMEOUT}ms (past the standing greeting). ${busyNote}`,
      });
    } else if (!hasCitationSurface) {
      record({
        id: "BH3",
        title: "IL-23/psoriasis research citation surface",
        verdict: "BUG",
        evidence: `Answer rendered (substantive=${substantiveAnswer}) but NO structured citation surface: References(N) count=${refCount}, source-open rows=${sourceRows}. A knowledge answer with no verifiable source list violates the citation standard. Excerpt="${answerText.slice(0, 200)}". ${busyNote}`,
      });
    } else {
      record({
        id: "BH3",
        title: "IL-23/psoriasis research citation surface",
        verdict: "PASS",
        evidence: `Citation surface present: References count=${refCount}, source-open rows=${sourceRows}. Substantive answer=${substantiveAnswer}. ${busyNote}`,
      });
    }
    // Separate finding for the research-stream busy signal (BH5 only tested the
    // workflow path; this is the progressStatus path the bug was suspected on).
    if (researchSendMidStream > 0) {
      record({
        id: "BH3b",
        title: "Composer busy signal during RESEARCH stream",
        verdict: "BUG",
        evidence: `During the research answer stream the typing indicator (chat-response-pending) was up but the composer showed the SEND button (not STOP) for ${researchSendMidStream} sampled ticks — composer looks idle mid-stream on the research path. sawStop=${researchSawStop}.`,
      });
    } else {
      record({
        id: "BH3b",
        title: "Composer busy signal during RESEARCH stream",
        verdict: "PASS",
        evidence: `Busy signal consistent on the research path (sawStop=${researchSawStop}, no send-while-pending ticks).`,
      });
    }
    expect(answered, "assistant should answer the knowledge question").toBeTruthy();
  });

  // ── Case 4: Clarification / disambiguation on ambiguous request ──────────
  test("BH4 ambiguous 'run an analysis on my data' → clarification, not silent wrong wf", async ({
    page,
  }) => {
    await bootApp(page);
    await page.locator('[data-testid="button-new-chat"]').first().click().catch(() => {});
    const baseline = await copyButtonCount(page);
    await send(page, "run an analysis on my data");

    // Two acceptable outcomes: (a) a disambiguation card, or (b) an assistant
    // message that asks a clarifying question. A silently-generated concrete
    // workflow (panel opens with a specific pipeline) is the BUG.
    // Wait for a genuine terminal state: panel visible OR a NEW assistant answer
    // (past the standing greeting). Do NOT settle on the greeting's copy button.
    let panelAppeared = false;
    const panel = page.locator('[data-testid="workflow-artifact-panel"]');
    const startWait = Date.now();
    while (Date.now() - startWait < CHAT_TIMEOUT) {
      if ((await panel.count().catch(() => 0)) > 0) {
        panelAppeared = true;
        break;
      }
      const copyN = await copyButtonCount(page);
      const pending = await page.locator('[data-testid="chat-response-pending"]').isVisible().catch(() => false);
      const stop = await page.locator('[data-testid="chat-stop-button"]').isVisible().catch(() => false);
      if (copyN > baseline && !pending && !stop) break; // fresh answer settled
      await page.waitForTimeout(500);
    }
    await page.waitForTimeout(1500);
    await shot(page, "bh4-clarify");

    const text = (await latestAssistantText(page)).toLowerCase();
    // Disambiguation card renders WorkflowDisambiguationCard; detect via its
    // prompt copy or a candidate-selection affordance.
    const disambigCard =
      (await page
        .getByText(/which workflow best fits|did you mean|choose a workflow/i)
        .count()) > 0;
    // A clarifying reply = ends-or-contains a question AND either asks about the
    // data/analysis or offers a choice ("A or B?"). Kept broad but grounded: the
    // assistant is soliciting missing information rather than silently running.
    const hasQuestion = /\?/.test(text);
    const solicitsInfo =
      /(what|which|could you|can you|please|clarify|specify|more detail|type of|kind of|dataset|data type|\bdata\b|upload|provide|are you|is your|do you|would you|tell me|let me know)/i.test(
        text
      );
    const offersChoice = /\bor\b[^?]*\?/i.test(text); // "... A or B?"
    const asksClarifying = hasQuestion && (solicitsInfo || offersChoice);
    const panelName = panelAppeared
      ? (await panel.locator(".panel-name").first().textContent().catch(() => ""))?.trim()
      : "";

    if (disambigCard || asksClarifying) {
      record({
        id: "BH4",
        title: "Ambiguous request → clarification",
        verdict: "PASS",
        evidence: `Clarification surfaced. disambigCard=${disambigCard}, asksClarifying=${asksClarifying}. panelAppeared=${panelAppeared} (name="${panelName}").`,
      });
    } else if (panelAppeared) {
      record({
        id: "BH4",
        title: "Ambiguous request → clarification",
        verdict: "BUG",
        evidence: `Silently generated a concrete workflow ("${panelName}") for a totally ambiguous request with no data attached — should have asked a clarifying question / shown disambiguation. asksClarifying=${asksClarifying}.`,
      });
    } else {
      const freshAnswer = (await copyButtonCount(page)) > baseline;
      if (!freshAnswer) {
        record({
          id: "BH4",
          title: "Ambiguous request → clarification",
          verdict: "BLOCKED",
          evidence: `No new assistant answer, no clarification card, and no workflow within ${CHAT_TIMEOUT}ms — cannot judge clarification behaviour (possible timeout/LLM stall). Excerpt="${text.slice(0, 200)}".`,
        });
      } else {
        record({
          id: "BH4",
          title: "Ambiguous request → clarification",
          verdict: "BUG",
          evidence: `Assistant answered but did NOT ask a clarifying question and did NOT show a disambiguation card for a totally ambiguous request — it neither clarified nor surfaced options. Excerpt="${text.slice(0, 220)}".`,
        });
      }
    }
    // Non-fatal: record only.
  });

  // ── Case 5: send-button / streaming signal (SUSPECTED BUG) ───────────────
  test("BH5 composer send/stop state DURING streaming — is there a reliable 'busy' signal?", async ({
    page,
  }) => {
    await bootApp(page);
    await page.locator('[data-testid="button-new-chat"]').first().click().catch(() => {});

    // Use a prompt that produces a multi-phase progress stream + a workflow
    // card (the exact scenario where progressStatus suppresses displayTyping).
    await send(
      page,
      "run RNA-seq differential expression then GO enrichment on human GRCh38"
    );

    // Poll every 400ms for up to CHAT_TIMEOUT. At each tick record whether the
    // STOP button (data-testid=chat-stop-button, only when isStreaming) OR the
    // SEND button (only when NOT streaming) is present, and whether a progress
    // line / typing indicator is visible (i.e. the assistant is clearly still
    // working). The BUG signature: SEND button visible (composer looks idle)
    // WHILE a progress line is still on screen.
    const samples: Array<{
      t: number;
      stop: boolean;
      sendEnabled: boolean;
      progressVisible: boolean;
      answered: boolean;
    }> = [];
    const start = Date.now();
    let sawStop = false;
    let idleMidStreamTicks = 0;
    let firstProgressAt = -1;
    let lastProgressAt = -1;

    while (Date.now() - start < CHAT_TIMEOUT) {
      const t = Date.now() - start;
      const stop = await page.locator('[data-testid="chat-stop-button"]').isVisible().catch(() => false);
      const sendBtn = page.locator('[data-testid="chat-send-button"]');
      const sendVisible = await sendBtn.isVisible().catch(() => false);
      // "Still working" heuristic: a progressStatus line (research phase) or a
      // typing/thinking indicator is on screen. progressStatus text is rendered
      // in the placeholder message; we detect a spinner + a phase-y line.
      const progressVisible =
        (await page
          .getByText(
            /generating|analy[sz]ing|searching|retriev|routing|planning|thinking|building the workflow|reconnecting|running|preparing|reasoning|working/i
          )
          .count()
          .catch(() => 0)) > 0;
      const answered =
        (await page.locator('[data-testid="workflow-artifact-panel"]').count().catch(() => 0)) > 0;

      if (stop) sawStop = true;
      if (progressVisible) {
        if (firstProgressAt < 0) firstProgressAt = t;
        lastProgressAt = t;
      }
      // BUG signature: assistant is clearly still working (progress line up,
      // stop button NOT shown) but composer shows the enabled Send button.
      const sendEnabled = sendVisible && !stop;
      if (progressVisible && !stop && sendVisible) idleMidStreamTicks++;

      samples.push({ t, stop, sendEnabled, progressVisible, answered });

      if (answered) break; // panel present → the card we care about arrived
      await page.waitForTimeout(400);
    }
    await shot(page, "bh5-streaming-state");

    // Characterize: during the window [firstProgressAt, lastProgressAt] (assistant
    // demonstrably working), how many ticks showed the send button instead of stop?
    const workingWindowSamples = samples.filter(
      (s) => firstProgressAt >= 0 && s.t >= firstProgressAt && s.t <= lastProgressAt
    );
    const sendVisibleWhileWorking = workingWindowSamples.filter(
      (s) => !s.stop && s.sendEnabled
    ).length;
    const stopVisibleWhileWorking = workingWindowSamples.filter((s) => s.stop).length;

    const summary =
      `sawStopButtonEver=${sawStop}; ` +
      `progressWindow=[${firstProgressAt}..${lastProgressAt}]ms over ${workingWindowSamples.length} ticks; ` +
      `ticks with SEND-visible-while-working=${sendVisibleWhileWorking}; ` +
      `ticks with STOP-visible-while-working=${stopVisibleWhileWorking}; ` +
      `total idleMidStreamTicks=${idleMidStreamTicks}.`;

    // Verdict logic:
    // - If STOP was never shown at all, there is NO busy signal → BUG.
    // - If the composer showed SEND (idle-looking) during the working window
    //   for a material number of ticks, the "answer complete" signal is
    //   unreliable / the composer looks idle mid-stream → BUG.
    if (!sawStop) {
      record({
        id: "BH5",
        title: "Composer busy signal during streaming",
        verdict: "BUG",
        evidence: `The STOP button (data-testid=chat-stop-button) NEVER appeared during a full workflow-generation stream. isStreaming is effectively never true from the composer's POV → there is NO reliable 'assistant is busy' signal for a user or harness. ${summary}`,
      });
    } else if (sendVisibleWhileWorking > 0 && workingWindowSamples.length > 0) {
      record({
        id: "BH5",
        title: "Composer busy signal during streaming",
        verdict: "BUG",
        evidence: `Composer showed the ENABLED SEND button (looks idle/ready) during ${sendVisibleWhileWorking}/${workingWindowSamples.length} ticks WHILE the assistant was still streaming a progress line. Root cause (code review): chat-interface.tsx displayTyping = ...&& !placeholderHasProgress — when a progressStatus line is streaming, displayTyping flips false, so ChatInput isStreaming=false and renders the Send button instead of Stop. A user/harness cannot distinguish 'mid-stream' from 'done'. ${summary}`,
      });
    } else {
      record({
        id: "BH5",
        title: "Composer busy signal during streaming",
        verdict: "PASS",
        evidence: `Stop button consistently shown while the assistant was working; send button did not appear mid-stream. ${summary}`,
      });
    }
    // Non-fatal — this test's purpose is to CHARACTERIZE, verdict is in the log.
  });

  test.afterAll(async () => {
    // eslint-disable-next-line no-console
    console.log("\n\n================ BUG-HUNT FINDINGS TABLE ================");
    for (const f of findings) {
      // eslint-disable-next-line no-console
      console.log(`${f.verdict.padEnd(7)} | ${f.id.padEnd(4)} | ${f.title}`);
    }
    const bugs = findings.filter((f) => f.verdict === "BUG");
    // eslint-disable-next-line no-console
    console.log(`\nCONFIRMED BUGS: ${bugs.length}`);
    for (const b of bugs) {
      // eslint-disable-next-line no-console
      console.log(`  - [${b.id}] ${b.title}: ${b.evidence}`);
    }
    // eslint-disable-next-line no-console
    console.log("========================================================\n");
    fs.mkdirSync(SHOT_DIR, { recursive: true });
    fs.writeFileSync(
      path.join(SHOT_DIR, "findings.json"),
      JSON.stringify(findings, null, 2)
    );
  });
});
