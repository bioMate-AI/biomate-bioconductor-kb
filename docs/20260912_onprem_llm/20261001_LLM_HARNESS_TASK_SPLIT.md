# LLM vs Harness: The Task Split (evidence-driven)

**Date:** 2026-10-01
**Trigger:** "what is the task set after assigning llm and harness respectively" + "routing is
two-staged, isn't the second stage with just a short list after retrieval easy? why you always
just use it" + "you have changed the training datasets and tasks, why the evaluation not updated".

## The evidence that forces the split

Full 17-task objective eval (`eval_arms_vllm_full_f1.json`, salient-F1 / accept_set / mcqa),
sorted by sft_v5 score:

| Task | base | sft_v5 | verdict |
|------|-----:|-------:|---------|
| workflow_routing | **0.940** | 0.867 | **base already solves it; SFT HURTS** |
| design_constraint | 0.354 | 0.732 | learnable |
| knowledge_recall | 0.300 | 0.660 | learnable (knowledge) |
| parameter_extraction | 0.291 | 0.528 | learnable (reasoning part) |
| scientific_qa | 0.187 | 0.480 | learnable (knowledge) |
| model_selection | 0.117 | 0.458 | learnable |
| log_diagnosis | 0.268 | 0.455 | learnable |
| tool_recommendation | 0.303 | 0.410 | partial |
| autofix_repair | 0.190 | 0.402 | partial |
| dataset_prerequisite_check | 0.206 | 0.361 | partial |
| clarification_request | 0.370 | 0.360 | **stuck — SFT flat** |
| lane_arbitration | 0.103 | 0.348 | hard |
| multi_workflow_chaining | 0.228 | 0.304 | hard |
| task_decomposition | 0.222 | 0.294 | hard |
| findings_interpretation | 0.172 | 0.286 | hard |
| workflow_generation | 0.214 | 0.280 | hard |
| **out_of_catalog_composition** | 0.124 | **0.099** | **hardest — SFT HURTS** |

**Two tasks where the base model is already near-ceiling or SFT backfires (routing 0.94;
out-of-catalog SFT −0.025) bracket the whole lesson:** effort should flow to the *middle and
bottom* of this table, never the top.

## Why routing is the wrong thing to train (the two-stage argument)

Routing is **two-staged**:
1. **Stage 1 — retrieval.** Dense cosine resonance over the 4,200-workflow catalog → a short
   candidate list. This is the **harness's** job (`UnifiedWorkflowSearch` / lane arbiter). It is
   recall over a huge, volatile corpus — exactly what a small LLM should NOT hold in weights.
2. **Stage 2 — pick from the short list.** Given 5–7 candidates in the prompt, name the best.
   This is **grounded-by-construction** (the answer must be one of the provided candidates; the
   `grounded_pick` primitive enforces it) and the **base model already scores 0.94** on it.

So stage-2 routing is easy *and* already owned by the harness boundary. Distilling CoT for it
(my v8 did, 1,468 traces @ 98% keep) teaches a solved task. **High keep rate was a symptom that
the task was easy, not a sign the data was good.** The only routing slice with LLM value is
genuine **disambiguation** (two candidates both plausible) — a thin sub-case, not 1,468 traces.

## The assignment

### Harness owns (deterministic / retrieval / execution / numeric / volatile)
- **Stage-1 retrieval** (routing candidate generation, tool search) — dense vectors, not weights.
- **Stage-2 grounded pick** on a clean short list — `grounded_pick` (reject off-catalog).
- **Parameter validation** against `params_schema.allowed_values` (guardrail, drop/normalize).
- **Deterministic extraction RULES** (per CLAUDE.md): unit conversion (ns→n_steps, fs→dt),
  negation, boolean flags (single-end→true), canonical aliases (human→GRCh38). Zero-cost, exact.
- **Execution** on AWS Batch, programmatic output checks, QC gates, run-state persistence.
- **Knowledge retrieval (RAG)** — facts fetched into the prompt, not recalled from weights.
- **Verification** — majority_vote / verified_sample / consensus (the VerificationLayer).

### LLM owns (judgment under ambiguity — irreducible to retrieval or rules)
Ranked by where the gap is (low score = high opportunity):
1. **out_of_catalog_composition** (0.099) — nothing in the short list fits → compose a plan from
   primitive steps, or ABSTAIN. The anti-hallucination judgment.
2. **findings_interpretation / conclusion_drawing** (0.286) — turn result numbers into meaning.
3. **workflow_generation** (0.280) — wire steps with correct I/O.
4. **task_decomposition / multi_workflow_chaining** (0.29–0.30) — ordered multi-step plans.
5. **lane_arbitration** (0.348) — resolve disagreement between the 3 classifiers.
6. **clarification_request** (0.360, stuck) — decide WHEN to ask and WHAT to ask vs. proceeding.
7. **parameter_extraction — the reasoning half** (0.528) — context→which values (after rules do
   conversions/flags). The LLM infers "paired-end dUTP mouse" → strandedness=reverse, genome=GRCm39.
8. **tool_recommendation** (0.410), **model_selection**, **design_constraint** — fit reasoning.
9. **Knowledge tasks** (knowledge_recall 0.66, scientific_qa 0.48) — RAG-assisted; only *stable*
   facts go to weights (scoped CPT), volatile facts stay in retrieval.
10. **disambiguation** — the thin hard slice of routing (NOT the easy pick).

## Consequences (what changes)

1. **Stop scaling routing CoT.** Keep a small routing set as a regression guard only. Redirect
   the distillation budget to tasks 1–6 above.
2. **Hard-task CoT must be OPEN-BOOK** — the same trick that made routing keep high, applied
   where it matters: put the *retrieved context* (candidate steps, result numbers, schema+a
   realistic scenario, the classifier votes) in the teacher's prompt so it reasons to a reachable,
   checkable gold. Closed-book hard-task distillation fails because the teacher can't invent the
   workflow-specific gold (that was the 20% keep ceiling).
3. **Eval reads per-task, not macro.** Macro is dominated by the easy high-scorers; v6 "0.42 vs
   0.429" looked flat because the hard tasks barely moved under the noise of the easy ones. The
   scorecard must headline the **hard-task subset** (tasks 1–6) and track routing only as a
   "still ≥0.9?" guard. The eval SET (`objective_eval.jsonl`) already covers all 17; what was
   stale was *how I read it* (macro) and *what I trained for* (easy tasks).
4. **Midtrain/CPT stays scoped.** `mid500` scored 0.26 ≈ base 0.27 — midtrain does NOT help these
   retrieval-grounded tasks (confirms the KEY RULE). CPT is reserved for the quantitative-prediction
   "clock analog" (ADMET/PBPK/BOIN), not for routing/QA.

## Next (v9, redirected)
- Build **open-book hard-task CoT** for out_of_catalog_composition, findings_interpretation,
  task_decomposition, lane_arbitration, clarification_request — gold constructed to be checkable
  (e.g. out-of-catalog: candidates deliberately missing the needed step → gold = compose-or-abstain;
  findings: real result table → gold = the salient interpretation; decomposition: real step_metadata
  as the plan but with the WORKFLOW HIDDEN so it's genuine planning not recall).
- Re-run the 17-task eval, report the **hard-task macro** as the headline metric.
- v8 (routing-CoT-heavy) finishes as a datapoint but is NOT expected to move the hard tasks.
