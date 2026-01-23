#!/bin/bash
# Biomate AI Tools - Environment Setup
# Run this script to configure the environment for AI tools
#
# Usage: source setup_env.sh

echo "=============================================="
echo "Biomate AI Tools - Environment Setup"
echo "=============================================="

# Base directories
export BIOMATE_TOOLS_DIR="/home/yzhang/biomate/backend/tools/biomate_ai_tools"
export BIOMATE_REPOS_DIR="/home/yzhang/biomate/tools_repos"
export BIOMATE_MODELS_DIR="/home/yzhang/biomate/models"

# Tool-specific directories
export SYNCRAFT_DIR="${BIOMATE_REPOS_DIR}/syncraft"
export PROFAM_DIR="${BIOMATE_REPOS_DIR}/profam"
export PROTREK_DIR="${BIOMATE_REPOS_DIR}/ProTrek"
export DRUGCLIP_DIR="${BIOMATE_REPOS_DIR}/DrugCLIP"
export STATE_DIR="${BIOMATE_REPOS_DIR}/state"
export SCFV_PMPNN_DIR="${BIOMATE_REPOS_DIR}/scFv_Pmpnn_AF2"
export BOLTZ_DIR="${BIOMATE_REPOS_DIR}/boltz"
export CHAI_DIR="${BIOMATE_REPOS_DIR}/chai-lab"
export EVO2_DIR="${BIOMATE_REPOS_DIR}/evo2"
export ALPHAFOLD3_DIR="${BIOMATE_REPOS_DIR}/alphafold3"

# Model directories (for local execution)
export STATE_MODEL_DIR="${BIOMATE_MODELS_DIR}/state"
export PROFAM_CHECKPOINT="${BIOMATE_MODELS_DIR}/profam"
export GENMOL_MODEL_DIR="${BIOMATE_MODELS_DIR}/genmol"
export CAMBRIAN_MODEL_DIR="${BIOMATE_MODELS_DIR}/cambrian1"
export MAMMAL_MODEL_DIR="${BIOMATE_MODELS_DIR}/mammal"
export OMNIGENOME_MODEL_DIR="${BIOMATE_MODELS_DIR}/omnigenome"

# API Keys (set these with your actual keys)
# GEMINI_API_KEY - Required for SynCraft
# Get free key at: https://aistudio.google.com/apikey
if [ -z "$GEMINI_API_KEY" ]; then
    echo ""
    echo "WARNING: GEMINI_API_KEY not set"
    echo "  SynCraft requires this key."
    echo "  Get free key at: https://aistudio.google.com/apikey"
    echo "  Set with: export GEMINI_API_KEY='your-key-here'"
fi

# Optional paid API keys (not required for FREE tools)
# NVIDIA_API_KEY - For Boltz-2/Evo-2 via NVIDIA NIM (optional)
# BIOLM_API_KEY - For Chai-1 via BioLM (optional)

echo ""
echo "Environment configured!"
echo ""
echo "Available Tools:"
echo "----------------------------------------"
echo "FREE APIs (ready now):"
echo "  - ESMFold API      (structure, <400 residues)"
echo "  - AlphaFold DB     (200M+ pre-computed structures)"
echo "  - AlphaFold 3      (alphafoldserver.com, 20/day)"
echo "  - DrugCLIP         (drugclip.com search)"
echo "  - ProTrek          (search-protrek.com)"
echo "  - SynCraft         (retrosynthesis, needs GEMINI_API_KEY)"
echo ""
echo "Local tools (small, ready for GB10):"
echo "  - ProFam-1         (~3 GB)"
echo "  - GenMol           (~5 GB)"
echo "  - STATE            (~7 GB)"
echo "  - MAMMAL           (~9 GB)"
echo "  - OmniGenome       (~15 GB)"
echo "  - scFv-pMPNN       (~23 GB)"
echo "  - Cambrian-1       (~23 GB)"
echo "  - Chai-1           (~30 GB)"
echo ""
echo "HOLD (too large for this version):"
echo "  - Boltz-2          (~103 GB)"
echo "  - Evo 2 40B        (~100 GB, Blackwell issue)"
echo "  - AlphaFold 3 local (~1 TB databases)"
echo "----------------------------------------"

# Create model directories if they don't exist
mkdir -p "${BIOMATE_MODELS_DIR}"
mkdir -p "${STATE_MODEL_DIR}"
mkdir -p "${PROFAM_CHECKPOINT}"
mkdir -p "${GENMOL_MODEL_DIR}"
mkdir -p "${CAMBRIAN_MODEL_DIR}"
mkdir -p "${MAMMAL_MODEL_DIR}"
mkdir -p "${OMNIGENOME_MODEL_DIR}"

echo ""
echo "Model directories created at: ${BIOMATE_MODELS_DIR}"
echo ""
echo "To download model weights, use the individual tool setup scripts."
echo "=============================================="
