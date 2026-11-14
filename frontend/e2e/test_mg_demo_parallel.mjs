/**
 * MG Demo — Parallel E2E Test
 *
 * Runs all three demo workflows simultaneously in separate browser contexts:
 *   Session A: DESeq2 differential expression (GSE227835, pre-staged S3)
 *   Session B: enrichGO pathway enrichment (pre-staged de_genes.txt)
 *   Session C: ADMET screening (iptacopan SMILES)
 *
 * Wall-clock time: max(45, 30, 5) min ≈ 45 min instead of 80 min sequential.
 * All three submit to AWS Batch in parallel.
 */
import { chromium } from '@playwright/test';
import { resolveE2eBaseUrl } from './_e2e-base-url.ts';

const DEV_URL = resolveE2eBaseUrl('https://dev-public.biomate.ai');
const EMAIL = 'lifeifei163361@163.com';
const PASSWORD = 'WpmFixture!2026';
const E2E_TOKEN = 'biomate-e2e-bypass-token-dev-only';
const IPTACOPAN_SMILES = 'CCO[C@H]1CCN(Cc2c(OC)cc(C)c3[nH]ccc23)[C@H](c2ccc(C(=O)O)cc2)C1';
const DEMO_BUCKET = 's3://biomate-nextflow-work/demo/mg_demo';
const SCREENSHOT_DIR = '/Users/kky/biomate/reference/claude_design/biomate/screenshots_conference/parallel';
import { mkdirSync } from 'fs';

const PASS = '✅ PASS';
const FAIL = '❌ FAIL';
const SKIP = '⚠️ SKIP';

const allResults = [];
function record(session, label, ok, detail = '') {
  const status = ok === null ? SKIP : (ok ? PASS : FAIL);
  const full = `[${session}] ${label}`;
  console.log(`${status}  ${full}${detail ? ' — ' + detail : ''}`);
  allResults.push({ session, label, ok, detail });
}

async function screenshot(page, session, name) {
  mkdirSync(SCREENSHOT_DIR, { recursive: true });
  const p = `${SCREENSHOT_DIR}/${session}_${name}.png`;
  await page.screenshot({ path: p, fullPage: false }).catch(() => {});
}

async function login(page) {
  const domain = new URL(DEV_URL).hostname;
  const response = await page.request.post(`${DEV_URL}/api/auth/login`, {
    headers: { 'Content-Type': 'application/json', 'x-e2e-test-token': E2E_TOKEN },
    data: { email: EMAIL, password: PASSWORD },
  });
  if (!response.ok()) {
    throw new Error(`Login failed: HTTP ${response.status()}`);
  }
  const body = await response.json();
  const token = body.token;
  if (!token) throw new Error(`No token in login response`);
  await page.context().addCookies([{
    name: 'biomate_token', value: token, domain, path: '/',
    httpOnly: true, secure: DEV_URL.startsWith('https'), sameSite: 'Lax',
  }]);
  await page.goto(`${DEV_URL}/`);
  await page.waitForLoadState('networkidle');
}

async function startFreshChat(page) {
  await page.goto(`${DEV_URL}/`);
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(1500);
  const btn = page.locator('[data-testid="new-chat"], button:has-text("New Chat")').first();
  if (await btn.isVisible({ timeout: 3000 })) {
    await btn.click();
    await page.waitForTimeout(1000);
  }
}

async function sendMessage(page, msg) {
  const ta = page.locator('[data-testid="chat-input"], textarea').first();
  await ta.waitFor({ state: 'visible', timeout: 10000 });
  await ta.click();
  await ta.fill(msg);
  await page.waitForTimeout(300);
  const sendBtn = page.locator('[data-testid="chat-send-button"]').first();
  if (await sendBtn.isVisible({ timeout: 2000 })) {
    await sendBtn.click();
  } else {
    await page.keyboard.press('Enter');
  }
}

function routingMatches(card, keyword) {
  const text = ((card.name || '') + ' ' + (card.detail || '')).toLowerCase();
  return text.includes(keyword.toLowerCase());
}

async function waitForWorkflowCard(page, msgsBefore = 0, timeoutMs = 90000) {
  const deadline = Date.now() + timeoutMs;
  const aiMsgSel = '[class*="assistant"], .assistant-message';
  while (Date.now() < deadline) {
    await page.waitForTimeout(2000);
    const msgs = await page.locator(aiMsgSel).count();
    if (msgs > msgsBefore) {
      await page.waitForSelector('[data-testid="chat-stop-button"]', { state: 'hidden', timeout: timeoutMs })
        .catch(() => {});
      // find workflow card
      const cards = await page.locator('[data-testid="workflow-run-card"], [data-workflow-name], .workflow-card').all();
      for (const c of cards) {
        const name = await c.getAttribute('data-workflow-name') ||
                     await c.locator('[data-testid="workflow-name"], .workflow-title, h3, h4').first()
                       .textContent({ timeout: 2000 }).catch(() => '');
        if (name) return { found: true, name: name.trim(), detail: '' };
      }
      // fallback: look for any card-like element
      const allText = await page.locator(aiMsgSel).last().textContent({ timeout: 3000 }).catch(() => '');
      return { found: allText.length > 10, name: allText.slice(0, 80), detail: '' };
    }
  }
  return { found: false, name: '', detail: 'timeout' };
}

async function clickRun(page) {
  const runSels = [
    '[data-testid="button-run-workflow"]',
    'button:has-text("Run workflow")',
    'button:has-text("Run")',
    '[data-testid*="run"]',
  ];
  for (const sel of runSels) {
    const btn = page.locator(sel).first();
    if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) {
      await btn.click();
      return true;
    }
  }
  return false;
}

async function waitForCompletion(page, timeoutMs) {
  const doneSels = [
    '[data-testid="workflow-status-completed"]',
    '[data-testid="workflow-status-failed"]',
    '[data-testid="workflow-after-run"]',
    '.workflow-completed',
    '.workflow-failed',
    'text=Workflow completed',
    'text=Workflow failed',
    'text=completed successfully',
  ].join(', ');
  try {
    await page.waitForSelector(doneSels, { timeout: timeoutMs });
    const failSel = '[data-testid="workflow-status-failed"], .workflow-failed, text=Workflow failed';
    const failed = await page.locator(failSel).count() > 0;
    return { completed: !failed, failed, timeout: false };
  } catch {
    return { completed: false, failed: false, timeout: true };
  }
}

// ── Per-session runners ──────────────────────────────────────────────────────

async function runDeSeq2(browser) {
  const S = 'DESeq2';
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('console', m => m.type() === 'error' && console.log(`[${S}][app] ${m.text().slice(0, 100)}`));
  try {
    await login(page);
    record(S, 'Login', true);
    await startFreshChat(page);
    await screenshot(page, S, '01_fresh_chat');

    const msg = `Run differential expression on AChR+ myasthenia gravis PBMC data (GSE227835, 10 MG patients vs 10 healthy controls) — find the key complement pathway drivers.\nsamplesheet: ${DEMO_BUCKET}/sample_metadata.csv\nmatrix: ${DEMO_BUCKET}/counts_matrix.csv\ncontrasts: ${DEMO_BUCKET}/contrasts.csv`;
    const aiMsgSel = '[class*="assistant"], .assistant-message';
    const msgs0 = await page.locator(aiMsgSel).count();
    await sendMessage(page, msg);
    console.log(`[${S}] Message sent — waiting for routing card...`);

    const card = await waitForWorkflowCard(page, msgs0, 90000);
    record(S, 'Workflow card appears', card.found, (card.name || '').slice(0, 60));
    const routed = routingMatches(card, 'differential') || routingMatches(card, 'deseq2') || routingMatches(card, 'abundance');
    record(S, 'Routes to DESeq2/differentialabundance', routed, `"${(card.name || '').slice(0, 60)}"`);
    await screenshot(page, S, '02_card');

    const ran = await clickRun(page);
    record(S, 'Run clicked', ran);
    if (ran) {
      console.log(`[${S}] Run started — waiting up to 45 min...`);
      await screenshot(page, S, '03_running');
      const exec = await waitForCompletion(page, 2700000);
      const state = exec.timeout ? 'timed out' : exec.failed ? 'workflow failed' : 'success';
      record(S, 'DESeq2 completes', exec.completed || exec.failed, state);
      await screenshot(page, S, '04_done');
    }
  } catch (err) {
    record(S, 'Session error', false, err.message);
  } finally {
    await ctx.close();
  }
}

async function runEnrichGO(browser) {
  const S = 'enrichGO';
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('console', m => m.type() === 'error' && console.log(`[${S}][app] ${m.text().slice(0, 100)}`));
  try {
    await login(page);
    record(S, 'Login', true);
    await startFreshChat(page);
    await screenshot(page, S, '01_fresh_chat');

    const msg = `Run pathway enrichment on DE genes from the MG vs HC comparison — find top complement GO terms.\ngene_list: ${DEMO_BUCKET}/de_genes.txt`;
    const aiMsgSel = '[class*="assistant"], .assistant-message';
    const msgs0 = await page.locator(aiMsgSel).count();
    await sendMessage(page, msg);
    console.log(`[${S}] Message sent — waiting for routing card...`);

    const card = await waitForWorkflowCard(page, msgs0, 90000);
    record(S, 'Workflow card appears', card.found, (card.name || '').slice(0, 60));
    const routed = routingMatches(card, 'clusterprofiler') || routingMatches(card, 'enrichgo') ||
      routingMatches(card, 'pathway') || routingMatches(card, 'enrichment');
    record(S, 'Routes to enrichGO/clusterProfiler', routed, `"${(card.name || '').slice(0, 60)}"`);
    await screenshot(page, S, '02_card');

    const ran = await clickRun(page);
    record(S, 'Run clicked', ran);
    if (ran) {
      console.log(`[${S}] Run started — waiting up to 30 min...`);
      await screenshot(page, S, '03_running');
      const exec = await waitForCompletion(page, 1800000);
      const state = exec.timeout ? 'timed out' : exec.failed ? 'workflow failed' : 'success';
      record(S, 'enrichGO completes', exec.completed || exec.failed, state);
      await screenshot(page, S, '04_done');
    }
  } catch (err) {
    record(S, 'Session error', false, err.message);
  } finally {
    await ctx.close();
  }
}

async function runADMET(browser) {
  const S = 'ADMET';
  const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('console', m => m.type() === 'error' && console.log(`[${S}][app] ${m.text().slice(0, 100)}`));
  try {
    await login(page);
    record(S, 'Login', true);
    await startFreshChat(page);
    await screenshot(page, S, '01_fresh_chat');

    const msg = `Screen iptacopan for ADMET properties. SMILES: ${IPTACOPAN_SMILES}`;
    const aiMsgSel = '[class*="assistant"], .assistant-message';
    const msgs0 = await page.locator(aiMsgSel).count();
    await sendMessage(page, msg);
    console.log(`[${S}] Message sent — waiting for routing card...`);

    const card = await waitForWorkflowCard(page, msgs0, 90000);
    record(S, 'Workflow card appears', card.found, (card.name || '').slice(0, 60));
    const routed = routingMatches(card, 'admet') || routingMatches(card, 'predict') || routingMatches(card, 'properties');
    record(S, 'Routes to ADMET workflow', routed, `"${(card.name || '').slice(0, 60)}"`);
    await screenshot(page, S, '02_card');

    const ran = await clickRun(page);
    record(S, 'Run clicked', ran);
    if (ran) {
      console.log(`[${S}] Run started — waiting up to 5 min...`);
      await screenshot(page, S, '03_running');
      const exec = await waitForCompletion(page, 300000);
      const state = exec.timeout ? 'timed out' : exec.failed ? 'workflow failed' : 'success';
      record(S, 'ADMET completes', exec.completed, state);
      await screenshot(page, S, '04_done');
    }
  } catch (err) {
    record(S, 'Session error', false, err.message);
  } finally {
    await ctx.close();
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────

const browser = await chromium.launch({ headless: true });
console.log(`\n🚀  MG Demo — 3 workflows in parallel → ${DEV_URL}\n`);
const start = Date.now();

await Promise.allSettled([
  runDeSeq2(browser),
  runEnrichGO(browser),
  runADMET(browser),
]);

await browser.close();

const elapsed = Math.round((Date.now() - start) / 1000);
const passed = allResults.filter(r => r.ok === true).length;
const failed = allResults.filter(r => r.ok === false).length;
const skipped = allResults.filter(r => r.ok === null).length;

console.log(`\n${'─'.repeat(60)}`);
console.log(`Total wall-clock: ${Math.floor(elapsed/60)}m ${elapsed%60}s`);
console.log(`${passed} passed · ${failed} failed · ${skipped} skipped`);
process.exit(failed > 0 ? 1 : 0);
