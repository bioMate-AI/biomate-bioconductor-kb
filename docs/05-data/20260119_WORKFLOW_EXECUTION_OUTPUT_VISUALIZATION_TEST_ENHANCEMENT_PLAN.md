# BioMate Workflow Execution & Output Visualization: Test and Enhancement Plan

## Overview

Systematic two-iteration approach to test, fix, and enhance BioMate's workflow execution and output visualization system.

---

## Iteration 1: Test & Fix Current Implementation

### 1.1 Code Review (Checklist)

**Files to Review:**

| File | Focus Areas |
|------|-------------|
| `frontend/server/workflow-sse.ts` | SSE connection handling, authentication, cleanup on disconnect |
| `frontend/server/galaxy-state-poller.ts` | Polling logic, state detection, memory leaks |
| `frontend/server/galaxy-api-proxy.ts` | Galaxy API integration, error handling |
| `frontend/server/routes.ts:2900-3200` | Output endpoints, file streaming |
| `frontend/client/src/components/chat-output-attachments.tsx` | Output rendering, type detection |

**Review Checklist:**
- [ ] SSE connection cleanup on disconnect
- [ ] Error propagation from Galaxy to frontend
- [ ] Memory leaks in polling sessions
- [ ] Concurrent invocation handling
- [ ] Large file streaming
- [ ] Authentication for SSE endpoints

### 1.2 Test Cases

#### A. Workflow Execution Tests
**New File:** `frontend/server/workflow-execution.test.ts`

| Test ID | Description | Priority |
|---------|-------------|----------|
| TC-WE-001 | Successful workflow invocation | Critical |
| TC-WE-002 | Invocation with missing inputs | High |
| TC-WE-003 | Workflow cancellation | High |
| TC-WE-004 | Concurrent invocations | Medium |
| TC-SSE-001 | SSE connection establishment | Critical |
| TC-SSE-002 | State change broadcasting | Critical |
| TC-SSE-003 | Client disconnect handling | High |
| TC-SSE-004 | Multiple clients same invocation | Medium |
| TC-ERR-001 | Galaxy API timeout | High |
| TC-ERR-002 | Network disconnection recovery | High |

#### B. Output Visualization Tests
**New File:** `frontend/server/output-visualization.test.ts`

| Test ID | Description | Priority |
|---------|-------------|----------|
| TC-FT-001 | Image detection (PNG, JPG, SVG, PDF) | Critical |
| TC-FT-002 | Table detection (CSV, TSV, BED, VCF) | Critical |
| TC-FT-003 | HTML interactive detection | High |
| TC-FT-004 | Unknown format fallback | Medium |
| TC-PV-001 | Table preview (first N lines) | High |
| TC-PV-002 | Large file preview limits | Medium |
| TC-DL-001 | Single file download | Critical |
| TC-DL-002 | Bulk download (ZIP) | High |
| TC-DL-003 | Large file streaming | High |

#### C. Component Tests
**New File:** `frontend/client/src/components/chat-output-attachments.test.tsx`

| Test ID | Description |
|---------|-------------|
| TC-UI-001 | Loading state display |
| TC-UI-002 | Empty outputs message |
| TC-UI-003 | Image output rendering |
| TC-UI-004 | Table preview toggle |
| TC-UI-005 | Download button |
| TC-UI-006 | Output grouping by type |

#### D. Edge Cases
| Test ID | Description |
|---------|-------------|
| TC-LF-001 | File > 100MB streaming |
| TC-UF-001 | Binary file handling (BAM) |
| TC-UF-002 | Compressed file detection (.gz) |
| TC-NE-001 | Galaxy API timeout during preview |
| TC-NE-002 | SSE reconnection after network failure |

### 1.3 Evaluation Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Execution Success Rate | ≥95% | Successful / Total invocations |
| SSE Connection Stability | ≥99% | Uptime during execution |
| Output Display Accuracy | 100% (supported types) | Visual + automated testing |
| SSE Latency | <500ms | Galaxy change → frontend update |
| Preview Response Time | <2s (files <10MB) | API timing |
| Download Throughput | ≥10 MB/s | Large file timing |
| Error Recovery Rate | ≥90% | Recovered / Recoverable errors |

### 1.4 Fix Protocol

| Severity | Timeline | Requires |
|----------|----------|----------|
| Critical (blocks execution) | Same iteration | Unit + integration test |
| High (degraded UX) | Before iteration end | Regression test |
| Medium (minor issue) | Document for Iter 2 | Issue tracking |

---

## Iteration 2: Enhancement

### 2.1 New Bioinformatics Viewers

| Viewer | Formats | Features |
|--------|---------|----------|
| **BAM/SAM Viewer** | .bam, .sam | Read alignment, coverage display |
| **VCF Viewer** | .vcf, .vcf.gz | Variant table, filtering, quality scores |
| **Sequence Viewer** | .fasta, .fastq | Sequence display, QC stats, GC content |
| **Annotation Viewer** | .bed, .gff, .gtf | Feature table, genomic coordinates |
| **Single-Cell Viewer** | .h5ad | UMAP/t-SNE, gene expression, clustering |

### 2.2 Interactive Tool Integration

Connect output viewing to Galaxy Interactive Tools:
- CellxGene for .h5ad files
- Pavian for Kraken reports
- Jupyter/RStudio for custom analysis

**New Component:** `frontend/client/src/components/interactive-tool-launcher.tsx`
- Suggest appropriate tools based on output type
- Launch interactive session
- Embed in BioMate UI

### 2.3 Enhanced Features

| Feature | Description |
|---------|-------------|
| Output Comparison | Side-by-side diff of outputs from different runs |
| Advanced Table Viewer | Sorting, filtering, statistics |
| Output Search | Full-text search in text outputs |
| Output Annotations | User notes and tags |

### 2.4 Enhancement Test Cases

| Test ID | Description |
|---------|-------------|
| TC-BAM-001 | Load and display BAM file |
| TC-VCF-001 | Parse VCF and display variants |
| TC-SEQ-001 | Display FASTA with statistics |
| TC-IT-001 | Launch CellxGene from h5ad output |
| TC-IT-002 | Embed interactive tool session |

### 2.5 Enhancement Metrics

| Metric | Target |
|--------|--------|
| Viewer Load Time | <3s for files <50MB |
| Interactive Tool Startup | <30s |
| Format Coverage | 15+ bioinformatics formats |
| User Satisfaction | ≥4.0/5.0 |

---

## Files to Modify/Create

### Iteration 1 (Testing)
```
frontend/server/workflow-execution.test.ts        # NEW - execution tests
frontend/server/output-visualization.test.ts      # NEW - output tests
frontend/client/src/components/chat-output-attachments.test.tsx  # NEW
frontend/server/workflow-sse.ts                   # FIX - based on review
frontend/server/galaxy-state-poller.ts            # FIX - based on review
```

### Iteration 2 (Enhancement)
```
frontend/client/src/components/viewers/           # NEW directory
  bam-viewer.tsx
  vcf-viewer.tsx
  sequence-viewer.tsx
  annotation-viewer.tsx
  single-cell-viewer.tsx
frontend/client/src/components/interactive-tool-launcher.tsx  # NEW
frontend/server/routes.ts                         # MODIFY - new endpoints
frontend/client/src/components/chat-output-attachments.tsx  # MODIFY
```

---

## Verification Plan

### Iteration 1 Verification
1. Run full test suite: `npm test` in frontend
2. Check coverage report: `npm run test:coverage`
3. Manual testing of each viewer type with sample files
4. Stress test: 10 concurrent workflow executions
5. SSE stability test: 1-hour continuous monitoring

### Iteration 2 Verification
1. Load test each new viewer with large files
2. Interactive tool launch from UI
3. Performance benchmarks for each metric
4. User acceptance testing with bioinformatics team

---

## Acceptance Criteria

### Iteration 1 Complete When:
- [ ] All critical/high priority tests passing (≥95%)
- [ ] Execution success rate meets target (≥95%)
- [ ] SSE stability meets target (≥99%)
- [ ] No critical bugs remaining
- [ ] Code review issues addressed

### Iteration 2 Complete When:
- [ ] At least 3 bioinformatics viewers implemented
- [ ] Interactive tool launcher functional
- [ ] All enhancement tests passing
- [ ] Performance metrics met
- [ ] Documentation updated
