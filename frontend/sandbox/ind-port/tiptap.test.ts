/**
 * End-to-end test that the TipTap editor in EditableParagraph fires
 * captureEdit() when the user edits a paragraph.
 *
 * The backend isn't running in the sandbox harness, so we intercept the
 * POST and assert (a) it was made, (b) the payload shape matches
 * EditCapture from ind-report-api.ts.
 */
import { test, expect } from "@playwright/test";

test("typing into a TipTap paragraph and blurring fires captureEdit", async ({ page }) => {
  const editPosts: any[] = [];
  await page.route("**/api/ind-report/projects/*/edit", async (route) => {
    const req = route.request();
    editPosts.push({ url: req.url(), body: req.postDataJSON() });
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ recorded: true, id: "stubbed-row-id" }),
    });
  });

  await page.goto("/");
  // Wait for the first TipTap paragraph to mount
  const para = page.locator(".tiptap-paragraph").first();
  await expect(para).toBeVisible();

  // Focus, append text, then blur.
  await para.click();
  await page.keyboard.press("End");
  await page.keyboard.type(" — appended by smoke test");
  // Blur by clicking outside the editor
  await page.locator(".ind-doc-head").click();

  // EditableParagraph debounces nothing — blur should fire onSettled,
  // which calls onParaBlur in DocPanel, which calls captureEdit.
  await page.waitForTimeout(300);
  expect(editPosts.length).toBeGreaterThan(0);

  const body = editPosts[0].body;
  expect(body).toHaveProperty("paragraph_id");
  expect(body).toHaveProperty("original");
  expect(body).toHaveProperty("edited");
  expect(body).toHaveProperty("section_type");
  expect(body.edited).toContain("appended by smoke test");
  // Original should not contain the appended text (the diff is real)
  expect(body.original).not.toContain("appended by smoke test");
});

test("blurring without changes is a no-op (no captureEdit POST)", async ({ page }) => {
  const editPosts: any[] = [];
  await page.route("**/api/ind-report/projects/*/edit", async (route) => {
    editPosts.push(route.request().postDataJSON());
    await route.fulfill({ status: 200, body: "{}" });
  });

  await page.goto("/");
  const para = page.locator(".tiptap-paragraph").first();
  await expect(para).toBeVisible();
  await para.click();
  // Click outside without typing
  await page.locator(".ind-doc-head").click();
  await page.waitForTimeout(300);
  expect(editPosts.length).toBe(0);
});

test("clicking + cite icon opens the suggest popover and POSTs on submit", async ({ page }) => {
  const citePosts: any[] = [];
  await page.route("**/api/ind-report/citations/suggest", async (route) => {
    citePosts.push(route.request().postDataJSON());
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ recorded: true, id: "stubbed", queued_for_review: true }),
    });
  });

  await page.goto("/");
  await page.locator(".cite-add").first().click();
  const popover = page.locator(".cite-popover");
  await expect(popover).toBeVisible();
  await popover.locator("input").first().fill("CDE Test Guideline 2025");
  await popover.locator("textarea").fill("Applies to NMPA bridging studies");
  await popover.locator("button.primary").click();
  await page.waitForTimeout(300);
  expect(citePosts.length).toBe(1);
  expect(citePosts[0].guideline_id).toBe("CDE Test Guideline 2025");
  expect(citePosts[0].document_only).toBe(false);
});
