# PepGLAD run diagnosis — why AAR is low (config, not ceiling)

Run `pepglad-long-20260913T222203Z` (AE 40 / LDM 80 epochs). Held-out validation generation
was weak (LDM val AAR ~0.06, Cα-RMSD ~13 Å). Diagnosis from SSM inspection of the live
instance: **the autoencoder is healthy; the latent diffusion model is undertrained relative to
the published recipe.** This is a config/compute limit, not an architectural ceiling.

## Per-stage metrics (TensorBoard, this run)
- **Autoencoder — good.** Validation **reconstruction AAR ≈ 0.72**, Cα coord loss ≈ 0.27. The
  latent space encodes peptides well; the representation is not the bottleneck.
- **Latent diffusion — weak.** Val AAR ≈ 0.064, Cα-RMSD ≈ 13 Å, with a large train/val gap
  (train Struct/Loss_X → 0.018 vs val 1.20; train Seq/Loss_H best 0.82 vs val 1.61).

## Our bounded config vs PepGLAD upstream defaults
| Param | Upstream default | This run | Effect |
|---|---|---|---|
| **LDM `max_epoch`** | **500** | **80** | 6× under-trained — primary cause |
| **`ubound_per_batch`** | **60000** | **30000** | half the effective (dynamic) batch size |
| AE `max_epoch` | 100 | 40 | fine — AE converged (72% recon) |
| AE train datasets | list of 2 (incl. ProtFrag aug) | 1 (no ProtFrag) | AE-only augmentation; AE is fine regardless |
| `save_topk` | 10 | 3 | irrelevant to quality |
| `grad_clip` | none | 1.0 | minor |
| `num_workers` | 4 | 0 | throughput only |

## Verdict
- The all-atom **representation works** (AE 72% reconstruction). The weak generation is the
  **latent-diffusion prior being trained 6× less than published (80 vs 500 epochs)** plus a
  halved batch — an explainable, fixable config/compute limit, not evidence of a ceiling.
- The during-training val AAR uses fast sampling and may **understate** true generation; the
  calibrated full-sampling benchmark is the real number.

## Recommended next run (publication-matched, still bounded)
- LDM `max_epoch`: raise substantially toward the published 500 (e.g. 300–500) — this is the
  main lever. At ~100 s/epoch on the A10G, 300 epochs ≈ 8–9 h → needs a longer deadline and
  Spot-resume, or a bigger/faster GPU.
- `ubound_per_batch`: restore to 60000 (fits A10G 24 GB; verify no OOM).
- Keep AE at ~40–100 epochs (already converged); optionally re-add ProtFrag augmentation.
- Then re-run the calibrated validation benchmark and compare AAR/RMSD to PepGLAD's paper
  before any claim.
