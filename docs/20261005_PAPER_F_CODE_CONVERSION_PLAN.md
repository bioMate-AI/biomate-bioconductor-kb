# Paper F (SEPARATE manuscript) — heterogeneous-source → Nextflow conversion & the execution-graded benchmark

**Date:** 2026-10-05. **Status: PLAN / forward-looking** (capability being built; the benchmark exists with a
frontier smoke baseline; converters + local-9B eval + SFT lift are pending). Per the user's instruction, the
WDL/CWL/Jupyter-notebook/Python-R-script conversion work is **reserved for THIS paper and kept out of every
other manuscript** (RealBio, Bioc-KB ×2, Paper B, Paper D, Paper E). Companion plans: coverage
`20261005_SOURCE_FORMAT_CONVERSION_COVERAGE.md`, capability `20261005_LOCAL_LLM_CODING_CAPABILITY_AND_PLAN.md`,
assets `20261005_LEVERAGING_BIOMATE_ASSETS_FOR_CODING.md`, benchmark `evaluation/datasets/nextflow_coding/`.

## Terminology (avoid the overloaded word)
- **This paper = "implicit-DAG recovery" / source→pipeline conversion**: turn Snakemake/WDL/CWL/Galaxy/
  notebooks/Python-R scripts into a reproducible, executable **Nextflow** pipeline.
- **NOT the same as Paper B's "task/request decomposition"** (breaking a multi-task *user request* into a
  sub-task plan over *existing* catalog workflows — orchestration planning). Cite Paper B as the sister task;
  do not merge them.

## Single core claim
*A single capability — recovering an explicit, executable DAG from heterogeneous bioinformatics sources —
lets a small on-prem model, inside a stub-run **verify-fix** loop seeded by a validated workflow catalog,
convert scripts/workflows across formats into reproducible, QC-gated Nextflow pipelines; and we make it
falsifiable with an **execution-graded** benchmark (does it parse → stub-run → run to an output contract),
not string similarity.*

## Why a standalone paper (distinct contribution)
- The unifying insight: convert-from-Snakemake/WDL/CWL/notebook and Python/R script→pipeline all reduce to
  **one** capability (DAG recovery), so one method + one benchmark covers the whole fragmented ecosystem.
- The **execution grader** is the methodological contribution (parse/`-stub-run`/real-run tiers) — most
  "LLM writes a pipeline" work grades by similarity or human eyeball; this grades by actually running it.
- Clean separation from the knowledge/routing story (Paper B/D) and the drug-dev governance story (Paper E).

## Structure
1. Intro — bioinformatics is fragmented across workflow languages + ad-hoc scripts + notebooks; value of one
   reproducible, QC-governed target (Nextflow) and of *execution*-based evaluation.
2. The capability & the convert-from skills — convert→`-stub-run` verify→fix, retrieval-seeded from the
   ~4,209-workflow catalog; small-LLM-in-loop; escalate/abstain on hard cases (`run:`/wildcards/checkpoints).
3. The execution-graded benchmark (the yardstick) — convert/fix/write + `convert_from_{snakemake,wdl,cwl,
   notebook}` + `decompose_script_to_pipeline` (implicit-DAG, Python/R); tiered grader; the "monolithic
   one-process conversion is penalized" contract.
4. Method — the skill loop + execution-grounded code-SFT (reject-sampling on stub-run pass) from the verified
   conversions + the harvested catalog/fix-commit corpus.
5. Results — (see evidence table).
6. Limitations — stub-run ≠ semantic equivalence; hard directives abstained; etc.

## Evidence: have vs needed (honest)
| Claim | Have now | Needed |
|---|---|---|
| Execution grader works (parse/stub/run, discriminates) | ✅ built + validated in-env (nextflow 25.10.6; reference→1.0, broken→0, tier-A≠tier-B proven) | — |
| Benchmark covers the source formats | ✅ convert/fix/write + snakemake; ⏳ WDL/CWL/notebook/decompose being added | finish the added kinds |
| Frontier baseline | ✅ deepseek-v4.1-flash 1.0 on 12 smoke tasks (<$0.01) | harder tasks for headroom |
| **Local-9B + harness result** | ❌ (9B training, not served) | serve 9B → run `run_bench.py` → the headline number |
| Convert-from-X skills (Snakemake first) | ❌ scoped only | build + measure |
| Execution-grounded SFT lift | ❌ | harvest → SFT → re-measure |

## Venue
Bioinformatics / GigaScience (methods+software) or a NeurIPS D&B-style track for the benchmark; workflow-
systems venues (e.g. the Nextflow/nf-core community) as an alternative. Decide once the local-9B + skill
results land.

## Rule (registered in manuscript-plan.md)
The conversion/implicit-DAG-recovery work and its benchmark are **Paper F only** — do not fold into A–E.
