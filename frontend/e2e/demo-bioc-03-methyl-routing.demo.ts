/**
 * Bioconductor Demo 3 — 450k methylation → DMRs (minfi chain)
 *
 * 19 steps · ~2.3 min runtime · video lands in e2e/demo-videos/
 *
 * Arc: read IDAT → GenomicRatioSet (genomic backbone) → DMPs → DMRs
 *      → CpG-corrected enrichment (the centerpiece beat) → 7-tab report.
 *
 * Centerpiece: the CpG-density bias correction — extended dwell (8s vs
 * default 5.5s). See docs/20260610_BIOC_TUTORIAL_NARRATIVE_AUDIT.md D5.
 */
import { test } from '@playwright/test';
import { loadBiocRef, BIOC_TOURS } from './demo-bioc-helpers';
import { runTourDemo, shot, pause } from './demo-ref-helpers';

const DEMO = 'bioc-03-methyl-routing';
const TOUR = BIOC_TOURS.methyl;

test('Bioc-03 — 450k methylation → DMRs: IDAT → GenomicRatioSet → DMPs → DMRs → CpG-corrected GO', async ({ page }) => {
  test.setTimeout(300_000);

  await loadBiocRef(page);
  await shot(page, DEMO, 'pre_tour');
  await pause(page, 2_000);

  await runTourDemo(page, DEMO, TOUR.label, TOUR.nSteps, TOUR.pauseOverride);

  await shot(page, DEMO, 'done');
  console.log(`[${DEMO}] ✅ ${TOUR.nSteps}-step methylation walkthrough complete`);
});
