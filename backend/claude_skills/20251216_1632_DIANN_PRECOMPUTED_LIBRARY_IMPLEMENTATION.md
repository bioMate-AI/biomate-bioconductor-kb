# DIA-NN Pre-computed Spectral Library - Implementation Summary

**Date**: 2025-12-16 (Updated: 2025-12-16 19:15)
**Status**: Implementation complete, ready for spectral library generation

---

## Overview

Implemented a pre-computed spectral library system for DIA-NN to reduce analysis time from **2 days to 2-4 hours**.

## S3 Data Status

**S3 Bucket**: `s3://knowledge-datasets-1759951976/`

### Available FASTA Files (Ready)
```
uniprot/uniprot_sprot_human.fasta.gz  (7.7 MB)
uniprot/uniprot_sprot_mouse.fasta.gz  (8.0 MB)
uniprot/uniprot_sprot_rat.fasta.gz    (7.9 MB)
```

### Spectral Libraries (Pending Generation)
```
spectral_libraries/human/human_swissprot.speclib         ✗ PENDING
spectral_libraries/human/human_swissprot_phospho.speclib ✗ PENDING
spectral_libraries/mouse/mouse_swissprot.speclib         ✗ PENDING
spectral_libraries/rat/rat_swissprot.speclib             ✗ PENDING
```

---

## Files Created

### 1. Library Registry
**Path**: `/home/yzhang/biomate/backend/lib/galaxy/ai/spectral_libraries/library_registry.json`

Contains metadata for all available pre-computed libraries:
- Human (reviewed, phospho)
- Mouse (reviewed)
- Rat (reviewed)
- MetaboAnalyst MS2 databases (for metabolomics)

### 2. Python Library Manager
**Path**: `/home/yzhang/biomate/backend/lib/galaxy/ai/spectral_libraries/library_manager.py`

Features:
- List available libraries
- Check S3 availability status
- Download with progress tracking
- Local caching
- MD5 validation
- Compatibility checking
- CLI interface

Usage:
```bash
cd /home/yzhang/biomate/backend/lib/galaxy/ai/spectral_libraries

# List libraries
python3 library_manager.py list

# Check availability status
python3 library_manager.py status

# Get info
python3 library_manager.py info human --variant reviewed

# Download (once libraries are generated)
python3 library_manager.py download human --variant reviewed
```

### 3. Spectral Library Generation Script
**Path**: `/home/yzhang/biomate/backend/lib/galaxy/ai/spectral_libraries/generate_speclib.sh`

Usage:
```bash
# Generate human SwissProt library (~24-48 hours)
./generate_speclib.sh human reviewed

# Generate human phospho library (~24-48 hours)
./generate_speclib.sh human phospho

# Generate mouse library
./generate_speclib.sh mouse reviewed

# Generate all libraries
./generate_speclib.sh all
```

Environment variables:
- `THREADS=16` - Number of CPU threads (default: 16)

### 4. Nextflow Download Module
**Path**: `/home/yzhang/biomate/backend/nf-core-modules/modules/local/spectral_library/main.nf`

Processes:
- `DOWNLOAD_SPECTRAL_LIBRARY` - Downloads pre-computed library
- `CHECK_PRECOMPUTED_LIBRARY` - Checks if compatible library exists
- `GENERATE_SPECTRAL_LIBRARY` - Fallback generation from FASTA

### 5. Smart Subworkflow
**Path**: `/home/yzhang/biomate/backend/nf-core-modules/subworkflows/local/smart_spectral_library/main.nf`

Workflow: `SMART_SPECTRAL_LIBRARY`
- Automatically decides between download vs generate
- Supports user-provided library path
- Falls back to generation if no pre-computed available

### 6. Configuration
**Path**: `/home/yzhang/biomate/backend/nf-core-modules/subworkflows/local/smart_spectral_library/nextflow.config`

New parameters:
```groovy
params.organism = null                    // "human", "mouse", "rat"
params.speclib_variant = "reviewed"       // "reviewed", "phospho"
params.precomputed_speclib = null         // User-provided path
params.force_generate_speclib = false     // Force generation
params.spectral_library_base_url = "https://knowledge-datasets-1759951976.s3.amazonaws.com"
```

---

## Available Libraries

| Organism | Variant | Proteins | Estimated Size | Status |
|----------|---------|----------|----------------|--------|
| Human | reviewed | 20,428 | ~2.6 GB | ⏳ Pending |
| Human | phospho | 20,428 | ~8.6 GB | ⏳ Pending |
| Mouse | reviewed | 17,171 | ~2.2 GB | ⏳ Pending |
| Rat | reviewed | 8,000 | ~1.1 GB | ⏳ Pending |

---

## Time Comparison

| Step | Without Pre-computed | With Pre-computed |
|------|---------------------|-------------------|
| Library generation | 24-48 hours | 0 (skipped) |
| Library download | 0 | 5-10 minutes |
| DIA-NN analysis | 2-4 hours | 2-4 hours |
| **Total** | **26-52 hours** | **2-4 hours** |

**Speedup: 10-20x faster**

---

## Next Steps

### Step 1: Generate Spectral Libraries (One-time, ~24-48h each)

Run on a machine with sufficient resources (16+ CPU cores, 32GB+ RAM):

```bash
cd /home/yzhang/biomate/backend/lib/galaxy/ai/spectral_libraries

# Generate human library first (most commonly used)
THREADS=16 ./generate_speclib.sh human reviewed

# Then generate other libraries
./generate_speclib.sh mouse reviewed
./generate_speclib.sh rat reviewed
./generate_speclib.sh human phospho
```

The script will:
1. Download FASTA from S3
2. Run DIA-NN in Docker to generate .speclib
3. Upload results to S3
4. Create metadata JSON files

### Step 2: Verify Upload

```bash
python3 library_manager.py status
```

### Step 3: Update Registry

After generation, update `library_registry.json` with:
- Actual file sizes
- MD5 checksums
- Generation dates

---

## MetaboAnalyst Databases (For Metabolomics)

The S3 bucket also contains MetaboAnalyst MS2 databases for metabolomics workflows:

| Database | Size |
|----------|------|
| Pathway Library | 39 MB |
| Biological Library | 207 MB |
| Lipids Library | 308 MB |
| Exposomics Library | 403 MB |
| FragsAnnotateDB | 335 MB |

**Note**: These are for metabolomics (small molecule identification), NOT proteomics/DIA-NN.

---

## Directory Structure

```
backend/
├── lib/galaxy/ai/spectral_libraries/
│   ├── __init__.py              # Python package
│   ├── library_registry.json    # Library metadata + S3 paths
│   ├── library_manager.py       # Python management tool
│   └── generate_speclib.sh      # Library generation script
│
├── nf-core-modules/
│   ├── modules/local/spectral_library/
│   │   └── main.nf              # Download/generate modules
│   │
│   └── subworkflows/local/smart_spectral_library/
│       ├── main.nf              # Smart selection workflow
│       └── nextflow.config      # Configuration
│
└── claude_skills/
    ├── 20251205_1526_DIANN_SPEEDUP_INTEGRATION_PLAN.md
    ├── 20251205_1609_DIANN_PRECOMPUTED_LIBRARY_EXPLAINED.md
    └── 20251216_1632_DIANN_PRECOMPUTED_LIBRARY_IMPLEMENTATION.md  # This file
```

---

## Quick Start Guide

### For Users (After Libraries Are Generated)

```bash
# Check what's available
python3 library_manager.py status

# Download human library to local cache
python3 library_manager.py download human --variant reviewed
# Downloaded to: ~/.biomate/spectral_libraries/human/human_swissprot.speclib

# Use in Nextflow pipeline
nextflow run nf-core/quantms \
    --input samples.csv \
    --database uniprot_human.fasta \
    --organism human \
    -profile docker
```

### For Administrators (Library Generation)

```bash
# Check current status
python3 library_manager.py status

# Generate libraries (one-time, takes 24-48h each)
./generate_speclib.sh human reviewed
./generate_speclib.sh mouse reviewed

# Verify upload
aws s3 ls s3://knowledge-datasets-1759951976/spectral_libraries/
```
