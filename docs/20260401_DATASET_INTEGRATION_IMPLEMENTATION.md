# Dataset Integration Implementation

**Date:** 2026-04-01  
**Branch:** integration/next-phase  
**Tests:** 38/38 pass (new), 120/122 pass existing (2 pre-existing RAG index failures unrelated)

Implements two dataset-aware improvements to the workflow generation pipeline.

> **Correction (2026-04-01):** Initial wiring incorrectly connected `request.available_datasets`
> (BioMNI public reference catalog datasets used for RAG knowledge retrieval) as `uploaded_datasets`.
> These are two distinct data categories. `available_datasets` are accessed for domain knowledge
> context — they are NOT the user's actual input files. The incorrect wiring has been reverted.
> Both concerns remain implemented in backend library code; they activate when actual user session
> uploads are threaded through the API (future work — see **Pending Wiring** section below).

---

## What Was Fixed

### Concern A — WorkflowDatasetSelector (was a stub)

`backend/lib/galaxy/ai/workflow_dataset_selector.py`

The class previously returned `{}` unconditionally. Now implements format-based matching of available user datasets to workflow input steps.

**Matching strategy:**

1. Detect the format group of each available dataset from its `type` / `fileType` / `extension` field (e.g. `fastq.gz` → `fastq`, `fa` → `fasta`).
2. For each workflow step, infer required input format(s) from the tool ID or name using a lookup table of 30+ common Galaxy tools (e.g. `fastqc` → `['fastq']`, `gatk` → `['bam', 'fasta', 'vcf']`). Falls back to keyword scan of the step description.
3. Match step to the best available dataset of the required format. Tie-break by name overlap with the step description (e.g. a step described as "reference genome alignment" prefers a dataset named `reference_genome.fa`).
4. Each dataset is assigned at most once — no double-use across steps.
5. Returns two lists: `workflow_steps` (assigned) and `unassigned_inputs` (steps with no matching dataset), surfaced to the prereq checklist for user confirmation before execution.

**Return shape:**
```python
{
    'workflow_steps': [
        {'step': 1, 'tool_id': 'fastqc',
         'datasets': [{'name': 'sample.fastq', 'path': 'ds1', 'dataset_id': 'ds1', 'format': 'fastq'}]},
        ...
    ],
    'unassigned_inputs': [
        {'step': 2, 'tool_id': 'deseq2', 'expected_formats': ['tabular']}
    ],
    'total_steps': 3,
    'assigned_count': 2,
}
```

Unassigned steps are shown in the prereq checklist `input_data` item with `status: "missing"` so the user can see what needs to be provided before running.

**Format groups supported:**

| Group | Detected from |
|---|---|
| `fastq` | fastq, fq, fastq.gz, fq.gz, reads, r1, r2, paired, sequences |
| `bam` | bam, sam, cram, alignment, aligned, mapped, sorted_bam |
| `vcf` | vcf, bcf, variants, snp, snv, indel, calls, genotype |
| `fasta` | fasta, fa, fna, reference, genome, ref, assembly |
| `bed` | bed, regions, intervals, peaks, sites, annotation |
| `gtf` | gtf, gff, gff3, annotation, genes, transcripts |
| `tabular` | csv, tsv, tabular, txt, counts, expression, matrix |
| `h5ad` | h5ad, h5, anndata, single_cell |

---

### Concern B — Data type context in specialist prompt

`backend/lib/galaxy/ai/agents/domain_specialist.py`

`_build_specialist_prompt()` now accepts the available datasets and injects a context block when datasets are present. This shapes the specialist's workflow recommendation to start from the user's existing data, avoiding redundant upstream steps.

**Injected prompt section (example):**
```
Available Input Data:
The user already has datasets in these formats: fastq, bam
Shape the workflow to START from these input types.
Do not include upstream steps that would produce data the user already has.
```

No additional LLM calls — the context is a string prepended to the existing prompt.

---

## Data Flow Changes

### Before

```
Frontend → {id, name, type} dicts
API endpoint: strips to [id, id, id]  ← information lost here
generate_workflow_unified(uploaded_datasets: List[str])
WorkflowDatasetSelector.select_datasets_for_workflow(uploaded_datasets=["id1"])
→ returns {}  ← stub, nothing assigned
```

### After (corrected)

```
Frontend → {id, name, type} BioMNI catalog dicts   ← used for RAG knowledge only
API endpoint: available_datasets stays in request for other uses (e.g. pilot count)
generate_workflow_unified(uploaded_datasets=None)   ← dormant until session_datasets wired
  ├── WorkflowDatasetSelector: skipped (uploaded_datasets=None)
  └── AgentOrchestrator.generate_workflow(available_datasets=None)
        └── DomainSpecialistPool: no format context injected
```

Future wiring (Pending Wiring section below):

```
req.session.uploadedDatasets → session_datasets field → Python AIRequestModel
generate_workflow_unified(uploaded_datasets=[{id,name,type}])
  ├── WorkflowDatasetSelector.select_datasets_for_workflow(...)  ← activates
  └── DomainSpecialistPool._build_specialist_prompt(...)         ← activates
```

---

## Files Changed

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/workflow_dataset_selector.py` | Full implementation replacing stub |
| `backend/lib/galaxy/ai/agents/domain_specialist.py` | `available_datasets` param threaded through `consult_specialists` → `_consult_parallel/_consult_sequential` → `_consult_single` → `_build_specialist_prompt` |
| `backend/lib/galaxy/ai/agents/agent_orchestrator.py` | `available_datasets: Optional[List[Dict]]` added to `generate_workflow()`, passed to `consult_specialists()` |
| `backend/lib/galaxy/ai/ai_assistant.py` | `uploaded_datasets` type changed from `Optional[List[str]]` to `Optional[List[Dict[str, Any]]]` in `generate_workflow_unified`, `generate_workflow_multi_agent`, `run_via_pipeline`, `_build_workflow_ga_from_multi_agent`; selector call updated to pass `available_datasets=uploaded_datasets` |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Removed ID-only stripping at both `/generate_workflow` endpoints — full dataset objects now flow through |

---

## Architecture Boundary — Selector Result vs Galaxy .ga JSON

**Critical distinction:** `available_datasets` from the frontend contains BioMNI catalog IDs, not valid Galaxy LDDA history IDs. These cannot be embedded directly into Galaxy `.ga` workflow JSON (which uses `src: 'ldda'` references to real history dataset objects).

The selector result is therefore **surfaced in the response for display only**, not wired into the Galaxy workflow JSON:

```python
# In generate_workflow_unified() — high_confidence Galaxy .ga path:
dataset_match_result = self.dataset_selector.select_datasets_for_workflow(
    workflow={'steps': workflow_steps},
    user_intent=user_intent,
    available_datasets=uploaded_datasets,
) if uploaded_datasets else {}

# Build Galaxy .ga WITHOUT embedding dataset IDs (actual wiring happens
# at execution time via Galaxy UI using real history dataset IDs)
workflow_ga = self._build_workflow_ga_from_template(workflow_json, {})

# Return match result for frontend prereq checklist display
return { ..., 'dataset_match_result': dataset_match_result, ... }
```

The `unassigned_inputs` field tells the frontend which step formats the user still needs to provide. The `workflow_steps` field tells it which formats were matched (for informational display). Actual Galaxy dataset wiring happens at execution time in the Galaxy UI.

**Nextflow workflows** (primary path): Unaffected — return before the selector is called. Nextflow handles inputs via `params.*` not Galaxy dataset connections.

## What Still Requires User Confirmation

The selector produces **candidate format matches** for prereq checklist display. The user sees:
- Matched steps → "Input data: X datasets matched by format"
- Unmatched steps → "Input data: missing — expected formats: fastq, fasta"

Actual dataset selection (picking specific files from Galaxy history) happens at execution time. No frontend changes were needed — the existing prereq checklist UI handles both states.

---

## Test Coverage

**New tests** (run inline, 38/38 pass):

| Group | Cases | What's tested |
|---|---|---|
| `_dataset_format_group` | 10 | All format groups + edge cases (empty, unknown, gz extension stripping) |
| `_step_expected_formats` | 8 | Tool-name lookup, fallback keyword scan, no-match case |
| `select_datasets_for_workflow` | 14 | Happy path, empty datasets, no format match, single-use constraint, name tie-breaking, legacy param handling |
| `_build_specialist_prompt` | 6 | Dataset context present/absent, format dedup, empty list |

**Existing tests** (120/122 pass, 2 pre-existing failures unrelated):
- `test_unified_workflow_generation.py`: 2/2 pass
- `biomni_workflows/pipeline_composition/tests/`: 114/114 pass
- 2 failures in `test_enhanced_workflow_rag.py` are pre-existing (`total_datasets: 0` in BioMNI RAG index — not related to this change)

---

## Wiring — Session Datasets (implemented 2026-04-01)

Both concerns are now live. The full wiring chain:

```
req.session.uploadedDatasets            (routes.ts — tracked at upload time)
  → enrichedContext.sessionDatasets     (routes.ts /api/chat and /api/chat/stream)
  → context.sessionDatasets             (galaxy-assistant.ts ChatContext)
  → generateWorkflow(sessionDatasets)   (galaxy-assistant.ts)
  → request.session_datasets            (galaxy-api-proxy.ts backendRequest)
  → AIRequestModel.session_datasets     (api/ai_assistant.py)
  → uploaded_datasets = request.session_datasets or None
  → WorkflowDatasetSelector             (Concern A — format matching)
  → DomainSpecialistPool                (Concern B — prompt format context)
```

**Key semantic distinction preserved:**
- `available_datasets` = BioMNI public reference catalog (RAG context only)
- `session_datasets` = user's actual uploaded input files (workflow input wiring)

**Files changed for wiring:**

| File | Change |
|---|---|
| `frontend/shared/galaxy-types.ts` | Added `session_datasets?` to `WorkflowGenerationRequest` |
| `frontend/server/galaxy-assistant.ts` | `ChatContext` + `generateWorkflow()` + both call sites |
| `frontend/server/galaxy-api-proxy.ts` | Spread `session_datasets` into `backendRequest` |
| `frontend/server/routes.ts` | Both `/api/chat` and `/api/chat/stream` inject `sessionDatasets` |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | `AIRequestModel.session_datasets` + both endpoints |
