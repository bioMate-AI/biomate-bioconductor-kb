/**
 * execplan-coldstart.e2e.ts — LIVE-dev execution of the cold-start / composer /
 * chat test plan (docs/20260909_TESTPLAN_COLDSTART_COMPOSER_CHAT.md).
 *
 * Targets https://dev-public.biomate.ai. NO API mocking (CLAUDE.md §Testing
 * Rules). Single shared fixture, login ONCE (cached cookies via _fixture-login),
 * ONE project reused. Screenshots → e2e/execshots/coldstart/.
 *
 * Scope: UI-observable, high-value UCs that do NOT need a real completed
 * AWS-Batch run. Workflow-card / progress / findings UCs that require a live
 * run are SKIPPED and flagged in the delivered pass/fail table.
 *
 * All assertions use REAL data-testids read from the live components:
 *   cold-start-dashboard.tsx, chat-input.tsx, lane-preview.tsx, chat-message.tsx
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SHOT_DIR = path.join(__dirname, "execshots", "coldstart");
fs.mkdirSync(SHOT_DIR, { recursive: true });

async function shot(page: Page, name: string) {
  await page
    .screenshot({ path: path.join(SHOT_DIR, `${name}.png`), fullPage: false })
    .catch(() => {});
}

// Navigate to the root chat and wait for the cold-start dashboard to mount
// (it renders only when displayMessages.length === 0 && !isTyping).
async function gotoColdStart(page: Page) {
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  const dash = page.getByTestId("cold-start-dashboard");
  await dash.waitFor({ state: "visible", timeout: 45_000 });
  return dash;
}

const intentInput = (p: Page) => p.getByTestId("cold-intent-input");
const intentRoute = (p: Page) => p.getByTestId("cold-intent-route");
const composer = (p: Page) => p.getByTestId("chat-input");
const sendBtn = (p: Page) => p.getByTestId("chat-send-button");

test.describe("Cold-start / composer / chat — live dev exec plan", () => {
  test.describe.configure({ mode: "serial" });

  test.beforeEach(async ({ page }) => {
    await loginAsFixture(page);
  });

  // ─── §1 Cold-start dashboard ──────────────────────────────────────────────

  test("UC-CS-01 dashboard renders in a fresh empty session", async ({ page }) => {
    await gotoColdStart(page);
    await expect(
      page.locator('text=What are you trying to do?').first()
    ).toBeVisible();
    await expect(page.getByTestId("cold-intent-bar")).toBeVisible();

    const cards = page.getByTestId("cold-module-card");
    await expect(cards).toHaveCount(4);
    const ids = await cards.evaluateAll((els) =>
      els.map((e) => (e as HTMLElement).dataset.moduleId)
    );
    expect(new Set(ids)).toEqual(new Set(["search", "analysis", "design", "models"]));
    // all collapsed
    for (const el of await cards.all()) {
      await expect(el).toHaveAttribute("data-open", "false");
    }
    // Honesty: no digit-count inventory strings in card bodies (cards collapsed
    // so bodies absent — assert dashboard has no "N workflows" style text).
    const bodyText = await page.getByTestId("cold-start-dashboard").innerText();
    expect(bodyText).not.toMatch(/\b\d+\s+(workflows?|tools?|pipelines?)\b/i);
    await shot(page, "CS-01-dashboard");
  });

  test("UC-CS-02 intent bar idle: no verdict below 7 chars", async ({ page }) => {
    await gotoColdStart(page);
    await intentInput(page).fill("herg"); // 4 chars
    await page.waitForTimeout(500);
    await expect(intentRoute(page)).toHaveCount(0);
    // send enabled once any non-space char present
    await expect(page.getByTestId("cold-intent-send")).toBeEnabled();
    // whitespace-only → disabled
    await intentInput(page).fill("   ");
    await expect(page.getByTestId("cold-intent-send")).toBeDisabled();
    await shot(page, "CS-02-no-verdict");
  });

  test("UC-CS-03 intent bar routes an Instant/evidence goal", async ({ page }) => {
    await gotoColdStart(page);
    await intentInput(page).fill(
      "What is the evidence linking this target to disease?"
    );
    const route = intentRoute(page);
    await expect(route).toBeVisible();
    await expect(route).toHaveAttribute("data-lane", "instant");
    await expect(page.getByTestId("cold-intent-route-lane")).toHaveText(
      "Answer here · with sources"
    );
    await expect(page.getByTestId("cold-intent-route-domain")).toHaveText(
      "Literature"
    );
    await shot(page, "CS-03-instant-evidence");
  });

  test("UC-CS-04 intent bar routes a Cloud/ADMET goal", async ({ page }) => {
    await gotoColdStart(page);
    await intentInput(page).fill(
      "Screen these SMILES for ADMET liabilities and rank them."
    );
    const route = intentRoute(page);
    await expect(route).toBeVisible();
    await expect(route).toHaveAttribute("data-lane", "cloud");
    await expect(page.getByTestId("cold-intent-route-domain")).toHaveText(
      "Drug discovery"
    );
    await shot(page, "CS-04-cloud-admet");
  });

  test("UC-CS-05 domain read for representative DOMAIN_RULES branches", async ({
    page,
  }) => {
    await gotoColdStart(page);
    const cases: Array<[string, string, string]> = [
      ["Who holds composition-of-matter claims on this scaffold?", "Patents", "instant"],
      ["Have we assayed this scaffold before?", "Internal record", "instant"],
      ["Pull every reported structure for this target.", "Databases", "instant"],
      ["Predict the structure for this sequence.", "Structure prediction", "cloud"],
      ["Generate candidates for this target.", "Molecular design", "cloud"],
      ["Predict binding affinity for these candidates.", "Activity prediction", "cloud"],
      ["Call variants on these samples.", "Genomics", "cloud"],
      ["Process this cryo-EM set to a density map.", "Structural biology", "cloud"],
      ["Stratify this cohort by response, primary endpoint.", "Clinical", "cloud"],
      ["Plot potency against logP for this table.", "Data analysis", "instant"],
    ];
    const failures: string[] = [];
    for (const [text, dom, lane] of cases) {
      await intentInput(page).fill(text);
      const route = intentRoute(page);
      try {
        await expect(route).toBeVisible({ timeout: 3000 });
        const gotLane = await route.getAttribute("data-lane");
        const gotDom = await page
          .getByTestId("cold-intent-route-domain")
          .innerText();
        if (gotLane !== lane || gotDom.trim() !== dom) {
          failures.push(`"${text}" → got ${gotLane}/${gotDom}, want ${lane}/${dom}`);
        }
      } catch {
        failures.push(`"${text}" → NO route strip`);
      }
    }
    await shot(page, "CS-05-domain-matrix");
    expect(failures, `domain-rule mismatches:\n${failures.join("\n")}`).toEqual([]);
  });

  test("UC-CS-06 seed composer via intent-bar send (not sent)", async ({ page }) => {
    await gotoColdStart(page);
    const goal = "Call variants on these samples. Human GRCh38.";
    await intentInput(page).fill(goal);
    await page.getByTestId("cold-intent-send").click();
    await expect(composer(page)).toHaveValue(goal);
    // No user message posted → dashboard still present (mounts only when 0 msgs)
    await expect(page.getByTestId("cold-start-dashboard")).toBeVisible();
    await expect(
      page.locator('[data-testid^="chat-message-"][data-role="user"]')
    ).toHaveCount(0);
    await shot(page, "CS-06-seed-send");
  });

  test("UC-CS-07 seed composer via Enter in intent bar (not sent)", async ({
    page,
  }) => {
    await gotoColdStart(page);
    const goal =
      "Differential expression between treated and control, then GO enrichment.";
    await intentInput(page).fill(goal);
    await intentInput(page).press("Enter");
    await expect(composer(page)).toHaveValue(goal);
    await expect(page.getByTestId("cold-start-dashboard")).toBeVisible();
    await shot(page, "CS-07-seed-enter");
  });

  test("UC-CS-08/09/17 expand, single-open, collapse", async ({ page }) => {
    await gotoColdStart(page);
    const card = (id: string) =>
      page.locator(`[data-testid="cold-module-card"][data-module-id="${id}"]`);
    const expand = (id: string) =>
      card(id).getByTestId("cold-module-expand");

    // expand search
    await expand("search").click();
    await expect(card("search")).toHaveAttribute("data-open", "true");
    await expect(expand("search")).toHaveAttribute("aria-expanded", "true");
    await expect(card("search").getByTestId("cold-module-body")).toBeVisible();
    await expect(page.getByRole("tablist", { name: "Search & evidence tracks" })).toBeVisible();
    await shot(page, "CS-08-expand-search");

    // open analysis → search must auto-close (single-open)
    await expand("analysis").click();
    await expect(card("search")).toHaveAttribute("data-open", "false");
    await expect(card("analysis")).toHaveAttribute("data-open", "true");
    await expect(page.getByTestId("cold-module-body")).toHaveCount(1);
    await shot(page, "CS-09-single-open");

    // collapse analysis by re-click
    await expand("analysis").click();
    await expect(card("analysis")).toHaveAttribute("data-open", "false");
    await expect(page.getByTestId("cold-module-body")).toHaveCount(0);
    await shot(page, "CS-17-collapse");
  });

  test("UC-CS-10/11 track tabs render + select across all modules", async ({
    page,
  }) => {
    await gotoColdStart(page);
    const expand = (id: string) =>
      page
        .locator(`[data-testid="cold-module-card"][data-module-id="${id}"]`)
        .getByTestId("cold-module-expand");

    const expected: Record<string, string[]> = {
      search: ["cold-track-literature", "cold-track-databases", "cold-track-patents", "cold-track-internal"],
      analysis: ["cold-track-ad-hoc-compute", "cold-track-validated-workflows"],
      design: ["cold-track-generate", "cold-track-predict-activity", "cold-track-optimise-properties", "cold-track-rank-candidates"],
      models: ["cold-track-train", "cold-track-adapt", "cold-track-optimise"],
    };
    const missing: string[] = [];
    for (const [id, tabs] of Object.entries(expected)) {
      await expand(id).click();
      for (const t of tabs) {
        if ((await page.getByTestId(t).count()) === 0) missing.push(`${id}:${t}`);
      }
    }
    // CS-10: select Databases in search, example rows swap
    await expand("search").click(); // re-open search (single-open)
    await page.getByTestId("cold-track-databases").click();
    await expect(page.getByTestId("cold-track-databases")).toHaveAttribute("aria-selected", "true");
    await expect(
      page.locator('[data-testid="cold-example"]', {
        hasText: "Pull every reported structure for this target.",
      })
    ).toBeVisible();
    await shot(page, "CS-10-11-tracks");
    expect(missing, `missing tab testids:\n${missing.join("\n")}`).toEqual([]);
  });

  test("UC-CS-12 example row seeds composer (raw text, no curly quotes)", async ({
    page,
  }) => {
    await gotoColdStart(page);
    await page
      .locator(`[data-testid="cold-module-card"][data-module-id="design"]`)
      .getByTestId("cold-module-expand")
      .click();
    const ex = page.locator('[data-testid="cold-example"]', {
      hasText: "Generate candidates for this target with drug-like properties.",
    });
    await ex.click();
    const val = await composer(page).inputValue();
    expect(val).toBe(
      "Generate candidates for this target with drug-like properties."
    );
    expect(val).not.toContain("“"); // “
    expect(val).not.toContain("”"); // ”
    await shot(page, "CS-12-example-seed");
  });

  test("UC-CS-13/14/15/16 domain chips → shapes → seed", async ({ page }) => {
    await gotoColdStart(page);
    const analysis = page.locator(
      `[data-testid="cold-module-card"][data-module-id="analysis"]`
    );
    await analysis.getByTestId("cold-module-expand").click();

    // Ad-hoc compute active by default → NO domain chips
    await expect(page.getByTestId("cold-domain-dd")).toHaveCount(0);

    // switch to validated workflows → 6 domain chips appear
    await page.getByTestId("cold-track-validated-workflows").click();
    for (const d of ["dd", "txn", "gen", "str", "prot", "clin"]) {
      await expect(page.getByTestId(`cold-domain-${d}`)).toBeVisible();
    }
    await shot(page, "CS-13-domain-chips");

    // select Drug discovery → shapes replace examples (exactly 3)
    await page.getByTestId("cold-domain-dd").click();
    await expect(page.getByTestId("cold-domain-dd")).toHaveAttribute(
      "aria-pressed",
      "true"
    );
    const shapes = page.getByTestId("cold-shape");
    await expect(shapes).toHaveCount(3);
    await expect(
      page.locator('[data-testid="cold-shape"]', {
        hasText: "Screen a compound set for ADMET liabilities",
      })
    ).toBeVisible();
    await shot(page, "CS-14-shapes");

    // shape seeds the composer with its seed (distinct from title)
    await page
      .locator('[data-testid="cold-shape"]', {
        hasText: "Screen a compound set for ADMET liabilities",
      })
      .click();
    await expect(composer(page)).toHaveValue(
      "Screen these SMILES for ADMET liabilities and rank them by developability."
    );
    await shot(page, "CS-15-shape-seed");

    // CS-16 (content audit, subset): verify every domain shows exactly 3 shapes
    const perDomain: string[] = [];
    for (const d of ["dd", "txn", "gen", "str", "prot", "clin"]) {
      // re-open fresh to reset local state each time
      await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
      await page.getByTestId("cold-start-dashboard").waitFor({ timeout: 30_000 });
      await page
        .locator(`[data-testid="cold-module-card"][data-module-id="analysis"]`)
        .getByTestId("cold-module-expand")
        .click();
      await page.getByTestId("cold-track-validated-workflows").click();
      await page.getByTestId(`cold-domain-${d}`).click();
      const n = await page.getByTestId("cold-shape").count();
      if (n !== 3) perDomain.push(`${d}=${n}`);
    }
    expect(perDomain, `domains without 3 shapes: ${perDomain.join(",")}`).toEqual(
      []
    );
  });

  test("UC-CS-18 router self-consistency: sample card examples route non-null", async ({
    page,
  }) => {
    await gotoColdStart(page);
    const samples = [
      "What is the evidence linking this target to disease?",
      "Pull every reported structure for this target.",
      "Who holds composition-of-matter claims on this scaffold?",
      "Generate candidates for this target with drug-like properties.",
      "Train a potency predictor on our in-house assay data.",
      "Summarise this assay table and plot potency against logP.",
    ];
    const nulls: string[] = [];
    for (const s of samples) {
      await intentInput(page).fill(s);
      if ((await intentRoute(page).count()) === 0) nulls.push(s);
    }
    expect(nulls, `examples that produced NO verdict:\n${nulls.join("\n")}`).toEqual(
      []
    );
    await shot(page, "CS-18-self-consistency");
  });

  test("UC-CS-20 ARIA on cards, tabs, chips, intent bar", async ({ page }) => {
    await gotoColdStart(page);
    await expect(intentInput(page)).toHaveAttribute("aria-label", "Describe the goal");
    await expect(page.getByTestId("cold-intent-send")).toHaveAttribute(
      "aria-label",
      "Seed the composer with this goal"
    );
    const search = page.locator(
      `[data-testid="cold-module-card"][data-module-id="search"]`
    );
    await expect(search.getByTestId("cold-module-expand")).toHaveAttribute(
      "aria-expanded",
      "false"
    );
    await search.getByTestId("cold-module-expand").click();
    await expect(search.getByTestId("cold-module-expand")).toHaveAttribute(
      "aria-expanded",
      "true"
    );
    await expect(page.getByRole("tablist", { name: "Search & evidence tracks" })).toBeVisible();
    await expect(page.getByTestId("cold-track-literature")).toHaveAttribute(
      "aria-selected",
      "true"
    );
    await shot(page, "CS-20-aria");
  });

  // ─── §2 Composer (chat-input) ─────────────────────────────────────────────

  test("UC-CI-01/02 empty send disabled; typing enables", async ({ page }) => {
    await gotoColdStart(page);
    // fresh session: composer empty → send disabled
    await expect(sendBtn(page)).toBeDisabled();
    await expect(composer(page)).toHaveAttribute(
      "placeholder",
      "What would you like to analyze?"
    );
    // whitespace-only keeps disabled
    await composer(page).fill("   ");
    await expect(sendBtn(page)).toBeDisabled();
    // real text enables
    await composer(page).fill("run rna-seq on these fastqs");
    await expect(sendBtn(page)).toBeEnabled();
    // clearing re-disables
    await composer(page).fill("");
    await expect(sendBtn(page)).toBeDisabled();
    await shot(page, "CI-01-02-send-gate");
  });

  test("UC-CI-03 Shift+Enter newline; Enter sends", async ({ page }) => {
    await gotoColdStart(page);
    await composer(page).click();
    await composer(page).type("line1");
    await composer(page).press("Shift+Enter");
    await composer(page).type("line2");
    const val = await composer(page).inputValue();
    expect(val).toContain("line1");
    expect(val).toContain("line2");
    expect(val).toContain("\n");
    // dashboard should still be present (Shift+Enter did not send)
    await expect(page.getByTestId("cold-start-dashboard")).toBeVisible();
    await shot(page, "CI-03-shift-enter");
    // Enter sends → a user message appears, composer clears
    await composer(page).press("Enter");
    await expect(
      page.locator('[data-testid^="chat-message-"][data-role="user"]').first()
    ).toBeVisible({ timeout: 30_000 });
    await expect(composer(page)).toHaveValue("");
    await shot(page, "CI-03-enter-sent");
  });

  test("UC-CI-14 programmatic draft prefill focuses composer (via cold-start seed)", async ({
    page,
  }) => {
    await gotoColdStart(page);
    await intentInput(page).fill("Summarise this assay table and plot IC50.");
    await page.getByTestId("cold-intent-send").click();
    await expect(composer(page)).toHaveValue("Summarise this assay table and plot IC50.");
    // focused after seed (setTimeout focus in onRegisterSetDraft)
    await page.waitForTimeout(300);
    const focused = await composer(page).evaluate(
      (el) => el === document.activeElement
    );
    expect(focused).toBe(true);
    await shot(page, "CI-14-draft-prefill");
  });

  // ─── §3 Lane preview ──────────────────────────────────────────────────────
  // Lane preview shows local heuristic immediately, upgraded by the server
  // arbiter (POST /api/route/classify) when it answers. We assert the visible
  // data-lane (which may be server-confirmed) and the presence of read/footer.

  async function typeAndReadLane(page: Page, text: string) {
    await composer(page).fill(text);
    const lp = page.getByTestId("lane-preview");
    await lp.waitFor({ state: "visible", timeout: 10_000 });
    // let the 350ms debounce + potential server arbiter (<2.5s) settle
    await page.waitForTimeout(2800);
    return {
      lane: await lp.getAttribute("data-lane"),
      read: await page.getByTestId("lane-preview-read").innerText().catch(() => ""),
    };
  }

  test("UC-LP-01 Instant verdict for an evidence question", async ({ page }) => {
    await gotoColdStart(page);
    const { lane } = await typeAndReadLane(
      page,
      "What is the evidence linking this target to disease?"
    );
    expect(lane).toBe("instant");
    await expect(page.getByTestId("lane-preview-chip")).toContainText(
      "Answer here · with sources"
    );
    await expect(
      page.locator('text=Advisory').first()
    ).toBeVisible();
    await expect(page.getByTestId("lane-preview-override")).toBeVisible();
    await shot(page, "LP-01-instant");
  });

  test("UC-LP-02 Cloud verdict for a named method (DESeq2)", async ({ page }) => {
    await gotoColdStart(page);
    const { lane } = await typeAndReadLane(page, "Run DESeq2 on these counts.");
    expect(lane).toBe("cloud");
    await expect(page.getByTestId("lane-preview-chip")).toContainText(
      "Prepare an analysis · review before starting"
    );
    await shot(page, "LP-02-cloud-method");
  });

  test("UC-LP-03/04 Cloud via consequence verb / scale cue", async ({ page }) => {
    await gotoColdStart(page);
    const r1 = await typeAndReadLane(page, "Call variants and align these reads.");
    expect(r1.lane).toBe("cloud");
    await shot(page, "LP-03-verb");
    const r2 = await typeAndReadLane(page, "Process these 24 samples.");
    expect(r2.lane).toBe("cloud");
    await shot(page, "LP-04-scale");
  });

  test("UC-LP-05 Ad-hoc compute stays Instant", async ({ page }) => {
    await gotoColdStart(page);
    const { lane } = await typeAndReadLane(
      page,
      "Summarise this table and plot potency vs logP."
    );
    expect(lane).toBe("instant");
    await shot(page, "LP-05-adhoc-instant");
  });

  test("UC-LP-06 server arbiter present (read text de-duplicated)", async ({
    page,
  }) => {
    await gotoColdStart(page);
    const { read } = await typeAndReadLane(page, "Run DESeq2 on these counts.");
    // read must never double the "reads as" prefix (client strips server's).
    expect(read.toLowerCase()).not.toMatch(/reads as\s+reads as/);
    expect(read.toLowerCase().startsWith("reads as")).toBe(true);
    await shot(page, "LP-06-server-read");
  });

  test("UC-LP-07/08 override flips lane, clear restores", async ({ page }) => {
    await gotoColdStart(page);
    await typeAndReadLane(page, "What is the evidence for X in disease?");
    // instant verdict offers "run a validated pipeline instead" → forces cloud
    await page.getByTestId("lane-preview-override").click();
    const forced = page.getByTestId("lane-preview");
    await expect(forced).toHaveAttribute("data-lane", "cloud");
    await expect(forced).toContainText("Prepare an analysis · review before starting");
    await expect(page.getByTestId("lane-preview-clear-override")).toBeVisible();
    await shot(page, "LP-07-override");
    // clear → back to advisory verdict
    await page.getByTestId("lane-preview-clear-override").click();
    await expect(page.getByTestId("lane-preview-override")).toBeVisible();
    await shot(page, "LP-08-clear-override");
  });

  test("UC-LP-09 advisory strip never blocks send", async ({ page }) => {
    await gotoColdStart(page);
    await composer(page).fill("Run DESeq2 on these counts.");
    // send is enabled regardless of the verdict
    await expect(sendBtn(page)).toBeEnabled();
    await shot(page, "LP-09-no-block");
  });

  // ─── §4 Chat message (one live instant answer; no Batch run) ──────────────

  test("UC-CM-01/02 user bubble + AI markdown answer render (live instant)", async ({
    page,
  }) => {
    test.setTimeout(240_000);
    await gotoColdStart(page);
    const QUESTION =
      "What is the mechanism of action of aspirin? Answer briefly.";
    await composer(page).fill(QUESTION);
    await sendBtn(page).click();
    // user turn renders immediately
    const userMsg = page
      .locator('[data-testid^="chat-message-"][data-role="user"]')
      .first();
    await expect(userMsg).toBeVisible({ timeout: 30_000 });
    await shot(page, "CM-01-user-bubble");

    // NOTE (honest gate): on the research path the send-button returns while the
    // assistant bubble still shows a rotating progress line ("BioMate is
    // thinking…" → "Searching relevant literature…" → "Synthesizing findings and
    // generating response…"). So send-button visibility is NOT a reliable
    // answer-complete signal. Poll the FINAL assistant bubble until it is a real
    // answer: not the static greeting, not any progress placeholder, and long
    // enough to be prose. A stuck spinner will time out (FAIL), not fake-pass.
    const aiMsg = page
      .locator('[data-testid^="chat-message-"][data-role="assistant"]')
      .last();
    await expect(aiMsg).toBeVisible({ timeout: 30_000 });
    const PLACEHOLDER =
      /Hello! I'm BioMate|BioMate is thinking|Searching relevant|Synthesi[sz]ing|Analy[sz]ing|Working on|Routing your|Consulting|Generating response|Reading|Retrieving/i;
    await expect
      .poll(
        async () => {
          const t = (await aiMsg.innerText().catch(() => "")).trim();
          // real answer only when no placeholder phrase remains and it's prose
          return PLACEHOLDER.test(t) || t.length < 60 ? "" : t;
        },
        { timeout: 150_000, intervals: [3000] }
      )
      .not.toBe("");
    const answer = (await aiMsg.innerText()).trim();
    // aspirin MoA should mention its real pharmacology
    expect(answer.toLowerCase()).toMatch(/cox|cyclo-?oxygenase|prostaglandin|platelet|thromboxane/);
    await shot(page, "CM-02-ai-answer");
  });
});
