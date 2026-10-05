# nextflow_coding — an execution-graded Nextflow coding benchmark

Measures a model's ability to **write Nextflow (DSL2) that actually runs**, scored by
**execution**, not string similarity. This follows BioMate's execution-grader philosophy
(see `project_execution_grader` memory / `docs` on execution grading): a pass means the real
`nextflow` binary accepted the code and produced the contracted output — never a regex over the
generated text.

It is the *code-generation* complement to the existing selection benchmarks: `routing` /
`cross_domain_routing` test **which** workflow to pick, `bioc_method_selection` tests **which**
method; this tests whether the model can **produce a correct pipeline** at the Nextflow-source level.

## The 3 task kinds (`tasks.jsonl`, 12 tasks: 4 / 4 / 4)

| kind | input the model gets | what it must produce |
|---|---|---|
| **convert** | an existing script (`source`, in bash / Python / Snakemake) + a spec | an equivalent Nextflow DSL2 pipeline |
| **fix** | a broken `.nf` (`broken_nf`) with ONE specific real bug | the corrected `.nf` |
| **write** | a prose spec only | a minimal DSL2 pipeline from scratch |

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

**Per-task score** (max 1.0): A = 0.34, B = 0.33, C = 0.33; for `runnable:false` tasks (no Tier C)
the A+B weights are renormalised to 1.0 so kinds are comparable. In this release all 12 tasks are
`runnable:true`.

`expected_contract` per task: `{tierB_stub, runnable, outputs:[{glob, contains:[...]}]}`.

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
a worked example of the target style, and a **grader regression fixture** (all 12 must score 1.0).

## Honesty notes (strict)

- **Every reported pass means `nextflow` ran and returned the expected result.** The grader never
  pattern-matches the `.nf` text. If `nextflow` is not on PATH, `grade.py` and `run_bench.py` **exit
  with an error** rather than emitting fake passes.
- **Grader validated in this environment** (nextflow 25.10.6, Java 17.0.8, macOS):
  - *Correct → pass:* all 12 `reference/*.nf` → A/B/C all pass, mean_score **1.0**.
  - *Broken → fail:* the original `broken_nf` of all four fix tasks scores 0 (three fail Tier A; the
    emit bug scores 0.34 = passes A, fails B — confirming A and B are independent execution gates).
- **Small + synthetic by design.** 12 tasks is a smoke-scale discrimination probe, not a
  leaderboard; coreutils stand in for real bioinformatics tools so the bar is "correct Nextflow
  *mechanics*", not "correct genomics". Extending to tool-bearing tasks (needs containers/conda) is
  future work and should stay a separate, explicitly-flagged tier.
- **No fabricated scores.** Any model baseline in `results/` was produced by actually running
  `run_bench.py`; token usage / cost is recorded alongside.
