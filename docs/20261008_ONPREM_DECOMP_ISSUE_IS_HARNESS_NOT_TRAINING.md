# On-prem LLM "serious issues" — verified, with discrepancies, and the fix that makes sense

**Date:** 2026-10-08
**Scope:** double-check of the serious issues reported by the local on-prem LLM training sessions,
their stated demand, discrepancies found, and the fix that aligns with the orchestration/retrieval
work shipped today. Evidence is cited to file:line; S3-only derivations are flagged "unverified".

## 1. The three serious issues — and which category each really is
1. **Parallel/mixed decomposition collapse (REAL, cross-confirmed).** `20261006_DECOMPOSITION_ERROR_ANALYSIS.md:99` ("10/12 gold failures = failing to express parallelism; the SFT prior is 'chain everything'"), `:110` ("Mixed is 0/8 for both arms"); `20261008_DECOMP_SOLVE_LADDER.md:124` (9B structure 0.35 vs 27B ~0.60). Not an artifact.
2. **Degenerate empty-mask v3 SFT (REAL, code-fixed, NOT verified end-to-end).** `20261007_SFT_V3_CLEAN_RETRAIN.md:4-6,38-39` (supervised = 0/97,065 tokens). Fix `5ae31cc03` (`{% generation %}` markers + `assert_nonempty_mask()` guard) is present and correct **at the mask level** (render byte-equality 500/500, mean supervised 29.8%). **But STEP-1 TRAIN and STEP-2 EVAL are empty placeholders** (`:107`, `:120`; `20261007_SFT_V3_REAL_RETRAIN.md` `<!-- RESULTS_* -->` unfilled). → "v3 fixes decomposition" is **unproven**.
3. **param-prefill `must_not_fill` over-fill (REAL direction, exact numbers NOT locally reproducible).** `20261006_SFT_V2_DECOMP_RETRAIN.md:63` reports base→ckpt-275 = **34→61**. The derivation boot.log is **S3-only**; recomputing locally with `public_export/score.py` gives **base = 53** (not 34), sft = 36. Over-fill is pervasive (36–62 violations on every locally-scorable checkpoint), but the exact 34→61 delta compares two different serving runs → **reporting artifact, not a clean measurement.**

## 2. "Their demand" (quoted) — and it already agrees with the harness thesis
`20261008_REQUIREMENT_COMPOSER_EXECUTION_SUBSTRATE.md:17`: **"the LLM is not the bottleneck — a frontier LLM already plans fan-out→rank→select correctly (`composed_rate 1.00`). The missing piece is the substrate to execute the plan."** `:34` (P2): replace the sequential `for`-loop (`workflow_chain.py:465-479`) with a DAG executor; **stop discarding the plan** (remove the `ai_assistant.py:724-728` fallback). Evidence it's broken now: **41% of chain connections broken (56/137)**.

## 3. Discrepancies found (the "double-check")
- **D1 — the real fix is UNBUILT where that doc looks.** The composer substrate (`map_reduce.py`, DAG executor) does not exist on `cursor/tutorial`. **It DOES exist and is validated on `feat/orch-retrieval-s2-20261008`** (`backend/lib/galaxy/ai/map_reduce.py`, 11/11 tests on Py3.9) — today's orchestration work. So it's a **branch/coordination gap**, not a missing capability. Reconcile the composer spec's P2 with the shipped `map_reduce`.
- **D2 — `must_not_fill` 34→61 not locally reproducible** (base=53 locally; the pair is two different runs). The **qwen harness-dividend cells DO verify exactly** (60/62/49 recomputed = reported).
- **D3 — `decomposition_v2` "win" (node 0.36→0.73, struct→1.000) is a self-disclosed lower-bound**: truncated at step 275/650, recovered from a lost run, and **in-distribution to its own generator** (`20261007_SFT_V3_REAL_RETRAIN.md:15-18`). The honest out-of-generator signal is `decomposition_real ≈ 0.016` and solve-ladder need_f1 flat ~0.40 — **do not cite the 0.73/1.000 as a real capability gain.**
- **D4 — `need_grader.py` docstring was inconsistent with its code** (claimed harmonic-mean + ungated reward; code is a recall-leaning blend + recall-gated reward). **FIXED today** (docstring-only, no behavior/number change; code was already correct).

## 4. The fix that makes sense given today's efforts
**The headline "decomposition is broken" is mostly a HARNESS gap, not a model-capability gap.** The frontier LLM plans correctly (1.00); BioMate discards the plan and runs a sequential loop with 41% broken edges; the 9B's parallel weakness (0.35 vs 0.60) is **largely mooted if the harness executes the fan-out from the LLM's `depends_on` plan.** This is exactly the `project_llm_harness_task_split` / `project_execution_grader` thesis.

**Therefore the right lever is the execution substrate — which was built + validated today — not retraining the 9B for parallel topologies:**
- `map_reduce.py` (bounded, order-preserving, fault-isolating fan-out+reduce; 11/11 on Py3.9) is the execution primitive the composer P2 DAG executor runs on.
- Recommended sequence (matches the composer spec): **P4 (typed handoff, fix 41%→<5%) → P2 (DAG executor consuming the `TaskDecomposer` plan; stop discarding it at `ai_assistant.py:724-728`).** The DAG-executor build is owned by a separate session per that spec; today's `map_reduce` is its substrate — the two must be reconciled, not duplicated.

**What NOT to do (to avoid wasted effort / wrong conclusions):**
- Do not retrain the 9B to force parallel decomposition before the harness executes the plan.
- Do not cite `decomposition_v2` 0.73/1.000 as a capability gain (D3).
- Before claiming the empty-mask fix improved anything, **run and record the v3 train+eval** (issue 2 placeholders).

## 5. Fixes applied today
- `need_grader.py` docstring corrected to match the code (D4) — zero behavior change, `py_compile` clean.
- (The `map_reduce` execution substrate was built+validated separately — see
  `docs/20261008_ORCHESTRATION_RETRIEVAL_S1_S2_VALIDATION.md`.)
