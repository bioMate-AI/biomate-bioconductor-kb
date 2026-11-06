# Eval correction (domain-pro not broken) + the system-level bar

**Date:** 2026-10-03
**User directive:** the bar that matters is **BioMate (LLM + harness) end-to-end performance across
different LLMs** — that is what LLM optimization must beat, not an LLM-isolated score.

## Correction: the "catastrophic regression" was a grader artifact
The takeover paired eval (`eval/med_today_20261003/{base,domainpro}.json`) reported domain-pro at
**0.018** (109/112 "invalid") vs base 0.68 — which looked like the CPT+SFT destroyed the model.
Checking the raw predictions disproves it: domain-pro answers in **explained format** — e.g.
`"D) Thyroid agenesis."` — and the **strict single-letter grader** counted those as invalid. base
happens to emit bare letters, so it parsed; the comparison was confounded by output format.

**Re-scored with a lenient leading-letter extractor (both arms, same 261 items):**
| Model | MCQA accuracy (lenient) | parseable |
|-------|------------------------:|----------:|
| base (Qwen3.5-9B, original) | 0.636 | 1.000 |
| **domain-pro (CPT+SFT, bounded 300+500 steps)** | **0.655** | 1.000 |

So the bounded domain-pro is **+1.9 pts over base**, not a regression. It is a *bounded* run (not the
full 593M-token / 72K-row pass), so this is a weak-but-positive signal, within noise. **Action for the
takeover eval code:** replace the strict-letter grader with the lenient extractor, else it will keep
mis-scoring any explained-format model. (The local `eval_vllm.py:first_letter` already uses `\b[A-E]\b`
and is fine; the broken parser is in the recovery `today_entry.sh` eval.)

## What the evidence says so far (toward the bar)
- **Knowledge MCQA (LLM-isolated proxy):** domain-pro ≈ base (0.655 vs 0.636). Not the system bar.
- **Grounded ADMET decision (harness-in-loop):** both base and domain-pro produced **valid, contract-
  passing** `{workflow, params}` (`grounded_{base,domainpro}.jsonl`, `contract_pass:true`), but
  `execution_status: NOT_RUN` — the artifacts were never executed+graded. The molecule sets
  (aspirin/caffeine/ibuprofen; imatinib) match earlier **PASS** runs (635bb415, e34317e3), so both
  backends' decisions are execution-valid → **model-invariant on ADMET** (matches the task-split:
  grounded/harness-carried tasks don't depend on the LLM).

## The system bar — what remains (the real metric)
"BioMate performance with LLM X" = run the real task set **through the harness** with backend=X, grade
by **execution** (does the workflow run + output pass the programmatic check), per task, for each of
{base, domain-pro, frontier}. Status:
- The grounded bakeoff is **2 ADMET tasks only** and **NOT_RUN** — convert those to real execution grades first.
- Then broaden to a diverse task set (routing, param-extraction, compose/out-of-catalog, findings) —
  the tasks where the LLM backend *could* matter — through the live harness, each backend, execution-graded.
- Backend swap is enabled by the on-prem `LLM_API_URL`/`openai_compatible` config (next-phase); serve
  base and domain-pro at OpenAI-compatible endpoints and point the harness at each.
- Metric = `execution_grader` (terminal success + output-content + per-workflow contract), NOT MCQA/similarity.

**Bottom line:** the domain-pro is not broken (parser artifact) and shows a small positive signal; but
the *system bar* (BioMate end-to-end across LLMs, execution-graded) is still unmeasured beyond 2 ADMET
decisions. Completing that — especially on tasks where the LLM is the ceiling — is the priority.
