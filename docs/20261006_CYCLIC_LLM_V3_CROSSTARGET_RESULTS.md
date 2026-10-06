# Cyclic LLM v3 — Cross-Target Generalization Probe (RESULTS)

**Date:** 2026-10-06 · All results **in-silico**; honest caveats inline. This is the experiment that
would make the methods paper (#2) real — or honestly bound it. **Verdict: NULL cross-target transfer
in both regimes** (as predicted from the data wall). A null here is a valid, publishable finding; we do
not manufacture a positive.

## Question
Can a **target-conditioned** display-trained cyclic LLM steer generation toward a **held-out target** it
never saw binders for? This is the hard problem v2 left open (v2 was single-target / property-conditioned).

## Design (honest; underpowered by construction)
- **Conditioning:** continuous **target-protein feature vector** (24-d: AA composition + log-length +
  Kyte-Doolittle hydrophobicity + net-charge frac + aromatic frac) as a learned prefix token, **plus**
  the **enrichment-tail bucket** (`<e_hi>`/`<e_mid>`/`<e_lo>`, tail-bucketed by log2FC≥2.0 per the v2
  lesson). Target features are a *vector from the protein sequence*, not a bare ID — so a held-out target
  has a well-defined conditioning vector at test time.
- **Within-regime held-out splits** (identical display chemistry on both sides — no chemistry confound):
  - **A — RaPID thioether-ncAA:** train **PADI4** (370,806 uniq, 7,297 hi-tail) → hold out **FIKK13**.
  - **B — M13-phage disulfide:** train **Abeta42** (44,099 uniq, 1,571 hi-tail) → hold out **hIAPP**.
- **Leakage control:** the held-out target's rows are **fully excluded** from training; used only to fit a
  held-out-target enrichment regressor (RandomForest on AA-composition) and to supply the known-binder
  reference for identity scoring.
- **Model:** ~10 M-param char-level GPT (d=256, 6 layers, block 32), target-prefix + enrichment-token
  conditioning. Trained 3,000 steps/split on local Apple-MPS (~9 min/split). **No AWS instances launched**
  — the model is tiny enough that the spot-EC2 guardrail did not apply (compute was never the blocker).
- **Cross-target eval (400 samples/condition):** compare `(heldout feats, hi)` vs `(heldout feats, lo)`
  vs `(train feats, hi)` vs `(train feats, lo)`, scored by (i) the held-out-target regressor, (ii)
  identity to the held-out target's literature binder, (iii) mean-max identity to held-out binders.
  **Transfer is real only if held-out-feature conditioning beats BOTH the low-enrichment control AND the
  train-target conditioning.** If target features are ignored, held-out-feats ≈ train-feats → NULL.

## Results — NULL in both regimes

### Split A (PADI4 → FIKK13); held-out binders n=38; ref `ESCRYRQVLQL`
| Conditioning | pred-heldout-enr | ident→ref | ident→heldout-binders | novelty |
|---|---|---|---|---|
| held-out feats, **hi** | 0.291 | 0.142 | 0.304 | 0.99 |
| held-out feats, lo | 0.264 | 0.136 | 0.297 | 1.00 |
| train feats, hi | 0.286 | 0.148 | 0.305 | 1.00 |

- **target-feature swap effect** (held-out−train, hi): pred-enr **+0.005**, ident→ref **−0.006**,
  ident→binders **−0.001** → target features are **ignored**.
- hi−lo (held-out feats): pred-enr **+0.027** (< the 0.2 bar) → enrichment conditioning does not raise the
  **held-out** target's score. **Transfer: NULL.**

### Split B (Abeta42 → hIAPP); held-out binders n=828; ref `CHVVGVIC`
| Conditioning | pred-heldout-enr | ident→ref | ident→heldout-binders | novelty |
|---|---|---|---|---|
| held-out feats, **hi** | 0.144 | 0.375 | 0.614 | 0.18 |
| held-out feats, lo | 0.248 | 0.289 | 0.594 | 0.99 |
| train feats, hi | 0.162 | 0.389 | 0.621 | 0.20 |

- **target-feature swap effect** (held-out−train, hi): pred-enr **−0.018**, ident→ref **−0.014**,
  ident→binders **−0.007** → target features **ignored** again.
- Note the *apparent* signal: hi raises ident→ref (+0.086) over lo — but this is **scaffold memorization,
  not targeting**: both phage campaigns share the same Cys-flanked disulfide scaffold and anchors, so
  "hi" generations collapse to a narrow Abeta42-learned consensus (novelty crashes 0.99→0.18) that
  overlaps the shared `C…C` motif. The **held-out regressor score drops** for hi (−0.104), and the
  target-feature swap confirms zero hIAPP-specific steering. **Transfer: NULL.**

## Why NULL was the expected, correct outcome (root cause, not excuse)
With exactly **one training target per regime**, the target-feature prefix is a **constant** across every
training example. A constant input carries **no gradient** that teaches "how changing target features
changes the preferred binder." The model therefore learns to **ignore** the target prefix and collapses to
enrichment/scaffold conditioning on the single training target. Swapping in a held-out target's feature
vector at test time — a direction the model never varied over — does nothing systematic. This is close to
a mathematical certainty, not merely an empirical miss, and it precisely **locates the data wall**:

> **Cross-target generalization is not learnable from 1 training target/regime. It requires ≥3 training
> targets per regime (same display chemistry) so the target→binder map has gradient to learn from.**

This is consistent with the program's prior OOD findings (binding model PD-L1 hold-out Spearman 0.18;
foundation-model transfer doesn't generalize OOD) — target-conditioning is not a shortcut around the
paired-(target, binder) data constraint.

## What this does / doesn't change for the papers
- **Does NOT** support a "our LLM generalizes across targets" claim. Do not write one.
- **DOES** give the methods paper a clean, honest **negative control + a quantified data requirement**
  (≥3 targets/regime), which is a real contribution: it tells the field exactly what display-data scale is
  needed before target-conditioned cyclic generation is even testable.
- v2's **within-target** result stands (enrichment is a learnable binding signal, Δ+0.317); v3 shows the
  **cross-target** boundary. Together they bound the capability honestly.

## Next step to actually test transfer (not run here — needs data, not compute)
Harvest **≥3 targets within one display chemistry** (e.g. more RaPID-thioether campaigns from SRA/ENA, or
a proprietary multi-target campaign), retrain target-conditioned with **leave-one-target-out**, and
re-run this exact eval. Only a multi-target training set can move this from NULL to a real yes/no.
Optionally upgrade target features from composition to **ESM-2 embeddings** (richer target relatedness) —
but that is second-order; the n≥3 training-target requirement dominates.

## Artifacts
- Code: `research/guangzhou_all_atom/cyclic_llm/train_cyclic_llm_v3.py` (build-data / train / eval).
- Data blobs: `research/guangzhou_all_atom/data/display/v3_A.json`, `v3_B.json` (+ `target_proteins.json`).
- Checkpoints + evals on S3: `s3://knowledge-datasets-1759951976/cyclic_peptide/runs/cyclic-llm-v3/`
  (`cyclic_llm_v3_{A,B}.pt`, `*.meta.json`, `cyclic_llm_v3_{A,B}_eval.json`, `target_proteins.json`).
- Multi-target source: `s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/display_ngs_multitarget/`
  (2,215,404 rows; 5 targets).
- Lineage: `20261006_CYCLIC_LLM_V2_DISPLAY_RESULTS.md`, `20261006_INNOVATION_PROGRAM_STATUS.md`,
  `20261005_INNOVATION_THESIS_CYCLIC_LLM.md`, `20261005_CHALLENGE_INVENTORY_RECOVERED.md`.
