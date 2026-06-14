/**
 * Bioconductor Demo 2 — scRNA-seq → pseudobulk DE (OSCA chain)
 *
 * 19 steps · ~2.3 min runtime · video lands in e2e/demo-videos/
 *
 * Arc: route to OSCA → cell QC → cluster → parallel markers+annotation
 *      → pseudobulk DE (the centerpiece beat) → 7-tab After-run report.
 *
 * Centerpiece: the pseudobulk warning — extended dwell (8s vs default 5.5s)
 * so viewers can read the trap + fix in one breath. See
 * docs/20260610_BIOC_TUTORIAL_NARRATIVE_AUDIT.md D4.
 */
import { test } from '@playwright/test';
import { loadBiocRef, BIOC_TOURS } from './demo-bioc-helpers';
import { runTourDemo, shot, pause } from './demo-ref-helpers';

const DEMO = 'bioc-02-sc-routing';
const TOUR = BIOC_TOURS.sc;

test('Bioc-02 — scRNA-seq → pseudobulk DE: route → cluster → annotate → pseudobulk', async ({ page }) => {
  test.setTimeout(300_000);

  await loadBiocRef(page);
  await shot(page, DEMO, 'pre_tour');
  await pause(page, 2_000);

  await runTourDemo(page, DEMO, TOUR.label, TOUR.nSteps, TOUR.pauseOverride);

  await shot(page, DEMO, 'done');
  console.log(`[${DEMO}] ✅ ${TOUR.nSteps}-step scRNA → pseudobulk DE walkthrough complete`);
});
