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

/** Retry Galaxy-proxied calls — dig briefly 500s with ECONNREFUSED during worker recycle. */
async function withGalaxyRetry<T>(
  label: string,
  fn: () => Promise<T>,
  opts: { attempts?: number; ok?: (v: T) => boolean } = {},
): Promise<T> {
  const attempts = opts.attempts ?? 5;
  let last: unknown;
  for (let i = 1; i <= attempts; i++) {
    try {
      const v = await fn();
      if (opts.ok && !opts.ok(v)) {
        last = v;
        console.warn(`[retry] ${label} attempt ${i}/${attempts}: not ok yet`);
      } else {
        return v;
      }
    } catch (e) {
      last = e;
      console.warn(`[retry] ${label} attempt ${i}/${attempts}:`, (e as Error)?.message || e);
    }
    await new Promise((r) => setTimeout(r, 1500 * i));
  }
  throw last instanceof Error ? last : new Error(`${label} failed after ${attempts} attempts: ${JSON.stringify(last)}`);
}

// Independent flows — do not serialize: Run Manager must still prove even if the
// CryoSPARC UI open path flakes on clarification.

test("A: CryoSPARC license ask + hard-block (API + UI)", async ({ page }) => {
  test.setTimeout(12 * 60 * 1000);
  await loginAsFixture(page);
  const req = page.request;

  // ── A1: API license-requirements hard-blocks cryosparc without user key ──
  // Best-effort clear — Galaxy may 500 during recycle; license assert is what matters.
  const del = await req.delete(BASE_URL + "/api/users/credentials/cryosparc").catch(() => null);
  console.log("[A1] delete cryosparc credential →", del ? del.status() : "n/a");

  const licBody = await withGalaxyRetry("license-requirements", async () => {
    const lic = await req.get(
      BASE_URL +
        "/api/workflows/license-requirements?nextflow_path=" +
        encodeURIComponent("cryosparc_standard_spa/main.nf"),
    );
    if (!lic.ok()) throw new Error(`license-requirements HTTP ${lic.status()}: ${(await lic.text()).slice(0, 200)}`);
    return lic.json();
  });
  const cryo = (licBody.requirements || []).find(
    (r: any) => r.tool_id === "cryosparc",
  );
  expect(cryo, "cryosparc must appear in license-requirements").toBeTruthy();
  expect(cryo.source, "no user key → source none").toBe("none");
  expect(cryo.has_fallback, "cryosparc has no open fallback").toBeFalsy();
  console.log("[A1] cryosparc requirement:", JSON.stringify(cryo));

  // ── A2: execute without license → 402 (backend hard block) ──
  const { execStatus, execBody } = await withGalaxyRetry(
    "execute-without-license",
    async () => {
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
      const status = exec.status();
      const body = await exec.json().catch(() => ({}));
      // 5xx = Galaxy blip — retry. 402 is success for this assertion.
      if (status >= 500) throw new Error(`execute HTTP ${status}: ${JSON.stringify(body).slice(0, 200)}`);
      return { execStatus: status, execBody: body };
    },
    { ok: (v) => v.execStatus === 402 },
  );
  console.log("[A2] execute without license →", execStatus, JSON.stringify(execBody).slice(0, 300));
  expect(
    execStatus,
    "execute must refuse without a CryoSPARC user license",
  ).toBe(402);
  expect(String(execBody.error || execBody.message || "")).toMatch(
    /cryosparc_license_required|license/i,
  );

  // ── A3: UI — open panel, Tool Credentials blocks Confirm ──
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  const composer = page.locator("textarea").first();
  await composer.waitFor({ state: "visible", timeout: 60_000 });
  // Include a placeholder movies_path so clarification does not swallow the panel open.
  await composer.fill(
    "Open cryosparc_standard_spa for my micrographs. movies_path=s3://biomate-demo/empiar-10028/movies/. Prepare the workflow panel only — do not run.",
  );
  await page.keyboard.press("Enter");

  // Prefer explicit open: Confirm and configure / wf-chip / In panel.
  const openPanel = async () => {
    const candidates = [
      page.getByRole("button", { name: /Confirm and configure/i }),
      page.getByTestId("wf-chip-open"),
      page.locator(".wf-chip").first(),
      page.getByText(/In panel/i).first(),
    ];
    for (const c of candidates) {
      if (await c.isVisible({ timeout: 5_000 }).catch(() => false)) {
        await c.click();
        return true;
      }
    }
    return false;
  };

  // Wait for AI reply (clarification or card), then open panel.
  await page.waitForTimeout(8_000);
  const opened = await openPanel();
  if (!opened) {
    // Wait longer for the stream to finish, then retry.
    await page.waitForTimeout(60_000);
    await openPanel();
  }

  const panel = page
    .locator(
      '[data-testid="workflow-artifact-panel"], [data-testid="panel-phases"], [data-testid="panel-settings"]',
    )
    .first();
  await expect(panel).toBeVisible({ timeout: 120_000 });
  await shot(page, "A3_cryosparc_panel_before_settings");

  const settingsBtn = page
    .locator("button")
    .filter({ hasText: /Workflow settings|^Settings$/i })
    .first();
  if (await settingsBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await settingsBtn.click();
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
});

test("B: Run Manager opens owning chat (not panel-only on New Chat)", async ({ page }) => {
  test.setTimeout(5 * 60 * 1000);
  await loginAsFixture(page);
  const req = page.request;

  // Dig sometimes drops the first GET after a long prior test (socket hang up).
  let runs: Array<{ id: string; chatSessionId?: string; workflowName?: string }> = [];
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      const runsResp = await req.get(BASE_URL + "/api/workflows/runs?limit=50", {
        timeout: 60_000,
      });
      expect(runsResp.ok(), `runs list HTTP ${runsResp.status()}`).toBe(true);
      runs = await runsResp.json();
      break;
    } catch (e: any) {
      console.warn(`[B] runs list attempt ${attempt} failed:`, e?.message || e);
      if (attempt === 4) throw e;
      await page.waitForTimeout(2000 * attempt);
    }
  }
  // Prefer runs tied to a real client chat id (chat-*), not synthetic e2e-cs-lic-*
  // ids from API execute probes that never created a chat_sessions row.
  const withSession = runs.filter(
    (r) =>
      r.chatSessionId &&
      r.id &&
      !String(r.chatSessionId).startsWith("e2e-cs-lic-") &&
      !String(r.chatSessionId).startsWith("e2e-cs-ui-") &&
      !String(r.chatSessionId).startsWith("e2e-probe"),
  );
  console.log(
    "[B] real chatSessionId runs:",
    withSession.length,
    "/",
    runs.length,
    withSession.slice(0, 3).map((r) => r.chatSessionId),
  );
  expect(
    withSession.length,
    "need at least one run with a real chatSessionId (chat-*)",
  ).toBeGreaterThan(0);

  // Start on a clean New Chat (empty cold-start) — matches the screenshot bug.
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  await page
    .getByTestId("cold-start-dashboard")
    .waitFor({ state: "visible", timeout: 60_000 })
    .catch(() => {});
  await shot(page, "B0_empty_new_chat");

  const toggle = page.getByTestId("button-toggle-run-manager");
  await expect(toggle).toBeVisible({ timeout: 30_000 });
  await toggle.click();
  await expect(page.getByTestId("run-manager-panel")).toBeVisible({ timeout: 15_000 });
  await page.getByTestId("run-manager-scope-all-chats").click();
  await page.waitForTimeout(1500);

  // Run Manager only renders 6 rows/bucket — search by run id so the target
  // is actually in the DOM for a real click (not a synthetic location.assign).
  const target = withSession[0];
  const search = page.getByTestId("run-manager-search-input");
  await search.fill(target.id);
  await page.waitForTimeout(800);
  // A failed run can appear in both needs_attention and failed buckets — use .first().
  const specific = page.getByTestId(`run-manager-item-${target.id}`).first();
  await expect(
    specific,
    `run ${target.id} must appear after search`,
  ).toBeVisible({ timeout: 15_000 });
  await specific.click();

  await page.waitForFunction(
    () => {
      const u = new URL(window.location.href);
      return u.searchParams.has("session") && u.searchParams.has("focusRun");
    },
    undefined,
    { timeout: 30_000 },
  );
  const afterUrl = page.url();
  const sessionParam = new URL(afterUrl).searchParams.get("session");
  const focusRun = new URL(afterUrl).searchParams.get("focusRun");
  console.log("[B] after click URL:", afterUrl);
  expect(sessionParam, "must navigate to owning chat session").toBeTruthy();
  expect(focusRun, "must carry focusRun for the clicked run").toBeTruthy();
  if (target?.chatSessionId) {
    expect(sessionParam).toBe(target.chatSessionId);
  }
  if (target?.id) {
    expect(focusRun).toBe(target.id);
  }

  // Wait for SPA remount after location.assign — panel via focusRun, chat via session=.
  await expect(
    page
      .locator(
        '[data-testid="workflow-artifact-panel"], [data-testid="panel-phases"], [data-testid="panel-settings"]',
      )
      .first(),
  ).toBeVisible({ timeout: 60_000 });

  // Owning chat: cold-start home must leave, OR chat messages / non-"New Chat" title.
  await page.waitForTimeout(2500);
  const stillEmptyHome = await page
    .getByTestId("cold-start-dashboard")
    .isVisible({ timeout: 2_000 })
    .catch(() => false);
  const hasChatBubble = await page
    .locator('[data-testid^="chat-message"], .chat-message, [data-role="assistant"], [data-role="user"]')
    .first()
    .isVisible({ timeout: 2_000 })
    .catch(() => false);
  console.log("[B] stillEmptyHome=", stillEmptyHome, "hasChatBubble=", hasChatBubble);
  expect(
    !stillEmptyHome || hasChatBubble,
    "left panel must open the owning chat (leave empty New Chat home)",
  ).toBe(true);

  await shot(page, "B1_run_manager_opened_owning_chat");
  console.log("[B] Run Manager opened owning chat + panel — pass");
});
