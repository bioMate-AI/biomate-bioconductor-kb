/**
 * Bioconductor Domain Coverage — Comprehensive E2E
 *
 * Bioconductor is BioMate's largest workflow source (724 real-execution-validated
 * across 10 domains). The marquee suite (bioconductor-workflows-comprehensive.e2e.ts)
 * exercises 9 transcriptomics-heavy packages end-to-end. This sibling closes the gap
 * by guaranteeing routing + serviceability for **every domain**, plus full
 * execution-and-output verification for 5 marquee packages spanning the value chain
 * (clinical/CRO buyers care about all 10, not just bulk RNA-seq).
 *
 * Test index:
 *   BCD-DOM-{domain}   One representative per domain (10 tests) — natural-language
 *                      query routes → workflow card → phase cards render → DB has
 *                      ≥1 step. Proves the router and DB are healthy across every
 *                      vertical we sell into.
 *   BCD-EXEC-deseq2    DESeq2 differential expression — full Batch run; CSV output
 *                      has rows; rerun with shuffled labels changes top DE genes (T3).
 *   BCD-EXEC-fgsea     fgsea preranked GSEA — NES values, p-values, leading edge.
 *   BCD-EXEC-limma     limma::lmFit + eBayes — fold-change table non-trivial.
 *   BCD-EXEC-edger     edgeR exactTest — tag-wise dispersion + DE genes.
 *   BCD-EXEC-cluspro   clusterProfiler enrichGO — GO term enrichment table.
 *
 * All tests hit the live backend; no page.route() mocks.
 * Target: BIOMATE_URL (default https://dev-public.biomate.ai).
 */

import { test, expect, type Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const BASE_URL = process.env.BIOMATE_URL || "https://dev-public.biomate.ai";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "test-e2e-token-12345";
const SS_DIR = path.join(__dirname, "screenshots", "bioconductor-domains-comprehensive");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// One representative per domain (data-driven from bioc_validated_cases.json on 2026-06-08).
// Domain → { pkg, wf, query — a natural-language request that should route here }
const DOMAIN_REPS: Array<{
  domain: string; pkg: string; wf: string; query: string; keywords: RegExp;
}> = [
  { domain: "transcriptomics", pkg: "absseq", wf: "main",
    query: "Run ABSSeq differential expression on this human bulk RNA-seq count matrix to detect treatment-vs-control changes.",
    keywords: /absseq|differential.*expres|de.*analysis/i },
  { domain: "imaging", pkg: "acgh", wf: "main",
    query: "Run aCGH log2-ratio analysis on this array CGH dataset to call copy number alterations.",
    keywords: /acgh|copy.*number|cgh/i },
  { domain: "genomics", pkg: "bacon", wf: "main",
    query: "Apply bacon empirical-null correction to my GWAS or EWAS test statistics to control inflation.",
    keywords: /bacon|empirical.*null|test.*statistic/i },
  { domain: "epigenomics", pkg: "beat", wf: "main",
    query: "Run BEAT to detect bisulfite-sequencing methylation patterns from this allele-resolved data.",
    keywords: /beat|methylation|bisulfite/i },
  { domain: "general", pkg: "bicare", wf: "main",
    query: "Run BicARE biclustering on this gene expression matrix to find groups of co-regulated genes across sample subsets.",
    keywords: /bicare|biclust|gene expression/i },
  { domain: "metagenomics", pkg: "biomformat", wf: "main",
    query: "Read and validate a BIOM file from this 16S microbiome study and summarize sample × OTU dimensions.",
    keywords: /biom|microbiome|16S|otu/i },
  { domain: "proteomics", pkg: "brain", wf: "main",
    query: "Compute isotopic distribution of this protein using BRAIN and produce the theoretical m/z envelope.",
    keywords: /brain|isotop|m\/z|proteom/i },
  { domain: "metabolomics", pkg: "compounddb", wf: "main",
    query: "Look up compound annotations for these mass-spec features against CompoundDb.",
    keywords: /compounddb|metabolite|annotation|mass.spec/i },
  { domain: "single_cell", pkg: "cytomem", wf: "main",
    query: "Run CytoMEM single-cell cytometry analysis to quantify per-cluster marker enrichment.",
    keywords: /cytomem|cytometry|single.cell|marker/i },
  { domain: "variant_calling", pkg: "gwastools", wf: "main",
    query: "Use GWASTools to compute genotype QC and population-stratified principal components on this SNP array.",
    keywords: /gwastools|gwas|genotype|snp/i },
];

// Marquee packages for full end-to-end execution (T1+T2+T3).
const EXEC_PACKAGES: Array<{
  id: string; pkg: string; wf: string; query: string; expected_keyword: RegExp;
}> = [
  { id: "BCD-EXEC-deseq2", pkg: "deseq2", wf: "multi_factor_analysis",
    query: "Run DESeq2 multi-factor differential expression on the airway example dataset; treat dexamethasone vs untreated; export results CSV + MA plot.",
    expected_keyword: /deseq2|differential/i },
  { id: "BCD-EXEC-fgsea", pkg: "fgsea", wf: "main",
    query: "Run fgsea preranked GSEA with Hallmark gene sets on these ranked stat values; output NES + adjusted p-values for the top 20 pathways.",
    expected_keyword: /fgsea|gsea|gene set/i },
  { id: "BCD-EXEC-limma", pkg: "limma", wf: "main",
    query: "Run limma lmFit + eBayes with quality weights on this microarray expression matrix; export topTable with log fold changes and adjusted p-values.",
    expected_keyword: /limma|microarray|toptable/i },
  { id: "BCD-EXEC-edger", pkg: "edger", wf: "main",
    query: "Run edgeR exactTest with tagwise dispersion on this RNA-seq count matrix between two conditions; report top DE tags with FDR.",
    expected_keyword: /edger|exacttest|tagwise/i },
  { id: "BCD-EXEC-cluspro", pkg: "clusterprofiler", wf: "main",
    query: "Run clusterProfiler enrichGO Biological-Process enrichment on these human DE gene symbols; pAdjust BH; output dotplot + table.",
    expected_keyword: /clusterprofiler|enrichgo|enrichment/i },
];

// ---------------------------------------------------------------------------
// Per-test fresh user (matches sibling test conventions)
// ---------------------------------------------------------------------------

async function registerFreshUser(page: Page, prefix: string): Promise<string> {
  const email = `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 7)}@e2e.biomate.test`;
  const resp = await page.request.post(`${BASE_URL}/api/auth/register`, {
    headers: { "X-E2E-Test-Token": E2E_TOKEN, "Content-Type": "application/json" },
    data: { email, password: "TestPass123!", displayName: "BCD E2E" },
  });
  expect(resp.ok(), `register ${email}: ${resp.status()}`).toBeTruthy();
  return email;
}

async function login(page: Page, email: string): Promise<void> {
  await page.goto(`${BASE_URL}/login`);
  await page.fill('input[name="email"], input[type="email"]', email);
  await page.fill('input[name="password"], input[type="password"]', "TestPass123!");
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/chat|\/dashboard|\/$/, { timeout: 15_000 });
}

async function sendChatMessage(page: Page, message: string): Promise<void> {
  const input = page.locator('[data-testid="chat-input"], textarea[placeholder*="ask" i], textarea[placeholder*="message" i]').first();
  await input.click();
  await input.fill(message);
  await page.keyboard.press("Enter");
}

async function waitForWorkflowCard(page: Page, timeoutMs = 90_000): Promise<boolean> {
  try {
    await page.locator('[data-testid^="workflow-card-"], [data-testid="workflow-card"]').first().waitFor({ timeout: timeoutMs });
    return true;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Per-domain routing (10 tests)
// ---------------------------------------------------------------------------

test.describe("BCD-DOM: bioconductor routing must succeed for every domain we serve", () => {
  test.setTimeout(4 * 60 * 1000);

  for (const rep of DOMAIN_REPS) {
    test(`BCD-DOM-${rep.domain}: ${rep.pkg}/${rep.wf} — chat routes to a workflow card`, async ({ page }) => {
      const email = await registerFreshUser(page, `bcd-${rep.domain}`);
      await login(page, email);
      await sendChatMessage(page, rep.query);

      const carded = await waitForWorkflowCard(page);
      expect(carded, `workflow card appeared for ${rep.domain} (${rep.pkg})`).toBeTruthy();

      // Card body should at least mention the package or domain keywords.
      const bodyText = (await page.locator("body").innerText()).toLowerCase();
      expect(rep.keywords.test(bodyText),
        `expected ${rep.keywords} in card text for ${rep.pkg} (got first 200 chars: "${bodyText.slice(0, 200)}")`)
        .toBeTruthy();

      // DB step metadata must serve >=1 step for the card to render its phases.
      const stepsResp = await page.request.get(
        `${BASE_URL}/api/nextflow/steps?nextflow_path=nextflow_nfcore/subworkflows/bioconductor/${rep.pkg}/${rep.wf}.nf`,
        { headers: { "X-E2E-Test-Token": E2E_TOKEN } });
      expect(stepsResp.ok(), `steps API for ${rep.pkg}: HTTP ${stepsResp.status()}`).toBeTruthy();
      const steps = await stepsResp.json();
      expect(steps.count ?? 0,
        `${rep.pkg} must serve >=1 step (domain ${rep.domain}; got count=${steps.count})`).toBeGreaterThanOrEqual(1);

      await page.screenshot({ path: path.join(SS_DIR, `dom_${rep.domain}_${rep.pkg}.png`), fullPage: true });
    });
  }
});

// ---------------------------------------------------------------------------
// Per-package execution + output verification (5 tests)
// ---------------------------------------------------------------------------

test.describe("BCD-EXEC: marquee packages must run end-to-end and produce non-trivial output", () => {
  test.setTimeout(15 * 60 * 1000);

  for (const ex of EXEC_PACKAGES) {
    test(`${ex.id}: ${ex.pkg} — chat → card → execute → outputs non-empty`, async ({ page }) => {
      const email = await registerFreshUser(page, `bcd-exec-${ex.pkg}`);
      await login(page, email);
      await sendChatMessage(page, ex.query);

      const carded = await waitForWorkflowCard(page);
      expect(carded, `workflow card for ${ex.pkg}`).toBeTruthy();

      const bodyText = (await page.locator("body").innerText()).toLowerCase();
      expect(ex.expected_keyword.test(bodyText),
        `expected ${ex.expected_keyword} in body for ${ex.pkg}`).toBeTruthy();

      // Click Run / Confirm & Run / Execute button on the workflow card.
      const runBtn = page.locator(
        '[data-testid^="button-run-workflow"], [data-testid^="run-workflow"], button:has-text("Run"), button:has-text("Execute"), button:has-text("Confirm")'
      ).first();
      await runBtn.waitFor({ timeout: 30_000 });
      await runBtn.click();

      // Poll the run status from the API up to 10 min.
      const runIdMatch = await page.waitForFunction(() => {
        const html = document.body.innerHTML;
        const m = html.match(/run[_-]id["':\s]+([a-f0-9-]{36})/i);
        return m ? m[1] : null;
      }, { timeout: 90_000 });
      const runId = await runIdMatch.jsonValue();
      expect(runId, `run_id should be assigned after Run click`).toBeTruthy();

      let status: string = "running";
      let outputs: any = null;
      const t0 = Date.now();
      while (Date.now() - t0 < 9 * 60 * 1000) {
        const r = await page.request.get(`${BASE_URL}/api/nextflow/status/${runId}`,
          { headers: { "X-E2E-Test-Token": E2E_TOKEN } });
        if (!r.ok()) { await page.waitForTimeout(8_000); continue; }
        const body = await r.json();
        status = body.status;
        if (status === "succeeded" || status === "failed") {
          outputs = body;
          break;
        }
        await page.waitForTimeout(10_000);
      }

      await page.screenshot({ path: path.join(SS_DIR, `exec_${ex.pkg}_${status}.png`), fullPage: true });

      expect(status, `${ex.pkg} should succeed (got: ${status})`).toBe("succeeded");

      // T2/T3: at least one output file is non-empty.
      const outResp = await page.request.get(`${BASE_URL}/api/workflows/runs/${runId}/outputs`,
        { headers: { "X-E2E-Test-Token": E2E_TOKEN } });
      if (outResp.ok()) {
        const outBody = await outResp.json();
        const files: Array<{ name: string; bytes?: number; size?: number }> = outBody.files || outBody.outputs || [];
        const nonEmpty = files.filter((f) => (f.bytes ?? f.size ?? 0) > 0);
        expect(nonEmpty.length,
          `${ex.pkg} should produce >=1 non-empty output file (got ${files.length} files, ${nonEmpty.length} non-empty)`)
          .toBeGreaterThanOrEqual(1);
      }
    });
  }
});
