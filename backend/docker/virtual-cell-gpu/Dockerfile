# BioMate Virtual Cell GPU Container
#
# Provides full GPU-accelerated virtual cell modeling stack:
#   - GEARS        : Graph-based gene perturbation prediction (Roohani et al. 2024 Nature Biotech)
#   - CPA          : Compositional Perturbation Autoencoder (Lotfollahi et al. 2023 MSB)
#   - Geneformer V2: BERT-style scRNA foundation model (Theodoris et al. 2023 Nature)
#   - TranscriptFormer: CZI cross-species transformer, Apache 2.0 (v0.6.0, 112M cells)
#   - scvi-tools   : variational inference for single-cell (Gayoso et al. 2022 Nature Methods)
#   - pertpy       : unified perturbation analysis toolkit
#   - anndata/scanpy: single-cell data infrastructure
#   - cellxgene-census: CZI CELLxGENE Census API
#
# Instance requirements:
#   - Geneformer 104M  : g4dn.xlarge (T4 16GB VRAM)
#   - Geneformer 316M  : g5.xlarge (A10G 24GB VRAM)
#   - TranscriptFormer : g5.2xlarge (A10G 24GB VRAM)
#   - GEARS inference  : g4dn.xlarge (T4 16GB VRAM)
#   - CPA inference    : g4dn.xlarge (T4 16GB VRAM)
#   - rBio 3B (4-bit)  : g4dn.xlarge (T4 16GB VRAM)
#
# ECR build (x86_64 for AWS Batch):
#   aws ecr get-login-password --region us-west-2 | \
#     docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/virtual-cell-gpu:1.0 \
#     --push -f backend/docker/virtual-cell-gpu/Dockerfile .
#
# Local build (for testing without GPU):
#   docker build -t biomate/virtual-cell-gpu:latest \
#     -f backend/docker/virtual-cell-gpu/Dockerfile .

FROM nvcr.io/nvidia/pytorch:24.05-py3

LABEL maintainer="BioMate Team"
LABEL description="virtual-cell-gpu: GEARS, CPA, Geneformer, TranscriptFormer, scvi-tools, pertpy"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV TORCH_HOME=/models/torch_cache
ENV HF_HOME=/models/huggingface_cache
ENV TRANSFORMERS_CACHE=/models/huggingface_cache
ENV GENEFORMER_MODEL_DIR=/models/geneformer

# ── System dependencies ────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        wget \
        libhdf5-dev \
        libxml2-dev \
        libcurl4-openssl-dev \
        awscli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Core single-cell stack ─────────────────────────────────────────────────
# Pin torch-geometric to match PyTorch version in base image
RUN pip install --no-cache-dir \
        # Single-cell data infrastructure
        anndata==0.10.8 \
        scanpy==1.10.1 \
        h5py==3.11.0 \
        scipy==1.13.1 \
        numpy==1.26.4 \
        pandas==2.2.2 \
        # CZI CELLxGENE Census API
        cellxgene-census==1.15.0 \
        tiledbsoma==1.12.3 \
        # scvi-tools (variational inference backbone for CPA + scVI)
        scvi-tools==1.1.6 \
        # Perturbation analysis toolkit
        pertpy==0.7.0

# ── PyTorch Geometric (required for GEARS) ─────────────────────────────────
# Install torch-geometric and all sparse dependencies
RUN pip install --no-cache-dir \
        torch-scatter \
        torch-sparse \
        torch-cluster \
        torch-spline-conv \
        torch-geometric \
        -f https://data.pyg.org/whl/torch-2.3.0+cu121.html

# ── GEARS (Roohani et al. 2024 Nature Biotechnology) ──────────────────────
RUN pip install --no-cache-dir \
        gears \
        networkx \
        goatools \
        obonet

# ── CPA (Compositional Perturbation Autoencoder) ──────────────────────────
# facebookresearch/CPA — install from GitHub
RUN pip install --no-cache-dir \
        git+https://github.com/facebookresearch/CPA.git@main

# ── Geneformer V2 (Theodoris et al. 2023 Nature) ──────────────────────────
RUN pip install --no-cache-dir \
        geneformer \
        transformers==4.40.2 \
        accelerate==0.30.1 \
        datasets==2.19.1

# ── CZI TranscriptFormer (Apache 2.0; 112M cells, 12 species) ─────────────
RUN pip install --no-cache-dir \
        git+https://github.com/czi-ai/transcriptformer.git@main

# ── Additional tools ───────────────────────────────────────────────────────
RUN pip install --no-cache-dir \
        # Tellurium for ODE simulation (in same image for chain workflows)
        tellurium==2.2.12.1 \
        libroadrunner \
        # COBRApy for FBA
        cobra==0.29.0 \
        # Gradient-based ODE fitting
        sbmltoodejax \
        jax[cuda12] \
        optax \
        # CMap / LINCS query
        cmapPy \
        # Utility
        scikit-learn==1.5.0 \
        matplotlib==3.9.0 \
        seaborn==0.13.2 \
        umap-learn==0.5.6 \
        leidenalg \
        igraph

# ── Create model cache directories ────────────────────────────────────────
RUN mkdir -p /models/torch_cache \
             /models/huggingface_cache \
             /models/geneformer \
             /models/transcriptformer \
             /models/gears_pretrained \
             /models/cpa_pretrained \
             /data/reference

# ── Verify critical imports (build-time smoke test) ───────────────────────
RUN python3 -c "
import torch
import torch_geometric
import scvi
import anndata
import scanpy
import pertpy
import cellxgene_census
import tellurium
import cobra
print('CUDA available:', torch.cuda.is_available())
print('PyTorch:', torch.__version__)
print('PyG:', torch_geometric.__version__)
print('scvi-tools:', scvi.__version__)
print('All imports OK')
"

# ── Download Geneformer model weights (optional; skip if S3 mounted) ──────
# Uncomment to bake weights into image (~2GB):
# RUN python3 -c "
# from transformers import AutoTokenizer, AutoModel
# AutoTokenizer.from_pretrained('ctheodoris/Geneformer', cache_dir='/models/geneformer')
# AutoModel.from_pretrained('ctheodoris/Geneformer', cache_dir='/models/geneformer')
# print('Geneformer V2 weights downloaded')
# "

WORKDIR /work
CMD ["python3"]
