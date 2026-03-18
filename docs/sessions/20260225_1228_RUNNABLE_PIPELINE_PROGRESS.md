# Runnable Pipeline Progress Update

**Timestamp:** 2026-02-25 12:28 (local)
**Goal:** Move BioMate from demo-like behavior to real end-to-end runnable workflows.

## What Was Implemented

### 1) Runtime environment preflight in Nextflow executor
File: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

- Added documented-image-first runtime selection:
  - Reads local docs to discover expected Docker images.
  - Checks local image existence before use.
  - Validates required Python modules in candidate containers.
- Added fallback path:
  - If suitable Docker image is not found, check host Python modules.
  - Attempt `pip install` for missing modules automatically.
  - Fail fast with explicit missing module list if unresolved.
- Added runtime metadata to run records and API response:
  - `runtime_mode`, `runtime_image`, module requirements, missing modules.

### 2) Cross-architecture support (ARM now, x86 later)
File: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

- Added host/image architecture detection.
- Default behavior now avoids cross-arch image selection.
- Added env control:
  - `NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER=true|false`
  - `NEXTFLOW_RUNTIME_IMAGE_PRIORITY=<comma-separated image refs>`
- Added runtime payload fields:
  - `host_arch`, `image_arch`, `cross_arch_allowed`

### 3) Runnable workflow selection in AI search/generation
Files:
- `backend/lib/galaxy/ai/ai_assistant.py`
- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

- Refined executable filtering:
  - Keep excluding known non-entry nf-core library subworkflows.
  - Stop blanket rejection of all `subworkflows` paths.
- Added runnable preference from historical test results:
  - Uses `backend/biomni_workflows/nextflow_nfcore/test_results/passed_workflows.txt`.
  - Prefers workflows that are both executable and present in passed list.

### 4) E2E prompt moved to safer runnable family
File: `frontend/e2e/complete-workflow.e2e.ts`

- Changed workflow request from RNA-seq QC to molecular biology restriction-site workflow prompt, aligned with known passed workflows.

## Current Status

- Code changes are in place.
- Lint check on edited files returned no errors.
- Next step is to run strict complete E2E and confirm:
  - workflow artifact rendered,
  - execution reaches backend `completed`,
  - output indicators are present.

## Immediate Next Actions

1. Rebuild/restart services with updated backend/frontend.
2. Run strict E2E test: `frontend/e2e/complete-workflow.e2e.ts`.
3. If failure remains, capture exact terminal backend error and tighten runnable allowlist for CI.
