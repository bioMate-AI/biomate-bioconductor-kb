# BioMate Autofix Benchmark Report
**Date:** 2026-04-12  
**Branch:** integration/next-phase  
**Author:** Session 5 (Track 5B)

---

## Overview

The autofix benchmark measures BioMate's ability to:
1. **Correctly identify the root cause** of a workflow failure (root cause accuracy)
2. **Propose the right fix action** (fix accuracy)

20 deliberately-broken workflow states are presented to BioMate via chat. Each case includes the workflow name, parameter set, and a realistic error log. An LLM judge (Claude Haiku) evaluates whether BioMate's response correctly identifies the root cause category and proposes an equivalent fix.

**Scoring:**
- 1.0 = root cause correct AND fix correct
- 0.5 = root cause correct, fix wrong/partial
- 0.0 = wrong root cause

---

## Test Cases

| Case ID | Category | Workflow | Description | Difficulty |
|---|---|---|---|---|
| af_001 | genome_mismatch | nf-core/rnaseq | hg19 genome with GRCh38 STAR index | easy |
| af_002 | genome_mismatch | nf-core/chipseq | mm9 not in iGenomes (use mm10) | easy |
| af_003 | genome_mismatch | nf-core/sarek | Mixed build: fasta=hg38, dbsnp=hg19 VCF | medium |
| af_004 | genome_mismatch | nf-core/atacseq | GRCh37 peak calling chromosome size error | easy |
| af_005 | genome_mismatch | nf-core/methylseq | Bismark index mismatch hg38 vs hg19 | easy |
| af_006 | missing_input | nf-core/rnaseq | Samplesheet S3 path does not exist | easy |
| af_007 | missing_input | nf-core/clipseq | Required ncrna_fasta not provided | easy |
| af_008 | missing_input | nf-core/sarek | Relative FASTQ paths in samplesheet | medium |
| af_009 | missing_input | gromacs_protein_md | Protein PDB missing for MD simulation | easy |
| af_010 | missing_input | nf-core/differentialabundance | Count matrix path empty | easy |
| af_011 | param_type_error | nf-core/rnaseq | min_trimmed_reads as string "100" | easy |
| af_012 | param_type_error | nf-core/sarek | skip_qc as string "true" | easy |
| af_013 | param_type_error | nf-core/chipseq | min_reps_consensus = 0.5 (not int) | easy |
| af_014 | param_type_error | alphafold_db_search | max_template_date as Unix timestamp | medium |
| af_015 | param_type_error | nf-core/methylseq | clip_r1/clip_r2 as strings | easy |
| af_016 | resource_failure | nf-core/rnaseq | STAR OOM (32GB → need 64GB) | medium |
| af_017 | resource_failure | nf-core/sarek | HaplotypeCaller 6h wall time timeout | medium |
| af_018 | resource_failure | amber_pmemd_md | GPU OOM for large solvated complex | hard |
| af_019 | resource_failure | nf-core/differentialabundance | DESeq2 OOM for 50k × 200 matrix | medium |
| af_020 | resource_failure | nf-core/rnaseq | Disk full during FASTQ merge | easy |

---

## Results

> **Status: Benchmark not yet run. Run with:**
> ```
> cd evaluation/
> python runners/run_autofix_benchmark.py --output results/autofix_benchmark/
> ```

| Category | N | Mean Score | Target | Notes |
|---|---|---|---|---|
| genome_mismatch | 5 | — | ≥ 0.90 | Genome build errors are well-defined and common — BioMate should excel |
| missing_input | 5 | — | ≥ 0.90 | File-not-found and missing param errors are unambiguous |
| param_type_error | 5 | — | ≥ 0.95 | Error message includes the exact fix — near-perfect expected |
| resource_failure | 5 | — | ≥ 0.80 | Requires knowing AWS instance sizes and resource configs |
| **Overall** | **20** | **—** | **≥ 0.90** | |

---

## AI Scientist Comparison

The AI Scientist paper (Lu et al., 2024) reports:
- Error recovery rate: ~65–70% (self-correction on failed experiments)  
- Mean attempts to resolution: 2.1  
- Categories: Python execution errors, dependency errors, config errors

BioMate's autofix benchmark is analogous but bioinformatics-specific:
- **Error recovery rate** = mean autofix benchmark score (target: 78%)
- **Mean attempts**: tracked implicitly (single-shot diagnosis, no retry loop in benchmark)
- **BioMate-unique**: resource failure category (AWS Batch OOM/timeout) has no AI Scientist equivalent

Target is ≥90% overall — a system that fails to diagnose 1 in 10 workflow errors is not production-quality. The AI Scientist paper's 65-70% recovery rate is a floor, not a ceiling.

---

## Autofix Framework Modules Tested

| Fixer Class | Cases Covered | Expected Trigger |
|---|---|---|
| `NextflowParameterFixer` | af_001, af_004, af_007, af_009-015 | Missing params, type errors |
| `ReferenceGenomeFixer` | af_002, af_003, af_005 | Genome build mismatches |
| `SamplesheetFixer` | af_008 | Relative path errors in samplesheet |
| `DataFileFixer` | af_006 | S3 file not found |
| `AWSResourceFixer` | af_016-020 | OOM, timeout, disk full |
| `RetryStrategyFixer` | af_017 | Timeout → retry with extended walltime |

---

## Improvement Opportunities

If baseline score < 0.70:
1. **Resource failure gap** (af_016–020): BioMate may not know specific AWS instance types. Add instance size reference to `domain_knowledge.yaml`.
2. **Mixed build diagnosis** (af_003): Requires recognizing two incompatible reference sets. Add "check VCF/BAM sequence dictionary match" to sarek troubleshooting knowledge.
3. **Relative path recognition** (af_008): Samplesheet path resolution is AWS Batch-specific. Add to nextflow AWS troubleshooting docs.

---

## Notes

- Benchmark uses chat-based diagnosis (not the internal autofix Python API) — tests the same capability a user would experience
- LLM judge evaluates semantic correctness of the fix, not exact string match
- Cases with `fix_difficulty: hard` (af_018) are expected to score lower — BioMate may not know AMBER GPU memory requirements
- All 20 cases are based on real error patterns observed in AWS Batch Nextflow executions
