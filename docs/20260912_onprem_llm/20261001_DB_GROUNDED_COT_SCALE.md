# DB-Grounded CoT + SFT at Scale (v8)

**Date:** 2026-10-01
**Context:** The A1 CoT-distillation (`build_cot_distill.py`) was distilling from the tiny
`multitask_sft_v5` seed set capped at 250/task, yielding only **303 traces** at a 20% keep
rate — the keep rate was ceilinged by our *weak generative-task gold*. The fix: use the full
**enriched workflow DB** (4200 workflows, 12k tools) as a **grounded-by-construction** seed
source with **deterministic gold**, generating training data at scale.

## What changed

### 1. `build_db_grounded.py` — grounded SFT seeds from the real DB (NEW, free, no LLM)
Traverses all 4200 workflows and emits SFT seeds whose gold is read directly from real,
populated DB fields — no LLM, no weak gold, fully reproducible:

| Task | Gold source (DB field) | Seeds |
|------|------------------------|------:|
| `workflow_routing` | `name` (vs real domain-sibling candidates, open-book) | 1800 |
| `tool_recommendation` | `tools_used` | 1800 |
| `dataset_prerequisite_check` | `input_types` | 1800 |
| `parameter_extraction` | `params_schema` keys | 1800 |
| `task_decomposition` | `step_metadata[].step` (ordered) | 1800 |
| **Total** | | **9000** |

Field population (of 4200): description 4200, input_types 3804, output_types 3276,
params_schema 3058, step_metadata 3152, tools_used 2565. (`step_metadata` uses the key
`step`, not `name`/`tool` — the first pass missed it and emitted 0 decomposition seeds;
fixed.)

### 2. `build_cot_distill.py` — `--solo` + routing contract
- **`--solo`**: for *strong deterministic* gold, a single teacher (GPT-6 Solar) reaching the
  gold is sufficient — no dual-teacher consensus needed (that was only to bypass *weak* gold).
  Halves cost, doubles throughput.
- **`--tasks`** override of the HARD filter.
- **`workflow_routing` is the clean open-book CoT task**: candidates are in the prompt, gold is
  one of them, so the teacher reasons to a *correct* answer → high keep. (For
  param/tool/decomposition the gold is workflow-specific detail the teacher can't infer from the
  prompt → those stay plain grounded SFT, no CoT — the weak-gold trap in new clothes.)
- **`ask()` strips the embedded "Reply ONLY…" constraint** and forces ≥3 numbered reasoning
  steps. Without this, Solar obeyed the routing prompt's terseness instruction and returned the
  bare (correct) answer with *no trace* → 0% parse. After: **0% → ~98% keep**, with real
  comparative traces that rule out near-misses.

### 3. `run_sft_v7_9b.sh` — spot reclaim is no longer fatal
The 9B SFT kept dying `exit 4` on `shutting-down`. Root cause: a *single spot reclaim* was
treated as fatal by the wrapper, even though `spot_train.sh` mirrors checkpoints to S3 and is
resume-aware. Fix: **relaunch + resume from the S3 ckpt** (3h budget across relaunches).
Also fixed the cosmetic `${1:+od-}` label that printed `od-` for spot launches (`$1="0"` is
non-empty) — it kept falsely implying an on-demand launch. **Confirmed SPOT-ALWAYS is
respected**: `launch 0` → `ONDEMAND=0`; the no-capacity fallback is `exit 3 "no on-demand,
policy"`, never an on-demand launch.

## Results (keep rates)
- Routing CoT distill: **~98% keep** (100/1500 checkpoint: 98 kept) vs the old 20%.
- Grounded SFT: deterministic, 100% usable by construction.

## v8 composition (`assemble_v8.py`, exact-deduped, system turn normalized)
`multitask_sft_v8 = v5 (72,461) + db_grounded (9,000) + cot_routing (~1,470) + cot_generative (303)`
→ uploaded to `s3://…/20260912/sft/multitask_sft_v8.jsonl`.
*(final counts filled in on assembler completion.)*

## Next steps
1. v8 SFT run (4B + 9B) → eval v5 vs v7 vs v8 (F1, thinking on/off, latency): does DB-grounded
   data + routing CoT improve routing/tool/decomposition accuracy.
2. ADMET-CPT two-arm test (`build_admet_data.py`): CPT→SFT vs SFT-only — the "clock analog"
   where parametric knowledge priors should help (unlike retrieval-grounded routing).
3. Extend grounded CoT to `out_of_catalog_composition` (multi-workflow chains) once single-
   workflow routing CoT is validated.

## Files
- `evaluation/local_trial/build_db_grounded.py` (NEW)
- `evaluation/local_trial/build_cot_distill.py` (`--solo`, routing contract, trace-forcing)
- `evaluation/local_trial/assemble_v8.py` (NEW)
- `evaluation/local_trial/run_sft_v7_9b.sh` (relaunch-on-reclaim)
