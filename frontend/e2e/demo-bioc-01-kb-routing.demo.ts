/**
 * Bioconductor Demo 1 — KB routing & execution (DESeq2 chain)
 *
 * 21 steps · ~2.5 min runtime · video lands in e2e/demo-videos/
 *
 * Arc: match KB → disambig card → routed by data format → run 6 phases
 *      → walk the 7-tab After-run report.
 *
 * Pre-req: static server on :8000 serving reference/claude_design/bioconductor-handoff/
 * (see frontend/e2e/demo-bioc-helpers.ts for the URL).
 *
 * Run:
 *   npx playwright test --config frontend/playwright.demo.config.ts \
 *     frontend/e2e/demo-bioc-01-kb-routing.demo.ts
 */
import { test } from '@playwright/test';
import { loadBiocRef, BIOC_TOURS } from './demo-bioc-helpers';
import { runTourDemo, shot, pause } from './demo-ref-helpers';

const DEMO = 'bioc-01-kb-routing';
const TOUR = BIOC_TOURS.kb;

test('Bioc-01 — DESeq2 chain: match → route → run → 7-tab report', async ({ page }) => {
  test.setTimeout(300_000); // 5 min ceiling; expected ~2.5 min

  await loadBiocRef(page);
  await shot(page, DEMO, 'pre_tour');
  await pause(page, 2_000);

  await runTourDemo(page, DEMO, TOUR.label, TOUR.nSteps, TOUR.pauseOverride);

  await shot(page, DEMO, 'done');
  console.log(`[${DEMO}] ✅ ${TOUR.nSteps}-step DESeq2 walkthrough complete`);
});
