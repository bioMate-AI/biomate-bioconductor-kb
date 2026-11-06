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

---

## Results & status — 2026-10-03 (living; update each step)

### Model
| Milestone | Result | Notes |
|---|---|---|
| UniMoMo reproduce (LINEAR, LNR-93) | **DockQ 0.7754** vs published 0.759 (+0.016) | matched split/budget/oracle best-of-N; verifies the base + inherits its multimodal transfer-pretrain |
| UniMoMo base on CYCLIC test | DockQ **0.4029** | linear-trained base drops on cyclic (expected) |
| **Cyclic-specialization fine-tune (full 30 epochs)** | DockQ **0.4126 (+0.0097)** | run `unimomo-cyclic-ft-20261002T204906Z`; frozen IterVAE, warm-start from reproduced base, 616 cyclic complexes; same UniMoMo harness, oracle best-of-N, 100/target |

**Leakage audit (run 170124Z `split_audit.json`, 502 train / 55 val / 88 test):** test is **peptide-disjoint (0 shared peptide seqs), complex-disjoint (0 shared complex seqs), PDB-disjoint (0 shared IDs)** — the primary criterion for a *peptide co-design* benchmark is clean. Residual: **5/88 test complexes share a receptor sequence** with train (`4kel_B,5iop_E,5t1m_E,5t90_F,5th2_E`) — novel peptide on a seen pocket; a sensitivity caveat, not peptide leakage. Train/val share 17 peptide seqs (internal val only, not the reported test). **Before any generalization headline:** report the peptide-disjoint number (have it) + a receptor-disjoint sensitivity subset (exclude the 5); homology/pocket-similarity/pretraining-overlap remain unquantified.

### Closed loop (DBTL) — VERIFIED end-to-end (mechanics), not yet efficacy
Generator (UniMoMo-cyclic) → CRO synth+SPR → **KD → EXPERT pairs** (`wetlab_kd_to_pairs.py`, self-tested) → **DPO close-back** (`dpo_peptide_trainer.py` + `dpo_unimomo_adapter.py`) → retrain. Verified (codex, 2026-10-03): real UniMoMo CUDA DPO on the production assay service with **explicitly synthetic KD** — 7/7 checks (pairs loaded, optimizer updates, reference unchanged, frozen AE unchanged, 199 trainable tensors changed, exact checkpoint reload, finite weights); one-epoch training smoke 502/502 updates. CPU loop: DPO loss 0.693→0.659, reward margin 0→0.072. **All synthetic — validates wiring, not biology.** Gated on real wet-lab KD (CRO round being sent) for efficacy.

### Remaining experiments for the paper (priority order)
1. **Best-of-N + self-consistency ranker** (plan §3) — cheapest SOTA lever; still unrun. Generate N, re-fold, rank by scRMSD/ipTM; measure realistic-pick-1 + best-of-N DockQ lift on the cyclic test.
2. **Receptor-disjoint sensitivity** — recompute base-vs-FT excluding the 5 receptor-overlap complexes (needs per-target DockQ; re-run eval if not saved).
3. **Prospective wet-lab round** — CRO KD (round 1 sent) → feed the verified close-back → round-2 improvement = the closed-loop headline figure.
4. **Designability + binding-energy** metrics alongside DockQ; head-to-head vs PepGLAD-cyclic (0.506, *different harness* — needs one-harness comparison before any claim).

### Change log
- 2026-10-02: reproduce 0.775; cyclic-FT pipeline built; DPO close-back + UniMoMo port; KD→pairs link.
- 2026-10-03 (codex): closed-loop verified end-to-end on real model (synthetic KD); leakage audit; hardening (40 tests); full 30-epoch cyclic-FT completed (0.403→0.413).
