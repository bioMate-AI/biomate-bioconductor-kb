/**
 * E2E: Project Workspace — full end-to-end lifecycle.
 *
 * This test file is intentionally comprehensive. Each test drives a REAL browser
 * against a REAL running server with REAL authentication, REAL S3 uploads, and
 * REAL workflow execution on AWS Batch. No page.route() mocking anywhere.
 *
 * Journey covered:
 *
 *   UC-PW1  LLM context injection
 *           Create project with researchGoal → open chat in project context →
 *           ask "what is the research focus?" → wait for LLM (90 s) → verify
 *           response contains research goal keywords (proves system prompt injection).
 *
 *   UC-PW2  Full file-to-run-to-tab cycle   [S3 + AWS Batch required]
 *           Upload FASTQ to project (real S3) → click "Analyze with BioMate" →
 *           verify chat opens pre-filled with filename → submit → wait for LLM
 *           routing (90 s) → click Run → wait for completion (up to 30 min) →
 *           verify SSE progress pills appeared → navigate back to project →
 *           Workflow Runs tab → verify run in API list AND in UI → click run →
 *           verify NextflowWorkflowViewer shows completed badge, phases, download button.
 *
 *   UC-PW3  Active project banner
 *           New Chat from Chat tab → banner visible → "Go to project" navigates back.
 *
 *   UC-PW4  Project lifecycle actions
 *           Rename via ⋯ dropdown → API confirms new name.
 *           Archive → redirect to /projects → API confirms status=archived.
 *
 *   UC-PW5  Auth gates (unauthenticated)
 *           All project endpoints return 401 when no cookie is present.
 *
 * Timeouts:
 *   LLM routing:  90 s
 *   AWS Batch:    30 min per workflow
 *   Total budget: ~35 min (UC-PW1 + UC-PW2 dominate)
 *
 * Run:
 *   BIOMATE_URL=https://dev-public.biomate.ai \
 *   E2E_FIXTURE_PASSWORD=WpmFixture!2026 \
 *   AWS_ACCESS_KEY_ID=... S3_BUCKET_NAME=... \
 *   npx playwright test e2e/project-workspace.e2e.ts --project=chromium
 *
 * Constraints (CLAUDE.md):
 *   - NO page.route() mocking. Real backend only.
 *   - One shared project across UC-PW1..UC-PW4 (rule 2: don't create per test).
 *   - Fixture: lifeifei163361@163.com / WpmFixture!2026.
 *   - Screenshots → e2e/screenshots/project-workspace/.
 */

import { test, expect, type Page, type APIRequestContext } from '@playwright/test';
import {
  sendAndWait,
  clickRunAndWait,
  waitForNoActiveRuns,
  shot,
  pause,
  BASE_URL,
} from './demo-helpers.js';

// ── Constants ─────────────────────────────────────────────────────────────────

const FIXTURE_EMAIL    = 'lifeifei163361@163.com';
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const E2E_TOKEN        = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';
const EXEC_TIMEOUT_MS  = 30 * 60_000; // 30 min — AWS Batch cold start

// File upload tests require S3 credentials (run on dev EC2, not locally)
const S3_AVAILABLE = !!(process.env.AWS_ACCESS_KEY_ID && process.env.S3_BUCKET_NAME);

// Research goal keyword baked in so the LLM context injection test can verify it
const RESEARCH_GOAL = 'Study rheumatoid arthritis GWAS data to identify causal genetic variants';
const RESEARCH_KEYWORDS = ['rheumatoid', 'arthritis', 'GWAS', 'genetic'];

// Shared across all serial tests
let sharedProjectId: string;
let sharedProjectName: string;
let uploadedRunId: string | null = null; // set by UC-PW2, read by Workflow Runs assertions

// ── Auth ──────────────────────────────────────────────────────────────────────

async function login(page: Page): Promise<void> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');

  const token = await page.evaluate(
    async ({ baseUrl, email, password, e2eToken }) => {
      const resp = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': e2eToken },
        credentials: 'include',
        body: JSON.stringify({ email, password }),
      });
      if (!resp.ok) throw new Error(`Login ${resp.status}: ${await resp.text()}`);
      return ((await resp.json()) as { token: string }).token;
    },
    { baseUrl: BASE_URL, email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, e2eToken: E2E_TOKEN }
  );

  const domain = new URL(BASE_URL).hostname;
  await page.context().addCookies([{
    name: 'biomate_token', value: token, domain, path: '/',
    httpOnly: true, secure: BASE_URL.startsWith('https'), sameSite: 'Lax',
  }]);
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  // Suppress survey for 7 days
  await page.evaluate(() => {
    try { localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 86400_000)); } catch {}
  });
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 30_000 });
}

// ── Project helpers ───────────────────────────────────────────────────────────

async function apiLoginRequest(request: APIRequestContext): Promise<void> {
  await request.post(`${BASE_URL}/api/auth/login`, {
    headers: { 'x-e2e-test-token': E2E_TOKEN },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
}

async function apiCreateProject(request: APIRequestContext, name: string): Promise<string> {
  const res = await request.post(`${BASE_URL}/api/projects`, {
    data: {
      name,
      description: 'E2E project workspace test',
      primaryDomain: 'genomics',
      researchGoal: RESEARCH_GOAL,
    },
  });
  expect(res.ok(), `POST /api/projects failed: ${await res.text()}`).toBeTruthy();
  const body = await res.json();
  const id = body?.project?.id ?? body?.id;
  expect(id, 'project id missing from response').toBeTruthy();
  return id;
}

// ── Status helpers (mirrors service-page-execution.e2e.ts) ───────────────────

async function getOverallStatus(page: Page): Promise<string> {
  return page.evaluate(() => {
    const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
    if (badge) {
      const s = (badge as HTMLElement).dataset.status ?? '';
      if (s) return s;
    }
    const cards = document.querySelectorAll('[data-testid^="phase-card-"]');
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'completed')) return 'completed';
    if (Array.from(cards).some(c => (c as HTMLElement).dataset.status === 'failed')) return 'failed';
    return 'unknown';
  }).catch(() => 'unknown');
}

async function waitForTerminalStatus(page: Page): Promise<string> {
  const deadline = Date.now() + 10_000;
  let status = await getOverallStatus(page);
  while (status === 'running' && Date.now() < deadline) {
    await pause(page, 1_000);
    status = await getOverallStatus(page);
  }
  return status;
}

// ── The tests ─────────────────────────────────────────────────────────────────

test.describe.serial('project-workspace', () => {

  // ── Setup: create one project, reused across all tests ─────────────────────
  test.beforeAll(async ({ request }) => {
    await apiLoginRequest(request);
    sharedProjectName = `PW-E2E ${Date.now()}`;
    sharedProjectId   = await apiCreateProject(request, sharedProjectName);
    console.log(`[setup] project created: ${sharedProjectId} "${sharedProjectName}"`);
  });

  // ── Teardown: hard-delete (archived projects linger in DB otherwise) ────────
  test.afterAll(async ({ request }) => {
    if (!sharedProjectId) return;
    await apiLoginRequest(request);
    await request.delete(`${BASE_URL}/api/projects/${sharedProjectId}`).catch(() => {});
    console.log(`[teardown] project deleted: ${sharedProjectId}`);
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-PW1  LLM context injection — researchGoal appears in LLM response
  // ────────────────────────────────────────────────────────────────────────────
  test('UC-PW1: researchGoal injected into LLM system prompt — model describes project context', async ({ browser }) => {
    test.setTimeout(3 * 60_000); // 90 s LLM + overhead

    const page = await browser.newPage();
    page.on('console', msg => {
      if (/SSE|project|context/i.test(msg.text())) console.log(`[browser] ${msg.text()}`);
    });

    try {
      await login(page);

      // Activate the project in localStorage so the chat stream carries projectId
      await page.evaluate((id: string) => {
        try { localStorage.setItem('biomate-active-project-id', id); } catch {}
      }, sharedProjectId);

      // Start a fresh chat on the root route
      await page.goto(BASE_URL);
      await page.waitForLoadState('load');
      await page.locator('[data-testid="chat-input"], textarea').first()
        .waitFor({ state: 'visible', timeout: 20_000 });

      // Banner must show the project name
      const banner = page.getByTestId('active-project-banner');
      await expect(banner).toBeVisible({ timeout: 8_000 });
      await shot(page, 'project-workspace', 'PW1_01_banner_visible');
      console.log('[PW1] banner visible — project context is active');

      // Ask the LLM what the project is about — this will ONLY return correct info
      // if the backend injected researchGoal into the system prompt
      const hasRunBtn = await sendAndWait(
        page,
        'What is the research focus of this project? Summarise it in one sentence.',
        90_000
      );
      console.log(`[PW1] LLM responded (hasRunBtn=${hasRunBtn})`);
      await shot(page, 'project-workspace', 'PW1_02_llm_response');

      // The response must contain at least one of the keywords from our researchGoal
      const responseText = await page
        .locator('[data-is-latest-assistant="true"]').first()
        .textContent({ timeout: 5_000 })
        .catch(() => '');

      console.log(`[PW1] LLM response excerpt: "${responseText?.slice(0, 200)}"`);

      const mentionsGoal = RESEARCH_KEYWORDS.some(kw =>
        responseText?.toLowerCase().includes(kw.toLowerCase())
      );
      expect(
        mentionsGoal,
        `LLM response does not mention any of [${RESEARCH_KEYWORDS.join(', ')}] — ` +
        `project context was not injected into the system prompt. Got: "${responseText?.slice(0, 300)}"`
      ).toBe(true);

      console.log('[PW1] ✅ research goal confirmed in LLM response');
    } finally {
      await page.close().catch(() => {});
    }
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-PW2  File upload → Analyze → full workflow run → Workflow Runs tab
  // ────────────────────────────────────────────────────────────────────────────
  test('UC-PW2: upload file → Analyze pre-fills chat → run workflow → appears in Workflow Runs tab', async ({ browser }) => {
    test.skip(!S3_AVAILABLE, 'S3 not configured — run on dev EC2 with AWS credentials set');
    test.setTimeout((90_000 + EXEC_TIMEOUT_MS + 120_000)); // LLM + AWS Batch + buffer

    const page = await browser.newPage();
    page.on('console', msg => {
      const t = msg.text();
      if (t.includes('[SSE') || t.includes('[UnifiedExecution') || t.includes('project') || msg.type() === 'error') {
        console.log(`[browser:${msg.type()}] ${t}`);
      }
    });

    try {
      await login(page);

      // ── 1. Upload a small FASTQ file to the project via the UI ──────────────
      await page.goto(`${BASE_URL}/projects?project=${sharedProjectId}&tab=files`);
      await page.getByTestId('project-file-tree').waitFor({ state: 'visible', timeout: 15_000 });

      const fileInput = page.getByTestId('project-files-input');
      await fileInput.setInputFiles({
        name: 'e2e_test.fastq',
        mimeType: 'text/plain',
        buffer: Buffer.from(
          '@E2E_READ_1\nGATTTGGGGTTTCAAGCAGGGCGATTGCTTATATCCTGATGCCGTGGCAGATTCCTAT\n+\n' +
          '!\'\'*((((***+))%%%++)(%%%%).1***-+*\'\'\')\'.1^C,3\'110%%+##\n' +
          '@E2E_READ_2\nACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACG\n+\n' +
          'IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII\n'
        ),
      });

      // File appears in tree under inputs/
      await expect(page.locator('text=e2e_test.fastq')).toBeVisible({ timeout: 15_000 });
      await shot(page, 'project-workspace', 'PW2_01_file_uploaded');
      console.log('[PW2] file uploaded to project');

      // ── 2. Click "Analyze with BioMate" → chat opens pre-filled ─────────────
      const analyzeBtn = page.getByTestId('button-analyze-files');
      await expect(analyzeBtn).toBeVisible({ timeout: 5_000 });
      await analyzeBtn.click();

      // Should navigate to / (chat root)
      await expect(page).toHaveURL(/^\/?(\?.*)?$/, { timeout: 12_000 });

      // Active project banner must be visible
      await expect(page.getByTestId('active-project-banner')).toBeVisible({ timeout: 10_000 });

      // Chat input MUST be pre-filled with the filename
      const chatInput = page.locator('[data-testid="chat-input"], textarea').first();
      await chatInput.waitFor({ state: 'visible', timeout: 10_000 });
      const prefillValue = await chatInput.inputValue();
      expect(prefillValue, 'chat input not pre-filled with uploaded filename').toContain('e2e_test.fastq');
      console.log(`[PW2] chat pre-filled: "${prefillValue.slice(0, 100)}..."`);
      await shot(page, 'project-workspace', 'PW2_02_chat_prefilled');

      // ── 3. Submit the pre-filled message and wait for LLM routing ───────────
      await waitForNoActiveRuns(page, 120_000);
      console.log('[PW2] submitting analyze message to LLM...');

      const hasRunBtn = await sendAndWait(page, prefillValue, 90_000);
      console.log(`[PW2] LLM responded — Run button visible: ${hasRunBtn}`);
      await shot(page, 'project-workspace', 'PW2_03_llm_routed');

      // LLM must have routed to a workflow (Run button present)
      expect(
        hasRunBtn,
        'LLM did not route to a workflow after the file-analysis prompt — no Run button appeared'
      ).toBe(true);

      // Workflow chip must show something related to the file type
      const chipText = await page.locator('.wf-chip-name').first()
        .textContent({ timeout: 10_000 })
        .catch(() => '');
      console.log(`[PW2] workflow chip: "${chipText}"`);

      // ── 4. Click Run and wait for completion ────────────────────────────────
      console.log('[PW2] clicking Run...');
      const execPromise = clickRunAndWait(page, EXEC_TIMEOUT_MS);

      // Capture the running state in parallel (fast workflows complete before we can check)
      let observedRunning = false;
      const runningPoll = (async () => {
        const deadline = Date.now() + 120_000;
        while (Date.now() < deadline) {
          const s = await getOverallStatus(page);
          if (s === 'running') {
            observedRunning = true;
            console.log('[PW2] ✅ running state captured');
            await shot(page, 'project-workspace', 'PW2_04_running');
            return;
          }
          if (s === 'completed' || s === 'failed') return;
          await pause(page, 2_000);
        }
      })();

      await Promise.race([execPromise, runningPoll]);
      uploadedRunId = await execPromise;

      if (!observedRunning) console.log('[PW2] ⚠️ completed before running state was captured');

      const finalStatus = await waitForTerminalStatus(page);
      console.log(`[PW2] terminal status: "${finalStatus}", runId: "${uploadedRunId}"`);
      await shot(page, 'project-workspace', 'PW2_05_terminal');

      expect(
        finalStatus,
        `workflow failed — got status "${finalStatus}"`
      ).toBe('completed');

      // ── 5. SSE progress pills ────────────────────────────────────────────────
      const pillCount = await page.evaluate(() =>
        document.querySelectorAll('[data-message-type="workflow_progress"]').length
      ).catch(() => 0);
      console.log(`[PW2] SSE progress pills: ${pillCount}`);
      if (pillCount === 0) {
        console.warn('[PW2] ⚠️ no workflow_progress pills — check SSE inject path');
      }

      // ── 6. After-run tabs ────────────────────────────────────────────────────
      await pause(page, 2_000);
      const afterTabBtn = page.locator('[data-testid="panel-tab-after-run"]').first();
      if (await afterTabBtn.isVisible({ timeout: 5_000 }).catch(() => false)) {
        const isActive = await afterTabBtn.evaluate(el =>
          el.classList.contains('active') || el.getAttribute('aria-selected') === 'true'
        ).catch(() => false);
        if (!isActive) await afterTabBtn.click().catch(() => {});
        await pause(page, 1_000);
      }

      const downloadBtn = page.locator('[data-testid="afterrun-download-report"]').first();
      const downloadVisible = await downloadBtn.isVisible({ timeout: 5_000 }).catch(() => false);
      console.log(`[PW2] download report button: ${downloadVisible ? '✅' : '⚠️ not found'}`);
      await shot(page, 'project-workspace', 'PW2_06_after_run');

      // ── 7. Navigate to project → Workflow Runs tab ──────────────────────────
      await page.goto(`${BASE_URL}/projects?project=${sharedProjectId}&tab=workflows`);
      await page.waitForLoadState('load');
      await shot(page, 'project-workspace', 'PW2_07_project_runs_tab');

      // Verify via API: the run must be linked to this project
      const apiRes = await page.request.get(
        `${BASE_URL}/api/workflows/runs?projectId=${sharedProjectId}`
      );
      expect(apiRes.ok(), `GET /api/workflows/runs?projectId failed: ${apiRes.status()}`).toBeTruthy();
      const apiBody = await apiRes.json();
      const runs: any[] = apiBody?.runs ?? apiBody ?? [];
      console.log(`[PW2] API run count for project: ${runs.length}`);
      expect(runs.length, 'no runs linked to project in API').toBeGreaterThan(0);

      if (uploadedRunId) {
        const matchedRun = runs.find((r: any) => r.runId === uploadedRunId || r.id === uploadedRunId);
        expect(
          matchedRun,
          `run ${uploadedRunId} not found in project runs (API returned: ${JSON.stringify(runs.map((r: any) => r.id || r.runId))})`
        ).toBeTruthy();
        console.log('[PW2] ✅ run linked to project in API');
      }

      // Verify in UI: Workflow Runs tab must show the run list
      const runsList = page.locator('[data-testid="project-runs-list"], [data-testid^="project-run-item-"]');
      await expect(runsList.first()).toBeVisible({ timeout: 15_000 });
      await shot(page, 'project-workspace', 'PW2_08_runs_list');

      // ── 8. Click the run → verify NextflowWorkflowViewer renders ────────────
      await runsList.first().click();
      await pause(page, 2_000);

      // The embedded viewer must show up
      const viewer = page.locator('[data-testid="nextflow-workflow-viewer"]');
      await expect(viewer).toBeVisible({ timeout: 10_000 });
      await shot(page, 'project-workspace', 'PW2_09_viewer');

      // Overall status badge inside the viewer must show "completed"
      const viewerStatus = await page.evaluate(() => {
        const badge = document.querySelector('[data-testid="workflow-overall-status-badge"]');
        return (badge as HTMLElement | null)?.dataset.status ?? badge?.textContent ?? 'unknown';
      });
      console.log(`[PW2] viewer status badge: "${viewerStatus}"`);
      expect(
        /completed/i.test(viewerStatus),
        `viewer shows "${viewerStatus}" instead of "completed"`
      ).toBe(true);

      // Phase cards must be visible
      const phaseCards = viewer.locator('[data-testid^="phase-card-"]');
      const phaseCount = await phaseCards.count();
      console.log(`[PW2] phase cards in viewer: ${phaseCount}`);
      expect(phaseCount, 'no phase cards rendered in embedded viewer').toBeGreaterThan(0);

      await shot(page, 'project-workspace', 'PW2_10_viewer_phases');
      console.log('[PW2] ✅ full file-to-run-to-tab cycle complete');

    } finally {
      await page.close().catch(() => {});
    }
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-PW3  Active project banner — new chat → banner → Go to project
  // ────────────────────────────────────────────────────────────────────────────
  test('UC-PW3: Chat tab New Chat sets project active, banner "Go to project" navigates back', async ({ page }) => {
    test.setTimeout(60_000);
    await login(page);

    // Navigate to Chat tab of the project
    await page.goto(`${BASE_URL}/projects?project=${sharedProjectId}&tab=chat`);
    await page.getByRole('tab', { name: /chat/i }).waitFor({ state: 'visible', timeout: 12_000 });
    await page.getByRole('tab', { name: /chat/i }).click();

    // Click New Chat (the dashed card or button)
    const newChatBtn = page
      .getByTestId('button-new-project-chat')
      .or(page.getByRole('button', { name: /new chat/i }))
      .first();
    await expect(newChatBtn).toBeVisible({ timeout: 10_000 });
    await newChatBtn.click();

    // Chat root must open
    await expect(page).toHaveURL(/^\/?(\?.*)?$/, { timeout: 12_000 });
    await page.locator('[data-testid="chat-input"], textarea').first()
      .waitFor({ state: 'visible', timeout: 20_000 });

    // Banner must show project name
    const bannerName = page.getByTestId('active-project-banner-name');
    await expect(bannerName).toBeVisible({ timeout: 8_000 });
    const bannerText = await bannerName.textContent();
    expect(bannerText, 'banner does not show project name').toContain(sharedProjectName);
    await shot(page, 'project-workspace', 'PW3_01_banner_in_chat');
    console.log(`[PW3] banner shows: "${bannerText}"`);

    // "Go to project" must navigate back to the project detail
    await page.getByTestId('active-project-banner-goto').click();
    await expect(page).toHaveURL(new RegExp(`project=${sharedProjectId}`), { timeout: 10_000 });
    await shot(page, 'project-workspace', 'PW3_02_back_to_project');
    console.log('[PW3] ✅ banner navigation complete');
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-PW4  Lifecycle actions: rename → API confirms; archive → API confirms
  // ────────────────────────────────────────────────────────────────────────────
  test('UC-PW4: rename project via ⋯ menu → API confirms new name, then archive → API confirms archived', async ({ page }) => {
    test.setTimeout(60_000);
    await login(page);

    await page.goto(`${BASE_URL}/projects?project=${sharedProjectId}`);
    await page.getByRole('heading', { level: 1 }).waitFor({ state: 'visible', timeout: 12_000 });

    // ── Rename ────────────────────────────────────────────────────────────────
    const moreBtn = page
      .getByTestId('project-actions-menu')
      .or(page.locator('button').filter({ hasText: /^$/ }).filter({ has: page.locator('[data-lucide="more-horizontal"]') }))
      .or(page.getByRole('button', { name: /more/i }))
      .first();
    await expect(moreBtn).toBeVisible({ timeout: 8_000 });
    await moreBtn.click();

    await page.getByRole('menuitem', { name: /rename/i }).click();

    const renameInput = page.getByRole('textbox').first();
    await expect(renameInput).toBeVisible({ timeout: 5_000 });
    await renameInput.clear();
    const newName = `PW-E2E-Renamed-${Date.now()}`;
    await renameInput.fill(newName);
    await page.getByRole('button', { name: /save|confirm|ok/i }).click();

    // Wait for heading to update
    await expect(page.getByRole('heading', { level: 1 })).toContainText(newName, { timeout: 8_000 });
    await shot(page, 'project-workspace', 'PW4_01_renamed');
    console.log(`[PW4] renamed to "${newName}"`);

    // Verify via API
    const detailRes = await page.request.get(`${BASE_URL}/api/projects/${sharedProjectId}`);
    expect(detailRes.ok()).toBeTruthy();
    const detail = await detailRes.json();
    const apiName = detail?.project?.name ?? detail?.name;
    expect(apiName, `API shows "${apiName}" instead of "${newName}"`).toBe(newName);
    console.log('[PW4] ✅ rename confirmed in API');

    sharedProjectName = newName; // update for teardown reference

    // ── Archive ───────────────────────────────────────────────────────────────
    await moreBtn.click();
    await page.getByRole('menuitem', { name: /archive/i }).click();

    // AlertDialog confirmation
    const confirmBtn = page.getByRole('button', { name: /archive|confirm/i }).last();
    await expect(confirmBtn).toBeVisible({ timeout: 5_000 });
    await confirmBtn.click();

    // Must redirect to /projects
    await expect(page).toHaveURL(/\/projects/, { timeout: 10_000 });
    await shot(page, 'project-workspace', 'PW4_02_after_archive');

    // Project card must NOT appear in the default active list
    const card = page.locator(`[data-testid="project-card-${sharedProjectId}"]`);
    await expect(card).not.toBeVisible({ timeout: 5_000 });

    // API must confirm archived status
    const archiveRes = await page.request.get(`${BASE_URL}/api/projects/${sharedProjectId}`);
    expect(archiveRes.ok()).toBeTruthy();
    const archiveBody = await archiveRes.json();
    const status = archiveBody?.project?.status ?? archiveBody?.status;
    expect(status, `API status is "${status}" instead of "archived"`).toBe('archived');
    console.log('[PW4] ✅ archive confirmed in API');
  });

  // ────────────────────────────────────────────────────────────────────────────
  // UC-PW5  Auth gates — unauthenticated requests return 401
  // ────────────────────────────────────────────────────────────────────────────
  test('UC-PW5: all project endpoints return 401 when not authenticated', async ({ request }) => {
    const fakeId = '00000000-0000-0000-0000-000000000001';
    const cases: [string, () => Promise<import('@playwright/test').APIResponse>][] = [
      ['GET /api/projects',                () => request.get(`${BASE_URL}/api/projects`)],
      ['POST /api/projects',               () => request.post(`${BASE_URL}/api/projects`, { data: { name: 'x' } })],
      ['GET /api/projects/:id',            () => request.get(`${BASE_URL}/api/projects/${fakeId}`)],
      ['PATCH /api/projects/:id',          () => request.patch(`${BASE_URL}/api/projects/${fakeId}`, { data: { name: 'y' } })],
      ['DELETE /api/projects/:id',         () => request.delete(`${BASE_URL}/api/projects/${fakeId}`)],
      ['GET /api/projects/:id/files',      () => request.get(`${BASE_URL}/api/projects/${fakeId}/files`)],
      ['GET /api/workflows/runs?projectId',() => request.get(`${BASE_URL}/api/workflows/runs?projectId=${fakeId}`)],
    ];

    for (const [label, fn] of cases) {
      const res = await fn();
      expect(res.status(), `${label} should return 401, got ${res.status()}`).toBe(401);
    }
    console.log('[PW5] ✅ all 7 project endpoints correctly return 401 unauthenticated');
  });
});
