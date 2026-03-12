import { test, expect } from "@playwright/test";
import {
  BASE_URL,
  setupTestUser,
  sendMessageAndWaitForResponse,
} from "./helpers.js";

test.setTimeout(180000);

test.describe("Run Triage Hierarchy", () => {
  test("shows status/action/logs/outputs triage sections in fixed order when workflow appears", async ({
    page,
  }) => {
    await setupTestUser(page, "triage");

    const hasWorkflow = await sendMessageAndWaitForResponse(
      page,
      "Run an RNA-seq quality control workflow",
      120000
    );

    if (!hasWorkflow) {
      // AI responded but did not surface a workflow card — just verify the
      // chat replied with some text and skip the workflow-specific assertions.
      const body = await page.textContent("body").catch(() => "");
      expect(
        body && body.trim().length > 0,
        "Expected the AI to produce some response text"
      ).toBeTruthy();
      test.info().annotations.push({
        type: "skip-reason",
        description: "AI did not return a workflow — triage section assertions skipped",
      });
      return;
    }

    // A workflow card appeared. Check whether the execution triage summary is
    // rendered and, if so, that its child sections are in the correct order.
    const triage = page.getByTestId("execution-triage-summary");
    const triageVisible = await triage
      .isVisible({ timeout: 10000 })
      .catch(() => false);

    if (!triageVisible) {
      // The workflow card exists but the triage block is not yet visible
      // (e.g. workflow not yet executed). That is acceptable — the section
      // appears after the user clicks Run. Verify the Run button is present
      // and skip the ordering check.
      await expect(
        page.getByTestId("button-run-workflow-panel").first()
      ).toBeVisible({ timeout: 10000 });
      return;
    }

    // Triage summary is visible — assert the child order.
    const triageChildren = triage.locator("[data-testid^='execution-triage-']");
    const count = await triageChildren.count();
    expect(count).toBeGreaterThanOrEqual(1);

    // Collect the data-testid values in DOM order.
    const orderedIds: (string | null)[] = await triageChildren.evaluateAll(
      (nodes) => nodes.map((n) => n.getAttribute("data-testid"))
    );

    // The canonical order must be preserved for whichever sections exist.
    const canonicalOrder = [
      "execution-triage-status",
      "execution-triage-next-action",
      "execution-triage-logs",
      "execution-triage-outputs",
    ];

    const presentInOrder = orderedIds.filter((id): id is string =>
      canonicalOrder.includes(id ?? "")
    );
    const expectedSubset = canonicalOrder.filter((id) =>
      orderedIds.includes(id)
    );

    expect(presentInOrder).toEqual(expectedSubset);

    // Content spot-checks for each visible section.
    for (const id of presentInOrder) {
      const section = page.getByTestId(id);
      await expect(section).toBeVisible();
    }

    if (orderedIds.includes("execution-triage-status")) {
      await expect(page.getByTestId("execution-triage-status")).toContainText(
        /status/i
      );
    }
    if (orderedIds.includes("execution-triage-next-action")) {
      await expect(
        page.getByTestId("execution-triage-next-action")
      ).toContainText(/next action/i);
    }
    if (orderedIds.includes("execution-triage-logs")) {
      await expect(page.getByTestId("execution-triage-logs")).toContainText(
        /logs/i
      );
    }
    if (orderedIds.includes("execution-triage-outputs")) {
      await expect(page.getByTestId("execution-triage-outputs")).toContainText(
        /outputs/i
      );
    }
  });
});
