# Hero A — "BioMate caught a cardiotoxic candidate and remediated the screen" (case study)

**Date:** 2026-10-04 · **Built from real committed runs — no simulated numbers.**
**One-line:** *A scientist screened a candidate panel in plain English; BioMate ran it on managed cloud,
and its QC auto-loop flagged a cardiotoxic (hERG) liability a naive pipeline would have shipped silently —
with a cited threshold and a grounded remediation — then the corrected screen passed clean.*

This is the flagship Paper A **Tier-3 case study** and the marketing hero. Every value traces to a committed
run; the one remaining production step is filming the live panel (recipe below).

## The sequence (all real)
1. **Screen** — ADMET/developability on a candidate panel incl. a known liability.
   - Run **`d0ff684b-fd91-4e6f-ba0a-ea136b427700`** (AWS Batch, succeeded, 292 s): `smiles_list = [aspirin,
     terfenadine]`, model MPNN. Workflow `predict_admet_properties`.
2. **The hero beat — the QC gate HALTS (live, real run):** run-record `qc_gates`:
   - `herg_ic50_uM = 0.012` < 1.0 µM → **[GOLD] halt** — "below the high-risk threshold of 1.0 µM
     (Sanguinetti & Tristani-Firouzi 2006; FDA E14). Predicts QT prolongation / Torsade de Pointes.
     Structural optimisation required before progression."
   - `dili_risk = high` → **[GOLD] halt** (DILIrank; Chen 2016).
   - Per-compound ground truth (`docs/autoloop_live_proof_20261004/toxicity_report.json`): **terfenadine**
     logP 7.01, MW 499.7, **hERG IC50 0.0124 µM, hERG_prob 0.974**; aspirin hERG-safe (10000 µM).
3. **Remediation (grounded, from `param_tuner.remediate()`):** tighten the developability envelope —
   `logp_max 5.0 → ≤4.0`, `mw_max_da 500 → 400` (hERG QSAR inversion + Lammert boundary; DILI rule). The
   system *recommends* the fix; the re-run is a deliberate step (reactive/advisory, not autonomous restart).
4. **Resolved — the corrected screen passes clean:** run **`46953d98-fd2a-4df5-9ebe-74786311f899`** (same
   workflow, the safe panel aspirin/caffeine/ibuprofen) completed with **`qc_gates: []`** — the gate stays
   silent on safe chemistry, proving it discriminates rather than always-firing.
5. **Audit report:** gate table + cited thresholds + params + run provenance (run ids, S3 outputs) — fully
   reproducible.

## Why it lands (vs competitors)
No surveyed system (Biomni, FutureHouse, Seqera AI, the data-clouds) demonstrates **chat-driven QC-gate
detection + remediation over an executed pipeline.** The story is not "we found a drug" — it is **"you can
trust the result: BioMate catches the scientifically-unsafe candidate and tells you why, with a citation."**
Pairs with input-QC (data perception) for the end-to-end-trust narrative (`biomate-marketing-strategy.md` §9).

## Reproduction recipe (for the filmed version)
1. MCP `search_workflow("ADMET hERG cardiotoxicity")` → `Predict ADMET Properties (AI)`.
2. MCP `run_workflow(workflow_id, params={smiles_list:"[aspirin, terfenadine]", ADMET_model_type:"MPNN",
   admet_shard_size:25}, stream=true)` → watch the gate halt in the auto-loop panel (`[data-testid=
   autoloop-gate-table]`, `autoloop-remediation-card`).
3. Drop terfenadine → `run_workflow` the safe panel → clean pass → `export_report`.
To capture the live SSE remediation panel (the one visual not yet recorded): run
`frontend/e2e/autoloop-live-proof.e2e.ts` and screenshot the panel; produce EN+CN per the tutorial pipeline.

## Honesty
Reactive/advisory remediation (not an autonomous closed-loop restart). ADMET values are model estimates
(Chemprop/ADMET-AI) — experimental validation required. All numbers from committed runs d0ff684b / 46953d98
and `docs/20261004_AUTOLOOP_LIVE_PROOF.md`.
