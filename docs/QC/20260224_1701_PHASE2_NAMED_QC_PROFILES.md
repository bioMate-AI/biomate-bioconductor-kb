# Phase 2 — Named QC Profiles (Layer 3) Implementation

**Date:** 2026-02-24 17:01
**Status:** Complete — 422/422 tests passing
**Follows from:** `20260224_1613_PHASE1_CONFIGURABLE_QC_IMPLEMENTATION.md`

---

## Summary

Phase 2 adds the named QC profile system (Layer 3 in the governance stack). Users can
now select a scientifically-curated profile at workflow launch time instead of specifying
individual metric overrides. Profiles are read-only, versioned, and cited.

---

## Governance Stack (Updated)

```
Layer 0: Red Lines          — hardcoded, no override ever (4 red lines)
Layer 1: GOLD thresholds    — no user override: mapped_pct, tss_enrichment, nrf_score
Layer 2: SILVER/BRONZE      — override via qc_overrides dict (Phase 1, 22 keys)
Layer 3: Named profiles     — curated sets of Layer-2 overrides (Phase 2, 20 profiles)  ← NEW
Layer 4: Metadata-inferred  — system suggests profile from metadata (Phase 3 — future)
```

**Precedence:** `explicit qc_overrides > profile overrides > platform defaults`

---

## Profiles Added (20 total)

### RNA-seq (5)
| Profile ID | Key threshold change | Source |
|---|---|---|
| `rnaseq_polya_standard` | Default (no changes) | nf-core/rnaseq v3.14 |
| `rnaseq_ribodepleted` | alignment_rate: 70%→50%, reads_surviving: 70%→65%, assigned_reads: 50%→40% | Zhao et al. 2020 RNA Biol |
| `rnaseq_ffpe` | alignment_rate: 70%→45%, reads_surviving: 70%→60%, q30_pct: 75%→65% | Sinicropi et al. 2012 PLoS ONE |
| `rnaseq_single_nucleus` | alignment_rate: 70%→50% | 10x Genomics snRNA-seq Guide v2.0 |
| `rnaseq_nonmodel_organism` | alignment_rate: 70%→40%, assigned_reads: 50%→30% | [BRONZE] community practice |

### DNA-seq / WGS / WES (6)
| Profile ID | Key threshold change | Source |
|---|---|---|
| `wgs_germline_standard` | Default (no changes) | GATK Best Practices |
| `wgs_germline_lowpass` | mean_coverage: 30X→4X, duplicate_pct: 40%→60% | Rubinacci et al. 2021 Nat Genet |
| `wgs_somatic_tumor_only` | mean_coverage: 30X→80X, duplicate_pct: 40%→50% | GATK Mutect2 guidelines |
| `wgs_ffpe` | duplicate_pct: 40%→65% | Robbe et al. 2018 Nat Med |
| `wes_research` | mean_coverage: 30X→50X | nf-core/sarek v3 |
| `wes_clinical_germline` | mean_coverage: 30X→80X | ACMG 2016 NGS standards |

### Single-cell RNA-seq (3)
| Profile ID | Key threshold change | Source |
|---|---|---|
| `scrna_standard` | Default (no changes) | 10x Genomics Cell Ranger v7 |
| `scrna_cardiac` | mito_fraction_pct: 20%→40%, mito warning: 10%→25% | Simonson et al. 2023; Kuppe et al. 2022 |
| `scrna_neuronal` | mito: 20%→30%, warning: 10%→20%, median_genes: 500→300 | [BRONZE] Allen Brain Atlas |

### Metagenomics (4)
| Profile ID | Key threshold change | Source |
|---|---|---|
| `metagenomics_human_gut` | classified_pct_critical: 30%→50% (tighter) | HMP Consortium 2012 |
| `metagenomics_soil` | critical: 30%→3%, warning: 60%→8% (suppressed) | Bahram et al. 2018 |
| `metagenomics_marine` | critical: 30%→4%, warning: 60%→10% (suppressed) | Sunagawa et al. 2015 |
| `metagenomics_clinical_pathogen` | critical: 30%→60% (tighter), warning: 60%→70% | [BRONZE] IDSA guidance |

### Cryo-EM (3)
| Profile ID | Key threshold change | Source |
|---|---|---|
| `cryoem_spa_purified` | Default (no changes) | EMPIAR/EMDB standards |
| `cryoem_spa_membrane` | total_drift: 50Å→80Å, fit_quality: 0.7→0.65 | [BRONZE] community practice |
| `cryoem_tomo_in_situ` | total_drift: 50Å→150Å, fit_quality: 0.7→0.5, correlation: 0.5→0.3 | [BRONZE] FIB-SEM practice |

---

## Files Changed

### `backend/lib/galaxy/jobs/qc_trace_monitor.py`

1. **`QC_NAMED_PROFILES` constant** added after `QC_GOLD_METRICS`:
   - Dict of 20 profiles, each with `description`, `domain_hint`, `overrides`, `references`
   - Profiles for `metagenomics_soil` and `metagenomics_marine` have lowered warning thresholds (8% and 10% respectively) to match real-world dark matter expectations

2. **Three new classmethods** added in the `# QC override support (Phase 1)` section:
   - `validate_qc_profile(profile_name)` → `(bool, list[str])`
   - `get_profile_overrides(profile_name)` → `Dict[str, Any]`
   - `list_profiles()` → `list[dict]` — used by `/api/qc/profiles` endpoint

3. **`__init__` updated** to accept `qc_profile: Optional[str] = None`:
   - Merge semantics: `{**profile_overrides, **explicit_qc_overrides}` (explicit wins)
   - `self.active_profile` attribute stored for SSE/audit serialization
   - Audit log entry written at init when profile OR overrides are active
   - Log message distinguishes between "named profile active" and "manual overrides"

4. **`_write_audit_log_entry`** includes `active_profile` field

5. **SSE events** both include `"active_profile": self.active_profile`:
   - `_emit_qc_gate_event` (`qc_gate_triggered` event)
   - `_emit_qc_warning_event` (`qc_warning` event)

### `backend/lib/galaxy/jobs/runners/nextflow_monitor.py`

- `NextflowMonitor.__init__` + `register_workflow()` both accept `qc_profile: Optional[str] = None`
- `_init_qc_handler()` passes `qc_profile` to `NextflowQCGateHandler`
- Log message updated to include profile note

### `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

- `NextflowExecuteRequest` adds `qc_profile: Optional[str] = None` field
- `execute_nextflow()` validates profile with `validate_qc_profile()` → HTTP 422 on unknown name
- `_runs` registry stores `qc_profile` per run
- `_start_qc_monitor()` signature extended with `qc_profile: Optional[str] = None` and passes it to `NextflowQCGateHandler`
- **New endpoint**: `GET /api/qc/profiles` returns all 20 profiles with full metadata

---

## API Contract

### Execute with profile
```json
POST /api/nextflow/execute
{
  "nextflow_path": "/path/to/workflow.nf",
  "qc_profile": "rnaseq_ribodepleted",
  "qc_overrides": {"alignment_rate": 45.0}
}
```
Effective alignment_rate threshold = 45.0 (explicit override beats profile's 50.0).

### List profiles
```json
GET /api/qc/profiles

200 OK
{
  "profiles": [
    {
      "id": "rnaseq_ribodepleted",
      "description": "Total RNA with ribosomal depletion...",
      "domain_hint": "rnaseq",
      "overrides": {"alignment_rate": 50.0, "reads_surviving_pct": 65.0, "assigned_reads_pct": 40.0},
      "references": ["Zhao S et al. 2020 RNA Biol 17(8):1105-1118"]
    },
    ...
  ],
  "count": 20
}
```

### Invalid profile → 422
```json
POST /api/nextflow/execute
{"nextflow_path": "...", "qc_profile": "nonexistent_xyz"}

422 Unprocessable Entity
{"error": "Unknown qc_profile", "errors": ["Unknown QC profile 'nonexistent_xyz'. Known profiles: ..."]}
```

---

## Tests Added (`test_qc_edge_cases.py` — `TestNamedProfiles`, 25 tests)

| Category | Tests |
|---|---|
| `validate_qc_profile` | known → valid, unknown → errors, all 20 pass |
| `get_profile_overrides` | ribodepleted alignment, unknown → empty, soil critical ≤ 5% |
| `list_profiles` | count matches constant, all entries have required keys |
| `__init__` merge semantics | profile applies, explicit wins, non-overlapping merge, active_profile stored, None when no profile |
| SSE events | gate event includes active_profile, None when no profile, warning event includes active_profile |
| Audit log | JSONL records include active_profile |
| Biological use cases | ribodepleted (55% passes), cardiac scRNA (35% mito passes), soil meta (12% passes), wgs lowpass (5X passes), membrane protein drift (70Å passes), polya_standard is identity |

---

## Known Limitations / Phase 3 Notes

1. **Profile selection is manual** — user must know which profile applies. Phase 3 will add
   metadata-inferred profile suggestion (organism, tissue type, library type → suggested profile).

2. **No profile forking UI** — users can augment profiles via `qc_overrides` but cannot
   save named variants. Phase 3 will add a `POST /api/qc/profiles/fork` endpoint.

3. **`metagenomics_human_gut` critical threshold is TIGHTER** (50%) than the default (30%) —
   this is intentional (gut is well-characterised) but may surprise users coming from other tools.

4. **`duplicate_pct` is shared by FLAGSTAT and MARKDUP** — Phase 3 will split into
   `flagstat_duplicate_pct` and `markdup_duplicate_pct` for per-tool precision.
