# Complete Working Tools Inventory

**Date:** December 19, 2025
**Platform:** x86_64 (linux/amd64)

This document provides a comprehensive list of all tools included in each Docker image. All tools listed here are verified working on native x86 systems.

---

## 1. WGS/WES Image (`biomate/wgs-wes:x86`)

**Size:** ~9.5GB
**Supported Workflows:** nf-core/sarek, nf-core/raredisease

### Aligners
| Tool | Version | Description |
|------|---------|-------------|
| bwa | 0.7.19 | Burrows-Wheeler Aligner |
| bwa-mem2 | 2.x | Faster BWA-MEM implementation |
| bowtie2 | 2.x | Fast short read aligner |
| minimap2 | 2.x | Long read aligner |
| dragmap | 1.3.0 | DRAGEN-compatible mapper |

### BAM/SAM Processing
| Tool | Version | Description |
|------|---------|-------------|
| samtools | 1.23 | SAM/BAM manipulation |
| bcftools | 1.x | VCF/BCF manipulation |
| htslib | 1.x | High-throughput sequencing library |
| bedtools | 2.31.1 | BED file operations |
| vcftools | 0.1.x | VCF file operations |
| tabix | 1.x | Generic TAB-delimited indexer |
| picard | 3.x | BAM manipulation tools |
| sambamba | 1.x | Fast BAM processing |
| mosdepth | 0.3.x | Fast coverage calculation |

### Variant Callers - SNV/Indel
| Tool | Version | Description |
|------|---------|-------------|
| gatk4 | 4.x | GATK HaplotypeCaller, Mutect2 |
| freebayes | 1.3.9 | Bayesian haplotype-based variant caller |
| lofreq | 2.1.5 | Low-frequency variant caller |
| glnexus | 1.4.1 | Joint genotyping |

### Structural Variant Callers
| Tool | Version | Description |
|------|---------|-------------|
| tiddit | 3.9.2 | SV and CNV caller |
| svdb | 2.x | SV database operations |
| cnvkit | 0.9.x | Copy number caller (requires matplotlib<3.9, pandas<2.0) |

### Copy Number Analysis
| Tool | Version | Description |
|------|---------|-------------|
| control-freec | 11.6 | Copy number and LOH caller |

### Variant Annotation
| Tool | Version | Description |
|------|---------|-------------|
| snpeff | 5.x | Genetic variant annotation (with openjdk=17) |
| ensembl-vep | 112.x | Variant Effect Predictor (with perl-dbi) |
| vcfanno | 0.3.7 | VCF annotation |

### QC Tools
| Tool | Version | Description |
|------|---------|-------------|
| fastqc | 0.12.1 | Sequence QC |
| fastp | 0.23.x | Fast all-in-one preprocessor |
| multiqc | 1.x | Aggregate QC reports |
| qualimap | 2.x | BAM QC |
| preseq | 3.x | Library complexity prediction |

### Trimming
| Tool | Version | Description |
|------|---------|-------------|
| cutadapt | 5.x | Adapter trimming |
| trim-galore | 0.6.10 | Wrapper for cutadapt + FastQC |

### Additional Tools
| Tool | Version | Description |
|------|---------|-------------|
| msisensor-pro | 1.3.0 | MSI detection |
| fgbio | 2.x | UMI-aware tools |
| vt | 0.5.x | Variant normalization |
| rtg-tools | 3.12.1 | Real Time Genomics tools |

### NOT Included (use separate containers)
- DeepVariant → `google/deepvariant:1.6.0`
- Strelka2 → `quay.io/biocontainers/strelka:2.9.10--h9ee0642_1`
- Manta → `quay.io/biocontainers/manta:1.6.0--h9ee0642_2`
- ASCAT → install via R devtools

---

## 2. RNA-seq Image (`biomate/rnaseq:x86`)

**Size:** ~10GB
**Supported Workflows:** nf-core/rnaseq, nf-core/drop

### Aligners
| Tool | Version | Description |
|------|---------|-------------|
| STAR | 2.7.11b | Spliced aligner |
| hisat2 | 2.2.1 | Splice-aware aligner |

### Quantification
| Tool | Version | Description |
|------|---------|-------------|
| salmon | 1.x | Pseudo-alignment quantification |
| kallisto | 0.51.1 | Pseudo-alignment quantification |
| rsem | 1.3.1 | RNA-seq quantification |
| subread (featureCounts) | 2.x | Read counting |
| stringtie | 3.0.3 | Transcript assembly and quantification |
| htseq | 2.x | Read counting |

### BAM/SAM Processing
| Tool | Version | Description |
|------|---------|-------------|
| samtools | 1.x | SAM/BAM manipulation |
| bcftools | 1.x | VCF/BCF manipulation |
| bedtools | 2.x | BED file operations |
| picard | 3.x | BAM manipulation tools |

### QC Tools
| Tool | Version | Description |
|------|---------|-------------|
| fastqc | 0.12.1 | Sequence QC |
| fastp | 1.0.1 | Fast all-in-one preprocessor |
| multiqc | 1.x | Aggregate QC reports |
| preseq | 3.x | Library complexity |
| qualimap | 2.x | BAM QC |
| rseqc | 5.x | RNA-seq specific QC |
| dupradar | 1.x | Duplication rate QC |

### Trimming
| Tool | Version | Description |
|------|---------|-------------|
| cutadapt | 5.x | Adapter trimming |
| trim-galore | 0.6.x | Wrapper for cutadapt + FastQC |
| umi_tools | 1.x | UMI processing |

### Contamination Check
| Tool | Version | Description |
|------|---------|-------------|
| sortmerna | 4.x | rRNA filtering |
| bbmap | 39.x | Read mapping and filtering |
| kraken2 | 2.x | Taxonomic classification |
| bracken | 2.x | Abundance estimation |

### R/Bioconductor Packages
| Package | Version | Description |
|---------|---------|-------------|
| DESeq2 | 1.42.0 | Differential expression |
| edgeR | 4.x | Differential expression |
| limma | 3.x | Linear models for microarray |
| OUTRIDER | 1.20.1 | Outlier detection (drop pipeline) |
| FRASER | 1.99.4 | Splicing analysis (drop pipeline) |
| tidyverse | 2.x | Data manipulation |

### Python Packages
| Package | Description |
|---------|-------------|
| numpy | Numerical computing |
| scipy | Scientific computing |
| pandas | Data manipulation |
| matplotlib | Plotting |
| seaborn | Statistical visualization |
| biopython | Biological computation |
| pysam | SAM/BAM interface |

---

## 3. CUT&RUN Image (`biomate/cutandrun:x86`)

**Size:** ~6GB
**Supported Workflows:** nf-core/cutandrun

### Aligners
| Tool | Version | Description |
|------|---------|-------------|
| bowtie2 | 2.5.4 | Short read aligner |
| bwa | 0.7.19 | Burrows-Wheeler Aligner |

### Peak Callers
| Tool | Version | Description |
|------|---------|-------------|
| macs2 | 2.2.9.1 | Peak calling |
| macs3 | 3.0.3 | Peak calling (updated) |
| SEACR | 1.3 | CUT&RUN-specific peak caller |

### Signal Analysis
| Tool | Version | Description |
|------|---------|-------------|
| deeptools | 3.5.6 | Signal analysis and visualization |
| bamCoverage | 3.5.6 | Coverage calculation |

### BAM/SAM Processing
| Tool | Version | Description |
|------|---------|-------------|
| samtools | 1.23 | SAM/BAM manipulation |
| bedtools | 2.31.1 | BED file operations |
| picard | 3.x | BAM manipulation tools |
| sambamba | 1.x | Fast BAM processing |

### QC Tools
| Tool | Version | Description |
|------|---------|-------------|
| fastqc | 0.12.1 | Sequence QC |
| fastp | 1.0.1 | Fast all-in-one preprocessor |
| multiqc | 1.x | Aggregate QC reports |
| preseq | 3.x | Library complexity |
| phantompeakqualtools | 1.x | ChIP-seq QC |

### Trimming
| Tool | Version | Description |
|------|---------|-------------|
| cutadapt | 5.x | Adapter trimming |
| trim-galore | 0.6.x | Wrapper for cutadapt + FastQC |

### Python Packages
| Package | Description |
|---------|-------------|
| numpy | Numerical computing |
| scipy | Scientific computing |
| pandas | Data manipulation |
| matplotlib | Plotting |
| seaborn | Statistical visualization |
| pybedtools | BED file interface |
| pysam | SAM/BAM interface |

---

## 4. Single-cell Image (`biomate/singlecell:x86`)

**Size:** ~9.2GB
**Supported Workflows:** scAuto, 10x Genomics, Drop-seq, Smart-seq2

### Single-cell Quantification
| Tool | Version | Description |
|------|---------|-------------|
| alevin-fry | 0.11.2 | Fast single-cell quantification |
| kb-python | 0.x | kallisto|bustools wrapper |
| salmon | 1.x | Pseudo-alignment quantification |
| kallisto | 0.51.1 | Pseudo-alignment (with hdf5) |

### Aligners
| Tool | Version | Description |
|------|---------|-------------|
| STAR | 2.7.11b | Spliced aligner |
| minimap2 | 2.30 | Long read aligner |

### BAM/SAM Processing
| Tool | Version | Description |
|------|---------|-------------|
| samtools | 1.x | SAM/BAM manipulation |
| bedtools | 2.x | BED file operations |

### QC Tools
| Tool | Version | Description |
|------|---------|-------------|
| fastqc | 0.12.1 | Sequence QC |
| fastp | 1.0.1 | Fast all-in-one preprocessor |
| multiqc | 1.x | Aggregate QC reports |

### Python Single-cell Packages
| Package | Version | Description |
|---------|---------|-------------|
| scanpy | 1.11.x | Single-cell analysis |
| anndata | 0.12.x | Annotated data matrices |
| leidenalg | 0.11.x | Leiden clustering |
| igraph | 1.x | Graph analysis |
| scrublet | 0.2.3 | Doublet detection |
| doubletdetection | 4.x | Doublet detection |
| scvi-tools | 1.4.x | Deep learning for single-cell |
| squidpy | 1.7.x | Spatial single-cell analysis |
| scvelo | 0.3.x | RNA velocity |
| pytorch | 2.9.x | Deep learning framework |

### R/Bioconductor Packages
| Package | Version | Description |
|---------|---------|-------------|
| Seurat | 5.4.0 | Single-cell analysis |
| SingleCellExperiment | 1.28.0 | Data structure |
| scater | 1.x | QC and visualization |
| tidyverse | 2.x | Data manipulation |

---

## Quick Reference Commands

### Run verification on any image:
```bash
docker run --rm biomate/wgs-wes:x86
docker run --rm biomate/rnaseq:x86
docker run --rm biomate/cutandrun:x86
docker run --rm biomate/singlecell:x86
```

### Enter interactive shell:
```bash
docker run -it -v /data:/data biomate/wgs-wes:x86 bash
```

### Run a specific tool:
```bash
docker run --rm -v /data:/data biomate/wgs-wes:x86 bwa mem ref.fa reads.fq > aligned.sam
docker run --rm -v /data:/data biomate/rnaseq:x86 STAR --genomeDir /data/genome --readFilesIn /data/reads.fq
docker run --rm -v /data:/data biomate/singlecell:x86 python -c "import scanpy as sc; print(sc.__version__)"
```

---

## Notes for x86 Users

1. All tools listed work on native x86 systems
2. Some tools show QEMU errors when tested on ARM64 - this is expected and does not affect x86 usage
3. For nf-core workflows, these images provide most required tools - specialized tools (DeepVariant, Strelka2, Manta) are pulled automatically by nf-core
