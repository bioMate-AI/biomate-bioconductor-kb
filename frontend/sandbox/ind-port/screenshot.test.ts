/**
 * Captures three snapshots of the ported IND Report so a human reviewer
 * can compare against the Claude Design prototype at
 *   reference/claude_design/IND_design/BioMate IND Report.html
 *
 * Output: frontend/sandbox/ind-port/.snapshots/{main,sign,audit}.png
 *   plus full-page versions for scrollable inspection.
 */
import { test } from "@playwright/test";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const OUT = join(__dirname, ".snapshots");

test.use({ viewport: { width: 1440, height: 900 } });

test("snapshot main view", async ({ page }) => {
  await page.goto("/");
  await page.waitForSelector(".ind-shell");
  await page.screenshot({ path: join(OUT, "main.png") });
  await page.screenshot({ path: join(OUT, "main-full.png"), fullPage: true });
});

test("snapshot with Sign overlay open", async ({ page }) => {
  await page.goto("/");
  await page.waitForSelector(".ind-step-actions .ind-btn.primary");
  const sign = page.locator(".ind-step-actions .ind-btn.primary").first();
  if (await sign.count() > 0) {
    await sign.click();
    await page.waitForSelector(".sign-overlay");
    await page.screenshot({ path: join(OUT, "sign-overlay.png") });
  }
});

test("snapshot with each step expanded", async ({ page }) => {
  await page.goto("/");
  await page.waitForSelector(".ind-shell");
  // Click each step header to expand
  const steps = page.locator(".ind-step .ind-step-head");
  const n = await steps.count();
  for (let i = 0; i < n; i++) {
    await steps.nth(i).click();
  }
  await page.screenshot({ path: join(OUT, "all-steps-expanded.png"), fullPage: true });
});
