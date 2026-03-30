# Supplementary S5 — RNA-seq QC Implementation
**Paper:** BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale
**Module:** `backend/lib/galaxy/jobs/qc_trace_monitor.py`
**Suggester:** `backend/lib/galaxy/jobs/parameter_suggester.py` → `RNASeqParameterSuggester`
**Test classes:** `TestRNASeqDomain`, `TestTrimming`, `TestAlignment`, `TestQuantification` (in `tests/test_qc_e2e_domains.py`)

---

## Overview

BioMate monitors four sequential stages of an RNA-seq workflow: read trimming, read alignment, transcript/gene quantification, and (optionally) duplication. Metrics are parsed from the standard output files of the most common tools at each stage. Each stage has at least one SILVER-tier gate; alignment has a two-tier critical/warning split. Thirteen named profiles adjust thresholds for degraded, specialised, or non-model-organism samples.

---

## 1. Read Trimming

### 1.1 Process name routing

The following process names route to the trimming parser (substring match, case-insensitive):

| Keyword | Common tool |
|---|---|
| `FASTP` | fastp |
| `TRIMGALORE` | Trim Galore! |
| `TRIMMOMATIC` | Trimmomatic |
| `BBDUK` | BBDuk |

### 1.2 Output files read

The parser (`_parse_trimming_metrics`) searches `task_work_dir` recursively in this priority order:

| Priority | Glob pattern | Format | Tool |
|---|---|---|---|
| 1 | `*.json` | JSON | fastp |
| 2 | `*.log` | Text | Trim Galore / Trimmomatic |
| 3 | `*.txt` | Text | Trimmomatic summary |

**fastp JSON fields used:**

| JSON path | Metric name | Unit |
|---|---|---|
| `summary.after_filtering.read1_mean_length` | — (length check) | bp |
| `filtering_result.passed_filter_reads` / `summary.before_filtering.total_reads` | `reads_surviving_pct` | % |
| `summary.after_filtering.q30_rate` × 100 | `q30_pct` | % |
| `summary.before_filtering.total_reads` | `total_reads_in` | count |

**Trim Galore / Trimmomatic text fields used** (regex line scan):

| Pattern matched | Metric name |
|---|---|
| `Reads written (passing filters):.*\((.+)%\)` | `reads_surviving_pct` |
| `% surviving` (Trimmomatic) | `reads_surviving_pct` |

### 1.3 Gate logic

| Metric | Default threshold | Evidence tier | Operator | Overridable | Message template |
|---|---|---|---|---|---|
| `reads_surviving_pct` | 70.0% | [SILVER] | `<` | Yes | `"Low read survival: {val:.1f}% (threshold: {t:.0f}%)"` |
| `q30_pct` | 75.0% | [SILVER] | `<` | Yes | `"Low Q30: {val:.1f}% (threshold: {t:.0f}%)"` |

**Evidence:** nf-core/rnaseq pipeline default; ENCODE RNA-seq QC standards recommend ≥ 80% surviving trimming. 70% is the floor below which downstream alignment quality is substantially impaired.

### 1.4 Near-threshold warnings

| Metric | Warning range | Message |
|---|---|---|
| `reads_surviving_pct` | 70–77% | `"Read survival {val:.1f}% is near the 70% threshold — monitor closely"` |

### 1.5 Named profile overrides

| Profile | `reads_surviving_pct` | `q30_pct` | Rationale |
|---|---|---|---|
| `rnaseq_polya_standard` | 70.0 (default) | 75.0 (default) | — |
| `rnaseq_ribodepleted` | 65.0 | — | Ribosomal depletion reduces input; some adapter loss expected |
| `rnaseq_ffpe` | 60.0 | 65.0 | FFPE fragmentation increases adapter content and reduces yield |
| `rnaseq_single_nucleus` | 70.0 | — | Standard |
| `rnaseq_nonmodel_organism` | 60.0 | — | Non-model libraries often have higher adapter rates |

### 1.6 Parameter suggestions

Triggered when `reads_surviving_pct < 70%` (RNASeqParameterSuggester):

| Condition | Parameter | Current → Suggested | Confidence | Source |
|---|---|---|---|---|
| Low survival + high adapter in fastp report | `adapter_trimming` | `false → true` | 0.85 | rule |
| Low survival + polyX tail detected | `trim_poly_x` | `false → true` | 0.80 | rule |
| Q30 < 75% | `quality_cutoff` | current → `20` | 0.75 | rule |

---

## 2. Read Alignment

### 2.1 Process name routing

| Keyword | Common tool |
|---|---|
| `STAR_ALIGN`, `STAR_GENOME` | STAR |
| `HISAT2_ALIGN`, `HISAT2` | HISAT2 |
| `BOWTIE2_ALIGN`, `BOWTIE2` | Bowtie2 |
| `BWA_MEM`, `BWA_MEM2`, `BWAMEM` | BWA-MEM (DNA; shares alignment gate) |

### 2.2 Output files read

| Priority | Glob pattern | Format | Tool |
|---|---|---|---|
| 1 | `*Log.final.out`, `Log.final.out` | Text | STAR |
| 2 | `*.log` | Text | HISAT2 / Bowtie2 |
| 3 | `*.txt` | Text | BWA-MEM flagstat |

**STAR `Log.final.out` fields used:**

| Line pattern | Metric |
|---|---|
| `Uniquely mapped reads %` | `alignment_rate` (primary) |
| `% of reads mapped to multiple loci` | added to `alignment_rate` if unique fails |

**HISAT2 / Bowtie2 text fields (regex):**

| Pattern | Metric |
|---|---|
| `(\d+\.\d+)% overall alignment rate` | `alignment_rate` |
| `(\d+\.\d+)% were paired` | (informational) |

### 2.3 Gate logic

This gate has two severity tiers with a fixed red-line sub-threshold:

| Metric | Threshold | Severity | Evidence | Operator | Message |
|---|---|---|---|---|---|
| `alignment_rate` | 70.0% (default, overridable) | `warning` | [SILVER] | `<` | `"Low alignment rate: {val:.1f}% (threshold: {t:.0f}%)"` |
| `alignment_rate` | 25.0% (fixed, non-overridable) | `critical` | [SILVER] | `<` | `"Critically low alignment rate: {val:.1f}%... species/genome mismatch..."` |

The 25% sub-threshold is a **red-line**: it is checked before the overridable threshold and cannot be relaxed by `qc_overrides`. Alignment rates below 25% indicate catastrophic sample-reference mismatch (species swap, corrupt input, extreme contamination) — not a calibration issue.

**Evidence:** nf-core/rnaseq, GATK documentation, STAR manual. ENCODE post-2020 standard describes 85% as a *target* for high-quality organisms, not a hard threshold. 70% as a minimum gate is widely adopted community practice. The 25% critical tier is consistent across multiple tool documentation sources.

### 2.4 Near-threshold warnings

| Metric | Warning range | Message |
|---|---|---|
| `alignment_rate` | 70–77% | `"Alignment rate {val:.1f}% is near the 70% threshold — monitor closely"` |

### 2.5 Named profile overrides

| Profile | `alignment_rate` | Rationale |
|---|---|---|
| `rnaseq_polya_standard` | 70.0 (default) | — |
| `rnaseq_ribodepleted` | 50.0 | Ribosomal RNA depletion reduces effective alignment rate; some rRNA scaffold misalignments expected |
| `rnaseq_ffpe` | 45.0 | FFPE fragmentation and C→T deamination damage increase multi-mapping and unmapped fractions |
| `rnaseq_single_nucleus` | 50.0 | snRNA-seq aligns to pre-mRNA (including introns); intronic reads inflate unmapped fraction with standard transcript indices |
| `rnaseq_nonmodel_organism` | 40.0 | Incomplete genome annotation; many reads map to un-annotated regions |

### 2.6 Parameter suggestions

| Condition | Parameter | Suggested value | Confidence | Source |
|---|---|---|---|---|
| `alignment_rate < 70%` | `twopassMode` | `Basic` | 0.85 | literature (Dobin et al. 2013, Bioinformatics) |
| `alignment_rate < 70%` | `outFilterMismatchNoverLmax` | `0.04 → 0.06` | 0.72 | rule |
| Critical (< 25%) | `genome_build` | (advisory: verify species) | — | N/A — troubleshooting message only |

---

## 3. Gene / Transcript Quantification

### 3.1 Process name routing

| Keyword | Tool | Gate type |
|---|---|---|
| `FEATURECOUNTS`, `SUBREAD`, `HTSEQ` | featureCounts / HTSeq | Gene-level assignment rate |
| `SALMON_QUANT`, `SALMON` | Salmon | Mapping rate |
| `KALLISTO` | kallisto | Mapping rate |

### 3.2 Output files read — featureCounts

| Glob | Format | Field used |
|---|---|---|
| `*.summary` | Tab-separated | `Assigned` count / total = `assigned_reads_pct` |

**Summary file format:**
```
Status          <sample.bam>
Assigned        18423761
Unassigned_NoFeatures   4821034
Unassigned_Ambiguity    512034
...
```
`assigned_reads_pct = Assigned / (Assigned + all Unassigned_*) × 100`

### 3.3 Output files read — Salmon / Kallisto

| Glob | Format | Field |
|---|---|---|
| `aux_info/meta_info.json` | JSON | `percent_mapped` → `mapping_rate` |
| `aux_info/alevin_meta_info.json` | JSON | `percent_mapped` |
| `*.json` (fallback) | JSON | `percent_mapped` or `mapping_rate` |

### 3.4 Gate logic

| Process | Metric | Default threshold | Evidence | Operator | Message |
|---|---|---|---|---|---|
| featureCounts | `assigned_reads_pct` | 50.0% | [SILVER] | `<` | `"Low feature assignment: {val:.1f}% (threshold: {t:.0f}%)"` |
| Salmon / Kallisto | `mapping_rate` | 50.0% | [SILVER] | `<` | `"Low mapping rate: {val:.1f}% (threshold: {t:.0f}%)"` |

**Evidence:** nf-core/rnaseq uses 50% as the floor for featureCounts assignment; below this, results are dominated by multi-mapping or unannotated reads. Salmon mapping rate < 50% generally indicates transcriptome–sample mismatch.

### 3.5 Near-threshold warnings

| Metric | Warning range |
|---|---|
| `mapping_rate` (Salmon/Kallisto) | 50–55% |

### 3.6 Named profile overrides

| Profile | `assigned_reads_pct` | `mapping_rate` | Rationale |
|---|---|---|---|
| `rnaseq_ribodepleted` | 40.0 | — | Residual rRNA reads inflate unassigned fraction |
| `rnaseq_nonmodel_organism` | 30.0 | 40.0 | Incomplete annotation; many reads legitimately unmapped |

### 3.7 Parameter suggestions (Salmon)

| Condition | Parameter | Suggested value | Confidence | Source |
|---|---|---|---|---|
| `mapping_rate < 50%` | `libType` | `A` (auto-detect) | 0.85 | literature (Srivastava et al. 2020, Bioinformatics) |
| `mapping_rate < 50%` | `decoy` | (rebuild with decoy) | 0.72 | literature |

---

## 4. Duplicate Marking (Picard / GATK)

### 4.1 Process name routing

| Keywords |
|---|
| `MARKDUPLICATES`, `PICARD_MARKDUP`, `MARKDUP`, `GATK_MARKDUP` |

### 4.2 Domain-aware skip logic

The duplication gate is **suppressed** for the following domain strings (exact substring match, lowercase):

```python
_skip_domains = {
    "rna_seq", "rnaseq", "rna", "scrna_seq", "scrna",
    "single_cell", "atac_seq", "atacseq",
    "chip_seq", "chipseq", "cut_and_run", "cutandrun",
    "hic", "hic_seq", "hi_c"
}
```

RNA-seq duplicates arise from PCR amplification of a finite mRNA pool — they are biological (not technical) and are expected. HiC libraries have similar properties. The gate only fires for DNA-seq domains (see Supplement S6).

### 4.3 Output files read

| Glob | Format | Field |
|---|---|---|
| `*.metrics`, `*.dup_metrics`, `*.txt` | Picard text | `PERCENT_DUPLICATION` column |

---

## 5. Mock Reproduction Guide

Any gate in this supplement can be tested in isolation using BioMate's mock mode:

```bash
cd /home/yzhang/biomate/backend

# 1. Create a minimal FASTP JSON mock output
mkdir -p /tmp/test_fastp_workdir
cat > /tmp/test_fastp_workdir/fastp.json << 'EOF'
{
  "summary": {
    "before_filtering": {"total_reads": 10000000},
    "after_filtering": {"read1_mean_length": 150, "q30_rate": 0.91}
  },
  "filtering_result": {"passed_filter_reads": 6200000}
}
EOF

# 2. Run the gate directly
.venv/bin/python - << 'EOF'
from pathlib import Path
from unittest.mock import Mock
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

events = []
handler = NextflowQCGateHandler(
    invocation_id="test-001",
    work_dir=Path("/tmp"),
    sse_callback=lambda t, d: events.append((t, d)),
    app=Mock()
)
metrics = handler._parse_trimming_metrics(Path("/tmp/test_fastp_workdir"))
print("Metrics:", metrics)
passed, failures = handler._check_qc_thresholds("FASTP", metrics)
print("Passed:", passed)
print("Failures:", failures)
EOF
```

Expected output when `reads_surviving_pct = 62.0%` (6.2M / 10M):
```
Metrics: {'reads_surviving_pct': 62.0, 'q30_pct': 91.0, 'total_reads_in': 10000000}
Passed: False
Failures: [{'metric': 'reads_surviving_pct', 'value': 62.0, 'threshold': 70.0, 'operator': '<', 'message': 'Low read survival: 62.0% (threshold: 70%)'}]
```

---

## 6. Example SSE Events

### qc_gate_triggered (SILVER — blocking)

```json
{
  "event_type": "qc_gate_triggered",
  "invocation_id": "inv-abc123",
  "process_name": "FASTP",
  "timestamp": "2026-03-04T14:22:01Z",
  "qc_metrics": {
    "reads_surviving_pct": 62.0,
    "q30_pct": 91.0,
    "total_reads_in": 10000000
  },
  "failures": [
    {
      "metric": "reads_surviving_pct",
      "value": 62.0,
      "threshold": 70.0,
      "operator": "<",
      "message": "Low read survival: 62.0% (threshold: 70%)"
    }
  ],
  "suggestions": [
    {
      "parameter": "adapter_trimming",
      "currentValue": false,
      "suggestedValue": true,
      "reason": "Low read survival may be caused by undetected adapter sequences.",
      "confidence": 0.85,
      "source": "rule"
    }
  ],
  "active_profile": null,
  "active_overrides": {}
}
```

### qc_warning (non-blocking, near threshold)

```json
{
  "event_type": "qc_warning",
  "invocation_id": "inv-abc123",
  "process_name": "STAR_ALIGN",
  "timestamp": "2026-03-04T14:25:33Z",
  "qc_metrics": {
    "alignment_rate": 72.3,
    "total_reads": 45000000
  },
  "warnings": [
    {
      "metric": "alignment_rate",
      "value": 72.3,
      "threshold": 70.0,
      "operator": "<",
      "severity": "near_threshold",
      "message": "Alignment rate 72.3% is near the 70% threshold — monitor closely"
    }
  ]
}
```

---

## 7. Test Coverage

| Test class | File | What it covers |
|---|---|---|
| `TestRNASeqAlignmentGate` | `test_qc_e2e_domains.py` | Alignment rate gate, critical tier, near-threshold |
| `TestTrimmingGate` | `test_qc_e2e_domains.py` | reads_surviving_pct, q30_pct |
| `TestQuantificationGate` | `test_qc_e2e_domains.py` | featureCounts assigned %, Salmon mapping rate |
| `TestRNASeqNamedProfiles` | `test_qc_edge_cases.py` | rnaseq_ribodepleted, rnaseq_ffpe profile overrides |
| `TestTierOneChanges` | `test_qc_edge_cases.py` | Critical alignment sub-tier (< 25%) |
| `TestPaper1P0Fixes` | `test_qc_edge_cases.py` | Near-threshold warnings for coverage, TSS, NRF |
