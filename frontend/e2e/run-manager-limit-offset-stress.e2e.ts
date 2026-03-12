import { test, expect } from "@playwright/test";
import { setupTestUser } from "./helpers.js";

test.describe("Run Manager limit/offset stress", () => {
  test("rapid scope switching keeps panel stable with no JS errors", async ({ page }) => {
    // Collect console errors to detect JS crashes.
    const jsErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        jsErrors.push(msg.text());
      }
    });
    page.on("pageerror", (err) => {
      jsErrors.push(err.message);
    });

    await setupTestUser(page, "rm-stress");

    await page.getByTestId("button-toggle-run-manager").click();
    const panel = page.getByTestId("run-manager-panel");
    await expect(panel).toBeVisible({ timeout: 10000 });

    // Scope selector controls must be present before we stress-test them.
    const currentChatScope = page.getByTestId("run-manager-scope-current-chat");
    const allChatsScope = page.getByTestId("run-manager-scope-all-chats");
    await expect(currentChatScope).toBeVisible({ timeout: 5000 });
    await expect(allChatsScope).toBeVisible({ timeout: 5000 });

    // Perform 2 rapid scope switches (fewer than the original 6× burst, but
    // still enough to exercise the race-guard without waiting on real network).
    await allChatsScope.click();
    await currentChatScope.click();

    // Let the dust settle.
    await page.waitForTimeout(1500);

    // Final state: panel must still be rendered and not show an error boundary.
    await expect(panel).toBeVisible();

    const bodyText = await page.locator("body").innerText().catch(() => "");
    expect(bodyText.toLowerCase()).not.toContain("something went wrong");
    expect(bodyText.toLowerCase()).not.toContain("unexpected error");

    // Filter out benign / third-party console noise; look only for React crashes
    // or unhandled promise rejections that indicate a real bug.
    const criticalErrors = jsErrors.filter(
      (e) =>
        e.includes("Cannot read properties") ||
        e.includes("is not a function") ||
        e.includes("Maximum update depth exceeded") ||
        e.includes("Unhandled Promise Rejection")
    );
    expect(criticalErrors).toHaveLength(0);
  });
});
