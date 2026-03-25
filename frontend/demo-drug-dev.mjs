/**
 * BioMate Drug Development Demo Recording
 * Narrative: "From Target to Safety Signal"
 * PM-approved script: KRAS G12C → structure + docking → QC gates → PK/download
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const BASE_URL  = 'http://localhost:5415';
const OUT_DIR   = path.join(__dirname, '..', 'demo_videos', 'drug_dev_' + Date.now());
const SS_DIR    = path.join(OUT_DIR, 'screenshots');
fs.mkdirSync(SS_DIR, { recursive: true });

// ── Prompts (PM-approved, word-for-word) ──────────────────────────────────
const PROMPTS = [
  // 1. Research anchor
  "What are the best molecular targets for overcoming KRAS G12C inhibitor resistance, and what structural features should I prioritize in next-generation covalent inhibitors?",
  // 2. Structure prediction + docking
  "Run structure prediction and docking for a next-generation covalent KRAS G12C inhibitor candidate. Use AlphaFold3 for structure prediction, then run DiffDock blind docking. The target is KRAS G12C and the ligand is a covalent warhead scaffold with a chloroacetamide group.",
  // 3. Drug safety QC
  "Run a full drug safety QC assessment for this compound using the compound_druglike profile. I need hERG cardiotoxicity, DILI liver safety, Ames mutagenicity, ClinTox, and PGx CYP2D6 coverage checks.",
  // 4. PK/PD + export
  "Run a non-compartmental PK analysis using PKNCA for this compound, then summarize all results so I can download a report for my team.",
];

async function shot(page, name) {
  const p = path.join(SS_DIR, `${name}.png`);
  await page.screenshot({ path: p, fullPage: false });
  console.log(`  📸 ${name}.png`);
  return p;
}

async function typeSlowly(locator, text, msPerChar = 35) {
  await locator.click();
  for (const ch of text) {
    await locator.pressSequentially(ch);
    await new Promise(r => setTimeout(r, msPerChar + Math.random() * 20));
  }
}

async function waitContentStable(page, timeout = 120000) {
  let prev = -1;
  const start = Date.now();
  while (Date.now() - start < timeout) {
    const len = await page.evaluate(() => {
      const els = document.querySelectorAll(
        '[class*="prose"] p, [class*="prose"] li, [class*="prose"] h1, [class*="prose"] h2, [class*="prose"] h3'
      );
      return [...els].reduce((s, e) => s + (e.textContent || '').length, 0);
    });
    if (len === prev && len > 80) return true;
    prev = len;
    await page.waitForTimeout(2500);
  }
  return false;
}

async function waitWorkflowPanel(page, timeout = 30000) {
  try {
    await page.waitForSelector('[data-testid="button-run-workflow-panel"]', { timeout });
    return true;
  } catch { return false; }
}

async function clickSend(page) {
  const btn = page.locator('[data-testid="chat-send-button"]').first();
  if (await btn.count() > 0) {
    await btn.click();
  } else {
    await page.keyboard.press('Enter');
  }
}

// ── Radix Select helper ───────────────────────────────────────────────────
async function selectQcProfile(page, profileId) {
  // Expand QC settings if collapsed
  const section = page.locator('[data-testid="qc-settings-section"]').first();
  if (await section.count() > 0) {
    const isExpanded = await section.evaluate(el => {
      return el.getAttribute('data-state') === 'open' ||
             !!el.querySelector('[role="combobox"]');
    });
    if (!isExpanded) {
      await section.click();
      await page.waitForTimeout(400);
    }
  }

  // Click the Radix SelectTrigger (the combobox)
  const trigger = page.locator('[role="combobox"]').first();
  if (await trigger.count() > 0) {
    await trigger.click();
    await page.waitForTimeout(300);
    // Click the option matching profileId
    const opt = page.locator(`[role="option"]`).filter({ hasText: profileId.replace(/_/g, '\u00a0') }).first();
    if (await opt.count() > 0) {
      await opt.click();
      console.log(`  ✅ QC profile set to: ${profileId}`);
    } else {
      // fallback: try text match with underscores
      const opt2 = page.locator(`[role="option"]`).filter({ hasText: profileId }).first();
      if (await opt2.count() > 0) await opt2.click();
      console.log(`  ✅ QC profile set (fallback): ${profileId}`);
    }
    await page.waitForTimeout(300);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────
async function main() {
  console.log('🎬 BioMate Drug Development Demo');
  console.log(`📁 Output: ${OUT_DIR}`);

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    recordVideo: { dir: OUT_DIR, size: { width: 1440, height: 900 } },
  });
  const page = await ctx.newPage();

  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 120)); });

  try {
    // ── Load app ────────────────────────────────────────────────────────
    console.log('\n[0] Loading BioMate...');
    await page.goto(BASE_URL, { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(1000);
    await shot(page, '00-home');

    // Start new chat
    const newChatBtn = page.locator('button:has-text("New Chat")').first();
    if (await newChatBtn.count() > 0) {
      await newChatBtn.click();
      await page.waitForTimeout(600);
    }

    const input = page.locator('[data-testid="chat-input"], textarea').first();
    await input.waitFor({ state: 'visible', timeout: 10000 });

    // ── PROMPT 1: Research anchor ────────────────────────────────────────
    console.log('\n[1] KRAS G12C research question...');
    await typeSlowly(input, PROMPTS[0]);
    await shot(page, '01-prompt1-typed');
    await clickSend(page);
    await page.waitForTimeout(2000);
    await shot(page, '02-prompt1-sent');

    console.log('  Waiting for response (up to 120s)...');
    const stable1 = await waitContentStable(page, 120000);
    await page.waitForTimeout(2000);
    await shot(page, '03-prompt1-response');
    console.log(`  ${stable1 ? '✅' : '⚠️'} Response stabilized`);

    // Scroll to show full response
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(1500);
    await shot(page, '04-prompt1-scrolled');

    // ── PROMPT 2: Structure prediction + docking ─────────────────────────
    console.log('\n[2] Structure prediction + docking workflow...');
    await input.click();
    await page.waitForTimeout(300);
    await typeSlowly(input, PROMPTS[1]);
    await shot(page, '05-prompt2-typed');
    await clickSend(page);
    await page.waitForTimeout(2000);
    await shot(page, '06-prompt2-sent');

    console.log('  Waiting for workflow panel or response (up to 120s)...');
    const hasWorkflow2 = await waitWorkflowPanel(page, 20000);
    if (!hasWorkflow2) {
      await waitContentStable(page, 100000);
    }
    await page.waitForTimeout(2000);
    await shot(page, '07-prompt2-workflow');

    // Scroll to see workflow panel
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(1500);
    await shot(page, '08-prompt2-docking-results');

    // ── PROMPT 3: Drug safety QC ─────────────────────────────────────────
    console.log('\n[3] Drug safety QC with compound_druglike profile...');
    await input.click();
    await page.waitForTimeout(300);
    await typeSlowly(input, PROMPTS[2]);
    await shot(page, '09-prompt3-typed');
    await clickSend(page);
    await page.waitForTimeout(2000);
    await shot(page, '10-prompt3-sent');

    console.log('  Waiting for QC workflow panel (up to 120s)...');
    const hasWorkflow3 = await waitWorkflowPanel(page, 20000);
    if (!hasWorkflow3) {
      await waitContentStable(page, 100000);
    }
    await page.waitForTimeout(1500);

    // Try to set QC profile to compound_druglike
    await selectQcProfile(page, 'compound_druglike');
    await page.waitForTimeout(800);
    await shot(page, '11-prompt3-qc-profile-set');

    // Scroll to see QC results
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(2000);
    await shot(page, '12-prompt3-qc-gates');

    // ── PROMPT 4: PK/PD + download ───────────────────────────────────────
    console.log('\n[4] PK analysis + download...');
    await input.click();
    await page.waitForTimeout(300);
    await typeSlowly(input, PROMPTS[3]);
    await shot(page, '13-prompt4-typed');
    await clickSend(page);
    await page.waitForTimeout(2000);
    await shot(page, '14-prompt4-sent');

    console.log('  Waiting for PK response (up to 120s)...');
    await waitContentStable(page, 120000);
    await page.waitForTimeout(2000);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(1000);
    await shot(page, '15-prompt4-pk-response');

    // Click download button
    const downloadBtn = page.locator('button[aria-label="Save response as file"]').first();
    if (await downloadBtn.count() > 0) {
      await downloadBtn.click();
      await page.waitForTimeout(600);
      await shot(page, '16-download-dropdown');
      // Click .docx option
      const docxOpt = page.locator('text=/\.docx/i, text=/docx/i').first();
      if (await docxOpt.count() > 0) {
        await docxOpt.click();
        await page.waitForTimeout(500);
        console.log('  ✅ Download .docx clicked');
      }
      await page.keyboard.press('Escape');
    } else {
      // Try copy button as fallback
      const copyBtn = page.locator('button[aria-label*="Copy"]').first();
      if (await copyBtn.count() > 0) await copyBtn.click();
      console.log('  ℹ️  No download button found, used copy');
    }
    await page.waitForTimeout(500);
    await shot(page, '17-final-state');

    // ── Summary ──────────────────────────────────────────────────────────
    const responsePreview = await page.evaluate(() => {
      const proses = document.querySelectorAll('[class*="prose"]');
      return [...proses].map(p => p.textContent?.slice(0, 300)).join('\n---\n');
    });

    console.log('\n' + '='.repeat(60));
    console.log('✅ DEMO RECORDING COMPLETE');
    console.log(`📸 Screenshots: ${SS_DIR}`);
    console.log(`Console errors: ${errors.length === 0 ? 'none' : errors.slice(0, 3).join('; ')}`);
    console.log('\nResponse preview (last message):');
    console.log(responsePreview.slice(-400) || '(no prose found)');

  } catch (err) {
    console.error('❌ Recording failed:', err.message);
    await shot(page, 'ERROR-state').catch(() => {});
    throw err;
  } finally {
    const video = page.video();
    await ctx.close();
    if (video) {
      const vp = path.join(OUT_DIR, 'biomate_drug_dev_demo.webm');
      try { await video.saveAs(vp); console.log(`📹 Video: ${vp}`); } catch (e) { console.warn('Video save:', e.message); }
    }
    await browser.close();
  }
}

main().catch(err => { console.error(err); process.exit(1); });
