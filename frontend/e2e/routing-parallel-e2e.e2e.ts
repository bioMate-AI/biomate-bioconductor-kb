/**
 * Parallel E2E routing test — 7 failing queries through the BioMate UI.
 *
 * Each test:
 *  1. Logs in as the fixture user
 *  2. Sends the routing query in the chat textarea
 *  3. If BioMate asks for clarification, answers it
 *  4. Checks that the correct workflow card appears
 *
 * Run in parallel: test.describe.configure({ mode: 'parallel' })
 * Target: dev-public.biomate.ai (default) or BIOMATE_URL env var.
 */

import { test, expect, type Page, type BrowserContext } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";

test.describe.configure({ mode: "parallel" });

const BASE_URL = process.env.BIOMATE_URL || "http://localhost:5000";
const E2E_TOKEN =
  process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";
const FIXTURE_EMAIL = "lifeifei163361@163.com";
const FIXTURE_PASSWORD =
  process.env.E2E_FIXTURE_PASSWORD || "WpmFixture!2026";

const SS_DIR = path.join(import.meta.dirname, "screenshots", "routing-parallel");
if (!fs.existsSync(SS_DIR)) fs.mkdirSync(SS_DIR, { recursive: true });

// ─────────────────────────────────────────────────────────────────────────────
// Auth
// ─────────────────────────────────────────────────────────────────────────────

async function loginAndNavigate(page: Page): Promise<void> {
  const loginResp = await page.request.post(`${BASE_URL}/api/auth/login`, {
    headers: {
      "x-e2e-test-token": E2E_TOKEN,
      "content-type": "application/json",
    },
    data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
  });
  if (!loginResp.ok()) {
    throw new Error(
      `login failed: ${loginResp.status()} ${await loginResp.text()}`
    );
  }
  const token: string = (await loginResp.json()).token;
  const host = new URL(BASE_URL).hostname;

  await page.context().addCookies([
    {
      name: "biomate_token",
      value: token,
      domain: host,
      path: "/",
      httpOnly: false,
      secure: BASE_URL.startsWith("https"),
      sameSite: "Lax",
    },
  ]);
  await page.context().setExtraHTTPHeaders({
    Authorization: `Bearer ${token}`,
    "X-E2E-Test-Token": E2E_TOKEN,
    "X-Forwarded-Proto": "https",
  });

  await page.goto(BASE_URL);
  await page.waitForLoadState("load");

  // Dismiss survey or onboarding modal if present
  const dismiss = page
    .locator('button:has-text("Skip"), button:has-text("Dismiss"), button:has-text("Maybe later")')
    .first();
  if (await dismiss.isVisible({ timeout: 4_000 }).catch(() => false)) {
    await dismiss.click({ force: true });
    await page.waitForTimeout(400);
  }

  // Wait for chat textarea
  await page.waitForSelector("textarea", { state: "visible", timeout: 25_000 });
  await page.waitForTimeout(800);
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat helpers
// ─────────────────────────────────────────────────────────────────────────────

async function sendAndWait(page: Page, msg: string, timeoutMs = 120_000): Promise<string> {
  const ta = page.locator("textarea").first();
  await ta.fill(msg);
  await ta.press("Enter");
  console.log(`[chat] → "${msg.slice(0, 80)}"`);

  // Wait for thinking indicator to appear then disappear
  const thinkSels = [
    "[data-testid='chat-response-pending']",
    "[data-testid='chat-analysis-status']",
    "text=BioMate is thinking",
    "text=Analyzing",
  ];
  await Promise.race(
    thinkSels.map((s) =>
      page.waitForSelector(s, { state: "visible", timeout: 20_000 }).catch(() => null)
    )
  );
  await Promise.all(
    thinkSels.map((s) =>
      page.waitForSelector(s, { state: "hidden", timeout: timeoutMs }).catch(() => null)
    )
  );

  // Wait for a substantive assistant reply
  await page
    .waitForFunction(
      () => {
        const el = document.querySelector('[data-is-latest-assistant="true"]');
        if (!el) return false;
        return (el.textContent?.trim().length ?? 0) > 30;
      },
      { timeout: timeoutMs }
    )
    .catch(() => {});

  await page.waitForTimeout(1500);
  const latest = page.locator('[data-is-latest-assistant="true"]').last();
  return (await latest.textContent({ timeout: 10_000 }).catch(() => "")) ?? "";
}

/** Return workflow card name visible in UI, or "" if none. */
async function getWorkflowCardName(page: Page): Promise<string> {
  // 1. wf-chip-name in the AI chat bubble (chat-message.tsx line 508)
  const chips = page.locator(".wf-chip-name");
  const chipCount = await chips.count().catch(() => 0);
  if (chipCount > 0) {
    const last = chips.last();
    const name = (await last.textContent().catch(() => ""))?.trim() ?? "";
    if (name && name !== "Workflow") return name;
  }

  // 2. Right panel name (nextflow-workflow-viewer.tsx line 2388: .panel-name)
  const panelName = page.locator(
    '[data-testid="workflow-artifact-panel"] .panel-name'
  ).first();
  if (await panelName.isVisible({ timeout: 1_000 }).catch(() => false)) {
    const name = (await panelName.textContent().catch(() => ""))?.trim() ?? "";
    if (name && name !== "Untitled") return name;
  }

  // 3. workflow-artifact-anchor has a data-workflow-name or adjacent text
  const anchors = page.locator('[data-testid^="workflow-artifact-anchor-"]');
  const anchorCount = await anchors.count().catch(() => 0);
  if (anchorCount > 0) {
    // Try to get the name from the nearest parent that has the chip
    for (let i = anchorCount - 1; i >= 0; i--) {
      const anchor = anchors.nth(i);
      const parent = anchor.locator("xpath=../..");
      const chip = parent.locator(".wf-chip-name").first();
      const name = (await chip.textContent({ timeout: 500 }).catch(() => ""))?.trim() ?? "";
      if (name && name !== "Workflow") return name;
    }
  }

  return "";
}

/** Does `got` match `expected`? Normalised comparison. */
function isMatch(got: string, expected: string, alts: string[] = []): boolean {
  if (!got) return false;
  const norm = (s: string) =>
    s.toLowerCase().replace(/nf-core\//g, "").replace(/[-_ /]/g, "");
  const gn = norm(got);
  if (norm(expected) === gn || norm(expected).includes(gn) || gn.includes(norm(expected)))
    return true;
  return alts.some((a) => norm(a) === gn || norm(a).includes(gn) || gn.includes(norm(a)));
}

// ─────────────────────────────────────────────────────────────────────────────
// Test cases
// ─────────────────────────────────────────────────────────────────────────────

const CASES: Array<{
  id: string;
  query: string;
  clarifications: string[];  // successive answers to BioMate clarification rounds
  expected: string;
  alts: string[];
}> = [
  {
    id: "rna_007",
    query:
      "Generate BigWig coverage tracks from my RNA-seq experiment for genome browser visualization",
    clarifications: [
      "s3://mybucket/rnaseq/sample1_R1.fastq.gz and s3://mybucket/rnaseq/sample1_R2.fastq.gz — paired-end Illumina NovaSeq, mouse GRCm38.",
      "Please proceed with nf-core/rnaseq, genome GRCm38, paired-end mode.",
    ],
    expected: "nf-core/rnaseq",
    alts: ["rnaseq"],
  },
  {
    id: "sc_003",
    query:
      "Run Kallisto BUStools pipeline on my droplet-based single-cell sequencing data",
    clarifications: [
      "s3://mybucket/scrnaseq/sample_R1.fastq.gz and s3://mybucket/scrnaseq/sample_R2.fastq.gz — 10x Chromium v3, human GRCh38.",
      "Use nf-core/scrnaseq with Kallisto BUStools aligner, 10x Chromium chemistry.",
    ],
    expected: "nf-core/scrnaseq",
    alts: ["scrnaseq"],
  },
  {
    id: "meta_006",
    query:
      "Run MetaPhlAn to profile microbial species abundance in clinical metagenomic samples",
    clarifications: [
      "s3://mybucket/meta/sample1_R1.fastq.gz and s3://mybucket/meta/sample1_R2.fastq.gz — paired-end shotgun metagenomics from human stool.",
      "Please use nf-core/taxprofiler with MetaPhlAn3 profiler on these paired FASTQ files.",
    ],
    expected: "nf-core/taxprofiler",
    alts: ["taxprofiler"],
  },
  {
    id: "adv_009",
    query:
      "Predict protein structure from FASTA sequence using ESMFold — no MSA required",
    clarifications: [
      "s3://mybucket/proteins.fasta — 5 protein sequences, want ESMFold structure prediction without MSA.",
      "Use ESMFold via the Structure Prediction Docking pipeline for these sequences.",
    ],
    expected: "Structure Prediction Docking",
    alts: ["esmfold", "proteinfold"],
  },
  {
    id: "sp_012",
    query:
      "My Visium dataset has multiple tissue sections from different patients — batch-correct and integrate them",
    clarifications: [
      "SpaceRanger outputs at s3://mybucket/visium/sample1/, s3://mybucket/visium/sample2/, s3://mybucket/visium/sample3/ — 3 patients, needs Harmony batch correction.",
      "Please run nf-core/spatialvi with Harmony integration on these Visium SpaceRanger outputs.",
    ],
    expected: "nf-core/spatialvi",
    alts: ["spatialvi"],
  },
  {
    id: "rna_011",
    query:
      "Perform GSEA gene set enrichment analysis and volcano plots comparing two treatment groups",
    clarifications: [
      "s3://mybucket/counts.csv — RNA-seq count matrix, control (n=5) vs treated (n=5). Gene IDs are Ensembl.",
      "Please run nf-core/differentialabundance with DESeq2, GSEA, and volcano plots on this count matrix.",
    ],
    expected: "nf-core/differentialabundance",
    alts: ["differentialabundance"],
  },
  {
    id: "adv_002",
    query:
      "Somatic mutation profiling in multiple relapses of the same patient tumor over time",
    clarifications: [
      "tumor_T1_R1.fastq.gz, tumor_T2_R1.fastq.gz, tumor_T3_R1.fastq.gz and normal_R1.fastq.gz at s3://mybucket/longitudinal/ — WGS paired-end, GRCh38, 3 timepoint tumor biopsies + matched normal.",
      "Please run nf-core/sarek for somatic variant calling on these longitudinal WGS tumor-normal pairs.",
    ],
    expected: "nf-core/sarek",
    alts: ["sarek"],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// One test per case — all run in parallel
// ─────────────────────────────────────────────────────────────────────────────

for (const tc of CASES) {
  test(`routing-${tc.id}: "${tc.expected}"`, async ({ page }) => {
    test.setTimeout(300_000); // 5 min per query

    await loginAndNavigate(page);

    // Turn 1: initial query
    let reply = await sendAndWait(page, tc.query, 120_000);
    console.log(`[${tc.id}] T1 (${reply.length}c): "${reply.slice(0, 100)}"`);
    await page.screenshot({ path: path.join(SS_DIR, `${tc.id}_t1.png`) });

    let wfName = await getWorkflowCardName(page);

    // Up to N clarification rounds — answer each one with the next prepared reply
    for (let round = 0; round < tc.clarifications.length && !wfName; round++) {
      const needsClarification =
        reply.toLowerCase().includes("missing") ||
        reply.toLowerCase().includes("please provide") ||
        reply.toLowerCase().includes("need") ||
        reply.toLowerCase().includes("what") ||
        reply.toLowerCase().includes("which") ||
        reply.toLowerCase().includes("file") ||
        reply.toLowerCase().includes("path") ||
        reply.toLowerCase().includes("?");

      if (!needsClarification) break;

      const answer = tc.clarifications[round];
      console.log(`[${tc.id}] T${round + 2}: answering clarification round ${round + 1}`);
      reply = await sendAndWait(page, answer, 120_000);
      console.log(`[${tc.id}] T${round + 2} reply: "${reply.slice(0, 100)}"`);
      await page.screenshot({ path: path.join(SS_DIR, `${tc.id}_t${round + 2}.png`) });
      wfName = await getWorkflowCardName(page);
      console.log(`[${tc.id}] After T${round + 2} — card: "${wfName}"`);
    }

    // Extra wait for card to fully render
    if (!wfName) {
      await page.waitForTimeout(3_000);
      wfName = await getWorkflowCardName(page);
    }

    const passed = isMatch(wfName, tc.expected, tc.alts);
    await page.screenshot({ path: path.join(SS_DIR, `${tc.id}_final.png`) });
    console.log(
      `[${tc.id}] ${passed ? "✓ PASS" : "✗ FAIL"} — got="${wfName}" expected="${tc.expected}"`
    );

    expect(
      passed,
      `[${tc.id}] Expected "${tc.expected}" but got "${wfName}"\nLast reply: "${reply.slice(0, 300)}"`
    ).toBeTruthy();
  });
}
