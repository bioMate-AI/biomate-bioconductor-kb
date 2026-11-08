/**
 * DISPATCH-ONLY: send the CRISPR cold-start example and click Confirm & Run,
 * then exit. No in-test polling (that stalled the prior harness). The parent
 * polls /api/workflows/runs via curl afterwards.
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const DEMO_ROOT = "/demo/cold-start/";
const QUERY =
  "Analyze my pooled CRISPR screen: call enriched/depleted hits at an FDR cutoff and rank the candidate dependency genes.\n\nPrepared demo context:\nUse the official MAGeCK demo: sgRNA and Gene columns, HL60.initial/HL60.final and KBM7.initial/KBM7.final. Analyze final versus initial separately within each cell line and compare depletion effects between lines. There is one column per line/time, no replicate experiment: report that limitation and do not fabricate replicate correlations.";
// No attachments: D's nfcore/crisprseq is a SELF-CONTAINED MAGeCK workflow with a
// baked demo count table (no data_input channel). Attaching files trips the input
// gate (unbound inputs) → no run persists. Dispatch input-free to test the workflow.
const ATTACH: string[] = [];

test("dispatch crispr cold-start example", async ({ page }) => {
  test.setTimeout(280_000);
  await loginAsFixture(page);
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 45_000 });
  await page.waitForTimeout(3000);

  const payloads = [];
  for (const fname of ATTACH) {
    const resp = await page.request.get(`${BASE_URL}${DEMO_ROOT}${fname}`);
    if (!resp.ok()) throw new Error(`demo file ${fname} not served (${resp.status()})`);
    payloads.push({ name: fname, mimeType: "application/octet-stream", buffer: await resp.body() });
  }
  await page.locator('[data-testid="chat-attach-file-input"]').setInputFiles(payloads, { timeout: 30_000 });
  await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 20_000 }).catch(() => {});

  await input.click();
  await input.fill(QUERY);
  await page.locator('[data-testid="chat-send-button"]:not([disabled])').waitFor({ state: "visible", timeout: 30_000 });
  await page.getByTestId("chat-send-button").click();

  // Wait for the workflow card's Confirm & run (LLM gen up to ~200s).
  const confirm = page.getByRole("button", { name: /confirm.*run/i });
  await confirm.first().waitFor({ timeout: 220_000 });

  // Safety gate: the card must be crispr/mageck before we spend a run.
  const bodyText = (await page.locator("body").innerText()).toLowerCase();
  expect(bodyText).toMatch(/crispr|mageck/);
  console.log("[crispr-dispatch] routed OK (crispr/mageck). Clicking Confirm & run…");

  const btn = confirm.first();
  await btn.scrollIntoViewIfNeeded().catch(() => {});
  await btn.click({ timeout: 15_000 }).catch(async () => { await btn.click({ timeout: 15_000, force: true }); });
  await page.waitForTimeout(12_000); // let the run row persist
  console.log("[crispr-dispatch] Confirm clicked, run dispatched. Exiting (parent polls API).");
});
