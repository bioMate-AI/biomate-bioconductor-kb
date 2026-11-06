# Use case plan: survey a research topic, propose a new study, use public data to measure and prepare it

Date: 2026-11-01. Driving use case for the unified model in `20261101_ORCHESTRATION_OVERVIEW_AND_UNIFICATION.md`.
Status legend: EXISTS (code, live), WRITTEN (code present, untested), NEW (not built).

## 1. Pipeline (a plan = chain DAG of workflow and capability steps)
| # | Step | Kind | Status |
|---|---|---|---|
| 1 | Scope the topic (population, window, what a useful study is) | single LLM step + clarification | EXISTS (chat clarification) |
| 2 | Find literature: PubMed, Europe PMC, Semantic Scholar, OpenAlex, Crossref, corpus index (Paperclip optional) | `search_literature` | EXISTS |
| 3 | Read each paper: question, methods, datasets used, findings, limitations. **Fan-out, one reader per paper** | `corpus_map` LLM worker, quote check | WRITTEN (`corpus_fs/llm_map.py`, no tests) |
| 4 | Reviewer gate: each claim needs a verified verbatim quote | `make_llm_reviewer` | WRITTEN |
| 5 | Reduce to an evidence table; cited survey | `write_review`, citation existence check | EXISTS |
| 6 | Find gaps and check novelty (untested questions, conflicts, unused datasets, precedent) | LLM step over verified rows; novelty/FTO gate | PARTLY (gap step NEW) |
| 7 | **Human gate G3**: choose the gap | gate | NEW |
| 8 | Propose the study: hypothesis, design, endpoints, sample needs; each element linked to evidence or marked an assumption | LLM step | NEW |
| 9 | Find public data that can test it (GEO, TCGA, CELLxGENE, Open Targets, ClinicalTrials.gov). **Fan-out per dataset** | `fetch_public_data`, `resolve_accession`, source registry | EXISTS (tools) |
| 10 | Measure feasibility: sample counts, covariates, effect sizes, power, pilot analysis | catalogue workflows on Batch, or `run_code` | EXISTS |
| 11 | Prepare: analysis plan as a ready-to-run chain, data manifest, report | chain DAG, report export | EXISTS |

## 2. Human involvement
Gates stop the run; review points do not, but their edits feed the next step. Every gate shows its evidence (citations, counts, claim status).
| Id | Where | Person does | Type | Status |
|---|---|---|---|---|
| H1 | Start (1) | Confirms scope and window | gate | partial (chat clarification) |
| H2 | After survey (5) | Reviews survey and evidence table; excludes/adds papers | review | NEW (review screen) |
| H3 | Gap choice (7) | Picks the gap | gate | NEW |
| H4 | Proposal (8) | Edits or accepts hypothesis, design, assumptions | review | NEW |
| H5 | Before spend (9-10) | Approves data list, licence terms, compute and LLM cost (estimate shown first) | gate | partial (quota exists; estimate and approval NEW) |
| H6 | Feasibility (10) | Go / revise / stop; full analysis or plan only | gate | NEW (maps onto chain approve-each-step) |
| H7 | End (11) | Signs off plan and report | review | partial (export exists) |

Failures in automatic steps surface as `unsupported` / `unverified`, not as questions.

## 3. Build slices (each flag-gated, testable; none starts until the previous passes)
- **S1 Tests for the corpus pieces.** Offline tests for `ingest_ctgov`, `llm_map` (fake LLM: quote verification, unsupported answers, reviewer reject, synthesis unknown-id removal). Acceptance: all pass on python3.9.
- **S2 Command interface** (`ls/cat/grep/find/map`) over a corpus index, plus the ClinicalTrials.gov index built on EC2 spot from the S3 mirror. Acceptance: grep a condition returns real NCT ids; index row count equals 609,551.
- **S3 Step interface and registry**, including the declared `gate` field (`none` / `review` / `approve`) with the class defaults from the overview doc. Register the existing capabilities (no behaviour change). Acceptance: a capability and a workflow are interchangeable nodes in `validate_plan`.
- **S4 Capability steps in chain DAGs** (plan format, executor, `max_parallel`); `map` node + `reduce` node; reviewer node. Acceptance: a fan-out of N fake items runs, a failed item is isolated.
- **S5 New steps:** structured paper extraction schema, gap finder, study proposer, dataset feasibility. Acceptance: each returns an envelope with provenance and honest status.
- **S6 Gates and review screens** (H1-H7), reusing approve-each-step. Acceptance: the run halts at H3 and H6 and resumes with the person's choice.
- **S7 Planner + `orchestrate` chat tool**, off by default.
- **S8 Evaluation (time split).** Restrict literature to before a cut-off, run the pipeline, record proposed studies, and score against later published work and against a single-agent baseline. Report proposals that match, with the same honesty as the temporal target-ID test (small samples reported as such).

## 4. Cost and compute rules
LLM calls scale with papers read: state an estimate before any run over more than ~100 documents. Heavy work runs on EC2 spot or Spark, never the laptop. Public data only; licences and access terms are shown at H5.

## 5. Not in scope
The dormant multi-specialist orchestrator (specialists become context profiles), the run-level auto-loop, the paid Paperclip service.
