/**
 * Cryo-EM Auto-Loop Demo — headed browser, screenshot-based recording.
 *
 * Run with:
 *   cd frontend
 *   npx playwright test e2e/cryo-autoloop-demo.e2e.ts --headed --project=chromium
 *
 * After the test a helper script assembles screenshots into a slideshow video:
 *   ffmpeg -framerate 1/3 -pattern_type glob -i 'e2e/screenshots/cryo-autoloop-demo/*.png' \
 *     -vf "scale=1440:900:force_original_aspect_ratio=decrease,pad=1440:900:(ow-iw)/2:(oh-ih)/2" \
 *     -c:v libx264 -r 30 -pix_fmt yuv420p cryo-em-demo.mp4
 *
 * Auth state is saved to e2e/auth-state.json on first run.
 *
 * Demo flow
 * ─────────
 *  Phase A — Motion Correction & CTF    GOLD
 *  Phase B — Particle Picking           SILVER
 *  Phase C — 2D Classification          FAIL → remediation → SILVER
 *  Phase E — FSC 0.143 Resolution 3.2 Å GOLD
 */

import { test, Page, APIRequestContext, Route, BrowserContext } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL   = process.env.BIOMATE_URL || "http://localhost:5000";
const DEMO_EMAIL = process.env.DEMO_EMAIL  || "cryo_demo@biomate.test";
const DEMO_PASS  = process.env.DEMO_PASS   || "TestPass123!";
const AUTH_STATE = path.join(__dirname, "auth-state.json");
const SS_DIR     = path.join(__dirname, "screenshots", "cryo-autoloop-demo");

const DEMO_INV_ID = `cryo-spa-demo-${Date.now()}`;
const DEMO_RUN_ID = `run-cryo-demo-${Date.now()}`;
const MOCK_MOVIES = "s3://biomate-demo/cryo_em/micrographs/*.mrc";

// ── Playwright config ──────────────────────────────────────────────────────────
// Video recording is disabled to prevent OOM during long-running headed tests.
// A video is assembled from screenshots after the test completes via ffmpeg.
test.use({
  headless: false,
  video: { mode: "off" },
  viewport: { width: 1440, height: 900 },
  storageState: fs.existsSync(AUTH_STATE) ? AUTH_STATE : undefined,
});

// ── SSE payloads ───────────────────────────────────────────────────────────────

const PHASE_A_PASS = {
  phase: "phase_A", domain: "cryo_em", overall_level: "GOLD", passed: true,
  gates: [
    { gate: "motion_drift",    action: "pass",     level: "GOLD",   value: 8.4,   threshold: 30.0,  message: "Total drift 8.4 Å" },
    { gate: "per_frame_drift", action: "pass",     level: "GOLD",   value: 0.9,   threshold: 3.0,   message: "Per-frame 0.9 Å/frame" },
    { gate: "ctf_fit_quality", action: "pass",     level: "GOLD",   value: 0.142, threshold: 0.1,   message: "CTF FOM 0.142 — excellent" },
    { gate: "astigmatism",     action: "advisory", level: "SILVER", value: 412.0, threshold: 500.0, message: "Astigmatism 412 Å — advisory" },
  ],
};
const PHASE_A_COMPLETE = { phase: "phase_A", domain: "cryo_em", outcome: "pass", level: "GOLD" };

const PHASE_B_ADVISORY = {
  phase: "phase_B", domain: "cryo_em", overall_level: "SILVER", passed: true,
  gates: [
    { gate: "junk_fraction",          action: "advisory", level: "SILVER", value: 0.22,   threshold: 0.20,  message: "Junk fraction 0.22 — slight elevation" },
    { gate: "particle_yield",         action: "pass",     level: "GOLD",   value: 142800, threshold: 50000, message: "142,800 particles selected" },
    { gate: "orientation_anisotropy", action: "pass",     level: "GOLD",   value: 0.12,   threshold: 0.35,  message: "Anisotropy 0.12 — good" },
  ],
};
const PHASE_B_COMPLETE = { phase: "phase_B", domain: "cryo_em", outcome: "pass", level: "SILVER" };

const PHASE_C_FAIL = {
  phase: "phase_C", domain: "cryo_em", overall_level: "FAIL", passed: false,
  gates: [
    { gate: "class_quality", action: "halt", level: "FAIL", value: 0.31, threshold: 0.45,
      message: "Mean 2D class quality 0.31 < 0.45 — too many junk classes" },
  ],
};
const PHASE_C_UPDATE = {
  phase: "phase_C", domain: "cryo_em", attempt: 1, next_attempt: 2,
  remediations: [{
    phase: "phase_C", gate: "class_quality",
    param_changes: { num_2d_classes: 100, num_2d_iter: 25, particle_diameter_angstroms: 180 },
    rationale:
      "Mean 2D class quality 0.31 is below the 0.45 threshold. " +
      "Increasing num_2d_classes 50 → 100 allows CryoSPARC to resolve heterogeneous " +
      "views previously collapsed into junk classes.",
    citations: [
      {
        source_text:
          "Increasing 2D classes is the primary lever for improving classification quality.",
        paper_ref: "Punjani et al. (2017) Nature Methods 14:290-296",
        paper_doi: "10.1038/nmeth.4169",
        finding: "Doubling num_2d_classes (50→100) is the recommended first remediation when mean quality < 0.45.",
      },
      {
        source_text:
          "Particle diameter should enclose the particle with a 10–15% buffer.",
        paper_ref: "Scheres (2012) J Struct Biol 180:519-530",
        paper_doi: "10.1016/j.jsb.2012.09.006",
        finding: "Setting particle_diameter to 1.1× true size (~180 Å) minimises background contamination.",
      },
    ],
  }],
};
const PHASE_C_PASS = {
  phase: "phase_C", domain: "cryo_em", overall_level: "SILVER", passed: true,
  gates: [
    { gate: "class_quality", action: "pass", level: "SILVER", value: 0.52, threshold: 0.45,
      message: "Mean 2D class quality 0.52 ✓ — parameter adjustment successful" },
  ],
};
const PHASE_C_COMPLETE = { phase: "phase_C", domain: "cryo_em", outcome: "pass", level: "SILVER" };

const PHASE_E_PASS = {
  phase: "phase_E", domain: "cryo_em", overall_level: "GOLD", passed: true,
  gates: [
    { gate: "fsc_resolution", action: "pass", level: "GOLD", value: 3.2, threshold: 4.5,
      message: "FSC 0.143 resolution 3.2 Å — near-atomic map quality" },
  ],
};
const PHASE_E_COMPLETE = { phase: "phase_E", domain: "cryo_em", outcome: "pass", level: "GOLD" };

// ── Screenshot helper ──────────────────────────────────────────────────────────

function ss(page: Page, name: string) {
  fs.mkdirSync(SS_DIR, { recursive: true });
  return page.screenshot({ path: path.join(SS_DIR, `${name}.png`), fullPage: false })
    .then(() => console.log(`  [ss] ${name}.png`));
}

// ── SSE inject via server endpoint ────────────────────────────────────────────

async function injectSSE(request: APIRequestContext, invId: string, type: string, data: object) {
  const res = await request.post(`${BASE_URL}/internal/sse-inject`, {
    data: { invocation_id: invId, event_type: type, data },
  });
  return res.status();
}

// ── EventSource injection directly into browser ────────────────────────────────
// We patch EventSource in the browser to capture the connection opened by the
// NextflowWorkflowViewer so we can dispatch MessageEvents directly — bypassing
// the need for a real SSE server connection for the demo.

async function patchEventSource(page: Page, invId: string): Promise<void> {
  await page.evaluate((id) => {
    const OrigES = window.EventSource;
    // @ts-ignore
    window.__demoInvId = id;
    // @ts-ignore
    window.__demoES   = null;
    // @ts-ignore
    window.EventSource = class PatchedES extends OrigES {
      constructor(url: string, init?: EventSourceInit) {
        super(url, init);
        // @ts-ignore
        if (url.includes(window.__demoInvId)) {
          // @ts-ignore
          window.__demoES = this;
          console.log('[Demo] EventSource captured for demo invId:', url);
        }
      }
    };
    // @ts-ignore
    window.EventSource.prototype = OrigES.prototype;
    console.log('[Demo] EventSource patched');
  }, invId);
}

/**
 * Inject an SSE event directly into the captured EventSource.
 * Falls back to the server-side inject endpoint if the direct approach isn't available.
 */
async function injectEvent(
  page: Page, request: APIRequestContext,
  invId: string, type: string, data: object
): Promise<boolean> {
  // Try direct injection via captured EventSource
  const ok = await page.evaluate(({ type, data }) => {
    // @ts-ignore
    const es = window.__demoES;
    if (!es) return false;
    const event = new MessageEvent(type, { data: JSON.stringify(data) });
    es.dispatchEvent(event);
    return true;
  }, { type, data });

  if (ok) {
    console.log(`  [sse-direct] ${type} → dispatched`);
    return true;
  }

  // Fallback: server-side inject
  const status = await injectSSE(request, invId, type, data);
  console.log(`  [sse-server] ${type} → ${status}`);
  return status === 200;
}

/**
 * Wait for the AutoLoopPanel to become visible, injecting events each iteration.
 */
async function injectUntilVisible(
  page: Page, request: APIRequestContext,
  invId: string, events: Array<{ type: string; data: object }>,
  timeoutMs = 60_000
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  let n = 0;
  while (Date.now() < deadline) {
    n++;
    for (const ev of events) {
      await injectEvent(page, request, invId, ev.type, ev.data);
      await page.waitForTimeout(200);
    }
    const vis = await page.getByTestId("autoloop-panel").first()
      .isVisible({ timeout: 2_000 }).catch(() => false);
    if (vis) {
      console.log(`  panel visible after ${n} attempt(s)`);
      return true;
    }
    if (n % 3 === 0) console.log(`  [inject] ${n} attempts, panel not visible`);
    await page.waitForTimeout(1_000);
  }
  console.log(`  [inject] timed out after ${n} attempts`);
  return false;
}

// ── Workflow card helpers ──────────────────────────────────────────────────────

async function waitForWorkflowCard(page: Page, timeoutMs = 180_000): Promise<boolean> {
  const baseline = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    await page.evaluate(() => {
      const el = document.querySelector('[data-testid="chat-messages"], .chat-messages, main');
      if (el) el.scrollTop = el.scrollHeight;
      else window.scrollTo(0, document.body.scrollHeight);
    }).catch(() => {});

    const count = await page.locator('[data-testid^="workflow-artifact"]').count().catch(() => 0);
    if (count > baseline || count > 0) { await page.waitForTimeout(1500); return true; }

    for (const sel of [
      '[data-testid="button-run-workflow-panel"]',
      '[data-testid="button-confirm-and-run"]',
      '[data-testid="pipeline-confirm-run"]',
      'text=AWAITING REVIEW', 'text=Awaiting Review',
      '[data-testid="workflow-run-controls"]',
      '[data-testid="qc-settings-section"]',
    ]) {
      if (await page.locator(sel).first().isVisible({ timeout: 300 }).catch(() => false)) {
        await page.waitForTimeout(1000);
        return true;
      }
    }
    await page.waitForTimeout(1000);
  }
  return false;
}

// Known demo values for CryoSPARC SPA required params
const DEMO_PARAMS: Record<string, string> = {
  movies_path:           MOCK_MOVIES,
  dose_per_frame:        "1.0",
  molecular_weight_kda:  "300",
  cryosparc_license:     "DEMO-LICENSE-0000-0000",
  cryosparc_email:       "demo@biomate.ai",
  cryosparc_password:    "DemoPassword123",
  cryosparc_project_dir: "/home/ubuntu/cryosparc_projects",
  project_name:          "BioMate CryoEM Demo",
};

/**
 * Fill all known required params for CryoSPARC SPA demo.
 * Uses nativeInputValueSetter for reliable React controlled-input updates.
 */
async function fillDemoParams(page: Page): Promise<number> {
  let filled = 0;

  // First: open all collapsed accordion groups in the params section
  await page.evaluate(() => {
    // Find param group toggle buttons (Collapsible triggers)
    const btns = Array.from(document.querySelectorAll(
      '[data-testid^="params-"] button, [id^="params-"] button'
    )) as HTMLButtonElement[];
    btns.forEach(b => {
      // Only click if it's a collapse toggle (not a fill/confirm button)
      if (b.getAttribute('aria-expanded') === 'false') b.click();
    });
  }).catch(() => {});
  await page.waitForTimeout(500);

  // Fill each known param by id
  filled = await page.evaluate((params) => {
    let count = 0;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    const taSetter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;

    for (const [id, value] of Object.entries(params)) {
      const el = document.getElementById(id) as HTMLInputElement | HTMLTextAreaElement | null;
      if (!el) continue;
      if (el.tagName === 'TEXTAREA') {
        taSetter?.call(el, value);
        el.dispatchEvent(new Event('input',  { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      } else {
        setter?.call(el, value);
        el.dispatchEvent(new Event('input',  { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      }
      count++;
      console.log('[demo-fill] Filled', id, '=', value.slice(0, 40));
    }
    return count;
  }, DEMO_PARAMS);

  await page.waitForTimeout(800);
  return filled;
}

/**
 * Click the Confirm & Run button.
 * Priority order:
 *  1. Normal click if button is enabled
 *  2. React fiber __reactProps.onClick to bypass disabled check
 */
async function clickRunButton(page: Page): Promise<boolean> {
  const selectors = [
    '[data-testid="button-run-workflow-panel"]',
    '[data-testid="button-confirm-and-run"]',
    '[data-testid="pipeline-confirm-run"]',
    'button:has-text("Confirm & Run")',
    'button:has-text("Run Workflow")',
  ];

  for (const sel of selectors) {
    const btn = page.locator(sel).first();
    if (!await btn.isVisible({ timeout: 3_000 }).catch(() => false)) continue;

    console.log(`  [run] Found: ${sel}`);

    // Give React up to 5s to enable the button after param fills
    const deadline = Date.now() + 5_000;
    while (Date.now() < deadline) {
      if (await btn.isEnabled({ timeout: 300 }).catch(() => false)) {
        await btn.click();
        console.log(`  [run] Clicked (enabled)`);
        return true;
      }
      await page.waitForTimeout(500);
    }

    // Button still disabled — invoke React's onClick handler directly via fiber props.
    // React suppresses click events on disabled buttons via event delegation,
    // so we must bypass the event system entirely.
    const testId = sel.match(/data-testid="([^"]+)"/)?.[1];
    const invoked = await page.evaluate((tid) => {
      const el = tid
        ? document.querySelector(`[data-testid="${tid}"]`)
        : document.querySelector('button[data-testid]');
      if (!el) return false;
      // Find React's internal props key (__reactProps$... or __reactInternals...)
      const propsKey = Object.keys(el).find(k =>
        k.startsWith('__reactProps') || k.startsWith('__reactInternalInstance')
      );
      if (!propsKey) return false;
      const props = (el as any)[propsKey];
      if (props?.onClick) {
        props.onClick({ type: 'click', target: el, preventDefault: () => {}, stopPropagation: () => {} });
        return true;
      }
      return false;
    }, testId);

    console.log(`  [run] React fiber onClick invoked: ${invoked}`);
    return invoked;
  }

  console.log("  [run] No run button found");
  return false;
}

// ── Auth helper ────────────────────────────────────────────────────────────────

async function ensureLoggedIn(page: Page, context: BrowserContext): Promise<void> {
  await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  if (await page.locator("textarea").first().isVisible({ timeout: 5_000 }).catch(() => false)) {
    console.log("  Already on platform");
    return;
  }

  console.log("  Registering / logging in...");
  await page.goto(`${BASE_URL}/register`, { waitUntil: "domcontentloaded" });
  try {
    await page.waitForSelector("#email", { state: "visible", timeout: 8_000 });
    const name = page.locator("#name");
    if (await name.isVisible({ timeout: 500 }).catch(() => false)) await name.fill("CryoEM Demo");
    await page.fill("#email", DEMO_EMAIL);
    await page.fill("#password", DEMO_PASS);
    const cp = page.locator("#confirmPassword");
    if (await cp.isVisible({ timeout: 500 }).catch(() => false)) await cp.fill(DEMO_PASS);
    const terms = page.locator("#terms");
    if (await terms.isVisible({ timeout: 500 }).catch(() => false)) await terms.check();
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2_000);
  } catch { /* form absent */ }

  if (!await page.locator("textarea").first().isVisible({ timeout: 4_000 }).catch(() => false)) {
    await page.goto(`${BASE_URL}/login`, { waitUntil: "domcontentloaded" });
    try {
      await page.fill("#email", DEMO_EMAIL);
      await page.fill("#password", DEMO_PASS);
      await page.click('button[type="submit"]');
      await page.waitForTimeout(2_000);
    } catch { /* ignore */ }
    await page.goto(`${BASE_URL}/`, { waitUntil: "domcontentloaded" });
  }

  await context.storageState({ path: AUTH_STATE });
  console.log(`  Auth saved → ${AUTH_STATE}`);
}

// ── Demo test ──────────────────────────────────────────────────────────────────

test.describe("Cryo-EM Auto-Loop Demo", () => {
  test(
    "CryoSPARC SPA: Phase A GOLD → Phase C fail+remediate → Phase E GOLD",
    async ({ page, request, context }) => {
      test.setTimeout(900_000);

      // ── 1. Platform ────────────────────────────────────────────────────────
      console.log("\n=== 1. Platform ===");
      await ensureLoggedIn(page, context);

      // Dismiss onboarding modal
      for (const sel of [
        'button:has-text("Skip")',
        'button:has-text("Dismiss")',
        'button:has-text("Maybe later")',
      ]) {
        if (await page.locator(sel).first().isVisible({ timeout: 1_500 }).catch(() => false))
          await page.locator(sel).first().click({ force: true }).catch(() => {});
      }

      await page.waitForSelector("textarea", { state: "visible", timeout: 20_000 });
      await page.waitForTimeout(800);
      await ss(page, "01-platform");

      // ── 2. Patch EventSource to capture demo connection ────────────────────
      console.log("\n=== 2. Patch EventSource + mock execute API ===");
      await patchEventSource(page, DEMO_INV_ID);

      // Mock execute API → returns DEMO_INV_ID
      await page.route("**/api/workflows/execute", async (route: Route) => {
        console.log("  [mock] execute intercepted → DEMO_INV_ID");
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            id:                 DEMO_RUN_ID,
            runId:              DEMO_RUN_ID,
            galaxyInvocationId: DEMO_INV_ID,
            invocationId:       DEMO_INV_ID,
            status:             "running",
            execution: {
              status:             "running",
              galaxyInvocationId: DEMO_INV_ID,
              runId:              DEMO_RUN_ID,
            },
          }),
        });
      });

      // Mock status polls so the viewer stays "running"
      await page.route(`**/${DEMO_RUN_ID}**`, async (route: Route) => {
        if (route.request().url().includes("/events")) { await route.continue(); return; }
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            id: DEMO_RUN_ID, status: "running",
            execution: { status: "running", galaxyInvocationId: DEMO_INV_ID },
          }),
        });
      });

      // ── 3. Send CryoSPARC SPA query ────────────────────────────────────────
      console.log("\n=== 3. Send CryoSPARC SPA query ===");
      const ta = page.locator("textarea").first();
      await ta.fill(
        "Run CryoSPARC standard single-particle analysis on my cryo-EM dataset. " +
        "300 kV Titan Krios, pixel size 0.82 Å/px, 50 e⁻/Å² total dose. " +
        "The specimen is a 160 Å membrane protein complex."
      );
      await page.waitForTimeout(400);
      await ta.press("Enter");

      // ── 4. Wait for workflow card ──────────────────────────────────────────
      console.log("\n=== 4. Wait for AI + workflow card ===");
      const gotCard = await waitForWorkflowCard(page, 180_000);
      console.log(`  Workflow card: ${gotCard}`);
      await ss(page, "02-workflow-card");

      // ── 5. Fill all required demo params ──────────────────────────────────
      console.log("\n=== 5. Fill required demo params ===");
      const filled = await fillDemoParams(page);
      console.log(`  Filled ${filled} params`);
      await page.waitForTimeout(1_000);
      await ss(page, "02b-params-filled");

      // ── 6. Click Confirm & Run ─────────────────────────────────────────────
      console.log("\n=== 6. Confirm & Run ===");
      const clicked = await clickRunButton(page);
      console.log(`  Run button: ${clicked}`);

      // Wait for execute mock to fire and EventSource to open
      await page.waitForTimeout(5_000);

      // Verify EventSource was captured
      const esReady = await page.evaluate(() => {
        // @ts-ignore
        const ready = !!window.__demoES;
        // @ts-ignore
        console.log('[Demo] __demoES ready:', ready);
        return ready;
      });
      console.log(`  EventSource captured: ${esReady}`);
      await ss(page, "03-running");

      // If EventSource wasn't captured (execute didn't fire or invocationId mismatch),
      // try opening it directly from the browser as a fallback
      if (!esReady) {
        console.log("  [fallback] Opening demo EventSource from browser...");
        await page.evaluate((invId) => {
          // @ts-ignore
          window.__demoES = new (window.__origES || window.EventSource)(`/api/workflows/${invId}/events`);
          // @ts-ignore
          console.log('[Demo] Fallback EventSource opened for:', invId);
        }, DEMO_INV_ID);
        await page.waitForTimeout(2_000);
      }

      // ── 7. Phase A — Motion Correction & CTF (GOLD) ───────────────────────
      console.log("\n=== 7. Phase A — Motion Correction & CTF (GOLD) ===");
      const phaseAOk = await injectUntilVisible(page, request, DEMO_INV_ID, [
        { type: "autoloop_gate_results", data: PHASE_A_PASS },
      ]);
      await page.waitForTimeout(3_000);
      await ss(page, "04-phase-A-gold");
      if (phaseAOk) {
        await injectEvent(page, request, DEMO_INV_ID, "autoloop_phase_complete", PHASE_A_COMPLETE);
        await page.waitForTimeout(1_500);
        await ss(page, "05-phase-A-complete");
      }

      // ── 8. Phase B — Particle Picking (advisory) ──────────────────────────
      console.log("\n=== 8. Phase B — Particle Picking (advisory) ===");
      await injectEvent(page, request, DEMO_INV_ID, "autoloop_gate_results", PHASE_B_ADVISORY);
      await page.waitForTimeout(2_500);
      await ss(page, "06-phase-B-advisory");
      await injectEvent(page, request, DEMO_INV_ID, "autoloop_phase_complete", PHASE_B_COMPLETE);
      await page.waitForTimeout(800);

      // ── 9. Phase C — 2D Classification FAIL + remediation ─────────────────
      console.log("\n=== 9. Phase C — 2D Classification FAIL + remediation ===");
      const phaseCOk = await injectUntilVisible(page, request, DEMO_INV_ID, [
        { type: "autoloop_gate_results", data: PHASE_C_FAIL },
        { type: "autoloop_update",       data: PHASE_C_UPDATE },
      ]);
      await page.waitForTimeout(4_000);
      await ss(page, "07-phase-C-fail-remediation");

      if (phaseCOk) {
        const citBtn = page.locator("button").filter({ hasText: /citation/i }).first();
        if (await citBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
          await citBtn.click();
          await page.waitForTimeout(2_000);
          await ss(page, "08-citations-expanded");
        }
      }

      // ── 10. Phase C retry — SILVER ────────────────────────────────────────
      console.log("\n=== 10. Phase C retry — SILVER ===");
      await injectEvent(page, request, DEMO_INV_ID, "autoloop_gate_results",  PHASE_C_PASS);
      await page.waitForTimeout(800);
      await injectEvent(page, request, DEMO_INV_ID, "autoloop_phase_complete", PHASE_C_COMPLETE);
      await page.waitForTimeout(2_500);
      await ss(page, "09-phase-C-pass");

      // ── 11. Phase E — FSC 3.2 Å GOLD ─────────────────────────────────────
      console.log("\n=== 11. Phase E — FSC 3.2 Å GOLD ===");
      await injectEvent(page, request, DEMO_INV_ID, "autoloop_gate_results",  PHASE_E_PASS);
      await page.waitForTimeout(800);
      await injectEvent(page, request, DEMO_INV_ID, "autoloop_phase_complete", PHASE_E_COMPLETE);
      await page.waitForTimeout(3_500);
      await ss(page, "10-phase-E-gold");

      // ── 12. Dismiss panel ─────────────────────────────────────────────────
      const dismissBtn = page.getByTestId("autoloop-panel").locator("button").last();
      if (await dismissBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
        await dismissBtn.click();
        await page.waitForTimeout(1_200);
        await ss(page, "11-dismissed");
      }

      await page.waitForTimeout(2_000);
      console.log("\n=== DEMO COMPLETE ===");
      console.log(`  Screenshots → ${SS_DIR}`);
      console.log("  Assemble video:");
      console.log(`  ffmpeg -framerate 1/3 -pattern_type glob -i '${SS_DIR}/*.png' \\`);
      console.log(`    -vf "scale=1440:900:force_original_aspect_ratio=decrease,pad=1440:900:(ow-iw)/2:(oh-ih)/2" \\`);
      console.log("    -c:v libx264 -r 30 -pix_fmt yuv420p cryo-em-demo.mp4");
    }
  );
});
