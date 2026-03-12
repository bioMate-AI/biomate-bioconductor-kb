import { test, expect, type Locator, type Page } from "@playwright/test";
import { setupTestUser } from "./helpers.js";

async function isVisible(locator: Locator): Promise<boolean> {
  return locator
    .first()
    .isVisible({ timeout: 2000 })
    .catch(() => false);
}

async function expectAnyVisible(
  page: Page,
  candidates: Array<{ name: string; locator: Locator }>,
  label: string
): Promise<void> {
  for (const candidate of candidates) {
    if (await isVisible(candidate.locator)) {
      return;
    }
  }
  const available = candidates.map((c) => c.name).join(", ");
  expect(false, `Expected ${label} control to be visible. Tried: ${available}`).toBe(true);
}

test.describe("Run Manager Multi Chat Scope", () => {
  test("opens panel and renders scope/search/filter/sort controls", async ({ page }) => {
    await setupTestUser(page, "rm-multi");

    await page.getByTestId("button-toggle-run-manager").click();
    const panel = page.getByTestId("run-manager-panel");
    await expect(panel).toBeVisible({ timeout: 10000 });

    // --- Scope controls ---
    await expectAnyVisible(
      page,
      [
        { name: "scope-current-chat-testid", locator: page.getByTestId("run-manager-scope-current-chat") },
        { name: "scope-current-chat-button", locator: page.getByRole("button", { name: /current chat/i }) },
        { name: "scope-current-chat-text", locator: panel.getByText(/current chat/i) },
      ],
      "current chat scope"
    );

    await expectAnyVisible(
      page,
      [
        { name: "scope-all-chats-testid", locator: page.getByTestId("run-manager-scope-all-chats") },
        { name: "scope-all-chats-button", locator: page.getByRole("button", { name: /all chats/i }) },
        { name: "scope-all-chats-text", locator: panel.getByText(/all chats/i) },
      ],
      "all chats scope"
    );

    // --- Search control ---
    await expectAnyVisible(
      page,
      [
        { name: "search-testid", locator: page.getByTestId("run-manager-search-input") },
        { name: "searchbox-role", locator: panel.getByRole("searchbox") },
        { name: "search-placeholder", locator: panel.getByPlaceholder(/search/i) },
      ],
      "search"
    );

    // --- Filter control ---
    await expectAnyVisible(
      page,
      [
        { name: "filter-testid", locator: page.getByTestId("run-manager-filter-status") },
        { name: "filter-button", locator: panel.getByRole("button", { name: /filter/i }) },
        { name: "filter-label", locator: panel.getByText(/all statuses/i) },
      ],
      "filter"
    );

    // --- Sort control ---
    await expectAnyVisible(
      page,
      [
        { name: "sort-testid", locator: page.getByTestId("run-manager-sort-select") },
        { name: "sort-button", locator: panel.getByRole("button", { name: /sort/i }) },
        { name: "sort-label", locator: panel.getByText(/updated \(newest\)/i) },
      ],
      "sort"
    );

    // Panel must not show any error state.
    const bodyText = await page.locator("body").innerText().catch(() => "");
    expect(bodyText.toLowerCase()).not.toContain("something went wrong");
    expect(bodyText.toLowerCase()).not.toContain("unexpected error");
  });
});
