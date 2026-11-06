# Screenshot committee review — BioMate user-manual end-to-end screenshots

**Date:** 2026-10-13 · **Committee:** OpenAI `gpt-6.1-sol-pro` + Google `gemini-3.1-pro-preview` + Anthropic `claude-opus-5.5` (all via OpenRouter), each independently reviewing **all 56** `docs/user-manual/assets/*.png` on 4 axes (screen quality, UI elements, content correctness, clarity) against each shot's intended `CAPTURE` state.
Runner: `research/screenshot_committee/review.py` → `results/committee_raw.json`; aggregation → `results/aggregated.json`.
**This is a review/sanity layer, not validation.** Raw verdict tally: **121 major / 37 minor / 8 ok** (168 verdicts); **39/56 assets are consensus-major** (≥2 models).

## Executive summary — what actually matters

### A. Real UI / product / content bugs the committee caught (fix in the product, not the screenshot)
1. **CRO Library capture is a `Page not found` (404).** `i13-1-cro-library.png` shows an error page, not the CRO library — either `/drug-discovery-cro` was broken when captured or the capture hit an unauth/route error. **Investigate the route**; the asset is unusable until re-shot against a working page.
2. **Multi-objective design — accept logic contradicts the displayed gate.** `i11-3-multi-objective.png`: candidates BM-0001–BM-0004 are **"Accepted" despite `property_envelope = 0` failing the stated "≥ 1 target"** (flagged by OpenAI + Google). Either the accept rule or the displayed threshold is wrong — a genuine content/logic inconsistency to reconcile.
3. **Failed/mid-run panel shows contradictory status.** `r-fail-state.png`: overall progress vs per-step progress conflict, and "QC blocked / adjusting" coexists with a "Done" status. Real state-rendering inconsistency worth a product look (captured during the ADMET QC-gate moment).
4. **Two similarly-named download buttons confuse even expert reviewers.** On `i09-1`, `i09-2`, `r-merged-results-view` all three models flagged the top-right **aggregate "Download report"** as stale/confusing next to the new **"Download findings"**. The aggregate button is *intentional* (stitches all tabs) — so this is a **UX-clarity** issue, not staleness: if 3 frontier reviewers misread it, users will too. Consider renaming it (e.g. "Download full report") or disambiguating in-UI.
5. **Connectors dialog** (`i12-1`): tab label doesn't match the intended state and the data-residency copy reads as conflicting — verify the content.

### B. Systemic CAPTURE-quality issues (fix in the capture harness, not the product)
- **Ugly fixture data dominates many shots.** Project names like `E2E File Tree 1789241690756`, duplicate/near-identical project cards, orange "Watch" quality pills instead of a clean green example (`i05-*`, `m2-1`, cold-start). → **Seed a clean, reader-facing demo project** (good names + example data + a versioned, green-quality dataset) and capture against it.
- **Crop / dead space / clipped previews.** Most assets are full-viewport with large empty margins; several inline previews are clipped with no scroll cue. → **element-scoped crops** in the harness.
- **Wrong state captured.** e.g. `m2-1` shows the "Ad-hoc compute" tab, not "Validated workflows"; several shots don't match their intended `CAPTURE` state. → the harness should **drive to the intended state** before shooting.

### C. Coverage gaps (the bigger foundation issue)
- **17 assets are `unreferenced`** (not linked from any manual page) — orphaned captures.
- **Whole domain use cases have ZERO screenshots.** The per-use-case table below covers T0/T3/T10/T11/W2 + some modules, but **cryo-EM, single-cell, variant-calling, proteomics, metabolomics, metagenomics, epigenomics, structural-biology, multi-omics, CRISPR** have **no end-to-end screenshot sequence at all**. If end-to-end screenshots are the foundation "for each and every use case", these must be captured (each needs its own real run → the run-dependent harnesses).

---

