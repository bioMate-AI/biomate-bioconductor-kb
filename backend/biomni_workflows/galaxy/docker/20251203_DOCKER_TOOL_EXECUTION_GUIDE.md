# BioMate Tool Execution Guide: Docker vs Host

**Date:** 2025-12-03
**Author:** BioMate Team

## Overview

BioMate supports two modes for executing bioinformatics tools:
1. **Docker Mode** - Tools run inside `biomate/biotools:arm64` container (recommended)
2. **Host Mode** - Tools run directly on the host system

---

## Docker Images Available

| Image | Size | Platform | Tools Status |
|-------|------|----------|--------------|
| `biomate/biotools:arm64` | 8GB | ARM64-native | All tools working |
| `biomate/biotools:comprehensive` | 6.22GB | x86 binaries | Some tools skipped on ARM64 |

### Tools in `biomate/biotools:arm64` (ARM64-Native via Bioconda)

**Aligners:**
- STAR 2.7.11b
- hisat2 2.2.1
- salmon 1.10.3
- kallisto 0.51.1
- minimap2 2.30-r1287
- bwa 0.7.19
- bowtie2 2.5.4

**Variant Calling:**
- samtools 1.22.1
- bcftools (via conda)
- bedtools 2.31.1
- freebayes (via conda)

**QC & Trimming:**
- FastQC 0.12.1
- fastp 1.0.1
- multiqc (via conda)

**Sequence Analysis:**
- seqkit 2.11.0
- mafft 7.526
- HMMER 3.4
- BLAST 2.16.0

**Python Packages:**
- scanpy 1.11.5
- pysam 0.23.3
- pandas 2.3.3
- numpy 2.3.5
- torch 2.9.1+cpu
- biopython 1.86

---

## Configuration

### File Locations

```
/home/yzhang/biomate/backend/config/
├── galaxy.yml          # Main Galaxy config (references job_conf.yml)
└── job_conf.yml        # Job execution configuration
```

### Galaxy Configuration (`galaxy.yml`)

```yaml
galaxy:
  # ... other settings ...

  # Job configuration - use Docker container for tool execution
  job_config_file: config/job_conf.yml
```

---

## Option 1: Docker Mode (Recommended)

### Configuration (`job_conf.yml`)

```yaml
runners:
  local:
    load: galaxy.jobs.runners.local:LocalJobRunner
    workers: 4

execution:
  default: docker_biotools  # Use Docker by default
  environments:
    local:
      runner: local

    docker_biotools:
      runner: local
      docker_enabled: true
      docker_default_container_id: biomate/biotools:arm64
      docker_auto_rm: true
      docker_net: bridge
      docker_volumes: $defaults
      docker_memory: 16G
      docker_run_extra_arguments: --entrypoint /bin/bash

tools:
  - id: .*
    environment: docker_biotools
```

### Pros
- All tools pre-installed and tested
- No host dependency management
- Reproducible across machines
- ARM64-native binaries for Apple Silicon / ARM servers

### Cons
- 8GB image size
- Docker overhead (minimal)
- Need to rebuild image for tool updates

### Running Tools in Docker

```bash
# Interactive shell
docker run -it --entrypoint /bin/bash biomate/biotools:arm64 -c '
  eval "$(micromamba shell hook --shell bash)"
  micromamba activate biotools
  STAR --version
'

# Run a command with mounted data
docker run --rm \
  -v /path/to/data:/data \
  -w /data \
  --entrypoint /bin/bash \
  biomate/biotools:arm64 \
  -c 'eval "$(micromamba shell hook --shell bash)" && micromamba activate biotools && \
      samtools view -bS input.sam > output.bam'
```

---

## Option 2: Host Mode (Local Execution)

### Configuration (`job_conf.yml`)

```yaml
runners:
  local:
    load: galaxy.jobs.runners.local:LocalJobRunner
    workers: 4

execution:
  default: local  # Use local/host by default
  environments:
    local:
      runner: local

tools:
  - id: .*
    environment: local
```

### Installing Tools on Host

#### Method A: Conda Environment

```bash
# Create environment with all bioinformatics tools
conda create -n biotools -c conda-forge -c bioconda -y \
    python=3.11 \
    bwa bowtie2 hisat2 star minimap2 bwa-mem2 \
    salmon kallisto subread stringtie \
    samtools bcftools htslib bedtools vcftools freebayes \
    fastqc multiqc fastp cutadapt trimmomatic \
    seqkit mafft hmmer blast \
    spades kraken2 busco \
    picard gatk4

# Install Python packages
conda activate biotools
pip install scanpy pysam pandas numpy torch biopython \
    gseapy gget pybedtools pybiomart rdkit

# Activate before running Galaxy
conda activate biotools
```

#### Method B: System Packages (Ubuntu/Debian)

```bash
# Core tools via apt
sudo apt-get install -y \
    samtools bcftools bedtools \
    bwa bowtie2 \
    fastqc \
    mafft hmmer

# Tools not in apt - install via conda or from source
conda install -c bioconda star salmon kallisto hisat2 minimap2
```

### Pros
- No Docker overhead
- Faster startup
- Direct filesystem access

### Cons
- Must install and maintain tools manually
- Version conflicts possible
- Not reproducible across machines
- ARM64 compatibility issues (some tools x86-only)

---

## Option 3: Hybrid Mode

Route specific tools to different execution environments:

```yaml
execution:
  default: docker_biotools
  environments:
    local:
      runner: local
    docker_biotools:
      runner: local
      docker_enabled: true
      docker_default_container_id: biomate/biotools:arm64
      docker_auto_rm: true

tools:
  # Python-based tools on host (faster for quick operations)
  - id: gget_.*
    environment: local
  - id: scanpy_.*
    environment: local

  # Heavy CLI tools in Docker (guaranteed to work)
  - id: star_.*
    environment: docker_biotools
  - id: hisat2_.*
    environment: docker_biotools
  - id: salmon_.*
    environment: docker_biotools

  # Default: Docker
  - id: .*
    environment: docker_biotools
```

---

## Testing

### Test Docker Execution

```bash
cd /home/yzhang/biomate/backend
python3 tests/test_docker_biotools.py
```

Expected output:
```
============================================================
BioMate Docker Container Test Suite
Testing: biomate/biotools:arm64
============================================================
Test 1: Checking Docker container exists...
  ✓ Container biomate/biotools:arm64 exists

Test 2: Checking tool availability...
  ✓ STAR: 2.7.11b
  ✓ hisat2: 2.2.1
  ✓ salmon: 1.10.3
  ... (all 13 tools pass)

Total: 5/5 tests passed
✓ All tests passed! Container is ready for Galaxy integration.
```

### Test Host Execution

```bash
# Check if tools are on PATH
which samtools && samtools --version
which STAR && STAR --version
which salmon && salmon --version

# Test Python packages
python3 -c "import scanpy; print(scanpy.__version__)"
```

---

## Quick Reference

### Switch Between Modes

Edit `/home/yzhang/biomate/backend/config/job_conf.yml`:

```yaml
# For Docker execution:
default: docker_biotools

# For host execution:
default: local
```

Then restart Galaxy.

### Build Docker Image

```bash
# ARM64-native (recommended)
cd /home/yzhang/biomate/Biomni/biomni_galaxy/docker
docker build -t biomate/biotools:arm64 -f Dockerfile.arm64 .

# Comprehensive (x86 binaries, some fail on ARM64)
docker build -t biomate/biotools:comprehensive -f Dockerfile.comprehensive .
```

---

## Troubleshooting

### Docker: "Container not found"

```bash
docker images | grep biomate
# If missing, rebuild:
docker build -t biomate/biotools:arm64 -f Dockerfile.arm64 .
```

### Docker: Tool not working

```bash
# Check if tool is in container
docker run --rm --entrypoint /bin/bash biomate/biotools:arm64 -c '
  eval "$(micromamba shell hook --shell bash)"
  micromamba activate biotools
  which STAR
'
```

### Host: "Command not found"

```bash
# Check conda environment is active
conda activate biotools
which STAR

# If not installed, add it
conda install -c bioconda star
```

### ARM64 vs x86 Issues

Some tools have x86-only binaries. Use `biomate/biotools:arm64` which has ARM64-native builds from Bioconda.

---

## Summary

| Mode | Config Setting | Pros | Cons |
|------|---------------|------|------|
| **Docker** | `default: docker_biotools` | All tools included, reproducible | 8GB image |
| **Host** | `default: local` | Faster, no Docker | Must maintain tools |
| **Hybrid** | Tool-specific routing | Best of both | Complex config |

**Recommendation:** Use Docker mode (`biomate/biotools:arm64`) for production to ensure all tools work correctly on ARM64.
