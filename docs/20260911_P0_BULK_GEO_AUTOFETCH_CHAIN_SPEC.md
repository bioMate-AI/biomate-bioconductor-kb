# P0 · Bulk GEO auto-fetch chain — ready-to-implement spec

**Date:** 2026-09-11 · **内部文档** · branch `integration/dev-test`
**Why:** The #1 user-journey smoothness gap for the "reproduce a paper" use case
([[20260911_REPLICATION_USER_JOURNEY_UX_AUDIT]]): a **bulk RNA-seq** GEO request
(e.g. "reproduce GSE104687") yields an `nf-core/differentialabundance` card with
**`matrix`/`samplesheet` = null** and marked `required:false` → a deceptively-runnable
**empty card**; the accession is never resolved to data. (scRNA pseudobulk already
auto-fetches via the `geo_scrna_deg_v2` chain; bulk has no equivalent.)

**Status:** spec only — NOT shipped. Chain execution semantics (chain-as-unit,
step1→step2 output passing) require an AWS Batch run to verify; shipping unverified
into the active test branch is disallowed (review-before-deploy). Implement + verify
together.

---

## Fix (mirror the existing `geo_scrna_deg_v2` pattern)

### 1. New chain template — `backend/lib/galaxy/ai/bioc_chain_templates.py`
Add alongside `geo_scrna_deg_v2`:

```python
{
    "name": "geo_bulk_deg_v2",
    "display_name": "GEO Accession → Auto-fetch → Bulk Differential Expression",
    "domain": "transcriptomics",
    "description": (
        "End-to-end differential expression from JUST a bulk RNA-seq / microarray "
        "GEO accession with NO pre-staged files. Step 1 (geo_data_connector) fetches "
        "the count matrix + sample metadata via GEOquery; step 2 runs DESeq2. The user "
        "provides only the GEO ID. Do NOT use for single-cell (that is geo_scrna_deg_v2) "
        "or when the user already has an S3-staged matrix (differentialabundance-only)."
    ),
    "steps": [
        {"order": 1, "workflow_name": "geo_data_connector", "role": "geo_ingest", "params_template": {}},
        {"order": 2, "workflow_name": "nf-core/differentialabundance", "role": "differential_expression", "params_template": {}},
    ],
    "connections": [
        # geo_data_connector emits (verified in its main.nf): count_matrix.csv / sample_metadata.csv
        {"from_step": 1, "from_output": "count_matrix",    "to_step": 2, "to_input": "matrix"},
        {"from_step": 1, "from_output": "sample_metadata", "to_step": 2, "to_input": "samplesheet"},
        # differentialabundance auto-derives contrasts from the samplesheet metadata (no connector 'contrasts' output).
    ],
    "required_inputs": ["geo_accession"],
    "expected_outputs": ["de_table", "significant_genes", "volcano_plot"],
    "example_queries": [
        "run differential expression on GSE104687",
        "reproduce the DE analysis from this bulk RNA-seq GEO series",
        "download GSE... and run DESeq2 on the bulk data",
    ],
    "tags": ["geo", "bulk", "rnaseq", "microarray", "deseq2", "differentialabundance", "accession"],
    "trigger_on_workflows": ["geo_data_connector"],
    "trigger_on_output_extensions": [],
},
```

### 2. Routing change — `backend/lib/galaxy/ai/ai_assistant.py`
In `_try_fast_path_geo_scrna_pseudobulk`'s modality gate, the `bulk_rnaseq`/`microarray`
branch currently **defers to bare differentialabundance (empty matrix)**:

```python
if _platform in ('microarray', 'bulk_rnaseq'):
    log.info(... "deferring to normal routing (limma/differentialabundance)")
    return None                      # ← produces the empty card
```

Change so a **bare GEO accession + no S3 paths + bulk/microarray** routes to
`geo_data_connector` (base of `geo_bulk_deg_v2`), which self-fetches — instead of the
empty differentialabundance card. Gate it with the SAME conservative conditions already
in this function (GSE present, no `s3://…` paths) so it only affects the currently-broken
case and NOT the with-data differentialabundance path the team tests. (Prefer a sibling
`_try_fast_path_geo_bulk_connector` returning a `geo_data_connector` workflow_ga with
`geo_accession` prefilled, to keep the scRNA/bulk paths cleanly separated.)

**Safety:** this can only *fix* the currently-broken empty-card case; it cannot regress
the working "user supplies matrix" path (that hits CASE A / S3-path skip first).

---

## Verification (required before merge)
1. Real Batch run of the chain on a small bulk set (e.g. GSE104687 or a tiny GSE):
   confirm step-1 `count_matrix.csv`/`sample_metadata.csv` land as step-2 `matrix`/`samplesheet`.
2. Parity: DE table + volcano produced; sanity-check DEG direction vs the paper.
3. UI: card shows the CHAIN (2 steps) with data wired (not null); Confirm & Run → live
   progress → findings + report. No empty card, no "missing data" dead end.
4. Regression: a normal "here's my matrix.csv" differentialabundance request still routes
   to differentialabundance-only (chain NOT triggered).

## Related (not this spec)
- scRNA **clustering** from a GEO accession still needs a raw-FASTQ→`nf-core/scrnaseq`
  path (pseudobulk chain only covers pseudobulk-DE). Separate P0 item.
- Non-GEO (NGDC/CNCB `HRA…`) fetch: `geo_data_connector` uses GEOquery (GEO-only) →
  Chinese-archive fetch is a separate gap.

---

## Verification progress (2026-09-11, live dev)

**Root blocker found + fixed (shipped, commit `4b3b9fec6`):** `geo_data_connector` marked
`local_series_matrix` **required**, blocking every accession-only run with
`missing_required_params` ("needs 1 required parameter: local_series_matrix. No compute
was launched"). Cause: the `.nf` param parser (`ai_assistant.py:2398`) treats any
`null`-default param as required unless allowlisted in `_OPTIONAL_NULL_PARAMS`;
`local_series_matrix` (null = auto-download from GEO) wasn't listed. **Fix: added it to
`_OPTIONAL_NULL_PARAMS`.** This is ALSO the same `missing_required_params` that killed the
earlier open-claw `run_workflow`.

**Verified:** a live `/api/workflows/execute` of the connector (GSE108000) confirmed
`required_params == ['local_series_matrix']` (sole blocker) and, once past it, the run
**launched** (runId `8bfc12f8…`, status `running`). So the fix unblocks launch.

**Inconclusive (needs deployed fix + real product flow):** the launched Nextflow run then
failed at setup after 20 s — `GEO_FETCH` still `pending`, `processes: []`, empty log_tail,
returncode 1. Likely a **test-rig artifact**: the verification request was hand-built
(stripped required_param + `defer_param_prefill`), bypassing normal param-prefill, so the
minimal workflowDefinition may lack config the executor needs. Confirm connector
completion (emits `count_matrix.csv` / `sample_metadata.csv`) via the **deployed fix run
through the real product flow**, or by reading the S3 `.nextflow.log` in the work dir.
