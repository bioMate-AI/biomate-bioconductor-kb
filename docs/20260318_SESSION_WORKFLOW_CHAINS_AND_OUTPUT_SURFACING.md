# Session Summary: Workflow Chains Wiring + Output Surfacing Fixes

**Date**: 2026-03-18  
**Branch**: `feature/nfcore-reindex`  
**Status**: All work committed, tests running

---

## What Was Built This Session

### 1. Workflow Chains — Wired into Live Query Path

**Problem**: The `workflow_chains` table had 6 curated multi-step pipelines and the `search_chains()` API existed, but `generate_workflow_unified()` went straight to FTS individual search on every query. The chains table was never consulted.

**Fix**: Added Step 0 to `generate_workflow_unified()` in `backend/lib/galaxy/ai/ai_assistant.py`:

```
User query
  │
  ▼  Step 0 (NEW)
  search_chains(query, limit=3)        ← keyword + tag scoring, threshold 0.15
  │  match found?
  ├─ YES → return chain plan (workflow_type='chain')
  │         No LLM step assembly needed
  └─ NO  → Step 1: FTS iterative search → Step 2-N: LLM assembles
```

**Smoke test results** (all correct):
- "rare disease workup on WGS + RNA-seq" → `rare_disease_multimodal_workup` (5 steps)
- "bulk RNA-seq differential expression" → `bulk_rnaseq_de_analysis` (3 steps)
- "single cell analysis from Cell Ranger" → `single_cell_multimodal_analysis` (5 steps)
- "run ADMET screening then docking" → `drug_discovery_screening` (3 steps)
- "random protein structure query" → NO MATCH → falls through to FTS ✓

**New frontend component**: `workflow-chain-plan.tsx` — renders the ordered step pipeline with `from_output → to_input` connection arrows, required inputs, expected outputs, collapsible.

**New API endpoints**:
- `GET /api/workflows/chains` — list all curated chains (filterable by domain)
- `POST /api/workflows/chains/record-run` — update usage_count + rolling success_rate telemetry

**Files changed**:
- `backend/lib/galaxy/ai/ai_assistant.py` — Step 0 chain lookup
- `frontend/client/src/components/workflow-chain-plan.tsx` — new pipeline plan renderer
- `frontend/client/src/components/chat-message.tsx` — branch on `workflow_type==='chain'`
- `frontend/server/galaxy-assistant.ts` — `workflowGenerated` flag accepts chain type
- `frontend/server/routes.ts` — chain catalog proxy routes
- `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` — new catalog endpoints

**The 6 curated chains** (all seeded, all matchable):

| Chain name | Steps | Domain |
|---|---|---|
| `rare_disease_multimodal_workup` | sarek → VEP → rnaseq → DROP → case_report (5) | rare_disease |
| `bulk_rnaseq_de_analysis` | rnaseq → differentialabundance → GSEA (3) | transcriptomics |
| `single_cell_multimodal_analysis` | QC → Harmony → annotation → trajectory → DA (5) | single_cell |
| `cutandtag_chromatin_analysis` | alignment+spike-in → SEACR → diff_binding (3) | epigenomics |
| `alternative_polyadenylation_analysis` | rnaseq → polyaminer_bulk (2) | transcriptomics |
| `drug_discovery_screening` | ADMET → docking → binding_affinity (3) | drug_discovery |

---

### 2. Fix 1 — Real Nextflow Process Status in PhaseCards (replaces simulation)

**Problem**: The `NextflowWorkflowViewer` showed step progress by dividing the global `progress%` linearly across all phases — a comment in the code said *"simple simulation for now"*. Actual Nextflow process statuses from the trace file were parsed into `processes[]` but the frontend ignored them.

**Fix**:
- `_parse_trace_progress()` in `nextflow_executor.py` now reads the trace header to locate columns by name (handles Nextflow 22/23/24 trace format variations), extracts `name`, `status`, `work_dir` per task
- `nextflow-workflow-viewer.tsx`: when `nextflowStatus.processes` is populated, use those directly as the phase list — one card per real Nextflow process
- Fallback to linear simulation only when no trace data is available yet (pre-run or very early in execution)

**Before**: 4 static cards (Setup/Process/Analysis/Report) with progress% split uniformly  
**After**: N cards, one per actual Nextflow task (e.g., FASTQC, TRIMGALORE, STAR_ALIGN, MULTIQC), each showing real COMPLETED/RUNNING/FAILED status

---

### 3. Fix 2 — HTML Reports and All Outdir Files as Inline Output Cards

**Problem**: `addRuntimeArtifactOutputs()` was passed `outdir` (a directory path) and called `fs.stat(path).isFile()` on it — always false. So no files were ever registered as `Output` records from Nextflow runs. The output panel showed "No outputs generated yet" even after successful runs with a full `results/` directory.

**The MultiQC gap specifically**: Every nf-core pipeline outputs `results/multiqc/multiqc_report.html`. This was in the `outdir` but invisible to users. `classifyFileType('html')` returns `'interactive'` and `InteractiveOutput` already renders iframes — so the only missing piece was registration.

**Fix** in `frontend/server/routes.ts`:
- `addRuntimeArtifactOutputs()` now recursively walks any directory path (depth 4)
- Skips Nextflow control files: `.command.*`, `.exitcode`, `.started`, `work/`, `.nextflow/`
- Registers every real output file with `localPath` (or `s3Uri` for cloud runs)
- HTML files → `fileType: 'interactive'` → rendered in sandboxed iframe automatically
- Images → `fileType: 'image'` → rendered inline
- TSV/CSV → `fileType: 'table'` → table preview
- Added `s3Uri` field to `OutputDataset` metadata schema

---

### 4. Fix 3 — Per-Step Intermediate Files in PhaseCards

**Problem**: `PhaseCard` showed only status badge, step name, and Start/Pause button. No way to see what files a step produced.

**Fix**:
- `_parse_trace_progress()` calls `_scan_task_work_dir()` for each COMPLETED task
- Lists files in the task's `work_dir` (skipping `.command.*` internals)
- Returns `task_files: string[]` per process in the status response
- `PhaseCard` rewritten to show collapsible "N output files" with type-specific icons:
  - 🔵 image for PNG/JPG/SVG/PDF
  - 🟢 table icon for CSV/TSV/BED/VCF
  - 🟣 code icon for HTML reports
  - grey file/text for logs and other

---

## Architecture Summary

```
User query: "rare disease workup on WGS + RNA-seq"
    │
    ▼  Step 0: Chain lookup (NEW)
    search_chains() → rare_disease_multimodal_workup (score 0.42)
    │
    ▼  Returns workflow_type='chain'
    WorkflowChainPlan renders:
      [1] nf-core/sarek    → vcf →
      [2] vep_annotation   → vcf, bam →
      [3] nf-core/rnaseq   → bam →
      [4] nf-core/drop     → report →
      [5] case_report_aggregation
    
    User runs it → chain executor fires each step in sequence
    
    During execution:
      PhaseCard[FASTQC]:    ✅ COMPLETED  (3 files: multiqc_data.json, fastqc.html...)
      PhaseCard[TRIMGALORE]: ✅ COMPLETED  (2 files: sample.fq.gz, trim_report.txt)
      PhaseCard[STAR_ALIGN]: 🔄 RUNNING
      PhaseCard[MULTIQC]:    ⏳ pending
    
    On completion:
      Output panel shows:
        📊 multiqc_report.html  → renders inline in iframe (MultiQC QC dashboard)
        📊 salmon.merged.gene_counts.tsv → table preview
        🖼  sample_fastqc.png → image inline
        📄 nextflow_run_summary.txt → text viewer
```

---

## Files Changed This Session

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/ai_assistant.py` | Step 0 chain lookup in generate_workflow_unified |
| `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` | Chain catalog GET/POST endpoints + type compatibility |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Trace parser: header-based columns, work_dir, task_files |
| `backend/scripts/index_all_workflows.py` | Dynamic nf-core discovery + output_types backfill |
| `frontend/client/src/components/workflow-chain-plan.tsx` | NEW — pipeline plan renderer |
| `frontend/client/src/components/phase-card.tsx` | Rewritten — real status, task files, run button |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Use trace processes instead of simulation |
| `frontend/client/src/components/chat-message.tsx` | Chain workflow type branching |
| `frontend/server/galaxy-assistant.ts` | Chain type accepted as workflowGenerated |
| `frontend/server/routes.ts` | Recursive outdir scan, chain proxy routes |
| `frontend/shared/schema.ts` | s3Uri in OutputDataset metadata |
| `docs/WORKFLOW_CHAINS_DESIGN.md` | Design doc (pre-existing, written by colleague) |

---

## Known Gaps (Not in This Session)

1. **Chain execution UX**: When a chain response is returned, clicking "Run Pipeline" should wire into the chain executor (`POST /api/workflows/chain`). The UI shows the plan but has no run button wired to the chain executor yet.

2. **S3 display endpoint**: The `display` endpoint redirects S3 files to the backend presigned URL endpoint, but the backend `/api/nextflow/outputs/download` validates that `run_id` matches the file — the `run_id=direct` workaround used in the redirect may reject if strict validation is on.

3. **Visualization chain terminals**: The 6 chains all end at computation steps. Visualization/reporting steps (volcano plots, UMAP, enrichment) are not yet chained as terminals.

4. **Bioconductor tool input_types**: All Bioconductor viz tools have `input_types: ["count_data"]` — not wired to actual computation output types.
