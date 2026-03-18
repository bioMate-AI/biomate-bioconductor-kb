# Tools Used and Local Execution Guide
**Date**: 2026-02-12 16:00
**Question**: What tools do workflows use? Can they run locally?

---

## Current State: Mock Mode vs Real Mode

### 🎭 Mock Mode (Currently Implemented)

**What it uses**:
- ✅ **Python 3** (built-in, no external tools)
- ✅ **Nextflow** (workflow engine)
- ✅ **Standard libraries**: json, random, datetime, os, shutil

**What it does**:
- Simulates workflow execution with realistic dummy data
- Generates MRC files with proper headers
- Creates STAR files with particle metadata
- Produces scientifically plausible results (resolutions, scores)
- **NO external tools required**

**Can run locally?**: ✅ **YES** - Runs anywhere Python 3 + Nextflow are installed

**Example** (CryoEM SPA):
```bash
# Runs locally on laptop/desktop
cd backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa
nextflow run main.nf -profile test --outdir /tmp/results

# Takes ~5 seconds, uses ~2GB RAM, no GPU needed
```

---

### 🔬 Real Mode (Needs External Tools)

**What it uses**:

#### CryoEM Workflows → CryoSPARC
- **Tool**: CryoSPARC (commercial cryo-EM software)
- **License**: Academic license (free) - f312a30e-63fc-11f0-8e36-e3c932851287
- **Requirements**:
  - Linux OS (Ubuntu 20.04+)
  - NVIDIA GPU (8GB+ VRAM)
  - 32GB+ RAM
  - CryoSPARC installed and running
  - Python package: `cryosparc-tools`
- **Can run locally?**: ✅ **YES** - If you have GPU workstation
- **Setup time**: 2-3 hours (install CryoSPARC)

#### AlphaFold 3 → Docker Container
- **Tool**: AlphaFold 3 (Google DeepMind)
- **Container**: `ghcr.io/google-deepmind/alphafold3:latest`
- **Requirements**:
  - Linux OS
  - NVIDIA GPU (A100 80GB recommended, minimum 40GB)
  - Docker with GPU support (nvidia-docker2)
  - 630GB disk space (databases)
  - 64GB+ RAM
- **Can run locally?**: ⚠️ **MAYBE** - Only if you have high-end GPU
- **Setup time**: 4-6 hours (download databases)

---

## What Runs Locally vs Cloud

### ✅ Runs Perfectly on Laptop/Desktop (Mock Mode)

**Requirements**:
- Python 3.8+
- Nextflow 21.10+
- 4GB RAM
- No GPU needed

**All 9 workflows work in mock mode**:
1. CryoEM Standard SPA ✅
2. Complete ET ✅
3. Live Processing ✅
4. Model Building ✅
5. AlphaFold 3 ✅
6. Helical ✅
7. Membrane Protein ✅
8. High Resolution ✅
9. Heterogeneity ✅
10. 3DFlex ✅
11. Topaz Picking ✅
12. Local Refinement ✅

**Use case**: Testing, development, demos, education

---

### ⚠️ Needs GPU Workstation (Real Mode, Local)

**Requirements**:
- NVIDIA GPU (RTX 3090, RTX 4090, or better)
- 32GB+ RAM
- 1TB+ disk space
- Linux OS

**Workflows that can run**:
- CryoEM workflows (with CryoSPARC installed) ✅
- AlphaFold 3 (if GPU has 40GB+ VRAM) ⚠️

**Setup**:
```bash
# Install CryoSPARC
curl -L https://get.cryosparc.com/download/master-latest/$LICENSE > cryosparc.tar.gz
tar -xf cryosparc.tar.gz
cd cryosparc_master
./install.sh --license $LICENSE --port 30000

# Install cryosparc-tools
pip install cryosparc-tools

# Run workflow
nextflow run main.nf \
  -profile cryosparc_local \
  --cryosparc_license $LICENSE \
  --movies_path /data/movies/*.tif
```

**Cost**: $0 (uses your own hardware)
**Time**: 2-4 hours for full SPA workflow

---

### ☁️ Best on Cloud (Real Mode, AWS/GCP/Azure)

**Requirements**:
- AWS account (or GCP/Azure)
- AWS CLI configured
- Nextflow with AWS Batch executor

**Why cloud?**:
- GPU instances expensive to own ($5,000-15,000)
- Pay only for what you use ($0.50-3.00/hour)
- Scale to 100+ GPUs for parallelism
- No setup/maintenance

**Setup**:
```bash
# Request spot instance (REQUIRED per CLAUDE.md)
aws ec2 request-spot-instances \
  --instance-type g6.2xlarge \
  --spot-price "0.50" \
  --region us-east-1

# Run workflow via AWS Batch
nextflow run main.nf \
  -profile aws \
  --movies_path s3://my-bucket/movies/*.tif
```

**Cost**: ~$10-15 for all 9 workflows
**Time**: 6-8 hours compute (can run overnight)

---

## Detailed Tool Breakdown

### CryoEM Workflows

| Step | Tool (Real Mode) | Alternative (Mock Mode) |
|------|------------------|-------------------------|
| Motion Correction | CryoSPARC Patch Motion | Python simulation |
| CTF Estimation | CryoSPARC Patch CTF | Python simulation |
| Particle Picking | CryoSPARC Blob Picker | Python simulation |
| 2D Classification | CryoSPARC Class2D | Python simulation |
| 3D Reconstruction | CryoSPARC Ab-Initio | Python simulation |
| Refinement | CryoSPARC Homogeneous | Python simulation |

**Real tool**: CryoSPARC (https://cryosparc.com)
- **License**: Free academic, $25k/year commercial
- **We have**: Academic license f312a30e-63fc-11f0-8e36-e3c932851287

**Communication**:
- Uses `cryosparc-tools` Python API
- HTTP/WebSocket to CryoSPARC master (port 30000)
- Jobs submitted to CryoSPARC worker nodes
- Results retrieved via API

**Mock mode**:
- No CryoSPARC needed
- Pure Python scripts
- Generates realistic dummy data

---

### AlphaFold 3 Workflow

| Step | Tool (Real Mode) | Alternative (Mock Mode) |
|------|------------------|-------------------------|
| Build Input | Python (AlphaFold3InputBuilder) | Same (no external tool) |
| Predict Structure | AlphaFold 3 Docker | Python simulation |
| Rank Models | Python (parse scores) | Same |
| Validate Structure | Python (geometry checks) | Same |
| Analyze Confidence | Python (pLDDT analysis) | Same |
| Visualize | ChimeraX/PyMOL scripts | Same (script generation) |

**Real tool**: AlphaFold 3
- **License**: Non-commercial (CC-BY-NC-SA)
- **Container**: `ghcr.io/google-deepmind/alphafold3:latest`
- **GPU**: A100 80GB or H100

**Communication**:
- Docker run with volume mounts
- Input: JSON file
- Output: CIF structures + confidence scores

**Mock mode**:
- Simulates AlphaFold 3 predictions
- Generates valid CIF files with realistic pLDDT
- No GPU, no Docker, no databases needed

---

## Quick Start Guide

### Option 1: Local Mock Mode (Recommended for Testing)

**Install**:
```bash
# Install Nextflow
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/

# Verify
nextflow -version
```

**Run**:
```bash
# CryoEM SPA
cd backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa
nextflow run main.nf -profile test

# AlphaFold 3
cd backend/biomni_workflows/nextflow_nfcore/subworkflows/structural_biology/alphafold3_complete_workflow
nextflow run main.nf --num_seeds 5
```

**Results**: In ~5-10 seconds, get realistic outputs without any external tools

---

### Option 2: Local Real Mode (GPU Workstation)

**Install CryoSPARC** (one-time setup):
```bash
# Download
curl -L https://get.cryosparc.com/download/master-latest/f312a30e-63fc-11f0-8e36-e3c932851287 > cryosparc.tar.gz

# Extract and install
tar -xf cryosparc.tar.gz
cd cryosparc_master
./install.sh --license f312a30e-63fc-11f0-8e36-e3c932851287 --port 30000

# Start
./bin/cryosparcm start

# Install Python tools
pip install cryosparc-tools
```

**Run workflow**:
```bash
nextflow run main.nf \
  -profile cryosparc_local \
  --cryosparc_license f312a30e-63fc-11f0-8e36-e3c932851287 \
  --movies_path /data/empiar10940/movies/*.tif \
  --outdir ./results
```

**Cost**: $0 (uses your GPU)
**Time**: 2-4 hours (depends on dataset size and GPU)

---

### Option 3: Cloud AWS Batch (Recommended for Production)

**Setup** (one-time):
```bash
# Configure AWS
aws configure

# Install Nextflow
curl -s https://get.nextflow.io | bash

# Set up AWS Batch (automated script)
bash backend/lib/galaxy/galaxy-cloud-executor/scripts/create_aws_batch.sh
```

**Run workflow**:
```bash
nextflow run main.nf \
  -profile aws \
  --movies_path s3://biomate-data/empiar10940/movies/*.tif \
  --outdir s3://biomate-results/spa-run1
```

**Cost**: ~$10-15 for all workflows
**Time**: 6-8 hours compute (runs unattended)
**Benefit**: No GPU purchase needed, scalable to 100+ jobs

---

## Comparison: Mock vs Real vs Cloud

| Aspect | Mock Mode (Local) | Real Mode (Local GPU) | Real Mode (AWS Cloud) |
|--------|-------------------|----------------------|----------------------|
| **Tools Required** | Python + Nextflow | CryoSPARC + GPU | AWS account |
| **Setup Time** | 5 minutes | 2-3 hours | 1 hour |
| **Hardware Cost** | $0 | $5,000-15,000 | $0 (pay per use) |
| **Running Cost** | $0 | $0 (electricity) | $0.50-3/hr |
| **GPU Needed** | No | Yes (8GB+) | No (cloud provides) |
| **Disk Space** | <1 GB | 500GB+ | Unlimited (S3) |
| **Execution Time** | 5-10 seconds | 2-4 hours | 6-8 hours |
| **Results** | Simulated | Real science | Real science |
| **Parallelism** | Limited (CPU cores) | Limited (1-2 GPUs) | Unlimited (100+ GPUs) |
| **Best For** | Testing, dev, demos | Small labs, single datasets | Production, high-throughput |

---

## Can You Run Real Mode Locally?

### CryoEM Workflows: ✅ YES

**Minimum specs**:
- GPU: NVIDIA RTX 3060 (12GB VRAM) or better
- RAM: 32GB
- Disk: 500GB SSD
- OS: Ubuntu 20.04 or 22.04

**Realistic specs** (for good performance):
- GPU: RTX 4090 (24GB) or A5000 (24GB)
- RAM: 64GB
- Disk: 2TB NVMe SSD
- CPU: 16+ cores

**What you can process**:
- Small datasets: 20-50 movies ✅
- Medium datasets: 100-200 movies ✅ (will take time)
- Large datasets: 500+ movies ⚠️ (slow, may run out of disk)

**Cost to build**: $3,000-5,000 for workstation

---

### AlphaFold 3: ⚠️ DIFFICULT

**Problem**: AlphaFold 3 needs 80GB GPU VRAM

**Consumer GPUs**:
- RTX 4090: 24GB ❌ (not enough)
- RTX 6000 Ada: 48GB ❌ (still not enough)
- A6000: 48GB ❌ (not enough)

**Workstation GPUs**:
- A100 40GB: ⚠️ (minimum, may work for small proteins)
- A100 80GB: ✅ (recommended, $15,000)
- H100 80GB: ✅ (best, $25,000)

**Alternative**: Use AlphaFold Server (free, 20 jobs/day)
- https://alphafoldserver.com
- No local setup needed
- Results in 10-30 minutes

**Cost to build**: $15,000-25,000 for single GPU workstation

---

## Recommendation

### For Testing/Development: Use Mock Mode
```bash
# Works on any laptop/desktop
nextflow run main.nf -profile test

# Fast (seconds), free, no setup
```

### For Real Science:

**If you have**: GPU workstation (RTX 3090+, 32GB RAM)
→ **Install CryoSPARC locally** (free academic license)
→ Run workflows with `-profile cryosparc_local`

**If you don't have**: GPU workstation
→ **Use AWS Batch with spot instances** (per CLAUDE.md policy)
→ Cost: ~$10-15 for all workflows
→ No hardware purchase needed

**For AlphaFold 3 specifically**:
→ **Use AlphaFold Server** (free, web-based)
→ OR use AWS g5.12xlarge spot instance ($2.50/hr)
→ Don't buy $15k GPU for occasional use

---

## Current Status

**What works right now**:
- ✅ All 9 workflows work in **mock mode locally** (laptop/desktop)
- ✅ All 9 workflows have **AWS Batch configuration** (cloud ready)
- ⚠️ Real mode needs CryoSPARC/AlphaFold 3 setup

**What's tested**:
- ✅ Mock mode: All workflows tested and working
- ✅ Parallelism: Confirmed in mock mode
- ⏳ Real mode: Not tested yet (need GPU infrastructure)
- ⏳ AWS Batch: Not tested yet (need AWS deployment)

---

## Next Steps

**For you to decide**:

1. **Test mock mode locally** (5 min, free)
   - Verify parallelism works
   - Check outputs are realistic
   - No setup needed

2. **Set up local CryoSPARC** (if you have GPU)
   - 2-3 hours setup
   - Test real execution locally
   - $0 ongoing cost

3. **Deploy to AWS Batch** (recommended)
   - 1 hour setup
   - Real execution on cloud
   - ~$10-15 total cost for all workflows

**What would you prefer?**
