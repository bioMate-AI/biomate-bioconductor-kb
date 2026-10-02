# On-Prem LLM: Direction, What We Learned, and the Execution-Grader Plan

**Date:** 2026-10-01
**Status:** decision made — build a valid execution grader FIRST; defer backend-swap plumbing.
**Companion docs:** [[20261001_LLM_HARNESS_TASK_SPLIT]] (evidence table + CAN/CANNOT cut),
[[20261001_DB_GROUNDED_COT_SCALE]] (the data work that preceded this), this doc = the synthesis.

---

## 1. The arc of this session (what changed my mind, in order)

1. Generated DB-grounded SFT + routing CoT at scale (303 → 1,771 CoT + 9k grounded) to fix a
   "too few traces" problem.
2. **User: routing is two-staged; stage-2 (pick from a retrieved short list) is easy — why keep
   training it?** Pulled the baseline eval: **routing = 0.94 on the UNTRAINED base model.** True.
   I had been chasing keep-rate (a proxy for *easy*), not skill value.
3. **User: evaluate BioMate end-to-end (the harness), not the LLM in isolation.** Correct — per-task
   pure-LLM F1 is the wrong metric.
4. **User: the small LLM won't match open/frontier LLMs — what's the point?** Largely right: a 4B/9B
   will not beat frontier on open-ended reasoning.
5. **User: what can the harness complement, what can't?** → the decisive cut (section 3).
6. **User: the similarity grader is useless for correctness (e.g. findings interpretation).** Correct
   — and it invalidates the headline numbers for 14 of 17 tasks (section 4).
7. **User: these tasks are knowledge/DB-dependent; what knowledge does the LLM even learn? We should
   never expect the LLM to do it alone.** The thesis. The knowledge lives in the DB and is retrieved;
   training the LLM to memorize DB columns is the wrong objective (section 5). → stopped + terminated
   all closed-book SFT.

## 2. What is PROVEN (free, by code + existing data)

- **Workflow routing is retrieval-grounded.** `unified_workflow_search.py`: candidates come from
  BGE/MiniLM dense cosine (≥0.55); the LLM only "re-orders near-ties"; output is always a real
  catalog id. With base = 0.94, routing is **model-invariant by construction**.
- **The architecture already encodes the split.** `model_resolver.py` ROLE_DEFAULTS: cheap models for
  grounded roles (`intent`=gemini-flash, `tool_rank`=haiku), stronger for judgment roles
  (`param`/`convert`/`response`=sonnet).
- **mid-train is a no-op here** (mid500 0.26 ≈ base 0.27) — CPT doesn't help retrieval-grounded
  tasks, as predicted.

## 3. The decisive cut — what the harness CAN vs CANNOT complement

A weak LLM is rescued by the harness **iff the task reduces to**: (S) selection from a retrieved set,
(R) a deterministic rule, or (V) a cheap programmatic verifier (pass@k). Otherwise — open-ended
generation, no retrieval answer, no cheap verifier — the harness can only *reject* a bad output, not
*produce* a good one, so **output quality = LLM quality**.

- **CAN carry (LLM ≈ irrelevant → cheapest model):** routing, tool_recommendation,
  dataset_prerequisite_check, parameter conversions (rules), knowledge/QA (RAG), autofix (rerun = V),
  validation. *The majority of calls.*
- **CANNOT substitute (LLM is the ceiling):** out_of_catalog_composition, findings_interpretation,
  clarification calibration, the planning core of decomposition/generation.

## 4. The grader problem (why most numbers mean nothing)

Grader validity, from `eval_vllm.py`:
- `accept_set` (routing): **valid** — but routing is the easy invariant task.
- `mcqa` (knowledge_recall, scientific_qa): **valid** — but these are general medical MCQA
  (medmcqa/med_qa), **not BioMate capabilities**.
- `clarify_ask` ("?" present): near-useless.
- `content_overlap` (**salient-token F1 = similarity**): **useless for correctness** — covers 14 of
  17 tasks, including every hard BioMate reasoning task.

**Consequence:** we currently have NO valid measurement of the BioMate CANNOT tasks. The reported
gains there are not evidence of capability or of failure.

## 5. What knowledge should the LLM learn — and what it should NOT

"Never expect the LLM to do it alone" ⇒ the LLM learns **no BioMate domain/DB content** (tools,
inputs, schemas, steps, workflow names). That is DB-resident and retrieved. My `build_db_grounded.py`
set gold = raw DB columns → trained memorization of retrievable, stale (DB went 2,455→4,200),
non-transferable facts. **Wrong objective.** The only learnable surface is the *operating skill* over
harness-supplied context (select / wire / value / decide-to-ask) — small, stable — and it must be
trained and evaluated **open-book**. Action taken: closed-book SFT stopped, wrappers killed, 3 GPU
instances terminated.

## 6. The point of the small LLM (honest, final)

NOT a capability play (it won't beat frontier on the CANNOT list, and the harness won't save it).
It is a **cost + compliance play wrapped around a strong harness**:
1. **On-prem / compliance** — regulated pharma/CRO data can't leave the VPC; there the choice is
   "small vs nothing," not "small vs frontier."
2. **Cost on the CAN-carry majority** — cheap on-prem model + harness delivers frontier-quality
   *system* output; reserve frontier (hybrid difficulty-router) for the CANNOT minority where
   compliance allows.
3. **Training value is marginal and belongs only on the CANNOT list** (open-book), if at all.

## 7. DECISION: build a valid execution grader FIRST (defer backend-swap)

The sweep of backends is premature: even a perfect backend sweep can't measure the CANNOT tasks
because they have **no valid grader**. The real missing piece is a **valid grader**, and the only
valid one for these tasks is **execution**: let BioMate produce the artifact (workflow + params),
**actually run it, and check the output passes a programmatic check.** Build that first; a backend
swap becomes worth wiring only after a valid grader exists.

### Backend-swap options (deferred, recorded for later)
- **(B, preferred) plumb per-request BYOK** — finish wiring `user_overrides` from the chat request →
  `resolve_model` (0 call sites pass it today). Enables per-request swap on dev with no env change;
  also ships a BYOK product feature.
- (A) sanctioned dev deploy per model (BIOMATE_MODEL on dev via the deploy path) — manual, serial.
- (C) local full stack + real DB from S3 — heavy, uncertain deps in this worktree.

## 8. Execution-grader plan (the build, starting now)

**Principle:** validate the grader on an EXISTING finished run before spending any Batch (review-
before-expensive). Drive everything through the existing BioMate MCP tools against dev (no new client,
no dev-config change).

**Steps:**
1. `list_runs` on dev → find an existing completed run (known-good) and, if available, a failed one.
2. Build the grader `grade_run(run)` → objective PASS/FAIL from: terminal status == success AND the
   expected output type is present AND the output file is non-empty / parses. No similarity, no LLM.
3. Validate: grader = PASS on the known-good run, FAIL on a known-bad/failed run.
4. One fresh end-to-end loop on a SMALL/fast workflow: request → `search_workflow` (harness retrieval)
   → `run_workflow` (params) → `watch_run`/`get_run` → `preview_file`/`analyze_results` → `grade_run`.
   Predict the outcome before running; pick a cheap workflow (NOT a 35-min GPU job).
5. Report: does the full loop yield an objective PASS? If yes, we have the first valid measurement of a
   BioMate end-to-end task — and the foundation to later vary the backend.

**Explicitly NOT doing now:** backend-swap plumbing, more SFT/CoT, any large Batch sweep.
