# A1 — CoT-distillation stage: design & execution plan (2026-10-01)

Goal: distill strong-reasoner chain-of-thought into our small model for the hard generative tasks where the
F1 eval shows headroom — grounded on retrieved context, verified by reject-sampling. Produces v7; A/B vs v5.

## Teacher choice (corrected)
Distillation quality is bounded by the TEACHER's reasoning — so do NOT use a fast/cheap model (Gemini-3.8-flash)
as the teacher. Use the strongest reasoners, as a **DUAL-TEACHER**:
- **Claude Opus 5.5** (needs `ANTHROPIC_API_KEY` — currently missing locally; provision it) — exposes rich
  step-by-step reasoning.
- **GPT-6 Solar** (OpenAI) — second independent teacher. (Note: gpt-6-luna at high effort returned EMPTY earlier
  — reasoning tokens hidden; Solar is the exposed-reasoning variant to use.)
Why two: (1) **trace diversity** → the student generalizes over reasoning styles, not one teacher's quirks;
(2) **cross-verification** → a trace is higher-confidence when both teachers reach the same verified answer;
(3) **coverage** → keep verified traces from either teacher, so yield is higher after the reject gate.
Gemini-flash is relegated to the cheap VERIFIER/reviewer role (batched), not the teacher.

## Define each task clearly and correctly (per-task teacher contract)
Every contract: reason ONLY over the provided (retrieved) context; no external/hallucinated facts; end with a
VERIFIABLE final answer in a fixed format. The teacher gets {task-instruction + retrieved context + input}.
- **findings_interpretation**: "Given these analysis RESULTS and the retrieved domain facts, reason step by
  step to the KEY FINDINGS (what the results *mean* biologically). Interpret, don't restate. Every claim must
  trace to a given result/fact. Output: <reasoning> then FINDINGS." Verify: findings faithful to results (no
  causal overclaim — the faithfulness lesson).
- **conclusion_drawing**: "...reason to a CONCLUSION + implications/next-steps; do NOT assert causation beyond
  what the results support." Verify: no overclaim; grounded.
- **task_decomposition**: "Given the PROBLEM and the retrieved CANDIDATE workflows/tools, reason to an ORDERED
  plan; each step names a candidate (verbatim) or marks GENERATE." Verify: steps use real candidates; order valid.
- **out_of_catalog_composition**: "No single workflow fits. Reason to an ordered plan mapping each step to a
  candidate or GENERATE; ABSTAIN if truly infeasible." Verify: step/accept-set overlap + appropriate abstention.
- **parameter_extraction**: "Given the request + data context + the param SCHEMA (allowed-values, defaults),
  reason to ONLY the context-dependent param values; justify each from the request/data; leave the rest to
  defaults." Verify: values ∈ allowed-values; key-match vs gold.
- **tool_recommendation**: "Given the task + retrieved candidate tools, reason to the best-fitting tool(s),
  justified from their descriptions." Verify: tool ∈ catalog/candidates.
- **workflow_generation**: "Compose a workflow from existing steps; reason the composition and I/O wiring."
  Verify: steps real; I/O types connect.

## Pipeline
1. **Seeds** = existing v5 hard-task examples (carry context already) + the audited-clean recipe findings/decomp.
2. **Dual-teacher CoT** (Opus 5.5 + GPT-6 Solar), batched, per the contracts above. Forward mode (reason→answer);
   rationalize mode (given grounded gold, produce justifying reasoning) only as fallback for low-yield tasks.
3. **Reject-sample / verify** (the gate — non-negotiable): keep a trace iff its final answer matches the grounded
   gold (gold tasks) or passes the batched reviewer (open tasks). Train on NOTHING unverified (80%-contamination
   lesson). Dual-teacher: keep verified traces from either; mark "both-agree" as high-confidence.
4. **Format** (Qwen3 thinking): target = `<think>{verified trace}</think>\n{answer}`.
5. **Assemble v7** = v5 ∪ CoT hard tasks (uniform schema; `build_clean_sft.py` path). Per-task thinking policy:
   CoT ON for hard tasks; routing stays no-think/terse (base wins 0.94 there).
6. **Train** v7 — reuse `run_sft_v6.sh`→`run_sft_v7.sh` (STAGE=sft, base, SAME config as v5 for a clean A/B), SPOT-only.
7. **Eval** v7 vs v5 — reuse `build_eval_v6`/`eval_vllm` F1 on 17 tasks, **thinking-ON vs OFF**, record token/latency cost.

## Design decisions / risks / controls
- Teacher = strongest reasoners, dual; Gemini = verifier only. (Your correction.)
- Grounded-on-retrieval (doubles as A2) → knowledge stays swappable, traces don't hallucinate.
- Verify-before-train reject gate → only correct reasoning enters.
- Per-task thinking policy → no reasoning overhead where the base already wins (routing).
- F1 grader already de-biases CoT verbosity. Report thinking token cost next to accuracy.
- Ship v7 only if it beats v5 on hard-task F1 without wrecking routing/latency; else honest negative.

## Scripts (build 1, reuse 4)
- Build `build_cot_distill.py`: dual-teacher (Opus 5.5 + GPT-6 Solar) batched CoT per contract → reject-sample
  verify → `<think>` format. Teacher API keys via env (add ANTHROPIC_API_KEY).
- Reuse: `build_batch_review.py` (verify open-ended), `build_clean_sft.py` (assemble v7), `run_sft_v7.sh` (train),
  `build_eval_v6.sh`/`eval_vllm.py` (A/B eval, thinking on/off).

## Cost/time
Dual-teacher CoT over ~15–20k seeds (batched) ≈ a few hours + modest $ (Opus 5.5/GPT-6 Solar pricier than
gemini — justified for a one-time distillation pass); SFT on spot ≈ 2–4h; eval ≈ 20 min. Clean v5-vs-v7 in ~1 day.

## Prereq
Provision `ANTHROPIC_API_KEY` (missing locally) so Opus 5.5 can serve as teacher; confirm GPT-6 Solar model id.
