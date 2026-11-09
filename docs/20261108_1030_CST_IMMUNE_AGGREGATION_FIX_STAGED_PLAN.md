# Staged plan: fix the knowledge aggregation, re-test the 2×2 (gated, cheap-before-GPU)

Recorded: 2026-11-08 ~10:30 CST. Spark unreachable at write time (mDNS name not resolving — the
intermittent same-Wi-Fi condition). Everything here is **staged and ready to fire** when Spark returns.

## Where the investigation stands

The feature-level 2×2 (docs `20261108_0905_...WHY_KNOWLEDGE_WORKS...`) established: our pathway/TF **mean**
knowledge channel wins only under {scarce labels × held-out cell type}; it LOSES under held-out tissue
at every budget. Proposed mechanism: a per-cell MEAN inherits the compartment OFFSET, so across tissues
the features carry a tissue-batch term that breaks transfer (the E2 flaw in the 2026-09-02
`KNOWLEDGE_BOTTLENECK_V1_ERROR_ANALYSIS`).

## Gate 1 (CHEAP, CPU, no encoder) — run FIRST

**`docs/20261108_knowledge_features_baseline/percellnorm/run_percellnorm_crosstissue.py`** (staged,
syntax-checked). Tests the falsifiable prediction of the mechanism: strip the per-cell offset BEFORE
aggregating (`know_pc` = gene-set means over per-cell z-scored HVG) and the cross-tissue transfer
failure should shrink/vanish. Decisive contrast per (held-out tissue, budget): `know_pc − raw` vs the
current `know_mean − raw`.

Run when Spark is back:
```
WS=/home/yzhang/immune_fm_spark AUD=/home/yzhang/immune_fm_spark/eval_repair_20261107 \
  python3 run_percellnorm_crosstissue.py        # from ~/immune_fm_spark/eval_repair_20261107
```
Interpretation / branch:
- **`know_pc − raw` ≫ `know_mean − raw` (ideally ≥ 0):** offset confirmed as the cause; per-cell-norm
  is a cheap aggregation fix. → proceed to Gate 2 to get the same benefit inside a trained model.
- **`know_pc − raw` ≈ `know_mean − raw` (still negative):** offset is NOT the (sole) cause. Do NOT
  spend GPU on the expiMap retrain yet — the transfer gap is deeper (raw is simply more
  tissue-invariant for this signal); revisit the mechanism before training.

## Gate 2 (GPU, expiMap/VEGA decoder) — run ONLY if Gate 1 is positive

Build the knowledge integration the error-analysis prescribed, replacing the frozen lossy mean:
1. **expiMap masked DECODER** from `z_cell`: linear decoder whose weights are masked by the gene-set
   membership matrix, so z must reconstruct expression *through* the programs (gradient flows INTO z,
   fixing the knowledge2 bypass). Reuse scArches/expiMap; do not hand-roll.
2. **De-novo unconstrained latent nodes** alongside the constrained ones (recovers the capacity the
   v1 mean-replacement destroyed, −0.092 F1).
3. **Learnable soft mask** init from the GMT membership (+ optional group-lasso), not frozen.
4. **Per-cell-normalized input** to the program aggregation (Gate 1's fix, inside the model).
Then **re-run this exact 2×2** (cell-type and tissue holdout × abundant/scarce) on the trained z.
Win condition: knowledge now also wins (or ties) the tissue-shift cells — i.e. the TRANSFER slice is
recovered, not just the sample-efficiency slice.

Caveats carried forward: single donor D534, within-dataset shifts (tissue/cell-type) as transfer
proxies; a truly independent cohort + pretraining-overlap audit is the eventual gold test (overlap
audit matters only at Gate 2, since Gate 1 is encoder-free). Batch-clean latent remains the
precondition for any clinical-endpoint knowledge claim (separate from this stimulation endpoint).

## GATE OUTCOME (11:05 CST — Spark was reachable by IP 192.168.1.205; the `.local` name just
doesn't resolve from the current 10.234.x subnet, so Spark was never down)

**Gate 1 (per-cell-norm cross-tissue) — NOT a clean pass.** Offset-stripping (`know_pc`) recovered only
~+0.015–0.028 at full labels and nothing under scarcity; knowledge still loses cross-tissue at every
budget (`know_pc − raw` = −0.017 lung / −0.031 spleen @full). So the per-cell OFFSET is a **minor**
contributor, not the main cause. Per the pre-registered rule: do NOT jump to the expiMap GPU retrain.

**Gate 1b (selection vs aggregation, `selection_vs_aggregation_20261108/`) — isolates the real cause.**
The 1,995/2,000 genes that live in ≥1 gene set, left **ungrouped**, transfer *exactly* as well as raw
(`raw_knowgenes − raw` = +0.001 lung / −0.000 spleen). Collapsing them into gene-set **means** is what
loses transfer (`know_pc − raw` ≈ −0.02 to −0.03); a richer per-set summary (mean+std+max) recovers
most of it for spleen. **Cause = AGGREGATION (averaging destroys within-set gene-level resolution),
not gene selection, not offset.**

**DECISION — DEFER Gate 2 (expiMap) for this endpoint. Do not spend GPU here.** The decisive fact:
`raw_knowgenes ≈ raw` means the best any knowledge aggregation can do on this cell-level tissue-transfer
task is **match raw, never beat it** — there is no latent knowledge transfer advantage to recover
(all genes are measured in all tissues, so there is no unseen-entity gap for knowledge to bridge). A
perfect expiMap would at most catch up to raw, not demonstrate a knowledge edge. The genuine
knowledge-transfer advantage the literature shows (GEARS: **unseen genes/perturbations**) requires a
regime this endpoint does not contain.

**Revised use of Gate 2:** build the expiMap de-novo/learnable-mask decoder ONLY in service of a task
that actually has an unseen-entity gap (unseen-gene / unseen-perturbation / genuinely independent
cohort), where knowledge can bridge what raw cannot — not for cross-tissue on a fully-measured panel.
The sample-efficiency benefit (scarce × cell-type-holdout) remains the real, reproduced value of the
current mean channel on in-distribution data.

## Gate 1c (unseen-gene external-knowledge bridge — the GEARS regime itself)

Constructed the unseen-entity gap directly: mask 30% of HVG as "unseen", impute each from its SEEN
gene-set co-members (external knowledge only, no coexpression/leak), leave-tissue-out, 3 mask seeds.
Result (`unseen_gene_bridge_20261108/`): masking barely hurts (lung 0.843→0.837, spleen 0.699→0.666)
and the knowledge bridge recovers ~0 (+7%/+4%, i.e. nil). **The stim signal is redundantly distributed
across genes → there is NO unseen-entity gap to bridge on this task**, and the co-membership bridge
doesn't recover even the small gap. This is a TASK property, not a mechanism failure: cell-level
classification on a redundant 2000-HVG panel is the opposite of GEARS's setting (a held-out perturbation
whose UNIQUE effect must be inferred from known relations).

**PROGRAM CONCLUSION:** knowledge-for-transfer cannot be demonstrated on this endpoint at all, for any
mechanism. To pursue it, change the TASK to one with a genuine unseen-entity gap — held-out-PERTURBATION
prediction on the CZI Perturb-seq atlas (`s3://genome-scale-tcell-perturb-seq/`, leave-perturbation-out),
the natural home of GEARS-style knowledge wins — not cross-tissue/cell-type on a fully-measured panel.
Knowledge's demonstrated value on stimulation = sample-efficiency regularization under scarcity (real).

## Status
- Gate 1 + Gate 1b + Gate 1c: RUN, documented. Conclusion: aggregation-loss confirmed; no transfer advantage to
  recover on this endpoint → GPU expiMap retrain DEFERRED (would at best match raw here).
- Gate 2: hold for an unseen-entity task; the two cheap gates saved an underdelivering GPU run.
