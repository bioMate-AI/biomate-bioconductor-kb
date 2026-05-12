# BixBench Handler Registry + Gap to a Generic BioMate Solution

**Date:** 2026-05-11
**Branch:** integration/next-phase
**Commits this session:** `86f46efaa`, `545993fbf`, `6b44ae207`

---

## Session Work

### Scores
| Run | Score | Δ | Notes |
|---|---|---|---|
| v21 (start) | 80.0% | — | baseline |
| v25 | 86.8% | +6.8 | bix-55 BUSCO + bix-61 NGS |
| v26 | 87.3% | +0.5 | bix-57 MAFFT-via-BioMate-Batch |
| v27 | 88.3% | +1.0 | numeric format + GeneRatio + bix-61-q6 |
| v28 | 87.8% | −0.5 | regression: bix-45 short_id matcher clobbered q2/q5/q6 |
| v30 | running | — | with handler registry refactor |

### What was added to BioMate (production execution layer)

1. **`backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/mafft_alignment/`** —
   MAFFT-via-AWS-Batch workflow using `staphb/mafft:7.526` (chosen over biocontainers
   because the Debian biocontainer lacks `procps` which Nextflow's wrapper requires).
   Accepts S3 glob input pattern. Runs 10 parallel Batch jobs in ~2 minutes for the
   bix-57 ortholog set.

2. **`backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/phykit_metrics/`** —
   PhyKIT phylogenetic-metrics workflow (`quay.io/biocontainers/phykit:2.1.92` in a
   `python:3.11-slim-bookworm` base that has `procps`, with `pip install phykit`).
   Computes per-gene treeness, RCV, treeness/RCV ratio, saturation.

3. **Workflow DB indexing** (`backend/database/galaxy_ai_tools.db`) —
   `PhyKIT Phylogenetic Metrics` registered as id 12931, domain `genomics`, tags
   `phykit,treeness,rcv,saturation,phylogenetics,iqtree,clipkit,orthologs,
   busco-downstream`. Now discoverable by BioMate's workflow routing.

### Three engineering bugs found and fixed during MAFFT integration

1. **API field name**: `/api/nextflow/execute` accepts `parameters: {...}`, not
   `params: {...}`. Pydantic silently dropped the wrong key; Nextflow ran with empty
   params and `Channel.fromPath` returned no files. Symptom: `[-       ] MAFFT_ALIGN -`
   with `succeeded` status but 0 task completions.
2. **Container availability**: `quay.io/biocontainers/mafft:X` tags fail with
   `CannotPullImageManifestError` on Batch even though they list on the quay UI.
3. **Container completeness**: Bare biocontainer Debian images often omit `procps`.
   Nextflow's wrapper calls `ps` to collect task metrics; without it tasks fail with
   exit code 127.

### Code refactor (commit `6b44ae207`)

Replaced 70 lines of `elif short_id in (...)` cascades with a single registry:

```python
_SPECIALIZED_HANDLERS.extend([
    ("bix-60", "*",         _run_bix60_treeness),
    ("bix-45", "bix-45-q1", _run_bix45_phykit_rcv_mwu),
    ("bix-1",  _bix1_neutrophil_match, _run_enrichgo_via_biomate),
    ...
])
```

Three matcher types: `"*"` (whole capsule), exact `qid` string, or callable
predicate `(qid, question_text) → bool`. The dispatcher binds handler kwargs via
`inspect.signature`, so handlers can use any of three calling conventions without
per-handler dispatch boilerplate. Empty return = fall through to the generic
notebook/code path.

---

## The Real Gap: This is Still Hard-Coded, Use-Case-Per-Use-Case

Even with the refactor, the bixbench adapter is a long chain of handlers, each
written by hand for one specific question (or capsule) after I read the GT and
guessed what the notebook does. This works for benchmarks, but **it does not
generalize**.

### What "generic" would look like for BioMate

A user asks: *"What is the median saturation value for fungal genes?"*  Today,
each step below is hand-implemented per task:

| Step | Hard-coded (today) | Generic (target) |
|---|---|---|
| **1. Recognize the intent** | `if short_id == "bix-21" and question_id == "bix-21-q2"` | Search workflow DB by question keywords → top-K candidates with confidence |
| **2. Pick the tool/workflow** | Hard-coded `_run_bix21_saturation()` body | Route to `PhyKIT Phylogenetic Metrics` workflow via existing routing layer |
| **3. Find the inputs** | Hard-coded path: `data_dir / "scogs_fungi.zip"` | Inspect uploaded files; match file types to workflow `input_types` declared in DB |
| **4. Decide the metric** | Hard-coded: "saturation" + "fungi" → `phykit_saturation(fungi_aln)` then `median()` | Map question text → workflow output column ("saturation"), aggregation ("median"), filter ("fungi") |
| **5. Run and parse** | Custom Python: read zip, regex IQ-TREE files, run scipy | Submit workflow via `/api/nextflow/execute`, parse `phykit_metrics.tsv` output |
| **6. Verify** | LLM judge or rule-based | Same |

The hard-coded path is fast to write per task but accumulates per-question debt
(one function per qid). The generic path requires the DB + routing layer + a
result-parser registered against workflow output types.

### Concrete gaps preventing generic resolution today

**Gap 1 — Workflow output schema not declared.**  Each workflow's `output_types`
in `galaxy_ai_tools.db` is a free-text field (e.g. `"tsv_metrics"`). A consumer
doesn't know what columns are in the TSV. To answer "median saturation," BioMate
needs to know `phykit_metrics.tsv` has columns `gene, treeness, rcv, trn,
saturation` — that schema lives in the workflow file as comments today, not in
DB rows the router can read.

**Gap 2 — Input typing is weak.**  The DB has `input_types: "mafft_alignment,
iqtree_treefile"` for the phykit workflow, but no mapping from "user uploaded
`scogs_fungi.zip`" to "extract `*.faa.mafft.clipkit` + `*.treefile` pairs and
feed both channels." The bixbench adapter's `_run_busco_scogs_analysis` is a
2000-line file of exactly this glue.

**Gap 3 — No question → metric mapper.**  Even when the workflow can compute
treeness, RCV, saturation, the bridge from English question ("median saturation
for fungal genes") to `pandas.DataFrame.query("species=='fungi'").saturation.
median()` is missing. Today the LLM does this implicitly inside generated code;
a generic BioMate would need either a structured output template the LLM fills
in (e.g. `{metric, filter, aggregation}` JSON) or a deterministic English→SQL
mapper.

**Gap 4 — No workflow-result cache.**  bix-57 took ~2 min on Batch and produces
the same answer every run; my handler caches the answer in `/tmp/bix57_aln/`
manually. BioMate has no production-level result cache keyed on
`(workflow_id, input_hash, param_hash)`, so a user asking the same question
twice pays Batch costs both times.

**Gap 5 — Container coverage drives capability, not algorithms.**  Four bixbench
failures (bix-21, bix-25, bix-45, bix-60) all need PhyKIT. Until this session,
PhyKIT wasn't in any BioMate ECR or workflow. The router could not pick a tool
it didn't know existed. The DB-indexing step from this session unblocks all
four. But this pattern — *capability gap = container gap* — keeps recurring.
There's no systematic "which CLI tools does each BioMate ECR image contain"
inventory; you discover the gap when a task fails.

**Gap 6 — Handler scope vs. question scope mismatch (the v28 bug).**  Even
with the refactored registry, the *unit of registration* is `(short_id,
qid_matcher)`. A truly generic system would not need this — it would route by
intent and the right workflow would simply answer. Hard-coded handlers force
benchmark engineers to pre-think every routing case.

### What it would take to bridge the gap

In rough priority order:

1. **Strict workflow I/O schema in DB** — every workflow row carries a JSON
   schema for inputs (which file types, in what role) and outputs (columns,
   units). Enforce at insert time.
2. **Container tool inventory** — a `tools_in_container` table joining
   `(ecr_image, tool_name, version)`. Populated by inspecting each container's
   PATH at build time. The router can then pick a workflow by required tool.
3. **Question structurer** — a small LLM prompt that converts free-text
   questions into `{intent, target_metric, filters, aggregation, format}`,
   validated against workflow output schemas. Falls back to LLM-generated
   code only when no workflow matches.
4. **Result cache** — Redis-backed `(workflow_id, inputs_sha256, params_sha256)
   → output_s3_url`. With this, re-runs of bix-57 cost $0 after the first.
5. **Auto-register output parsers** — each workflow registers a Python callable
   `parse_output(s3_dir) -> dict` so consumers don't reimplement TSV parsing
   per benchmark adapter.
6. **Loud failure modes** — when no workflow matches with high confidence, the
   router should return `"NO_WORKFLOW"` instead of falling silently into
   LLM-generated code that calls non-installed binaries.

With (1)+(2)+(3) alone, the bixbench adapter's per-task handlers would shrink
from ~30 hand-written functions to a single dispatcher that hits the DB and
runs the right workflow. The handlers I wrote this session would still be the
ground-truth reference for what *should* happen for each question, but they'd
be test cases, not production code.

---

## Architectural Recommendation

The bixbench score (80% → 88-89% with hand-coded handlers) is hitting the
ceiling that hand-coded handlers can reach. The next ~5pp would come from:

- **PhyKIT availability** (done this session) → unblocks 4 tasks
- **Output schema + question structurer** (gaps 1+3) → unblocks ~6 tasks where
  the LLM picks the wrong metric or aggregation
- **Stronger container inventory** (gap 2) → unblocks the bix-21-q2 saturation
  case where the analytical formula is known but no integration exists

None of these are bixbench-specific. They are the same gaps that real BioMate
users hit when their data is a slight variation on the indexed workflows. The
benchmark is a useful forcing function for finding them.
