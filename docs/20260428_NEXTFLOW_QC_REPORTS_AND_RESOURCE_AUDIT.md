# Nextflow QC Reports, Scientific Quality Control, and Resource Auditing in BioMate

**Date:** 2026-04-28
**Scope:** What Nextflow produces, how BioMate integrates it, and where BioMate's QC adds unique value

---

## Background: Two Complementary QC Layers

BioMate runs Nextflow pipelines as its scientific compute engine.
Nextflow and its nf-core community have built a rich ecosystem of quality
control tools that BioMate respects and builds on rather than replaces.
BioMate adds a second, active-control QC layer that drives auto-remediation,
dynamic threshold management, and real-time alerting.

The distinction matters for marketing: BioMate does not compete with MultiQC
or the nf-core QC ecosystem — it **orchestrates them** and adds
domain-aware intelligence that static reports cannot provide.

---

## Part 1 — What Nextflow Produces

### 1a. Infrastructure Execution Reports (Universal — Every Run)

Every Nextflow workflow automatically generates:

| File | Size (typical) | Content |
|------|---------------|---------|
| `pipeline_info/report.html` | 2.8 MB | Per-task resource table: CPU%, RSS/VMem, disk I/O, duration, allocated vs. actual resources, container, queue, script |
| `pipeline_info/timeline.html` | 250 KB | Gantt chart of task execution timing (D3.js) |
| `pipeline_info/trace.txt` | <50 KB | Same data as report.html, TSV format, machine-readable |
| `pipeline_info/dag.html` | <100 KB | Workflow DAG visualization (Mermaid/Graphviz) |

**Key data in `report.html` (`window.data.trace`):**
```json
{
  "task_id": 1,
  "process": "LIGAND_PREP",
  "status": "COMPLETED",
  "queue": "galaxy-cloud-queue",
  "container": "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ambertools-gromacs-nf:latest",
  "duration": 278424,       // wall clock ms
  "realtime": 192504,       // CPU-active ms
  "%cpu": 182.5,            // actual CPU utilization (e.g., 182.5% of 1 core = 1.825 cores used)
  "%mem": 0.2,
  "rss": 50573312,          // bytes — actual resident set size
  "peak_rss": 50573312,     // bytes
  "vmem": 979988480,        // bytes
  "read_bytes": 0,
  "write_bytes": 229376,
  "cpus": 4,                // allocated CPUs
  "memory": 8589934592,     // allocated memory bytes
  "cpu_model": "Intel(R) Xeon(R) CPU E5-2686 v4 @ 2.30GHz"
}
```

This data enables:
- **vCPU-hour billing**: `cpu_fraction × duration_hours` per task, summed
- **Memory-GB-hour billing**: `rss_GB × duration_hours` per task, summed
- **Resource efficiency**: allocated vs. actual (over-provisioning detection)
- **Cost attribution**: by queue, container, process type

### 1b. Scientific QC Reports (Domain-Specific — 127+ Workflows)

A survey of BioMate's 2,455 workflow database found **127 workflows with QC output**.
These fall into three categories:

#### Bioconductor R Package QC (32 workflows)

All follow the pattern: CSV + RDS + optional PDF (R plot objects).
Key packages and their metrics:

| Package | Domain | Key Metrics |
|---------|--------|-------------|
| **FastqCleaner** | Sequencing | Quality filtering rate, FASTQ trimming |
| **QCMetrics** | Proteomics | Generic multi-assay QC framework |
| **ngsReports** | RNA/DNA | FastQC parsing, read totals, quality summaries |
| **Rqc** | Sequencing | Cycle quality, read frequency, quality box plots |
| **miQC** | Single-cell | Mitochondrial fraction, doublet detection, mixture models |
| **ATACseqQC** | ATAC-seq | NFR score, TSS enrichment, PT score, library complexity |
| **ChIPQC** | ChIP-seq | Cross-correlation, peak enrichment, RAP (Reads in Annotated Peaks) |
| **cytofQC** | CyTOF/mass-spec | Bead/debris/doublet detection, density histograms |
| **arrayQualityMetrics** | Microarray | Batch effects, outlier detection, distribution metrics |
| **BatchQC** | Multi-assay | Cramér's V batch effect, PCA, heatmaps |
| **alevinQC** | scRNA-seq | Alevin/Salmon barcode collapse, knee plots |
| **ribosomeProfilingQC** | Ribo-seq | P-site estimation, CDS/UTR coverage |
| **MethylAid** | Methylation arrays | Sample quality detection |
| **MSQuality** | Mass spectrometry | Mass accuracy, RT alignment |
| **DEReport** | Differential expression | DE QC report, MA plots, dispersion |
| **MDQC** | Multi-dimensional | Multi-metric outlier detection |

#### WGS / Genomics MultiQC (1 workflow)

`wgs_germline_gatk` runs 14 steps that each produce a `*.json` report,
then aggregates them via a Python-simulated MultiQC step:

```
FASTQC    → fastqc_report.json   (read quality, GC content, adapter content)
FASTP     → fastp_report.json    (adapter trim rate, quality filtering)
BWA-MEM2  → alignment data
SAMTOOLS  → flagstat_report.json (alignment_rate, mapped reads)
MOSDEPTH  → coverage_report.json (mean_coverage, coverage uniformity)
MARKDUP   → markdup_report.json  (duplicate_rate, library complexity)
GATK      → variant annotation
MULTIQC   → multiqc_data.json    (aggregated QC: PASS/WARN flags)
           → multiqc_report.html (interactive dashboard)
```

`multiqc_data.json` contains:
```json
{
  "alignment_rate": 94.2,
  "duplicate_rate": 12.1,
  "mean_coverage": 31.5,
  "titv_ratio": 2.04,
  "total_variants": 4821037,
  "qc_passed": true,
  "qc_flags": [],
  "qc_summary": "PASS"
}
```

#### Drug Discovery HTS QC (1 workflow)

`hts_plate_qc_hit_calling` produces:
```
qc_metrics.json  — Z'-factor (≥0.5 gate), signal window, CV%, dynamic range
hit_list.csv     — compounds exceeding activity threshold
dose_response.csv — EC50, Hill coefficient, R²
```

#### CryoEM / CryoET (6+ workflows)

CryoSPARC, RELION, and tomo workflows produce JSON metrics for:
- FSC (Fourier Shell Correlation) at 0.143 criterion
- CTF estimation: defocus range, resolution, astigmatism
- Particle counts, 2D class quality, refinement convergence

---

## Part 2 — BioMate's QC Layer: What It Adds

### Architecture

```
                    Nextflow Pipeline
                         │
                    ┌────▼────┐
                    │ Per-step│  fastqc_report.json
                    │ JSON QC │  toxicity_report.json
                    │ reports │  multiqc_data.json
                    └────┬────┘
                         │
          ┌──────────────┴──────────────┐
          │                             │
  ┌───────▼────────┐           ┌────────▼───────┐
  │  Static HTML   │           │  BioMate QC    │
  │  (multiqc.html)│           │  Monitor       │
  │  Visualization │           │  qc_trace_monitor.py
  │  for humans    │           │                │
  └───────┬────────┘           └────────┬───────┘
          │                             │
    iframe display               ┌──────▼──────────────┐
    in output panel              │ Dynamic Gates        │
                                 │ Literature citations │
                                 │ SSE real-time alerts │
                                 │ Auto-loop triggers   │
                                 │ Threshold overrides  │
                                 └──────────────────────┘
```

### Comparison: Pipeline QC vs. BioMate QC

| Dimension | Pipeline QC (MultiQC etc.) | BioMate QC Monitor |
|-----------|---------------------------|---------------------|
| **Trigger** | Post-hoc: after run finishes | Real-time: per-step via Nextflow trace file |
| **Thresholds** | Hardcoded in pipeline params | Dynamic: 32 built-in profiles + per-user overrides |
| **Severity tiers** | Binary pass/fail | GOLD / SILVER / advisory (literature-graded) |
| **Literature citations** | None | PMID citations for every threshold (e.g., Sanguinetti 2006 for hERG 1 µM gate) |
| **Action on failure** | None — static flag | Triggers auto-loop: rewrites params, re-runs, verifies |
| **Communication** | HTML file in output list | SSE events → real-time panel alerts |
| **Domain coverage** | Tool-specific (FastQC, MultiQC) | All domains: ADMET, CryoEM, RNAseq, WGS, docking, NCA-PK, IVIVE, CYP-DDI |
| **AWS Batch support** | Yes (outputs to S3) | Added: `_evaluate_qc_from_s3()` reads S3 post-completion |
| **Cost** | Bundled in pipeline | Part of BioMate platform value |

### Domain-Specific Gates (BioMate only)

**ADMET / Drug Discovery:**
- [GOLD] hERG IC50 < 1.0 µM → QT prolongation risk (FDA E14; Sanguinetti & Tristani-Firouzi 2006)
- [GOLD] DILI "Most-DILI-Concern" classification (FDA DILIrank; Chen et al. 2016)
- [SILVER] Ames positive structural alerts (Kazius et al. 2005 J Med Chem)
- [SILVER] ClinTox probability ≥ 0.7 (FDA clinical toxicity)
- [SILVER] Lipinski Ro5 violations ≥ 2 (bioavailability)

**CryoEM:**
- [GOLD] FSC resolution > user threshold (EMDB deposition standard)
- [SILVER] CTF defocus outside 1,000–100,000 Å
- [ADVISORY] Astigmatism > 1,000 Å (non-blocking)

**Genomics (WGS):**
- Alignment rate < configurable threshold (default 70%)
- Mean coverage < configurable threshold (default 20×)
- Ti/Tv ratio outside 1.8–2.2
- Duplicate rate > 30%

---

## Part 3 — BioMate Integration of Nextflow Reports

### What Changed (2026-04-28)

#### Scientific QC HTML Reports (e.g., multiqc_report.html)

- **Before**: `.html` files were filtered out or shown as download-only `FileOutput`
- **After**: `classifyFileType('html') = 'interactive'` → `InteractiveOutput` iframe (always was correct)
- Fixed `display` endpoint for S3-backed HTML: uses AWS SDK streaming with `Content-Type: text/html`
  (was: redirect to Galaxy presign URL which served wrong Content-Type)
- Added dedicated **"QC Reports"** section in `ChatOutputAttachments` for files matching
  `multiqc|qc.report|fastqc|fastp` — shown with 600px iframe instead of 384px
- `pipeline_info/report.html` and `pipeline_info/timeline.html` remain **excluded from output list**
  but are now accessible via dedicated endpoints

#### Infrastructure Reports (Execution Report + Timeline)

- **Before**: Filtered from output list, no other access
- **After**:
  - `_find_nf_infra_reports()` locates `pipeline_info/report.html` and `pipeline_info/timeline.html` in S3
  - `_parse_nf_resource_metrics()` downloads and parses `window.data.trace` from `report.html`,
    extracting per-task CPU/memory/duration data
  - `resource_metrics` (per-task data + summary) added to Nextflow status response
  - `nf_report_s3` and `nf_timeline_s3` added to status response
  - New endpoints:
    - `GET /api/workflows/runs/:id/resource-metrics` — per-task breakdown + vCPU-hours/mem-GB-hours
    - `GET /api/workflows/runs/:id/nf-report` — proxy stream `report.html` with `text/html`
    - `GET /api/workflows/runs/:id/nf-timeline` — proxy stream `timeline.html` with `text/html`
  - **ResourceMetricsPanel** added to `NextflowWorkflowViewer`:
    - Collapsible "Resource Usage" section, visible after run completion
    - Summary: wall time, vCPU-hours, mem-GB-hours, peak RSS, task counts
    - Per-task table: process, duration, CPU%, RSS, allocated CPUs, status
    - Buttons: "Execution Report" + "Timeline" → full-screen iframe modal
    - Full-screen iframe for `report.html` (Plotly charts) and `timeline.html` (D3 Gantt)

### Resource Data Schema (from report.html)

```typescript
interface TaskResource {
  task_id: number;
  process: string;           // e.g., "PREDICT_ADMET_PROPERTIES"
  name: string;              // e.g., "PREDICT_ADMET_PROPERTIES (run)"
  status: "COMPLETED" | "FAILED" | "CACHED" | "ABORTED";
  queue: string;             // e.g., "galaxy-cloud-queue"
  container: string;         // ECR image URI
  duration_ms: number;       // wall clock time
  realtime_ms: number;       // CPU-active time
  cpu_pct: string;           // e.g., "182.5" (percent of one core)
  mem_pct: string;           // e.g., "0.2"
  rss_bytes: number;         // resident set size
  peak_rss_bytes: number;
  alloc_cpus: number;        // CPUs requested (Nextflow process label)
  alloc_mem_bytes: number;   // memory requested
  read_bytes: number;
  write_bytes: number;
  cpu_model: string;         // EC2 instance CPU type
}

interface ResourceMetricsSummary {
  total_tasks: number;
  completed: number;
  failed: number;
  total_wall_ms: number;     // sum of all task durations
  vcpu_hours: number;        // Σ (cpu_fraction × duration_hours)
  mem_gb_hours: number;      // Σ (rss_GB × duration_hours)
  peak_rss_bytes: number;
}
```

### Cost Auditing Formula

```
vCPU-hours = Σ_tasks [ (%cpu / 100) × (duration_ms / 3,600,000) ]
mem-GB-hours = Σ_tasks [ (rss_bytes / 1,073,741,824) × (duration_ms / 3,600,000) ]
```

For AWS Batch pricing (us-east-1 Fargate pricing as reference):
- vCPU: $0.04048/hr
- Memory: $0.004445/GB-hr

This enables per-run cost estimates without relying on approximate job-level Batch billing.

---

## Part 4 — Marketing / Publication Key Points

### For Blog Posts

1. **"BioMate doesn't replace your tools — it amplifies them"**
   - Runs the same MultiQC, FastQC, ATACseqQC, ChIPQC, miQC that bioinformaticians trust
   - Adds active quality control: when hERG IC50 < 1 µM fires, BioMate doesn't just show a flag —
     it automatically reformulates compounds, re-runs ADMET, and verifies the fix
   - Shows Nextflow's own execution timeline and resource reports directly in the BioMate panel

2. **"Scientific QC gates with literature provenance"**
   - Every threshold has a PMID. hERG 1 µM from Sanguinetti & Tristani-Firouzi (Nature 2006).
     DILI from FDA DILIrank (Chen et al., Drug Metab Dispos 2016).
     CryoEM FSC from EMDB deposition policy.
   - Users can override thresholds with custom values — the citations remain visible for audit trails

3. **"Full compute cost transparency"**
   - After every AWS Batch run, BioMate parses Nextflow's execution report
   - Shows per-task CPU%, memory usage, and wall time in a resource panel
   - Calculates vCPU-hours and memory-GB-hours for cost attribution
   - Displays the Nextflow execution timeline (Gantt chart) and full resource report via iframe

4. **"127 bioinformatics QC tools, one platform"**
   - Survey of BioMate's 2,455 workflows: 127 produce structured QC output
   - Domains: genomics, transcriptomics, proteomics, single-cell, ChIP-seq, ATAC-seq, cryo-EM,
     drug discovery, methylation, ribo-seq, HDX-MS, mass spectrometry
   - All QC outputs (HTML, JSON, CSV, PDF) surfaced in BioMate's output panel with appropriate viewers

### For Scientific Publications

BioMate's QC architecture can be presented as:

> "BioMate integrates domain-specific quality control with an active feedback control loop.
> Scientific thresholds are grounded in published literature — e.g., hERG IC50 < 1 µM
> for cardiotoxicity risk (Sanguinetti & Tristani-Firouzi, Nature 2006; FDA E14 2005) —
> and can be overridden per experiment with full audit trail. When a quality gate fails,
> BioMate's auto-loop engine automatically remediates workflow parameters and re-executes
> the affected steps, completing QC-driven optimization without manual intervention.
> Resource utilization is recorded at task granularity from Nextflow's execution report,
> enabling accurate cost attribution and over-provisioning detection (vCPU utilization
> vs. allocated CPUs per task)."

---

## Files Changed (2026-04-28)

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | `_find_nf_infra_reports()`, `_parse_nf_resource_metrics()`, `resource_metrics`/`nf_report_s3`/`nf_timeline_s3` in status |
| `frontend/server/routes.ts` | `resource-metrics`, `nf-report`, `nf-timeline` endpoints; S3 streaming fix for `display` endpoint |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | `ResourceMetricsPanel` component; full-screen iframe modal for Nextflow reports |
| `frontend/client/src/components/chat-output-attachments.tsx` | "QC Reports" section; 600px iframe for MultiQC/FastQC HTML; `ChartBar` icon |

---

## Known Limitations

1. Resource metrics only available for **AWS Batch runs** (local runs don't generate `report.html` in S3)
2. `_parse_nf_resource_metrics` uses shell script stripping via regex — edge cases possible for complex scripts
3. `multiqc_report.html` is only generated if `multiqc` CLI is installed in the container (WGS workflow falls back to JSON-only)
4. Timeline.html uses D3.js from Nextflow CDN — requires internet access in iframe
5. Per-task vCPU-hours undercount if tasks have retry attempts (each attempt counted separately)
