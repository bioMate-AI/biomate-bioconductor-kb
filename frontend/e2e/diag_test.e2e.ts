import { test } from '@playwright/test';

const BASE_URL = 'http://localhost:5000';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';
const TEST_EMAIL = 'diag_test_user@biomate.test';
const TEST_PASS = 'DiagPass123!';

test('diagnose workflow card', async ({ browser }) => {
  // Get JWT via register (bypass E2E rate limit) or login
  const ctx0 = await browser.newContext();
  const pg0 = await ctx0.newPage();
  let jwt: string | null = null;
  const isJWT = (v: string) => /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v);
  const e2eHeaders = { 'X-E2E-Test-Token': E2E_TOKEN };

  try {
    const r1 = await pg0.request.post(`${BASE_URL}/api/auth/register`, {
      data: { fullName: 'Diag Test', email: TEST_EMAIL, password: TEST_PASS, terms_accepted: true },
      headers: e2eHeaders,
    });
    const b1 = await r1.json().catch(() => ({})) as any;
    if (b1?.token && isJWT(b1.token)) jwt = b1.token;
  } catch {}

  if (!jwt) {
    try {
      const r2 = await pg0.request.post(`${BASE_URL}/api/auth/login`, {
        data: { email: TEST_EMAIL, password: TEST_PASS },
        headers: e2eHeaders,
      });
      const b2 = await r2.json().catch(() => ({})) as any;
      if (b2?.token && isJWT(b2.token)) jwt = b2.token;
    } catch {}
  }
  await ctx0.close();
  console.log(`JWT obtained: ${jwt ? 'YES' : 'NO (proceeding without auth)'}`);

  const page = await browser.newPage();

  // Capture ALL console messages before navigation
  const allLogs: string[] = [];
  page.on('console', msg => allLogs.push(`[${msg.type()}] ${msg.text().slice(0, 300)}`));
  page.on('pageerror', err => allLogs.push(`[PAGE_ERROR] ${err.message}`));

  if (jwt) {
    const u = new URL(BASE_URL);
    await page.context().addCookies([{
      name: 'biomate_token', value: jwt,
      domain: u.hostname, path: '/', httpOnly: true, sameSite: 'Strict'
    }]);
  }

  await page.goto(BASE_URL);
  await page.waitForSelector('textarea', { state: 'visible', timeout: 20000 });

  const ta = page.locator('textarea').first();
  await ta.fill('Run predict_admet_properties workflow now for Imatinib SMILES: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5');
  await ta.press('Enter');

  // The typing indicator disappears when streaming STARTS (not when it ends).
  // Wait for either the workflow card to appear OR a long timeout covering the full stream.
  await page.waitForSelector('[data-testid="chat-response-pending"]', { state: 'visible', timeout: 30000 }).catch(() => {});
  // Wait for workflow card to appear (appears only after onSuccess fires)
  // OR wait up to 120s for the stream to complete and onSuccess to fire
  await page.waitForSelector(
    '[data-testid="workflow-artifact-panel"],[data-testid="nextflow-workflow-viewer"],[data-testid="button-confirm-and-run"]',
    { timeout: 120000 }
  ).catch(async () => {
    // Workflow card didn't appear — wait max 90s from now for any ChatInterface log
    await page.waitForTimeout(90000);
  });
  await page.waitForTimeout(2000);

  // Print all logs
  console.log(`\n=== Total console logs: ${allLogs.length} ===`);

  // ChatInterface logs
  const chatLogs = allLogs.filter(l => l.includes('ChatInterface'));
  console.log(`\n--- ChatInterface logs (${chatLogs.length}) ---`);
  chatLogs.forEach(l => console.log(l));

  // Errors
  const errors = allLogs.filter(l => l.includes('[error]') || l.includes('PAGE_ERROR'));
  console.log(`\n--- Errors (${errors.length}) ---`);
  errors.forEach(l => console.log(l));

  // Check DOM
  const hasWorkflowCard = await page.locator('[data-testid="workflow-artifact-panel"],[data-testid="nextflow-workflow-viewer"]').count();
  const hasRunBtn = await page.locator('[data-testid="button-run-workflow-panel"],[data-testid="button-confirm-and-run"],[data-testid="pipeline-confirm-run"]').count();
  const hasCopyIcon = await page.locator('[data-testid="button-copy-workflow-icon"]').count();
  console.log(`\nWorkflow card: ${hasWorkflowCard}, Run btn: ${hasRunBtn}, Copy icon: ${hasCopyIcon}`);

  // Print all non-delta, non-trivial logs for full picture
  const notableLogs = allLogs.filter(l =>
    !l.includes('[ChatInterface] Updating streaming') &&
    !l.includes('event: delta') &&
    !l.includes('[log] [') // filter noisy framework logs
  );
  console.log(`\n--- Notable logs (${notableLogs.length}) ---`);
  notableLogs.slice(0, 50).forEach(l => console.log(l));
});
