# Fuller 9B concept-CPT — launched on the spark box (DGX GB10)

**Date:** 2026-10-05 · Continues `20261005_9B_CONCEPT_CPT_EVAL_CORRECTED.md` (bounded run gave +4.4pp
knowledge_recall → direction positive → scale it up). Running on the user's **spark machine**
(`spark-d816`, NVIDIA GB10, 128 GB unified, aarch64, CUDA 13, driver 580.95).

## Review note (pre-launch, per "review before expensive runs")
- **What it does:** CPT (LoRA 4-bit QLoRA) on the 593M-token concept mix (391,975 docs) + FineWeb-Edu
  replay 0.3 → merge → base_domain → SFT 500 steps on the 72k-row concept SFT set → sft adapter.
  Runner: `~/biomate-onprem-train/run_fuller.sh` (chained, local checkpoints, **no S3 dependency** — spark's
  AWS keys are dead, so corpus/base/replay were staged from the Mac's S3).
- **Recipe (matches the validated 2026-10-03 9B run, just more CPT steps):** bs1, grad-accum 4,
  seq 2048, lora-r 16, lr 1e-4 cosine. CPT **1200 steps** (4× the bounded 300) vs the prior run.
- **Conditions satisfied:** venv transformers 5.18.0 / trl 1.14.1 / peft 0.21.2 / bitsandbytes 0.50.2 on
  boltzft torch 2.14.1+cu130 (CUDA True); base Qwen3.5-9B pinned rev `c2022362…`; concept mix + SFT +
  replay staged; **the corrected grader (`eval_today.py`) is on the box**.
- **Measured step time:** 24.6 s/it at grad-accum 4 (→ CPT ~8.2 h, + merge + SFT ~3.5 h ≈ **~12 h**).
- **Predicted outcome:** CPT loss ~2.3→~2.0 decreasing (as bounded run); a larger knowledge-recall lift
  than the bounded +4.4pp if more concept exposure helps (the hypothesis under test).

## Two env fixes required on GB10 (root-caused, not worked around)
1. **4-bit load offloaded to CPU under `device_map="auto"`** because nvidia-smi reports GB10 unified
   memory as "Not Supported" → accelerate mis-estimated GPU RAM. Fix: launch via
   `python -m torch.distributed.run --standalone --nproc_per_node=1`, which sets LOCAL_RANK → the
   trainer's intended single-GPU `device_map={"":0}` (full model on the GPU). No code edit.
2. **Qwen3.5 is a hybrid-attention model** → needs `flash-linear-attention` (installed, fla 0.5.2).
   `causal_conv1d` would not build on aarch64/cu13 → conv falls back to the reference PyTorch impl
   ("correct but slower"). Accepted; it is the only remaining slow kernel.

## Deviations from the prior run (flagged for honesty)
- conv1d reference fallback (no optimized kernel on aarch64) — correct, slightly slower.
- Otherwise same base + recipe + replay as the 2026-10-03 run; only CPT step count is larger (1200 vs 300).

## How to monitor / what's next
- Watch: `tmux attach -t cpt` on spark, or `tail -f ~/biomate-onprem-train/fuller.log` (tr '\r' '\n').
- Checkpoints: `~/biomate-onprem-train/out/med/fuller_20261005/{midtrain,base_domain,sft}/`.
- **Eval (after it finishes):** run the paired MCQA via the FIXED `eval_today.py` comparing the original
  base vs the new domainpro (base_domain + sft) — same 261-item frozen diagnostic — to measure the
  knowledge lift at 1200 CPT steps vs the bounded 300. The openbook eval needs the literature sqlite
  index; stage it from the Mac's S3 (`airgap/literature_identified_20261003/`) before eval.
- Feeds **Paper D** (the "full(er)-corpus CPT decision row" its Appendix C flags as pending GPU).
