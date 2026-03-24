# BioMate AI Tools — Docker Image Registry

**Date**: 2026-03-24
**ECR Registry**: `399683337364.dkr.ecr.us-west-2.amazonaws.com`
**Region**: `us-west-2`
**Architecture**: `linux/amd64` (x86_64) — all images

---

## Overview

Every AI tool has **two image tags**:

| Tag | ENTRYPOINT | Purpose |
|-----|------------|---------|
| `:latest` | Present | Standalone use, direct `docker run` |
| `:nextflow` | **Removed** | Nextflow / AWS Batch (required — Nextflow must control entrypoint) |

**Always use `:nextflow` in Nextflow `.nf` process `container` directives.**

---

## Image Catalog

### ProTrek
**Description**: Trimodal protein search — query by sequence, structure (Foldseek notation), or free-text description. Returns ranked UniProt hits with confidence scores.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest` | 3.7 GB | 2026-03-24 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:nextflow` | 3.7 GB | 2026-03-24 |

**Base image**: `pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime`
**GPU**: Recommended (8 GB+ VRAM)
**Source**: `tools_repos/ProTrek/`
**Key paths inside container**:
- `/opt/protrek/` — source code
- `/opt/protrek/demo/search.py` — CLI: search proteins by query
- `/opt/protrek/demo/embed.py` — CLI: generate embeddings from FASTA
- `/models/protrek/` — mount model weights here

**CLI usage**:
```bash
# Search by text
docker run --gpus all -v /path/to/weights:/models/protrek \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest \
  search --query "kinase involved in cell cycle" --type text --top_k 50 --output results.json

# Generate embeddings
docker run --gpus all -v /path/to/weights:/models/protrek \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest \
  embed --input proteins.fasta --output embeddings.pt
```

---

### STATE
**Description**: Arc Institute virtual cell model. Predicts single-cell transcriptomic responses to perturbations (gene knockdown, CRISPR, drug treatment). Input: `.h5ad` AnnData file.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest` | 3.9 GB | 2026-03-24 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:nextflow` | 3.9 GB | 2026-03-24 |

**Base image**: `pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime`
**GPU**: Optional (CPU mode supported)
**Source**: `tools_repos/state/`
**Key paths inside container**:
- `/opt/state/` — source code
- `/models/state/` — mount model weights here

**CLI usage** (via `state` CLI installed as package):
```bash
# Perturbation prediction
docker run --gpus all -v /path/to/data:/workspace -v /path/to/models:/models \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest \
  tx infer --adata /workspace/perturb_data.h5ad \
           --model-dir /models/state \
           --output /workspace/predicted.h5ad

# Cell embedding
docker run --gpus all -v /path/to/data:/workspace \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest \
  emb transform --input /workspace/cells.h5ad \
                --model-folder /models/state \
                --output /workspace/embedded.h5ad
```

---

### ProFam
**Description**: 251M-parameter protein family language model. Scores variant fitness or generates novel sequences conditioned on a family MSA.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest` | 3.7 GB | 2026-03-24 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:nextflow` | 3.7 GB | 2026-03-24 |

**Base image**: `pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime`
**GPU**: Recommended (8 GB+ VRAM)
**Source**: `tools_repos/profam/`
**Key paths inside container**:
- `/opt/profam/` — source code
- `/opt/profam/scripts/score_sequences.py` — variant scoring
- `/opt/profam/scripts/generate_sequences.py` — sequence generation
- `/models/profam/` — mount model checkpoint here

**CLI usage**:
```bash
# Score variants
docker run --gpus all -v /path/to/models:/models -v /path/to/data:/workspace \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest \
  score --checkpoint_dir /models/profam \
        --conditioning_fasta /workspace/family.fasta \
        --candidates_file /workspace/variants.csv \
        --save_dir /workspace/output

# Generate sequences
docker run --gpus all -v /path/to/models:/models -v /path/to/data:/workspace \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest \
  generate --checkpoint_dir /models/profam \
           --conditioning_fasta /workspace/family.fasta \
           --num_sequences 100
```

---

### scFv-pMPNN
**Description**: Single-chain Fv antibody framework design using ProteinMPNN. Designs antibody sequences from a target structure; optionally predicts structure via ColabFold.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest` | 3.6 GB | 2026-03-24 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:nextflow` | 3.6 GB | 2026-03-24 |

**Base image**: `pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime`
**GPU**: Required (16 GB+ VRAM recommended)
**Source**: `tools_repos/scFv_Pmpnn_AF2/`
**Key paths inside container**:
- `/opt/scfv-pmpnn/` — source code + pipeline scripts
- `/opt/scfv-pmpnn/run_design.py` — CLI: sequence design (wraps ProteinMPNN pipeline)
- `/opt/scfv-pmpnn/run_predict.py` — CLI: structure prediction (wraps ColabFold)
- `/opt/scfv-pmpnn/scripts/scfv_anarci.py` — convert antibody sequence to scFv
- `/opt/ProteinMPNN/` — mount ProteinMPNN weights here
- `/opt/localcolabfold/` — mount LocalColabFold installation here

**Note**: ProteinMPNN and LocalColabFold are external dependencies that must be mounted at runtime. Without them, the container runs in mock/stub mode for pipeline testing.

**CLI usage**:
```bash
# Design antibody sequences
docker run --gpus all \
  -v /path/to/pmpnn:/opt/ProteinMPNN \
  -v /path/to/data:/workspace \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest \
  design --target /workspace/antibody.pdb \
         --output_fasta /workspace/designed.fasta \
         --output_scores /workspace/scores.csv \
         --num_designs 100 \
         --design_region framework

# Predict structures
docker run --gpus all \
  -v /path/to/colabfold:/opt/localcolabfold \
  -v /path/to/data:/workspace \
  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest \
  predict --input /workspace/designed.fasta \
          --output /workspace/structures/
```

---

### SynCraft
**Description**: LLM-guided molecular synthesizability optimization. Uses Gemini API to optimize synthesis routes. No GPU required.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:latest` | 289 MB | 2026-03-24 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:nextflow` | 289 MB | 2026-03-24 |

**Base image**: `python:3.10-slim`
**GPU**: Not required
**Source**: cloned from `github.com/catalystforyou/SynCraft-Core`
**Key paths inside container**:
- `/opt/syncraft/` — source code
**Runtime requirement**: `GEMINI_API_KEY` environment variable

---

### DrugCLIP
**Description**: Deep contrastive learning for genome-wide virtual screening (10M× faster than docking). Matches drug-like molecules to protein targets via embedding similarity.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:latest` | 2.9 GB | 2026-03-24 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:nextflow` | 2.9 GB | 2026-03-24 |

**Base image**: `python:3.10-slim`
**GPU**: Optional (CPU mode supported)
**Source**: cloned from `github.com/bowen-gao/DrugCLIP`
**Key paths inside container**:
- `/opt/drugclip/` — source code

---

### Boltz-2
**Description**: Structure prediction for proteins, nucleic acids, and small molecules. MIT-licensed AlphaFold3-class model.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest` | 7.5 GB | 2026-01-21 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:nextflow` | 7.5 GB | 2026-03-13 |

**GPU**: Required (16 GB+ VRAM)
**Note**: No rebuild needed — images are stable and production-verified.

---

### Chai-1
**Description**: Multi-modal biomolecular structure prediction (proteins + nucleic acids + ligands). Requires Chai-1 license acceptance.

| Tag | Image URI | Size | Pushed |
|-----|-----------|------|--------|
| `:latest` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest` | 7.6 GB | 2026-01-21 |
| `:nextflow` | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:nextflow` | 7.6 GB | 2026-03-16 |

**GPU**: Required (24 GB+ VRAM)
**Note**: No rebuild needed — images are stable and production-verified.

---

## Pulling Images

### Login to ECR
```bash
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  399683337364.dkr.ecr.us-west-2.amazonaws.com
```

### Pull an image
```bash
docker pull 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/<tool>:nextflow
```

---

## Using in Nextflow

All nf-core modules under `backend/nf-core-workflows/modules/biomate-ai-tools/` already reference the `:nextflow` tag. Example:

```groovy
process PROTREK_SEARCH {
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:nextflow'
    ...
}
```

The `:nextflow` tag is identical to `:latest` except `ENTRYPOINT []` is set — this is required so Nextflow/AWS Batch can inject its own command.

---

## Build Infrastructure

Dockerfiles and build scripts live at:
```
backend/docker/biomate-ai-tools/
├── build-ecr.sh               # Master build + push script (run from repo root)
├── protrek/
│   ├── Dockerfile             # :latest — copies from tools_repos/ProTrek/
│   ├── Dockerfile.nextflow    # :nextflow wrapper
│   ├── entrypoint.sh
│   ├── search.py              # CLI: protein search
│   └── embed.py               # CLI: embedding generation
├── state/
│   ├── Dockerfile             # :latest — copies from tools_repos/state/
│   ├── Dockerfile.nextflow
│   └── entrypoint.sh
├── profam/
│   ├── Dockerfile             # :latest — copies from tools_repos/profam/
│   ├── Dockerfile.nextflow
│   └── entrypoint.sh
├── scfv-pmpnn/
│   ├── Dockerfile             # :latest — copies from tools_repos/scFv_Pmpnn_AF2/
│   ├── Dockerfile.nextflow
│   ├── entrypoint.sh
│   ├── run_design.py          # CLI: antibody design (wraps ProteinMPNN)
│   └── run_predict.py         # CLI: structure prediction (wraps ColabFold)
├── syncraft/
│   ├── Dockerfile
│   └── Dockerfile.nextflow
└── drugclip/
    ├── Dockerfile
    └── Dockerfile.nextflow
```

### Rebuild a specific tool
```bash
cd /home/yzhang/biomate   # Must run from repo root
bash backend/docker/biomate-ai-tools/build-ecr.sh protrek
```

### Rebuild all tools
```bash
cd /home/yzhang/biomate
bash backend/docker/biomate-ai-tools/build-ecr.sh
```

### Rebuild only :nextflow wrappers (fast, ~5s each)
```bash
cd /home/yzhang/biomate
bash backend/docker/biomate-ai-tools/build-ecr.sh --nextflow-only syncraft drugclip
```

---

## Changes Made 2026-03-24

| Tool | Change |
|------|--------|
| ProTrek | Rebuilt `linux/amd64` from local `tools_repos/ProTrek/`; added `demo/search.py` + `demo/embed.py` CLI scripts (were missing); added `Dockerfile.nextflow` |
| STATE | Rebuilt `linux/amd64` from local `tools_repos/state/`; fixed `cell-eval`/`cell-load` dependency install; updated `PYTHONPATH` to `src/`; added `Dockerfile.nextflow` |
| ProFam | Rebuilt `linux/amd64` from local `tools_repos/profam/`; added `Dockerfile.nextflow` |
| scFv-pMPNN | Rebuilt `linux/amd64` from local `tools_repos/scFv_Pmpnn_AF2/`; **root-cause fix**: created `run_design.py` + `run_predict.py` CLI wrappers that were missing (caused exit code 2); added `Dockerfile.nextflow` |
| SynCraft | Was `arm64` — rebuilt `linux/amd64`; added `Dockerfile.nextflow` (was missing) |
| DrugCLIP | Was `arm64` — rebuilt `linux/amd64`; added `Dockerfile.nextflow` (was missing) |
| All nf-core modules | Updated container tag from `:latest` → `:nextflow` in all 8 `main.nf` files |
