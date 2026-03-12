import { setupTestUser } from "./helpers.js";
import { test, expect } from "@playwright/test";

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";

test.setTimeout(240000);

test.describe("Feedback Feature Flags Disabled", () => {
  test.skip(
    process.env.ENABLE_UX_FEEDBACK !== "false",
    "This suite requires ENABLE_UX_FEEDBACK=false at server startup."
  );

  test("hides feedback UI and rejects feedback API writes", async ({ page, request }) => {
    await setupTestUser(page, "ff_flags");
    // API behavior: feedback endpoint disabled, telemetry endpoint no-op 204.
    const feedbackRes = await request.post(`${BASE_URL}/api/feedback`, {
      data: { feedback_type: "inline", rating: "up" },
    });
    expect(feedbackRes.status()).toBe(404);

    const telemetryRes = await request.post(`${BASE_URL}/api/telemetry/events`, {
      data: {
        event: "test.feedback.disabled",
        timestamp: new Date().toISOString(),
        payload: { probe: true },
      },
    });
    expect(telemetryRes.status()).toBe(204);

    await page.goto(BASE_URL);
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(1000);

    // Feedback affordances should not render when feature flag disabled.
    await expect(page.getByTestId("inline-feedback-thumbs-up")).toHaveCount(0);
    await expect(page.getByRole("button", { name: /report confusion/i })).toHaveCount(0);
    await expect(page.getByTestId("post-run-survey-dialog")).toHaveCount(0);
    await expect(page.getByTestId("session-end-pulse-dialog")).toHaveCount(0);
  });
});
