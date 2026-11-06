# Committee Audit v2 — FULL records, workflow data & tasks

**2026-09-19.** Re-review after v1's truncation mistake. Both gpt-5.6 and gemini-3.8-flash received
**complete records** and **independently converged** on the same real defects. Both conclude: **do not
start GPU training until these label defects are validated/regenerated/quarantined.** No false alarms
this time — these were verified as real in the samples.

## P0 — real label-contract defects (both models, confirmed)

### 1. `interwf_decomp` semantic mislabel (both: "smoking gun")
A compound request whose branch is clearly **raw scRNA-seq** got gold
`{"sub_task":"metabolomics analysis","workflow":"phenomis"}` (phenomis = metabolomics). The
generator samples workflows from different domains and writes a compound query, but the
branch↔workflow correspondence drifts and `sub_task` is a generic `"{domain} analysis"` label.
→ **Fix:** verify each sampled workflow's domain/keywords actually appear in its query branch; make
`sub_task` reflect the real workflow purpose; drop/regenerate mismatches. (Root: `generate_interworkflow_decomp.py`.)

### 2. `clarify` / `cond_param` under-report missing required params
Schema marks 7–13 params **required**; the request supplies none of them; gold asks for only **one**
(`{"clarify_needed":["splits"]}`, `["extend_reads"]`). The generator omits one random required param
and ignores the rest. → **Fix:** report the FULL set of genuinely-missing required params — but first
resolve the nuance the committee raised: many "required" params have defaults / are auto-set, so the
schema's `required` flag is unreliable. Treat "required AND no default AND not user-provided" as the
must-ask set. (Root: `generate_clarification.py`, `generate_conditional_param.py` + schema semantics.)

### 3. `decompose` broken DAG dependencies
`epiNEM` gold: step 2 (inference) `depends_on:[]` (should be `[1]`); step 3 (plot) `depends_on:[1]`
(should be `[2]` — plotting consumes the inferred network, not the input matrix). Teaches topologically
invalid graphs. → **Fix:** `build_dag` must link each step to its true immediate predecessor, not the
first step of the prior phase. (Root: `generate_decomposition_data.py`.)

## P1 — design & coverage (both models)

### 4. Missing task: input/output TYPE & STAGE compatibility (pre-flight)
A FASTQ request was configured against a BAM/regions-expecting schema. Need a task that checks a
workflow's required input type vs what the user has, and that **upstream output type matches downstream
input type** in a chain (+ genome build, identifier namespace, matrix orientation, metadata survival).

### 5. Missing: routing abstention / retriever-failure
rag_routing guarantees the gold is present → only tests reranking. Add `none_of_the_above`,
"no candidate supports the input type", "needs a chain not one workflow", out-of-scope. Otherwise the
model confidently picks an invalid candidate.

### 6. Missing: resource/infra + failure triage (gemini)
`--max_memory`/`--max_cpus`/profile sizing by sample+genome size; OOM/exit-137/missing-index log triage
(partly covered by `diag_fix`/`autofix`, but not resource sizing).

### 7. Ambiguous single-labels (CUT&Tag vs CUT&RUN)
Gold `nf-core/cutandrun` while a dedicated `Cutandtag Alignment Spikein` candidate exists → label not
textually unique. → allow **acceptable-alts** / multi-label, add discriminative detail, or exclude from
exact-match training.

### 8. `param` Ex1 dirty artifact
`"Candidate parameter: exclude=sgc."` leaked into the prompt/gold — a generation/serialization artifact.
→ add an output-sanity filter.

### 9. Coverage/distribution
15,254 / 4,200 workflows ≈ 3.6 examples/workflow; `interwf_decomp` (354) critically thin for
cross-domain combinations. → rebalance; grow the starved tasks.

## Priorities
1. **Automated label validator + regenerate/quarantine** the affected subsets (both models' #1).
2. Fix the three generator bugs (interwf mislabel, clarify under-report, decompose deps).
3. Add the **input-type/stage-compatibility** task + routing **abstention**.
4. Acceptable-alts for ambiguous routing; rebalance coverage.

## Meta
v2 (full records) produced real, actionable findings where v1 (truncated) produced false alarms —
confirming: **never audit on truncated samples.** Raw reviews: `committee_reviews/audit_v2_*.md`.
