# Supplementary S7 — Single-Cell RNA-seq and ATAC-seq QC Implementation
**Paper:** BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale
**Module:** `backend/lib/galaxy/jobs/qc_trace_monitor.py`
**Suggester:** `backend/lib/galaxy/jobs/parameter_suggester.py` → `SingleCellParameterSuggester`, `ChIPSeqParameterSuggester`
**Test classes:** `TestSingleCellQCDomain`, `TestATACSeqQCDomain` (in `tests/test_qc_e2e_domains.py`); `TestPaper1P0Fixes`, `TestAuditFindings` (in `tests/test_qc_edge_cases.py`)

---

## Overview

This supplement covers two epigenomics-adjacent domains:

1. **Single-cell RNA-seq (scRNA-seq):** BioMate parses CellRanger / STARsolo output to check cell yield, gene complexity, and mitochondrial contamination. Two tissue-specific named profiles (`scrna_cardiac`, `scrna_neuronal`) relax the mitochondrial gate based on published cell atlas data. A perturbation screen profile (`scrna_perturbation`) adds guide library coverage and doublet detection gates.

2. **ATAC-seq / ChIP-seq:** BioMate enforces the full ENCODE4 ATAC-seq standard: TSS enrichment (GOLD gate), NRF / PCR Bottleneck Coefficient (GOLD gate), and FRiP (advisory non-blocking). Peak calling (MACS2/3) applies a minimal peak count gate. All three core ATAC-seq metrics are GOLD tier; they cannot be relaxed by `qc_overrides`.

---

## Part 1: Single-Cell RNA-seq

### 1.1 Process name routing

| Keyword | Tool |
|---|---|
| `CELLRANGER_COUNT`, `CELLRANGER` | 10x Genomics Cell Ranger |
| `STARSOLO` | STARsolo (nf-core/scrnaseq) |
| `ALEVIN` | Salmon Alevin |

### 1.2 Output files read

Parser: `_parse_singlecell_metrics` (line 1597)

| Priority | Glob | Format | Tool |
|---|---|---|---|
| 1 | `metrics_summary.csv` (current dir + `outs/`) | Comma-separated key-value | Cell Ranger v7+ |
| 2 | `Summary.csv` | Tab-separated | STARsolo |
| 3 | `*.csv` (fallback) | Auto-detect | Any |

**CellRanger `metrics_summary.csv` fields used:**

| CSV column header | Metric name | Processing |
|---|---|---|
| `Estimated Number of Cells` | `cells_detected` | Strip commas, parse int |
| `Median Genes per Cell` | `median_genes_per_cell` | Strip commas, parse int |
| `Reads Mapped to Genome` | `mapping_rate` | Strip `%`, parse float |
| `Sequencing Saturation` | `sequencing_saturation_pct` | Strip `%`, parse float |
| `Mitochondrial Reads` (variant spellings) | `mito_fraction_pct` | Strip `%`; if value < 1.0, multiply × 100 (0–1 → %) |

**Mitochondrial fraction normalisation:** CellRanger v5 and earlier report as 0–1 fraction; v7 reports as percentage. The parser checks: if the parsed float is ≤ 1.0, it is assumed to be a fraction and multiplied by 100.

### 1.3 Gate logic

| Metric | Default threshold | Evidence | Operator | Message |
|---|---|---|---|---|
| `cells_detected` | 200 | [SILVER] | `<` | `"Too few cells: {val} (minimum: {t:.0f}). Check input cell count and capture efficiency."` |
| `median_genes_per_cell` | 500 | [SILVER] | `<` | `"Low gene complexity: {val} genes/cell (threshold: {t:.0f}). May indicate low-quality cells or over-filtering."` |
| `mito_fraction_pct` | 20.0% | [BRONZE] | `>` | `"High mitochondrial fraction: {val:.1f}% (threshold: {t:.0f}%). Likely dead/damaged cells."` |
| `sequencing_saturation_pct` | 30.0% | [BRONZE] advisory | `<` | `"Low sequencing saturation: {val:.1f}% (threshold: {t:.0f}%). Consider deeper sequencing."` |

**Evidence — cells detected:** 200 cells is a conservative floor; even pilot captures with 10x Chromium should yield > 1,000 cells. Below 200 usually indicates a failed capture or filter file mixup.

**Evidence — median genes:** Luecken & Theis 2019 (Mol Syst Biol 15:e8746) established 500 median genes as the lower bound for interpretable cluster analysis. Immune lineages (e.g., neutrophils) routinely achieve 1,000–3,000 median genes.

**Evidence — mito fraction:** Luecken & Theis 2019; Osorio & Cai 2021 (Front Genet 12:799726). 20% is the canonical threshold for PBMC and epithelial cells. This is [BRONZE] because the biologically correct threshold is highly tissue-dependent (see profiles §1.5).

**Evidence — sequencing saturation:** 10x Genomics Cell Ranger documentation. Below 30% saturation, gene detection is strongly depth-limited and additional sequencing is warranted. This is advisory (non-blocking) because saturation is a resource decision, not a sample quality failure.

### 1.4 Near-threshold warnings

| Metric | Warning range | Message |
|---|---|---|
| `mito_fraction_pct` | 10–20% | `"Mitochondrial fraction {val:.1f}% is elevated — approaching the 20% threshold. In cardiac or neuronal samples, consider switching to the scrna_cardiac or scrna_neuronal profile."` |

The 10% near-threshold advisory fires even when no profile override is active, specifically prompting the user to consider tissue-appropriate profiles. This prevents silent misclassification of biologically normal high-mito cells.

### 1.5 Named profile overrides

| Profile | `mito_fraction_pct` | `mito_fraction_pct_warning` | `median_genes_per_cell` | Rationale |
|---|---|---|---|---|
| `scrna_standard` | 20.0 (default) | — | — | — |
| `scrna_cardiac` | 40.0 | 25.0 | — | Cardiomyocytes are mitochondria-rich; 30–40% mito is biologically normal. Simonson et al. 2023 Circ Res; Kuppe et al. 2022 Nature |
| `scrna_neuronal` | 30.0 | 20.0 | 300 | Neurons have elevated mitochondrial content; inhibitory interneurons have narrow transcriptomes (Allen Brain Atlas). Warning moves to 20% (original hard gate) |
| `scrna_perturbation` | 20.0 (default) | — | — | Adds: `guide_library_coverage_pct` ≥ 70%, `transfection_efficiency_pct` ≥ 30%, `max_doublet_fraction_pct` ≤ 10% (Replogle et al. 2022 Cell) |

### 1.6 Parameter suggestions

Triggered by `SingleCellParameterSuggester` when QC gates fire:

| Process | Gate metric | Suggestion | Confidence | Source |
|---|---|---|---|---|
| CELLRANGER | `cells_detected < 200` | Verify cell input concentration; re-capture if < 500 cells/µL estimated | advisory | rule |
| CELLRANGER | `mito_fraction_pct > 20` | Filter cells: `mito_pct_cutoff` → `current` or activate scrna_cardiac/neuronal profile | 0.75 | rule |
| CELLRANGER | `median_genes_per_cell < 500` | Increase sequencing depth; check if correct species reference used | 0.70 | rule |
| CELLRANGER | `sequencing_saturation_pct < 30` | `target_reads_per_cell` → increase by 2× | 0.80 | 10x docs |

---

## Part 2: ATAC-seq and ChIP-seq

### 2.1 Process name routing

| Keyword | Tool | Parser |
|---|---|---|
| `ATAC_QC`, `TSS_ENRICH`, `ATAC_PEAK`, `DEEPTOOLS_PLOTFINGERPRINT`, `PLOTFINGERPRINT` | deepTools / ENCODE ATAC pipeline | `_parse_atac_metrics` |
| `MACS2`, `MACS3`, `CALLPEAK` | MACS2 / MACS3 | `_parse_peakcalling_metrics` |

### 2.2 Output files read — ATAC_QC

Parser: `_parse_atac_metrics` (line 1748)

**TSS enrichment (priority 1):**

| Glob | Format | Field |
|---|---|---|
| `tss_enrich.txt`, `*.tss.txt`, `*tss_enrichment*` | Plain text, one float per line | First parseable float value |

Written by nf-core/atacseq `ATAC_QC` process or ENCODE ATAC pipeline.

**NRF / PBC (priority 2):**

| Glob | Format | Column |
|---|---|---|
| `*.pbc.txt`, `*pbc*` | Tab-separated, 7+ columns | Column index 4 (NRF = DistinctReadPairs / TotalReadPairs) |

nf-core/atacseq `pbc.txt` format (7 columns):
```
TotalReadPairs  DistinctReadPairs  OneReadPair  TwoReadPairs  NRF    PBC1   PBC2
45231048         42318211           39821029      2497182      0.935  0.941  17.0
```
BioMate reads column index 4 as `nrf_score`.

**FRiP score (priority 3):**

| Glob | Format | Field |
|---|---|---|
| `*frip_score*`, `*frip*` | Plain text, one float per line | First parseable float |

### 2.3 Gate logic — ATAC_QC

All three ATAC-seq metrics are GOLD tier (ENCODE4 mandate):

| Metric | Default threshold | Evidence | Operator | Blocking | Message |
|---|---|---|---|---|---|
| `tss_enrichment` | 5.0 | [GOLD] ENCODE4 2022 | `<` | Yes | `"Low TSS enrichment: {val:.2f} (threshold: {t:.1f}). ENCODE4: ≥7 high quality, ≥5 acceptable."` |
| `nrf_score` | 0.9 | [GOLD] ENCODE4 2022 | `<` | Yes | `"Low NRF: {val:.3f} (threshold: {t:.1f}). NRF < 0.7 indicates severe PCR over-amplification."` |
| `frip_score` | 0.2 | [GOLD] ENCODE4 2022 | `<` | Yes | `"Low FRiP: {val:.3f} (threshold: {t:.1f}). ENCODE4 minimum FRiP for ATAC-seq is 0.2."` |

**Note on GOLD / override:** `tss_enrichment` and `nrf_score` are in `QC_GOLD_METRICS` (line 53). The `frip_score` gate uses the ENCODE4 minimum (0.2) but is also effectively protected because FRiP below 0.2 is definitionally invalid for ATAC-seq.

**Evidence — TSS enrichment:** ENCODE ATAC-seq Standards v2 (2022). TSS ≥ 7 is "high quality"; TSS 5–7 is "acceptable". Below 5 is insufficient for confident peak calls.

**Evidence — NRF:** ENCODE4 Consortium. NRF = distinct read pairs / total read pairs. Values < 0.7 indicate that the library was substantially over-amplified and nucleosome-free regions may be dominated by PCR duplicates. Values 0.7–0.9 are borderline.

**Evidence — FRiP:** ENCODE4 ATAC-seq pipeline documentation. Fraction of reads in peaks ≥ 0.2 is the ENCODE4 minimum acceptable threshold for ATAC-seq (vs. 0.01/0.1 for TF/histone ChIP-seq respectively).

### 2.4 Near-threshold warnings — ATAC_QC

| Metric | Warning range | Message |
|---|---|---|
| `tss_enrichment` | 5.0–5.5 | `"TSS enrichment {val:.2f} is near the 5.0 ENCODE4 minimum — monitor closely"` |
| `nrf_score` | 0.9–0.99 | `"NRF {val:.3f} is near the 0.9 ENCODE4 threshold — some PCR over-amplification may be present"` |

### 2.5 Output files read — MACS2/3

Parser: `_parse_peakcalling_metrics` (line 1700)

| Priority | Glob | Format | Metric extracted |
|---|---|---|---|
| 1 | `*_peaks.narrowPeak`, `*_peaks.broadPeak`, `*_summits.bed` | BED | Line count = `peaks_called` |
| 2 | `*.log` (MACS2 log) | Text | `"total tags after filtering: (\d+)"` → `tags_after_filtering` |
| 3 | `*frip_score*`, `*frip*` | Text | `frip_score` |

### 2.6 Gate logic — MACS2/3

| Metric | Default threshold | Evidence | Blocking | Message |
|---|---|---|---|---|
| `peaks_called` | 1,000 | [SILVER] | Yes | `"Too few peaks called: {val} (threshold: {t:.0f}). Library may lack open chromatin signal."` |
| `frip_score` | 0.01 | [BRONZE] advisory | No | `"Low FRiP from peak calling: {val:.3f} (ENCODE advisory). TF ChIP: ≥0.01; histone marks: ≥0.1."` |

**Evidence — FRiP from MACS2:** Landt et al. 2012 ENCODE2/3 guidelines. ENCODE4 explicitly does not define a hard FRiP threshold; the 0.01 gate is therefore [BRONZE] advisory and non-blocking. FRiP from MACS2 is informational alongside the ATAC_QC FRiP gate.

### 2.7 Parameter suggestions

Triggered by `ChIPSeqParameterSuggester`:

| Process | Gate metric | Suggestion | Confidence | Source |
|---|---|---|---|---|
| ATAC_QC | `tss_enrichment < 5` | Check adapter contamination; verify Tn5 transposase efficiency | advisory | rule |
| ATAC_QC | `nrf_score < 0.9` | Reduce PCR cycles (current → current − 2); consider re-library-prep with less input DNA | 0.75 | ENCODE4 |
| MACS2 | `peaks_called < 1000` | Lower `--qvalue` threshold; confirm open chromatin input (ATAC, not ChIP) | 0.70 | rule |

---

## 3. Mock Reproduction Guide

### 3a. scRNA-seq CellRanger mock

```bash
cd /home/yzhang/biomate/backend

mkdir -p /tmp/test_cellranger_workdir/outs
cat > /tmp/test_cellranger_workdir/outs/metrics_summary.csv << 'EOF'
Estimated Number of Cells,Median Genes per Cell,Reads Mapped to Genome,Sequencing Saturation,Mitochondrial Reads
1243,"2,847",92.3%,78.4%,28.5%
EOF

.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-scrna-001",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="scrna_seq"
)
metrics = handler._parse_singlecell_metrics(Path("/tmp/test_cellranger_workdir"))
print("Metrics:", metrics)
passed, failures = handler._check_qc_thresholds("CELLRANGER_COUNT", metrics)
print("Passed:", passed)
print("Failures:", failures)
EOF
```

Expected: `mito_fraction_pct = 28.5`, gate fires because 28.5% > 20.0%.

### 3b. ATAC-seq NRF mock

```bash
mkdir -p /tmp/test_atac_workdir
printf "TotalReadPairs\tDistinctReadPairs\tOneReadPair\tTwoReadPairs\tNRF\tPBC1\tPBC2\n" \
    > /tmp/test_atac_workdir/sample.pbc.txt
printf "45231048\t30912211\t28321029\t2491182\t0.683\t0.703\t12.1\n" \
    >> /tmp/test_atac_workdir/sample.pbc.txt

.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-atac-001",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="atac_seq"
)
metrics = handler._parse_atac_metrics(Path("/tmp/test_atac_workdir"))
print("Metrics:", metrics)
passed, failures = handler._check_qc_thresholds("ATAC_QC", metrics)
print("Passed:", passed)
print("Failures:", failures)
EOF
```

Expected: `nrf_score = 0.683`, GOLD gate fires because 0.683 < 0.9. Override attempt via `qc_overrides={"nrf_score": 0.5}` should be silently rejected (GOLD metric).

---

## 4. Example SSE Events

### scRNA-seq mito gate (BRONZE, blocking)

```json
{
  "event_type": "qc_gate_triggered",
  "invocation_id": "inv-scrna-001",
  "process_name": "CELLRANGER_COUNT",
  "timestamp": "2026-03-04T16:00:00Z",
  "qc_metrics": {
    "cells_detected": 1243,
    "median_genes_per_cell": 2847,
    "mito_fraction_pct": 28.5,
    "sequencing_saturation_pct": 78.4
  },
  "failures": [
    {
      "metric": "mito_fraction_pct",
      "value": 28.5,
      "threshold": 20.0,
      "operator": ">",
      "message": "High mitochondrial fraction: 28.5% (threshold: 20%). Likely dead/damaged cells."
    }
  ],
  "suggestions": [
    {
      "parameter": "mito_pct_cutoff",
      "currentValue": 20,
      "suggestedValue": 20,
      "reason": "Consider switching to scrna_cardiac or scrna_neuronal profile if tissue is mitochondria-rich.",
      "confidence": 0.75,
      "source": "rule"
    }
  ],
  "active_profile": null,
  "active_overrides": {}
}
```

### ATAC-seq near-threshold warning (qc_warning, non-blocking)

```json
{
  "event_type": "qc_warning",
  "invocation_id": "inv-atac-001",
  "process_name": "ATAC_QC",
  "timestamp": "2026-03-04T16:05:00Z",
  "qc_metrics": {
    "tss_enrichment": 5.3,
    "nrf_score": 0.944,
    "frip_score": 0.31
  },
  "warnings": [
    {
      "metric": "tss_enrichment",
      "value": 5.3,
      "threshold": 5.0,
      "operator": "<",
      "severity": "near_threshold",
      "message": "TSS enrichment 5.3 is near the 5.0 ENCODE4 minimum — monitor closely"
    }
  ]
}
```

---

## 5. Test Coverage

| Test class | File | What it covers |
|---|---|---|
| `TestSingleCellQCDomain` | `test_qc_e2e_domains.py` | CellRanger metrics parse, mito gate, median-genes gate |
| `TestATACSeqQCDomain` | `test_qc_e2e_domains.py` | TSS enrichment GOLD gate, NRF GOLD gate, FRiP advisory |
| `TestPaper1P0Fixes` | `test_qc_edge_cases.py` | CellRanger saturation advisory gate, TSS/NRF near-threshold warnings |
| `TestAuditFindings` | `test_qc_edge_cases.py` | NRF falsy-value bug fix (0.0 is falsy; gate now uses `"nrf_score" in metrics`) |
| `TestRound2AuditFindings` | `test_qc_edge_cases.py` | GOLD-metric override rejection (NRF and TSS cannot be overridden) |
| `TestNamedProfiles` | `test_qc_edge_cases.py` | scrna_cardiac (40% mito), scrna_neuronal (30% mito + 300 genes), scrna_perturbation |
