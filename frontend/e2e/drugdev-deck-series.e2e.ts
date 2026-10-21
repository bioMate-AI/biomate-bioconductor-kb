/**
 * Drug-dev deck series — per-use-case PRERUN-ONLY captures (no Batch spend).
 * For each demo: clean chat → goal typed → AI response/plan → workflow card +
 * prerun panel (name, steps, params). Stops BEFORE "Confirm & Run".
 *
 * Queries are the routing-verified set from docs/20261020_DECK_SCREENSHOT_CAPTURE_PLAN.md.
 *
 * Run:
 *   cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD='WpmFixture!2026' \
 *     npx playwright test e2e/drugdev-deck-series.e2e.ts --project=chromium --workers=1
 */
import { test } from "@playwright/test";
import * as path from "path";
import * as fs from "fs";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 });

const BASE_OUT = process.env.DECK_OUT
  || "/Users/kky/Desktop/business/bioconductor_screenshot/drugdev_decks_20261021";

const SMILES3 =
  "CC(=O)Oc1ccccc1C(=O)O, CN1C=NC2=C1C(=O)N(C(=O)N2C)C, CC(C)Cc1ccc(cc1)C(C)C(=O)O";
const ASPIRIN = "CC(=O)Oc1ccccc1C(=O)O";

// deck slug → query. Prerun-capture only; SMILES-bearing ones use the safe panel.
const DECKS: Array<{ slug: string; query: string }> = [
  { slug: "dd1-target-id", query: "Rank candidate targets for rheumatoid arthritis by tractability and genetic evidence" },
  { slug: "dd2-virtual-screening", query: "Virtual screen a compound library against EGFR with DrugCLIP" },
  { slug: "dd3-docking", query: `Dock these ligands into the EGFR binding site with AutoDock Vina: ${SMILES3}` },
  { slug: "dd4-novelty-fto", query: `Score chemical novelty and freedom-to-operate for these hits: ${SMILES3}` },
  { slug: "dd5-qsar", query: `Predict hERG cardiac safety for these SMILES with a QSAR model: ${SMILES3}` },
  { slug: "dd7-generative", query: `Use REINVENT to generate novel analogs of this scaffold optimized for QED and potency: ${ASPIRIN}` },
  { slug: "dd8-rbfe", query: `Rank this congeneric series by relative binding free energy against the reference: ${SMILES3}` },
  { slug: "dd9-md", query: "Run a molecular dynamics simulation of this protein-ligand complex" },
  { slug: "dd10-structure", query: "Predict the 3D structure of this protein sequence: GIVEQCCTSICSLYQLENYCN" },
  { slug: "dd11-retrosynthesis", query: `Plan a retrosynthetic route for this molecule: ${ASPIRIN}` },
  { slug: "dd12-pbpk", query: "Predict plasma concentration over time with a PBPK model for a 70 kg adult, oral 100 mg dose" },
  { slug: "dd13-nca", query: "Run non-compartmental PK on this concentration-time data" },
  { slug: "dd14-ames", query: `Predict AMES genotoxicity for these compounds: ${SMILES3}` },
  { slug: "dd15-cyclic-peptide", query: "Design a cyclic peptide binder against the αvβ6 integrin epitope" },
  { slug: "dd16-clinical-trial", query: "Simulate a phase 2 clinical trial for a dose range of 50, 100, 200 mg" },
];

test("drug-dev deck series — prerun captures", async ({ page }) => {
  test.setTimeout(55 * 60 * 1000);
  await loginAsFixture(page);
  fs.mkdirSync(BASE_OUT, { recursive: true });
  const summary: string[] = [];

  const newChat = async () => {
    await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
    await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
    const nc = page.getByTestId("button-new-chat");
    if ((await nc.count().catch(() => 0)) > 0) { await nc.first().click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1200); }
    await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 30_000 });
    await page.waitForTimeout(1500);
  };

  // dd17 — expert-feedback: capture the Skills & experts popover (expert packs).
  try {
    await newChat();
    const out = path.join(BASE_OUT, "dd17-expert-feedback");
    fs.mkdirSync(out, { recursive: true });
    const toggle = page.getByTestId("composer-experts-toggle");
    await toggle.first().waitFor({ state: "visible", timeout: 20_000 });
    await toggle.first().click({ timeout: 8000 });
    await page.waitForTimeout(1500);
    await page.screenshot({ path: path.join(out, "02-experts-popover.png") });
    summary.push("OK   dd17-expert-feedback (experts popover)");
  } catch (e: any) {
    summary.push("FAIL dd17-expert-feedback — " + (e?.message?.split("\n")[0] ?? e));
  }

  const only = process.env.DECK_ONLY ? process.env.DECK_ONLY.split(",") : null;
  for (const deck of DECKS) {
    if (only && !only.includes(deck.slug)) continue;
    const out = path.join(BASE_OUT, deck.slug);
    fs.mkdirSync(out, { recursive: true });
    try {
      await newChat();
      await page.screenshot({ path: path.join(out, "01-cold-start.png") });
      const input = page.getByTestId("chat-input");
      await input.click();
      await input.fill(deck.query);
      await page.waitForTimeout(600);
      await page.screenshot({ path: path.join(out, "02-goal-typed.png") });

      const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
      await send.waitFor({ state: "visible", timeout: 30_000 });
      await send.scrollIntoViewIfNeeded().catch(() => {});
      await send.click({ timeout: 15_000 }).catch(async () => { await send.click({ force: true, timeout: 10_000 }); });

      await page.waitForTimeout(8000);
      await page.screenshot({ path: path.join(out, "03-ai-response-plan.png") });

      // Wait for the prerun panel (Confirm & Run) — do NOT click it (no Batch).
      const confirm = page.getByRole("button", { name: /confirm.*run/i });
      let routed = false;
      try {
        await confirm.first().waitFor({ timeout: 150_000 });
        routed = true;
      } catch { /* may not produce a runnable card (capability/answer surface) */ }
      await page.waitForTimeout(3000);
      await page.screenshot({ path: path.join(out, "04-prerun-full-page.png") });
      const panel = page.getByTestId("workflow-right-panel");
      if ((await panel.count().catch(() => 0)) > 0) {
        await panel.first().screenshot({ path: path.join(out, "05-prerun-panel.png") }).catch(() => {});
      }
      // Record the routed workflow name for the summary.
      let wfName = "";
      try { wfName = (await panel.first().locator("h1,h2,h3,[class*='title']").first().innerText().catch(() => "")).trim().slice(0, 48); } catch {}
      summary.push(`${routed ? "OK  " : "NORUN"} ${deck.slug}${wfName ? " — " + wfName : ""}`);
    } catch (e: any) {
      summary.push("FAIL " + deck.slug + " — " + (e?.message?.split("\n")[0] ?? e));
    }
  }

  const report = summary.join("\n");
  fs.writeFileSync(path.join(BASE_OUT, "_capture_summary.txt"), report);
  console.log("\n[drugdev-decks] OUT=" + BASE_OUT + "\n" + report + "\n");
});
