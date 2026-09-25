# Committee Audit — SFT Task Definitions, Training Data, Eval Data (2026-09-25)

**Committee:** Claude Opus 5.5 (`claude-opus-5-5`), GPT (`gpt-6-luna`), Gemini (`gemini-3.8-flash`),
each grounded independently in the real artifacts: per-task train/eval counts, 2 real samples/task,
the task taxonomy (`20260922_LLM_TASK_TAXONOMY_NEWVERSION.md`), and the metric caveat.
Raw critiques: `committee_sft_audit_raw.json`. Runner: `evaluation/local_trial/committee_sft_audit.py`.

## Headline (unanimous across all three)

The SFT mix is **still shaped like the old Galaxy-era assistant** and does not match the data-centric,
de-Galaxy direction. The volume curve is the **inverse of the value curve**, the flagship is **unmeasured**,
and **~82% of the eval scores teacher-fidelity, not correctness** — so it can reward hallucinations.

## Consensus findings (agreement noted)

1. **Value–volume inversion [C/G/Gem].** Of 47,959 train rows, **~62% go to 4 lookup/QA tasks**
   (tool_recommendation, knowledge_recall, scientific_qa, dataset_prerequisite_check). The 4 genuinely
   new LLM tasks **N1–N4 get ~4.9%** (2,372 rows); the **flagship N1 gets 1.2% (599)**. A 4B has limited
   capacity — spending ~30k rows on ToolShed trivia crowds out composition/abstention/structured extraction
   and trains "fluent hallucination" (closed-book fact regurgitation on a model too small to hold the facts).

2. **Flagship N1 has 0 eval rows [C/G/Gem].** `out_of_catalog_composition`: 599 train / **0 eval**. No
   baseline, no regression check, no abstention measurement. Called a **deployment blocker**.

3. **Eval metric doesn't measure correctness [C/G/Gem].** 15/17 tasks are scored by LLM-judge *coverage of
   the teacher's answer* → rewards reproducing the teacher, **including its hallucinations**. Concrete proof
   in the data: a `clarification_request` teacher answer claims the **`rtracklayer` workflow expects type
   `marraylm`** — scientifically absurd (rtracklayer = BED/WIG/BigWig I/O; `marraylm` = a limma object).
   That hallucination is now a training target *and* would be rewarded by the judge. Also: a boolean flip
   (`stranded=True/False`), swapped ref/alt alleles, or a coordinate offset destroys the science but keeps
   ~98% judge text-coverage.

4. **Three tasks are really one [C/G/Gem].** knowledge_recall + scientific_qa + tool_recommendation
   (~23k rows, ~48%) are all "summarize the doc page for package X." None of the scientific_qa samples do
   scientific *reasoning* (e.g. "3 replicates, high dispersion → DESeq2 or limma-voom?"). **Merge** into one
   grounded-QA task (retrieved context + citation requirement); rebuild tool_recommendation as constraint-
   based selection where the user never names the suite.

5. **Galaxy contamination vs de-Galaxy [C/G/Gem].** Nearly every tool sample is a ToolShed wrapper (HVIS,
   `Agat Convertgff2Bed`, MiModD Reheader, vSNP, Collect.shared, chainSort, "Filter - Median"). If these
   aren't executable in the new backend, BioMate will recommend/route to things it can't run. The routing
   **accept-set gold** is built on the same stale DB and needs re-audit against the current catalog.

6. **Label ≠ content (mis-scoped tasks) [C/G/Gem].**
   - `parameter_extraction`: samples are *param-doc QA* ("what's the default of freq"), but eval uses
     schema-key recall → **train and eval measure different things**. Should be utterance→typed JSON slot-fill.
   - `dataset_prerequisite_check`: lists a workflow's declared inputs; should check the *user's actual
     dataset* (files/headers/metadata) as satisfied/missing/convertible — the core data-centric task, and
     **no sample checks anything**.
   - `findings_interpretation`: hypothetical "what will outputs show?" pre-run; should interpret *real*
     result tables with numbers that trace to the table.
   - `workflow_generation` / `task_decomposition`: describe an existing catalog workflow's internals =
     recall, not generation/planning.

7. **CI/CD harness leakage in log_diagnosis + autofix_repair [C/Gem].** Samples carry internal QA metadata
   ("validation failure was a test-environment artifact, /rlib shadow, flagged as runnable"). This trains the
   model to (a) dismiss failures as environmental and (b) recite internal benchmark flags to end users.

8. **Data-quality bugs [G/Gem].** Truncated generations (`multi_workflow_chaining`: "...run chainSort on
   each of " — no EOS validation), and free-text "workflows" that are non-executable (package lists, prose
   steps) where the orchestrator needs deterministic JSON with I/O bindings.

9. **Missing high-value tasks [C/G].** dataset profiling / data-understanding (a data-centric product with
   no data-reading task is a contradiction); backend argument-building (routing to NIM/REINVENT/ML-train is
   useless without a well-formed payload); grounded-with-citations answering (Instant-cited lane);
   abstention / out-of-scope / safety refusal (incl. toxin/pathogen design refusal); multi-turn state
   carryover; structured-output (JSON-schema) adherence as a trained+evaluated behavior.

## Prioritized actions (committee consensus)

1. **Rebalance the corpus.** Downsample the 3 QA tasks ~75% (cap ~1,500 each) and reallocate to N1–N4.
   Gemini's concrete targets: N1 ≥3,500, N2 ≥2,500, N3 ≥2,000, N4 ≥1,500. Make N1 supported-compositions +
   graph-grounding + **abstention negatives** explicit coverage requirements.
2. **Build an N1 gold eval as a deployment gate.** ~250 graph-composition problems: valid multi-block
   pipelines scored by DAG validity + port type-compatibility, plus negative controls for correct abstention.
3. **Replace teacher-fidelity scoring with programmatic gold** for N1–N4, workflow_generation, autofix:
   JSON-schema validation, DAG acyclicity/port checks, 5-way lane Exact-Match + per-class P/R, field-F1 for
   constraints, sandbox patch-application for autofix. Keep LLM-judge only for genuine summarization
   (findings_interpretation). Add source-grounded factual-accuracy evals for the QA tasks.
4. **Rewrite task contracts + relabel** (merge redundant, fix label≠content, force structured JSON outputs
   for operational tasks); quantify label-disagreement before the next training run.
5. **Purge CI artifacts + truncated samples + stale Galaxy entities.** Regex-drop internal QA jargon
   (`/rlib shadow`, "flagged as runnable"), drop truncated rows, and audit every referenced entity against
   the current catalog snapshot; re-audit the routing accept-set on the live DB.
6. **Add an end-to-end data-centric agent eval:** use the user's data state → identify prerequisites → ask
   only necessary questions → choose a lane → produce a valid plan → hand off to the correct backend.

## Honesty notes / caveats

- Findings 1–3 are **quantified from the actual counts** (not opinion). Findings 4, 6, 7, 8 are grounded in
  the specific samples the committee saw (2/task) — they are strong signals but should be confirmed at
  corpus scale (measure label-disagreement %, truncation %, stale-entity %) before acting corpus-wide.
- This audit is on the **SFT** corpus; the parallel large-scale **mid-train** (`_lit`, PubMed literature)
  is a separate track and addresses the knowledge-QA weakness from a different angle.
- Next step per this audit is a **corpus-scale quality pass** (label-disagreement, truncation, stale-entity,
  leakage metrics) + the N1 gold eval, before the next SFT run.
