/**
 * Bioconductor demo helpers — points the existing demo-ref pipeline at the
 * separate "Research Agent UI" prototype that lives in
 * reference/claude_design/bioconductor-handoff/ (the bioc tutorials live
 * inside that prototype, not the older Workflow Panel Redesign).
 *
 * Pre-req: a static server must be running on port 8000 serving the
 * bioconductor-handoff directory. The runner script
 * scripts/recording/serve-bioc-handoff.sh starts one if needed. Manually:
 *
 *   cd reference/claude_design/bioconductor-handoff
 *   python3 -m http.server 8000
 *   # → http://localhost:8000/Research%20Agent%20UI.html
 *
 * Tutorial labels (from src/Tour.jsx in the handoff):
 *   BIO  — bioc-kb-routing   = 'BIO — Bioconductor · KB routing & execution'
 *   BIO2 — bioc-sc-routing   = 'BIO2 — Bioconductor · scRNA-seq → pseudobulk DE'
 *   BIO3 — bioc-methyl-routing = 'BIO3 — Bioconductor · 450k methylation → DMRs'
 *
 * Step counts (audited 2026-06-10):
 *   BIO  : 21 steps (10 own + 10 after-run + 1 wrap)
 *   BIO2 : 19 steps (8 own + 10 after-run + 1 wrap)
 *   BIO3 : 19 steps (8 own + 10 after-run + 1 wrap)
 *
 * Per-step pause overrides — from
 * docs/20260610_BIOC_TUTORIAL_NARRATIVE_AUDIT.md. The defaults are
 * 5.5–6s; we extend the few content-dense steps so viewers can read them.
 */
import type { Page } from '@playwright/test';

export const BIOC_REF_URL =
  process.env.BIOC_REF_URL ||
  'http://localhost:8000/Research%20Agent%20UI.html';

/**
 * Load the bioc handoff prototype. Unlike loadRef() in demo-ref-helpers, no
 * tweaks panel exists here — the tutorial drives scenario/runState via its
 * own __tourReset() and showCard() machinery.
 */
export async function loadBiocRef(page: Page): Promise<void> {
  await page.addInitScript(() => {
    try { localStorage.removeItem('biomate_wf_tour_seen'); } catch {}
  });
  await page.goto(BIOC_REF_URL, { waitUntil: 'networkidle', timeout: 30_000 });
  await page.waitForTimeout(2_500);
}

/**
 * Tutorial step counts — single source of truth.
 * Update if BiocTours.jsx step lists change.
 */
export const BIOC_TOURS = {
  kb: {
    id: 'bioc-kb-routing',
    label: 'BIO — Bioconductor · KB routing & execution',
    // Step count grew to 22 after Interactive Launcher step was added to
    // afterRunSteps (REQUEST_ADD_INTERACTIVE_PANEL.md request landed).
    nSteps: 22,
    /** D1 fix: extend disambig (step 3) dwell so viewer can read both scores */
    pauseOverride: { 2: 7_500 } as Record<number, number>,
  },
  sc: {
    id: 'bioc-sc-routing',
    label: 'BIO2 — Bioconductor · scRNA-seq → pseudobulk DE',
    nSteps: 20,
    /** D4 fix: extend pseudobulk centerpiece (step 8 → index 7) to 8s */
    pauseOverride: { 7: 8_000 } as Record<number, number>,
  },
  methyl: {
    id: 'bioc-methyl-routing',
    label: 'BIO3 — Bioconductor · 450k methylation → DMRs',
    nSteps: 20,
    /** D5 fix: extend CpG-bias centerpiece (step 8 → index 7) to 8s */
    pauseOverride: { 7: 8_000 } as Record<number, number>,
  },
} as const;
