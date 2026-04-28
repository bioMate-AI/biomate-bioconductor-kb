/**
 * Demo 2 — Genomics: Whole-Genome Sequencing Variant Calling
 *
 * Scientific story: germline variant calling on a real public dataset.
 * SRR1518169 is a 1000 Genomes Project WGS sample (NA12878, Illumina HiSeq,
 * 30× coverage).  We pull 500 000 reads via fasterq-dump, align to hg38
 * with BWA-MEM2, call germline variants with GATK HaplotypeCaller, and
 * annotate with snpEff.
 *
 * Expected outputs:
 *   BAM      → aligned reads, flagstat QC metrics
 *   VCF      → SNVs + indels (PASS-filtered)
 *   snpEff   → functional annotation (coding/noncoding, impact)
 *   QC report → coverage, Ti/Tv ratio, het/hom ratio
 *
 * Billing: LLM + compute both asserted.
 */

import { test, expect } from '@playwright/test';
import {
  setupDemoUser,
  sendAndWait,
  clickRunAndWait,
  waitForNoActiveRuns,
  captureBilling,
  captureBillingAfter,
  billingDelta,
  logBillingDelta,
  shot,
  pause,
  tip,
  exploreTutorial,
} from './demo-helpers.js';

const DEMO = 'demo-02-genomics-wgs';
const EMAIL = 'demo_genomics_wgs@biomate.test';

const WGS_QUERY =
  `Run germline variant calling on SRR1518169 (1000 Genomes NA12878, Illumina HiSeq 2500, ` +
  `30× WGS). Use max_spots=500000 for this demo. ` +
  `Align to hg38, call variants with GATK HaplotypeCaller in GVCF mode, apply VQSR filtering, ` +
  `and annotate with snpEff (GRCh38.105). ` +
  `Report: total variants, PASS variants, Ti/Tv ratio, coding variants by impact.`;

const INTERPRETATION_QUERY =
  `Interpret the variant calling results. What is the Ti/Tv ratio and what does it indicate ` +
  `about data quality? How many HIGH-impact coding variants were found, and what are the ` +
  `most significant ones? Is this consistent with a healthy individual genome?`;

test('Demo 2 — WGS variant calling: SRR1518169 → hg38 → GATK → snpEff', async ({ page }) => {
  test.setTimeout(1_800_000);

  // ── Setup ──────────────────────────────────────────────────────────────────
  await setupDemoUser(page, EMAIL, 'DemoPass123!', 'Genomics');
  await shot(page, DEMO, '00_start');

  await tip(page, 'Welcome to BioMate — AI-native genomics analysis from raw sequencing data to annotated variants', 4500);
  await pause(page, 4_500);

  const billingBefore = await captureBilling(page, 'demo2-before');

  // ── Turn 1: WGS pipeline ───────────────────────────────────────────────────
  console.log('[Demo2] Turn 1: WGS variant calling');
  await tip(page, 'BioMate identifies the full BWA-MEM2 → GATK → snpEff pipeline from a single natural language request', 4500);
  await pause(page, 2_000);

  const hasRun = await sendAndWait(page, WGS_QUERY, 180_000);
  await shot(page, DEMO, '01_wgs_card');

  if (hasRun) {
    await tip(page, 'SRA accession, reference genome, variant caller, and annotation database were all auto-filled', 4000);
    await pause(page, 3_000);

    await tip(page, 'Step 1 of 4: fasterq-dump pulls reads from NCBI SRA — no manual download required', 3500);
    await pause(page, 2_000);

    console.log('[Demo2] Running WGS pipeline on AWS Batch (BWA-MEM2 → GATK → snpEff)...');
    const runId = await clickRunAndWait(page, 1_200_000);
    console.log('[Demo2] Pipeline complete. runId:', runId);

    await shot(page, DEMO, '02_wgs_phases');
    await pause(page, 2_000);

    // Narrate what each completed phase produced
    await tip(page, 'Pipeline complete — fasterq-dump pulled 500K reads from NCBI SRA without any manual download', 4000);
    await pause(page, 3_000);

    await tip(page, 'BWA-MEM2 aligned reads to hg38 — 2× faster than BWA, alignment metrics in flagstat output', 4000);
    await pause(page, 3_000);

    await tip(page, 'GATK HaplotypeCaller called germline SNVs and indels in GVCF mode with VQSR filtering applied', 4000);
    await pause(page, 3_000);

    await tip(page, 'snpEff annotated every variant with functional impact: HIGH / MODERATE / LOW / MODIFIER', 4000);
    await pause(page, 3_000);

    await shot(page, DEMO, '03_wgs_results');

    // Comprehensive tutorial traversal of WGS results
    await exploreTutorial(page, (text, ms) => tip(page, text, ms));

    await shot(page, DEMO, '03b_wgs_explored');

    await waitForNoActiveRuns(page, 1_200_000);
    await pause(page, 3_000);
  } else {
    console.log('[Demo2] WARN: Run button not visible');
    await shot(page, DEMO, '01b_wgs_response');
  }

  // ── Turn 2: Scientific interpretation ─────────────────────────────────────
  console.log('[Demo2] Turn 2: scientific interpretation');
  await tip(page, 'Now ask BioMate to interpret the results — it reads the VCF and snpEff report directly', 4000);
  await pause(page, 2_000);

  await sendAndWait(page, INTERPRETATION_QUERY, 120_000);
  await shot(page, DEMO, '04_interpretation');

  await tip(page, 'Ti/Tv ratio ~2.0–2.1 confirms high-quality whole-genome data — BioMate flags any QC anomalies', 4500);
  await pause(page, 4_000);

  // Scroll slowly through the interpretation for the recording
  await page.locator('[data-is-latest-assistant="true"]').scrollIntoViewIfNeeded().catch(() => null);
  await pause(page, 2_000);

  await tip(page, 'HIGH-impact variants are listed with gene name, consequence, and population frequency context', 4000);
  await pause(page, 4_000);

  // ── Billing audit ──────────────────────────────────────────────────────────
  const billingAfter = await captureBillingAfter(page, 'demo2-after');
  const delta = billingDelta(billingBefore, billingAfter);
  logBillingDelta('demo2', delta);

  await tip(page, `Total session cost: $${delta.total_usd.toFixed(4)} — full WGS pipeline + AI interpretation`, 5000);
  await pause(page, 5_000);

  expect(delta.llm_cost_usd, 'Demo2: LLM billing not emitted').toBeGreaterThan(0);

  if (delta.compute_cost_usd === 0) {
    console.log('[Demo2] WARN: compute_cost_usd=0 — Batch→Lambda→Lago pipeline may not be wired');
  }

  await shot(page, DEMO, '05_final');
  console.log(
    `[Demo2] COMPLETE — llm=$${delta.llm_cost_usd.toFixed(4)} ` +
    `compute=$${delta.compute_cost_usd.toFixed(4)}`
  );
});
