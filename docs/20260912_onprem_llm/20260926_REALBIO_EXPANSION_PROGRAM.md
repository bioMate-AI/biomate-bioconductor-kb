# RealBio Expansion — generate our own (larger scope), release part (2026-09-26)

**This is an EXPANSION of RealBio, not a new benchmark.** RealBio already IS our open, objectively-scored,
cross-system benchmark (660 items / 8–9 tasks, open deterministic `score.py` CC-BY-4.0, honesty contract,
public-items + gated-portion release model, leaderboard vs 8 LLMs + Biomni + BioMate — see
`20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md`, `20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md`). Its `score.py`
already provides the **objective grading** the committee asked for (exact-match where the task admits, no
LLM judge). "Generate our own larger scope + release part" = **grow RealBio's scope and item count**, keep
its open-scorer + release-part protocol.

**Decision:** expand RealBio into a large-scale, **verifiable, agentic** corpus — **larger scope than
LatchBio** (all 36 BioMate domains × the full task taxonomy + instruments + clinical use-cases) — as (a) a
proprietary **training** bulk and (b) a **public RealBio release** subset. Every task carries an **objective
grader** (RealBio `score.py` + LatchBio `eval_graders` + our accept-set/schema/DAG graders — no teacher-fidelity).

## Why we can go larger than Latch
Latch hand-curates ~1,147 evals across single-cell/spatial/variant/epi/tx/biosec. **BioMate can generate
verifiable gold at scale** because it already has: 4,000+ workflows across 36 domains (routing/param/DAG
gold), PrimeKG (8.1M edges, knowledge/reasoning gold), a literature corpus, and — crucially — an
**execution engine** (AWS Batch) that can *run* a workflow on a real dataset to produce ground-truth
outputs (the expensive part Latch does by hand). That closed loop = verifiable tasks across every domain.

## Scope (larger than Latch)
- **A. Agent tasks (DB/KG-anchored, no execution — generate now):** workflow_routing (accept-set gold),
  parameter_extraction (schema gold), task_decomposition (workflow-DAG gold), workflow_generation,
  clarification, log_diagnosis, autofix, findings_interpretation, multi_workflow_chaining, lane_arbitration,
  design_constraint, model_selection, out_of_catalog_composition (N1), knowledge/scientific_qa/kg_reasoning
  (KG + literature gold).
- **B. Analysis tasks (execution-based — phase 2):** qc, normalization, dim-reduction, clustering,
  cell_typing, differential_expression, spatial, variant, epigenomics — gold from **BioMate executing the
  workflow on a real dataset** (numeric/label ground-truth), the Latch-style verifiable tasks but across
  all 36 domains + our workflow catalog.
- **C. Instrument orchestration (NEW — hospital/lab instruments):** from the 9 connectors in
  `biomate-connector/lab_instruments` (Illumina BaseSpace, Benchling ELN, Nanopore MinKNOW, CryoEM EPU,
  LC-MS/flow/qPCR/plate-reader watchers, SiLA2, OpenTrons) + tools (`list_instrument_runs`,
  `fetch_instrument_data`, `detect_completed_runs`, `parse_instrument_output`, `run_instrument_protocol`).
  Tasks: instrument-run → BioMate params → workflow; protocol selection; output parsing. Gold = the
  connector's deterministic `*_to_biomate_params` mapping (objectively checkable). This is a task class
  Latch does NOT have — real clinical/wet-lab instrument→analysis handoff.
- **D. Clinical end-to-end use-cases (NEW — our priority documents):** seed from
  `BIOMATE_PLATFORM_PROPOSAL_HIGH_PRIORITY_USE_CASES.md` (clinical DIA proteomics, multi-omics cancer dx,
  CRISPR therapy design, clinical NGS automation, …) → multi-step end-to-end automation tasks with
  checkable milestones. Our proprietary real-world distribution.

## Verifiability (grader per task — no teacher-fidelity)
Adopt + extend graders: `accept_set_membership` (routing), `schema_key_recall` (param), `dag_step_coverage`
(decomposition), `numeric_tolerance` / `label_set_jaccard` / `marker_gene_precision_recall` /
`multiple_choice` / `all_of` (analysis — LatchBio `eval_graders`, already fetched), `kg_fact_match`
(reasoning). Gold comes from the DB / KG / execution — never a teacher's free text.

## Public / proprietary split + release
- **Release subset (~10–20%):** a held-out, **canary-marked** public benchmark ("BioMate-Bench") — a
  contribution + credibility signal. Balanced across domains × categories.
- **Proprietary bulk (~80–90%):** training. (Our own release carries a canary for *others*; per our
  internal policy [[feedback_no_data_exclusion]] we do not exclude *external* benchmark data from our own
  training — the canary is a courtesy to downstream users, applied to what WE publish.)
- Scale target: **≥10k verifiable tasks** (A now; B as execution capacity allows) — ~10× Latch's public set.

## Phases
1. **P1 (now):** DB+KG-anchored verifiable agent tasks (category A) — generator + programmatic graders,
   smoke-test → scale. No Batch runs.
2. **P2:** execution-based analysis tasks (category B) — pick real datasets, run BioMate workflows to get
   gold, wrap with `eval_graders`. Batch cost.
3. **P3:** assemble → domain/category-balanced split → public release packaging (canary, license, card) +
   proprietary training merge (provenance-labeled, deduped).

## Status / next
- Generator `bench_gen.py` (P1) — build + smoke-test before scale (verify-before-spend discipline).
- Inventory captured from Latch (908+ eval IDs + facets, `eval/latch_full_inventory.json`) = coverage
  cross-check so our scope is a superset.
- Feeds the same pool as the other sourced data (Claude-logs 8,428, gold QA 25k, KG→SFT, Latch traj 132).
