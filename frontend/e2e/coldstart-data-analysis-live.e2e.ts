/**
 * LIVE test of every Data analysis cold-start example on dev — the real path a
 * user takes: click the card row → composer is seeded + files attached → send
 * → read the real AI response. Nothing is mocked; requests are only observed.
 *
 * Per example it asserts:
 *   A. the attached files are exactly the example's own bundle (catalog /
 *      PREPARED_EXAMPLES) — no shared/default dataset, no missing file
 *   B. the sent text carries no project id / internal scaffolding
 *   C. the AI does not bounce back a "which target / please upload" question
 *      (the bundle is supposed to make the goal runnable as-is)
 *   D. a non-empty answer or a workflow card (never "undefined" in the name)
 * It STOPS before "Confirm & Run" — no AWS Batch spend.
 *
 * Results (per-example JSON + a screenshot) land in
 * e2e/execshots/coldstart-data-analysis/ for the audit step.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/coldstart-data-analysis-live.e2e.ts \
 *     --project=chromium --retries=0 --workers=4
 */
import { test, expect, type Page } from "@playwright/test";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import { COLD_DEMO_BUNDLES } from "../client/src/components/cold-start-demo-catalog";

const OUT = path.join(path.dirname(fileURLToPath(import.meta.url)), "execshots", "coldstart-data-analysis");
fs.mkdirSync(OUT, { recursive: true });

// cold-start-examples.ts imports a JSON module that Playwright's ESM loader
// rejects, so read each one-line `{ label, prompt, files? }` entry from source.
const EXAMPLES_SRC = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), "../client/src/components/cold-start-examples.ts"), "utf8");
const PREPARED_EXAMPLES = [...EXAMPLES_SRC.matchAll(/\{ label: '([^']+)', prompt: '(?:[^'\\]|\\.)*'(?:, files: \[([^\]]*)\])?/g)]
  .map((m) => ({ label: m[1], files: m[2] ? [...m[2].matchAll(/'([^']+)'/g)].map((f) => f[1]) : undefined }));

// 90 s+ for any LLM path that may produce a workflow card (CLAUDE.md rule 6).
const ANSWER_TIMEOUT = 180_000;

type Row =
  | { kind: "track"; track: string; index: number }
  | { kind: "domain"; domain: string; index: number };

// Card layout (asserted against the live DOM in the first test so it cannot drift).
const TRACKS: Record<string, number> = { "ad-hoc-compute": 3, "validated-workflows": 3, "try-sample-data": 12 };
const DOMAINS = ["dd", "txn", "gen", "fgen", "str", "prot", "clin"];
const ROWS: Row[] = [
  ...Object.entries(TRACKS).flatMap(([track, n]) => Array.from({ length: n }, (_, index) => ({ kind: "track" as const, track, index }))),
  ...DOMAINS.flatMap((domain) => [0, 1, 2].map((index) => ({ kind: "domain" as const, domain, index }))),
];
// Rows that ask BioMate to run an analysis must end in a workflow card (the
// Cloud lane), not a text reply telling the user to go find the workflow. The
// ad-hoc compute track is Instant by design; dd-2 is an evidence question.
const expectsCard = (r: Row) => (r.kind === "domain" ? !(r.domain === "dd" && r.index === 2) : r.track !== "ad-hoc-compute");
const rowId = (r: Row) => (r.kind === "track" ? `${r.track}-${r.index}` : `domain-${r.domain}-${r.index}`);

const CLARIFY = /\b(which|what) (target|dataset|data|compound|series|file|samples?|organism|genome)\b.{0,40}\?|please (provide|upload|attach|share|specify)|could you (share|provide|upload|clarify|specify)|i (need|would need) (you to|the|your) (upload|data|file)|no (files?|data) (were|was|is|are) (attached|provided)/i;
const SCAFFOLD = /\(Project [0-9a-f-]{8,}|Project [0-9a-f]{8}-[0-9a-f]{4}|use the attached files — these are inputs/i;

async function openAnalysis(page: Page) {
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  await page.getByTestId("cold-start-dashboard").waitFor({ state: "visible", timeout: 60_000 });
  await page.locator('[data-testid="cold-module-card"][data-module-id="analysis"]').getByTestId("cold-module-expand").click();
}

async function rowLocator(page: Page, r: Row) {
  if (r.kind === "track") {
    await page.getByTestId(`cold-track-${r.track}`).click();
    return page.getByTestId("cold-example").nth(r.index);
  }
  await page.getByTestId("cold-track-validated-workflows").click();
  await page.getByTestId(`cold-domain-${r.domain}`).click();
  return page.getByTestId("cold-shape").nth(r.index);
}

/** Expected attachments: the prepared example's own files, or the catalog bundle whose context was seeded. */
function expectedFiles(label: string, prompt: string): string[] | null {
  const prepared = PREPARED_EXAMPLES.find((e) => e.label === label) as { files?: readonly string[] } | undefined;
  if (prepared) return prepared.files ? [...prepared.files] : [];
  const bundle = Object.values(COLD_DEMO_BUNDLES).find((b) => prompt.includes(b.context));
  return bundle ? [...bundle.files, "demo_notes.md"] : null;
}

test.describe.configure({ mode: "parallel" });

test("card layout matches the declared rows", async ({ page }) => {
  await loginAsFixture(page);
  await openAnalysis(page);
  for (const [track, n] of Object.entries(TRACKS)) {
    await page.getByTestId(`cold-track-${track}`).click();
    if (track !== "validated-workflows") await expect(page.getByTestId("cold-example"), track).toHaveCount(n);
  }
  await page.getByTestId("cold-track-validated-workflows").click(); // domain chips live on this track
  for (const d of DOMAINS) {
    await page.getByTestId(`cold-domain-${d}`).click();
    await expect(page.getByTestId("cold-shape"), d).toHaveCount(3);
    await page.getByTestId(`cold-domain-${d}`).click(); // clear
  }
});

for (const r of ROWS) {
  test(`live ${rowId(r)}`, async ({ page }) => {
    test.setTimeout(ANSWER_TIMEOUT + 120_000);
    await loginAsFixture(page);
    await openAnalysis(page);
    const row = await rowLocator(page, r);
    const label = (await row.innerText()).split("\n")[0].trim().replace(/^[“"]|[”"]$/g, "");
    const sent: { url: string; body: string }[] = [];
    page.on("request", (req) => {
      if (req.method() === "POST" && /chat|stream|upload|files/.test(req.url())) sent.push({ url: req.url(), body: (req.postData() || "").slice(0, 4000) });
    });
    await row.click();

    const composer = page.getByTestId("chat-input");
    await expect(composer).not.toHaveValue("", { timeout: 60_000 });
    const prompt = await composer.inputValue();
    const attached = await page.getByTestId("composer-attached-file").evaluateAll((els) => els.map((e) => e.getAttribute("data-filename") || ""));
    const want = expectedFiles(label, prompt);
    await page.screenshot({ path: path.join(OUT, `${rowId(r)}-seeded.png`) }).catch(() => {});

    await page.getByTestId("chat-send-button").click();
    // Done = the stop button is gone and an assistant message with content exists.
    const assistant = page.locator('[data-role="assistant"]').last();
    await assistant.waitFor({ state: "visible", timeout: ANSWER_TIMEOUT });
    // Done = no stop button, no progress placeholder, and the reply text has
    // been stable for 10 s (the stream can pause between plan and answer).
    const PLACEHOLDER = /Preparing the plan|Understanding your goal|Thinking|Analy[sz]ing|Searching|Working on it|Finding|Generating|…\s*$/i;
    const panelReady = page.locator('[data-testid="workflow-artifact-panel"] [data-testid="button-run-workflow-panel"]');
    const deadline = Date.now() + ANSWER_TIMEOUT;
    let last = "", stableSince = Date.now();
    while (Date.now() < deadline) {
      const now = (await page.locator('[data-role="assistant"]').allInnerTexts()).join("\n");
      if (now !== last) { last = now; stableSince = Date.now(); }
      const busy = (await page.getByTestId("chat-stop-button").count()) > 0 || PLACEHOLDER.test(now.trim());
      if ((await panelReady.count()) > 0 && !busy) break; // workflow card is the terminal state of a Cloud goal
      if (!busy && Date.now() - stableSince > 20_000) break;
      await page.waitForTimeout(2_000);
    }
    const answer = (await page.locator('[data-role="assistant"]').allInnerTexts()).join("\n---\n");
    const userText = (await page.locator('[data-role="user"]').allInnerTexts()).join("\n");
    const workflowNames = await page.locator('.wf-chip-name, [data-testid="workflow-artifact-panel"] .panel-name').allInnerTexts();
    await page.screenshot({ path: path.join(OUT, `${rowId(r)}-answer.png`), fullPage: true }).catch(() => {});

    const result = {
      row: rowId(r), label, prompt, attached, expectedFiles: want,
      userText, workflowNames: workflowNames.map((t) => t.slice(0, 200)), answer: answer.slice(0, 6000),
      clarifying: CLARIFY.exec(answer)?.[0] ?? null,
      leaks: answer.match(/s3:\/\/[^\s)]+|\/uploads\/[0-9a-f-]{36}/g) ?? [],
      timedOutInProgress: PLACEHOLDER.test(answer.trim()),
      requests: sent.map((s) => s.url),
    };
    fs.writeFileSync(path.join(OUT, `${rowId(r)}.json`), JSON.stringify(result, null, 2));

    expect.soft(want, `A: no bundle resolved for "${label}"`).not.toBeNull();
    if (want) expect.soft([...attached].sort(), `A: attachments for "${label}"`).toEqual([...want].sort());
    expect.soft(userText + prompt, "B: project id / scaffolding in the query").not.toMatch(SCAFFOLD);
    expect.soft(result.clarifying, `C: AI asked for inputs the example should provide`).toBeNull();
    expect.soft(answer.trim().length + workflowNames.join("").length, "D: empty response").toBeGreaterThan(80);
    expect.soft(result.timedOutInProgress, "D: still in progress at timeout").toBe(false);
    expect.soft(result.leaks, "B: internal storage path shown to the user").toEqual([]);
    if (expectsCard(r)) expect.soft(workflowNames.length, `E: "${label}" produced no workflow card`).toBeGreaterThan(0);
    expect.soft(workflowNames.join(" "), "D: workflow name undefined").not.toMatch(/\bundefined\b/);
  });
}
