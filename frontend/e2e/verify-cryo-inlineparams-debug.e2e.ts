import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
const CRYO_QUERY = "Process this cryo-EM dataset to a density map and report the resolution.\n\nPrepared demo context:\nUse the already staged EMPIAR-10028 beta-galactosidase movies at s3://biomate-cryo-data/empiar-10028/Micrographs/ (001_movie.mrcs through 020_movie.mrcs). cryo_inputs.json provides acquisition settings: pixel size 0.885 Å, 300 kV, Cs 2.7 mm, amplitude contrast 0.1, symmetry D2, particle diameter 180 Å. Bind the staged movie prefix as the workflow input, not this manifest as a micrograph. Report observed QC/resolution honestly.";

test("dump cryo inline_parameters delivered to browser", async ({ page }) => {
  test.setTimeout(240000);
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
  await page.getByRole("button", { name: /confirm.*run/i }).first().waitFor({ timeout: 180000 });
  await page.waitForTimeout(2500);
  const dbg = await page.evaluate(() => {
    const el = document.querySelector("[data-debug-inline-params]");
    return el ? el.getAttribute("data-debug-inline-params") : "(no data-debug-inline-params element)";
  });
  console.log("[cryo] INLINE_PARAMS_DELIVERED: " + dbg);
  expect(true).toBe(true);
});
