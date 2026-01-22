# Biomate AI Tools Knowledge Base
**Generated: 2026-01-21**
**Last Updated: 2026-01-21**

This document contains all gathered knowledge about the 14 cutting-edge bioinformatics tools integrated into Biomate.

---

## Quick Start

```bash
# Set up environment
source /home/yzhang/biomate/backend/tools/biomate_ai_tools/setup_env.sh

# Activate virtual environment for local tools
source /home/yzhang/biomate/backend/tools/biomate_ai_tools/.venv/bin/activate

# Set Gemini API key for SynCraft
export GEMINI_API_KEY='your-key-here'

# Download models for local tools
python /home/yzhang/biomate/backend/tools/biomate_ai_tools/scripts/download_models.py --list
python download_models.py --tool profam   # ~1.5 GB
python download_models.py --tool state    # ~28 GB
```

## Installation Status (2026-01-21)

| Tool | Type | Status | Size | Notes |
|------|------|--------|------|-------|
| ESMFold | API | ✅ Ready | N/A | FREE, no key needed |
| AlphaFold DB | API | ✅ Ready | N/A | FREE, 200M+ structures |
| AlphaFold 3 Server | API | ✅ Ready | N/A | FREE, 20 jobs/day |
| SynCraft | API | ✅ Ready | N/A | Needs GEMINI_API_KEY |
| ProTrek | Web | ✅ Ready | N/A | Web interface only |
| DrugCLIP | Web | ✅ Ready | N/A | Web interface only |
| **ProFam-1** | **Local** | **✅ Installed** | **1.5 GB** | Model downloaded, CLI working |
| **STATE** | **Local** | **✅ Installed** | **28 GB** | SE-600M model, CLI working |
| GenMol | Local | ⏳ Pending | ~5 GB | Not yet downloaded |
| MAMMAL | Local | ⏳ Pending | ~9 GB | Not yet downloaded |
| OmniGenome | Local | ⏳ Pending | ~15 GB | Not yet downloaded |
| scFv-pMPNN | Local | ⏳ Pending | ~23 GB | Not yet downloaded |
| Cambrian-1 | Local | ⏳ Pending | ~23 GB | Not yet downloaded |
| Chai-1 | Local | ⏳ Pending | ~30 GB | Not yet downloaded |
| Boltz-2 | **HOLD** | ❌ Too large | ~103 GB | Exceeds GB10 capacity |
| Evo 2 40B | **HOLD** | ❌ Too large | ~100 GB | Blackwell accuracy issue |
| AlphaFold 3 local | **HOLD** | ❌ Too large | ~1 TB | Use server instead |

**Virtual Environment**: `/home/yzhang/biomate/backend/tools/biomate_ai_tools/.venv/`
**Models Directory**: `/home/yzhang/biomate/models/`

---

## API Test Results (2026-01-21)

| Tool | API Status | Test Result |
|------|------------|-------------|
| ESMFold | ✅ Working | Predicted 51-residue structure |
| AlphaFold DB | ✅ Working | Retrieved P69905 (pLDDT 98.06) |
| AlphaFold 3 Server | ✅ Available | 20 jobs/day at alphafoldserver.com |
| ProTrek | ⚠️ Web only | Use search-protrek.com |
| DrugCLIP | ⚠️ Web only | Use drugclip.com |
| SynCraft | ✅ Ready | Requires GEMINI_API_KEY |

---

## Hardware Available

**NVIDIA GB10 (Project DIGITS / Grace Blackwell)**
- Unified Memory: **~120 GB** shared between CPU and GPU
- Architecture: Blackwell
- CUDA Version: 13.0
- Driver: 580.95.05

**Important Compatibility Notes:**
- Evo 2 40B reports "low accuracy on Blackwell hardware" - may need API fallback
- AlphaFold 3 officially supports only A100/H100 - needs testing on GB10

---

## Source Code Repositories

All tool repositories cloned to: `/home/yzhang/biomate/tools_repos/`

```
tools_repos/
├── alphafold3/     # google-deepmind/alphafold3
├── boltz/          # jwohlwend/boltz
├── chai-lab/       # chaidiscovery/chai-lab
├── DrugCLIP/       # bowen-gao/DrugCLIP
├── evo2/           # ArcInstitute/evo2
├── profam/         # alex-hh/profam
├── ProTrek/        # westlake-repl/ProTrek
├── scFv_Pmpnn_AF2/ # jbderoo/scFv_Pmpnn_AF2
├── state/          # ArcInstitute/state
└── syncraft/       # catalystforyou/SynCraft-Core
```

---

## Table of Contents
1. [Structure Prediction Tools](#structure-prediction-tools)
2. [Genomics/DNA Tools](#genomicsdna-tools)
3. [Drug Discovery Tools](#drug-discovery-tools)
4. [Single Cell Analysis Tools](#single-cell-analysis-tools)
5. [Protein Analysis Tools](#protein-analysis-tools)
6. [Protein Design Tools](#protein-design-tools)
7. [Size & Resource Summary](#size--resource-summary)

---

## Structure Prediction Tools

### 1. Boltz-2
- **Version**: latest
- **GitHub**: https://github.com/jwohlwend/boltz
- **License**: MIT (fully open for commercial use)
- **Category**: Structure Prediction
- **Local Repo**: `/home/yzhang/biomate/tools_repos/boltz/`

**Description**: Biomolecular foundation model for predicting structures of proteins, RNA, DNA, ligands, and binding affinities. Claims to be 1000x faster than physics-based FEP methods.

**Capabilities**:
- Protein structure prediction
- RNA/DNA structure prediction
- Ligand binding prediction
- Binding affinity estimation

**Resource Requirements** (from NVIDIA NIM & official docs):
- **Minimum GPU**: 48 GB VRAM (NVIDIA NIM requirement)
- **Recommended**: A100 80GB, H100 80GB, or L40S 48GB
- **24 GB GPU (RTX 4090)**: Limited to ~1,300-1,600 tokens
- **Disk Space**: ~12 GB for model weights
- **CPU-only**: Not recommended (very slow)

**Token Limits by GPU**:
| GPU VRAM | Max Tokens |
|----------|------------|
| 24 GB | ~1,300 tokens |
| 48 GB | ~2,500 tokens |
| 80 GB | Full capacity |

**GB10 Compatibility**: **Yes** - 120GB unified memory exceeds requirements

**Galaxy Wrapper**: `boltz2.xml`
**Docker Image**: `ghcr.io/biomate/boltz2:1.0`

**Sources**:
- [NVIDIA NIM Boltz2 Support Matrix](https://docs.nvidia.com/nim/bionemo/boltz2/latest/support-matrix.html)
- [LMI4Boltz Paper](https://www.biorxiv.org/content/10.1101/2025.10.29.684571v2.full)

---

### 2. Chai-1
- **Version**: 0.6.1
- **GitHub**: https://github.com/chaidiscovery/chai-lab
- **License**: Apache 2.0 (commercial use allowed)
- **Category**: Structure Prediction
- **Local Repo**: `/home/yzhang/biomate/tools_repos/chai-lab/`

**Description**: Multi-modal foundation model for molecular structure prediction. Achieves state-of-the-art accuracy for proteins, small molecules, DNA, RNA, glycosylations, and ligand complexes.

**Capabilities**:
- Protein structure prediction
- Protein-ligand complex prediction
- DNA/RNA structure prediction
- Multi-chain complex prediction

**Resource Requirements** (from official README):
- **Recommended**: A100 80GB or H100 80GB or L40S 48GB
- **A100 40GB**: Up to ~1,550 amino acids
- **RTX 4090 (24GB)**: Smaller complexes only
- **A10/A30**: Smaller complexes
- **Disk Space**: ~15 GB for model weights
- **CPU-only**: Not supported

**Token Limits by GPU** (from GitHub issues):
| GPU | VRAM | Max Sequence |
|-----|------|--------------|
| A100/H100 | 80 GB | Full 2,048 tokens |
| L40S | 48 GB | ~1,800 tokens |
| A100 | 40 GB | ~1,550 amino acids |
| RTX 4090 | 24 GB | Small complexes |

**GB10 Compatibility**: **Yes** - 120GB exceeds 80GB recommendation

**API Alternative**: BioLM API (https://biolm.ai)
- No local GPU required
- Pay-per-prediction pricing
- API Key: `BIOLM_API_KEY` environment variable

**Galaxy Wrappers**:
- `chai1.xml` (local, recommended for GB10)
- `chai1_api.xml` (API fallback)
- Docker: `ghcr.io/biomate/chai1:0.6.1`

**Sources**:
- [Chai-1 GitHub README](https://github.com/chaidiscovery/chai-lab)
- [GitHub Issue #17 - Memory](https://github.com/chaidiscovery/chai-lab/issues/17)

---

### 3. AlphaFold 3
- **Version**: 3.0.0
- **GitHub**: https://github.com/google-deepmind/alphafold3
- **License**: CC-BY-NC-SA (Non-commercial only)
- **Category**: Structure Prediction
- **Local Repo**: `/home/yzhang/biomate/tools_repos/alphafold3/`

**Description**: DeepMind's latest model for predicting structures of biomolecular complexes with proteins, DNA, RNA, ligands, and ions. 50%+ improvement over AlphaFold 2.

**Capabilities**:
- Protein structure prediction
- Protein-DNA complexes
- Protein-RNA complexes
- Protein-ligand complexes
- Ion binding prediction

**Resource Requirements** (from official docs):
- **Officially Supported**: NVIDIA A100 80GB and H100 80GB **ONLY**
- **Minimum**: Compute Capability 8.0+ (Ampere or newer)
- **Disk Space**: Up to 1 TB for genetic databases (SSD recommended)
- **RAM**: 32 GB minimum
- **CUDA**: 12.3+ (12.6 preferred)

**Token Limits by GPU**:
| GPU | VRAM | Max Tokens |
|-----|------|------------|
| A100/H100 | 80 GB | 5,120 tokens |
| A100 | 40 GB | 4,352 tokens (unified memory) |
| V100 | 32 GB | 1,280 tokens (unified memory) |
| P100 | 16 GB | 1,024 tokens |

**GB10 Compatibility**: **Unknown** - Not officially supported, needs testing
- GB10 has 120GB unified memory which exceeds requirements
- But only A100/H100 officially tested

**API Alternative**: AlphaFold Server (https://alphafoldserver.com)
- Free to use, 20 jobs per day limit
- No API key required

**Alternative**: AlphaFold Database API (EBI)
- 200M+ pre-computed structures
- No GPU needed, instant access

**Galaxy Wrappers**:
- `alphafold3.xml` (local, needs testing on GB10)
- `alphafold_api.xml` (EBI Database for pre-computed structures)

**Sources**:
- [AlphaFold 3 Installation Guide](https://github.com/google-deepmind/alphafold3/blob/main/docs/installation.md)
- [AlphaFold 3 Performance](https://github.com/google-deepmind/alphafold3/blob/main/docs/performance.md)

---

## Genomics/DNA Tools

### 4. Evo 2
- **Version**: 40B (also available: 7B, 1B)
- **GitHub**: https://github.com/ArcInstitute/evo2
- **License**: Apache 2.0
- **Category**: Genomics
- **Local Repo**: `/home/yzhang/biomate/tools_repos/evo2/`

**Description**: 40 billion parameter DNA foundation model trained on 9 trillion nucleotides from 100,000+ species. Supports 1 million base pair context length for genome-scale predictions.

**Capabilities**:
- DNA sequence generation
- Variant effect prediction
- Regulatory element identification
- Cross-species genomic analysis

**Resource Requirements** (from official README):

**CRITICAL WARNING**:
> "The 40B and 1B models require FP8 for numerical accuracy, and **low accuracy has been reported on Blackwell hardware** or without FP8."

- **40B Model**: Requires **multiple GPUs** (Vortex auto-splits across devices)
- **7B Model**: Single GPU, can run without FP8
- **Hardware**: Compute Capability 8.9+ (Ada/Hopper) for FP8
- **Software**: CUDA 12.1+, Python 3.12

**Model Variants**:
| Model | Parameters | Context | GPUs Needed |
|-------|------------|---------|-------------|
| evo2_40b | 40B | 1M bp | Multiple |
| evo2_7b | 7B | 1M bp | Single |
| evo2_1b_base | 1B | 8K bp | Single |

**GB10 Compatibility**: **PROBLEMATIC**
- GB10 is Blackwell architecture
- Official docs warn of "low accuracy on Blackwell hardware"
- Recommend using **evo2_7b** or **API** instead

**API Alternative**: NVIDIA NIM API (Recommended for GB10)
- URL: https://build.nvidia.com/arcinstitute/evo-2-40b
- API Key: `NVIDIA_API_KEY` environment variable

**Galaxy Wrappers**:
- `evo2.xml` (local - use 7B model on GB10)
- `evo2_api.xml` (API - recommended for 40B on GB10)

**Sources**:
- [Evo 2 GitHub README](https://github.com/ArcInstitute/evo2)
- [NVIDIA NIM Evo 2](https://build.nvidia.com/arcinstitute/evo-2-40b)

---

### 5. OmniGenome
- **Version**: 1.0
- **GitHub**: (Research tool)
- **Category**: Genomics

**Description**: Multi-task genomic foundation model for sequence analysis including promoter prediction, splice site detection, and variant effect prediction.

**Capabilities**:
- Promoter prediction
- Splice site prediction
- Enhancer prediction
- Conservation scoring
- Variant effect prediction

**Resource Requirements** (estimated):
- **Model Size**: ~1-3B parameters
- **GPU Memory**: 16-24 GB
- **Disk Space**: ~10 GB
- **CPU-only**: Possible but slow

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `omnigenome.xml`
**Docker Image**: `ghcr.io/biomate/omnigenome:1.0`

---

### 6. MAMMAL
- **Version**: 1.0
- **GitHub**: (Research tool)
- **Category**: Genomics

**Description**: Multi-species genomic analysis and annotation tool for mammalian genomes.

**Capabilities**:
- Gene prediction
- Regulatory element prediction
- Cross-species conservation
- Functional annotation

**Resource Requirements** (estimated):
- **Model Size**: ~500M-1B parameters
- **GPU Memory**: 8-16 GB
- **Disk Space**: ~5 GB
- **CPU-only**: Possible

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `mammal.xml`
**Docker Image**: `ghcr.io/biomate/mammal:1.0`

---

## Drug Discovery Tools

### 7. DrugCLIP
- **Version**: 1.0.0
- **GitHub**: https://github.com/bowen-gao/DrugCLIP
- **License**: Research
- **Category**: Drug Discovery
- **Local Repo**: `/home/yzhang/biomate/tools_repos/DrugCLIP/`

**Description**: Contrastive learning framework for virtual screening that is 10 million times faster than traditional docking methods. Published in Science 2026. Screened 10K proteins × 500M compounds.

**Capabilities**:
- Ultra-fast virtual screening
- Protein-ligand matching
- Hit identification
- Lead optimization support

**Resource Requirements** (estimated):
- **Model Size**: ~300M parameters
- **GPU Memory**: 8-16 GB
- **Disk Space**: ~2 GB
- **CPU-only**: Possible (still fast)

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `drugclip.xml`
**Docker Image**: `ghcr.io/biomate/drugclip:1.0`

---

### 8. SynCraft
- **Version**: 1.0.0
- **GitHub**: https://github.com/catalystforyou/SynCraft-Core
- **Category**: Drug Discovery
- **Local Repo**: `/home/yzhang/biomate/tools_repos/syncraft/`

**Description**: LLM-guided framework for molecular synthesizability optimization using Chain-of-Thought prompting with Gemini-2.5-Pro. Predicts atom-level edits (DEL_ATOM, ADD_BOND, DEL_BOND, CHANGE_BOND).

**Capabilities**:
- Retrosynthesis planning
- Synthesis route optimization
- Atom-level reaction prediction
- Multi-step synthesis design

**Resource Requirements**:
- **Model Size**: Uses external LLM (Gemini)
- **GPU Memory**: Minimal (API-based)
- **Disk Space**: ~1 GB
- **CPU-only**: Yes (uses API)
- **Requires**: `GEMINI_API_KEY`

**GB10 Compatibility**: **Yes** (API-based)

**Galaxy Wrapper**: `syncraft.xml`
**Docker Image**: `ghcr.io/biomate/syncraft:1.0`

---

### 9. GenMol
- **Version**: 1.0
- **Category**: Drug Discovery

**Description**: Generative molecular design using diffusion models for creating novel drug-like molecules.

**Capabilities**:
- Unconditional molecule generation
- Property-guided generation
- Scaffold-based generation
- Lead optimization

**Resource Requirements** (estimated):
- **Model Size**: ~100-500M parameters
- **GPU Memory**: 8-16 GB
- **Disk Space**: ~3 GB
- **CPU-only**: Possible but slow

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `genmol.xml`
**Docker Image**: `ghcr.io/biomate/genmol:1.0`

---

## Single Cell Analysis Tools

### 10. STATE
- **Version**: 1.0.0
- **GitHub**: https://github.com/ArcInstitute/state
- **License**: Apache 2.0
- **Category**: Single Cell Analysis
- **Local Repo**: `/home/yzhang/biomate/tools_repos/state/`

**Description**: Arc Institute's virtual cell model for predicting cellular perturbation responses. Uses State Embedding (SE) for transcriptome vectorization and State Transition (ST) for response prediction. Trained on 270M+ cells including Tahoe-100M dataset.

**Capabilities**:
- Cell state embedding (SE-600M model)
- Perturbation response prediction
- Drug response prediction
- Cell type classification

**Resource Requirements**:
- **Model Size**: 600M parameters (SE-600M)
- **GPU Memory**: 8-16 GB
- **Disk Space**: ~3 GB
- **CPU-only**: Possible but slow

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `state.xml`
**Docker Image**: `ghcr.io/biomate/state:1.0`

---

## Protein Analysis Tools

### 11. ProTrek
- **Version**: 650M
- **GitHub**: https://github.com/westlake-repl/ProTrek
- **License**: Research
- **Category**: Protein Analysis
- **Local Repo**: `/home/yzhang/biomate/tools_repos/ProTrek/`

**Description**: Trimodal protein language model unifying sequence, structure, and function through contrastive learning. Enables advanced protein searches across 5B+ proteins. Published in Nature Biotechnology 2025.

**Capabilities**:
- Protein function search
- Sequence similarity search
- Structure-based search
- Multi-modal protein understanding

**Resource Requirements**:
- **Model Size**: 650M parameters
- **GPU Memory**: 8-12 GB
- **Disk Space**: ~3 GB
- **CPU-only**: Possible

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `protrek.xml`
**Docker Image**: `ghcr.io/biomate/protrek:1.0`

---

### 12. ProFam-1
- **Version**: 1.0.0
- **GitHub**: https://github.com/alex-hh/profam
- **Category**: Protein Analysis
- **Local Repo**: `/home/yzhang/biomate/tools_repos/profam/`

**Description**: 251M parameter autoregressive protein family language model for fitness prediction. Achieves state-of-the-art on ProteinGym benchmark (0.47 substitutions, 0.53 indels) without requiring MSA at inference.

**Capabilities**:
- Protein family classification
- Fitness prediction
- Mutation effect prediction
- No MSA required at inference

**Resource Requirements**:
- **Model Size**: 251M parameters
- **GPU Memory**: 4-8 GB
- **Disk Space**: ~1 GB
- **CPU-only**: Yes (reasonable speed)

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `profam.xml`
**Docker Image**: `ghcr.io/biomate/profam:1.0`

---

## Protein Design Tools

### 13. scFv-pMPNN-AF2
- **Version**: 1.0.0
- **GitHub**: https://github.com/jbderoo/scFv_Pmpnn_AF2
- **Category**: Protein Design
- **Local Repo**: `/home/yzhang/biomate/tools_repos/scFv_Pmpnn_AF2/`

**Description**: AI pipeline integrating AlphaFold2 and ProteinMPNN for converting antibodies to functional scFv intrabodies. Achieves 73% success rate compared to 31% with standard methods. Published in Science Advances 2026.

**Capabilities**:
- Antibody to scFv conversion
- CDR loop optimization
- Framework region design
- Humanization support

**Resource Requirements**:
- **Model Size**: Uses ProteinMPNN (~100M) + AF2 (~3B)
- **GPU Memory**: 16-24 GB (for AF2 component)
- **Disk Space**: ~15 GB
- **CPU-only**: ProteinMPNN only (slow)

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `scfv_pmpnn.xml`
**Docker Image**: `ghcr.io/biomate/scfv-pmpnn:1.0`

---

## Image Analysis Tools

### 14. Cambrian-1
- **Version**: 1.0
- **GitHub**: (Vision-language model)
- **Category**: Biological Image Analysis

**Description**: Vision-language model trained on biological images for automated image analysis of microscopy, gels, western blots, and histopathology.

**Capabilities**:
- Image description generation
- Object/cell counting
- Region segmentation
- Image classification
- Visual question answering

**Resource Requirements** (estimated):
- **Model Size**: ~7-13B parameters
- **GPU Memory**: 16-24 GB
- **Disk Space**: ~15 GB
- **CPU-only**: Not practical

**GB10 Compatibility**: **Yes**

**Galaxy Wrapper**: `cambrian1.xml`
**Docker Image**: `ghcr.io/biomate/cambrian1:1.0`

---

## Size & Resource Summary

### CORRECTED Requirements (from official sources)

| Tool | Official VRAM | Docker Image | Model Weights | Total Disk |
|------|---------------|--------------|---------------|------------|
| ProFam-1 | 4-8 GB | ~2 GB | ~1 GB | ~3 GB |
| DrugCLIP | 8-16 GB | ~3 GB | ~2 GB | ~5 GB |
| STATE | 8-16 GB | ~4 GB | ~3 GB | ~7 GB |
| ProTrek | 8-12 GB | ~4 GB | ~3 GB | ~7 GB |
| GenMol | 8-16 GB | ~3 GB | ~2 GB | ~5 GB |
| MAMMAL | 8-16 GB | ~4 GB | ~5 GB | ~9 GB |
| OmniGenome | 16-24 GB | ~5 GB | ~10 GB | ~15 GB |
| scFv-pMPNN | 16-24 GB | ~8 GB | ~15 GB | ~23 GB |
| Cambrian-1 | 16-24 GB | ~8 GB | ~15 GB | ~23 GB |
| **Boltz-2** | **48+ GB** | **~73 GB** | **~30 GB** | **~103 GB** |
| **Chai-1** | **40-80 GB** | **~15 GB** | **~15 GB** | **~30 GB** |
| **Evo 2 40B** | **Multiple GPUs** | **~20 GB** | **~80 GB** | **~100 GB** |
| **AlphaFold 3** | **80 GB** | **~5 GB** | **~1 TB** (databases) | **~1 TB** |

### GB10 Compatibility

| Tool | Runs on GB10? | Notes |
|------|---------------|-------|
| ProFam-1 | **Yes** | Smallest, runs on CPU |
| DrugCLIP | **Yes** | Fast even on CPU |
| STATE | **Yes** | |
| ProTrek | **Yes** | |
| GenMol | **Yes** | |
| MAMMAL | **Yes** | |
| OmniGenome | **Yes** | |
| scFv-pMPNN | **Yes** | |
| Cambrian-1 | **Yes** | |
| **Boltz-2** | **Yes** | NVIDIA NIM requires 48GB min |
| **Chai-1** | **Yes** | 80GB for full 2048 tokens |
| **Evo 2 40B** | **Problematic** | Low accuracy on Blackwell! |
| **AlphaFold 3** | **Unknown** | Only A100/H100 officially supported |

### Docker Image Size Details

**Large Images (>50 GB):**
- **Boltz-2 NIM**: ~73 GB image + ~30 GB model weights = **~103 GB total**
  - Source: [NVIDIA NIM Boltz2](https://docs.nvidia.com/nim/bionemo/boltz2/latest/support-matrix.html)

**Medium Images (10-50 GB):**
- **Evo 2**: ~20 GB base (PyTorch) + ~80 GB model weights = **~100 GB total**
  - Base: `nvcr.io/nvidia/pytorch:25.04-py3`
  - Models downloaded on first use from HuggingFace
- **Chai-1**: ~15 GB image + ~15 GB model weights = **~30 GB total**
  - Base: Ubuntu 22.04 + CUDA + Python 3.10
- **scFv-pMPNN**: ~8 GB (includes AlphaFold2 + ProteinMPNN)

**Small Images (<10 GB):**
- **AlphaFold 3**: ~5 GB image (but **~1 TB for databases**)
  - Base: `nvidia/cuda:12.6.3-base-ubuntu24.04`
  - Genetic databases: 415 GB download → 2.2 TB unzipped
  - Source: [AlphaFold 3 Installation](https://github.com/google-deepmind/alphafold3/blob/main/docs/installation.md)
- **ProFam-1, DrugCLIP, STATE, ProTrek**: 2-5 GB each

### GB10 Deployment Strategy

**Run Locally (Confirmed Compatible)**:
- ProFam-1, DrugCLIP, STATE, ProTrek, GenMol, MAMMAL
- OmniGenome, scFv-pMPNN, Cambrian-1
- Boltz-2 (120GB > 48GB requirement)
- Chai-1 (120GB > 80GB requirement)

**Use API Instead (Recommended)**:
- **Evo 2 40B** → NVIDIA NIM API (Blackwell accuracy issues)
- **AlphaFold 3** → AlphaFold Server or test locally first

**Use Smaller Model Variant**:
- Evo 2: Use `evo2_7b` instead of `evo2_40b` locally

---

## Available APIs and Cloud Services

### FREE APIs (No Local Resources Needed)

| Tool | Free Service | URL | Notes |
|------|--------------|-----|-------|
| **AlphaFold DB** | EBI Database API | https://alphafold.ebi.ac.uk/api | 200M+ pre-computed structures |
| **AlphaFold 3** | AlphaFold Server | https://alphafoldserver.com | 20 jobs/day free |
| **ESMFold** | Meta API | https://api.esmatlas.com | Free, <400 residues |
| **DrugCLIP** | DrugCLIP.com | https://drugclip.com | Free database of 10K proteins × 500M compounds |
| **ProTrek** | Search Service | http://search-protrek.com | Free protein search |

### PAID APIs (Reduce Local GPU Usage)

| Tool | Provider | URL | Cost |
|------|----------|-----|------|
| **Boltz-2** | NVIDIA NIM | https://build.nvidia.com/mit/boltz2 | Pay per use |
| **Boltz-2** | Neurosnap | https://neurosnap.ai/service/Boltz-2 | Pay per use |
| **Boltz-2** | Rowan | https://rowansci.com | Pay per use |
| **Chai-1** | BioLM | https://biolm.ai/models/chai1/ | Pay per use |
| **Chai-1** | Neurosnap | https://neurosnap.ai/service/Chai-1 | Pay per use |
| **Evo 2** | NVIDIA NIM | https://build.nvidia.com/arcinstitute/evo-2-40b | Pay per use |
| **ESMFold** | BioLM | https://biolm.ai/models/esmfold/ | Pay per use (longer seqs) |

### Available MCP Servers

| MCP Server | Description | GitHub |
|------------|-------------|--------|
| **AlphaFold MCP** | Access AlphaFold DB (200M+ structures) | [Augmented-Nature/AlphaFold-MCP-Server](https://github.com/Augmented-Nature/AlphaFold-MCP-Server) |
| **UniProt MCP** | 26 tools for protein database queries | [Augmented-Nature/UniProt-MCP-Server](https://github.com/Augmented-Nature/UniProt-MCP-Server) |
| **PDB MCP** | Protein Data Bank access | Available on MCP registries |

---

## Current Deployment Strategy

**Decision (2026-01-21)**: Use FREE APIs + Gemini now, local for small models, hold large models.

### Available NOW - FREE APIs (6 tools)

Use immediately - no payment required:

| Tool | Free Service | API Key | Status |
|------|--------------|---------|--------|
| **ESMFold** | Meta ESMFold API | None | ✅ `esmfold_api.xml` |
| **AlphaFold DB** | EBI Database (200M+) | None | ✅ `alphafold_api.xml` |
| **AlphaFold 3** | AlphaFold Server (20/day) | None | ✅ `alphafold3_server.xml` |
| **DrugCLIP** | drugclip.com | None | ✅ `drugclip_search.xml` |
| **ProTrek** | search-protrek.com | None | ✅ `protrek_search.xml` |
| **SynCraft** | Gemini API | GEMINI_API_KEY ✓ | ✅ `syncraft.xml` |

### Available NOW - Local Small Models (8 tools, <50 GB each)

Run on GB10 immediately:

| Tool | Size | Galaxy Wrapper |
|------|------|----------------|
| ProFam-1 | ~3 GB | `profam.xml` |
| GenMol | ~5 GB | `genmol.xml` |
| STATE | ~7 GB | `state.xml` |
| MAMMAL | ~9 GB | `mammal.xml` |
| OmniGenome | ~15 GB | `omnigenome.xml` |
| scFv-pMPNN | ~23 GB | `scfv_pmpnn.xml` |
| Cambrian-1 | ~23 GB | `cambrian1.xml` |
| Chai-1 | ~30 GB | `chai1.xml` |

### HOLD - Too Large for This Version (3 tools)

Deferred to future release:

| Tool | Size | Issue |
|------|------|-------|
| Boltz-2 | ~103 GB | Too large |
| Evo 2 40B | ~100 GB | Too large + Blackwell accuracy issue |
| AlphaFold 3 local | ~1 TB | Database files too large |

### Paid APIs (Available but no keys)

These work but require paid API keys:

| Tool | Provider | Galaxy Wrapper | API Key Env |
|------|----------|----------------|-------------|
| Boltz-2 | NVIDIA NIM | `boltz2_api.xml` | `NVIDIA_API_KEY` |
| Chai-1 | BioLM | `chai1_api.xml` | `BIOLM_API_KEY` |
| Evo 2 40B | NVIDIA NIM | `evo2_api.xml` | `NVIDIA_API_KEY` |

---

## API Keys Required

| Tool | API Provider | Environment Variable | Get Key At |
|------|--------------|---------------------|------------|
| Chai-1 | BioLM | `BIOLM_API_KEY` | https://biolm.ai |
| Evo 2 | NVIDIA NIM | `NVIDIA_API_KEY` | https://build.nvidia.com |
| Boltz-2 | NVIDIA NIM | `NVIDIA_API_KEY` | https://build.nvidia.com |
| SynCraft | Google | `GEMINI_API_KEY` | https://aistudio.google.com |
| AlphaFold 3 | DeepMind | None (web interface) | https://alphafoldserver.com |
| ESMFold | Meta | None (free API) | https://api.esmatlas.com |
| DrugCLIP | None | None (free web) | https://drugclip.com |
| ProTrek | None | None (free web) | http://search-protrek.com

---

## Files Created

**Galaxy XML Wrappers** (`/home/yzhang/biomate/backend/tools/biomate_ai_tools/`):

**FREE API Tools (Use Now - No Key Required):**
- `esmfold_api.xml` - ESMFold via Meta API (FREE)
- `alphafold_api.xml` - AlphaFold Database via EBI API (FREE)
- `drugclip_search.xml` - DrugCLIP.com search (FREE)
- `protrek_search.xml` - ProTrek search-protrek.com (FREE)

**PAID API Tools (Requires API Key):**
- `boltz2_api.xml` - Boltz-2 via NVIDIA NIM
- `chai1_api.xml` - Chai-1 via BioLM API
- `evo2_api.xml` - Evo 2 via NVIDIA NIM

**Local Execution Tools (For Future Use):**
- `alphafold3.xml` - AlphaFold 3 local
- `boltz2.xml` - Boltz-2 structure prediction
- `cambrian1.xml` - Biological image analysis
- `chai1.xml` - Chai-1 local
- `drugclip.xml` - Virtual screening
- `evo2.xml` - Evo 2 local (use 7B on GB10)
- `genmol.xml` - Molecular generation
- `mammal.xml` - Mammalian genomics
- `omnigenome.xml` - Genomic analysis
- `profam.xml` - Protein family classification
- `protrek.xml` - Protein search
- `scfv_pmpnn.xml` - Antibody design
- `state.xml` - Single cell perturbation
- `syncraft.xml` - Retrosynthesis

**Configuration:**
- `tool_conf.xml` - Galaxy tool registration (prioritizes FREE APIs)

**API Wrapper Scripts** (`/home/yzhang/biomate/backend/tools/biomate_ai_tools/scripts/`):
- `esmfold_api_wrapper.py` - FREE, no API key
- `alphafold_api_wrapper.py` - FREE, no API key
- `drugclip_search_wrapper.py` - FREE, no API key
- `protrek_search_wrapper.py` - FREE, no API key
- `boltz2_api_wrapper.py` - Requires NVIDIA_API_KEY
- `chai1_api_wrapper.py` - Requires BIOLM_API_KEY
- `evo2_api_wrapper.py` - Requires NVIDIA_API_KEY

**Local Wrapper Scripts** (`/home/yzhang/biomate/backend/tools/biomate_ai_tools/scripts/`):
- `state_wrapper.py` - STATE perturbation prediction
- `profam_wrapper.py` - ProFam fitness scoring
- `syncraft_wrapper.py` - SynCraft retrosynthesis (needs GEMINI_API_KEY)
- `scfv_pmpnn_wrapper.py` - Antibody design pipeline
- `genmol_wrapper.py` - Molecular generation
- `mammal_wrapper.py` - Mammalian genomics
- `omnigenome_wrapper.py` - Genomic analysis
- `cambrian1_wrapper.py` - Biological image analysis
- `boltz2_wrapper.py` - Boltz-2 local structure prediction
- `chai1_wrapper.py` - Chai-1 local structure prediction
- `evo2_wrapper.py` - Evo 2 local DNA analysis (use 7B model!)
- `alphafold3_wrapper.py` - AlphaFold 3 local prediction
- `drugclip_wrapper.py` - DrugCLIP local screening
- `protrek_wrapper.py` - ProTrek local embedding

**Configuration Updated**:
- `/home/yzhang/biomate/backend/config/galaxy.yml` - Added biomate_ai_tools

---

## Citations

1. **Boltz-2**: Passaro et al. Boltz-2: Towards Accurate and Efficient Binding Affinity Prediction. bioRxiv (2025)
2. **Chai-1**: Chai Discovery. Chai-1: Decoding molecular interactions (2024)
3. **AlphaFold 3**: Abramson et al. Accurate structure prediction of biomolecular interactions. Nature (2024)
4. **Evo 2**: Brixi et al. Genome modeling and design across all domains of life with Evo 2. bioRxiv (2025)
5. **STATE**: Arc Institute. State: Virtual cell model for perturbation prediction (2025)
6. **DrugCLIP**: Gao et al. DrugCLIP: Contrastive learning for virtual screening. Science (2026)
7. **ProTrek**: ProTrek: Trimodal protein language model. Nature Biotechnology (2025)
8. **ProFam-1**: ProFam: Protein family language model for fitness prediction (2024)
9. **scFv-pMPNN-AF2**: Deroo et al. AI pipeline for scFv design. Science Advances (2026)
10. **SynCraft**: SynCraft: LLM-guided retrosynthesis (2024)

---

## External Sources

- [NVIDIA NIM Boltz2 Support Matrix](https://docs.nvidia.com/nim/bionemo/boltz2/latest/support-matrix.html)
- [Chai-1 GitHub](https://github.com/chaidiscovery/chai-lab)
- [AlphaFold 3 Installation](https://github.com/google-deepmind/alphafold3/blob/main/docs/installation.md)
- [Evo 2 GitHub](https://github.com/ArcInstitute/evo2)
- [LMI4Boltz Paper](https://www.biorxiv.org/content/10.1101/2025.10.29.684571v2.full)
