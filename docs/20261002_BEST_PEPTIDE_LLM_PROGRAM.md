# Best Peptide LLM — SOTA-Beating Program (non-incremental) + Eval-over-Existing-Works + Fast Workflow

**Date:** 2026-10-02 · **Mandate (user):** build the *best* peptide binder generator — **not** incremental
M2c-plus-more-cyclic-data. We know the challenges and the SOTA to beat; adopt the recipe that actually beats
it, evaluate rigorously vs **all** existing works, and win on the real bar (wet-lab). Grounds on
`20261001_CYCLIC_PEPTIDE_SOTA_LANDSCAPE.md` + the existing eval scripts (`official_eval.sh` PepBench,
`cyclic_official_eval.sh`/`cyclic_benchmark_eval.sh` PepBDB-cyclic).

## 1 · Eval-over-existing-works — the benchmark framework (what we must beat)
*The field does NOT compete on co-design DockQ alone; we track the full set, DockQ only as a fast dev-check.*

| Benchmark | Metric | **SOTA to beat** | Our current standing |
|---|---|---|---|
| PepBench (linear) | DockQ (conf-gen) | **RADiAnce ~0.77 · UniMoMo ~0.759** (2025) | repro 0.512 (n=10) |
| PepBDB-cyclic | DockQ (co-design) | PepGLAD **0.403** | cyclic-FT 0.506; base-vs-current eval RUNNING |
| any | **AAR / RMSD(CA)** | D-Flow AAR 0.59 / RMSD 1.63 | M2c 0.23 / 4.6 (our hard split) |
| any | **Designability** (self-consistency scRMSD) | the Baker-lab gate | not yet tracked ← add |
| any | **Binding energy** (Rosetta/FEP ΔG) | CpSDE / RFpeptides | MM-GBSA ΔG (have) |
| **wet-lab (the real bar)** | **hit-rate, Kd** | **RFpeptides 21–38%, Kd 1–10 µM** | round-1 loop being ordered |

Commit to reporting **all six** per model version, on the SAME benchmark at matched sampling — no more
phantom cross-benchmark comparisons.

## 2 · The non-incremental architecture — how SOTA (0.59→0.77) was actually won
From the verified landscape, the levers that moved the number (NOT raw cyclic data — that's low-hundreds):

1. **Unified multimodal cross-domain transfer pretraining** (UniMoMo recipe) — ONE generator pretrained over
   **peptides + antibodies + small-molecule** complexes, then specialized. This is the real data lever (and
   exactly the "all peptides, not just cyclic" intuition). Sources: the broad peptide mine (have, ~11k),
   **SAbDab** antibody–antigen, **PDBbind** protein–ligand.
2. **Co-folding structure prior** — condition on / distill a co-folder. **We already have BoltzGen** (Boltz-based).
3. **Self-consistency ranker + best-of-N** — generate N, re-fold (AF2/Boltz), rank by scRMSD/ipTM, keep best.
   Cheapest high-impact lever; this is what RFpeptides/HighFold/AfCycDesign do.
4. Full-atom + flow/diffusion (have) → then **cyclic fine-tune** for the ring constraint.
5. **Close the wet-lab loop (DPO on measured binders)** — the moat AND the real-SOTA (hit-rate) game.

**= a unified multimodal co-design generator + self-consistency ranker + best-of-N, cyclic-specialized, in the
wet-lab loop.** NOT "M2c + 662 cyclic complexes."

## 3 · Fast workflow (the #1 ask — kill the per-job tax)
The slowness has been **launch → cold-install → spot-hunt → terminate, per job**. Fixes:
1. ✅ **Pre-baked AMI** (`ami-06e366a5b89d12344`) — runs start in seconds, not ~10-min installs.
2. **Persistent warm GPU dev box** — keep ONE on-demand GPU up for the whole dev loop; iterate train/eval/rank
   in minutes instead of relaunching + capacity-hunting each time. **This is the biggest single speedup.**
3. **One orchestrated pipeline** (mine→process→pretrain→finetune→eval→rank) as a cached DAG — not N manual
   launches; skip recompute.
4. **Durable cloud + parallel** — never local-background (it dies on session restart; lost the mine twice).

## 4 · Execution order
1. **(running)** honest baseline — base vs current on PepBDB-cyclic vs PepGLAD 0.403 (+ retrain data-lever).
2. **Persistent warm dev box** (speed) + the orchestrated pipeline.
3. **Self-consistency ranker + best-of-N** — cheapest SOTA lever; measure DockQ/designability lift immediately.
4. **Unified transfer corpus** (peptide ∪ antibody ∪ small-molecule) → transfer-pretrain → cyclic fine-tune.
5. **Eval vs all SOTA** on the §1 framework, matched sampling.
6. **Wet-lab loop** (DPO) — the real-SOTA hit-rate bar.

## Honesty contract
- No phantom cross-benchmark claims (the 0.592 lesson). Every number on the same benchmark, matched n, vs the
  named SOTA. The real bar is **wet-lab hit-rate** (RFpeptides), DockQ is a dev-check.
- "Best" is measured against existing works on this framework, not asserted.
