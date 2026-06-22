/**
 * Tutorial Use Cases — Workflow Routing Audit
 *
 * Validates that each of the 7 tutorial domain scenarios routes to the
 * correct workflow on dev. No AWS Batch execution — routing-only checks.
 *
 * Scenarios (from Seven-Domain Tutorial Package):
 *   T1 — Bulk RNA-seq DE + GSEA
 *   T2 — scRNA-seq QC → cluster → annotate
 *   T3 — Germline variant calling (GIAB)
 *   T4 — ChIP-seq peaks → annotation → enrichment
 *   T5 — Proteomics LFQ (MSnBase + limma)
 *   T6 — Shotgun metagenomics → MAGs
 *   T7 — LC-MS metabolomics (xcms + biosigner)
 *
 * E2E plan discipline (CLAUDE.md):
 *   - Login ONCE via beforeAll
 *   - New Chat per scenario (not new browser session)
 *   - 90 s timeout per LLM call
 *   - Soft assertions — all 7 cases always run; failures logged, not thrown
 *   - No /api/auth/register — fixture already registered
 */

import { test, expect, Page, Browser } from '@playwright/test';
import {
  sendAndWait,
  shot,
  pause,
  BASE_URL,
} from './demo-helpers.js';

// ── Constants ──────────────────────────────────────────────────────────────────

const FIXTURE_EMAIL    = 'lifeifei163361@163.com';
const FIXTURE_PASSWORD = process.env.E2E_FIXTURE_PASSWORD || 'WpmFixture!2026';
const E2E_TOKEN        = process.env.E2E_TEST_TOKEN ?? 'biomate-e2e-bypass-token-dev-only';

interface TutorialCase {
  id: string;
  domain: string;
  prompt: string;
  /** Substring(s) expected in the workflow card title — any match passes */
  expectWorkflow: string[];
}

const TUTORIAL_CASES: TutorialCase[] = [
  {
    id: 'T1',
    domain: 'transcriptomics',
    prompt: 'Run nf-core rnaseq then differential expression and GSEA',
    expectWorkflow: ['rnaseq', 'RNA', 'differential', 'DESeq2', 'expression'],
  },
  {
    id: 'T2',
    domain: 'single_cell',
    prompt: 'Run single-cell RNA-seq QC, clustering and annotation from Cell Ranger output',
    expectWorkflow: ['single.cell', 'scRNA', 'Seurat', 'Cell Ranger', 'harmony', 'scrna'],
  },
  {
    id: 'T3',
    domain: 'variant_calling',
    prompt: 'Germline variant calling annotation and filtering on this WGS sample',
    expectWorkflow: ['variant', 'sarek', 'GATK', 'calling', 'annotation'],
  },
  {
    id: 'T4',
    domain: 'epigenomics',
    prompt: 'Annotate my ChIP-seq peaks and run pathway enrichment',
    expectWorkflow: ['ChIP', 'chipseq', 'peak', 'ChIPseeker', 'enrichment'],
  },
  {
    id: 'T5',
    domain: 'proteomics',
    prompt: 'Bioconductor MSnBase proteomics pipeline — DDA label-free protein differential expression with limma',
    expectWorkflow: ['proteomics', 'MSnBase', 'limma', 'label.free', 'protein'],
  },
  {
    id: 'T6',
    domain: 'metagenomics',
    prompt: 'MAG recovery with binning and taxonomy assignment',
    expectWorkflow: ['MAG', 'metagenom', 'binning', 'CONCOCT', 'taxonomy'],
  },
  {
    id: 'T7',
    domain: 'metabolomics',
    prompt: 'Untargeted metabolomics multi-method analysis',
    expectWorkflow: ['metabolomics', 'xcms', 'biosigner', 'CAMERA', 'metabol'],
  },
];

// ── Helpers ────────────────────────────────────────────────────────────────────

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
      if (!resp.ok) throw new Error(`Login ${resp.status}`);
      const d = await resp.json();
      return d.token as string;
    },
    { baseUrl: BASE_URL, email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD, e2eToken: E2E_TOKEN }
  );
  const domain = new URL(BASE_URL).hostname;
  await page.context().addCookies([{
    name: 'biomate_token', value: token,
    domain, path: '/', httpOnly: true,
    secure: BASE_URL.startsWith('https'), sameSite: 'Lax',
  }]);
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.evaluate(() => {
    try { localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 86400_000)); } catch {}
  });
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 30_000 });
}

async function startNewChat(page: Page): Promise<void> {
  // Navigate to root — always gives a clean chat regardless of sidebar/panel state
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 20_000 });
  await pause(page, 500);
}

/**
 * Returns the workflow title from the compact wf-chip card shown in chat
 * when the workflow panel is open. Falls back to the workflow anchor card name.
 * `.wf-chip-name` holds the workflow display name (e.g. "nf-core/rnaseq").
 */
async function getWorkflowTitle(page: Page, timeoutMs = 90_000): Promise<string | null> {
  // Primary: compact chip shown when workflow is in the right panel
  const chipName = page.locator('.wf-chip-name').first();
  const chipVisible = await chipName.isVisible({ timeout: timeoutMs }).catch(() => false);
  if (chipVisible) {
    return chipName.textContent().catch(() => null);
  }
  // Fallback: workflow anchor card title (when panel is not open)
  const anchor = page.locator('[data-testid^="workflow-artifact-anchor-"]').first();
  const anchorVisible = await anchor.isVisible({ timeout: 3_000 }).catch(() => false);
  if (anchorVisible) {
    // Title is inside the NextflowWorkflowViewer header
    const nameEl = anchor.locator('h2, h3, [class*="workflow-name"], [class*="wf-name"]').first();
    return nameEl.textContent().catch(() => anchor.textContent().catch(() => null));
  }
  return null;
}

// ── Shared session ─────────────────────────────────────────────────────────────

let sharedBrowser: Browser;
let sharedPage: Page;

test.beforeAll(async ({ browser }) => {
  sharedBrowser = browser;
  sharedPage = await browser.newPage();
  await login(sharedPage);
});

test.afterAll(async () => {
  await sharedPage.close().catch(() => {});
});

// ── Test ───────────────────────────────────────────────────────────────────────

test('Tutorial workflow routing — all 7 domain scenarios', async () => {
  test.setTimeout(900_000); // 15 min total (7 × ~90 s LLM + overhead)

  const results: {
    id: string; domain: string; workflowTitle: string | null; pass: boolean; reason: string;
  }[] = [];

  for (const tc of TUTORIAL_CASES) {
    console.log(`\n[${tc.id}] ${tc.domain} — sending: "${tc.prompt}"`);

    await startNewChat(sharedPage);

    // Send query; sendAndWait waits for AI to finish + checks for Run button
    await sendAndWait(sharedPage, tc.prompt, 90_000);

    // Check for wf-chip
    const title = await getWorkflowTitle(sharedPage, 8_000);
    const chipVisible = title !== null;

    // When chip title is "Workflow" (empty-name fallback for generated workflows),
    // also check the AI message text for routing keywords (e.g. "seurat_qc_clustering").
    let effectiveTitle = title ?? '';
    if (title === 'Workflow') {
      const msgText = await sharedPage
        .locator('[data-is-latest-assistant="true"]').first()
        .textContent().catch(() => '');
      if (msgText && msgText.trim().length > 10) effectiveTitle = msgText;
    }

    // Check title/message matches expected keywords (case-insensitive)
    const titleLower = effectiveTitle.toLowerCase();
    const matched = tc.expectWorkflow.some(kw => titleLower.includes(kw.toLowerCase()));

    const pass = chipVisible && matched;
    const reason = !chipVisible
      ? 'NO wf-chip (text-only response)'
      : !matched
        ? `chip="${title}" — no keyword match in [${tc.expectWorkflow.join(', ')}]`
        : title === 'Workflow' ? 'OK (name fallback — keyword matched in AI message text)' : 'OK';

    console.log(`[${tc.id}] ${pass ? '✅' : '❌'} workflow="${title ?? 'none'}" → ${reason}`);

    // Screenshot regardless of pass/fail
    await shot(sharedPage, 'tutorial-cases', `${tc.id}_${tc.domain}`);

    // Also grab the panel if it's open
    const panelVisible = await sharedPage
      .locator('[data-testid="nextflow-workflow-viewer"]')
      .isVisible({ timeout: 2_000 }).catch(() => false);
    if (panelVisible) {
      await shot(sharedPage, 'tutorial-cases', `${tc.id}_${tc.domain}_panel`);
    }

    results.push({ id: tc.id, domain: tc.domain, workflowTitle: title, pass, reason });

    await pause(sharedPage, 1_000);
  }

  // Summary
  console.log('\n══════════════════════════════════════════');
  console.log('Tutorial Routing Audit Summary');
  console.log('══════════════════════════════════════════');
  let passed = 0;
  for (const r of results) {
    const mark = r.pass ? '✅' : '❌';
    console.log(`  ${mark} ${r.id} (${r.domain}): ${r.workflowTitle ?? 'no card'} — ${r.reason}`);
    if (r.pass) passed++;
  }
  console.log(`\nResult: ${passed}/${results.length} scenarios routed correctly`);
  console.log('══════════════════════════════════════════');

  // Hard-fail only if fewer than 4/7 routed (majority fail = systemic issue)
  const MINIMUM_PASS = 4;
  expect(passed, `Only ${passed}/${results.length} tutorials routed correctly (need ≥ ${MINIMUM_PASS})`).toBeGreaterThanOrEqual(MINIMUM_PASS);
});
