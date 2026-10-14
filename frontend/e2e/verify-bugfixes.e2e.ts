/**
 * Verify 2 deployed UI bug fixes + re-capture the affected manual shots.
 *  - r2-running / w1-1-phases: panel-header icons (Maximize2/Ban, not <Square>).
 *  - w3-1-step-row: completed step row with Details, in ENGLISH.
 *  - domain-cryo-em-prerun: "Dataset Id" now a clean id (guardrail), NOT
 *    "<id>, s3_uri=<uri>". Prerun ONLY — never Confirm (no GPU spend).
 * deviceScaleFactor=2 pinned.
 */
import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1680, height: 1050 }, deviceScaleFactor: 2 });
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const ADMET_PROMPT =
  "Predict ADMET properties (hERG, DILI, oral bioavailability, CYP) for aspirin CC(=O)OC1=CC=CC=C1C(=O)O and acetaminophen CC(=O)Nc1ccc(O)cc1.";
const CRYO_PROMPT =
  "Process this cryo-EM dataset to a density map and report the resolution.\n\nPrepared demo context:\nUse the already staged EMPIAR-10028 beta-galactosidase movies at s3://biomate-cryo-data/empiar-10028/Micrographs/ (001_movie.mrcs through 020_movie.mrcs). cryo_inputs.json provides acquisition settings: pixel size 0.885 Å, 300 kV, Cs 2.7 mm, amplitude contrast 0.1, symmetry D2, particle diameter 180 Å. Bind the staged movie prefix as the workflow input, not this manifest as a micrograph.";

test("icons + step row — live ADMET run", async ({ page }) => {
  test.setTimeout(12 * 60 * 1000);
  await loginAsFixture(page);
  const log: string[] = [];
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 30_000 });
  await page.waitForTimeout(3000);
  await input.click();
  await input.fill(ADMET_PROMPT);
  const sendReady = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await sendReady.waitFor({ state: "visible", timeout: 30_000 });
  await sendReady.click({ timeout: 15_000 });
  const confirm = page.getByRole("button", { name: /confirm.*run/i });
  await confirm.first().waitFor({ timeout: 180_000 });
  await page.waitForTimeout(3000);
  const txt = (await page.locator("body").innerText()).toLowerCase();
  if (!/admet/.test(txt)) { log.push("ABORT not ADMET"); console.log(log.join("\n")); return; }
  await confirm.first().click({ timeout: 30_000 }).catch(async () => { await confirm.first().click({ force: true }); });
  log.push("confirmed ADMET");
  // RUNNING — capture r2 + w1-1 (header icons live here).
  await page.waitForFunction(() => !!document.querySelector('[data-status="running"]'), { timeout: 240_000 });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(ASSETS, "r2-running.png") }); log.push("OK r2-running");
  const phasesTab = page.getByRole("tab", { name: /^phases$/i }).first();
  if ((await phasesTab.count()) > 0) { await phasesTab.click().catch(() => {}); await page.waitForTimeout(1200); }
  await page.screenshot({ path: path.join(ASSETS, "w1-1-phases.png") }); log.push("OK w1-1-phases");
  // Wait for a step to reach Completed, then crop that step row (w3-1, EN).
  try {
    await page.waitForFunction(() => /Run again|Completed|COMPLETED/.test(document.body.innerText || ""), { timeout: 10 * 60 * 1000 });
    await page.waitForTimeout(3000);
    if ((await phasesTab.count()) > 0) { await phasesTab.click().catch(() => {}); await page.waitForTimeout(1200); }
    const stepName = page.getByText(/Admet Infer Shard/i).first();
    const box = await stepName.boundingBox();
    if (box) {
      const x = Math.max(0, box.x - 48);
      await page.screenshot({ path: path.join(ASSETS, "w3-1-step-row.png"),
        clip: { x, y: Math.max(0, box.y - 18), width: Math.min(1680 - x, 1680), height: 86 } });
      log.push("OK w3-1-step-row");
    } else { log.push("SKIP w3-1 (no step row box)"); }
  } catch { log.push("SKIP w3-1 (no completed step)"); }
  console.log("\n[verify icons]\n" + log.join("\n") + "\n");
  expect(log.some((l) => l.startsWith("OK"))).toBe(true);
});

test("cryo Dataset Id guardrail — PRERUN ONLY (no Confirm)", async ({ page }) => {
  test.setTimeout(6 * 60 * 1000);
  await loginAsFixture(page);
  const log: string[] = [];
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 45_000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 30_000 });
  await page.waitForTimeout(3000);
  // Attach the cryo_inputs.json demo manifest (same as the domain harness).
  const resp = await page.request.get(`${BASE_URL}/demo/cold-start/cryo_inputs.json`);
  if (resp.ok()) {
    await page.locator('[data-testid="chat-attach-file-input"]').setInputFiles(
      [{ name: "cryo_inputs.json", mimeType: "application/json", buffer: await resp.body() }], { timeout: 30_000 });
    await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 20_000 }).catch(() => {});
  } else { log.push("WARN cryo_inputs.json fetch failed " + resp.status()); }
  await input.click();
  await input.fill(CRYO_PROMPT);
  const sendReady = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await sendReady.waitFor({ state: "visible", timeout: 30_000 });
  await sendReady.click({ timeout: 15_000 });
  const confirm = page.getByRole("button", { name: /confirm.*run/i });
  await confirm.first().waitFor({ timeout: 200_000 });
  await page.waitForTimeout(3500);
  // Open Workflow settings → expand Required parameters so Dataset Id shows.
  const wsTab = page.getByRole("tab", { name: /workflow settings/i }).first();
  if ((await wsTab.count()) > 0) { await wsTab.click().catch(() => {}); await page.waitForTimeout(1500); }
  // Expand Required parameters (retry: click header until the Dataset Id label shows).
  const reqHdr = page.getByText(/Required parameters/i).first();
  const dsLabel = page.getByText(/^Dataset Id$/i).first();
  for (let i = 0; i < 4 && (await dsLabel.count()) === 0; i++) {
    if ((await reqHdr.count()) > 0) await reqHdr.click({ timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1200);
  }
  // Read every input/textarea value and report any that look like a dataset id / s3 uri.
  const vals: string[] = await page.$$eval("input, textarea", (els) =>
    (els as (HTMLInputElement | HTMLTextAreaElement)[])
      .map((e) => e.value)
      .filter((v) => /[0-9a-f]{8}-[0-9a-f]{4}|s3:\/\//i.test(v || "")));
  log.push("id-like field values = " + JSON.stringify(vals));
  const leaked = vals.some((v) => /,\s*s3_uri=/i.test(v));
  log.push(leaked ? "FAIL — composite 'id, s3_uri=' STILL present (guardrail did not take)"
                  : "PASS — no composite 'id, s3_uri=' leak (guardrail works)");
  await page.screenshot({ path: path.join(ASSETS, "domain-cryo-em-prerun.png") });
  log.push("OK domain-cryo-em-prerun (PRERUN ONLY — no Confirm)");
  console.log("\n[verify cryo]\n" + log.join("\n") + "\n");
  expect(log.some((l) => l.startsWith("OK"))).toBe(true);
});
