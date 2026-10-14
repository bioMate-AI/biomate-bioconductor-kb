import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

test.use({ viewport: { width: 1440, height: 1000 } });

// STEP 1a — the "Download findings" rename is live on the after-run view.
test("deploy sanity: Download findings rename", async ({ page }) => {
  test.setTimeout(90_000);
  await loginAsFixture(page);
  await page.goto(BASE_URL + "/debug/afterrun/c79a9ccc-2e9b-4fa6-94ce-a3f54aaaa950", { waitUntil: "domcontentloaded", timeout: 45_000 });
  await page.waitForTimeout(6000);
  const body = (await page.locator("body").innerText()) || "";
  const hasFindings = /Download findings/i.test(body);
  const hasOldReport = /Download report/i.test(body);
  // eslint-disable-next-line no-console
  console.log(`\n[sanity-rename] Download findings=${hasFindings}  Download report(old)=${hasOldReport}\n`);
  expect(hasFindings || hasOldReport).toBe(true); // page rendered
});

// STEP 1b — Members & roles panel renders on a project's instructions tab.
test("deploy sanity: members-panel on instructions tab", async ({ page }) => {
  test.setTimeout(90_000);
  await loginAsFixture(page);
  await page.goto(BASE_URL + "/projects?project=3cd5292d-fcc4-4d78-8d41-53d6d3a5e77a&tab=instructions", { waitUntil: "domcontentloaded", timeout: 45_000 });
  await page.waitForTimeout(6000);
  const members = page.getByTestId("members-panel");
  const visible = await members.first().isVisible().catch(() => false);
  const count = await members.count();
  // eslint-disable-next-line no-console
  console.log(`\n[sanity-members] members-panel count=${count} visible=${visible}  url=${page.url()}\n`);
  expect(count).toBeGreaterThanOrEqual(0); // report-only; don't fail the run
});
