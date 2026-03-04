# Running and Monitoring a BioMate Workflow

Once BioMate has understood your query, it generates a workflow card in the chat panel.
This page walks through everything that happens from that point — execution, monitoring,
and result retrieval.

---

## The Workflow Card

After query processing, a **workflow artifact card** appears alongside BioMate's response.
The card summarises:

| Field | What it means |
|---|---|
| Tool count | Number of pipeline steps (e.g., "8 steps") |
| Estimated runtime | Wall-clock estimate based on sample count and compute profile |
| Execution engine | **Nextflow** (new pipelines) or **Galaxy** (legacy tool wrappers) |
| QC profile | The named QC profile that will be applied (e.g., `rnaseq_polya_standard`) |

You can expand the card to inspect individual steps, their parameters, and the tool
versions before committing to execution.

---

## The Pilot Run Feature

For datasets with 50 or more samples, BioMate automatically suggests a **Pilot Run**
before the full analysis.

### What a pilot run does

- Selects a representative subset of your samples (default: 20% of total, minimum 3
  samples).
- Runs the complete pipeline on that subset — including all QC gates.
- Returns full QC results within a fraction of the total compute time.
- Lets you verify that QC thresholds are appropriate before committing to the full run.

### Why it matters

Running QC on a small representative cohort catches problems early:
- Batch effects or mislabelled samples become visible in the pilot QC report.
- If a QC gate fails (e.g., low alignment rate for an unexpected library type), you can
  adjust the QC profile or override a threshold before spending hours on all samples.
- If the pilot passes, full execution starts automatically.

### Skipping the pilot

If you are re-running a workflow you have validated before, or your dataset is small
enough that a pilot is redundant, click **"Skip pilot, run full"** on the workflow card.
This option is always available before execution begins.

> **Note:** On datasets with fewer than 50 samples, the pilot run suggestion is suppressed
> and the workflow executes directly.

---

## Starting a Full Workflow

Click **"Execute Workflow"** on the workflow card. BioMate queues the job and immediately
returns control to the chat interface — you do not need to wait on this page.

What happens in the background:

1. BioMate submits the Nextflow pipeline (or Galaxy invocation) to the configured compute
   backend.
2. A live progress panel opens below the workflow card.
3. Each pipeline step transitions through: `queued` → `running` → `complete` (or `failed`).
4. QC gates are checked as each step completes; see [Understanding BioMate QC Output](03_read_qc_output.md).

---

## Live Progress Monitoring

The progress panel streams real-time updates via server-sent events (SSE). You will see:

```
[✓] FASTQC              2 / 12 samples complete
[▶] TRIM_GALORE         running — 6 / 12 samples
[⧖] STAR_ALIGN          queued
[⧖] MARKDUPLICATES      queued
[⧖] FEATURECOUNTS       queued
[⧖] DESEQ2_DIFFERENTIAL queued
```

Individual step logs are accessible by clicking the step name. Logs include standard
output, standard error, and resource usage (CPU, memory, wall time).

### What to do while it runs

You do not need to keep the browser tab open — workflows run asynchronously. You can:

- Send new queries in the same or a different chat session.
- Close the browser and return later; the workflow continues running on the server.
- Switch to another project; the progress panel resumes automatically when you return.

A notification appears in the chat when the workflow completes or if a QC gate fails.

---

## Compute Settings

By default, BioMate runs workflows on the local compute node. For large datasets you can
switch to a cluster or cloud backend.

To configure compute settings: open **Settings** (top-right menu) → **Compute** tab.

| Executor | When to use |
|---|---|
| `local` | Development, small datasets (< 20 samples), single-node servers |
| `slurm` | HPC clusters managed by SLURM; configure queue, CPUs, and memory limits |
| `awsbatch` | AWS cloud execution; requires an S3 bucket and an AWS Batch compute environment |

Per-run overrides are also accepted: if your system administrator provides a
`compute_config` block, it can be passed with the workflow execution request via the API.

---

## Estimated Runtimes for Common Workflows

These estimates assume default compute settings (single server, 16 CPU cores, 64 GB RAM).
Actual runtimes scale with sample count and cluster configuration.

| Workflow | Samples / scale | Estimated wall time |
|---|---|---|
| Bulk RNA-seq (DE + enrichment) | 12 samples | ~25 min |
| Single-cell RNA-seq (clustering + annotation) | 50,000 cells | ~45 min |
| ATAC-seq (peak calling + differential) | 8 samples | ~30 min |
| Cryo-EM SPA (full pipeline) | 2,000 micrographs | 4–8 hours |
| AlphaFold3 + DiffDock (single target) | 1 protein | ~30 min (API) / ~6 h (local GPU) |
| WGS germline variant calling | 4 samples, 30× | ~2 hours |
| Metagenomics (Kraken2 + Bracken) | 12 samples | ~40 min |

---

## Execution Engines

**Nextflow** (DSL2) is used for all new BioMate pipelines. It provides fine-grained
parallelism, container isolation per step, and reproducible provenance.

**Galaxy** wraps legacy tool XML definitions. Some older workflows may still use Galaxy
as the backend. The workflow card clearly labels which engine is in use; the monitoring
UI is identical for both.

---

## Exporting Results

When a workflow finishes, the workflow card shows two export options:

- **QC Report (HTML)** — a self-contained HTML file with per-step QC summaries, plots,
  and threshold evidence citations. Suitable for lab meeting presentations or manuscript
  supplementary material.
- **Workflow Logs** — a compressed archive (.zip) containing Nextflow trace files,
  per-process logs, and the parameter JSON used for the run.

Both are also accessible via the API:

```
POST /api/export/qc_report
{
  "invocation_id": "<workflow-invocation-id>"
}
```
