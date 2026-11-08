# Source-format → Nextflow conversion: coverage, gaps, and the first new converter

**Date:** 2026-10-05. Grounded in the actual converter code (`backend/lib/galaxy/ai/*converter*.py`,
`nextflow_composer.py`, `generate_biomni_nextflow.py`) + file counts in the repo. Feeds the coding track
(`20261005_LOCAL_LLM_CODING_CAPABILITY_AND_PLAN.md`) and the asset-leverage plan
(`20261005_LEVERAGING_BIOMATE_ASSETS_FOR_CODING.md`).

## 1. Coverage matrix
| Source format | In repo | Converter today | Status |
|---|---:|---|---|
| **Galaxy** (`.ga` / tool XML) | 5,417 | `improved_galaxy_to_nextflow`, `unified_galaxy_nextflow_converter`, `enhanced_process_converter` (576 composer refs) | ✅ covered (Galaxy→NF ~96–99% within catalog) |
| **Python** | — | 1 process wrapping a `python3` heredoc, from Galaxy XML | ✅ **tool-wrap only** / ❌ script-decompose |
| **R / Bioconductor** | — | 1,818 bioc workflows wrap a package call (`process BIOC_<pkg>`) | ✅ **package-wrap only** / ❌ script-decompose |
| **CLI / bash** | — | 36 / 21 refs; dependency converter (conda/singularity) | ✅ tool-wrap |

> **Important correction on Python/R (2026-10-05):** the earlier "✅ covered" overstated it. What exists is
> **tool/package wrapping** — one tool → one NF process, templated, generated largely *from Galaxy XML /
> Bioconductor metadata* (`generate_biomni_nextflow.py` parses Galaxy XML and emits a single-process
> heredoc; generated NFs have 1 process block). There is **no** arbitrary-script→NF converter (no Python/R
> AST decomposer). So:
> - single tool/package → one process = **done**;
> - ad-hoc one-off analysis → runs in the **`run_code` sandbox** (correctly NOT converted);
> - **arbitrary multi-step Python/R analysis → a decomposed multi-process NF pipeline = the GAP** (the
>   valuable one). Deciding process boundaries / file checkpoints / parallelism is the **same LLM-bound
>   DAG-resolution core** as Snakemake conversion, and is literally the decomposition task the task-split
>   flags as model-bound (0.40 vs 0.60).
> - **Triage first (Python/R only):** unlike Snakemake/WDL/CWL (already pipelines), a Python/R script needs
>   a *should-this-be-a-pipeline?* decision — convert only when reusable / multi-sample / needs scale-out;
>   else keep it in `run_code`. That triage is itself a skill.
| **Jupyter notebooks** (`.ipynb`) | 25 | ⚠️ trace only (1–2 refs) | **GAP (high)** — notebooks hold most ad-hoc analysis |
| **Snakemake** (`.smk`/Snakefile) | 0 | ❌ none | **GAP (high)** — dominant academic language |
| **WDL** (`.wdl`) | 0 | ❌ none | **GAP (high)** — GATK/Terra/Cromwell |
| **CWL** (`.cwl`) | 10 | ❌ none | **GAP (medium)** — standard; some on disk unconverted |
| **Perl** (`.pl`) | 58 | ⚠️ 1 ref | GAP (medium) — legacy tools |
| **Makefile** | 80 | ❌ none | GAP (low) |
| **Nextflow DSL1→DSL2** | — | partial | GAP (medium) — upgrade legacy, not new conversion |
| MATLAB / Julia | 1 / 1 | ❌ | negligible |

**The existing "Outstanding Gaps" in `WORKFLOW_SOURCES_INVENTORY.md` §10 are narrow** (2 specific Galaxy
workflows + more nf-core pipelines) — they track Galaxy→NF *within our catalog*, not other source
**languages**. This doc is the cross-language view.

## 2. Priority
1. **Snakemake, WDL, CWL** — the three other real workflow *languages*. Adding them lets BioMate ingest the
   entire *non-Nextflow* pipeline ecosystem (not just Galaxy). Highest strategic value.
2. **Jupyter → workflow** — highest-value *script* type; "notebook → reproducible, QC-gated pipeline" is a
   compelling product story and 25 are already in-repo.
3. Perl, Makefile, DSL1→DSL2 upgrade — lower.

## 3. Converters are "skills" (ties to the coding track)
Each converter is a harness **skill** with a built-in verifier: `convert-from-<X>` → generate NF →
**`nextflow -stub-run`** (validates DAG/channel wiring, no tools/data) → fix loop → retrieval-seed from the
nearest catalog NF (the ~4,209 library). The small LLM is the first-draft translator inside the verify-fix
loop, not a trusted one-shot converter. Every successful conversion is also a verified training pair
(execution-grounded code-SFT) — the data engine again.

## 4. Benchmark: add convert-from task kinds (to `evaluation/datasets/nextflow_coding/`)
Extend the Nextflow coding benchmark with `convert_from_snakemake`, `convert_from_wdl`, `convert_from_cwl`,
`convert_from_notebook` task kinds — each: a small real source in that language + the expected contract,
graded by the same tiered execution grader (parse → stub-run → tiny real run). This makes the gap
**measurable** per source language. *(To be appended after the base benchmark agent commits, to avoid
colliding on that dir.)*

## 5. First new converter — Snakemake → Nextflow (scope)
Highest-value + well-specified mapping:
- **Rule → process:** each Snakemake `rule` → an NF `process`; `input:`/`output:` (named/positional) →
  NF `input:`/`output:` channels; `shell:`/`run:`/`script:` → NF `script:`; `params:`→ NF params/`val`;
  `threads:`/`resources:` → `cpus`/`memory`; `conda:`/`container:` → NF `conda`/`container`; `wildcards`
  → channel metadata / tuple keys.
- **DAG wiring:** Snakemake infers the DAG from input/output filename matching; emit the NF `workflow {}`
  block by resolving rule input→output dependencies into channel plumbing (the hardest part — the LLM-bound
  core; stub-run verifies the wiring).
- **Entry/targets:** Snakemake `rule all:` / target files → the NF workflow's terminal emit.
- **Approach:** rule-by-rule deterministic skeleton (R-rules: direct field maps) + LLM for the shell/script
  bodies and the DAG resolution (S-seeded by retrieving a similar catalog NF), then **stub-run verify →
  fix**. Deliver as a `snakemake-to-nextflow` skill; measure on the new `convert_from_snakemake` benchmark
  tasks; harvest the Dockstore Snakemake corpus (the `fetch_workflows.py` already pulls Snakemake) as
  both source material and, after conversion+stub-run, execution-grounded training pairs.
- **Honesty:** `run:` directives (inline Python) and complex wildcard/checkpoint logic are the hard cases —
  flag/abstain rather than silently mis-convert; a stub-run pass ≠ semantic equivalence (note the limit).
