# Supplementary S9 — QC Governance Architecture
**Paper:** BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale
**Module:** `backend/lib/galaxy/jobs/qc_trace_monitor.py` (core logic)
**API:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (QC profile endpoint)
**Frontend:** `frontend/client/src/components/qc-gate-modal.tsx`, `workflow-artifact.tsx`

---

## Overview

BioMate implements a four-layer governance stack that separates evidence tiers, operator overrides, audit trails, and real-time user notification. The four layers interact through a strictly defined precedence order:

```
Layer 0: Red lines (absolute bounds — cannot be overridden by anyone)
   ↓
Layer 1: GOLD metrics (ENCODE4 / GATK mandated — cannot be user-overridden)
   ↓
Layer 2: Platform defaults (evidence-graded SILVER / BRONZE defaults)
   ↓
Layer 3: Named profiles + per-invocation overrides (user-configurable)
```

Each layer is formally specified in `qc_trace_monitor.py` as a Python constant or dataclass so that the governance logic is version-controlled alongside the workflows it governs.

---

## 1. Layer 0: Red Lines

Red lines are absolute bounds that apply regardless of any user or profile override. They represent the point at which continued analysis is definitionally invalid, not merely of lower quality.

### 1.1 Red-line specification

Defined as `QC_RED_LINES` (line 31):

```python
QC_RED_LINES: Dict[str, Any] = {
    "reads_surviving_pct": {
        "bound": 50.0, "direction": "min",
        "rationale": "> 50% loss = adapter-dominated library; downstream analysis is invalid",
    },
    "fit_quality": {
        "bound": 0.5, "direction": "min",
        "rationale": "CTF estimation completely failed; particle picking results are invalid",
    },
    "mito_fraction_pct": {
        "bound": 80.0, "direction": "max",
        "rationale": "Dead-cell lysates, not transcriptomes; results are biologically meaningless",
    },
    "alignment_rate": {
        "bound": 5.0, "direction": "min",
        "rationale": "< 5% alignment = species/sample swap; halt unconditionally",
    },
}
```

### 1.2 Red-line enforcement

In `_get_threshold()` (line 711), after applying any user override value, the result is clamped to the red-line bound:

```python
if rl["direction"] == "min" and override_val < rl["bound"]:
    log.warning(f"[QC Override] '{metric}' override {override_val} crosses red-line floor ...")
    override_val = rl["bound"]
elif rl["direction"] == "max" and override_val > rl["bound"]:
    ...
    override_val = rl["bound"]
```

The clamp is logged, written to `qc_overrides_audit.jsonl`, and the clamped value (not the user's value) is applied to the gate.

### 1.3 Hard-coded non-overridable gates

Three gates bypass `_get_threshold()` entirely and use hard-coded thresholds:

| Gate | Value | Location | Rationale |
|---|---|---|---|
| Critical alignment rate | 25% | `_check_qc_thresholds`, alignment branch | < 25% = catastrophic; species/genome swap is the only explanation below this floor |
| Invalid SMILES count | > 0 | `_check_qc_thresholds`, SMILES branch | Any invalid SMILES is a data integrity error |
| GOLD FDR gate | 1% | `_check_qc_thresholds`, proteomics branch | Elias & Gygi 2007 — cannot be relaxed for any study design |

The critical alignment gate (< 25%) is always checked first in the alignment branch; if triggered, the normal 70% gate is suppressed (only one failure dict is emitted).

---

## 2. Layer 1: GOLD Metrics

GOLD metrics are mandated by external authoritative bodies (ENCODE4, GATK Best Practices, ACMG). Users cannot override these thresholds via `qc_overrides`. Any attempt to override a GOLD metric is silently ignored (log warning issued) and the default is used.

### 2.1 GOLD metric specification

Defined as `QC_GOLD_METRICS` (line 53):

```python
QC_GOLD_METRICS: frozenset = frozenset({
    "mapped_pct",       # GATK Best Practices: FLAGSTAT mapped ≥ 70%
    "tss_enrichment",   # ENCODE4 ATAC-seq 2022: ≥ 5 acceptable, ≥ 7 ideal
    "nrf_score",        # ENCODE4 ATAC-seq 2022: ≥ 0.9
})
```

### 2.2 Override rejection logic

In `_get_threshold()` (line 728):

```python
if metric in QC_GOLD_METRICS:
    log.warning(
        f"[QC Override] Ignoring override for GOLD metric '{metric}' "
        f"(ENCODE4/GATK mandated — not user-configurable)"
    )
    return default
```

The rejection is silent to the end user (no error returned) but is logged at WARNING level for operator audit.

---

## 3. Layer 2: Platform Defaults (Evidence-Graded)

Platform defaults are the gate values used when no override is active. Each default has an explicit evidence tier:

| Tier | Abbrev | Source | Override allowed? |
|---|---|---|---|
| GOLD | [GOLD] | ENCODE4, GATK Best Practices, ACMG 2016 | No (Layer 1 protection) |
| SILVER | [SILVER] | Major bioinformatics pipelines (nf-core, GATK) or community standards | Yes (via qc_overrides) |
| BRONZE | [BRONZE] | Community heuristics; expert consensus without formal publication | Yes (via qc_overrides) |
| ADVISORY | [ADVISORY] | Informational only; no published threshold | Non-blocking advisory always |

All gate defaults, operators, and evidence tiers are specified inline in `_check_qc_thresholds` via `_get_threshold(metric_key, default_value)` calls and accompanying code comments. A human-readable version is published at `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md`.

---

## 4. Layer 3: Named Profiles and Per-Invocation Overrides

### 4.1 Named profiles

Named profiles are curated sets of Layer-2 overrides validated for well-characterised assay contexts. They are defined in `QC_NAMED_PROFILES` (line 69) as a versioned Python constant.

**Profile schema:**

```python
{
    "profile_name": {
        "description": str,           # human-readable summary
        "domain_hint": str,           # informational: primary domain
        "overrides": Dict[str, float], # threshold overrides
        "references": List[str],       # citations
    }
}
```

**Complete profile inventory (31 profiles as of 2026-03-04):**

| Category | Profiles |
|---|---|
| RNA-seq (5) | `rnaseq_polya_standard`, `rnaseq_ribodepleted`, `rnaseq_ffpe`, `rnaseq_single_nucleus`, `rnaseq_nonmodel_organism` |
| DNA-seq / WGS / WES (6) | `wgs_germline_standard`, `wgs_germline_lowpass`, `wgs_somatic_tumor_only`, `wgs_ffpe`, `wes_research`, `wes_clinical_germline` |
| Single-cell RNA-seq (4) | `scrna_standard`, `scrna_cardiac`, `scrna_neuronal`, `scrna_perturbation` |
| Metagenomics (4) | `metagenomics_human_gut`, `metagenomics_soil`, `metagenomics_marine`, `metagenomics_clinical_pathogen` |
| Cryo-EM (4) | `cryoem_spa_purified`, `cryoem_spa_membrane`, `cryoem_spa_phase_plate`, `cryoem_tomo_in_situ` |
| Proteomics LC-MS/MS (4) | `proteomics_standard`, `proteomics_phospho`, `proteomics_plasma_biomarker`, `proteomics_chemoproteomics` |
| Cheminformatics (3) | `compound_druglike`, `compound_natural_product`, `compound_peptidomimetic` |
| Pharmacogenomics (2) | `pgx_clinical`, `pgx_research` |

**API endpoint:** `GET /api/qc/profiles` returns all profiles as JSON:
```json
[
  {"id": "rnaseq_ribodepleted", "description": "...", "domain_hint": "rnaseq",
   "overrides": {"alignment_rate": 50.0, ...}, "references": [...]}
]
```

### 4.2 Per-invocation overrides

Users may supply a `qc_overrides` dict at workflow launch (via the execution panel or API). These override any profile defaults for the same key.

**Precedence rule (highest first):**
1. Per-invocation `qc_overrides` (user-supplied explicit values)
2. Named profile `overrides` (selected profile defaults)
3. Platform defaults (Layer 2)

**Merge logic in `__init__`** (line 603):
```python
profile_overrides = self.get_profile_overrides(qc_profile) if qc_profile else {}
explicit_overrides = qc_overrides or {}
self.qc_overrides = {**profile_overrides, **explicit_overrides}
```
Right-hand-side wins on key collision; explicit overrides always take precedence.

**Override keys (22 supported):**

| Key | Default | Applies to |
|---|---|---|
| `alignment_rate` | 70.0% | STAR, HISAT2, BWA-MEM |
| `reads_surviving_pct` | 70.0% | FASTP, TrimGalore, Trimmomatic |
| `q30_pct` | 75.0% | FASTP |
| `assigned_reads_pct` | 50.0% | featureCounts, HTSeq |
| `mapping_rate` | 50.0% | Salmon, Kallisto |
| `duplicate_pct` | 40.0% | Picard MarkDuplicates |
| `mean_coverage` | 30.0× | mosdepth, Picard WGS metrics |
| `mito_fraction_pct` | 20.0% | CellRanger, STARsolo |
| `median_genes_per_cell` | 500 | CellRanger, STARsolo |
| `classified_pct_critical` | 30.0% | Kraken2, MetaPhlAn |
| `classified_pct_warning` | 60.0% | Kraken2, MetaPhlAn |
| `total_drift_angstrom` | 50 Å | MotionCor2, RELION |
| `fit_quality` | 0.70 | CTFFIND4 |
| `astigmatism_angstrom` | 1000 Å | CTFFIND4 |
| `particles_picked` | 1000 | RELION, crYOLO |
| `junk_class_fraction` | 0.50 | CryoSPARC 2D |
| `fsc_resolution_angstrom` | 10.0 Å | CryoSPARC refinement |
| `local_resolution_std_spread` | 3.0 Å | CryoSPARC local res |
| `avg_phase_shift_rad_min` | 0.20 rad | VPP CTF (advisory) |
| `avg_phase_shift_rad_max` | 1.50 rad | VPP CTF (advisory) |
| `peaks_called` | 1000 | MACS2/3 |
| `sequencing_saturation_pct` | 30.0% | CellRanger |

---

## 5. Audit Trail

All invocations where overrides or profiles are active write a JSONL audit log at `{work_dir}/qc_overrides_audit.jsonl`. Each JSONL line is a self-contained JSON object.

### 5.1 Audit entry schema

```json
{
  "timestamp": "2026-03-04T15:10:22.381000+00:00",
  "invocation_id": "inv-abc123",
  "event_type": "initialized",
  "active_profile": "rnaseq_ribodepleted",
  "configured_overrides": {"alignment_rate": 50.0, "reads_surviving_pct": 65.0},
  "applied_overrides": {}
}
```

| Field | Type | Description |
|---|---|---|
| `timestamp` | ISO 8601 UTC | Time of event |
| `invocation_id` | string | Workflow invocation ID |
| `event_type` | `"initialized"` \| `"gate_triggered"` \| `"override_clamped"` | What happened |
| `active_profile` | string \| null | Named profile if active |
| `configured_overrides` | object | All effective overrides (profile + explicit merged) |
| `applied_overrides` | object | Overrides that were actually used in a gate check |

A record is written on: (1) handler initialisation when overrides/profile are present; (2) each `_check_qc_thresholds` call where an override is applied; (3) red-line clamping events.

### 5.2 Audit log location

Written to `work_dir / "qc_overrides_audit.jsonl"`. In production AWS Batch execution, `work_dir` is the Nextflow S3 working directory; the JSONL file is uploaded to S3 at workflow completion. In local execution, it is in the local Nextflow `work/` directory.

---

## 6. Real-Time User Notification via SSE

### 6.1 Event types

BioMate emits two SSE event types for QC:

| Event type | When emitted | Frontend behaviour |
|---|---|---|
| `qc_gate_triggered` | One or more **blocking** failures | QC gate modal appears; workflow pauses |
| `qc_warning` | Advisory items or near-threshold values only | Step annotation updated; no modal; workflow continues |

### 6.2 Event dispatch logic

In `handle_process_completion` (line 786):

```python
qc_passed, all_failures = self._check_qc_thresholds(process_name, qc_metrics)

blocking_failures = [f for f in all_failures if not f.get("advisory", False)]
advisory_items = [f for f in all_failures if f.get("advisory", False)]

if not qc_passed:
    # blocking_failures exist → gate event (modal)
    self._emit_qc_gate_event(process_name, qc_metrics, all_failures)
else:
    # no blocking failures → advisory + near-threshold → warning event
    near_threshold = self._check_qc_warnings(process_name, qc_metrics)
    all_warnings = advisory_items + near_threshold
    if all_warnings:
        self._emit_qc_warning_event(process_name, qc_metrics, all_warnings)
```

`qc_passed` is `True` when the only failures are advisory (`advisory: True`). This means an advisory-only outcome routes to `_emit_qc_warning_event`, not `_emit_qc_gate_event`.

### 6.3 Near-threshold warnings

`_check_qc_warnings()` uses a helper `_near_above(val, threshold, pct=0.10)` that returns `True` if `threshold ≤ val ≤ threshold × 1.10` (metric is ≤ 10% above the blocking threshold):

| Metric | Blocking threshold | Warning fires when |
|---|---|---|
| `alignment_rate` | 70% | 70–77% |
| `reads_surviving_pct` | 70% | 70–77% |
| `mapping_rate` | 50% | 50–55% |
| `classified_pct` | 60% (warning tier) | 60–66% |
| `mean_coverage` | 30× | 30–33× |
| `tss_enrichment` | 5.0 | 5.0–5.5 |
| `nrf_score` | 0.9 | 0.9–0.99 |
| `mito_fraction_pct` | 20% | 10–20% (advisory onset at 10%) |
| `ctf_fit_quality` | 0.70 | 0.70–0.77 |
| `particles_selected` | 50,000 | 50,000–55,000 |
| `junk_class_fraction` | 0.50 | 0.45–0.50 |
| `total_drift_angstrom` | 50 Å | 40–50 Å |
| `avg_phase_shift_rad` | 0.20 rad (VPP depleted) | 0.20–0.22 rad |
| `avg_phase_shift_rad` | 1.50 rad (VPP over-charged) | 1.35–1.50 rad |

Near-threshold warnings are not audit-logged (they are informational, not governance decisions).

### 6.4 SSE payload schema

**`qc_gate_triggered` payload:**

```json
{
  "event_type": "qc_gate_triggered",
  "invocation_id": "string",
  "process_name": "string",
  "timestamp": "ISO 8601 UTC",
  "qc_metrics": {"metric_key": numeric_value},
  "failures": [
    {
      "metric": "string",
      "value": "number",
      "threshold": "number",
      "operator": "< | > | <= | >=",
      "message": "string",
      "advisory": false,
      "severity": "warning | critical"   // optional; present for two-tier gates
    }
  ],
  "suggestions": [
    {
      "parameter": "string",
      "currentValue": "any",
      "suggestedValue": "any",
      "reason": "string",
      "confidence": "0.0–1.0",
      "source": "rule | literature | empirical"
    }
  ],
  "active_profile": "string | null",
  "active_overrides": {"metric_key": "applied_value"}
}
```

**`qc_warning` payload:**

Same schema except:
- `event_type: "qc_warning"`
- `"failures"` field is absent; replaced by `"warnings"` (same item schema, all items have `advisory: true` or `severity: "near_threshold"`)
- `"suggestions"` field is absent (warnings are informational; parameter changes are not prompted)

---

## 7. Parameter Suggester Architecture

When a `qc_gate_triggered` event fires, BioMate calls the parameter suggester to populate the `suggestions` array. The suggester is domain-specific and is instantiated once per invocation.

### 7.1 Suggester class hierarchy

```
ParameterSuggester (abstract base, parameter_suggester.py)
├── RNASeqParameterSuggester     — STAR, HISAT2, FASTP, featureCounts, Salmon
├── GenomicsParameterSuggester   — BWA-MEM, mosdepth, Picard MarkDuplicates
├── SingleCellParameterSuggester — CellRanger, STARsolo
├── ChIPSeqParameterSuggester    — MACS2, ATAC_QC, TSS_ENRICH
├── MetagenomicsParameterSuggester — Kraken2
├── CryoEMParameterSuggester     — all cryo-EM process types (9 stages)
│     ├── _suggest_ctf_estimation()
│     ├── _suggest_motion_correction()
│     ├── _suggest_particle_picking()
│     ├── _suggest_classification_2d()
│     ├── _suggest_refinement()
│     ├── _suggest_sharpening()       ← B-factor guidance (Rosenthal & Henderson 2003)
│     └── _suggest_local_resolution() ← 3D variability / focused classification
├── ProteomicsParameterSuggester — MaxQuant, DIA-NN
└── DrugDiscoveryParameterSuggester — hERG, DILI, Ames, pulldown, QSAR
```

### 7.2 Domain routing

`get_suggester_for_domain(domain: str, logger) -> ParameterSuggester` (line 1 of `parameter_suggester.py`) selects the appropriate class by substring match on `domain_lower`:

| Domain substring(s) | Suggester |
|---|---|
| `cryo_em`, `cryoem`, `spa`, `electron_microscopy` | `CryoEMParameterSuggester` |
| `rnaseq`, `rna_seq`, `rna` | `RNASeqParameterSuggester` |
| `wgs`, `wes`, `dna_seq`, `dnaseq`, `genomics`, `variant_calling` | `GenomicsParameterSuggester` |
| `scrna`, `scrna_seq`, `single_cell` | `SingleCellParameterSuggester` |
| `atac_seq`, `atacseq`, `chip_seq`, `chipseq` | `ChIPSeqParameterSuggester` |
| `metagenomics`, `metagenome`, `microbiome` | `MetagenomicsParameterSuggester` |
| `proteomics`, `proteome`, `maxquant`, `diann`, `spectronaut`, `chemoproteomics` | `ProteomicsParameterSuggester` |
| `drug`, `chemo` (non-proteomics), `herg`, `dili`, `compound`, `admet` | `DrugDiscoveryParameterSuggester` |

### 7.3 Suggestion schema

Each suggestion item:

```python
{
    "parameter": str,          # Nextflow param name
    "currentValue": Any,       # value from current_parameters dict (None if absent)
    "suggestedValue": Any,     # recommended value
    "reason": str,             # plain-English rationale
    "confidence": float,       # 0.0–1.0; ≥0.7 = auto-applied when pause_at_qc_failures=False
    "source": str,             # "rule" | "literature" | "empirical"
}
```

### 7.4 Confidence-based auto-apply

When the user disables "Pause at QC failures" in the execution panel (`pauseAtQcFailures = false`), the frontend auto-applies all suggestions with `confidence ≥ 0.7` when a QC gate fires, then re-runs the step without showing a modal. The workflow continues uninterrupted. A `qc_warning`-style step annotation is added to record the auto-applied change.

---

## 8. Formal Precedence Statement

The complete threshold resolution algorithm for any metric `m` with event-default `d`:

```
1. If m ∈ QC_RED_LINES:
       return clamp(resolve_override(m, d), QC_RED_LINES[m])

2. If m ∈ QC_GOLD_METRICS:
       ignore any override; return d

3. If m ∈ explicit qc_overrides:
       v = float(qc_overrides[m])
       if m ∈ QC_RED_LINES: v = clamp(v, QC_RED_LINES[m])
       return v

4. If m ∈ active named profile overrides:
       v = float(profile[m])
       if m ∈ QC_RED_LINES: v = clamp(v, QC_RED_LINES[m])
       return v

5. return d  (platform default)
```

This algorithm is implemented in `_get_threshold()` (line 711). Steps 3 and 4 are collapsed because profile and explicit overrides are merged in `__init__` with explicit values taking precedence.

---

## 9. Mock Reproduction Guide — Governance Stack

```bash
cd /home/yzhang/biomate/backend

.venv/bin/python - << 'EOF'
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler, QC_RED_LINES, QC_GOLD_METRICS

# --- Demonstrate Layer 0: Red-line clamping ---
# Try to relax reads_surviving_pct below 50% (red-line floor)
events = []
from unittest.mock import Mock
from pathlib import Path
handler = NextflowQCGateHandler(
    invocation_id="demo-001",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="rnaseq",
    qc_overrides={"reads_surviving_pct": 30.0}  # attempts to relax below red-line
)
effective = handler._get_threshold("reads_surviving_pct", 70.0)
print(f"Attempted override: 30.0%, effective: {effective}%")
# Expected: 50.0% (clamped to red-line floor, not 30.0)

# --- Demonstrate Layer 1: GOLD override rejection ---
handler2 = NextflowQCGateHandler(
    invocation_id="demo-002",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="atac_seq",
    qc_overrides={"nrf_score": 0.5}  # attempts to override GOLD metric
)
effective2 = handler2._get_threshold("nrf_score", 0.9)
print(f"GOLD override attempt: 0.5, effective: {effective2}")
# Expected: 0.9 (GOLD metric; override silently rejected)

# --- Demonstrate Layer 3: Named profile ---
handler3 = NextflowQCGateHandler(
    invocation_id="demo-003",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="rnaseq",
    qc_profile="rnaseq_ribodepleted"  # profile sets alignment_rate=50.0
)
effective3 = handler3._get_threshold("alignment_rate", 70.0)
print(f"Profile override: 70.0% default → {effective3}% (rnaseq_ribodepleted)")
# Expected: 50.0% (from named profile)
EOF
```

---

## 10. QC Event Log (In-Memory)

Each `NextflowQCGateHandler` instance maintains `self.qc_event_log: list` for the duration of the invocation. Each entry:

```python
{
    "type": "gate" | "warning",
    "process_name": str,
    "timestamp": str,           # ISO 8601 UTC
    "metrics": dict,
    "failures": list,           # present for "gate" entries
    "warnings": list,           # present for "warning" entries
    "suggestions": list,        # present for "gate" entries
}
```

This log is used by `GET /api/invocations/:id/qc-events`, which returns:

```json
{
  "gates_triggered": 1,
  "warnings_emitted": 2,
  "events": [...],
  "methods_text": "Quality control was performed automatically by BioMate ..."
}
```

The `methods_text` field is auto-generated for inclusion in the methods section of a manuscript, listing which profiles were active, how many gates fired, and directing readers to the BioMate QC governance documentation for threshold citations.
