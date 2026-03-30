/**
 * BioMate UI Audit v4 — 2026-03-12
 * Tests: workflow search, param panel, dataset picker, output panel, nextflow summary fix
 */
import { chromium } from 'playwright';
import { mkdirSync } from 'fs';

const BASE_URL = 'http://localhost:5000';
const DIR = '/tmp/biomate-audit4-screenshots';
mkdirSync(DIR, { recursive: true });

const TIMESTAMP = () => new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

async function shot(page, name) {
  const path = `${DIR}/${name}.png`;
  await page.screenshot({ path, fullPage: false });
  console.log(`  📸 ${name}.png`);
  return path;
}

async function fullShot(page, name) {
  const path = `${DIR}/${name}-full.png`;
  await page.screenshot({ path, fullPage: true });
  console.log(`  📸 ${name}-full.png`);
  return path;
}

async function waitForChatIdle(page, timeout = 120000) {
  // Wait until the streaming indicator disappears
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const isTyping = await page.evaluate(() => {
      const typingEl = document.querySelector('[data-testid="typing-indicator"], .animate-pulse');
      const loadingEl = document.querySelector('[class*="animate-spin"]');
      return !!(typingEl || loadingEl);
    });
    if (!isTyping) return true;
    await page.waitForTimeout(1500);
  }
  return false;
}

async function waitForWorkflowCard(page, timeout = 60000) {
  try {
    await page.waitForSelector('[data-testid="workflow-card"], [class*="workflow"], button:has-text("Run Workflow"), button:has-text("Confirm")', {
      timeout,
    });
    return true;
  } catch {
    return false;
  }
}

async function registerOrLogin(page) {
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  // Check if we're on the home page already (logged in) or auth page
  const url = page.url();
  console.log(`  Current URL: ${url}`);

  if (url.includes('/auth') || url.includes('/login')) {
    // Need to register
    const email = `demo_audit_${Date.now()}@biomate.test`;
    const password = 'DemoPass123!';
    console.log(`  Registering as ${email}...`);

    const tabReg = page.locator('button:has-text("Register"), [role="tab"]:has-text("Register")').first();
    if (await tabReg.count() > 0) await tabReg.click();
    await page.waitForTimeout(500);

    await page.fill('input[name="email"], input[type="email"]', email);
    await page.fill('input[name="password"], input[type="password"]', password);

    const usernameField = page.locator('input[name="username"]');
    if (await usernameField.count() > 0) {
      await usernameField.fill(`demo_audit_${Date.now()}`);
    }

    await page.click('button[type="submit"]:has-text("Register"), button:has-text("Create Account")');
    await page.waitForTimeout(3000);
  }

  console.log(`  Final URL: ${page.url()}`);
}

async function main() {
  console.log(`\n🔬 BioMate UI Audit v4 — ${new Date().toISOString()}`);
  console.log(`   Output: ${DIR}\n`);

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    recordVideo: { dir: DIR, size: { width: 1440, height: 900 } },
  });
  const page = await ctx.newPage();

  const errors = [];
  page.on('console', msg => {
    if (msg.type() === 'error') errors.push(msg.text().slice(0, 150));
  });

  const findings = [];
  const check = (label, ok, detail = '') => {
    const icon = ok ? '✅' : '❌';
    const msg = `${icon} ${label}${detail ? ': ' + detail : ''}`;
    findings.push({ ok, label, detail });
    console.log(`  ${msg}`);
  };

  // ── 1. Load and authenticate ────────────────────────────────────────────────
  console.log('\n[1] Auth...');
  await registerOrLogin(page);
  await shot(page, '01-home');
  check('Page loads', !page.url().includes('/auth'));

  // ── 2. New chat ─────────────────────────────────────────────────────────────
  console.log('\n[2] Start new chat...');
  const newChatBtn = page.locator('button:has-text("New Chat")').first();
  if (await newChatBtn.count() > 0) {
    await newChatBtn.click();
    await page.waitForTimeout(500);
  }
  await shot(page, '02-new-chat');

  // ── 3. Send workflow query ───────────────────────────────────────────────────
  console.log('\n[3] Sending workflow query (cryo-EM SPA)...');
  const textarea = page.locator('textarea').first();
  check('Chat input exists', await textarea.count() > 0);

  await textarea.fill('Run a cryo-EM single particle analysis pipeline on my raw micrographs');
  await shot(page, '03-query-typed');
  await textarea.press('Enter');

  // Wait for response
  await page.waitForTimeout(3000);
  await shot(page, '04-streaming-start');

  // Wait for the response to settle (up to 90s for AI)
  console.log('  Waiting for AI response...');
  let responseReady = false;
  for (let i = 0; i < 60; i++) {
    await page.waitForTimeout(2000);
    const spinners = await page.locator('[class*="animate-spin"]').count();
    const pulses = await page.locator('[class*="animate-pulse"]').count();
    const wfCards = await page.locator('[data-testid="workflow-card"], button:has-text("Confirm"), button:has-text("Run Workflow")').count();
    if (wfCards > 0 || (spinners === 0 && pulses === 0 && i > 5)) {
      responseReady = true;
      break;
    }
    if (i % 5 === 0) console.log(`    ... still waiting (${i * 2}s, spinners=${spinners})`);
  }

  await shot(page, '05-response-received');
  await fullShot(page, '05-response-received');
  check('AI responded', responseReady);

  // ── 4. Check for workflow artifact / right panel ──────────────────────────
  console.log('\n[4] Checking workflow artifact panel...');

  // Check for workflow card in chat or right panel
  const workflowCard = page.locator('[data-testid="workflow-card"]').first();
  const workflowPanel = page.locator('[data-testid="workflow-panel"], [class*="workflow-viewer"]').first();
  const confirmBtn = page.locator('button:has-text("Confirm & Run"), button:has-text("Confirm")').first();
  const runWorkflowBtn = page.locator('button:has-text("Run Workflow")').first();

  const hasWorkflowCard = await workflowCard.count() > 0;
  const hasConfirmBtn = await confirmBtn.count() > 0;
  const hasRunBtn = await runWorkflowBtn.count() > 0;

  check('Workflow card/panel present', hasWorkflowCard || hasConfirmBtn || hasRunBtn);

  // Look for "pending_review" / "AWAITING REVIEW" badge
  const awaitingReview = await page.locator('text=/AWAITING REVIEW/i').count() > 0;
  check('Pending review UX present', awaitingReview, awaitingReview ? '' : 'may be in run state directly');

  // Check for scientific rationale
  const rationaleSection = await page.locator('text=/scientific rationale/i, text=/Rationale/i').count() > 0;
  check('Scientific rationale section', rationaleSection);

  await shot(page, '06-workflow-panel');

  // ── 5. Check for right-side artifact panel ────────────────────────────────
  console.log('\n[5] Checking right artifact panel layout...');
  const rightPanel = await page.evaluate(() => {
    // Check if there's a split-pane layout with artifact on right
    const panels = document.querySelectorAll('[class*="artifact"], [class*="panel"], [class*="right"]');
    return panels.length;
  });
  check('Split panel elements found', rightPanel > 0, `${rightPanel} elements`);

  // Check for workflow steps (phase cards)
  const phaseCards = await page.locator('[data-testid^="phase-run-count-"]').count();
  check('Phase cards present', phaseCards > 0, `${phaseCards} steps`);

  // ── 6. Check interactive tools (should NOT appear without real outputs) ─────
  console.log('\n[6] Checking interactive visualization tools...');
  const jupyterBtn = await page.locator('text=/JupyterLab/i, button:has-text("Jupyter")').count();
  const rstudioBtn = await page.locator('text=/RStudio/i, button:has-text("RStudio")').count();
  check('JupyterLab NOT shown without outputs', jupyterBtn === 0, `count=${jupyterBtn}`);
  check('RStudio NOT shown without outputs', rstudioBtn === 0, `count=${rstudioBtn}`);

  // Check for nextflow summary placeholder (should be gone or shown as "Run log" only)
  const nextflowSummaryCard = await page.locator('[class*="card"]:has-text("nextflow_run_summary")').count();
  check('nextflow_run_summary not shown as full card', nextflowSummaryCard === 0);

  await shot(page, '07-viz-tools-check');

  // ── 7. Check parameter panel ─────────────────────────────────────────────
  console.log('\n[7] Checking parameter panel / dataset picker...');

  // Look for file/data parameters
  const parameterSection = await page.locator('[data-testid*="param"], [class*="parameter"]').count();
  check('Parameter section found', parameterSection > 0, `${parameterSection} elements`);

  // Look for "My datasets" button
  const myDatasetsBtn = await page.locator('button:has-text("My datasets"), button:has-text("datasets")').count();
  check('My datasets picker present', myDatasetsBtn > 0, myDatasetsBtn > 0 ? '' : '(only appears with file-type params)');

  await shot(page, '08-parameter-panel');

  // ── 8. Check output section ───────────────────────────────────────────────
  console.log('\n[8] Checking outputs section...');
  const outputSection = await page.locator('text=/Outputs/i, [data-testid*="output"]').count();
  check('Output section exists', outputSection > 0);

  // Check Run log link (should be present if workflow ran)
  const runLogLink = await page.locator('a:has-text("Run log"), text=/Run log/i').count();
  console.log(`  Run log link count: ${runLogLink}`);

  await shot(page, '09-outputs-section');

  // ── 9. Test upload area linkage ─────────────────────────────────────────
  console.log('\n[9] Checking chat file upload area...');
  const fileUploadArea = await page.locator('input[type="file"], [data-testid="file-upload"], button:has-text("Upload")').count();
  check('File upload area present', fileUploadArea > 0, `${fileUploadArea} elements`);

  await shot(page, '10-upload-area');

  // ── 10. Scroll to check full page ─────────────────────────────────────────
  console.log('\n[10] Full page screenshot...');
  await fullShot(page, '11-full-page');

  // ── 11. Summary ────────────────────────────────────────────────────────────
  console.log('\n─────────────────────────────────────────');
  console.log('AUDIT RESULTS:');
  const passed = findings.filter(f => f.ok).length;
  const total = findings.length;
  findings.forEach(f => console.log(`  ${f.ok ? '✅' : '❌'} ${f.label}${f.detail ? ' — ' + f.detail : ''}`));
  console.log(`\n${passed}/${total} checks passed`);

  if (errors.length > 0) {
    console.log('\nConsole errors:');
    errors.slice(0, 10).forEach(e => console.log(`  ⚠️  ${e}`));
  }

  await browser.close();

  console.log(`\nScreenshots saved to: ${DIR}`);
  return { passed, total, errors };
}

main().catch(err => {
  console.error('Audit failed:', err);
  process.exit(1);
});
