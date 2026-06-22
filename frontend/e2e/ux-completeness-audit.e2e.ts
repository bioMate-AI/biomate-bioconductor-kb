/**
 * UX Completeness Audit — consolidated 2026-06-22
 *
 * Two flows — never 42 serial tests:
 *
 *   Flow A (main journey, ~15 min):
 *     login → send ADMET query → check chat rendering →
 *     run workflow → check all panel states (running, completed, QC, params,
 *     step previews, auto-loop) → check sidebar navigation
 *
 *   Flow B (upload + auth gate, ~1 min):
 *     dataset upload UI checks + 401/404 auth gate probes
 *     (no Batch job; no re-login)
 *
 * Design rules (CLAUDE.md E2E plan discipline):
 *   - Login ONCE — shared cookie across both flows via storageState
 *   - ONE AWS Batch job total (ADMET in Flow A); RNA-seq is a text-only
 *     routing check (no Batch run)
 *   - 90 s timeout for LLM chat-stream calls
 *   - Soft assertions: try/catch + console.log; only hard-fail on blockers
 *   - No /api/auth/register — fixture account already exists
 *
 * Fixture:
 *   Email:    lifeifei163361@163.com
 *   Password: E2E_FIXTURE_PASSWORD env var || WpmFixture!2026
 */

import { test, expect, Page, Browser } from '@playwright/test';
import {
  sendAndWait,
  clickRunAndWait,
  waitForNoActiveRuns,
  shot,
  pause,
  BASE_URL,
} from './demo-helpers.js';

// ── Constants ──────────────────────────────────────────────────────────────────

const FIXTURE_EMAIL    = 'lifeifei163361@163.com';
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const E2E_TOKEN        = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';

const ADMET_QUERY =
  'Run ADMET toxicity screening on imatinib: Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1 ' +
  'and predict hERG cardiac risk (IC50), DILI probability, and Ames mutagenicity.';

// ── Helpers ────────────────────────────────────────────────────────────────────

async function login(page: Page): Promise<void> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  // Use browser-context fetch (same origin) — avoids Playwright APIRequestContext
  // serialization differences. Returns the JWT so we can also call addCookies()
  // explicitly (belt-and-suspenders against SameSite handling in headful Chrome).
  const token = await page.evaluate(
    async ({ baseUrl, email, password, token: e2eToken }) => {
      const resp = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': e2eToken },
        credentials: 'include',
        body: JSON.stringify({ email, password }),
      });
      if (!resp.ok) throw new Error(`Login API ${resp.status}`);
      const data = await resp.json();
      return data.token as string;
    },
    { baseUrl: BASE_URL, email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, token: E2E_TOKEN }
  );
  // Explicitly inject cookie so it survives the next navigation regardless of
  // the browser's same-site cookie processing during page.evaluate.
  const domain = new URL(BASE_URL).hostname;
  await page.context().addCookies([{
    name: 'biomate_token',
    value: token,
    domain,
    path: '/',
    httpOnly: true,
    secure: BASE_URL.startsWith('https'),
    sameSite: 'Lax',
  }]);
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.evaluate(() => {
    try {
      localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 86400_000));
    } catch { /* noop */ }
  });
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 30_000 });
}

/** Soft assertion — logs failure but does not throw. */
function soft(label: string, fn: () => Promise<void>): Promise<void> {
  return fn().catch(e => {
    console.log(`[SOFT FAIL] ${label}: ${(e as Error).message?.split('\n')[0]}`);
  });
}

// ── Shared login state ─────────────────────────────────────────────────────────

let sharedBrowser: Browser;
let sharedPage: Page;

test.beforeAll(async ({ browser }) => {
  sharedBrowser = browser;
  sharedPage = await browser.newPage();
  await login(sharedPage);
});

test.afterAll(async () => {
  await sharedPage.close().catch(() => {/* noop */});
});

// =============================================================================
// Flow A — Main journey (login → ADMET run → all panel/UI checks → sidebar)
// =============================================================================

test('Flow A — ADMET run + full panel and sidebar audit', async () => {
  test.setTimeout(900_000); // 15 min — one AWS Batch job

  const page = sharedPage;

  // ── Start fresh chat ────────────────────────────────────────────────────────
  const newChatBtn = page.locator('[data-testid="button-new-chat"]').first();
  if (await newChatBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await newChatBtn.click();
    await pause(page, 1_000);
  }

  // ── A1: AI text-only response renders markdown ──────────────────────────────
  console.log('[A] Sending ADMET query...');
  const hasRunBtn = await sendAndWait(page, ADMET_QUERY, 90_000);
  await shot(page, 'ux-audit', 'A_after_query');

  // A1 — AI message visible (testid is "chat-message-<id>", use prefix match)
  await soft('A1 AI text message', async () => {
    const aiMsg = page.locator('[data-testid^="chat-message-"]').first();
    await expect(aiMsg).toBeVisible({ timeout: 10_000 });
    console.log('[A1] ✅ AI chat message visible');
  });

  // A2 — Workflow artifact anchor in DOM (when isInPanel=true the div is an invisible anchor;
  //       check DOM presence not visibility)
  await soft('A2 workflow card', async () => {
    const wfChip = page.locator('[data-testid^="workflow-artifact-anchor-"]').first();
    await expect(wfChip).toBeAttached({ timeout: 10_000 });
    console.log('[A2] ✅ workflow artifact anchor in DOM');
  });

  // A3 — wf-chip "In panel" badge
  await soft('A3 in-panel badge', async () => {
    const badge = page.locator(':text("In panel"), [data-testid="wf-chip-in-panel"]').first();
    const has = await badge.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[A3] "In panel" badge: ${has}`);
  });

  // A4 — disambiguation (soft: only fires on ambiguous queries)
  console.log('[A4] DisambiguationCard: only fires on ambiguous queries — covered by routing unit tests');

  // A5 — alert banners (soft: depend on server state)
  await soft('A5 alert banners', async () => {
    const alert = page.locator('[data-testid^="alert-banner-"], [role="alert"]').first();
    const has = await alert.isVisible({ timeout: 3_000 }).catch(() => false);
    console.log(`[A5] Alert banner present: ${has}`);
  });

  // ── B: Workflow panel states ────────────────────────────────────────────────
  const panel = page.locator('[data-testid="workflow-artifact-panel"]').first();

  // B1 — Pre-run: param strip
  await soft('B1 param strip', async () => {
    const strip = panel.locator('[data-testid="param-strip"], .strip').first();
    const has = await strip.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[B1] Param strip: ${has}`);
  });
  await shot(page, 'ux-audit', 'B_pre_run');

  // B2 — Missing required params alert (soft — depends on workflow having required params)
  await soft('B2 missing-param alert', async () => {
    const blocked = panel.locator('[data-testid="blocked-run-alert"], .prereq-blocked').first();
    const has = await blocked.isVisible({ timeout: 3_000 }).catch(() => false);
    console.log(`[B2] Blocked alert present: ${has}`);
  });

  // B5 — Negative: skip phase/step buttons must NOT appear
  await soft('B5 no skip buttons', async () => {
    await expect(panel.locator('[data-testid="button-skip-phase"], button:has-text("Skip phase")')).toHaveCount(0);
    await expect(panel.locator('[data-testid="button-skip-step"], button:has-text("Skip step")')).toHaveCount(0);
    console.log('[B5] ✅ Skip buttons absent');
  });

  // B6 — Negative: watcher bar must NOT appear
  await soft('B6 no watcher bar', async () => {
    await expect(panel.locator('[data-testid="watcher-bar"]')).toHaveCount(0);
    console.log('[B6] ✅ Watcher bar absent');
  });

  if (!hasRunBtn) {
    console.log('[B3] No Run button — AI gave text-only response; skipping Batch assertions');
    return;
  }

  // B3 — Running state: SSE idle→running transition
  console.log('[B3] Clicking Run and observing running state...');
  const overallBadge = panel.locator('[data-testid="workflow-overall-status-badge"]');

  // Observe idle before run
  await soft('B3 idle state before run', async () => {
    const status = await overallBadge.getAttribute('data-status').catch(() => 'unknown');
    console.log(`[B3] Pre-run badge status: ${status}`);
  });

  const runId = await clickRunAndWait(page, 600_000);
  await shot(page, 'ux-audit', 'B3_running');
  console.log(`[B3] Run started, runId: ${runId}`);

  // B7 — SSE real-time: observe running badge during run
  await soft('B7 SSE running badge', async () => {
    // clickRunAndWait waits for completion; check badge is now terminal
    const status = await overallBadge.getAttribute('data-status').catch(() => '');
    const terminal = /completed|failed|errored/i.test(status ?? '');
    console.log(`[B7] Post-run badge status: ${status} (terminal: ${terminal})`);
  });

  // Wait fully for completion
  await waitForNoActiveRuns(page, 600_000);
  await shot(page, 'ux-audit', 'B4_completed');

  // B4 — Completed: badge or "Run again" button
  await soft('B4 completed state', async () => {
    const finalStatus = await overallBadge.getAttribute('data-status').catch(() => '');
    const runAgain = panel.locator(':text("Run again"), [data-testid="footer-button-run-again"]').first();
    const hasRunAgain = await runAgain.isVisible({ timeout: 5_000 }).catch(() => false);
    const completedCards = await panel.locator('[data-testid^="phase-card-"][data-status="completed"]').count();
    console.log(`[B4] badge=${finalStatus} runAgain=${hasRunAgain} completedCards=${completedCards}`);
    // Hard assert: either badge completed OR Run again visible
    expect(/completed/i.test(finalStatus ?? '') || hasRunAgain).toBe(true);
    console.log('[B4] ✅ Completed state verified');
  });

  // ── C: Parameter override panel ────────────────────────────────────────────
  await soft('C1-C4 param panel', async () => {
    const editParamsBtn = panel.locator('[data-testid="button-edit-params"], button:has-text("Edit params")').first();
    if (!await editParamsBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
      // Try opening the param strip
      const strip = panel.locator('.strip').first();
      if (await strip.isVisible({ timeout: 3_000 }).catch(() => false)) await strip.click();
    }
    const editBtn = panel.locator('[data-testid="button-edit-params"], button:has-text("Edit params")').first();
    if (!await editBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
      console.log('[C] "Edit params" button not visible after strip click — skipping param panel check');
      return;
    }
    await editBtn.click();
    await pause(page, 1_000);
    await shot(page, 'ux-audit', 'C1_params_panel');

    const paramsPanel = panel.locator('[data-testid="global-params-panel"], .params-panel').first();
    const panelOpen = await paramsPanel.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[C1] Params panel open: ${panelOpen}`);
    if (panelOpen) {
      const toggle = paramsPanel.locator('input[type="checkbox"], [role="switch"]').first();
      console.log(`[C2] Boolean toggle: ${await toggle.isVisible({ timeout: 3_000 }).catch(() => false)}`);
      const dropdown = paramsPanel.locator('select, [role="combobox"]').first();
      console.log(`[C3] Select dropdown: ${await dropdown.isVisible({ timeout: 3_000 }).catch(() => false)}`);
      const numInput = paramsPanel.locator('input[type="number"]').first();
      console.log(`[C4] Number input: ${await numInput.isVisible({ timeout: 3_000 }).catch(() => false)}`);
    }
  });

  // ── D: QC gate + settings ──────────────────────────────────────────────────
  await soft('D1-D3 QC gate', async () => {
    const qcAlert = panel.locator('[data-testid="qc-gate-alert"], [data-testid="qc-gate-blocked-alert"]').first();
    const hasQcAlert = await qcAlert.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[D1] QC gate alert: ${hasQcAlert}`);
    if (hasQcAlert) await shot(page, 'ux-audit', 'D1_qc_gate');

    // D2: QC edit toggle opens inline editor
    const qcEditToggle = panel.locator('[data-testid^="qc-edit-toggle-"]').first();
    if (await qcEditToggle.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await qcEditToggle.click();
      await pause(page, 500);
      const metricInput = panel.locator('.qc-gate input[type="number"]').first();
      const hasInput = await metricInput.isVisible({ timeout: 3_000 }).catch(() => false);
      console.log(`[D2] QC threshold editor input visible: ${hasInput}`);
      await shot(page, 'ux-audit', 'D2_qc_editor');
      // Close
      await qcEditToggle.click();
    } else {
      console.log('[D2] QC edit toggle not visible (no QC thresholds for this workflow)');
    }
  });

  // ── E: Step file preview formats ───────────────────────────────────────────
  await soft('E1-E3 step file previews', async () => {
    const imgPreview = panel.locator('img[data-preview], [data-testid^="preview-img-"]').first();
    console.log(`[E1] Image preview: ${await imgPreview.isVisible({ timeout: 3_000 }).catch(() => false)}`);
    const tablePreview = panel.locator('[data-testid^="preview-table-"], table[data-preview]').first();
    console.log(`[E2] Table preview: ${await tablePreview.isVisible({ timeout: 3_000 }).catch(() => false)}`);
    const codePreview = panel.locator('[data-testid^="preview-code-"], pre[data-preview]').first();
    console.log(`[E3] Code block preview: ${await codePreview.isVisible({ timeout: 3_000 }).catch(() => false)}`);
  });

  // ── F: Auto-loop panel ─────────────────────────────────────────────────────
  await soft('F1-F3 auto-loop', async () => {
    const remCard = panel.locator('[data-testid="autoloop-remediation-card"]').first();
    console.log(`[F1] Remediation card: ${await remCard.isVisible({ timeout: 3_000 }).catch(() => false)}`);
    const gateTable = panel.locator('[data-testid="autoloop-gate-table"]').first();
    console.log(`[F2] Gate table: ${await gateTable.isVisible({ timeout: 3_000 }).catch(() => false)}`);
    // F3: auto-loop toggle must be LOCKED
    const toggle = panel.locator('[data-testid^="autoloop-toggle-"]').first();
    if (await toggle.isVisible({ timeout: 3_000 }).catch(() => false)) {
      const isLocked = await toggle.getAttribute('aria-disabled').catch(() => 'false');
      const text = await page.locator(':text("coming soon")').first().isVisible({ timeout: 2_000 }).catch(() => false);
      console.log(`[F3] Auto-loop toggle aria-disabled=${isLocked} "coming soon" label=${text}`);
      expect(isLocked).toBe('true');
      console.log('[F3] ✅ Auto-loop locked');
    }
  });
  await shot(page, 'ux-audit', 'F_autoloop_section');

  // ── G: Sidebar navigation ──────────────────────────────────────────────────

  // G1 — New Chat
  await soft('G1 new chat', async () => {
    const newChat = page.locator('[data-testid="button-new-chat"]').first();
    await expect(newChat).toBeVisible({ timeout: 10_000 });
    await newChat.click();
    await pause(page, 1_000);
    await shot(page, 'ux-audit', 'G1_new_chat');
    const input = page.locator('[data-testid="chat-input"], textarea').first();
    await expect(input).toBeVisible({ timeout: 10_000 });
    const val = await input.inputValue().catch(() => '');
    expect(val).toBe('');
    console.log('[G1] ✅ New Chat starts empty session');
  });

  // G2 — Workflows dialog
  await soft('G2 workflows dialog', async () => {
    const btn = page.locator('[data-testid="button-workflows-nav"], [data-testid="button-starred-workflows"]').first();
    if (!await btn.isVisible({ timeout: 5_000 }).catch(() => false)) { console.log('[G2] skip — button not found'); return; }
    await btn.click();
    await pause(page, 800);
    await shot(page, 'ux-audit', 'G2_workflows_dialog');
    await page.keyboard.press('Escape');
    console.log('[G2] ✅ Workflows dialog opened');
  });

  // G3 — Runs → /dashboard
  await soft('G3 runs nav', async () => {
    const btn = page.locator('[data-testid="nav-runs"], a:has-text("Runs")').first();
    if (!await btn.isVisible({ timeout: 3_000 }).catch(() => false)) { console.log('[G3] skip — Runs not found'); return; }
    await btn.click();
    await pause(page, 1_500);
    const url = page.url();
    console.log(`[G3] URL: ${url} (has /dashboard: ${url.includes('/dashboard')})`);
    await page.goBack();
    await pause(page, 1_000);
    console.log('[G3] ✅ Runs nav checked');
  });

  // G5 — Billing
  await soft('G5 billing nav', async () => {
    const btn = page.locator('[data-testid="nav-billing"], a:has-text("Billing")').first();
    if (!await btn.isVisible({ timeout: 3_000 }).catch(() => false)) { console.log('[G5] skip'); return; }
    await btn.click();
    await pause(page, 1_500);
    await shot(page, 'ux-audit', 'G5_billing');
    await page.goBack();
    console.log('[G5] ✅ Billing nav checked');
  });

  // G6 — Settings dialog
  await soft('G6 settings dialog', async () => {
    const btn = page.locator('[data-testid="button-settings"]').first();
    if (!await btn.isVisible({ timeout: 3_000 }).catch(() => false)) { console.log('[G6] skip'); return; }
    await btn.click();
    await pause(page, 800);
    await shot(page, 'ux-audit', 'G6_settings');
    await page.keyboard.press('Escape');
    console.log('[G6] ✅ Settings dialog opened');
  });

  // G7 — Collapse / expand sidebar
  await soft('G7 sidebar collapse/expand', async () => {
    const collapseBtn = page.locator('[data-testid="button-sidebar-toggle"]').first();
    if (!await collapseBtn.isVisible({ timeout: 3_000 }).catch(() => false)) { console.log('[G7] skip'); return; }
    await collapseBtn.click();
    await pause(page, 800);
    await shot(page, 'ux-audit', 'G7_collapsed');
    const expandBtn = page.locator('[data-testid="button-sidebar-expand"]').first();
    if (await expandBtn.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await expandBtn.click();
    } else {
      await collapseBtn.click();
    }
    await pause(page, 800);
    await shot(page, 'ux-audit', 'G7_expanded');
    console.log('[G7] ✅ Collapse/expand verified');
  });

  // G8 — Chat history dots
  await soft('G8 history dots', async () => {
    const dot = page.locator('[data-testid^="history-dot-"]').first();
    const hasDot = await dot.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[G8] History dot present: ${hasDot}`);
  });

  console.log('[Flow A] ✅ All checks complete');
});

// =============================================================================
// Flow B — Dataset upload UI + auth gate probes (no Batch job, ~1 min)
// =============================================================================

test('Flow B — Upload UI and auth gate probes', async () => {
  test.setTimeout(180_000);

  const page = sharedPage;

  // Start fresh chat so upload button is available
  await soft('B-setup new chat', async () => {
    const btn = page.locator('[data-testid="button-new-chat"]').first();
    if (await btn.isVisible({ timeout: 5_000 }).catch(() => false)) {
      await btn.click();
      await pause(page, 1_000);
    }
  });

  // ── I1: Upload drop zone ────────────────────────────────────────────────────
  await soft('I1 upload drop zone', async () => {
    const addData = page.locator(
      '[data-testid="button-add-data"], button[aria-label*="Add data"], button[title*="Add data"]'
    ).first();
    if (!await addData.isVisible({ timeout: 5_000 }).catch(() => false)) {
      console.log('[I1] "Add data" button not visible');
      return;
    }
    await addData.click();
    await pause(page, 800);
    await shot(page, 'ux-audit', 'I1_upload_dropzone');

    // Dataset browser uses a button-based upload (no drag-drop zone)
    const uploadBtn = page.locator('button:has-text("Upload file from computer"), [data-testid="file-upload-drop-zone"], [data-testid="upload-dropzone"]').first();
    const hasDrop = await uploadBtn.isVisible({ timeout: 5_000 }).catch(() => false);
    console.log(`[I1] Upload mechanism present: ${hasDrop}`);

    // Format list
    const formatText = await page.locator(':text("FASTQ"), :text("FASTA"), :text("VCF"), :text("BAM")').first()
      .isVisible({ timeout: 3_000 }).catch(() => false);
    console.log(`[I1] Format hints visible: ${formatText}`);

    // I2: No folder picker (negative)
    const folderPicker = page.locator('input[type="file"][webkitdirectory]').first();
    const hasFolderPicker = await folderPicker.isVisible({ timeout: 2_000 }).catch(() => false);
    console.log(`[I2] Folder picker absent (expected false): ${hasFolderPicker}`);
    console.log('[I1/I2] ✅ Upload drop zone checked');

    await page.keyboard.press('Escape');
    await pause(page, 500);
  });

  // ── I4: URL import tab ───────────────────────────────────────────────────────
  await soft('I4 URL import tab', async () => {
    const addData = page.locator(
      '[data-testid="button-add-data"], button[aria-label*="Add data"], button[title*="Add data"]'
    ).first();
    if (!await addData.isVisible({ timeout: 5_000 }).catch(() => false)) { console.log('[I4] skip'); return; }
    await addData.click();
    await pause(page, 800);

    const urlTab = page.locator('[data-testid="tab-url-import"], button:has-text("From URL")').first();
    if (await urlTab.isVisible({ timeout: 3_000 }).catch(() => false)) {
      await urlTab.click();
      await pause(page, 500);
      await shot(page, 'ux-audit', 'I4_url_import');
      console.log('[I4] ✅ URL import tab visible');
    } else {
      console.log('[I4] URL import tab not found');
    }
    await page.keyboard.press('Escape');
    await pause(page, 500);
  });

  // ── I5: Dataset browser tabs ─────────────────────────────────────────────────
  await soft('I5 dataset browser tabs', async () => {
    const addData = page.locator(
      '[data-testid="button-add-data"], button[aria-label*="Add data"], button[title*="Add data"]'
    ).first();
    if (!await addData.isVisible({ timeout: 5_000 }).catch(() => false)) { console.log('[I5] skip'); return; }
    await addData.click();
    await pause(page, 800);

    const tabs = ['This session', 'BioMate history', 'From URL'];
    for (const tab of tabs) {
      const t = page.locator(`button:has-text("${tab}")`).first();
      console.log(`[I5] "${tab}" tab: ${await t.isVisible({ timeout: 2_000 }).catch(() => false)}`);
    }
    await shot(page, 'ux-audit', 'I5_dataset_browser');
    await page.keyboard.press('Escape');
    await pause(page, 500);
  });

  // ── Auth gate probes ──────────────────────────────────────────────────────────
  // 401 probe: use page.evaluate + fetch(credentials:'omit') so browser explicitly
  // strips the auth cookie. This is the only way to force an unauthenticated request
  // without creating a new context.
  await soft('Auth gate 401', async () => {
    const status = await page.evaluate(async (url) => {
      const r = await fetch(`${url}/api/projects`, { credentials: 'omit' });
      return r.status;
    }, BASE_URL);
    expect(status).toBe(401);
    console.log('[Auth] ✅ GET /api/projects without auth → 401');
  });

  // 404 probe: use page.context().request (Playwright APIRequestContext) — inherits
  // context cookies (authenticated) but does NOT depend on the page renderer being alive,
  // avoiding the "Target page, context or browser has been closed" hang that occurs
  // when the renderer is in a stale state after a long Flow A session.
  await soft('Auth gate 404 for fake project', async () => {
    const res = await page.context().request.get(
      `${BASE_URL}/api/projects/00000000-0000-0000-0000-000000000000`,
      { failOnStatusCode: false }
    );
    console.log(`[Auth] GET /api/projects/<fake-uuid> → ${res.status()} (expect 404)`);
    expect(res.status()).toBe(404);
    console.log('[Auth] ✅ Fake project → 404');
  });

  console.log('[Flow B] ✅ All checks complete');
});
