# DIA-NN ARM64 Limitation Analysis

## Executive Summary

DIA-NN cannot run on ARM64 (Apple Silicon, AWS Graviton) due to x86-specific SIMD instructions. This is a fundamental architectural limitation with no workaround.

## Technical Analysis

### DIA-NN Binary Requirements

DIA-NN uses x86-specific CPU features:
- **AVX/AVX2** - 256-bit vector operations
- **SSE4.1/SSE4.2** - 128-bit SIMD instructions
- **FMA** - Fused multiply-add

From `cpu_info.h`:
```cpp
static bool AVX(void) { return CPU_Rep.f_1_ECX_[28]; }
static bool AVX2(void) { return CPU_Rep.f_7_EBX_[5]; }
static bool SSE41(void) { return CPU_Rep.f_1_ECX_[19]; }
```

### Why ARM64 Compilation is Impossible

1. **Incomplete Source Code**: GitHub repo only contains Visual Studio project files, not full `.cpp` source
2. **x86-specific Intrinsics**: Uses `__cpuid`, `__cpuidex` which don't exist on ARM
3. **No ARM SIMD Port**: Would require rewriting with ARM NEON/SVE instructions

### Available DIA-NN Binaries

| Version | Platform | Architecture | Status |
|---------|----------|--------------|--------|
| 1.8.1 | Linux | x86_64 | Available (biocontainers) |
| 1.8.1 | Windows | x86_64 | Available |
| 2.1.0 | Linux | x86_64 | Available (bigbio/diann-docker) |
| 2.2.0 | Windows | x86_64 | Available (GitHub) |
| Any | Linux | ARM64 | **NOT AVAILABLE** |

## Impact on Biomate Platform

### What Works on ARM64

All standard bioinformatics tools via Bioconda:
- NGS: bwa, bowtie2, hisat2, star, minimap2, salmon, kallisto
- Variant Calling: gatk, freebayes, bcftools
- QC: fastqc, fastp, multiqc
- Metagenomics: kraken2, spades

### What Doesn't Work on ARM64

Proteomics tools requiring x86:
- **DIA-NN** - Data-independent acquisition analysis
- **MaxQuant** - Windows/.NET only
- **Some OpenMS tools** - x86 optimizations

## Solutions for ARM64 Users

### Option 1: Remote Execution (Recommended)

Execute DIA-NN workflows on x86_64 cloud instances:
```yaml
# Nextflow config
process {
    withLabel: 'diann' {
        executor = 'aws-batch'
        queue = 'diann-x86-queue'
        container = 'biocontainers/diann:v1.8.1_cv1'
    }
}
```

### Option 2: Pre-computed Spectral Libraries

For common organisms, use pre-computed libraries to skip the longest DIA-NN step:
- Human SwissProt: `s3://knowledge-datasets-1759951976/spectral_libraries/human/`
- Mouse SwissProt: `s3://knowledge-datasets-1759951976/spectral_libraries/mouse/`

**Note**: Still requires x86_64 for analysis steps.

### Option 3: Docker with Rosetta (macOS only)

On macOS with Apple Silicon:
```bash
docker run --platform linux/amd64 biocontainers/diann:v1.8.1_cv1 diann --help
```

Performance is ~50-70% of native x86_64.

## Docker Image Contents

### biomate/biotools:arm64 (8GB)

Tools installed via Bioconda (ARM64-native):
- Aligners: bwa, bwa-mem2, bowtie2, hisat2, star, minimap2
- RNA-seq: salmon, kallisto, stringtie, subread
- Variant: gatk, freebayes, samtools, bcftools, vcftools
- QC: fastqc, fastp, multiqc, cutadapt, trimmomatic
- Assembly: kraken2, spades, blast, hmmer

**Total executables**: 1336 (includes scripts and dependencies)

### biomate/biotools:comprehensive (6.22GB)

Pre-built x86_64 binaries + Python packages.
**Total in /usr/local/bin**: 301 tools

### Missing from Both

- DIA-NN (no ARM64 build available)
- MaxQuant (Windows only)
- Full nf-core module set (755 modules - impractical to bundle all)

## Recommendations

1. **For proteomics workflows**: Use x86_64 cloud execution (AWS, GCP, Azure)
2. **For ARM64 development**: Use the curated biomate/biotools:arm64 for genomics/transcriptomics
3. **For DIA-NN specifically**: Pre-generate spectral libraries on x86_64, distribute via S3

## Generated

Date: 2025-12-18
Analysis by: Claude Code
