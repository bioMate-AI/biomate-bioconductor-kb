# LLM Replacement — Test Plan
**Date:** 2026-03-30
**Branch:** `integration/next-phase`
**Companion:** `20260330_LLM_REPLACEMENT_PLAN.md`

---

## Scope

This test plan covers the first implementation wave:

| Change | Where |
|--------|-------|
| Remove `detectBulletPipeline()` regex | `galaxy-assistant.ts` |
| Expand `analyzeIntent()` response schema with `preferred_domains`, `key_terms`, `needs_thinking`, `chain_hint` | `galaxy-assistant.ts` |
| Update `IntentDecomposition` / `parseIntentResult()` to carry new fields | `galaxy-assistant.ts` |
| Pass `preferred_domains` + `key_terms` through to Galaxy backend search | `routes.ts` + `ai_assistant.py` / `unified_workflow_search.py` |
| Replace `_infer_domain_preferences()` when LLM-derived values are present | `unified_workflow_search.py` |
| Wire `needs_thinking` per-message instead of global config | `galaxy-assistant.ts` |

---

## 1. Unit Tests — `analyzeIntent()` Parser (`frontend/server/`)

**File to create:** `frontend/server/test-analyze-intent-uqu.ts`

These tests call `parseIntentResult()` directly with synthetic LLM response objects — no live API calls.

### 1.1 Sequential Pipeline — Numbered List
**Input LLM response:**
```json
{
  "is_sequential": true,
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["fastqc", "trim galore", "star", "deseq2"],
  "needs_thinking": false,
  "chain_hint": "bulk_rnaseq_de_analysis",
  "intents": [
    { "id": "step_1", "type": "workflow_generation", "subQuery": "FastQC on raw reads",
      "keywords": ["fastqc"], "dependsOn": [], "output_description": "QC reports" },
    { "id": "step_2", "type": "workflow_generation", "subQuery": "Adapter trimming with Trim Galore",
      "keywords": ["trim galore"], "dependsOn": ["step_1"],
      "input_from_description": "raw FASTQ from step 1", "output_description": "trimmed reads" },
    { "id": "step_3", "type": "workflow_generation", "subQuery": "Align with STAR to hg38",
      "keywords": ["star", "hg38"], "dependsOn": ["step_2"],
      "input_from_description": "trimmed reads from step 2" }
  ]
}
```
**Assertions:**
- `decomposition.isSequential === true`
- `decomposition.intents.length === 3`
- `decomposition.preferredDomains` includes `"transcriptomics"`
- `decomposition.keyTerms` includes `"fastqc"` and `"star"`
- `decomposition.needsThinking === false`
- `decomposition.chainHint === "bulk_rnaseq_de_analysis"`
- `decomposition.intents[1].dependsOn` equals `["step_1"]`
- `decomposition.intents[2].inputFromDescription` contains `"step 2"`

### 1.2 Sequential Pipeline — Bulleted List
**Input:** Same structure as 1.1 but `is_sequential: true`, items are bullet-style steps.

**Assertions:** Same as 1.1 — the parser must work identically regardless of how the user phrased it.

### 1.3 Single Intent — Domain Extraction
**Input LLM response:**
```json
{
  "type": "workflow_generation",
  "keywords": ["molecular docking", "autodock vina"],
  "preferred_domains": ["drug_discovery", "structural_biology"],
  "key_terms": ["autodock", "vina", "docking", "ligand"],
  "needs_thinking": false,
  "chain_hint": null,
  "inlineParameters": {},
  "facts": [],
  "workflowAmbiguity": null
}
```
**Assertions:**
- `decomposition.isSequential !== true`
- `decomposition.preferredDomains` equals `["drug_discovery", "structural_biology"]`
- `decomposition.keyTerms` includes `"autodock"` and `"docking"`
- `decomposition.chainHint === null`

### 1.4 Complex Query — `needs_thinking: true`
**Input:** Research question + comparison.
**Input LLM response:**
```json
{
  "type": "result_comparison",
  "preferred_domains": ["transcriptomics"],
  "key_terms": ["DESeq2", "edgeR", "differential expression"],
  "needs_thinking": true,
  "chain_hint": null,
  ...
}
```
**Assertions:**
- `decomposition.needsThinking === true`
- `decomposition.primaryIntent.type === "result_comparison"`

### 1.5 Fallback Safety — Missing New Fields
**Input:** Legacy LLM response without new fields (simulates model output before schema update).
```json
{
  "type": "workflow_generation",
  "keywords": ["rnaseq"]
}
```
**Assertions:**
- Parser does NOT throw
- `decomposition.preferredDomains` defaults to `[]`
- `decomposition.keyTerms` defaults to `[]`
- `decomposition.needsThinking` defaults to `false`
- `decomposition.chainHint` defaults to `null`

---

## 2. Integration Tests — Live `analyzeIntent()` API

**File:** `frontend/server/test-e2e-flexible-intents.ts` — add new test group `E2E-UQU`.

These tests call `assistant.processMessage()` against the live server and check that the new UQU fields are present and correct in logged output. Since the response object doesn't surface these fields to the client directly, we verify via side-effects (domain-appropriate workflow search results).

### 2.1 Bullet List → Sequential Pipeline (no regex path)
**Input:**
```
1. FastQC quality control on raw reads
2. Adapter trimming with Trim Galore
3. Alignment to hg38 with STAR
4. Differential expression with DESeq2
```
**Assertions:**
- Response contains `workflow_type: 'pipeline'`
- `pipeline_steps.length === 4`
- Steps are in numbered order
- **No log line** `"Bullet pipeline detected"` (was from the old regex path — deleted)
- Log line from `analyzeIntent` shows `is_sequential: true`

### 2.2 Bulleted List (hyphens)
**Input:**
```
- Trim reads with fastp
- Align to mm10 with HISAT2
- Count reads with featureCounts
```
**Assertions:**
- `pipeline_steps.length === 3`
- Each step subQuery contains the tool name

### 2.3 Mixed Intro + Numbered List
**Input:**
```
Please run the following RNA-seq pipeline:
1. QC with FastQC and MultiQC
2. Trimming with Trim Galore
3. Alignment with STAR
```
**Assertions:**
- `pipeline_steps.length === 3` (intro line not treated as a step)
- Steps extracted correctly

### 2.4 Step-Labelled Format
**Input:**
```
Step 1: Run quality control
Step 2: Trim adapters
Step 3: Align reads to reference genome
```
**Assertions:**
- `pipeline_steps.length === 3`

### 2.5 Domain Preference — Drug Discovery Query
**Input:** `"Run AutoDock Vina docking of my ligand library against EGFR"`
**Assertions:**
- First workflow result is from `drug_discovery` or `structural_biology` domain
- NOT a transcriptomics or metagenomics workflow

### 2.6 Domain Preference — Metagenomics Query
**Input:** `"Analyse 16S amplicon sequencing data from gut microbiome samples"`
**Assertions:**
- First result domain is `metagenomics` or `microbiology`

### 2.7 `needs_thinking` — Simple Request
**Input:** `"Run nf-core/rnaseq on my FASTQ files"`
**Assertion:** Response generated without extended thinking latency (< 5s round-trip).

### 2.8 `needs_thinking` — Complex Design
**Input:** `"Design an optimal pipeline for profiling chromatin accessibility in FFPE tissue samples. Compare ATAC-seq vs CUT&RUN approaches."`
**Assertion:** Response addresses both approaches; `thinking_content` present (if thinking enabled in config).

---

## 3. Backend Unit Tests — Domain Preference Pass-Through

**File:** `backend/tests/test_unified_workflow_search.py` (new or existing)

### 3.1 LLM Domains Override Rule-Based Inference
```python
results = search_workflows(
    query="analyze my samples",  # vague — rule-based infers nothing
    preferred_domains=["drug_discovery"],  # explicitly from LLM
    key_terms=["smiles", "admet"],
)
assert results[0]["domain"] in ("drug_discovery", "structural_biology")
```

### 3.2 Rule-Based Fallback When LLM Domains Absent
```python
results = search_workflows(
    query="analyze metagenomics data from soil samples",
    preferred_domains=None,  # not passed → fallback to _infer_domain_preferences
)
assert results[0]["domain"] in ("metagenomics", "microbiology")
```

### 3.3 Key Terms Boost FTS Recall
```python
results_without = search_workflows(query="spatial omics")
results_with = search_workflows(query="spatial omics", key_terms=["visium", "spatial transcriptomics"])
# The key_terms version should rank Visium workflows higher
assert results_with[0]["score"] >= results_without[0]["score"]
```

---

## 4. E2E Regression — Existing Sequential Pipeline Tests

The germline-complete and full-workflow E2E suites must continue to pass after `detectBulletPipeline()` is removed.

**Run after implementation:**
```bash
cd frontend && npx playwright test e2e/germline-complete-e2e.e2e.ts --reporter=list
cd frontend && npx playwright test e2e/full-workflow-e2e.e2e.ts --reporter=list
```

**Critical test:** GC-2 (prereq recovery → run → terminal state) must still pass because it depends on workflow generation, not on sequential pipeline detection.

**New test in full-workflow-e2e.e2e.ts — UC-SEQUENTIAL:**
```
User sends:
  "1. FastQC quality control\n2. Adapter trimming\n3. STAR alignment"
Assertions:
  - PipelineListView rendered (data-testid="pipeline-list-view")
  - 3 pipeline steps shown
  - Step 1 title contains "fastqc" or "quality" (case insensitive)
```

---

## 5. No-Regression Checklist

Before merging, verify manually:

| # | Check | Expected |
|---|-------|----------|
| R1 | Single-intent RNA-seq request | One workflow card, not pipeline view |
| R2 | Multi-intent parallel request | Two workflow cards side by side |
| R3 | Clarification ambiguity path | Clarification question returned, no pipeline |
| R4 | ADMET+SMILES fast path | Drug discovery workflow generated |
| R5 | Prose sequential ("then/followed by") | Sequential pipeline detected by LLM |
| R6 | Domain profile +2.0 boost | User's registered domain still gets boosted |
| R7 | `shouldEnableThinking` still exported | No TS compile error (other callers may exist) |

---

## Implementation Order

1. Update `IntentDecomposition` type (add `preferredDomains`, `keyTerms`, `needsThinking`, `chainHint`)
2. Update `analyzeIntent()` system prompt (new fields + remove "handled pre-LLM" comment)
3. Update `parseIntentResult()` (extract new fields, with safe defaults)
4. Delete `detectBulletPipeline()` method + call site
5. Wire `decomposition.needsThinking` into thinking gate
6. Pass `preferredDomains` + `keyTerms` through to Galaxy backend search call
7. Update Python `unified_workflow_search.py` to accept and use them
8. Write unit tests (test-analyze-intent-uqu.ts)
9. Run existing E2E suites; add UC-SEQUENTIAL test

---

## Rollback Plan

If E2E regressions are found:
1. Restore `detectBulletPipeline()` as a **post-LLM enhancement** (not pre-LLM bypass) — it can normalize ambiguous parse results instead of bypassing the LLM
2. Keep new fields in schema (they're additive — no breakage)
3. Keep Python changes (they're guarded by `if preferred_domains is not None`)
