/**
 * Live dig E2E for the two screenshot bugs (2026-11-13):
 *
 *   Flow A — CryoSPARC must ASK for a license and hard-block Confirm / execute
 *            without a user credential (no silent CRYOSPARC_LICENSE env fallback).
 *   Flow B — Run Manager (All chats) click must open the owning chat on the left,
 *            not only the right workflow panel on an empty New Chat.
 *
 * Discipline (CLAUDE.md): login once, no /register, one fixture, screenshots for audit.
 * Stops before any GPU Batch spend.
 *
 * Run:
 *   cd frontend && E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *     BIOMATE_URL=https://dev-public.biomate.ai \
 *     npx playwright test e2e/run-manager-chat-and-cryosparc-license.e2e.ts \
 *     --project=chromium --retries=0
 */
import { test, expect, type APIRequestContext, type Page } from "@playwright/test";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { randomUUID } from "crypto";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const OUT = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "execshots",
  "run-manager-cryosparc-license",
);
fs.mkdirSync(OUT, { recursive: true });

async function shot(page: Page, name: string) {
  const p = path.join(OUT, `${name}.png`);
  await page.screenshot({ path: p, fullPage: true });
  console.log(`[shot] ${p}`);
  return p;
}

async function chatFinal(
  req: APIRequestContext,
  message: string,
  sessionId: string,
): Promise<any> {
  const r = await req.post(BASE_URL + "/api/chat/stream", {
    data: {
      message,
      stream: true,
      context: { sessionId, uiLanguage: "en" },
    },
    timeout: 180_000,
  });
  expect(r.ok(), `chat HTTP ${r.status()}`).toBe(true);
  const text = await r.text();
  const blocks = text.split("\n\n");
  for (let i = blocks.length - 1; i >= 0; i--) {
    if (!/^event:\s*final/m.test(blocks[i])) continue;
    const data = blocks[i]
      .split("\n")
      .filter((l) => l.startsWith("data:"))
      .map((l) => l.slice(5).trim())
      .join("\n");
    return JSON.parse(data);
  }
  throw new Error("no final event from chat/stream");
}

test.describe.configure({ mode: "serial" });

test("CryoSPARC license ask+block and Run Manager opens owning chat", async ({ page }) => {
  test.setTimeout(12 * 60 * 1000);
  await loginAsFixture(page);
  const req = page.request;

  // ── Flow A1: API license-requirements hard-blocks cryosparc without user key ──
  const del = await req.delete(BASE_URL + "/api/users/credentials/cryosparc");
  console.log("[A1] delete cryosparc credential →", del.status());

  const lic = await req.get(
    BASE_URL +
      "/api/workflows/license-requirements?nextflow_path=" +
      encodeURIComponent("cryosparc_standard_spa/main.nf"),
  );
  expect(lic.ok(), `license-requirements HTTP ${lic.status()}`).toBe(true);
  const licBody = await lic.json();
  const cryo = (licBody.requirements || []).find(
    (r: any) => r.tool_id === "cryosparc",
  );
  expect(cryo, "cryosparc must appear in license-requirements").toBeTruthy();
  expect(cryo.source, "no user key → source none").toBe("none");
  expect(cryo.has_fallback, "cryosparc has no open fallback").toBeFalsy();
  console.log("[A1] cryosparc requirement:", JSON.stringify(cryo));

  // ── Flow A2: execute without license → 402 (backend hard block) ──
  const exec = await req.post(BASE_URL + "/api/workflows/execute", {
    data: {
      workflowDefinition: {
        name: "Cryosparc Standard Spa",
        workflow_type: "cryosparc",
        nextflow_path:
          "biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf",
        parameters: { pixel_size: 1.05, voltage: 300 },
      },
      inputs: [],
      chatSessionId: `e2e-cs-lic-${randomUUID()}`,
    },
    timeout: 60_000,
  });
  const execStatus = exec.status();
  const execBody = await exec.json().catch(() => ({}));
  console.log("[A2] execute without license →", execStatus, JSON.stringify(execBody).slice(0, 300));
  expect(
    execStatus,
    "execute must refuse without a CryoSPARC user license",
  ).toBe(402);
  expect(String(execBody.error || execBody.message || "")).toMatch(
    /cryosparc_license_required|license/i,
  );

  // ── Flow A3: UI — cryosparc workflow panel shows Tool Credentials + blocks Confirm ──
  const sessionId = `e2e-cs-ui-${randomUUID()}`;
  const final = await chatFinal(
    req,
    "Set up cryosparc_standard_spa single-particle analysis for my cryo-EM movies. Do not run it.",
    sessionId,
  );
  const wfName =
    final?.workflow?.workflow_ga?.name ||
    final?.workflow?.name ||
    final?.metadata?.workflowSuggestion?.name ||
    "";
  console.log("[A3] chat workflow:", wfName || "(none)", "keys:", Object.keys(final || {}).slice(0, 12));
  expect(String(wfName).toLowerCase()).toMatch(/cryosparc|cryo/);

  // Persist a minimal session so ?session= loads chat + card, then open panel.
  await page.goto(`${BASE_URL}/?session=${encodeURIComponent(sessionId)}`, {
    waitUntil: "domcontentloaded",
  });
  // If the chat session is server-backed via a different id, fall back to home + paste.
  // Prefer navigating with a fresh composer send that opens the panel.
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  const composer = page.locator("textarea").first();
  await composer.waitFor({ state: "visible", timeout: 60_000 });
  await composer.fill(
    "Open cryosparc_standard_spa for my micrographs — prepare the workflow panel only, do not run.",
  );
  await page.keyboard.press("Enter");

  // Wait for workflow panel (right) — name or CRYO-EM badge.
  const panel = page.locator('[data-testid="panel-phases"], [data-testid="panel-settings"]').first();
  await expect(panel).toBeVisible({ timeout: 180_000 });
  await shot(page, "A3_cryosparc_panel_before_settings");

  // Switch to Workflow settings where LicenseGate lives.
  const settingsTab = page.getByRole("tab", { name: /workflow settings|settings/i }).or(
    page.locator('button[aria-selected]').filter({ hasText: /settings/i }),
  ).first();
  // tabBtn may not use role=tab — click by visible label.
  const settingsBtn = page.locator("button").filter({ hasText: /Workflow settings|Settings/i }).first();
  if (await settingsBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await settingsBtn.click();
  } else if (await settingsTab.isVisible({ timeout: 2_000 }).catch(() => false)) {
    await settingsTab.click();
  }

  const gate = page.getByTestId("license-gate");
  await expect(gate).toBeVisible({ timeout: 30_000 });
  await expect(gate).toHaveAttribute("data-blocked", "true");
  await expect(page.getByTestId("license-row-cryosparc")).toBeVisible();
  await expect(page.getByText(/Provide credentials/i).first()).toBeVisible();

  const confirm = page.getByTestId("button-run-workflow-panel");
  await expect(confirm).toBeVisible({ timeout: 15_000 });
  await expect(confirm).toBeDisabled();
  await expect(page.getByTestId("license-blocked-hint")).toBeVisible();
  await shot(page, "A3_license_gate_blocks_confirm");
  console.log("[A3] LicenseGate visible + Confirm disabled — pass");

  // ── Flow B: Run Manager from empty New Chat → owning session (not panel-only) ──
  const runsResp = await req.get(BASE_URL + "/api/workflows/runs?limit=50");
  expect(runsResp.ok()).toBe(true);
  const runs: Array<{ id: string; chatSessionId?: string; workflowName?: string }> =
    await runsResp.json();
  const withSession = runs.filter((r) => r.chatSessionId && r.id);
  console.log("[B] runs with chatSessionId:", withSession.length, "/", runs.length);

  // Start on a clean New Chat (empty cold-start) — matches the screenshot bug.
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  await page.getByTestId("cold-start-dashboard").waitFor({ state: "visible", timeout: 60_000 }).catch(() => {});
  await shot(page, "B0_empty_new_chat");

  const toggle = page.getByTestId("button-toggle-run-manager");
  await expect(toggle).toBeVisible({ timeout: 30_000 });
  await toggle.click();
  await expect(page.getByTestId("run-manager-panel")).toBeVisible({ timeout: 15_000 });
  await page.getByTestId("run-manager-scope-all-chats").click();
  await page.waitForTimeout(1500);

  // Prefer a run whose session is not the empty page's (no session param yet).
  let target = withSession[0];
  const items = page.locator("[data-testid^='run-manager-item-']");
  const itemCount = await items.count();
  console.log("[B] run-manager items visible:", itemCount);
  expect(itemCount, "Run Manager All chats must list at least one run").toBeGreaterThan(0);

  // If API gave us a target, click that id; else click the first visible item.
  if (target) {
    const specific = page.getByTestId(`run-manager-item-${target.id}`);
    if (await specific.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await specific.click();
    } else {
      target = undefined as any;
      await items.first().click();
    }
  } else {
    await items.first().click();
  }

  // After click: URL must carry ?session= (owning chat), not stay on bare /.
  await page.waitForFunction(
    () => new URL(window.location.href).searchParams.has("session"),
    undefined,
    { timeout: 30_000 },
  );
  const afterUrl = page.url();
  const sessionParam = new URL(afterUrl).searchParams.get("session");
  console.log("[B] after click URL:", afterUrl);
  expect(sessionParam, "must navigate to owning chat session").toBeTruthy();
  if (target?.chatSessionId) {
    expect(sessionParam).toBe(target.chatSessionId);
  }

  // Left panel must leave the empty cold-start home for the owning chat.
  await page.waitForTimeout(2000);
  const stillEmptyHome = await page
    .getByTestId("cold-start-dashboard")
    .isVisible({ timeout: 3_000 })
    .catch(() => false);
  expect(
    stillEmptyHome,
    "left panel must open the owning chat, not stay on empty New Chat home",
  ).toBe(false);

  // Right panel should show the workflow for that run.
  await expect(
    page.locator('[data-testid="panel-phases"], [data-testid="panel-settings"]').first(),
  ).toBeVisible({ timeout: 60_000 });
  await shot(page, "B1_run_manager_opened_owning_chat");
  console.log("[B] Run Manager opened owning chat + panel — pass");
});
