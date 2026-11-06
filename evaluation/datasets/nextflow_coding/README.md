# nextflow_coding — an execution-graded Nextflow coding benchmark

Measures a model's ability to **write Nextflow (DSL2) that actually runs**, scored by
**execution**, not string similarity. This follows BioMate's execution-grader philosophy
(see `project_execution_grader` memory / `docs` on execution grading): a pass means the real
`nextflow` binary accepted the code and produced the contracted output — never a regex over the
generated text.

It is the *code-generation* complement to the existing selection benchmarks: `routing` /
`cross_domain_routing` test **which** workflow to pick, `bioc_method_selection` tests **which**
method; this tests whether the model can **produce a correct pipeline** at the Nextflow-source level.

## Task kinds (`tasks.jsonl`, 20 tasks)

Base kinds (12 — 4 / 4 / 4):

| kind | input the model gets | what it must produce |
|---|---|---|
| **convert** | an existing script (`source`, in bash / Python / Snakemake) + a spec | an equivalent Nextflow DSL2 pipeline |
| **fix** | a broken `.nf` (`broken_nf`) with ONE specific real bug | the corrected `.nf` |
| **write** | a prose spec only | a minimal DSL2 pipeline from scratch |

Extension kinds (8 — cross-language conversion + decomposition, added 2026-10-05):

| kind | count | input the model gets | what it must produce |
|---|---|---|---|
| **convert_from_wdl** | 2 | a small WDL workflow (tasks + `call` wiring; one uses `scatter`) | equivalent DSL2 NF |
| **convert_from_cwl** | 2 | a small CWL source (one `CommandLineTool`, one 2-step `Workflow`) | equivalent DSL2 NF |
| **convert_from_notebook** | 2 | a Jupyter `.ipynb` (3 cells: load → transform → write), JSON-embedded | a **decomposed** NF (≥2 processes) |
| **decompose_script_to_pipeline** | 2 | a multi-step Python **and** R script where the DAG is IMPLICIT in in-memory dataflow | a **decomposed** multi-process NF (≥3 processes, correct wiring) |

`decompose_script_to_pipeline` is the key LLM-bound capability (the same decomposition the task-split
work probes): the model must turn an implicit in-memory DAG (produce ids → per-item work in parallel →
aggregate) into explicit `process`→channel→`process` wiring. A monolithic one-process "conversion"
is penalised — see `min_processes` below.

All tasks are **small and tool-free**: reference solutions use only coreutils
(`echo`/`cat`/`printf`/`wc`/`sort`/`tr`/`seq`) as stand-in "tools", so every tier runs in any
environment with `nextflow` + Java 17+ and **no bioinformatics binaries**. Style is grounded in
real nf-core / Nextflow DSL2 patterns: `nextflow.enable.dsl=2`, `process` blocks with
`input:` / `output:` / `script:` (and `stub:`), named `emit:` channels, `Channel.of(...)`,
`.collect()`, process chaining, and `params`.

The four **fix** bugs are specific and real:

| task | bug | caught at |
|---|---|---|
| `fix_dsl1_dsl2_mix` | `nextflow.enable.dsl=1` declared while using DSL2 `workflow {}` syntax | Tier A |
| `fix_channel_cardinality` | process declares 2 input channels, workflow calls it with 1 argument | Tier A |
| `fix_bad_process_invocation` | workflow invokes an undefined process (`GREET_USER` vs `GREET`) | Tier A |
| `fix_missing_output_emit` | workflow reads `MAKE.out.seed` but the upstream `output:` has no `emit: seed` | **Tier B** (parses fine, fails when wired) |

`fix_missing_output_emit` is the deliberate Tier-A/Tier-B separator: it **compiles** but **does
not run as a pipeline**, proving Tier A and Tier B are distinct execution gates.

## The tiered grader (`grade.py`)

The grader **invokes `nextflow` for every pass it reports**. Tiers are gated (B needs A, C needs B):

- **Tier A — parse / compile:** `nextflow run <f> -preview` → exit 0. Syntax valid and the DAG builds.
- **Tier B — pipeline wiring:** `nextflow run <f> -stub-run` → exit 0. Every process runs its
  `stub:`/`script:` block with **no real tools or data**; validates channel cardinality, process I/O
  and `emit` wiring end-to-end. The cheap "does it run as a pipeline" signal.
- **Tier C — real execution + output contract** (tasks flagged `runnable:true`): `nextflow run <f>`
  → exit 0, **and** the run directory (scanned recursively, covering `work/<hash>/` and any
  `publishDir`) must contain each expected output file with the required content substrings. This is
  the actual output-contract check — the pipeline produced the right file with the right bytes.

**Decomposition contract (`min_processes`).** Conversion/decomposition tasks that must NOT be crammed
into one process carry `min_processes: N` in their contract. During Tier B the grader runs
`-stub-run -with-trace trace.txt` and **counts the DISTINCT process names that actually executed** (from
the real Nextflow trace; fan-out tags like `TAG (2)` collapse to `TAG`). Tier B passes only if the stub
run succeeded **and** `n_processes ≥ min_processes`. This is an execution signal — the DAG really ran
with that many processes — not a regex over the `.nf` text. A monolithic one-process "conversion"
stub-runs fine but reports `n_processes = 1`, so it **fails Tier B** and (because C is gated on B)
scores only the Tier-A credit (0.34) versus a decomposed solution's 1.0.

**Per-task score** (max 1.0): A = 0.34, B = 0.33, C = 0.33; for `runnable:false` tasks (no Tier C)
the A+B weights are renormalised to 1.0 so kinds are comparable. All 20 tasks are `runnable:true`.

`expected_contract` per task: `{tierB_stub, runnable, min_processes?, outputs:[{glob, contains:[...]}]}`.

## How to run

```bash
cd evaluation/datasets/nextflow_coding
python3 build_tasks.py                       # (re)generate tasks.jsonl

# grade pre-generated files (named <task_id>.nf) — e.g. the gold references:
python3 grade.py tasks.jsonl --gen-dir reference --out results/reference.json

# grade one file against one task:
python3 grade.py tasks.jsonl --task-id write_status_pipeline --nf some.nf

# full benchmark: generate from a model via OpenRouter, then grade:
export OPENROUTER_API_KEY=$(cat ~/.config/biomate/openrouter.key)
python3 run_bench.py deepseek/deepseek-v4.1-flash
```

Env knobs: `NEXTFLOW_BIN` (default `nextflow`), `NF_TIMEOUT` (per-invocation seconds, default 240).

### Pointing at the local 9B later

The local 9B is training / not served yet, so OpenRouter is the baseline path. When a served
OpenAI-compatible endpoint exists (e.g. vLLM), run the exact same benchmark against it:

```bash
export OPENROUTER_BASE=http://localhost:8000/v1/chat/completions
export OPENROUTER_API_KEY=dummy
python3 run_bench.py biomate-9b
```

`grade.py` executes the real `nextflow` binary regardless of which model wrote the `.nf`, so local
and hosted models are scored on the identical execution bar.

## `reference/` — gold solutions

`reference/<task_id>.nf` holds a correct, minimal solution for every task. They serve two purposes:
a worked example of the target style, and a **grader regression fixture** (all 20 must score 1.0;
`results/reference.json`).

## Honesty notes (strict)

- **Every reported pass means `nextflow` ran and returned the expected result.** The grader never
  pattern-matches the `.nf` text (including the `min_processes` check, which counts processes from the
  real stub-run trace). If `nextflow` is not on PATH, `grade.py` and `run_bench.py` **exit with an
  error** rather than emitting fake passes.
- **Grader validated in this environment** (nextflow 25.10.6, Java 17.0.8, macOS):
  - *Correct → pass:* all 20 `reference/*.nf` → A/B/C all pass, mean_score **1.0**. The decompose
    references really execute 3 distinct processes (`n_processes = 3`); the ≥2-process conversions
    report `n_processes = 2`; the single CWL tool reports 1 (no `min_processes` set).
  - *Broken → fail:* the original `broken_nf` of all four fix tasks scores 0 (three fail Tier A; the
    emit bug scores 0.34 = passes A, fails B — confirming A and B are independent execution gates).
  - *Monolithic decomposition penalised:* a one-process `.nf` that produces the correct report.txt for
    `decompose_python_pipeline` scores **0.34** (passes Tier A, **fails Tier B** with `n_processes = 1
    < 3`, so Tier C never runs) versus the decomposed reference's **1.0** — proving the contract
    rewards correct decomposition, not just correct output.
- **Small + synthetic by design.** 20 tasks is a smoke-scale discrimination probe, not a
  leaderboard; coreutils stand in for real bioinformatics tools so the bar is "correct Nextflow
  *mechanics* / decomposition", not "correct genomics". Extending to tool-bearing tasks (needs
  containers/conda) is future work and should stay a separate, explicitly-flagged tier.
- **All kinds validated to stub-run tool-free.** Every new kind (WDL/CWL/notebook/decompose) has a
  passing coreutils-only reference; none required a tool that could not stub-run, so nothing here is
  faked or marked "unvalidated".
- **No fabricated scores.** Any model baseline in `results/` was produced by actually running
  `run_bench.py`; token usage / cost is recorded alongside.
