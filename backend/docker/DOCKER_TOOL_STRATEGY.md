# BioMate Docker Tool Strategy

## Overview

Two categories of Docker containers:
1. **Analysis Notebook** (`biomate-notebook`) - Visualization and post-processing
2. **Tool Containers** - Individual bioinformatics tools for workflow execution

## Why Build Custom Docker Containers?

### Advantages of Local Docker Builds:
- **Efficiency**: Pre-built images, no runtime package installation
- **Reproducibility**: Fixed versions, consistent across environments
- **Offline Support**: No need to download tools during workflow execution
- **Customization**: Bundle specific tool versions, configurations
- **Speed**: Smaller, purpose-built images vs large general containers

### When to Use BioContainers vs Custom:
| Scenario | Use BioContainers | Use Custom Build |
|----------|-------------------|------------------|
| Standard tool, standard version | ✓ | |
| Multiple tools needed together | | ✓ |
| Custom tool configuration | | ✓ |
| Specific version combination | | ✓ |
| Need minimal image size | | ✓ |

## Container Architecture

```
docker/
├── biomate-notebook/       # Visualization & analysis
├── aligners/               # Read alignment tools
│   ├── bwa/
│   ├── hisat2/
│   ├── star/
│   └── bowtie2/
├── assemblers/             # Genome/transcriptome assembly
│   ├── spades/
│   ├── trinity/
│   └── megahit/
├── variant-calling/        # Variant analysis
│   ├── gatk/
│   ├── bcftools/
│   ├── freebayes/
│   └── deepvariant/
├── rna-seq/               # RNA-seq specific
│   ├── salmon/
│   ├── kallisto/
│   ├── htseq/
│   └── featurecounts/
├── single-cell/           # Single-cell analysis
│   ├── cellranger/
│   └── starsolo/
├── metagenomics/          # Microbiome analysis
│   ├── kraken2/
│   ├── metaphlan/
│   └── humann/
├── qc-tools/              # Quality control
│   ├── fastqc-multiqc/
│   ├── trimmomatic/
│   └── fastp/
└── utilities/             # General utilities
    ├── samtools-bcftools/
    ├── bedtools/
    └── picard/
```

## Build Strategy Options

### Option 1: Single-Tool Containers (Maximum Flexibility)
```dockerfile
# Example: samtools only
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y samtools
```
- **Pros**: Small, focused, easy to update
- **Cons**: Need many containers, more orchestration

### Option 2: Multi-Tool Containers (Recommended for BioMate)
```dockerfile
# Example: QC pipeline tools
FROM ubuntu:22.04
RUN apt-get install -y fastqc multiqc trimmomatic fastp
```
- **Pros**: Fewer containers, related tools together, efficient
- **Cons**: Larger images, update one = rebuild all

### Option 3: Base + Layer Approach (Best for Complex Tools)
```dockerfile
# Base image with common dependencies
FROM biomate/base-bio:latest
RUN install_specific_tool
```
- **Pros**: Shared base, faster builds
- **Cons**: More complex management

## Recommended Tool Groupings

### Group 1: QC & Preprocessing (`biomate/qc-tools`)
- FastQC, MultiQC, Fastp, Trimmomatic, Cutadapt

### Group 2: Alignment (`biomate/aligners`)
- BWA-MEM2, Bowtie2, HISAT2, Minimap2

### Group 3: RNA-seq Quantification (`biomate/rnaseq-quant`)
- Salmon, Kallisto, RSEM, featureCounts, HTSeq

### Group 4: Variant Calling (`biomate/variant-tools`)
- BCFtools, SAMtools, Freebayes, VCFtools

### Group 5: Utilities (`biomate/bio-utils`)
- SAMtools, BEDTools, Picard, GATK utilities

### Group 6: Metagenomics (`biomate/metagenomics`)
- Kraken2, Bracken, MetaPhlAn, HUMAnN

## Priority Build Order

Based on BioMate workflow patterns:

1. **Phase 1 (Core)**
   - `biomate/qc-tools` - Every workflow needs QC
   - `biomate/bio-utils` - SAMtools/BEDTools used everywhere

2. **Phase 2 (Domain-Specific)**
   - `biomate/aligners` - For genomics/transcriptomics
   - `biomate/rnaseq-quant` - For RNA-seq workflows

3. **Phase 3 (Specialized)**
   - `biomate/variant-tools` - For variant calling
   - `biomate/metagenomics` - For microbiome analysis

## Galaxy Integration

These containers work with Galaxy's containerized tool execution:
- Galaxy job destinations can specify containers
- BioMate workflows will reference these images
- Environment variables pass Galaxy context

## Build Commands

```bash
# Build all containers
./build-all.sh

# Build specific group
docker build -t biomate/qc-tools:latest docker/qc-tools/

# Build with version tag
docker build -t biomate/aligners:1.0-bwa-0.7.17 docker/aligners/
```
