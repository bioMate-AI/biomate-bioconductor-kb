/**
 * Workflow Panel — Merged Comprehensive E2E (2026-06-09)
 *
 * One use case (chat-routes-DESeq2 → workflow panel opens), every UI
 * element of the updated left workflow panel checked in a single test
 * via test.step. Auth + chat-routing pays its LLM cost ONCE per run,
 * not 12×.
 *
 * Replaces the stale ux-workflow-panel-comprehensive.e2e.ts class-based
 * selectors with the current `data-testid` surface from the latest viewer
 * (462606601f, d997a62ef8, a5f8af1751, a8f32f2f45, c12f9eb1e0). Uses the
 * proven Playwright `request.post` auth pattern from
 * allometric-qc-coverage.e2e.ts (lowercase header, `termsAccepted`,
 * register-then-login-for-token) — bypasses the rate-limit middleware via
 * X-E2E-Test-Token correctly.
 *
 * Steps (one test, many assertion blocks for localized failures):
 *   step 02  panel-tabs has Workflow settings + Phases + After run
 *   step 03  workflow settings strip toggle reveals params
 *   step 04  Phases tab: phase-group-* with data-status
 *   step 05  phase header expand reveals expanded state
 *   step 06  panel-action-bar: cancel button reachable
 *   step 07  run button enabled + Run/Confirm label
 *   step 08  cost-estimate-badge present
 *   step 09  qc-gate-inline testid surface intact (conditional)
 *   step 10  ai-analysis-panel OR analyze-results button present
 *   step 11  required panel testids all present in DOM
 *
 * BIOMATE_URL (default https://dev-public.biomate.ai) + E2E_TEST_TOKEN.
 * Hits the live backend; no page.route mocks.
 */

import { test, expect, type APIRequestContext } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const SS_DIR = path.join(__dirname, "screenshots", "workflow-panel-merged");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// Real, deliverable fixture email per CLAUDE.md / Testing Rules. Made-up
// addresses cause unverified-email quota degradation that surfaces as
// intermittent 401s from /api/ai_assistant/generate_workflow.
const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

async function getAuthToken(request: APIRequestContext): Promise<string> {
  await request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { name: "WPM Fixture", email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, termsAccepted: true },
  }).catch(() => null);
  const r = await request.post(`${BASE_URL}/api/auth/login`, {
    headers: { "x-e2e-test-token": E2E_TOKEN, "content-type": "application/json" },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  expect(r.ok(), `login: HTTP ${r.status()}`).toBeTruthy();
  return (await r.json()).token;
}

test("WPM: workflow panel — every updated UI element wired to backend", async ({ page, request }) => {
  test.setTimeout(8 * 60 * 1000);

  // ---- setup: login + chat → panel (pays LLM cost ONCE) ----------------
  const token = await getAuthToken(request);
  await page.context().addCookies([{
    name: "biomate_token", value: token, url: BASE_URL,
    httpOnly: false, secure: true, sameSite: "Lax",
  }]);
  await page.goto(BASE_URL);
  await page.waitForLoadState("domcontentloaded");

  const input = page.locator(
    '[data-testid="chat-input"], textarea[placeholder*="ask" i], textarea[placeholder*="message" i], textarea[placeholder*="run" i]'
  ).first();
  await input.waitFor({ timeout: 20_000 });
  await input.fill(
    "Run DESeq2 differential expression on the airway example dataset; treated vs untreated; export results CSV + MA plot."
  );
  await page.keyboard.press("Enter");

  await page.locator('[data-testid="panel-tabs"]').waitFor({ timeout: 180_000 });
  await page.screenshot({ path: path.join(SS_DIR, "00_panel_open.png"), fullPage: true });

  await test.step("panel-tabs: Workflow settings + Phases + After run", async () => {
    const tabs = page.locator('[data-testid="panel-tabs"]');
    await expect(tabs).toBeVisible();
    await expect(tabs.locator("button:has-text('Workflow settings')")).toBeVisible();
    await expect(tabs.locator("button:has-text('Phases')")).toBeVisible();
    await expect(tabs.locator("button:has-text('After run')")).toBeVisible();
  });

  await test.step("workflow settings strip toggle reveals params", async () => {
    const toggle = page.locator('[data-testid="button-toggle-workflow-settings"]');
    if (await toggle.count() > 0) {
      await toggle.click();
      await expect(page.locator("input, textarea, select").first()).toBeVisible({ timeout: 4_000 });
    }
  });

  await test.step("Phases tab: phase-group-* with data-status", async () => {
    await page.locator('[data-testid="panel-tabs"] button:has-text("Phases")').first().click();
    await page.locator('[data-testid^="phase-group-"]').first().waitFor({ timeout: 10_000 });
    const first = page.locator('[data-testid^="phase-group-"]').first();
    const status = await first.getAttribute("data-status");
    expect(status, "phase-group must have data-status").toBeTruthy();
    expect(["pending", "running", "completed", "failed", "idle"]).toContain(status);
  });

  await test.step("phase header expand changes its open state", async () => {
    const phase = page.locator('[data-testid^="phase-group-"]').first();
    await phase.locator('.phase-head, [role="button"]').first().click().catch(() => {});
    await page.waitForTimeout(300);
    const expanded = await phase.evaluate(
      (el) => el.classList.contains("open") || (el as any).getAttribute("aria-expanded") === "true"
    );
    expect(expanded).toBeTruthy();
  });

  await test.step("panel-action: cancel button reachable", async () => {
    await expect(page.locator('[data-testid="button-cancel-workflow-panel"]')).toBeVisible();
  });

  await test.step("run button enabled with Run/Confirm label", async () => {
    const run = page.locator('[data-testid="button-run-workflow-panel"]');
    await expect(run).toBeVisible();
    await expect(run).toBeEnabled();
    expect((await run.innerText()).toLowerCase()).toMatch(/run|confirm/);
  });

  await test.step("cost-estimate-badge present", async () => {
    await expect(page.locator('[data-testid="cost-estimate-badge"]')).toBeVisible({ timeout: 6_000 });
  });

  await test.step("qc-gate-inline testid surface intact (conditional)", async () => {
    const inline = page.locator('[data-testid="qc-gate-inline"]');
    if (await inline.count() > 0) {
      await expect(page.locator('[data-testid="qc-gate-measured"]')).toBeVisible();
      await expect(page.locator('[data-testid="qc-gate-threshold"]')).toBeVisible();
      await expect(page.locator('[data-testid="qc-gate-apply"]')).toBeVisible();
      await expect(page.locator('[data-testid="qc-gate-keep"]')).toBeVisible();
    }
  });

  await test.step("ai-analysis-panel OR analyze-results button present", async () => {
    const present =
      (await page.locator('[data-testid="ai-analysis-panel"]').count()) +
      (await page.locator('[data-testid="button-analyze-results"]').count()) > 0;
    expect(present).toBeTruthy();
  });

  await test.step("required panel testids all present in DOM", async () => {
    const ids = await page.evaluate(() =>
      Array.from(document.querySelectorAll("[data-testid]"))
        .map((n) => n.getAttribute("data-testid"))
        .filter(Boolean));
    for (const r of [
      "panel-tabs",
      "button-run-workflow-panel",
      "button-cancel-workflow-panel",
      "cost-estimate-badge",
    ]) {
      expect(ids, `required testid "${r}" missing`).toContain(r);
    }
    expect(ids.some((s) => s && s.startsWith("phase-group-"))).toBeTruthy();
  });

  await page.screenshot({ path: path.join(SS_DIR, "99_panel_final.png"), fullPage: true });
});
