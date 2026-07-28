/**
 * UI verification of the flat-tier / Lago-drop change.
 *
 * The Lago drop has no billing UI (the /billing route is intentionally unrouted),
 * so we verify the one UI-triggerable path into the gated code: a chat that drives
 * a Galaxy-backend LLM call (workflow generation) → galaxy.ai.cost_log.record().
 * That is exactly where cost_log used to spawn a thread and POST usage to Lago.
 *
 * This test proves the UI path still works (assistant responds / workflow card).
 * The gate itself (no [CostLog->Lago] forward for the new cost_log event) is
 * confirmed out-of-band against galaxy.log around this run.
 *
 * Canonical fixture, login-only, cookie-injected. No mocks — live dev backend.
 */
import { test, expect } from "@playwright/test";
import { BASE_URL, sendChatMessage } from "./helpers.js";

const E2E_TOKEN = "biomate-e2e-bypass-token-dev-only";
const FIXTURE_EMAIL = "lifeifei163361@163.com";
const FIXTURE_PASS = process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

test.setTimeout(200_000);

test("chat drives a Galaxy LLM call and renders a response (cost_log path, Lago gated off)", async ({ page, context }) => {
  // 1) Login as the shared fixture (no register) → JWT
  const login = await page.request.post(`${BASE_URL}/api/auth/login`, {
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASS },
    headers: { "X-E2E-Test-Token": E2E_TOKEN },
  });
  expect(login.status(), "fixture login must succeed").toBe(200);
  const token = (await login.json()).token as string;
  expect(token).toBeTruthy();

  // 2) Inject the httpOnly session cookie (propagates to navigations)
  const host = new URL(BASE_URL).hostname;
  await context.addCookies([{
    name: "biomate_token", value: token, domain: host, path: "/",
    httpOnly: true, secure: BASE_URL.startsWith("https"), sameSite: "Lax",
  }]);

  // 3) Open the app (root = chat workspace); suppress the survey modal
  await page.goto(BASE_URL);
  await page.waitForLoadState("load");
  await page.evaluate(() => {
    try { localStorage.setItem("biomate_survey_suppressed_until", String(Date.now() + 7 * 86400_000)); } catch { /* ignore */ }
  });

  // 4) Send a workflow-triggering prompt → routes to the Galaxy backend
  //    (ai_assistant → LLM → cost_log.record → gated Lago forward skipped)
  await sendChatMessage(page, "Run ADMET prediction for aspirin: CC(=O)Oc1ccccc1C(=O)O");

  // 5) Poll the DOM directly for a completed assistant response OR a workflow card
  //    (robust to thinking-indicator selector drift). Generous 150s LLM budget.
  const responded = await page.waitForFunction(() => {
    const assistant = document.querySelector('[data-is-latest-assistant="true"]');
    const hasText = !!assistant && (assistant.textContent ?? "").trim().length > 40;
    const hasWorkflowCard =
      !!document.querySelector('[data-testid*="workflow" i], .wf-chip, [class*="workflow-card" i]');
    return hasText || hasWorkflowCard;
  }, { timeout: 150_000 }).then(() => true).catch(() => false);

  await page.screenshot({ path: "e2e/screenshots/chat-costlog-verify.png", fullPage: true });

  const latest = await page.locator('[data-is-latest-assistant="true"]').last().innerText().catch(() => "");
  console.log("[chat-costlog] responded =", responded);
  console.log("[chat-costlog] latest assistant text (first 200):", latest.slice(0, 200).replace(/\n/g, " "));

  // 6) The UI path must work end-to-end
  expect(responded, "assistant must respond / workflow card must render").toBe(true);
  expect(latest.trim().length, "assistant message must have real content").toBeGreaterThan(0);
});
