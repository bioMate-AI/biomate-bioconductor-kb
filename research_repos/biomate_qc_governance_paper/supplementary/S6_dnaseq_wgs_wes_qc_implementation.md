# Supplementary S6 — DNA-seq / WGS / WES QC Implementation
**Paper:** BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale
**Module:** `backend/lib/galaxy/jobs/qc_trace_monitor.py`
**Suggester:** `backend/lib/galaxy/jobs/parameter_suggester.py` → `GenomicsParameterSuggester`
**Test classes:** `TestDNASeqDomain`, `TestCoverageGates`, `TestDuplicationGates` (in `tests/test_qc_e2e_domains.py`)

---

## Overview

BioMate monitors three stages of a DNA-seq / WGS / WES pipeline: alignment (BWA-MEM), duplicate marking (Picard), and coverage depth (mosdepth or Picard WGS metrics). Coverage thresholds are protocol-specific: WGS germline uses 30×, WES clinical uses 80×, low-pass uses 4×, and somatic tumour-only uses 80×. Domain is inferred from the Nextflow workflow `params.domain` field or the workflow file path.

---

## 1. Read Alignment (BWA-MEM)

### 1.1 Process name routing

| Keyword | Tool |
|---|---|
| `BWA_MEM`, `BWA_MEM2`, `BWAMEM` | BWA-MEM / BWA-MEM2 |
| `FLAGSTAT`, `SAMTOOLS_FLAGSTAT`, `SAMTOOLS_STATS` | SAMtools (post-alignment stats) |

BWA-MEM shares the same parser as RNA-seq aligners (`_parse_alignment_metrics`) — both read an alignment rate from log output. The same 70% gate and 25% critical sub-tier apply.

### 1.2 Output files read

| Glob | Format | Tool |
|---|---|---|
| `*.flagstat`, `*.txt` | SAMtools flagstat text | SAMtools |
| `*Log.final.out` | STAR-format (BWA doesn't produce this natively) | — |

**SAMtools flagstat format (regex):**

| Pattern | Metric |
|---|---|
| `(\d+) \+ \d+ mapped \((\d+\.\d+)%` | `mapped_pct` → used as `alignment_rate` |
| `(\d+) \+ \d+ in total` | `total_reads` |
| `(\d+) \+ \d+ duplicates` | `duplicate_pct` (duplicates / total) |

### 1.3 Gate logic

Identical to RNA-seq alignment gate (see Supplement S5 §2.3). The 70% threshold and 25% critical sub-tier apply. For BWA-MEM, BWA-MEM2 is expected to achieve > 95% on clean human samples; 70% is a conservative floor.

---

## 2. Duplicate Marking

### 2.1 Process name routing

| Keywords |
|---|
| `MARKDUPLICATES`, `PICARD_MARKDUP`, `MARKDUP`, `GATK_MARKDUP` |

### 2.2 Domain-aware skip logic

The gate fires **only** for DNA-seq domains. It is suppressed for:

```
rna_seq, rnaseq, rna, scrna_seq, scrna, single_cell,
atac_seq, atacseq, chip_seq, chipseq, cut_and_run,
cutandrun, hic, hic_seq, hi_c
```

Rationale: RNA-seq duplicates arise from finite mRNA molecule amplification and are not indicative of library quality in the same way as DNA-seq duplicates. HiC libraries are also excluded (spatial proximity ligation creates non-random duplication patterns that do not indicate library quality problems).

### 2.3 Output files read

| Glob | Format | Column |
|---|---|---|
| `*.metrics`, `*.dup_metrics`, `*.txt` | Picard text table | `PERCENT_DUPLICATION` (column 9 of the metrics table header row) |

**Picard MarkDuplicates metrics format:**
```
## METRICS CLASS	picard.sam.DuplicationMetrics
LIBRARY	UNPAIRED_READS_EXAMINED	...	PERCENT_DUPLICATION	ESTIMATED_LIBRARY_SIZE
lib1	45231048	...	0.2341	...
```
BioMate reads the `PERCENT_DUPLICATION` column and multiplies by 100 to produce `duplicate_pct`.

### 2.4 Gate logic

| Metric | Default threshold | Evidence | Operator | Message |
|---|---|---|---|---|
| `duplicate_pct` | 40.0% | [SILVER] | `>` | `"High duplication: {val:.1f}% (threshold: {t:.0f}%). Indicates over-amplification or low library complexity."` |

**Evidence:** GATK Best Practices; nf-core/sarek. 40% is the commonly cited threshold above which variant calling accuracy begins to degrade meaningfully.

### 2.5 Named profile overrides

| Profile | `duplicate_pct` | Rationale |
|---|---|---|
| `wgs_germline_standard` | 40.0 (default) | — |
| `wgs_germline_lowpass` | 60.0 | Low-pass (1–5×) requires higher input; PCR duplicates tolerated if molecule count low (Rubinacci et al. 2021) |
| `wgs_somatic_tumor_only` | 50.0 | Tumour DNA often from FFPE; higher duplication accepted; deep coverage compensates |
| `wgs_ffpe` | 65.0 | FFPE DNA is highly fragmented; PCR amplification required for library prep |
| `wes_research` | 40.0 (default) | — |
| `wes_clinical_germline` | 30.0 | Clinical diagnostic threshold more stringent |

---

## 3. Coverage Depth

### 3.1 Process name routing

| Keywords | Tool |
|---|---|
| `MOSDEPTH` | mosdepth |
| `SAMTOOLS_COVERAGE` | samtools coverage |
| `GATK_COVERAGE` | GATK CollectWgsMetrics |
| `PICARD_WGS` | Picard CollectWgsMetrics |

### 3.2 Output files read

Parser: `_parse_coverage_metrics`

| Priority | Glob | Format | Field |
|---|---|---|---|
| 1 | `*.mosdepth.summary.txt`, `*summary.txt` | mosdepth TSV | Column 3 of the `total` or `genome` row |
| 2 | `*.wgs_metrics`, `*wgs_metrics.txt` | Picard text | `MEAN_COVERAGE` column |

**mosdepth summary format:**
```
chrom  length    bases     mean     min   max
total  3099441038  93012031140  30.01   0    9876
```
BioMate reads the `total` row and uses column index 3 (`mean`) as `mean_coverage`.

**Picard CollectWgsMetrics format:**
```
## METRICS CLASS	picard.analysis.WgsMetrics
GENOME_TERRITORY  MEAN_COVERAGE  MEDIAN_COVERAGE  ...
3049315783        31.423456      ...
```
BioMate reads `MEAN_COVERAGE` from the first data row.

### 3.3 Gate logic with domain-aware threshold selection

Coverage thresholds are **automatically selected** based on the inferred domain:

| Domain string(s) | Threshold | Evidence | Rationale |
|---|---|---|---|
| `wes`, `whole_exome`, `exome_seq`, `exome`, `targeted_seq` | 80× | [GOLD] ACMG 2016 | Clinical WES requires 80× for high-confidence variant calling |
| `wgs_somatic_tumor_only`, `wgs_somatic_tumor_normal` | 80× | [GOLD] GATK Mutect2 | Somatic variant calling requires high depth for sensitivity |
| `wgs_germline_lowpass` | 4× | [SILVER] | Low-pass imputation pipelines (GLIMPSE/SHAPEIT) are designed for 1–5× |
| All other WGS | 30× | [GOLD] GATK Best Practices | Standard germline WGS; 30× is the widely adopted minimum for GATK |

Gate message:
```
"Coverage {val:.1f}× is below the {t:.0f}× threshold for {domain} (GATK Best Practices)"
```

### 3.4 Near-threshold warnings

| Domain | Warning range |
|---|---|
| WGS (30×) | 30–33× |
| WES (80×) | 80–88× |

### 3.5 Named profile overrides

| Profile | `mean_coverage` | Rationale |
|---|---|---|
| `wgs_germline_standard` | 30.0 | GATK Best Practices |
| `wgs_germline_lowpass` | 4.0 | Low-pass imputation |
| `wgs_somatic_tumor_only` | 80.0 | Mutect2 sensitivity |
| `wgs_ffpe` | 30.0 | FFPE coverage often uneven; 30× minimum maintained |
| `wes_research` | 50.0 | Research-grade WES |
| `wes_clinical_germline` | 80.0 | Clinical diagnostic standard (ACMG 2016) |

### 3.6 Parameter suggestions

Triggered when `mean_coverage` is below threshold (GenomicsParameterSuggester):

| Condition | Parameter | Suggested | Confidence | Source |
|---|---|---|---|---|
| Coverage < threshold | `sequencing_depth` | (advisory: increase input) | 0.80 | rule |
| Low coverage + high duplication | `pcr_cycles` | `current → current - 2` | 0.70 | rule |

---

## 4. Mock Reproduction Guide

```bash
cd /home/yzhang/biomate/backend

# Create mock mosdepth summary (coverage = 18×, below WGS 30× gate)
mkdir -p /tmp/test_coverage_workdir
cat > /tmp/test_coverage_workdir/sample.mosdepth.summary.txt << 'EOF'
chrom	length	bases	mean	min	max
chr1	248956422	4480215596	18.0	0	312
total	3099441038	55789938684	18.0	0	312
EOF

.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-wgs-001",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock(),
    workflow_domain="wgs_germline"
)
metrics = handler._parse_coverage_metrics(Path("/tmp/test_coverage_workdir"))
print("Metrics:", metrics)
passed, failures = handler._check_qc_thresholds("MOSDEPTH", metrics)
print("Passed:", passed)
print("Failures:", failures)
EOF
```

Expected: `mean_coverage = 18.0`, gate fires with threshold 30.0.

---

## 5. Example SSE Events

### Coverage gate (GOLD)

```json
{
  "event_type": "qc_gate_triggered",
  "invocation_id": "inv-wgs-001",
  "process_name": "MOSDEPTH",
  "timestamp": "2026-03-04T15:10:22Z",
  "qc_metrics": {"mean_coverage": 18.0},
  "failures": [
    {
      "metric": "mean_coverage",
      "value": 18.0,
      "threshold": 30.0,
      "operator": "<",
      "message": "Coverage 18.0× is below the 30× threshold for wgs_germline (GATK Best Practices)"
    }
  ],
  "suggestions": [],
  "active_profile": "wgs_germline_standard",
  "active_overrides": {}
}
```

---

## 6. Test Coverage

| Test class | File | What it covers |
|---|---|---|
| `TestDNASeqDomain` | `test_qc_e2e_domains.py` | Coverage gate, duplication gate, domain-aware threshold selection |
| `TestWESCoverageGate` | `test_qc_edge_cases.py` | 80× WES vs 30× WGS auto-select |
| `TestMarkDuplicatesSkipDomains` | `test_qc_edge_cases.py` | Hi-C false-positive suppression |
| `TestPaper1P0Fixes` | `test_qc_edge_cases.py` | Near-threshold warnings for coverage (30–33×) |
