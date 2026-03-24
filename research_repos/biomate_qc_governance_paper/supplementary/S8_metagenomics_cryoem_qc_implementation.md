# Supplementary S8 — Metagenomics and Cryo-EM SPA QC Implementation
**Paper:** BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale
**Module:** `backend/lib/galaxy/jobs/qc_trace_monitor.py`
**Suggester:** `backend/lib/galaxy/jobs/parameter_suggester.py` → `MetagenomicsParameterSuggester`, `CryoEMParameterSuggester`
**Test classes:** `TestMetagenomicsQCDomain` (in `tests/test_qc_e2e_domains.py`); `TestPriyaCryoEM_P1Gates`, `TestPriyaCryoEM_P2Gates`, `TestCryoEMNearThresholdWarnings`, `TestPriyaCryoEM_PhasePlate` (in `tests/test_qc_edge_cases.py`)

---

## Overview

This supplement covers two structurally distinct domains:

1. **Metagenomics:** BioMate monitors Kraken2 / MetaPhlAn taxonomic classification rate with two-tier thresholds (CRITICAL < 30%, WARNING < 60%). Four named profiles adapt the thresholds to well-characterised low-classification environments (soil, marine, clinical pathogen, human gut).

2. **Cryo-EM single-particle analysis (SPA):** BioMate monitors nine sequential SPA pipeline steps (motion correction → CTF estimation → particle picking → 2D classification → refinement → sharpening → local resolution) with seven parsers. CTF estimation has the most complex gate logic: it handles CryoSPARC `.cs` JSON, summary JSON, and CTFFIND4 text formats, and includes a directional defocus-out-of-range gate and a Volta Phase Plate (VPP) advisory gate.

---

## Part 1: Metagenomics

### 1.1 Process name routing

| Keyword | Tool |
|---|---|
| `KRAKEN2`, `KRAKEN`, `KRAKEN2_KRAKEN2` | Kraken2 (Wood, Lu & Langmead 2019) |
| `BRACKEN` | Bracken abundance re-estimation |
| `METAPHLAN` | MetaPhlAn4 (marker-based) |
| `KAIJU` | Kaiju (protein-based) |

### 1.2 Output files read

Parser: `_parse_metagenomics_metrics` (line 1818)

| Priority | Glob | Format | Field |
|---|---|---|---|
| 1 | `*.report`, `*kraken*`, `*.k2report` | Kraken2 report TSV | Column 0 = `%`; column 3 = rank (`U` = unclassified) |

**Kraken2 report format (tab-separated):**
```
100.00  500000  500000  U  0  unclassified
 72.34  361700  0       R  1  root
  ...
```
BioMate scans the first 5 lines for a row with rank `U` (column 3), reads the percentage (column 0), and computes:
```
classified_pct = 100.0 - unclassified_pct
```

### 1.3 Gate logic

The metagenomics gate is **two-tier** with domain-adjustable thresholds:

| Tier | Metric | Default threshold | Evidence | Operator | Severity | Message |
|---|---|---|---|---|---|---|
| CRITICAL | `classified_pct` | 30% | [SILVER] | `<` | `critical` | `"Critically low classification: {val:.1f}% (threshold: {t:.0f}%). Contamination, wrong database, or highly divergent organisms."` |
| WARNING | `classified_pct` | 60% | [BRONZE] | `<` | `warning` | `"Low classification rate: {val:.1f}% (threshold: {t:.0f}%). Consider a larger Kraken2 database."` |

**Evidence:** Wood, Lu & Langmead 2019 (Genome Biol 20:257). Novel environments classify 40–80% of reads depending on database comprehensiveness. A classification rate < 30% is definitionally problematic: below this floor, downstream abundance estimates are unreliable regardless of the environment.

**Override keys:** `classified_pct_critical` (default 30) and `classified_pct_warning` (default 60) are used by `_get_threshold()`. Both are SILVER tier and therefore overridable via `qc_overrides`.

### 1.4 Near-threshold warning

| Metric | Warning range | Message |
|---|---|---|
| `classified_pct` | 60–66% | `"Classification rate {val:.1f}% is near the 60% warning threshold — consider upgrading the Kraken2 database"` |

### 1.5 Named profile overrides

| Profile | `classified_pct_critical` | `classified_pct_warning` | Rationale |
|---|---|---|---|
| `metagenomics_human_gut` | 50.0 | 60.0 | Well-characterised gut microbiome; < 50% unusual (HMP Consortium 2012 Nature) |
| `metagenomics_soil` | 3.0 | 8.0 | High microbial "dark matter"; soil routinely classifies 5–40% (Bahram et al. 2018 Nature; Delgado-Baquerizo et al. 2018 Science) |
| `metagenomics_marine` | 4.0 | 10.0 | Open-ocean; 10–50% typical (Sunagawa et al. 2015 Science TARA Oceans) |
| `metagenomics_clinical_pathogen` | 60.0 | 70.0 | Clinical bloodstream / CSF; very low classification warrants investigation (IDSA 2024) |

### 1.6 Parameter suggestions

Triggered by `MetagenomicsParameterSuggester`:

| Gate metric | Suggestion | Confidence | Source |
|---|---|---|---|
| `classified_pct < 60%` | Upgrade to Standard 8 GB or PlusPFP database | 0.85 | Kraken2 docs |
| `classified_pct < 60%` | Lower `--confidence` threshold (try 0.0) | 0.75 | rule |
| `classified_pct < 30%` | Verify species; check for host contamination; consider re-extraction | advisory | rule |

### 1.7 Mock reproduction guide

```bash
cd /home/yzhang/biomate/backend

mkdir -p /tmp/test_kraken_workdir
cat > /tmp/test_kraken_workdir/sample.report << 'EOF'
 45.20  226000  226000  U  0  unclassified
 54.80  274000  0       R  1  root
 48.32  241600  0       D  2157  Archaea
EOF

.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-meta-001",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="metagenomics"
)
metrics = handler._parse_metagenomics_metrics(Path("/tmp/test_kraken_workdir"))
print("Metrics:", metrics)
passed, failures = handler._check_qc_thresholds("KRAKEN2", metrics)
print("Passed:", passed)
print("Failures:", failures)
EOF
```

Expected: `classified_pct = 54.8`. WARNING tier fires (54.8% < 60%). CRITICAL tier does not fire (54.8% > 30%).

---

## Part 2: Cryo-EM Single-Particle Analysis

### 2.1 Pipeline stage routing

| Process name keywords | Parser called |
|---|---|
| `MOTION_CORRECTION` | `_parse_motion_correction_metrics` |
| `CTF_ESTIMATION`, `CTF_ESTIMATE` | `_parse_ctf_metrics` |
| `PARTICLE_PICKING`, `PICKING` | `_parse_picking_metrics` |
| `CLASSIFY_2D`, `CLASS_2D`, `2D_CLASSIFICATION`, `2DCLASSIFICATION` | `_parse_2d_classification_metrics` |
| `HOMOGENEOUS_REFINEMENT`, `NONUNIFORM_REFINEMENT`, `HETEROGENEOUS_REFINEMENT`, `VALIDATION_FSC`, `LOCAL_CTF_REFINEMENT`, `AB_INITIO` | `_parse_refinement_metrics` |
| `SHARPEN`, `CTF_REFINE_SHARPEN`, `POSTPROCESS`, `POSTPROCESSING` | `_parse_sharpening_metrics` |
| `LOCAL_RESOLUTION`, `LOCALRES`, `MONORES`, `RESMAP` | `_parse_local_resolution_metrics` |

---

### 2.2 Stage 1: Motion Correction

**Parser:** `_parse_motion_correction_metrics` (line 1001)

#### Output files read

| Glob | Tool | Line pattern |
|---|---|---|
| `*.log`, `*_motion.txt` | MotionCor2 / RELION Motioncorr | `"total motion"` or `"global drift"` → value in Å |

BioMate scans each line; if `"total motion"` or `"global drift"` is found (case-insensitive), it extracts the first parseable float in the range (0, 500) as `total_drift_angstrom`.

Derived metric: `drift_per_frame_angstrom = total_drift_angstrom / n_frames` (default n_frames = 40 if not present in log).

#### Gate logic

| Metric | Default threshold | Evidence | Operator | Message |
|---|---|---|---|---|
| `total_drift_angstrom` | 50 Å | [BRONZE] | `>` | `"Excessive drift: {val:.1f}Å (threshold: {t:.0f}Å)"` |
| `correlation_score` | 0.5 | [BRONZE] | `<` | `"Low correlation: {val:.3f} (threshold: {t:.1f})"` |

**Override:** `cryoem_spa_membrane` profile raises drift threshold to 80 Å; `cryoem_tomo_in_situ` profile raises it to 150 Å.

#### Near-threshold warning

| Metric | Warning range | Message |
|---|---|---|
| `total_drift_angstrom` | 40–50 Å | `"Beam-induced motion {val:.1f}Å is approaching the 50Å threshold — monitor for dose rate changes"` |

---

### 2.3 Stage 2: CTF Estimation

**Parser:** `_parse_ctf_metrics` (line 1052)

#### Output files read (priority order)

| Priority | File | Format | Fields used |
|---|---|---|---|
| 1 | `micrographs_ctf.cs` (CryoSPARC) | JSON array of micrograph objects | `defocus_u_angstroms`, `defocus_v_angstroms`, `astigmatism_angstroms`, `ctf_cross_correlation` (average over all micrographs) |
| 2 | `ctf_report.json` (SPA pipeline) | JSON summary | `avg_defocus_angstroms`, `avg_phase_shift_rad` (or `avg_phase_shift_degrees` × π/180) |
| 3 | `*.txt`, `*_ctf.log` (CTFFIND4 / Gctf) | Whitespace-separated, ≥5 columns | col[0]=DefocusU, col[1]=DefocusV, col[4]=FitScore |

**CryoSPARC `.cs` metric note:** `ctf_cross_correlation` (scale 0.05–0.20) is NOT the same as CTFFIND4 `fit_quality` (scale 0–1). They are stored under separate keys. No hard gate is applied to `ctf_cross_correlation` because the calibration threshold requires real CryoSPARC data (the CTFFIND4 0.70 gate cannot be extrapolated to CC scores).

**CTFFIND4 defocus validity range:** 1,000–100,000 Å. Lines outside this range are saved to `oor_fallback` with `defocus_out_of_range = True` and `defocus_direction = "below" | "above"`, allowing direction-aware failure messages.

#### Gate logic

| Metric | Default threshold | Evidence | Operator | Advisory | Message |
|---|---|---|---|---|---|
| `defocus_u_angstrom` (out-of-range: `below`) | 1,000 Å | [SILVER] | `<` | No | `"Estimated defocus {du:.0f}Å is near-focus (valid range 1,000–100,000Å). Consider collecting at 1.0–3.0 μm underfocus."` |
| `defocus_u_angstrom` (out-of-range: `above`) | 100,000 Å | [SILVER] | `>` | No | `"Estimated defocus {du:.0f}Å is too far from focus. Check for stage drift or incorrect microscope calibration."` |
| `astigmatism_angstrom` | 1,000 Å | [BRONZE] | `>` | **Yes** | `"Elevated astigmatism: {astig:.0f}Å (advisory). May indicate lens contamination or specimen charging."` |
| `fit_quality` | 0.70 | [SILVER] | `<` | No | `"Poor CTF fit: {fit:.3f} (threshold: {t:.1f})"` |
| `avg_phase_shift_rad` | < 0.20 rad | [BRONZE] | `<` | **Yes** | `"[BRONZE] Volta Phase Plate appears depleted: {ps:.3f} rad. Move to fresher VPP position."` |
| `avg_phase_shift_rad` | > 1.50 rad | [BRONZE] | `>` | **Yes** | `"[BRONZE] Volta Phase Plate is over-charged: {ps:.3f} rad. Advance to fresh VPP spot."` |

**Astigmatism is advisory:** No published consensus threshold; high-resolution structures (< 3 Å) have been deposited with astigmatism 500–2,000 Å. `fit_quality` is the primary CTF quality gate. Astigmatism is flagged [BRONZE] advisory so the operator is aware without blocking the workflow.

**VPP advisory:** Danev & Bharat 2018 (Trends Cell Biol) — optimal phase shift 0.4–0.8π (≈ 1.3–2.5 rad); productive VPP range 0.2–1.5 rad. Depleted (< 0.20 rad) or over-charged (> 1.50 rad) plates are advised, not blocked. Both fire only when `avg_phase_shift_rad` is present in metrics (i.e., `params.phase_plate = true`).

**Named profile `cryoem_spa_phase_plate`:** Relaxes `fit_quality` to 0.65 (VPP CTF fits have inherently lower CC scores due to phase plate scatter). Uses default VPP advisory thresholds.

#### Near-threshold warning — CTF

| Metric | Warning range | Message |
|---|---|---|
| `fit_quality` | 0.70–0.77 | `"CTF fit quality {val:.3f} is near the 0.70 threshold — monitor for deteriorating microscope conditions"` |
| `avg_phase_shift_rad` (approaching depleted) | 0.20–0.22 rad | `"VPP phase shift {val:.3f} rad is approaching depletion threshold (0.20 rad) — consider moving to next VPP position soon"` |
| `avg_phase_shift_rad` (approaching over-charged) | 1.35–1.50 rad | `"VPP phase shift {val:.3f} rad is approaching over-charge threshold (1.50 rad) — monitor closely"` |

---

### 2.4 Stage 3: Particle Picking

**Parser:** `_parse_picking_metrics` (line 1184)

#### Output files read

| Glob | Tool | Field |
|---|---|---|
| `*.star` | RELION / CryoSPARC STAR format | Non-header, non-comment lines starting with a digit = particle count |
| `*.box` | EMAN2 box file | Same line count logic |
| `*.coords` | crYOLO / generic | Same |

`particles_picked` = sum over all coordinate files; `particle_density_per_micrograph` = total / count of files with > 0 picks.

#### Gate logic

| Metric | Default threshold | Evidence | Operator | Message |
|---|---|---|---|---|
| `particles_picked` | 1,000 | [SILVER] | `<` | `"Too few particles: {val} (threshold: {t:.0f}). Check picker threshold and micrograph quality."` |
| `duplicate_fraction` | 0.20 | [BRONZE] | `>` | `"High duplicate fraction: {val:.1%} (threshold: {t:.0%})"` |

#### Near-threshold warnings

| Metric | Warning range | Message |
|---|---|---|
| `particles_picked` | 1,000–1,100 | `"Particle count {val} is near the 1,000 threshold — low pick counts affect ab initio diversity"` |

---

### 2.5 Stage 4: 2D Classification

**Parser:** `_parse_2d_classification_metrics` (line 1858)

#### Output files read

| File (tried in order) | Format | Fields used |
|---|---|---|
| `class2d_report.json` | JSON | `junk_class_fraction` (direct) OR `num_good_classes` / `num_classes` (derived) |
| `class2d_r1_report.json`, `class2d_r2_report.json` | JSON | Same |
| `class2d_metrics.json` | JSON | Same |

Derivation when explicit `junk_class_fraction` is absent:
```
junk_class_fraction = 1.0 - (num_good_classes / num_classes)
```

Additional informational metrics stored (non-gated): `num_particles`, `num_classes`, `num_good_classes`, `avg_resolution_angstroms`.

#### Gate logic

| Metric | Default threshold | Evidence | Operator | Advisory | Message |
|---|---|---|---|---|---|
| `junk_class_fraction` | 0.50 | [BRONZE] | `>` | **Yes** | `"[BRONZE] High junk class fraction: {val:.1%} of 2D classes are low-quality. Consider re-picking with stricter threshold or checking ice thickness."` |

The gate is advisory (non-blocking) because junk class fraction depends on picker aggressiveness and ice quality. At > 0.70, an escalated advisory message is produced (the same gate fires; the percentage in the message communicates severity).

**Community heuristic rationale:** No published consensus threshold for junk class fraction. The 50% advisory is based on the empirical observation that when fewer than half of classes are informative, ab initio reconstruction diversity is substantially impaired. Determined from internal analysis of EMPIAR benchmark datasets.

#### Near-threshold warning

| Metric | Warning range | Message |
|---|---|---|
| `junk_class_fraction` | 0.45–0.50 | `"Junk class fraction {val:.1%} is approaching the 0.50 advisory threshold"` |

---

### 2.6 Stage 5: Refinement (Homogeneous / Heterogeneous / Non-Uniform)

**Parser:** `_parse_refinement_metrics` (line 1910)

#### Output files read (priority order)

| Priority | Glob | Format | Fields used |
|---|---|---|---|
| 1 | `*_results.json`, `job.json`, `*.json` | JSON | `fsc_resolution_angstrom` / `FSC_resolution_A` / `resolution_A`; `junk_class_fraction` / `rejected_fraction` |
| 2 | `*fsc*.txt`, `*refinement*.txt`, `*.txt` | Text | `FSC_resolution: X.X` pattern |

#### Gate logic

| Metric | Default threshold | Evidence | Operator | Advisory | Message |
|---|---|---|---|---|---|
| `fsc_resolution_angstrom` | 10.0 Å | [GOLD] Henderson et al. 2012 | `>` | No | `"Poor reconstruction: FSC 0.143 resolution {val:.1f}Å (gate: better than {t:.0f}Å). Check particle count and 2D class selection."` |
| `junk_class_fraction` | 0.50 | [BRONZE] | `>` | **Yes** | `"High junk class fraction: {val:.1%} of particles in low-quality classes."` |

**Evidence — FSC gate:** Henderson et al. 2012 (Science 338:1033) gold-standard FSC 0.143 criterion; Scheres 2012 (J Struct Biol 180:519). Note: smaller Å = better resolution; the gate fires when `fsc_resolution > threshold` (i.e., resolution is coarser than 10 Å).

---

### 2.7 Stage 6: Sharpening (Post-processing)

**Parser:** `_parse_sharpening_metrics` (line 1984)

#### Output files read

| File (tried in order) | Format | Field aliases checked |
|---|---|---|
| `sharpening_report.json` | JSON | `bfactor_angstrom_squared`, `b_factor_applied`, `b_factor`, `bfactor`, `b_factor_angstrom2` |
| `sharpening_results.json` | JSON | Same aliases |
| `postprocessing_results.json`, `postprocess_report.json` | JSON | Same aliases |

The SPA pipeline writes `b_factor_applied`; legacy field names are supported for RELION post-processing output.

#### Gate logic

| Condition | Threshold | Evidence | Advisory | Message |
|---|---|---|---|---|
| `bfactor_angstrom_squared > 0` (positive / blurring) | 0 Å² | [BRONZE] | **Yes** | `"[BRONZE] Applied B-factor {val:.1f} Å² is positive (blurring). Expected: −50 to −200 Å². Check that correct half-maps were used."` |
| `bfactor_angstrom_squared < −300` (over-sharpened) | −300 Å² | [BRONZE] | **Yes** | `"[BRONZE] Applied B-factor {val:.1f} Å² is very large negative — over-sharpening may introduce artefacts. Typical: −50 to −200 Å² (Rosenthal & Henderson 2003)."` |

Both gates are advisory (non-blocking). **Rationale:** B-factor selection depends on map resolution and is partially subjective. Automated sharpening tools (e.g., DeepEMhancer, ModelAngelo) may legitimately apply unconventional values. The gates are informational sanity checks.

**Evidence:** Rosenthal & Henderson 2003 (J Mol Biol 333:721); Terwilliger et al. 2018 (Acta Cryst D74:545).

---

### 2.8 Stage 7: Local Resolution

**Parser:** `_parse_local_resolution_metrics` (line 2096)

#### Output files read

| File (tried in order) | Format | Field aliases checked |
|---|---|---|
| `local_resolution_report.json` | JSON | `std_resolution_angstroms`, `std_spread_angstrom`, `resolution_std`, `std_local_resolution` |
| `local_resolution_results.json` | JSON | Same |
| `localres_results.json`, `localres_report.json` | JSON | Same; also: `mean_resolution_angstroms` / `mean_resolution_angstrom` / `mean_local_resolution_angstrom` → `mean_local_resolution_angstrom` |

The SPA pipeline writes `std_resolution_angstroms` and `mean_resolution_angstroms` (note trailing `s`); legacy field names are supported for RELION LocalRes and ResMap output.

#### Gate logic

| Metric | Default threshold | Evidence | Operator | Advisory | Message |
|---|---|---|---|---|---|
| `std_spread_angstrom` | 3.0 Å | [BRONZE] | `>` | **Yes** | `"[BRONZE] Local resolution spread σ={val:.1f} Å (advisory: < {t:.1f} Å). High heterogeneity — consider 3D variability analysis or focused classification."` |

**Evidence:** Vilas et al. 2018 (Structure 26:337, MonoRes). σ > 3 Å indicates dominant flexible regions, conformational heterogeneity, or preferred orientation artefacts.

---

### 2.9 Cryo-EM named profiles summary

| Profile | Key overrides | Rationale |
|---|---|---|
| `cryoem_spa_purified` | (none) | Default for purified soluble protein complexes |
| `cryoem_spa_membrane` | `total_drift_angstrom` → 80 Å; `fit_quality` → 0.65 | Membrane proteins in micelles/nanodiscs: higher motion, weaker CTF signal |
| `cryoem_spa_phase_plate` | `fit_quality` → 0.65; `avg_phase_shift_rad_min` → 0.20; `avg_phase_shift_rad_max` → 1.50 | VPP: lower CTF fit quality expected; phase shift advisory gates activated |
| `cryoem_tomo_in_situ` | `total_drift_angstrom` → 150 Å; `fit_quality` → 0.50; `correlation_score` → 0.30 | FIB-SEM lamellae: high drift and low SNR are expected |

---

## 3. Mock Reproduction Guide

### 3a. CTF defocus out-of-range (near-focus direction)

```bash
cd /home/yzhang/biomate/backend

mkdir -p /tmp/test_ctf_workdir
cat > /tmp/test_ctf_workdir/sample_ctffind.txt << 'EOF'
 950.00  940.00  45.0  0.000  0.82
EOF

.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-cryoem-001",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="cryo_em"
)
metrics = handler._parse_ctf_metrics(Path("/tmp/test_ctf_workdir"))
print("Metrics:", metrics)
passed, failures = handler._check_qc_thresholds("CTF_ESTIMATION", metrics)
print("Passed:", passed)
print("Failures:", failures)
EOF
```

Expected: `defocus_u_angstrom = 950`, `defocus_out_of_range = True`, `defocus_direction = "below"`.
Gate message should contain `"near-focus"` and `"1.0–3.0 μm underfocus"`.

### 3b. 2D classification high junk fraction

```bash
mkdir -p /tmp/test_2d_workdir
cat > /tmp/test_2d_workdir/class2d_report.json << 'EOF'
{"num_classes": 50, "num_good_classes": 18, "num_particles": 250000}
EOF

.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-cryoem-002",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="cryo_em"
)
metrics = handler._parse_2d_classification_metrics(Path("/tmp/test_2d_workdir"))
print("Metrics:", metrics)
# junk_class_fraction = 1 - (18/50) = 0.64
passed, failures = handler._check_qc_thresholds("CLASSIFY_2D_R1", metrics)
print("Passed:", passed)
print("Failures:", failures)
EOF
```

Expected: `junk_class_fraction = 0.64`, advisory gate fires (`advisory: True`); `passed = True` because only advisory items were emitted.

### 3c. Sharpening over-sharpened B-factor

```bash
mkdir -p /tmp/test_sharpen_workdir
cat > /tmp/test_sharpen_workdir/sharpening_report.json << 'EOF'
{"b_factor_applied": -350.0, "fsc_resolution_angstrom": 3.2}
EOF

.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-cryoem-003",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="cryo_em"
)
metrics = handler._parse_sharpening_metrics(Path("/tmp/test_sharpen_workdir"))
print("Metrics:", metrics)
passed, failures = handler._check_qc_thresholds("SHARPEN", metrics)
print("Passed:", passed)  # True — advisory only
print("Failures:", failures)  # advisory=True item present
EOF
```

Expected: `bfactor_angstrom_squared = -350.0`, advisory gate fires, `passed = True`.

---

## 4. Example SSE Events

### Metagenomics — two-tier classification failure

```json
{
  "event_type": "qc_gate_triggered",
  "invocation_id": "inv-meta-001",
  "process_name": "KRAKEN2",
  "timestamp": "2026-03-04T17:00:00Z",
  "qc_metrics": {"classified_pct": 22.4},
  "failures": [
    {
      "metric": "classified_pct",
      "value": 22.4,
      "threshold": 30.0,
      "operator": "<",
      "severity": "critical",
      "message": "Critically low classification: 22.4% (threshold: 30%). Contamination, wrong database, or highly divergent organisms."
    }
  ],
  "suggestions": [
    {
      "parameter": "kraken2_db",
      "currentValue": "minikraken",
      "suggestedValue": "standard_8gb",
      "reason": "Upgrade to Standard 8 GB database for broader taxonomic coverage.",
      "confidence": 0.85,
      "source": "rule"
    }
  ],
  "active_profile": null,
  "active_overrides": {}
}
```

### Cryo-EM CTF — Volta Phase Plate over-charged (BRONZE advisory)

```json
{
  "event_type": "qc_warning",
  "invocation_id": "inv-cryoem-001",
  "process_name": "CTF_ESTIMATION",
  "timestamp": "2026-03-04T17:05:00Z",
  "qc_metrics": {
    "defocus_u_angstrom": 6200,
    "fit_quality": 0.81,
    "avg_phase_shift_rad": 1.72
  },
  "warnings": [
    {
      "metric": "avg_phase_shift_rad",
      "value": 1.72,
      "threshold": 1.5,
      "operator": ">",
      "advisory": true,
      "message": "[BRONZE] Volta Phase Plate is over-charged: avg phase shift 1.720 rad > 1.50 rad advisory maximum. Advance to a fresh VPP spot."
    }
  ]
}
```

### Cryo-EM sharpening — B-factor advisory (continues without blocking)

```json
{
  "event_type": "qc_warning",
  "invocation_id": "inv-cryoem-002",
  "process_name": "SHARPEN",
  "timestamp": "2026-03-04T17:10:00Z",
  "qc_metrics": {"bfactor_angstrom_squared": -350.0},
  "warnings": [
    {
      "metric": "bfactor_angstrom_squared",
      "value": -350.0,
      "threshold": -300,
      "operator": "<",
      "advisory": true,
      "message": "[BRONZE] Applied B-factor -350.0 Å² is very large negative — over-sharpening may introduce map artefacts. Typical range: −50 to −200 Å² (Rosenthal & Henderson 2003)."
    }
  ]
}
```

---

## 5. Test Coverage

| Test class | File | What it covers |
|---|---|---|
| `TestMetagenomicsQCDomain` | `test_qc_e2e_domains.py` | Kraken2 classification gate, two-tier critical/warning, soil/marine profile |
| `TestPriyaCryoEM_P1Gates` | `test_qc_edge_cases.py` | 2D classification junk fraction (advisory), ice thickness (advisory), preferred orientation |
| `TestPriyaCryoEM_P2Gates` | `test_qc_edge_cases.py` | B-factor/Guinier advisory gates, local resolution std spread advisory |
| `TestCryoEMNearThresholdWarnings` | `test_qc_edge_cases.py` | Motion drift near-threshold (40–50 Å), CTF fit_quality near-threshold, particle count near-threshold, 2D junk near-threshold |
| `TestPriyaCryoEM_PhasePlate` | `test_qc_edge_cases.py` | VPP phase shift advisory gates, degree-to-radian conversion, near-threshold 0.20–0.22 rad and 1.35–1.50 rad, `cryoem_spa_phase_plate` profile |
| `TestTierOneChanges` | `test_qc_edge_cases.py` | CTF defocus out-of-range directional gate (below 1,000 Å and above 100,000 Å) |
| `TestNamedProfiles` | `test_qc_edge_cases.py` | `cryoem_spa_membrane` drift threshold, `cryoem_tomo_in_situ` thresholds |
