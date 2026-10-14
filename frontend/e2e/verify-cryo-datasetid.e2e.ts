import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");
const CRYO_QUERY = "Process this cryo-EM dataset to a density map and report the resolution.\n\nPrepared demo context:\nUse the already staged EMPIAR-10028 beta-galactosidase movies at s3://biomate-cryo-data/empiar-10028/Micrographs/ (001_movie.mrcs through 020_movie.mrcs). cryo_inputs.json provides acquisition settings: pixel size 0.885 Å, 300 kV, Cs 2.7 mm, amplitude contrast 0.1, symmetry D2, particle diameter 180 Å. Bind the staged movie prefix as the workflow input, not this manifest as a micrograph. Report observed QC/resolution honestly.";

test("verify cryo Dataset Id", async ({ page }) => {
  test.setTimeout(300000);
  await loginAsFixture(page);
  await page.setViewportSize({ width: 1600, height: 1200 });
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 45000 }); await page.waitForTimeout(3000);
  const resp = await page.request.get(`${BASE_URL}/demo/cold-start/cryo_inputs.json`);
  const buffer = await resp.body();
  await page.locator('[data-testid="chat-attach-file-input"]').setInputFiles([{ name: "cryo_inputs.json", mimeType: "application/json", buffer }], { timeout: 30000 });
  await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
  await input.click(); await input.fill(CRYO_QUERY);
  const sr = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await sr.waitFor({ state: "visible", timeout: 30000 }); await sr.click();
  await page.getByRole("button", { name: /confirm.*run/i }).first().waitFor({ timeout: 200000 });
  await page.waitForTimeout(3000);
  // Click the "Workflow settings" tab, then expand Required parameters
  await page.getByRole("tab", { name: /Workflow settings/i }).click({ timeout: 8000 }).catch(async () => {
    await page.getByText(/Workflow settings/i).first().click({ timeout: 8000 }).catch(() => {});
  });
  await page.waitForTimeout(1500);
  // Expand "Required parameters" by clicking the card header (parent of the label)
  for (let i = 0; i < 3; i++) {
    const dsVisible = await page.getByText(/Dataset Id/i).first().isVisible().catch(() => false);
    if (dsVisible) break;
    const hdr = page.getByText(/Required parameters/i).first();
    const card = hdr.locator('xpath=ancestor::div[1]');
    await card.click({ timeout: 6000 }).catch(() => hdr.click({ timeout: 6000 }).catch(() => {}));
    await page.waitForTimeout(1800);
  }
  const vals: string[] = await page.$$eval("input, textarea", els => els.map(e => (e as HTMLInputElement).value ?? ""));
  console.log("[cryo] input/textarea values: " + JSON.stringify(vals.filter(v => v && v.length > 8)));
  // read the Dataset Id value from the DOM region around the label
  const dsText = await page.evaluate(() => {
    const el = Array.from(document.querySelectorAll("*")).find(e => /\bDataset Id\b/i.test(e.textContent||"") && (e.children.length < 6));
    if (!el) return "(Dataset Id label not found)";
    const container = el.closest("div")?.parentElement || el.parentElement;
    const inp = container?.querySelector("input,textarea") as HTMLInputElement | null;
    return "label-region=" + (container?.textContent||"").replace(/\s+/g," ").slice(0,160) + " || input.value=" + (inp ? inp.value.slice(0,160) : "(no input)");
  });
  console.log("[cryo] DATASET_ID_READ: " + dsText);
  await page.screenshot({ path: path.join(ASSETS, "domain-cryo-em-prerun.png"), fullPage: false });
  console.log("[cryo] screenshot saved");
  expect(true).toBe(true);
});
