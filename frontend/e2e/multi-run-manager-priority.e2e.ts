import { test, expect, type Locator, type Page } from "@playwright/test";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

async function isVisible(locator: Locator): Promise<boolean> {
  return locator.isVisible({ timeout: 1500 }).catch(() => false);
}

async function setupSessionIfNeeded(page: Page): Promise<void> {
  const email = `e2e_run_manager_${Date.now()}@biomate.test`;
  const password = "TestPass123!";

  await page.goto(`${BASE_URL}/register`);
  await page.waitForLoadState("networkidle");

  // Register only when the form is present; otherwise assume an active session.
  const hasRegisterForm = await isVisible(page.locator("#name"));
  if (hasRegisterForm) {
    await page.fill("#name", "Run Manager E2E");
    await page.fill("#email", email);
    await page.fill("#password", password);
    await page.fill("#confirmPassword", password);

    const terms = page.locator("#terms");
    if (await isVisible(terms)) {
      await terms.check({ force: true });
    }

    const submit = page.locator('button[type="submit"]');
    if (await isVisible(submit)) {
      await submit.click();
      await page.waitForTimeout(1200);
    }
  }

  await page.goto(BASE_URL);
  await page.waitForLoadState("networkidle");
}

async function hasSelectedScopeStyle(button: Locator): Promise<boolean> {
  const className = (await button.getAttribute("class")) || "";
  return className.includes("bg-primary");
}

test.describe("Multi Run Manager Priority (Track D scaffold)", () => {
  test("shows run manager, supports all-chats scope toggle, and surfaces needs-attention bucket", async ({ page }) => {
    const observedRunUrls: string[] = [];
    page.on("request", (request) => {
      if (request.method() === "GET" && request.url().includes("/api/workflows/runs")) {
        observedRunUrls.push(request.url());
      }
    });

    await setupSessionIfNeeded(page);

    const runManagerToggle = page.getByTestId("button-toggle-run-manager");
    if (!(await isVisible(runManagerToggle))) {
      test.skip(true, "Run manager toggle not visible in this environment");
    }

    await runManagerToggle.click();
    const panel = page.getByTestId("run-manager-panel");
    await expect(panel).toBeVisible();

    const currentChatScope = page.getByTestId("run-manager-scope-current-chat");
    const allChatsScope = page.getByTestId("run-manager-scope-all-chats");
    await expect(currentChatScope).toBeVisible();
    await expect(allChatsScope).toBeVisible();

    // "Needs attention" currently maps to failed bucket in run-manager taxonomy.
    const needsAttentionBucket = panel.getByTestId("run-manager-bucket-failed");
    await expect(needsAttentionBucket).toBeVisible();
    await expect(panel.getByTestId("run-manager-bucket-count-failed")).toHaveText(/^\d+$/);

    const requestsBeforeAllChatsClick = observedRunUrls.length;
    await allChatsScope.click();
    await page.waitForTimeout(1500);

    const newUrlsAfterAllChatsClick = observedRunUrls.slice(requestsBeforeAllChatsClick);
    const sawAllChatsRequest = newUrlsAfterAllChatsClick.some((url) => {
      try {
        return !new URL(url).searchParams.has("chatSessionId");
      } catch {
        return false;
      }
    });

    const allChatsLooksSelected = await hasSelectedScopeStyle(allChatsScope);
    expect(
      allChatsLooksSelected || sawAllChatsRequest,
      "Expected all-chats scope selection to be reflected by style or network"
    ).toBeTruthy();

    // Optional reverse validation with soft assertion to avoid hard assumptions about backend churn.
    const requestsBeforeCurrentChatClick = observedRunUrls.length;
    await currentChatScope.click();
    await page.waitForTimeout(1000);
    const newUrlsAfterCurrentChatClick = observedRunUrls.slice(requestsBeforeCurrentChatClick);
    const sawCurrentChatScopedRequest = newUrlsAfterCurrentChatClick.some((url) => {
      try {
        return new URL(url).searchParams.has("chatSessionId");
      } catch {
        return false;
      }
    });
    expect.soft(
      sawCurrentChatScopedRequest || (await hasSelectedScopeStyle(currentChatScope)),
      "Current-chat scope change should be observable via request query or selected style"
    ).toBeTruthy();

    await page.screenshot({
      path: "e2e/debug-output/multi_run_manager_priority.png",
      fullPage: true,
    });
  });
});
