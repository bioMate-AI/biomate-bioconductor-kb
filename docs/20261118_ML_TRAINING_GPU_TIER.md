# ML Training — GPU tier for real LLM fine-tuning (DPO / GRPO)

**Goal:** run LLM preference-optimization (DPO) and RL (GRPO) adaptation on *real*
models (1–7B+) on GPU, instead of the current CPU path (SmolLM2-135M only). This is
the "too limited ML/DL" depth lever. The pattern already works for **diffusion**
(CUDA image + `process_gpu` → GPU Batch queue); this mirrors it for TRL/LLM.

## ✅ Code half — DONE + tested (this commit), OFF by default (safe)
- `ml_training/routing.py` → `nextflow_path_for` routes `trl_dpo`/`trl_grpo` to the GPU
  wrapper **only when `ML_TRAINING_GPU_LLM=1`**; otherwise the verified CPU path
  (`chemprop_train.nf`). Unit-tested (`test_routing.py::test_llm_gpu_tier_is_opt_in`).
- `biomni_workflows/nextflow_nfcore/ml_training/trl_train.nf` — the GPU wrapper
  (`label 'process_gpu'`; identical CLI wiring to chemprop_train.nf).
- `ml_training/trl_trainer.py` — precision now follows the hardware (`_use_bf16()` →
  bf16 on CUDA, fp32 on CPU) instead of hard-forcing fp32.

**Nothing changes until the flag is set**, and the flag must not be set until the
infra below exists, or jobs route to a GPU wrapper with no CUDA image / unsized queue.

## ⚙️ Infra half — TODO (your cost + AWS decision)
1. **Build the CUDA trl-training image** (CI: `.github/workflows/trl-training-image.yml`).
   Mirror `backend/docker/diffusion-training.Dockerfile` — change
   `backend/docker/trl-training.Dockerfile`:
   - `FROM python:3.10-slim` → `FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04`
     (or the 11.8 base the diffusion image uses), add `python3.10`/`pip` install.
   - CPU torch (`torch==…+cpu`) → a CUDA wheel (`torch==2.3.1 --index-url
     https://download.pytorch.org/whl/cu121`), keep trl/peft/transformers pins.
   - Push as a distinct tag (e.g. `biomate/trl-training-gpu:latest`) — keep the CPU
     tag so the default CPU path is unaffected.
2. **Executor image selection:** in `ml_training/executor_payload.py`
   (`_resolve_container`) / `nextflow_executor.py` container auto-select, pick the
   CUDA tag for `trl_dpo`/`trl_grpo` **when `ML_TRAINING_GPU_LLM=1`** (else the CPU tag).
3. **GPU Batch queue sized for the target model.** The existing `biomate-gpu-spot-queue`
   is small (~8 vCPU / 32 GB, L4-class from the diffusion/cryo-EM world). A 1–3B LoRA
   run fits a single 24–48 GB GPU (g5/g6/L4/A10); 7B+ needs 40–80 GB (A100/H100) and is
   not yet provisioned. Add a sized GPU CE/queue (Terraform `gpu_compute_env` is a named
   gap in `infra/terraform/README.md`) and map `process_gpu` → it in `nextflow_executor`.
4. **Flip it on:** set `ML_TRAINING_GPU_LLM=1` on the dev `biomate-galaxy-dev` container.
5. **Verify (ONE small run):** a SmolLM2-135M or ~1B DPO run on GPU end-to-end — confirm
   it lands on the GPU queue, the CUDA image loads, `bf16=True`, and it registers a model
   version. Do NOT skip straight to a 7B run; validate the path cheap first.

## 💲 Cost note
GPU Batch time is billed per GPU-hour, and larger-VRAM instances (A100/H100) are
materially more expensive than the current CPU/L4 path. Enabling this is a deliberate
spend decision — hence the opt-in flag and "validate small first" step. Per CLAUDE.md
("no speculative GPU runs"), the code is ready but no GPU job runs until you choose to.
