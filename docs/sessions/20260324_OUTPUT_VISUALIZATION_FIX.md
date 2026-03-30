# Output Visualization Fix — 2026-03-24

## Branch: `bioconductor_skill`

## Goal
Fix JSON output files not appearing as interactive table viewers after ADMET workflow completion. E2E test `output-visualization.e2e.ts` was passing table_viewer_visible=false.

## Root Cause Chain

### 1. Stale Fallback Summary Blocks Real Scan
When the outputs API (`GET /api/invocations/:id/outputs`) was called while the Nextflow run was still in progress (`nfStatus=running`):
- `addRuntimeArtifactOutputs()` scanned an empty directory → 0 files registered
- `materializeRuntimeSummary()` created a fallback `nextflow_run_summary.txt` entry in storage
- Subsequent API calls found `outputs.length > 0` (the fallback) → skipped real file scan
- Real JSON files (produced after completion) were never registered

### 2. classifyFileType('json') = 'text'
Even if files were registered, JSON was classified as `'text'` not `'table'` → rendered in raw `<pre>` block instead of sortable table.

### 3. CsvTableViewer Not Imported
The `CsvTableViewer` component was written but never imported or used anywhere in the codebase.

### 4. WorkflowComplete Handler Failing for Nextflow Runs
The `workflow_completed` event handler tried to call Galaxy API when `galaxyWorkflowId=''` (Nextflow direct runs) → failed silently → 0 outputs registered at completion time.

## Fixes Applied

### routes.ts — Outputs Endpoint
```typescript
// Detect stale fallback
const onlyFallbackSummary =
  outputs.length > 0 &&
  outputs.every((o: any) => o?.metadata?.source === 'nextflow_runtime_summary');

if ((outputs.length === 0 || onlyFallbackSummary) && invocation.galaxyInvocationId) {
  // Build disk path from nextflowRunId as guaranteed fallback
  if (nfRunId) {
    const diskOutdir = path.join(nfWorkBase, nfRunId, 'output');
    artifacts.push(diskOutdir);
  }
  // Only create fallback summary when workflow has actually finished
  const isTerminal = nfIsTerminal || runIsComplete;
  if (artifacts.length > 0) {
    if (onlyFallbackSummary) {
      for (const o of outputs) { await storage.deleteOutput(o.id); }
      outputs = [];
    }
    await addRuntimeArtifactOutputs(invocation.id, ...);
  }
  if (outputs.length === 0 && isTerminal) {
    await materializeRuntimeSummary(...);
  }
}
```

### routes.ts — WorkflowComplete Handler
Added Nextflow-direct path when `galaxyWorkflowId` is empty:
```typescript
if ((finalStatus === 'completed' || finalStatus === 'ok') && !executionRun.execution.galaxyWorkflowId) {
  const nfRunId = executionRun.execution?.nextflowRunId;
  const diskOutdir = path.join(nfWorkBase, nfRunId, 'output');
  // scanFiles → register all real outputs → delete stale fallback first
}
```

### routes.ts — classifyFileType
```typescript
// Before: json was in textExts
// After:
const tableExts = ['tsv', 'csv', 'tabular', 'json', 'bed', 'gtf', 'gff', 'vcf'];
```

Also:
- `isVisualizable()` expanded to include json, csv, tsv, fasta, fa, fastq, fq
- `NF_INTERNAL_FILES` set: added `dag.dot`, `versions.yml`

### chat-output-attachments.tsx
```typescript
import { CsvTableViewer } from "./viewers/csv-table-viewer"

// In OutputRenderer:
case 'table':
  if (['json', 'csv', 'tsv', 'tabular'].includes(output.extension?.toLowerCase() || '')) {
    return (
      <div data-testid="csv-table-viewer">
        <CsvTableViewer output={output} className="w-full" />
      </div>
    )
  }
  return <TableOutput output={output} invocationId={invocationId} onDownload={onDownload} />
```

## Test Results

### Output Visualization E2E (`output-visualization.e2e.ts`)
- **Status**: 1/1 PASS
- 5 real outputs registered: `report.html`, `timeline.html`, `ADMET_pred_output.txt`, `ADMET_pred_results.json`, `toxicity_report.json`
- JSON files classified as `table` → `CsvTableViewer` renders sortable table
- Test log: `[VizTest] Output Results section auto-opened: true`

### Full E2E Suite (`full-workflow-e2e.e2e.ts`)
- **Status**: 8/8 PASS (10.4 minutes)
- All ADMET, Review UX, UC-1 through UC-7 tests green

## AWS vs Local Execution (Design Note)
- `NEXTFLOW_USE_AWS=true` or S3 outdir → AWS Batch
- Default (dev mode, env var absent) → local `/tmp/nextflow_runs/{run_id}/output/`
- The disk-path fallback in the outputs endpoint is defensive: multi-worker gunicorn means worker that calls outputs API may not be the worker that stored the `outdir` URL in `_runs`. Using the `nextflowRunId` + standard path convention bypasses this inter-worker state issue.
- Disk fallback is not "ad hoc" — it reflects the actual invariant: all local Nextflow runs write to `/tmp/nextflow_runs/{run_id}/output/` by construction.
