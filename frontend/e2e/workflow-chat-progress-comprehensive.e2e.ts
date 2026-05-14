import { test, expect, Page, BrowserContext } from '@playwright/test';

// Force video for this audit suite (global config has video: 'off').
test.use({ video: 'on' });

/**
 * Comprehensive UI render audit — all 9 canonical chat_progress event kinds.
 *
 * Seeds a chat session with one progress message per kind (in the order a
 * typical workflow lifecycle would emit them) and asserts:
 *   - each line renders with the right friendly text
 *   - all lines render compactly (italic 🔹 style, not full assistant cards)
 *   - data-progress-kind attribute matches the canonical kind string
 *   - data-message-type='workflow_progress' on every progress line
 *   - regular user / assistant messages still render normally in between
 *
 * Saves a fullPage screenshot + the video recording is automatic per
 * playwright.config.ts (video: 'on').
 */

const BASE_URL = 'http://localhost:5000';
const BASE_DOMAIN = 'localhost';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
const STORAGE_KEY = 'biomate-chat-history';
const ACTIVE_SESSION_KEY = 'biomate-active-session-id';

async function registerAndAuth(page: Page, context: BrowserContext, label: string): Promise<void> {
  await context.clearCookies();
  await page.addInitScript(() => { try { localStorage.clear(); sessionStorage.clear(); } catch {} });
  const email = `e2e_progress_full_${label}_${Date.now()}@biomate.test`;
  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': E2E_TOKEN },
    data: { fullName: `Progress Full ${label}`, email, password: 'TestPass123!', termsAccepted: true },
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

// One entry per canonical event kind. Order matches a realistic lifecycle.
const PROGRESS_LIFECYCLE: Array<{ kind: string; content: string }> = [
  { kind: 'workflow.submitted',         content: 'Got it — starting your workflow now.' },
  { kind: 'workflow.queued',            content: 'Your workflow is in the AWS Batch queue.' },
  { kind: 'workflow.running',           content: 'Workflow is running.' },
  { kind: 'workflow.phase_started',     content: 'Step 1/3: FIRST_OK…' },
  { kind: 'workflow.phase_completed',   content: 'FIRST_OK done.' },
  { kind: 'workflow.phase_started',     content: 'Step 2/3: MIDDLE_FAIL…' },
  { kind: 'workflow.qc_gate_warning',   content: 'QC flagged hERG = 0.48 (threshold 0.5).' },
  { kind: 'workflow.qc_gate_blocked',   content: 'QC blocked on hERG — adjusting parameters.' },
  { kind: 'workflow.autoloop_started',  content: 'Trying again with logp_max=4.5, mw_max=480.' },
  { kind: 'workflow.phase_failed',      content: 'MIDDLE_FAIL failed — exit 42.' },
  { kind: 'workflow.failed',            content: 'Workflow stopped — exit 1. Looking into why…' },
];

test('all 9 canonical chat_progress event kinds render correctly', async ({ page, context }) => {
  await registerAndAuth(page, context, 'all-kinds');

  const sessionId = `e2e-full-${Date.now()}`;
  const invocationId = 'e2e-inv-full';

  // Mix a user message + an assistant text message + the progress lifecycle.
  const messages: any[] = [
    {
      id: 'msg-user-1',
      role: 'user',
      content: 'Run the ADMET workflow on these compounds.',
      timestamp: new Date(Date.now() - 120_000).toISOString(),
    },
    {
      id: 'msg-asst-1',
      role: 'assistant',
      content: "Sure — kicking off ADMET now. I'll keep you updated.",
      timestamp: new Date(Date.now() - 119_000).toISOString(),
    },
  ];
  PROGRESS_LIFECYCLE.forEach((p, i) => {
    messages.push({
      id: `msg-progress-${i}`,
      role: 'assistant',
      content: p.content,
      timestamp: new Date(Date.now() - (100_000 - i * 8_000)).toISOString(),
      invocationId,
      metadata: { type: 'workflow_progress', kind: p.kind, ts: Date.now() / 1000 - (100 - i * 8) },
    });
  });
  // Final assistant text reply tying it off
  messages.push({
    id: 'msg-asst-final',
    role: 'assistant',
    content: 'The run is wrapping up — I can re-launch with tighter logP filters if you want.',
    timestamp: new Date().toISOString(),
  });

  const session = {
    id: sessionId,
    title: 'Comprehensive progress render',
    userId: 'e2e-user',
    messages,
    createdAt: new Date(Date.now() - 200_000).toISOString(),
    updatedAt: new Date().toISOString(),
  };

  await page.addInitScript(([key, sid, sess, activeKey]) => {
    localStorage.setItem(key, JSON.stringify([sess]));
    localStorage.setItem(activeKey, sid);
  }, [STORAGE_KEY, sessionId, session, ACTIVE_SESSION_KEY]);

  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.locator('text=' + session.title).first().click({ timeout: 10_000 }).catch(() => {});
  await page.waitForTimeout(2000);

  // 1) All 11 progress lines visible.
  for (let i = 0; i < PROGRESS_LIFECYCLE.length; i++) {
    const loc = page.locator(`[data-testid="chat-message-msg-progress-${i}"]`);
    await expect(loc, `progress message ${i} (${PROGRESS_LIFECYCLE[i].kind}) visible`).toBeVisible({
      timeout: i === 0 ? 15_000 : 2_000,
    });
    // Content must match the friendly_message verbatim
    await expect(loc).toContainText(PROGRESS_LIFECYCLE[i].content);
    // 🔹 marker must be present
    await expect(loc).toContainText('🔹');
    // data-progress-kind must match the canonical kind
    await expect(loc).toHaveAttribute('data-progress-kind', PROGRESS_LIFECYCLE[i].kind);
    // No BioMate avatar/who-label inside the progress line
    expect(await loc.locator('text=BioMate').count()).toBe(0);
  }

  // 2) Regular user + assistant messages still render normally.
  const userMsg = page.locator('[data-testid="chat-message-msg-user-1"]');
  const asstMsg = page.locator('[data-testid="chat-message-msg-asst-1"]');
  const asstFinal = page.locator('[data-testid="chat-message-msg-asst-final"]');
  await expect(userMsg).toBeVisible();
  await expect(asstMsg).toBeVisible();
  await expect(asstFinal).toBeVisible();
  await expect(userMsg).toContainText('Run the ADMET workflow');
  await expect(asstMsg).toContainText('kicking off ADMET');
  await expect(asstFinal).toContainText('tighter logP filters');

  // 3) Compactness: combined height of 11 progress lines should fit in <450px
  //    (i.e. ~40px per line, vs. ~80-100px per full assistant card).
  const boxes = await Promise.all(
    PROGRESS_LIFECYCLE.map((_, i) =>
      page.locator(`[data-testid="chat-message-msg-progress-${i}"]`).boundingBox()
    )
  );
  const totalH = boxes.reduce((acc, b) => acc + (b?.height ?? 0), 0);
  const avgH = totalH / PROGRESS_LIFECYCLE.length;
  console.log(`[render-audit] ${PROGRESS_LIFECYCLE.length} progress lines: total=${totalH.toFixed(1)}px, avg=${avgH.toFixed(1)}px/line`);
  expect(totalH).toBeLessThan(450);
  expect(avgH).toBeLessThan(45);

  // 4) Audit screenshots (fullPage = the whole chat scroll)
  await page.screenshot({ path: '/tmp/chat-progress-all-kinds-fullpage.png', fullPage: true });
  await page.screenshot({ path: '/tmp/chat-progress-all-kinds.png' });

  // 5) Scroll the message container so all 11 lines are visible together, then screenshot.
  // (boundingBox should now reveal the chat region.)
  const firstBox = await page.locator('[data-testid="chat-message-msg-progress-0"]').boundingBox();
  const lastBox = await page.locator(`[data-testid="chat-message-msg-progress-${PROGRESS_LIFECYCLE.length - 1}"]`).boundingBox();
  console.log(`[render-audit] visible range y=${firstBox?.y.toFixed(0)} → y=${lastBox?.y.toFixed(0)} (span=${((lastBox?.y ?? 0) - (firstBox?.y ?? 0)).toFixed(0)}px)`);
});
