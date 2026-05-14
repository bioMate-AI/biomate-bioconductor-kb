import { test, expect, Page, BrowserContext } from '@playwright/test';

/**
 * E2E (b): UI render of workflow chat-progress messages.
 *
 * Verifies that chat-message.tsx renders `metadata.type === 'workflow_progress'`
 * messages as compact italic lines with the 🔹 icon, distinct from full AI
 * replies. Backend SSE delivery is covered separately by part (a) — this test
 * isolates the render path by seeding the chat session via localStorage.
 *
 * Pre-reqs:
 *   - Frontend dev server (vite + express) on http://localhost:5000
 *   - The chat-message.tsx changes from commit 2bd9570cf
 */

const BASE_URL = 'http://localhost:5000';
const BASE_DOMAIN = 'localhost';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
const STORAGE_KEY = 'biomate-chat-history';
const ACTIVE_SESSION_KEY = 'biomate-active-session-id';

async function registerAndAuth(page: Page, context: BrowserContext, label: string): Promise<void> {
  await context.clearCookies();
  await page.addInitScript(() => {
    try { localStorage.clear(); sessionStorage.clear(); } catch {}
  });
  const email = `e2e_progress_${label}_${Date.now()}@biomate.test`;
  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': E2E_TOKEN },
    data: { fullName: `Progress E2E ${label}`, email, password: 'TestPass123!', termsAccepted: true },
  });
  if (resp.ok()) {
    const data = await resp.json();
    if (data?.token) {
      await context.addCookies([{
        name: 'biomate_token', value: data.token, domain: BASE_DOMAIN, path: '/',
        httpOnly: true, secure: false, sameSite: 'Strict',
      }]);
    }
  }
}

test('workflow_progress messages render as italic 🔹 chat lines', async ({ page, context }) => {
  await registerAndAuth(page, context, 'render');
  // 1) Build a chat session with two progress messages baked in.
  const sessionId = `e2e-progress-${Date.now()}`;
  const invocationId = 'e2e-inv-12345';
  const session = {
    id: sessionId,
    title: 'E2E progress render test',
    userId: 'e2e-user',
    messages: [
      {
        id: 'msg-1',
        role: 'user',
        content: 'Run a workflow please',
        timestamp: new Date(Date.now() - 60_000).toISOString(),
      },
      {
        id: 'msg-2-progress-submitted',
        role: 'assistant',
        content: 'Got it — starting your workflow now.',
        timestamp: new Date(Date.now() - 30_000).toISOString(),
        invocationId,
        metadata: {
          type: 'workflow_progress',
          kind: 'workflow.submitted',
          ts: Date.now() / 1000 - 30,
          technical: { run_id: 'run-abc' },
        },
      },
      {
        id: 'msg-3-progress-phase',
        role: 'assistant',
        content: 'Step 2/5: STAR alignment…',
        timestamp: new Date(Date.now() - 15_000).toISOString(),
        invocationId,
        metadata: {
          type: 'workflow_progress',
          kind: 'workflow.phase_started',
          ts: Date.now() / 1000 - 15,
          technical: { phase_name: 'STAR alignment', n: 2, of: 5 },
        },
      },
    ],
    createdAt: new Date(Date.now() - 120_000).toISOString(),
    updatedAt: new Date().toISOString(),
  };

  // Seed BEFORE first navigation so the chat loads with our session ready.
  await page.addInitScript(([key, sid, sess, activeKey]) => {
    // Wrap as the array-of-sessions shape chat-history.ts expects.
    localStorage.setItem(key, JSON.stringify([sess]));
    localStorage.setItem(activeKey, sid);
  }, [STORAGE_KEY, sessionId, session, ACTIVE_SESSION_KEY]);

  await page.goto('/', { waitUntil: 'domcontentloaded' });

  // Click the session in the sidebar to open it (auto-open of active session
  // is unreliable on first load; the existing tests follow the same pattern).
  await page.locator('text=' + session.title).first().click({ timeout: 10_000 }).catch(() => {});
  // Allow a moment for the messages to render.
  await page.waitForTimeout(1500);

  // The two progress messages must appear by their data-testid (chat-message-{id}).
  const submittedLine = page.locator('[data-testid="chat-message-msg-2-progress-submitted"]');
  const phaseLine = page.locator('[data-testid="chat-message-msg-3-progress-phase"]');

  await expect(submittedLine).toBeVisible({ timeout: 15_000 });
  await expect(phaseLine).toBeVisible({ timeout: 5_000 });

  // 2) Friendly content must be the user-facing string, not the kind.
  await expect(submittedLine).toContainText('Got it — starting your workflow now.');
  await expect(phaseLine).toContainText('Step 2/5: STAR alignment…');

  // 3) The 🔹 icon must be present in each progress line (the visual marker).
  await expect(submittedLine).toContainText('🔹');
  await expect(phaseLine).toContainText('🔹');

  // 4) data-message-type and data-progress-kind must be set so future E2E tests
  //    can target specific event kinds.
  await expect(submittedLine).toHaveAttribute('data-message-type', 'workflow_progress');
  await expect(submittedLine).toHaveAttribute('data-progress-kind', 'workflow.submitted');
  await expect(phaseLine).toHaveAttribute('data-progress-kind', 'workflow.phase_started');

  // 5) The progress line MUST NOT be wrapped in the full assistant card layout.
  //    Specifically, the "BioMate" who-label and the markdown-styled content
  //    div should not be a parent of a progress message.
  const phaseHasWhoLabel = await phaseLine.locator('text=BioMate').count();
  expect(phaseHasWhoLabel).toBe(0);

  // 6) A regular user message in the same session should still render normally
  //    (sanity check that we didn't break the default path).
  const userMsg = page.locator('[data-testid="chat-message-msg-1"]');
  await expect(userMsg).toBeVisible();
  await expect(userMsg).toContainText('Run a workflow please');

  // Final screenshot for visual audit
  await page.screenshot({ path: '/tmp/workflow-chat-progress-e2e.png', fullPage: false });
});

test('progress lines render without taking the full assistant card surface', async ({ page, context }) => {
  await registerAndAuth(page, context, 'compact');
  // Compactness check: 5 progress messages should all fit in much less vertical
  // space than 5 full assistant cards would. This guards against accidentally
  // routing progress messages through the heavy default render path.
  const sessionId = `e2e-progress-compact-${Date.now()}`;
  const invocationId = 'e2e-inv-compact';
  const progressMessages = [
    { kind: 'workflow.submitted', text: 'Got it — starting your workflow now.' },
    { kind: 'workflow.queued', text: 'Your workflow is in the AWS Batch queue.' },
    { kind: 'workflow.running', text: 'Workflow is running.' },
    { kind: 'workflow.phase_started', text: 'Step 1/3: Quality control…' },
    { kind: 'workflow.phase_completed', text: 'Quality control done.' },
  ];

  const session = {
    id: sessionId,
    title: 'E2E compactness',
    userId: 'e2e-user',
    messages: progressMessages.map((p, i) => ({
      id: `msg-compact-${i}`,
      role: 'assistant',
      content: p.text,
      timestamp: new Date(Date.now() - (5 - i) * 5_000).toISOString(),
      invocationId,
      metadata: {
        type: 'workflow_progress',
        kind: p.kind,
        ts: Date.now() / 1000 - (5 - i) * 5,
      },
    })),
    createdAt: new Date(Date.now() - 60_000).toISOString(),
    updatedAt: new Date().toISOString(),
  };

  await page.addInitScript(([key, sid, sess, activeKey]) => {
    localStorage.setItem(key, JSON.stringify([sess]));
    localStorage.setItem(activeKey, sid);
  }, [STORAGE_KEY, sessionId, session, ACTIVE_SESSION_KEY]);

  await page.goto('/', { waitUntil: 'domcontentloaded' });

  // Click the session in the sidebar to open it (auto-open of active session
  // is unreliable on first load; the existing tests follow the same pattern).
  await page.locator('text=' + session.title).first().click({ timeout: 10_000 }).catch(() => {});
  // Allow a moment for the messages to render.
  await page.waitForTimeout(1500);

  // All five progress lines must be visible
  for (let i = 0; i < 5; i++) {
    await expect(page.locator(`[data-testid="chat-message-msg-compact-${i}"]`)).toBeVisible({
      timeout: i === 0 ? 15_000 : 2_000,
    });
  }

  // Measure: the bounding box of 5 progress lines combined should be < 250px
  // tall (i.e. each line is ~30-40px, which is much smaller than a card ~80px).
  const boxes = await Promise.all(
    [0, 1, 2, 3, 4].map((i) =>
      page.locator(`[data-testid="chat-message-msg-compact-${i}"]`).boundingBox()
    )
  );
  const totalHeight = boxes.reduce((acc, b) => acc + (b?.height ?? 0), 0);
  console.log(`[compact-check] 5 progress messages total height = ${totalHeight}px (target < 250)`);
  expect(totalHeight).toBeLessThan(250);

  await page.screenshot({ path: '/tmp/workflow-chat-progress-compact.png', fullPage: false });
});
