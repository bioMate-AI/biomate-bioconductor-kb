# Qwen3.8-27B (on-prem, our served weights) — RealBio baseline

Measured by running the real RealBio harness (`run_baseline.py` + `score.py`) against our OWN
served base 27B (4-bit, OpenAI-compatible shim), same protocol as the dev Qwen3.8-Max row.
This supersedes all earlier ad-hoc/local routing evals.

| Task | Qwen3.8-27B (ours) | Qwen3.8-Max (dev) | note |
|------|--------------------|-------------------|------|
| routing — bare (direct, no candidates) | 0.180 | 0.345 | retrieval problem, not fine-tune |
| routing — catalog (candidates given) | **0.815** | — | with candidates → strong |
| autofix (fix-category acc) | **0.87** [0.79,0.92] | 0.860 | already strong — NOT weak-base |
| param_prefill (F1) | 0.664 (P 0.77 / R 0.58) | 0.692 | decent; **53 must_not_fill violations** = restraint gap |
| workflow_generation (category acc) | 0.500 | 0.500 | mid |
| protocol_thresholds (QC action acc) | 0.430 | 0.460 | mid |
| pbpk (within-2-fold) | 0.067 | 0.000 | simulation — LLMs can't; needs a tool |
| boin (exact MTD-mg) | **0.778** | 0.111 | strong (beats Max) |
| drug_discovery (Spearman) | 0.700 | 0.700 | knowledge task — already good |

## Honest conclusions (from real numbers, correcting earlier assumptions)
- Our 27B is **on par with Qwen3.8-Max** and beats it on boin/pbpk/autofix. "Won't be so low" — confirmed.
- **autofix (0.87), boin (0.778), dd (0.70), param (0.66), routing+candidates (0.815) are already strong** →
  NOT worth fine-tuning. My earlier "param/diagnosis are weak-base" assumption was WRONG.
- Genuinely low & actionable:
  - **routing-bare 0.18** → fix with the RETRIEVER (recall@20=0.95), not weight fine-tuning.
  - **param restraint** → 53 must_not_fill violations (over-filling) is a specific, fine-tunable weakness
    even though F1 is decent.
  - **protocol_QC 0.43 / workflow_gen 0.50** → mid; candidate targets.
  - **pbpk 0.067** → a simulation task; belongs to a tool the agent calls, not the LLM.

## Base vs SFT (routing-only LoRA) — on the real harness

| Task | Base | SFT (routing LoRA) | Δ |
|------|------|--------------------|---|
| routing bare | 0.18 | 0.17 | −0.01 |
| routing catalog | 0.815 | 0.795 | −0.02 |
| autofix | 0.87 | 0.80 | **−0.07 (negative transfer)** |
| param_prefill F1 | 0.664 | 0.646 | −0.02 (violations 53→49) |
| workflow_gen | 0.50 | 0.50 | 0 |
| protocol | 0.43 | 0.43 | 0 |
| boin | 0.778 | 0.833 | +0.05 (n=20, noisy) |
| dd | 0.70 | 0.70 | 0 |

### Root cause (critical): train/eval PROMPT-FORMAT mismatch
The routing LoRA was trained with our `routing_prompt.py` format (select-from-candidates, "reply with
ONLY the name"). The RealBio harness uses a DIFFERENT prompt (its own `instr` + no candidates in bare
mode). On its OWN matching format the LoRA showed +3pp (0.96→0.99, eval_routing_hf); on the harness's
format it gives **nothing and slightly hurts**, and single-task tuning caused **negative transfer**
(autofix −7pp). 

Lessons that reshape the fine-tuning plan:
1. To lift a task on the production/harness metric, TRAIN ON THAT EXACT PROMPT FORMAT (the harness
   `instr` strings / real BioMate prompts) — not a bespoke format. "train==eval" must mean the eval we
   actually report.
2. Single-task LoRAs cause negative transfer → must train JOINTLY across the task cluster with a
   balanced mixture (and keep base-format examples to preserve untuned tasks).
3. The current routing LoRA is NOT shippable; rebuild data in the harness/production formats.
