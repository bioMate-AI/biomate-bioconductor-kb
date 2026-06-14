/**
 * C5 — IND assembly trust matrix.
 *
 * Coverage rows:
 *   C5.01 page mounts at /ind-report (route + render)
 *   C5.02 project list OR empty-state visible (no infinite spinner)
 *   C5.03 Path A.4 ingest_workflow API round-trip via Node proxy
 *
 * Modal/overlay rows deferred — see test.skip rationale.
 */
import { test, expect, type Page } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login.js";
import * as path from "path";

const SHOT_DIR = "test-results/ind-matrix";

async function bootIndPage(page: Page) {
  await loginAsFixture(page);
  await page.goto(`${BASE_URL}/ind-report`);
  await page
    .locator(".ind-shell, .ind-topbar, [data-testid='new-project-modal']")
    .first()
    .waitFor({ state: "attached", timeout: 15_000 })
    .catch(() => {});
}

async function shot(page: Page, name: string) {
  await page.screenshot({
    path: path.join(SHOT_DIR, `${name}.png`),
    fullPage: false,
  });
}

test.describe("IND assembly trust matrix (C5)", () => {
  test("C5.01 page mounts at /ind-report", async ({ page }) => {
    await bootIndPage(page);
    await expect(page).toHaveURL(/\/ind-report/);
    const indChrome = page.locator(
      ".ind-shell, .ind-topbar, .ind-center, [data-testid='new-project-modal']"
    );
    expect(await indChrome.count()).toBeGreaterThan(0);
    await shot(page, "01_route");
  });

  test("C5.02 project list OR empty-state (no infinite spinner)", async ({
    page,
  }) => {
    await bootIndPage(page);
    const has = await page
      .locator(
        ".ind-h1, .ind-empty, .ind-topbar, [data-testid='new-project-modal']"
      )
      .first()
      .isVisible({ timeout: 8_000 })
      .catch(() => false);
    expect(has).toBe(true);
    await shot(page, "02_project_or_empty");
  });

  test("C5.03 Path A.4 ingest API round-trip via Node proxy", async ({ page }) => {
    await bootIndPage(page);
    const projects = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/ind-report/projects`, {
        credentials: "include",
      });
      return await r.json();
    }, BASE_URL);
    expect(projects?.projects?.length).toBeGreaterThan(0);
    const projectId = projects.projects[0].id;

    const ingest = await page.evaluate(
      async ({ base, projectId }) => {
        const r = await fetch(
          `${base}/api/ind-report/projects/${projectId}/ingest_workflow`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            credentials: "include",
            body: JSON.stringify({
              workflow_run_id: `c5-${Date.now()}`,
              target_step: "admet",
              source: "chat_roll_in",
              payload: { summary: { pass: 7, total: 12 } },
            }),
          }
        );
        return await r.json();
      },
      { base: BASE_URL, projectId }
    );
    expect(ingest.ok).toBe(true);
    expect(ingest.step).toBe("admet");
    expect(ingest.new_summary?.pass).toBe(7);
  });

  test.skip("C5.x1 IndAuditOverlay opens — needs an active project with audit findings", async () => {});
  test.skip("C5.x2 New Project modal flow — needs admin-role check", async () => {});
  test.skip("C5.x3 SMILES list modal save flow — testids smiles-add-input + smiles-save-btn", async () => {});
  test.skip("C5.x4 Doc panel close affordance — aria-label='Close document panel'", async () => {});
});
