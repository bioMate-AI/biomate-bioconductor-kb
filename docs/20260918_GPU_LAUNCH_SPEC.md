# GPU Launch Spec — On-Prem BioMate LLM (two-model: small + ~27B)

**2026-09-18.** Everything runnable on the laptop is done (data, paraphrase diversity, contrastive
retriever, eval hardening). This spec is what to fire on a GPU box to produce trained models.

## 0. Why two models — controlled capacity comparison

Train the *identical pipeline on the identical data and all 11 tasks* at two capacities, so the
**only variable is model size**. We do NOT pre-assign tasks to a model — both models see the full
enriched SFT set and are evaluated on every task.

| | Small | Large |
|---|---|---|
| Base (same family → shared tokenizer/chat template) | `Qwen/Qwen3.8-4B` | `Qwen/Qwen3.8-27B` |
| Training data | **the full 17k enriched set, all 11 tasks** | **the same full 17k enriched set, all 11 tasks** |
| Fits on | 1× L40S 48GB (QLoRA) | 1× A100/H100 80GB (QLoRA) |

**What the comparison answers (post-hoc, not pre-decided):** for each task, how far does the small
model close the gap to the large one? Only *after* seeing per-task deltas do we decide any
deployment split — e.g. whether a **cascade** (small attempts, escalates to large on low confidence
/ hard cases) is worthwhile, or whether one model suffices. Both share the contrastive retriever.

The two models differ only in base checkpoint and size-appropriate capacity knobs (LoRA rank; the
large model gets a larger step budget to reach convergence). The *dataset, task mix, prompts,
holdout, and eval are identical*.

## 1. Instance & AMI

- **AMI:** AWS Deep Learning Base GPU AMI (Ubuntu). *Ubuntu 24.04 has no `awscli` apt package —
  install AWS CLI v2 from the official zip* (handled in `gpu_bootstrap.sh`).
- **Instance profile:** `AutoimmuneCorpusProfile` (S3 read/write to `biomate-models-...`), not
  `biomate-core-trial`.
- **Scratch:** `/opt/dlami/nvme` (fast local NVMe; base weights + checkpoints).
- **Instance types:**
  - Small model: `g6e.xlarge` (1× L40S 48GB) — cheapest that holds 4B QLoRA at seq 2048.
  - Large model: single A100/H100 80GB (e.g. via `p4de`/`p5` family, 1 GPU used) — 27B QLoRA in
    4-bit ≈ 14GB weights + activations; 80GB is comfortable, 40GB is tight.
- **Rough cost:** the prior 27B SFT was 200 steps ≈ 2.2 h. A full large run (mid-train 800 +
  SFT 600 + eval) ≈ 8–12 GPU-hours; small run ≈ 3–5. Budget one long day of a single 80GB GPU +
  a few hours of an L40S. (Confirm live pricing before launch.)

## 2. Run order

```bash
# on the GPU box, in evaluation/local_trial/
bash gpu_bootstrap.sh                       # AWS CLI v2, deps, pull data+retriever from S3

# STAGE 0 (cheap, do FIRST): re-eval the existing 27B adapter with the FIXED harness to confirm
# the 20260914 "0.0 delta everywhere" was purely the eval artifact, not a training failure.
aws s3 cp s3://.../20260912/sft_27b_20260914/ ./adapter_old --recursive
python3 eval_holdout.py --base <base27b> --adapter ./adapter_old \
  --holdout /opt/dlami/nvme/data/holdout.jsonl --out eval_old.json
#   -> the startup logit-probe now FAILS LOUD if the adapter is a no-op; otherwise you get a real delta.

MODEL_SIZE=small bash gpu_run_pipeline.sh   # mid-train -> merge -> SFT -> merge -> eval -> upload
MODEL_SIZE=large bash gpu_run_pipeline.sh
```

Each `gpu_run_pipeline.sh` does: mid-train (packed, all-token loss) → **merge** → SFT on the 17k
enriched set (assistant-only loss) → **merge** → **two-server eval** (base vs final under vLLM, no
adapter-toggle ambiguity) → upload adapter + eval json to
`s3://.../20260912/models_20260918/{small,large}/`.

## 3. Mid-train ratio sweep (committee item)

The domain-vs-general replay ratio is a hyperparameter, not a fixed 25/75. Sweep on the **small**
model first (cheap) to pick the ratio, then apply the winner to the large model:

```bash
for FRAC in 0.0 0.75 0.4 0.2; do   # 0.0 = no general replay ; else general fraction
  python3 midtrain_run.py --base $BASE --data midtrain_all.jsonl \
     --replay general_replay.jsonl --replay-frac $FRAC --out out/mid_$FRAC --max-steps 300
  # then short SFT + eval; compare holdout deltas
done
```
Requires a staged `general_replay.jsonl` (FineWeb-Edu / The Stack / Wikipedia sample) — fetch on the
box (has disk + bandwidth). Pick the ratio that maximizes held-out task delta without regressing a
small general-knowledge probe (anti-forgetting check).

## 4. Grounded RL / DPO (stage 4, after SFT)

Design (script `train_dpo_grounded.py`): sample pairs from the SFT model on routing/param/diagnosis
prompts; **reward = schema validity + execution success** (does the extracted param set satisfy the
workflow schema? does the routed workflow accept the inputs? does the proposed fix resolve the error
category?). Chosen = higher reward, rejected = lower. DPO is contrastive at the generation level —
the same principle as the retriever's InfoNCE, one level up. Run on the large model; optionally the
small model to sharpen its abstention.

## 5. Holdout discipline

Use **family/temporal** holdouts, not random splits: hold out whole workflow families and the most
recent studies, so the eval measures generalization to unseen workflows/phrasings rather than
memorization. Build `holdout.jsonl` (schema: `{benchmark, input_item, ground_truth}`) from the
labeled pool before training and stage it beside the SFT set in S3.

## 6. Artifacts this consumes / produces

- **Consumes:** `sft/multitask_sft_enriched.jsonl` (17,291), `midtrain_corpus/midtrain_all.jsonl`
  (~37M tok), `retriever/bge-routing-contrastive/`.
- **Produces:** `models_20260918/{small,large}/sft_adapter/`, `eval_{small,large}.json`, and
  (optionally) merged `final/` models for serving.

## 7. Open dependencies (need the box's disk/bandwidth)

- `general_replay.jsonl` for the mid-train sweep.
- nf-core `nextflow_schema.json` fetch for real if/then conditional-parameter SFT.
- `holdout.jsonl` family/temporal split staged to S3.
