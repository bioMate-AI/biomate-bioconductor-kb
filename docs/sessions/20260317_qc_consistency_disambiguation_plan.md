# QC Consistency + Disambiguation Wiring — Implementation Plan

**Date:** 2026-03-17  
**Based on:** QC consistency audit (41.7% mismatch) + workflow library audit

---

## Problem Statement

Two independent problems, each causing user confusion:

**Problem A — QC Split:** The same threshold (e.g. CTF fit_quality ≥ 0.7) is defined in the 
Python monitoring layer (`qc_trace_monitor.py`) but has NO corresponding `params.` variable in 
the Nextflow `.nf` file. Result: users cannot configure QC thresholds in the workflow panel; 
the monitoring layer uses hardcoded values the user never sees.

**Problem B — Disambiguation:** "variant calling on WGS with BWA and GATK" always produces 
a germline workflow even though a somatic workflow exists — because "somatic" is not in the 
keyword weight table and the search has no way to distinguish intent.

---

## Audit Findings

### QC Consistency (System A vs System B): 41.7% mismatch

| Process | QC Metric | Monitor Value | .nf Param | .nf Value | Status | Severity |
|---------|-----------|--------------|-----------|-----------|--------|----------|
| Alignment | alignment_rate | 70% | min_alignment_rate | 70.0 | ✓ MATCH | OK |
| Coverage | mean_coverage | 20× | min_mean_coverage | 20 | ✓ MATCH | OK |
| Test mode | mock_mode | supported | mock_mode | true | ✓ MATCH | OK |
| CTF fitting | fit_quality | 0.7 (red: 0.5) | **MISSING** | — | 🔴 MISMATCH | CRITICAL |
| Motion | total_drift_angstrom | 50 Å | **MISSING** | — | 🔴 MISMATCH | CRITICAL |
| Duplicates | duplicate_pct | ≤30% GOLD | **MISSING** | hardcoded | ⚠ MISMATCH | HIGH |
| Read quality | q30_pct | 75% | **MISSING** | — | ⚠ MISMATCH | HIGH |
| Phase shift | avg_phase_shift_rad | [0.2,1.5] rad | phase_plate (bool) | false | ⚡ PARTIAL | LOW |

### Variant Calling Workflows — Both Exist

| Type | File | Domain | Key Inputs |
|------|------|--------|------------|
| Germline | `genomics/wgs_germline_gatk/main.nf` | genomics | paired FASTQ (params.reads) |
| Somatic | `cancer_biology/detect_and_annotate_somatic_mutations/main.nf` | cancer_biology | params.tumor_bam + params.normal_bam |

"somatic" is NOT in the keyword weight table → the search always returns germline when 
"BWA GATK WGS" are present, even after the user answers a clarifying question.

---

## Implementation Plan

### Phase 1 — Fix .nf files: add missing QC threshold params (P0/P1)

#### 1a. cryosparc_standard_spa/main.nf — add CTF and motion params

Add to `params {}` block:
```groovy
// QC gate thresholds (used by BioMate qc_trace_monitor; surfaced in workflow panel)
params.fit_quality_threshold       = 0.7     // CTF fit quality minimum (red-line: 0.5)
params.total_drift_max_angstrom    = 50.0    // Max total drift in Å (profile: membrane=80, lowdose=60)
params.qc_profile                  = null    // Named profile: cryoem_spa_membrane | cryoem_spa_lowdose | ...
```

Add to parameter_metadata (returned by backend when building workflow panel):
```python
"fit_quality_threshold": {
    "label": "CTF Fit Quality Minimum",
    "type": "float",
    "help": "Minimum acceptable CTF fit quality score (0–1). Below 0.5 = estimation failed.",
    "level": "recommended",
    "default": 0.7,
    "step": "CTF Estimation",
    "qc_threshold": True,   # flag: this param drives a QC gate
}
```

#### 1b. wgs_germline_gatk/main.nf — add duplicate_pct and q30_pct params

Add to `params {}` block:
```groovy
params.max_duplicate_pct           = 30.0    // GOLD metric: ≤30% (GATK Best Practices)
params.min_q30_pct                 = 75.0    // Q30 read quality threshold
params.min_assigned_reads_pct      = 50.0    // Feature counting: ≥50% assigned reads
params.qc_profile                  = null    // Named profile: wgs_germline_standard | wgs_ffpe | ...
```

#### 1c. Principle for all future workflows
Every QC gate in `qc_trace_monitor.py` that monitors a process in workflow X MUST have a 
corresponding `params.` variable in that workflow's `.nf` file. The param name convention:
- Minimum thresholds: `params.min_{metric_name}`
- Maximum thresholds: `params.max_{metric_name}`
- Named profile: `params.qc_profile`

---

### Phase 2 — Make qc_trace_monitor read thresholds from workflow params

When `execute_nextflow()` starts the QC monitor, it passes `qc_overrides`. Currently these 
come from the frontend execute request. After Phase 1, they ALSO come from the workflow's 
own `params`:

In `nextflow_executor.py → execute_nextflow()`, before `_start_qc_monitor()`:
```python
# Extract QC threshold params from the workflow's own params dict
# These take priority over named-profile defaults but are overridden by explicit qc_overrides
workflow_qc_params = {
    "fit_quality": request.parameters.get("fit_quality_threshold"),
    "total_drift_angstrom": request.parameters.get("total_drift_max_angstrom"),
    "max_duplicate_pct": request.parameters.get("max_duplicate_pct"),
    "min_q30_pct": request.parameters.get("min_q30_pct"),
}
# Remove None values
workflow_qc_params = {k: v for k, v in workflow_qc_params.items() if v is not None}

# Merge: explicit qc_overrides > workflow_qc_params > named profile > defaults
merged_qc_overrides = {**workflow_qc_params, **(request.qc_overrides or {})}

_start_qc_monitor(
    run_id, nextflow_path, log_dir,
    qc_profile=request.qc_profile,
    qc_overrides=merged_qc_overrides,   # ← now includes workflow param values
    ...
)
```

Result: when the user sets `fit_quality_threshold = 0.65` in the workflow panel, that value 
flows to the QC monitor automatically — no separate QC settings needed.

---

### Phase 3 — Surface QC threshold params in the workflow panel

QC threshold params (those with `"qc_threshold": True` in parameter_metadata) should be 
rendered in the workflow panel as first-class parameters — under the step they belong to.

Visual treatment (in ParameterGroup / ParameterInput):
- Small "QC" badge next to the label
- Description: "BioMate will pause workflow if this threshold is crossed"
- Same Required/Recommended/Optional/Advanced classification as other params

In `buildViewerParameters()` / `parameter_metadata`, the `step` field (Phase 1c) enables 
these QC params to appear in the correct step group (e.g., `fit_quality_threshold` under 
"CTF Estimation" step card).

This closes the loop: user sees, edits, and submits QC thresholds alongside computational 
params — no hidden monitoring layer.

---

### Phase 4 — Fix disambiguation: keyword weights + domain suppression

#### 4a. unified_workflow_search.py — add discriminating keywords

Add to the keyword weight table:
```python
# Variant type disambiguation — MUST score higher than BWA/GATK to override
'somatic':           4.0,   # Tumor-specific mutations → cancer_biology domain
'germline':          3.5,   # Inherited variants → genomics domain
'tumor':             3.5,
'mutect':            4.0,
'mutect2':           4.0,
'tumor_normal':      4.0,
'inherited':         2.5,
'haplotypecaller':   3.5,

# RNA-seq type disambiguation
'bulk_rnaseq':       3.0,
'scrna':             3.5,
'single_cell':       3.5,
'deseq2':            2.5,   # → differential expression
'seurat':            3.5,   # → single-cell
```

#### 4b. unified_workflow_search.py — domain suppression for somatic queries

In `_infer_domain_preferences()`, add:
```python
somatic_tokens = {'somatic', 'tumor', 'mutect', 'mutect2', 'tumor_normal', 'cancer'}
if somatic_tokens & query_tokens:
    # Suppress genomics domain (germline workflows) for somatic queries
    domain_penalties['genomics'] = -50
    domain_boosts['cancer_biology'] = +40
```

After this fix: "perform variant calling on WGS with BWA and GATK" + user says "somatic" 
→ combined context has "somatic" → domain suppression fires → somatic workflow wins.

#### 4c. galaxy-assistant.ts — ambiguity detection in analyzeIntent

Add to the system prompt for intent analysis:
```
AMBIGUITY DETECTION:
When the user's request matches multiple fundamentally different workflows, set:
  "workflowAmbiguity": "variant_type" | "rnaseq_type" | "crispr_type" | null

Known fork points:
- "variant calling" without "germline" or "somatic" → "variant_type"
- "RNA-seq" or "transcriptomics" without "single cell" or "scrna" → "rnaseq_type"  
- "CRISPR" without "screen" qualifier → "crispr_type"
```

In `processMessage()`, before workflow generation:
```typescript
if (intent.workflowAmbiguity && !this.clarificationResolved(context, intent.workflowAmbiguity)) {
  // Return early with a clarifying question — do NOT generate workflow yet
  return this.buildClarificationResponse(intent.workflowAmbiguity);
}
```

The clarifying questions are pre-defined per ambiguity type:
```typescript
const CLARIFICATION_QUESTIONS = {
  variant_type: "Is this germline variant calling (inherited variants, e.g. rare disease) or somatic variant calling (tumor mutations, requires matched normal sample)?",
  rnaseq_type: "Is this bulk RNA-seq (differential expression) or single-cell RNA-seq?",
  crispr_type: "Is this a genome-wide CRISPR screen or targeted editing validation?",
};
```

When the user answers, the next message includes "germline" or "somatic" in context → Phase 4a/4b ensures the correct workflow is selected.

---

## Execution Order

| Priority | Task | Files | Effort |
|----------|------|-------|--------|
| P0 | Add `fit_quality_threshold` + `total_drift_max_angstrom` to CryoEM .nf | `cryosparc_standard_spa/main.nf` | Small |
| P0 | Make qc_trace_monitor use workflow params (Phase 2) | `nextflow_executor.py` | Small |
| P1 | Add `max_duplicate_pct` + `min_q30_pct` to WGS .nf | `wgs_germline_gatk/main.nf` | Small |
| P1 | Add `qc_threshold: True` flag to parameter_metadata | `ai_assistant.py` | Medium |
| P1 | Surface QC threshold params in workflow panel (Phase 3) | `nextflow-workflow-viewer.tsx`, `parameter-group.tsx` | Medium |
| P2 | Fix keyword weights for somatic/germline | `unified_workflow_search.py` | Small |
| P2 | Add domain suppression for somatic queries | `unified_workflow_search.py` | Small |
| P2 | Add ambiguity detection to intent analysis | `galaxy-assistant.ts` | Medium |
| P3 | Add consistency unit tests | `tests/test_qc_consistency.py` | Medium |

---

## What This Does NOT Change

- QC architecture: monitoring layer stays parallel to Nextflow (correct by design)
- Named profiles (31 profiles in qc_trace_monitor.py) remain the authoritative source of 
  domain-specific threshold overrides; the .nf params become the user-visible control surface
- Users never see the monitoring layer directly — they configure thresholds as workflow params
  and BioMate uses those values for both Nextflow execution AND QC governance

