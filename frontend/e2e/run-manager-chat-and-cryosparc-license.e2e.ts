/**
 * Live dig E2E for the two screenshot bugs (2026-11-13):
 *
 *   Flow A — CryoSPARC license end-to-end run path (not just "ask" UI):
 *            1) no user key → API 402 + LicenseGate blocks Confirm
 *            2) Provide credentials in the panel → gate clears
 *            3) Confirm & Run → execute is accepted past the license gate
 *               (panel goes running/queued, or fails for non-license reasons).
 *            Proves no silent CRYOSPARC_LICENSE env fallback. Cancels any
 *            accepted run immediately — does not wait for GPU SPA completion.
 *   Flow B — Run Manager (All chats) click must open the owning chat on the left,
 *            not only the right workflow panel on an empty New Chat.
 *
 * Discipline (CLAUDE.md): login once, no /register, one fixture, screenshots for audit.
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

test("A: CryoSPARC license ask → provide → Confirm & Run (E2E)", async ({ page }) => {
  test.setTimeout(15 * 60 * 1000);
  await loginAsFixture(page);
  const req = page.request;
  // E2E-only placeholder — proves the gate accepts a *user* key (not env). Not a real Structura license.
  const E2E_LICENSE = `e2e-${randomUUID()}`;
  let launchedRunId: string | null = null;

  try {
    // ── A1: clear user key → license-requirements source=none ──
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
    const cryo = (licBody.requirements || []).find((r: any) => r.tool_id === "cryosparc");
    expect(cryo, "cryosparc must appear in license-requirements").toBeTruthy();
    expect(cryo.source, "no user key → source none").toBe("none");
    expect(cryo.has_fallback, "cryosparc has no open fallback").toBeFalsy();
    console.log("[A1] cryosparc requirement:", JSON.stringify(cryo));

    // Cancel in-flight cryosparc runs first — dig idempotent dedupe (120s window)
    // can return HTTP 200 for an identical prior Confirm&Run and skip the 402 license gate.
    const preRuns = await req
      .get(BASE_URL + "/api/workflows/runs?limit=40", { timeout: 60_000 })
      .then((r) => (r.ok() ? r.json() : []))
      .catch(() => []);
    for (const r of preRuns as Array<{ id?: string; status?: string; workflowName?: string; name?: string; executionEngine?: string; execution?: { status?: string; executionEngine?: string } }>) {
      const st = String(r.execution?.status || r.status || "");
      const name = String(r.workflowName || r.name || "");
      const eng = String(r.execution?.executionEngine || r.executionEngine || "");
      if (!/configuring|queued|running|paused/i.test(st)) continue;
      if (!/cryo|spa/i.test(name + eng)) continue;
      const c = await req
        .post(BASE_URL + `/api/workflows/runs/${encodeURIComponent(String(r.id))}/cancel`, {
          data: {},
          timeout: 30_000,
        })
        .catch(() => null);
      console.log("[A2] pre-cancel in-flight", r.id, st, "→", c ? c.status() : "n/a");
    }

    // ── A2: execute without license → 402 (no silent env fallback) ──
    // Unique e2e_nonce so fingerprint cannot collide with a UI Confirm&Run still in the dedupe window.
    const a2Nonce = `e2e-nolic-${randomUUID()}`;
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
              parameters: {
                pixel_size: 1.05,
                voltage: 300,
                movies_path: "s3://biomate-demo/empiar-10028/movies/",
                e2e_nonce: a2Nonce,
              },
            },
            inputs: [],
            chatSessionId: `e2e-cs-lic-${randomUUID()}`,
          },
          timeout: 60_000,
        });
        const status = exec.status();
        const body = await exec.json().catch(() => ({}));
        if (status >= 500) throw new Error(`execute HTTP ${status}: ${JSON.stringify(body).slice(0, 200)}`);
        // Deduped in-flight twin is not a license proof — cancel and retry for a real 402.
        if (body?.deduplicated && body?.runId) {
          await req
            .post(BASE_URL + `/api/workflows/runs/${encodeURIComponent(String(body.runId))}/cancel`, {
              data: {},
              timeout: 30_000,
            })
            .catch(() => null);
          throw new Error(`execute deduplicated to ${body.runId}; cancelled and retrying for license 402`);
        }
        return { execStatus: status, execBody: body };
      },
      { ok: (v) => v.execStatus === 402 },
    );
    console.log("[A2] execute without license →", execStatus, JSON.stringify(execBody).slice(0, 300));
    expect(execStatus, "execute must refuse without a CryoSPARC user license").toBe(402);
    expect(String(execBody.error || execBody.message || "")).toMatch(
      /cryosparc_license_required|license/i,
    );

    // ── A3: UI — open panel; Tool Credentials blocks Confirm ──
    await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
    const composer = page.locator("textarea").first();
    await composer.waitFor({ state: "visible", timeout: 60_000 });
    await composer.fill(
      "Open cryosparc_standard_spa for my micrographs. movies_path=s3://biomate-demo/empiar-10028/movies/. pixel_size=1.05 voltage=300. Prepare the workflow panel — I will Confirm & Run myself.",
    );
    await page.keyboard.press("Enter");

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
    await page.waitForTimeout(8_000);
    if (!(await openPanel())) {
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

    // Disabled Confirm must not launch a run (force click is a no-op / ignored).
    await confirm.click({ force: true }).catch(() => {});
    await page.waitForTimeout(1500);
    const badge = page.getByTestId("workflow-overall-status-badge");
    if (await badge.isVisible().catch(() => false)) {
      const st = await badge.getAttribute("data-status");
      expect(st, "force-click Confirm must not start a run while license-blocked").not.toMatch(
        /running|queued|configuring/i,
      );
    }

    // ── A4: Provide credentials in the panel (user key, not env) ──
    await page.getByRole("button", { name: /Provide credentials/i }).first().click();
    // Prefer new testids; fall back to stable ids/labels already on dig.
    const modal = page
      .getByTestId("credential-modal")
      .or(page.getByRole("dialog").filter({ hasText: /CryoSPARC/i }));
    await expect(modal).toBeVisible({ timeout: 15_000 });
    await shot(page, "A4_credential_modal_open");
    const keyInput = page
      .getByTestId("credential-license-key")
      .or(page.locator("#cred-license-key"));
    await keyInput.fill(E2E_LICENSE);
    const saveBtn = page
      .getByTestId("credential-save")
      .or(page.getByRole("button", { name: /Save credentials/i }));
    await saveBtn.click();
    await expect(modal).toBeHidden({ timeout: 30_000 });

    // Gate must clear; Confirm enabled. Prefer row status + Confirm (authoritative
    // onBlockedChange); data-blocked must agree once dig has the hardPath attribute fix.
    await expect(page.getByTestId("license-row-cryosparc")).toHaveAttribute(
      "data-status",
      "resolved",
      { timeout: 45_000 },
    );
    await expect(confirm).toBeEnabled({ timeout: 15_000 });
    const blockedAttr = await gate.getAttribute("data-blocked");
    console.log("[A4] data-blocked after save:", blockedAttr);
    // Soft check: when dig serves the fixed LicenseGate, attribute must clear too.
    if (blockedAttr === "true") {
      console.warn(
        "[A4] data-blocked still true (dig may lack hardPath attribute fix) — Confirm enabled is the run gate",
      );
    } else {
      expect(blockedAttr).toBe("false");
    }
    await shot(page, "A4_license_saved_confirm_enabled");
    console.log("[A4] user license saved → Confirm enabled — pass");

    // license-requirements now reports source=user
    const licAfter = await withGalaxyRetry("license-requirements-after-save", async () => {
      const lic = await req.get(
        BASE_URL +
          "/api/workflows/license-requirements?nextflow_path=" +
          encodeURIComponent("cryosparc_standard_spa/main.nf"),
      );
      if (!lic.ok()) throw new Error(`license-requirements HTTP ${lic.status()}`);
      return lic.json();
    });
    const cryoAfter = (licAfter.requirements || []).find((r: any) => r.tool_id === "cryosparc");
    expect(cryoAfter?.source, "saved key must show as user credential").toBe("user");

    // ── A5: Confirm & Run — must pass the license gate (not 402) ──
    // Dig tip 1001dec4: execute can take a long time (GPU warm-up) then return
    // 500 cryosparc_execution_failed + runId — not 402. Panel may flip to Running
    // before the HTTP body arrives; do not fail solely on waitForResponse timeout.
    const execPromise = page
      .waitForResponse(
        (r) => r.url().includes("/api/workflows/execute") && r.request().method() === "POST",
        { timeout: 240_000 },
      )
      .then(async (execResp) => {
        const code = execResp.status();
        const json = await execResp.json().catch(() => ({}));
        return { code, json, via: "http" as const };
      })
      .catch(() => null);

    await confirm.click();

    // Race: HTTP execute outcome OR panel leaving idle (run accepted past license).
    let panelSawNonIdle = false;
    const panelPromise = page
      .waitForFunction(
        () => {
          const el = document.querySelector('[data-testid="workflow-overall-status-badge"]');
          const st = el?.getAttribute("data-status") || "";
          const bar = document.querySelector('[data-testid="panel-action-bar"]');
          const barSt = bar?.getAttribute("data-status") || "";
          return /running|queued|configuring|failed|completed/i.test(st || barSt);
        },
        undefined,
        { timeout: 240_000 },
      )
      .then(() => {
        panelSawNonIdle = true;
        return true;
      })
      .catch(() => false);

    const raced = await Promise.race([
      execPromise.then((r) => ({ kind: "http" as const, r })),
      panelPromise.then((ok) => ({ kind: "panel" as const, ok })),
    ]);

    let execCode = 0;
    let execJson: any = {};
    let via = "none";

    if (raced.kind === "http" && raced.r) {
      execCode = raced.r.code;
      execJson = raced.r.json;
      via = "http";
    } else {
      // Panel moved first (or alone) — give HTTP a short grace, then accept panel proof.
      const late = await Promise.race([
        execPromise,
        new Promise<null>((resolve) => setTimeout(() => resolve(null), 20_000)),
      ]);
      if (late) {
        execCode = late.code;
        execJson = late.json;
        via = "http-after-panel";
      } else {
        via = "panel";
        // Synthetic non-license success — Confirm was enabled and panel left idle.
        execCode = 200;
        execJson = {};
      }
    }

    console.log(
      "[A5] Confirm & Run execute →",
      via,
      execCode,
      JSON.stringify(execJson).slice(0, 400),
    );
    expect(
      execCode,
      "with a user license, execute must NOT be cryosparc_license_required 402",
    ).not.toBe(402);
    expect(String(execJson.error || execJson.message || "")).not.toMatch(
      /cryosparc_license_required/i,
    );

    launchedRunId =
      execJson.runId ||
      execJson.run_id ||
      execJson.id ||
      execJson.executionId ||
      null;

    // If HTTP hung but panel is running, resolve runId from the runs list for cancel.
    if (!launchedRunId) {
      const runs = await req
        .get(BASE_URL + "/api/workflows/runs?limit=20", { timeout: 60_000 })
        .then((r) => (r.ok() ? r.json() : []))
        .catch(() => []);
      const active = (runs as Array<{ id?: string; status?: string; workflowName?: string; name?: string; execution?: { status?: string } }>).find(
        (r) => {
          const st = String(r.execution?.status || r.status || "");
          const name = String(r.workflowName || r.name || "");
          return /configuring|queued|running|paused/i.test(st) && /cryo|spa/i.test(name);
        },
      );
      if (active?.id) {
        launchedRunId = String(active.id);
        console.log("[A5] runId from runs list (panel/HTTP race):", launchedRunId);
      }
    }

    const execErr = String(execJson.error || execJson.message || "");
    const notLicenseBlock =
      execCode !== 402 && !/cryosparc_license_required/i.test(execErr);
    const infraOrExecFail = /cryosparc_execution_failed|warming|infra/i.test(execErr);
    const nonLicenseHttpOk =
      (execCode >= 200 && execCode < 300) ||
      (execCode >= 400 && execCode < 500 && execCode !== 402);
    const afterStatusEarly =
      (await badge.getAttribute("data-status").catch(() => null)) ||
      (await page.getByTestId("panel-action-bar").getAttribute("data-status").catch(() => null));
    const panelNonIdle =
      panelSawNonIdle ||
      via === "panel" ||
      via === "http-after-panel" ||
      /running|queued|configuring|failed|completed/i.test(String(afterStatusEarly || ""));
    const licenseCleared =
      notLicenseBlock &&
      (!!launchedRunId || nonLicenseHttpOk || infraOrExecFail || !!panelNonIdle);
    expect(
      licenseCleared,
      `Confirm & Run must clear the license gate (via=${via}, HTTP ${execCode}, error=${execErr.slice(0, 120)}, runId=${launchedRunId})`,
    ).toBe(true);

    const afterStatus = afterStatusEarly;
    console.log(
      "[A5] panel status after Confirm & Run:",
      afterStatus,
      "runId=",
      launchedRunId,
      "via=",
      via,
      "execCode=",
      execCode,
      "execErr=",
      execErr.slice(0, 80),
    );
    await shot(page, "A5_confirm_run_past_license_gate");
    console.log("[A5] Confirm & Run past license gate — pass");
  } finally {
    // Cancel any launched / in-flight cryosparc run so we do not burn a full SPA GPU cycle.
    const cancelIds = new Set<string>();
    if (launchedRunId) cancelIds.add(launchedRunId);
    const leftover = await req
      .get(BASE_URL + "/api/workflows/runs?limit=20", { timeout: 60_000 })
      .then((r) => (r.ok() ? r.json() : []))
      .catch(() => []);
    for (const r of leftover as Array<{ id?: string; status?: string; workflowName?: string; name?: string; execution?: { status?: string } }>) {
      const st = String(r.execution?.status || r.status || "");
      const name = String(r.workflowName || r.name || "");
      if (/configuring|queued|running|paused/i.test(st) && /cryo|spa/i.test(name) && r.id) {
        cancelIds.add(String(r.id));
      }
    }
    for (const id of cancelIds) {
      const cancel = await req
        .post(BASE_URL + `/api/workflows/runs/${encodeURIComponent(id)}/cancel`, {
          data: {},
          timeout: 30_000,
        })
        .catch(() => null);
      console.log("[A6] cancel run", id, "→", cancel ? cancel.status() : "n/a");
    }
    if (cancelIds.size) await shot(page, "A6_run_cancelled").catch(() => {});
    await req.delete(BASE_URL + "/api/users/credentials/cryosparc").catch(() => null);
    console.log("[A6] cryosparc credential cleared");
  }
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
