/**
 * Service Page — 21 "Try it →" Use Cases — Workflow Routing Audit
 *
 * Validates that each of the 21 service-page queries routes to the
 * expected workflow on dev. Routing-only: no AWS Batch execution.
 *
 * Use cases mirror the 21 "Try it →" cards on the BioMate services page
 * and are documented in full detail (inputs, expected panel behavior,
 * step outputs, after-run tabs, downloaded report content) in:
 *   docs/20260701_TESTER_GUIDE_21_USE_CASES.md
 *
 * Test IDs match the tester guide sections:
 *   Q01–Q04  Section 1: Drug Discovery
 *   Q05–Q10  Section 2: Clinical Research
 *   Q11–Q17  Section 3: Genomics & Multi-Omics
 *   Q18–Q21  Section 4: Structural Biology
 *
 * E2E plan discipline (CLAUDE.md):
 *   - Login ONCE via beforeAll; token reused for all 21 cases
 *   - New Chat per query via page.goto(BASE_URL)
 *   - 90 s timeout per LLM call (chains can take ~45 s for LLM arbitration)
 *   - Soft assertions — all 21 cases run; failures logged, test still passes
 *     unless fewer than 15/21 route correctly (systemic threshold)
 *   - NEVER call /api/auth/register — fixture already registered
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

interface ServiceCase {
  id: string;
  section: string;
  label: string;
  prompt: string;
  /**
   * Workflow name substrings (case-insensitive) OR chain names that pass.
   * First match wins. Chain result: workflow_type==="chain" passes if
   * any keyword matches chain_name or chain_display_name.
   */
  expectWorkflow: string[];
  /** If true, both 'chain' and 'nextflow' workflow_type are acceptable */
  acceptChain?: boolean;
}

const SERVICE_CASES: ServiceCase[] = [
  // ── Section 1: Drug Discovery ─────────────────────────────────────────────
  {
    id: 'Q01',
    section: '1.1',
    label: 'Target Discovery',
    prompt: 'Run target tractability and prioritization analysis for Parkinson\'s disease — rank therapeutic targets by GWAS genetic support, DepMap CRISPR essentiality, GTEx brain tissue expression, and pocket druggability scoring',
    expectWorkflow: ['target', 'tractability', 'druggability', 'essentiality', 'genetic', 'prioritization'],
    acceptChain: true,
  },
  {
    id: 'Q02',
    section: '1.2',
    label: 'Virtual Screening',
    prompt: 'Screen a compound library against target protein PDB:1HSG (HIV protease) using AutoDock Vina and DiffDock — score, rank, and cluster hits against the active site',
    expectWorkflow: ['autodock', 'vina', 'diffdock', 'docking', 'virtual', 'screening', 'structure'],
    acceptChain: true,
  },
  {
    id: 'Q03',
    section: '1.3',
    label: 'ADMET Full Panel',
    prompt: 'Run a full ADMET panel for a small molecule drug candidate — hERG cardiotoxicity, DILI, Ames mutagenicity, CYP450 drug-drug interactions, and Lipinski Ro5 compliance',
    expectWorkflow: ['admet', 'herg', 'dili', 'ames', 'cyp450', 'lipinski', 'cardiotoxicity'],
    acceptChain: true,
  },
  {
    id: 'Q04',
    section: '1.4',
    label: 'PBPK / Allometric Scaling',
    prompt: 'Run PBPK simulation for a drug candidate and scale the dose from mouse to human using allometric scaling',
    expectWorkflow: ['pbpk', 'allometric', 'pharmacokinetic', 'dose', 'scaling'],
    acceptChain: true,
  },
  // ── Section 2: Clinical Research ──────────────────────────────────────────
  {
    id: 'Q05',
    section: '2.1',
    label: 'Pop PK / DDI',
    prompt: 'Run population pharmacokinetics analysis using nlmixr2 — fit a two-compartment model to 200 patient observations, estimate CL/V, simulate dose-escalation to find the MTD, and assess CYP3A4 drug-drug interaction risk',
    expectWorkflow: ['nlmixr', 'population', 'pk', 'pharmacokinetic', 'compartment', 'dose', 'ddi', 'clinical'],
    acceptChain: true,
  },
  {
    id: 'Q06',
    section: '2.2',
    label: 'Pharmacovigilance (FAERS)',
    prompt: 'Analyze FAERS adverse event data for a drug — run ROR and PRR disproportionality scoring',
    expectWorkflow: ['faers', 'pharmacovigilance', 'ror', 'prr', 'disproportionality', 'adverse'],
    acceptChain: false,
  },
  {
    id: 'Q07',
    section: '2.3',
    label: 'BOIN Dose Escalation',
    prompt: 'Design a Phase I oncology dose-escalation trial using the BOIN model for lung cancer — 5 dose levels (50, 100, 200, 400, 800 mg), target DLT rate 25%, cohort size 3, identify the MTD and recommend the Phase II dose',
    expectWorkflow: ['boin', 'dose', 'escalation', 'mtd', 'phase', 'oncology', 'clinical', 'trial', 'dlt'],
    acceptChain: true,
  },
  {
    id: 'Q08',
    section: '2.4',
    label: 'Pharmacogenomics CYP typing',
    prompt: 'Run CYP2D6 and CYP2C19 pharmacogenomics star-allele genotyping from a WGS VCF file — classify each patient as poor/intermediate/extensive/ultrarapid metabolizer using PharmVar database and CPIC guidelines',
    expectWorkflow: ['cyp2d6', 'cyp2c19', 'pharmacogenomics', 'genotyping', 'metabolizer', 'phenotype', 'star', 'cpic', 'pharmvar'],
    acceptChain: true,
  },
  {
    id: 'Q09',
    section: '2.5',
    label: 'Clinical Somatic Variant Calling',
    prompt: 'Run clinical somatic variant calling on a tumor sample with GATK4 — annotate against ClinVar and ACMG criteria',
    expectWorkflow: ['sarek', 'gatk', 'somatic', 'variant', 'clinvar', 'acmg'],
    acceptChain: false,
  },
  {
    id: 'Q10',
    section: '2.6',
    label: 'Survival Analysis / RWE',
    prompt: 'Run survival analysis on a retrospective cancer cohort — Kaplan-Meier curves, Cox proportional hazards model, biomarker discovery',
    expectWorkflow: ['survival', 'kaplan', 'cox', 'hazard', 'biomarker', 'cohort'],
    acceptChain: true,
  },
  // ── Section 3: Genomics & Multi-Omics ────────────────────────────────────
  {
    id: 'Q11',
    section: '3.1',
    label: 'WGS Germline Variant Calling',
    prompt: 'Run whole-genome sequencing variant calling using nf-core/sarek with GATK HaplotypeCaller — generate VCF and annotate with VEP',
    expectWorkflow: ['sarek', 'variant', 'gatk', 'haplotypecaller', 'vep', 'wgs'],
    acceptChain: false,
  },
  {
    id: 'Q12',
    section: '3.2',
    label: 'Bulk RNA-seq DESeq2',
    prompt: 'Run bulk RNA-seq differential expression analysis comparing treated vs control samples with DESeq2',
    expectWorkflow: ['bulk_rnaseq_de', 'deseq2', 'differential', 'expression', 'rna.seq', 'rnaseq'],
    acceptChain: true,
  },
  {
    id: 'Q13',
    section: '3.3',
    label: 'ATAC-seq Chromatin',
    prompt: 'Run ATAC-seq chromatin accessibility analysis using nf-core/atacseq — call peaks with MACS3',
    expectWorkflow: ['atacseq', 'atac', 'chromatin', 'macs', 'peak', 'accessibility'],
    acceptChain: false,
  },
  {
    id: 'Q14',
    section: '3.4',
    label: 'Proteomics DIA-NN',
    prompt: 'Run label-free proteomics DIA quantification with DIA-NN from mzML files',
    expectWorkflow: ['diann', 'dia.nn', 'proteomics', 'dia', 'label.free', 'quantification'],
    acceptChain: true,
  },
  {
    id: 'Q15',
    section: '3.5',
    label: 'Metabolomics XCMS',
    prompt: 'Run untargeted LC-MS metabolomics with XCMS — peak detection, alignment, annotation',
    expectWorkflow: ['xcms', 'metabolomics', 'lc.ms', 'peak', 'untargeted', 'metabol'],
    acceptChain: true,
  },
  {
    id: 'Q16',
    section: '3.6',
    label: 'Metagenomics Kraken2',
    prompt: 'Run shotgun metagenomics taxonomic profiling with Kraken2 and MetaPhlAn4',
    expectWorkflow: ['kraken', 'metaphlan', 'metagenom', 'taxonomic', 'profiling', 'shotgun'],
    acceptChain: true,
  },
  {
    id: 'Q17',
    section: '3.7',
    label: 'Multi-Omics MOFA+',
    prompt: 'Integrate RNA-seq, proteomics, and metabolomics datasets using MOFA+',
    expectWorkflow: ['mofa', 'multi.omics', 'multiomics', 'integration', 'rna', 'proteomics'],
    acceptChain: true,
  },
  // ── Section 4: Structural Biology ─────────────────────────────────────────
  {
    id: 'Q18',
    section: '4.1',
    label: 'Cryo-EM SPA CryoSPARC',
    prompt: 'Run CryoSPARC single particle analysis on cryo-EM micrographs — motion correction, CTF estimation, particle picking, 2D/3D classification, refinement',
    expectWorkflow: ['cryosparc', 'cryo.em', 'cryoem', 'single.particle', 'spa', 'micrograph'],
    acceptChain: false,
  },
  {
    id: 'Q19',
    section: '4.2',
    label: 'AlphaFold3 Structure Prediction',
    prompt: 'Predict the 3D structure of a protein sequence using AlphaFold3 — validate the model with MolProbity and identify binding sites',
    expectWorkflow: ['alphafold', 'alphafold3', 'structure', 'protein', 'molprobity', 'binding'],
    acceptChain: true,
  },
  {
    id: 'Q20',
    section: '4.3',
    label: 'GPU MD Simulation',
    prompt: 'Run GPU-accelerated GROMACS molecular dynamics for a protein-ligand complex — equilibration, production MD, trajectory analysis',
    expectWorkflow: ['gromacs', 'amber', 'molecular.dynamics', 'md', 'gpu', 'protein.ligand'],
    acceptChain: false,
  },
  {
    id: 'Q21',
    section: '4.4',
    label: 'AutoDock Vina Docking',
    prompt: 'Dock a small molecule ligand into a target protein using AutoDock Vina — score the top poses and visualize',
    expectWorkflow: ['autodock', 'vina', 'docking', 'ligand', 'dock', 'pose'],
    acceptChain: true,
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
  // Suppress onboarding survey so it doesn't block the chat input
  await page.evaluate(() => {
    try { localStorage.setItem('biomate_survey_suppressed_until', String(Date.now() + 7 * 86400_000)); } catch {}
  });
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 30_000 });
}

async function startNewChat(page: Page): Promise<void> {
  await page.goto(BASE_URL);
  await page.waitForLoadState('load');
  await page.locator('[data-testid="chat-input"], textarea').first()
    .waitFor({ state: 'visible', timeout: 20_000 });
  await pause(page, 400);
}

/**
 * Returns the workflow/chain title shown in the chat after the AI responds.
 *
 * Priority:
 *  1. `.wf-chip-name` — compact chip shown when workflow panel is open
 *  2. `[data-testid^="workflow-artifact-anchor-"]` h2/h3 — workflow anchor card
 *  3. `[data-workflow-type="chain"]` — chain card name
 */
async function getResultTitle(page: Page, timeoutMs = 90_000): Promise<{
  title: string | null;
  type: 'chain' | 'workflow' | null;
}> {
  // 1. wf-chip (workflow panel opened)
  const chip = page.locator('.wf-chip-name').first();
  const chipOk = await chip.isVisible({ timeout: timeoutMs }).catch(() => false);
  if (chipOk) {
    return { title: await chip.textContent().catch(() => null), type: 'workflow' };
  }
  // 2. Chain card — has data-workflow-type="chain" or contains chain display name
  const chainCard = page.locator('[data-workflow-type="chain"], [class*="chain-card"]').first();
  const chainOk = await chainCard.isVisible({ timeout: 3_000 }).catch(() => false);
  if (chainOk) {
    const chainTitle = await chainCard.locator('h2, h3, [class*="title"], [class*="name"]')
      .first().textContent().catch(() => null)
      ?? await chainCard.textContent().catch(() => null);
    return { title: chainTitle, type: 'chain' };
  }
  // 3. Workflow anchor card
  const anchor = page.locator('[data-testid^="workflow-artifact-anchor-"]').first();
  const anchorOk = await anchor.isVisible({ timeout: 3_000 }).catch(() => false);
  if (anchorOk) {
    const nameEl = anchor.locator('h2, h3, [class*="workflow-name"], [class*="wf-name"]').first();
    return {
      title: await nameEl.textContent().catch(() => anchor.textContent().catch(() => null)),
      type: 'workflow',
    };
  }
  return { title: null, type: null };
}

// ── Shared session ─────────────────────────────────────────────────────────────

let sharedPage: Page;

test.beforeAll(async ({ browser }) => {
  sharedPage = await browser.newPage();
  await login(sharedPage);
});

test.afterAll(async () => {
  await sharedPage.close().catch(() => {});
});

// ── Main test ──────────────────────────────────────────────────────────────────

test('Service page — 21 use case workflow routing', async () => {
  // 21 cases × ~90 s LLM + overhead; give generous headroom
  test.setTimeout(21 * 120_000);

  const results: {
    id: string;
    section: string;
    label: string;
    title: string | null;
    resultType: 'chain' | 'workflow' | null;
    pass: boolean;
    reason: string;
  }[] = [];

  for (const tc of SERVICE_CASES) {
    console.log(`\n[${tc.id}] §${tc.section} ${tc.label}`);
    console.log(`     → "${tc.prompt.slice(0, 80)}…"`);

    await startNewChat(sharedPage);

    let { title, type: resultType } = { title: null as string | null, type: null as ('chain' | 'workflow' | null) };
    let timedOut = false;

    try {
      await sendAndWait(sharedPage, tc.prompt, 90_000);
      ({ title, type: resultType } = await getResultTitle(sharedPage, 10_000));
    } catch (err) {
      timedOut = true;
      console.log(`[${tc.id}] ⏱ Timed out waiting for response`);
    }

    // Evaluate pass condition
    const chipPresent = title !== null && !timedOut;
    const titleLower = (title ?? '').toLowerCase();

    // Also check AI message text for keyword matches (handles generated-workflow fallback)
    let msgText = '';
    if (title === 'Workflow' || !chipPresent) {
      msgText = await sharedPage
        .locator('[data-is-latest-assistant="true"]').first()
        .textContent().catch(() => '') ?? '';
    }
    const searchText = (titleLower + ' ' + msgText).toLowerCase();

    const keywordMatched = tc.expectWorkflow.some(kw =>
      searchText.includes(kw.replace('.', ' ').toLowerCase()) ||
      searchText.includes(kw.replace('.', '-').toLowerCase())
    );

    // Chain acceptance: chain type is fine if acceptChain=true
    const typeOk = !resultType
      || resultType === 'workflow'
      || (resultType === 'chain' && tc.acceptChain !== false);

    const pass = chipPresent && keywordMatched && typeOk;

    let reason: string;
    if (timedOut) {
      reason = 'TIMEOUT — no response in 90 s';
    } else if (!chipPresent) {
      reason = 'NO CARD — text-only response (no workflow/chain card appeared)';
    } else if (!typeOk) {
      reason = `WRONG TYPE — got "${resultType}" but only "workflow" accepted`;
    } else if (!keywordMatched) {
      reason = `WRONG WORKFLOW — card="${title}" — no keyword in [${tc.expectWorkflow.slice(0, 4).join(', ')}]`;
    } else {
      reason = title === 'Workflow'
        ? 'OK (keyword matched in AI message text, not card title)'
        : `OK — "${title}"`;
    }

    console.log(`[${tc.id}] ${pass ? '✅' : '❌'} ${reason}`);

    await shot(sharedPage, 'service-21-cases', `${tc.id}_${tc.section.replace('.', '-')}_${tc.label.replace(/\s+/g, '_')}`);

    const panelVisible = await sharedPage
      .locator('[data-testid="nextflow-workflow-viewer"]')
      .isVisible({ timeout: 2_000 }).catch(() => false);
    if (panelVisible) {
      await shot(sharedPage, 'service-21-cases', `${tc.id}_panel`);
    }

    results.push({ id: tc.id, section: tc.section, label: tc.label, title, resultType, pass, reason });

    await pause(sharedPage, 800);
  }

  // ── Summary ──────────────────────────────────────────────────────────────
  console.log('\n══════════════════════════════════════════════════════════');
  console.log('Service Page — 21 Use Case Routing Audit Summary');
  console.log('══════════════════════════════════════════════════════════');
  let passed = 0;
  for (const r of results) {
    const mark = r.pass ? '✅' : '❌';
    const typeTag = r.resultType ? ` [${r.resultType}]` : '';
    console.log(`  ${mark} ${r.id} §${r.section} ${r.label}: "${r.title ?? 'none'}"${typeTag}`);
    if (!r.pass) console.log(`       ${r.reason}`);
    if (r.pass) passed++;
  }
  console.log(`\nResult: ${passed}/${results.length} use cases routed correctly`);
  console.log('══════════════════════════════════════════════════════════');

  // Hard-fail only if fewer than 15/21 pass — partial failure is acceptable
  // during rollout, systemic regression needs 6+ failures to trigger.
  const MINIMUM_PASS = 15;
  expect(
    passed,
    `Only ${passed}/${results.length} service-page use cases routed correctly (need ≥ ${MINIMUM_PASS})`
  ).toBeGreaterThanOrEqual(MINIMUM_PASS);
});
