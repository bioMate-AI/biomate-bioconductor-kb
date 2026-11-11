/**
 * E2E (dev, live, no mocks): a run_code plot (1) renders in the chat UI and (2) reaches the model as an
 * IMAGE it can read — not as base64 text, and not hidden from it.
 *
 * Proof the model read the pixels: bar heights come from SHA-256 of `<seed>-<label>` (no model can
 * compute that mentally), the prompt forbids printing them, and the test asserts the values never
 * appear in the tool output. The model can then only name the tallest/shortest bar by looking at
 * the plot. Truth is recomputed here with node:crypto (same formula, any Python version).
 *
 * Fixes under test: f3e1903101/d299034c4d (plots → image blocks; image_data_uri stripped from model
 * text), 15fa8a1dd3 (OpenRouter vision adapter — dev's tool turns run on Claude, so this exercises
 * the Anthropic image-block path).
 *
 * Run: E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/run-code-plot-vision.e2e.ts
 */
import { test, expect } from "@playwright/test";
import { createHash } from "crypto";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const LABELS = ["A", "B", "C", "D", "E", "F"];
const height = (seed: string, l: string) => parseInt(createHash("sha256").update(`${seed}-${l}`).digest("hex").slice(0, 2), 16);

/** A seed whose tallest and shortest bars are unique and clearly separated from the runners-up. */
function pickSeed(): { seed: string; values: number[]; tallest: string; shortest: string } {
  for (;;) {
    const seed = `bm${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`;
    const values = LABELS.map((l) => height(seed, l));
    const s = [...values].sort((a, b) => a - b);
    if (s[5] - s[4] >= 25 && s[1] - s[0] >= 25) {
      return { seed, values, tallest: LABELS[values.indexOf(s[5])], shortest: LABELS[values.indexOf(s[0])] };
    }
  }
}

test("run_code plot renders in the UI and the model reads it as an image", async ({ page }) => {
  test.setTimeout(6 * 60 * 1000);
  const { seed, values, tallest, shortest } = pickSeed();
  const prompt =
    `Use run_code (Python) to make a bar chart. Labels: A, B, C, D, E, F. The height of label L is ` +
    `int(hashlib.sha256(f"${seed}-{L}".encode()).hexdigest()[:2], 16). Save it as bars.png with matplotlib. ` +
    `Do NOT print, log, or return the heights or any statistic of them — the code must print nothing. ` +
    `Then, looking only at the plot image, answer on one line exactly: TALLEST=<label> SHORTEST=<label>`;
  console.log(`seed=${seed} values=${values.join(",")} truth TALLEST=${tallest} SHORTEST=${shortest}`);

  await loginAsFixture(page);
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.getByTestId("chat-input").waitFor({ state: "visible", timeout: 45_000 });
  const nc = page.getByTestId("button-new-chat");
  if ((await nc.count().catch(() => 0)) > 0) { await nc.first().click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1500); }
  await page.screenshot({ path: "e2e/screenshots/run-code-plot-vision-0-pre.png" });

  const input = page.getByTestId("chat-input");
  await input.click(); await input.fill(prompt);
  const send = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await send.waitFor({ state: "visible", timeout: 30_000 });
  await send.click({ timeout: 15_000 }).catch(async () => { await send.click({ force: true }); });

  // (1) The plot renders in the chat as a real PNG.
  const fig = page.getByTestId("run-code-figure").first();
  await fig.waitFor({ state: "visible", timeout: 240_000 });
  const src = (await fig.getAttribute("src")) || "";
  expect(src.startsWith("data:image/png;base64,"), `figure src should be a PNG data URI, got ${src.slice(0, 40)}`).toBe(true);
  const natural = await fig.evaluate((img: HTMLImageElement) => (img.complete ? img.naturalWidth : 0));
  expect(natural, "figure must decode (naturalWidth > 0)").toBeGreaterThan(0);

  // Wait for the final answer line.
  const answerRe = /TALLEST\s*=\s*\*{0,2}([A-F])\b[\s\S]{0,40}?SHORTEST\s*=\s*\*{0,2}([A-F])\b/i;
  await page.waitForFunction((re) => new RegExp(re, "i").test(document.body.innerText || ""), answerRe.source, { timeout: 240_000 });
  await page.waitForTimeout(3000); // let the stream settle
  await page.screenshot({ path: "e2e/screenshots/run-code-plot-vision-1-answer.png", fullPage: true });

  // (2) The values never reached the model as text: absent from every tool block (code + stdout).
  const toolText = (await page.locator('[data-testid^="tool-block-run_code"]').allInnerTexts()).join("\n");
  const leaked = values.filter((v) => new RegExp(`(^|[^0-9])${v}([^0-9]|$)`).test(toolText));
  expect(leaked.length, `heights appeared in tool output (${leaked.join(",")}) — test cannot prove vision`).toBeLessThan(3);

  // (3) The model read the plot.
  const body = await page.locator("body").innerText();
  const m = body.match(answerRe)!;
  console.log(`model: TALLEST=${m[1]} SHORTEST=${m[2]}`);
  expect(m[1].toUpperCase(), "tallest bar (only knowable from the image)").toBe(tallest);
  expect(m[2].toUpperCase(), "shortest bar (only knowable from the image)").toBe(shortest);

  // (4) No image bytes surfaced as text anywhere in the visible chat.
  expect(/data:image\/[a-z]+;base64,[A-Za-z0-9+/]{200}/.test(body), "base64 image text visible in chat").toBe(false);
  expect(/not visible to this model/i.test(body), "model path reported the image as not visible").toBe(false);
});
