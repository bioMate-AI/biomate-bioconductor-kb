# 2026-11-15 — Protein diffusion TRAIN executable path

**Scope:** Make explicit “fine-tune / train protein diffusion” requests runnable on
`biomate/diffusion-training` (not ignore NotImplementedError). Design/fold routing
stays a separate track.

## Root cause

Three stacked gaps — not one:

1. **Trainer skeleton after import.** `diffusion_trainer._train_rfdiffusion` raised
   `NotImplementedError` even when `torch` + `rfdiffusion` imported (“training driver
   is provisioned by the GPU image entrypoint, not this skeleton”). So the
   diffusion-training image still failed TRAIN.
2. **Wrong container on chat Confirm & Run.** `nextflow_executor` fallback for
   `ml_training/*` only special-cased TRL vs Ludwig. Without
   `compute_config.container`, `protein_diffusion` landed on
   `biomate/ml-training:latest` (no rfdiffusion) → same NotImplementedError.
3. **Weights not in the image.** Dockerfile installed RFdiffusion but deferred
   `Base_ckpt.pt` / `Complex_base_ckpt.pt` to run-time / “design doc §deferred”.

ECR already had `biomate/diffusion-training:latest` (~5.1 GB, tag `sha-b0eaaa51be4b`,
2026-11-09) — image existence was not the blocker; wiring + driver + weights were.

Open RosettaCommons/RFdiffusion ships **inference only** (`scripts/run_inference.py`).
There is no public SE(3) weight-update loop. BioMate therefore executes
**warm-start checkpoint + conditioned design** for `finetune=True`, and records
only metrics from real design outputs (`n_designs`, `mean_plddt`, `ca_rmsd_to_ref`
→ `scrmsd` for gating). It does **not** fabricate `train_loss`. `finetune=False`
(from-scratch) still raises a clear `NotImplementedError`.

## Fixed in this diff

| Piece | Change |
|-------|--------|
| Trainer | Weight staging (`ensure_rfdiffusion_weights`), real `run_inference.py` driver, honest metrics / extras |
| Executor | `resolve_ml_training_container(model_type, nf_path)` used when container missing |
| Routing | `route_ml_training` attaches `compute_config.container` (diffusion-training) |
| Dockerfile | Bake Base + Complex ckpts into `/opt/RFdiffusion/models`; set `DIFFUSION_WEIGHTS_DIR` |
| CI | Sparse checkout (mirror tabular); smoke asserts weights + `run_inference.py` |
| Tests | Weight ensure, from-scratch refuse, finetune-with-mocks, path-based container |

**Files:** `diffusion_trainer.py`, `executor_payload.py`, `routing.py`,
`nextflow_executor.py` (container fallback only), `diffusion_train.nf` (comment),
`diffusion-training.Dockerfile`, `.github/workflows/diffusion-training-image.yml`,
`tests/test_diffusion.py`.

## Still needs on DEV

1. **Rebuild + push** the diffusion-training image so weights are baked and the
   new trainer code is in the image COPY layer:
   ```bash
   git tag diffusion-training-v3   # or next free tag
   git push origin diffusion-training-v3
   # → .github/workflows/diffusion-training-image.yml
   ```
   Or `gh workflow run diffusion-training-image.yml` once the workflow is on the
   default branch.
2. **Sync** Galaxy + workflows so executor fallback + trainer land on DEV.
3. **Optional remasure:** prompt `fine-tune a protein diffusion model for FcRn binders`
   with a real PDB structure set (not `*_constraints.json`) — expect TRAIN in
   `…/biomate/diffusion-training:latest`, designs under artifact, no fabricated
   `train_loss`.

Until the image rebuild, an already-pulled `:latest` has rfdiffusion but **no**
baked weights; the trainer will try `files.ipd.uw.edu` at run time (needs egress).

## Verify (local)

```bash
cd backend && PYTHONPATH=lib python3.9 -m pytest \
  lib/galaxy/ai/ml_training/tests/test_diffusion.py -q
# container helper
PYTHONPATH=lib python3.9 -c "
from galaxy.ai.ml_training.executor_payload import resolve_ml_training_container
assert 'diffusion-training' in resolve_ml_training_container(model_type='protein_diffusion')
assert 'diffusion-training' in resolve_ml_training_container(nextflow_path='ml_training/diffusion_train.nf')
print('ok')
"
```

## Non-goals / do not regress

- Do **not** re-arm bare design/fold prompts into TRAIN (routing track).
- Do **not** touch pep-3 / flow-cyto / gromacs paths.
- Do **not** invent training metrics when inference fails.
