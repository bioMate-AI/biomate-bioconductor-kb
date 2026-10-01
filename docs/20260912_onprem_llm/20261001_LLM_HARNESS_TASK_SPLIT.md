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

## What the harness CAN complement vs CANNOT (the decisive cut)

A weak LLM is rescued by the harness **iff the task reduces to one of three shapes** the harness
can supply deterministically:
- **(S) selection from a retrieved set** — retrieval puts the answer in the prompt; the LLM picks.
- **(R) a deterministic rule** — no LLM needed at all.
- **(V) a cheap programmatic verifier** — sample k, keep the first that passes (`verified_sample`).

If none of those apply — **open-ended generation, no retrieval answer, no cheap verifier** — the
harness can only *reject* a bad output, never *produce* a good one, so **output quality = LLM
quality** and a 4B is genuinely, un-rescuably worse than frontier.

### Harness CAN carry (LLM choice ≈ irrelevant → use the cheapest on-prem model)
| Task | Mechanism | Why it works |
|------|-----------|--------------|
| workflow_routing | S + grounded_pick | base already 0.94; retrieval+pick do it |
| parameter_extraction (conversions/flags/aliases) | R + schema validation | exact, zero-LLM |
| dataset_prerequisite_check | S (DB `input_types`) | it's a stored fact |
| tool_recommendation | S + grounded_pick | pick from retrieved real tools |
| knowledge_recall / scientific_qa | S (RAG) + cite-or-abstain | ground recall, block fabrication |
| autofix_repair | V (rerun the step) | pipeline IS the verifier; pass@k |
| (param/output) validation | R (allowed_values) | guardrail, deterministic |

→ On these, a strong harness delivers frontier-quality **system** output on a cheap backend.
This is the "harness does well no matter the LLM" zone — and it is the *majority* of calls.

### Harness CANNOT substitute (LLM judgment is the ceiling → frontier >> small, no rescue)
| Task | Why the three shapes fail |
|------|---------------------------|
| out_of_catalog_composition (0.099) | by definition retrieval returns nothing adequate (no S); verifier only exists after an expensive run; must *create* a plan or abstain |
| findings_interpretation / conclusion (0.286) | numbers are in-context but the *meaning* is novel — no retrieval answer, no verifier; majority-vote can't fix a <50% model |
| clarification_request (0.360, stuck) | calibration judgment (when ambiguous enough to ask) — no gold to verify, no retrieval answer |
| decomposition/chaining *planning core* (0.29) | step→workflow mapping is S-able, but the plan shape is LLM judgment; verifier only by running |
| workflow_generation (0.280) | partially V (does it run?) via pass@k, but the floor is LLM-bound |

→ Here the harness is a guardrail (rejects bad), not a generator. A 4B loses to frontier and
**stays** lost. majority_vote/self-consistency only help when the model is already right >50% of
the time — these are all well below that.

## So what IS the point of training the small LLM (honest)
It is **not** to beat frontier on the CANNOT list — it can't, and the harness won't save it there.
The defensible points, in priority:
1. **On-prem / compliance** — regulated pharma/CRO data can't leave the VPC. An on-prem model is a
   *requirement* for that segment, independent of any benchmark. Frontier-via-API is simply off the
   table for them, so the comparison isn't "small vs frontier" — it's "small vs nothing".
2. **Cost/latency on the CAN-carry majority** — most calls are S/R/V-shaped; a cheap on-prem model
   handles them at ~100× lower cost with the harness guaranteeing quality. Frontier spend is
   reserved (hybrid difficulty-router) for the CANNOT list only — where compliance permits.
3. **Where training has marginal value** — concentrate it on the **CANNOT list**, because that's
   simultaneously (a) the only place the LLM is the ceiling and (b) the only lever for on-prem
   customers who have *no* frontier fallback. Training the CAN-carry tasks is near-wasted (0.94
   routing can't improve; the harness already wins).

This reframes the program: **the small model is a cost+compliance play wrapped around a strong
harness, not a capability play.** Its training budget belongs on the hard judgment tasks, and its
success metric is end-to-end BioMate task success — not pure-LLM F1.

## The decisive experiment (end-to-end, backend-swapped)
BioMate's backend LLM is an OpenAI-compatible client (`galaxy-assistant.ts` → OpenRouter baseURL),
and an end-to-end RealBio runner + `models.yaml` already exist. So:

Run the **same RealBio task set end-to-end through the full harness**, swapping only the backend:
`{frontier (Opus/GPT-6), our sft_v8 (vLLM), open base Qwen3-4B (vLLM)}`, measuring **task success
(workflow runs + output passes the programmatic check), cost, latency** — broken out by the CAN vs
CANNOT task classes above.

Predictions to falsify:
- **CAN-carry tasks:** backend barely moves end-to-end success → cheapest wins (validates thesis).
- **CANNOT tasks:** frontier >> small end-to-end → the gap = the real price of on-prem, and the
  training target.
If instead the harness flattens *even the CANNOT tasks*, then training is pointless and the answer
is "cheapest model + harness, escalate nothing." If frontier dominates *even the CAN tasks*, the
harness is weaker than claimed and needs work before any model choice matters. Either way the
experiment, not intuition, decides — and it is the metric that actually reflects the product.

## Next (v9, redirected)
- Build **open-book hard-task CoT** for out_of_catalog_composition, findings_interpretation,
  task_decomposition, lane_arbitration, clarification_request — gold constructed to be checkable
  (e.g. out-of-catalog: candidates deliberately missing the needed step → gold = compose-or-abstain;
  findings: real result table → gold = the salient interpretation; decomposition: real step_metadata
  as the plan but with the WORKFLOW HIDDEN so it's genuine planning not recall).
- Re-run the 17-task eval, report the **hard-task macro** as the headline metric.
- v8 (routing-CoT-heavy) finishes as a datapoint but is NOT expected to move the hard tasks.
