# BioMate Workflow Docker Images

**Created:** December 19, 2025
**Platform:** x86_64 (linux/amd64)
**Base Image:** mambaorg/micromamba:1.5-jammy

## Overview

Four specialized Docker images for nf-core bioinformatics workflows, split by use case for smaller, faster downloads.

| Image | Workflows | Size | Use Case |
|-------|-----------|------|----------|
| `biomate/wgs-wes:x86` | sarek, raredisease | 8.78GB | WGS/WES variant calling |
| `biomate/rnaseq:x86` | rnaseq, drop | 9.01GB | Bulk RNA-seq analysis |
| `biomate/cutandrun:x86` | cutandrun | 5.03GB | CUT&RUN/CUT&Tag |
| `biomate/singlecell:x86` | scAuto | 14.1GB | Single-cell RNA-seq |

---

## Quick Start

```bash
# Run any image interactively
docker run --platform linux/amd64 -it biomate/wgs-wes:x86 bash

# Mount data directory
docker run --platform linux/amd64 -it -v /path/to/data:/data biomate/wgs-wes:x86 bash

# Run verification script (default command)
docker run --platform linux/amd64 biomate/wgs-wes:x86
```

---

## Image Details

### 1. WGS/WES Image (`biomate/wgs-wes:x86`)

**Supported Workflows:**
- [nf-core/sarek](https://nf-co.re/sarek) v3.7.0 - WGS/WES variant calling
- [nf-core/raredisease](https://nf-co.re/raredisease) v2.6.0 - Rare disease analysis

**Included Tools:**

| Category | Tools |
|----------|-------|
| Aligners | bwa, bwa-mem2, bowtie2, minimap2 |
| BAM Processing | samtools, bcftools, bedtools, picard, sambamba, mosdepth |
| Variant Calling | GATK4, freebayes, lofreq, glnexus |
| SV Calling | tiddit, svdb, cnvkit |
| Copy Number | control-freec, ASCAT |
| Annotation | snpeff (with openjdk=17), ensembl-vep (with perl-dbi), vcfanno |
| QC | fastqc, fastp, multiqc, qualimap, preseq |
| Other | dragmap, fgbio, vt, msisensor-pro, rtg-tools |

**Not Included (use separate containers):**
- DeepVariant → `google/deepvariant`
- Strelka2 → `quay.io/biocontainers/strelka`
- Manta → `quay.io/biocontainers/manta`

---

### 2. RNA-seq Image (`biomate/rnaseq:x86`)

**Supported Workflows:**
- [nf-core/rnaseq](https://nf-co.re/rnaseq) v3.22.1 - Bulk RNA-seq
- [nf-core/drop](https://nf-co.re/drop) - RNA-seq for rare disease

**Included Tools:**

| Category | Tools |
|----------|-------|
| Aligners | STAR, HISAT2 |
| Quantification | salmon, kallisto, RSEM, subread (featureCounts), stringtie, htseq |
| BAM Processing | samtools, bcftools, bedtools, picard |
| QC | fastqc, fastp, multiqc, preseq, qualimap, rseqc, dupradar |
| Trimming | cutadapt, trim-galore, umi_tools |
| Other | sortmerna, bbmap, kraken2, bracken |
| Python | numpy, scipy, pandas, matplotlib, seaborn, biopython, pysam |
| R Packages | DESeq2, edgeR, limma, tidyverse, OUTRIDER, FRASER (via bioconductor) |

---

### 3. CUT&RUN Image (`biomate/cutandrun:x86`)

**Supported Workflows:**
- [nf-core/cutandrun](https://nf-co.re/cutandrun) v3.2.2 - CUT&RUN/CUT&Tag

**Included Tools:**

| Category | Tools |
|----------|-------|
| Aligners | bowtie2, bwa |
| Peak Calling | MACS2, MACS3, SEACR |
| Signal Analysis | deeptools (bamCoverage, computeMatrix, plotHeatmap, etc.) |
| BAM Processing | samtools, bedtools, picard, sambamba |
| QC | fastqc, fastp, multiqc, preseq, phantompeakqualtools |
| Trimming | cutadapt, trim-galore |
| Python | numpy, scipy, pandas, matplotlib, seaborn, pybedtools, pysam |

---

### 4. Single-cell Image (`biomate/singlecell:x86`)

**Supported Workflows:**
- scAuto (in-house single-cell RNA-seq pipeline)
- Compatible with 10x Genomics, Drop-seq, Smart-seq2

**Included Tools:**

| Category | Tools |
|----------|-------|
| Quantification | alevin-fry, kb-python, salmon, kallisto (with hdf5) |
| Aligners | STAR, minimap2 |
| BAM Processing | samtools, bedtools |
| QC | fastqc, fastp, multiqc |
| Python (via conda) | scanpy, anndata, leidenalg, igraph, scrublet, scvi-tools, squidpy, scvelo, pytorch |
| Python (via pip) | doubletdetection |
| R Packages | Seurat, SingleCellExperiment, scater, tidyverse |

**Note:** This image is larger (14.1GB) due to PyTorch dependencies for scvi-tools.

---

## Building Images

All Dockerfiles are located in:
```
/home/yzhang/biomate/Biomni/biomni_galaxy/docker/
```

### Build Commands

```bash
cd /home/yzhang/biomate/Biomni/biomni_galaxy/docker/

# Build individual images
docker build --platform linux/amd64 -t biomate/wgs-wes:x86 -f Dockerfile.wgs-wes .
docker build --platform linux/amd64 -t biomate/rnaseq:x86 -f Dockerfile.rnaseq .
docker build --platform linux/amd64 -t biomate/cutandrun:x86 -f Dockerfile.cutandrun .
docker build --platform linux/amd64 -t biomate/singlecell:x86 -f Dockerfile.singlecell .
```

### Building on ARM64 (Apple Silicon / AWS Graviton)

QEMU emulation is required:
```bash
# Install QEMU binfmt (one-time setup)
docker run --privileged --rm tonistiigi/binfmt --install all

# Then build with --platform flag as above
```

---

## Sharing Images

### Option 1: Docker Hub

```bash
# Login
docker login

# Push images
docker push biomate/wgs-wes:x86
docker push biomate/rnaseq:x86
docker push biomate/cutandrun:x86
docker push biomate/singlecell:x86
```

### Option 2: Export as Files

```bash
# Save and compress
docker save biomate/wgs-wes:x86 | gzip > wgs-wes-x86.tar.gz
docker save biomate/rnaseq:x86 | gzip > rnaseq-x86.tar.gz
docker save biomate/cutandrun:x86 | gzip > cutandrun-x86.tar.gz
docker save biomate/singlecell:x86 | gzip > singlecell-x86.tar.gz

# Load on another machine
docker load < wgs-wes-x86.tar.gz
```

### Option 3: Private Registry (AWS ECR, GCR, etc.)

```bash
# Tag for your registry
docker tag biomate/wgs-wes:x86 your-registry.com/biomate/wgs-wes:x86

# Push
docker push your-registry.com/biomate/wgs-wes:x86
```

---

## Usage Examples

### Run a Tool

```bash
# Run GATK
docker run --platform linux/amd64 -v $(pwd):/data biomate/wgs-wes:x86 \
    gatk HaplotypeCaller -R /data/ref.fa -I /data/sample.bam -O /data/output.vcf

# Run salmon
docker run --platform linux/amd64 -v $(pwd):/data biomate/rnaseq:x86 \
    salmon quant -i /data/index -l A -1 /data/R1.fq.gz -2 /data/R2.fq.gz -o /data/quant

# Run MACS2
docker run --platform linux/amd64 -v $(pwd):/data biomate/cutandrun:x86 \
    macs2 callpeak -t /data/treatment.bam -c /data/control.bam -n sample -outdir /data/peaks

# Run scanpy analysis
docker run --platform linux/amd64 -v $(pwd):/data biomate/singlecell:x86 \
    python /data/analysis_script.py
```

### Interactive Python/R Session

```bash
# Python with scanpy
docker run --platform linux/amd64 -it -v $(pwd):/data biomate/singlecell:x86 python

# R with Seurat
docker run --platform linux/amd64 -it -v $(pwd):/data biomate/singlecell:x86 R
```

---

## Environment Activation

All images use micromamba with a `biotools` environment. The entrypoint automatically activates it.

```bash
# Inside container, environment is already active
which bwa  # /opt/conda/envs/biotools/bin/bwa

# Manual activation (if needed)
eval "$(micromamba shell hook -s bash)"
micromamba activate biotools
```

---

## Tool Versions

Run the verification script to see installed tool versions:

```bash
docker run --platform linux/amd64 biomate/wgs-wes:x86
docker run --platform linux/amd64 biomate/rnaseq:x86
docker run --platform linux/amd64 biomate/cutandrun:x86
docker run --platform linux/amd64 biomate/singlecell:x86
```

---

## Known Limitations

### Tools Requiring Separate Containers

| Tool | Reason | Recommended Container |
|------|--------|----------------------|
| DeepVariant | TensorFlow x86 + GPU | `google/deepvariant` |
| Strelka2 | Requires Python 2.7 | `quay.io/biocontainers/strelka:2.9.10` |
| Manta | Requires Python 2.7 | `quay.io/biocontainers/manta:1.6.0` |
| CellRanger | Proprietary x86 binary | 10x Genomics official |

### Platform Notes

- Images are built for **linux/amd64** (x86_64)
- On ARM64 (Apple Silicon, Graviton), use `--platform linux/amd64` flag
- QEMU emulation may cause ~2-5x slowdown on ARM64

---

## File Structure

```
/home/yzhang/biomate/Biomni/biomni_galaxy/docker/
├── Dockerfile.wgs-wes          # WGS/WES image
├── Dockerfile.rnaseq           # RNA-seq image
├── Dockerfile.cutandrun        # CUT&RUN image
├── Dockerfile.singlecell       # Single-cell image
├── Dockerfile.x86-workflows    # Combined image (deprecated, too large)
├── Dockerfile.arm64            # ARM64 comprehensive image
└── README_WORKFLOW_DOCKERS.md  # This documentation
```

---

## Troubleshooting

### "exec format error"
You're running x86 image on ARM64 without QEMU:
```bash
docker run --privileged --rm tonistiigi/binfmt --install all
```

### Tool not found
Ensure the environment is activated:
```bash
eval "$(micromamba shell hook -s bash)"
micromamba activate biotools
```

### Permission denied on mounted files
Add user mapping:
```bash
docker run --platform linux/amd64 -u $(id -u):$(id -g) -v $(pwd):/data biomate/wgs-wes:x86 ...
```

---

## Contact

For issues or questions, contact the BioMate team.
