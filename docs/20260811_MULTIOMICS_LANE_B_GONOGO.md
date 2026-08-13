# Lane B go/no-go: does data-shape method-SELECTION beat a fixed default?

Date: 2026-08-11. The one experiment that decides whether the "auto-select the integration
method" idea is a real research contribution or just a wrapper. Verdict: **NO-GO on the
current premise — the selector loses to "always-MCIA".**

## Setup

- Cohorts (real, staged): CLL/IGHV (k2), TCGA-AML/cyto-risk (k3), TCGA-BRCA/PAM50 (k4).
  All pre-filtered to ~5000 features/modality (CLL: mrna+methylation; TCGA: exp+methy+mirna).
- ARI table: from MULTIOMICS_PLATFORM_MASTER.md §2 (7 methods × 3 cohorts), the platform's
  own matched-k ground-truth-recovery scores.
- Selector picks: obtained by running the real `method_selector.recommend()` on each
  cohort's actual shape (feature counts fetched from S3).

## What the selector actually picks (live code, not doc numbers)

| goal | CLL | AML | BRCA |
|---|---|---|---|
| `None` (data-shape only) | MOFA2 | MOFA2 | MOFA2 |
| `clustering` (what subtyping IS) | SNF | SNF | SNF |

**The selector does not differentiate cohorts — it collapses to one fixed method.** Reason:
the only rule that would pick MCIA (`high_dim_mixed`) requires ≥10,000 features, but the
data is filtered to 5,000, so it never fires. `goal=None` → always MOFA2; `goal=clustering`
→ always SNF. So "selection" here is identical to a fixed-method policy.

## The comparison (mean ARI across the 3 cohorts)

| strategy | CLL | AML | BRCA | MEAN |
|---|---|---|---|---|
| SELECTOR goal=None (=always-MOFA) | 0.797 | 0.093 | 0.202 | **0.364** |
| SELECTOR goal=clustering (=always-SNF) | 0.705 | 0.174 | 0.323 | **0.401** |
| always-MCIA | 0.778 | 0.237 | 0.332 | **0.449** |
| ORACLE (best method per cohort) | 0.876 | 0.237 | 0.332 | 0.482 |

- selector(goal=None) **loses** to always-MCIA by −0.085 ARI.
- selector(goal=clustering) **loses** to always-MCIA by −0.048 ARI.
- The verdict is robust to noise in the table: on both TCGA cohorts MOFA2/SNF trail MCIA
  by 2–3× (0.093/0.174 vs 0.237; 0.202/0.323 vs 0.332) — no plausible re-measurement error
  closes that.

## Interpretation

1. **The current selector is refuted on the data we have.** "Just always use MCIA"
   (Cantini 2021's recommended robust default) beats it in every configuration.
2. **The ceiling for selection here is thin anyway.** A perfect oracle beats always-MCIA
   by only +0.033 (7%), and the *entire* upside comes from one cohort (CLL, where MFA 0.876
   > MCIA 0.778). On the two TCGA cohorts MCIA already IS the oracle. So even a perfect
   selector would add little over "use MCIA" on this battery.
3. Therefore a defensible Lane-B methods paper is NOT achievable with the current premise,
   rules, or cohort set.

## What Lane B would now require (high effort, weak prior)

- A much larger cohort battery **spanning data-shape axes where the winner genuinely
  varies** (bulk/sc, paired/mosaic, 2–5 modalities, clustering/survival/biomarker) — 3
  cohorts where MCIA wins 2 is not enough signal.
- **Learned/tuned** selection rules that actually predict the per-cohort winner (the current
  hand-authored thresholds don't even differentiate these cohorts), plus fixing the
  miscalibrated `high_dim` threshold and the `goal=clustering→SNF` rule (SNF is dominated
  by MCIA on all three cohorts).
- Held-out validation showing selection ≥ oracle-adjacent and strictly > always-MCIA with
  CIs. Given (2) above, the prior that this beats always-MCIA is weak.

## Decision

- **Do NOT invest in Lane B on the current premise.** The honest scientific nugget that
  survives is a *cautionary* one: "naive data-shape heuristics do not beat a single robust
  default (MCIA captures 93% of oracle on this battery)" — a benchmark caveat, not a
  method.
- **Lane A (tool/Applications Note) remains the honest publishable path** — positioned as a
  reproducible convenience layer, with the selector presented as sensible defaults + the
  benchmark harness, NOT as a validated method-recommender. Fix the over-claims first
  (see 20260811_MULTIOMICS_NOVELTY_ASSESSMENT.md).

Cost note: no new AWS Batch runs were needed — the verdict rests on a code fact (the
selector collapses to one method) + the existing internally-consistent ARI table whose
TCGA gaps are too large for measurement error to flip.
