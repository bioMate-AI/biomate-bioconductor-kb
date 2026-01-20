#!/usr/bin/env python3
"""
Enhanced Tool Knowledge Collector

Fills in gaps identified in the audit:
- Hardware requirements
- Dependencies
- Help text
- Usage guides
- Recommended parameters
- Benchmark papers
- Installation instructions

Usage:
    python enhance_tool_knowledge.py
"""

import json
import logging
import os
import re
import sqlite3
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
import requests

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Curated data for each tool based on research
ENHANCED_DATA = {
    "state": {
        "primary_citation": {
            "doi": "10.1101/2025.06.26.661135",
            "title": "Predicting cellular responses to perturbation across diverse contexts with State",
            "authors": ["Arc Institute"],
            "journal": "bioRxiv",
            "year": 2025,
            "url": "https://www.biorxiv.org/content/10.1101/2025.06.26.661135"
        },
        "hardware_requirements": """
**Minimum Requirements:**
- CPU: Modern multi-core processor
- RAM: 32GB+ recommended
- GPU: Optional but recommended for training (NVIDIA with CUDA)
- Storage: 50GB+ for models and datasets

**Recommended for Training:**
- GPU: NVIDIA A100 40GB or better
- RAM: 64GB+
- Storage: 500GB+ SSD for large datasets (Tahoe-100M)

**For Inference Only:**
- GPU: NVIDIA T4 or better
- RAM: 16GB+
""",
        "dependencies": [
            "uv (package manager)",
            "Python 3.10+",
            "PyTorch 2.0+",
            "scanpy",
            "anndata",
            "numpy",
            "pandas",
            "wandb (optional, for logging)"
        ],
        "help_text": """
State CLI Commands:

state --help                    # Show main help
state emb --help               # State Embedding commands
state tx --help                # State Transition commands

State Embedding (SE):
  state emb fit               # Train SE model
  state emb transform         # Generate embeddings
  state emb query             # Query vector database

State Transition (ST):
  state tx train              # Train ST model
  state tx predict            # Evaluate on test set
  state tx infer              # Inference on new data
  state tx preprocess_train   # Preprocess training data
  state tx preprocess_infer   # Preprocess inference data
""",
        "usage_guide": """
## Quick Start Guide for State

### 1. Installation
```bash
uv tool install arc-state
```

### 2. Training a State Transition Model
```bash
state tx train \\
  data.kwargs.toml_config_path="config.toml" \\
  data.kwargs.embed_key=X_hvg \\
  training.max_steps=40000 \\
  training.batch_size=8 \\
  model=pertsets
```

### 3. Inference with Pre-trained Model
```bash
state tx infer \\
  --output_dir /path/to/model/ \\
  --checkpoint final.ckpt \\
  --adata /path/to/data.h5ad \\
  --pert_col gene \\
  --embed_key X_hvg
```

### 4. Download Pre-trained Models
Models available on HuggingFace: https://huggingface.co/arcinstitute

### Key Concepts:
- **State Embedding (SE)**: Converts transcriptomes to vector space
- **State Transition (ST)**: Predicts perturbation responses
- **TOML config**: Defines datasets, splits, and evaluation paradigms
""",
        "recommended_parameters": {
            "training": {
                "batch_size": {"default": 8, "range": "4-32", "note": "Larger with more GPU memory"},
                "learning_rate": {"default": 1e-4, "range": "1e-5 to 1e-3"},
                "max_steps": {"default": 40000, "note": "Increase for larger datasets"},
                "val_freq": {"default": 100, "note": "Validation frequency"}
            },
            "model": {
                "hidden_dim": {"default": 328},
                "cell_set_len": {"default": 64}
            }
        },
        "benchmark_papers": [
            {
                "title": "Tahoe-100M: The world's largest single-cell perturbation dataset",
                "url": "https://arcinstitute.org/datasets/tahoe-100m",
                "note": "Training dataset for State"
            }
        ]
    },

    "chai1": {
        "primary_citation": {
            "doi": "10.1101/2024.10.10.615955",
            "title": "Chai-1: Decoding the molecular interactions of life",
            "authors": ["Chai Discovery"],
            "journal": "bioRxiv",
            "year": 2024,
            "url": "https://www.biorxiv.org/content/10.1101/2024.10.10.615955"
        },
        "hardware_requirements": """
**Minimum Requirements:**
- GPU: NVIDIA A10 or A30 (for small complexes)
- VRAM: 24GB+
- RAM: 32GB
- Storage: 50GB

**Recommended:**
- GPU: NVIDIA A100 80GB or H100 80GB or L40S 48GB
- VRAM: 48-80GB
- RAM: 64GB+

**Consumer Grade (limited):**
- NVIDIA RTX 4090 (for smaller complexes only)

**Input Limitations:**
- Proteins: up to 1,024 residues
- DNA/RNA: up to 3,072 bases
- Ligands: up to 128 characters (SMILES)
""",
        "dependencies": [
            "Python 3.10+",
            "PyTorch 2.0+ with CUDA",
            "bfloat16 GPU support",
            "Linux operating system"
        ],
        "help_text": """
Chai-1 CLI Commands:

chai-lab fold <input.fasta> <output_folder>
    Fold sequences from FASTA file

    Options:
    --use-msa-server          Use ColabFold MMseqs2 for MSA generation
    --use-templates-server    Use template search server
    --msa-server-url URL      Custom MSA server URL
    --num-diffn-timesteps N   Diffusion timesteps (default: 200)
    --num-trunk-recycles N    Trunk recycles (default: 3)

chai citation                 Show citation information
chai --help                   Show all commands
""",
        "usage_guide": """
## Quick Start Guide for Chai-1

### 1. Installation
```bash
pip install chai_lab==0.6.1
```

### 2. Basic Structure Prediction
```bash
chai-lab fold input.fasta output_folder
```

### 3. With MSA Enhancement (Recommended)
```bash
chai-lab fold --use-msa-server --use-templates-server input.fasta output_folder
```

### 4. Python API
```python
from chai_lab.chai1 import run_inference

candidates = run_inference(
    fasta_file="complex.fasta",
    output_dir="./output",
    num_trunk_recycles=3,
    num_diffn_timesteps=200,
    seed=42,
    use_esm_embeddings=True
)
```

### 5. Web Interface
Visit: https://lab.chaidiscovery.com

### Key Features:
- Multi-modal: proteins, DNA, RNA, ligands, glycosylations
- Restraints support for guided folding
- Covalent bond specification
""",
        "recommended_parameters": {
            "inference": {
                "num_trunk_recycles": {"default": 3, "range": "1-5", "note": "More = better but slower"},
                "num_diffn_timesteps": {"default": 200, "range": "50-500", "note": "More = higher quality"},
                "use_esm_embeddings": {"default": True, "note": "Improves accuracy"},
                "use_msa_server": {"default": False, "note": "Set True for best results"}
            }
        },
        "benchmark_papers": [
            {
                "title": "CASP15 Results",
                "note": "Chai-1 evaluated on CASP15 targets"
            },
            {
                "title": "CAMEO Continuous Evaluation",
                "url": "https://cameo3d.org",
                "note": "Ongoing structure prediction benchmarks"
            }
        ]
    },

    "boltz2": {
        "primary_citation": {
            "doi": None,
            "title": "Boltz-2: A unified model for biomolecular structure and affinity prediction",
            "authors": ["Jeremy Wohlwend", "MIT", "Recursion"],
            "journal": "Preprint",
            "year": 2025,
            "url": "https://github.com/jwohlwend/boltz"
        },
        "hardware_requirements": """
**Minimum Requirements:**
- GPU: NVIDIA GPU with 16GB+ VRAM
- RAM: 32GB
- Storage: 20GB

**Recommended:**
- GPU: NVIDIA A100 or H100
- VRAM: 40-80GB (for large complexes)
- RAM: 64GB

**Scaling:**
- Small molecules: 16GB VRAM sufficient
- Large protein complexes: 40GB+ VRAM
- Affinity prediction: Additional compute
""",
        "dependencies": [
            "Python 3.10+",
            "PyTorch 2.0+",
            "CUDA toolkit"
        ],
        "help_text": """
Boltz CLI Commands:

boltz predict <input> [options]
    Predict structure from input file

    Input formats:
    - FASTA file
    - YAML file with sequences and ligands

    Options:
    --output_dir DIR         Output directory
    --num_samples N          Number of samples (default: 1)
    --recycling_steps N      Recycling iterations
    --diffusion_samples N    Diffusion samples

boltz affinity <complex>
    Predict binding affinity

boltz --help                 Show all commands
""",
        "usage_guide": """
## Quick Start Guide for Boltz-2

### 1. Installation
```bash
pip install boltz
# or with pixi
pixi add --pypi boltz
```

### 2. Predict Structure
```bash
boltz predict input.fasta --output_dir results/
```

### 3. Protein-Ligand Complex
Create YAML input:
```yaml
sequences:
  - protein:
      id: A
      sequence: MKTVRQERLKSIVRILERSKEPVSGAQ...
  - ligand:
      id: B
      smiles: CC(=O)Nc1ccc(O)cc1
```

```bash
boltz predict complex.yaml
```

### 4. Python API
```python
from boltz import Boltz

model = Boltz()
result = model.predict(
    protein_sequence="MKTVRQERLK...",
    ligand_smiles="CC(=O)Nc1ccc(O)cc1"
)
```

### Key Advantages:
- MIT License (fully commercial use)
- Joint structure + affinity prediction
- 1000x faster than FEP methods
""",
        "recommended_parameters": {
            "prediction": {
                "num_samples": {"default": 1, "range": "1-5", "note": "More samples = better confidence"},
                "diffusion_samples": {"default": 1, "range": "1-10"},
                "recycling_steps": {"default": 3, "range": "1-10"}
            }
        },
        "benchmark_papers": [
            {
                "title": "Comparison with AlphaFold 3",
                "note": "Boltz-2 approaches AF3 accuracy with MIT license"
            }
        ]
    },

    "evo2": {
        "primary_citation": {
            "doi": None,
            "title": "Evo 2: A 40 billion parameter DNA foundation model",
            "authors": ["Arc Institute", "NVIDIA", "Stanford", "UC Berkeley", "UCSF"],
            "journal": "Arc Institute",
            "year": 2025,
            "url": "https://arcinstitute.org/news/evo2"
        },
        "hardware_requirements": """
**For Local Inference (7B model):**
- GPU: NVIDIA A100 40GB or better
- VRAM: 40GB+
- RAM: 64GB
- Storage: 50GB

**For Full 40B Model:**
- GPU: Multiple NVIDIA H100 80GB
- VRAM: 160GB+ (multi-GPU)
- RAM: 256GB+
- Storage: 200GB

**NVIDIA NIM API (Recommended):**
- No local GPU required
- Rate limit: 40 requests/minute
- Free for developers
""",
        "dependencies": [
            "Python 3.10+",
            "PyTorch 2.0+",
            "CUDA 12.0+",
            "flash-attn==2.8.0.post2",
            "transformer-engine-torch==2.3.0"
        ],
        "help_text": """
Evo 2 Usage:

# Local Python API
from evo2 import Evo2

model = Evo2.from_pretrained("arcinstitute/evo2-7b")
output = model.generate(sequence="ATCGATCG...", max_length=1000)

# NVIDIA NIM API
import requests

response = requests.post(
    "https://integrate.api.nvidia.com/v1/biology/arc/evo2/generate",
    headers={"Authorization": "Bearer $NGC_API_KEY"},
    json={
        "sequence": "ATCGATCG...",
        "num_tokens": 100,
        "temperature": 1.0
    }
)

# Taxonomy-guided generation
sequence = "|D__BACTERIA;P__PSEUDOMONADOTA;...|ATCGATCG..."
""",
        "usage_guide": """
## Quick Start Guide for Evo 2

### 1. Installation
```bash
# Install dependencies
conda install -c nvidia cuda-nvcc cuda-cudart-dev
conda install -c conda-forge transformer-engine-torch=2.3.0
pip install flash-attn==2.8.0.post2 --no-build-isolation

# Install Evo 2
pip install evo2
```

### 2. Using NVIDIA NIM API (Recommended)
```python
import requests

# Get API key from developer.nvidia.com
response = requests.post(
    "https://integrate.api.nvidia.com/v1/biology/arc/evo2/generate",
    headers={
        "Authorization": "Bearer YOUR_NGC_API_KEY",
        "Content-Type": "application/json"
    },
    json={
        "sequence": "ATCGATCGATCG",
        "num_tokens": 100,
        "top_k": 4,
        "temperature": 1.0
    }
)
print(response.json())
```

### 3. Taxonomy-Guided Generation
```python
# Bias toward E. coli genome patterns
sequence = "|D__BACTERIA;P__PSEUDOMONADOTA;C__GAMMAPROTEOBACTERIA;O__ENTEROBACTERALES;F__ENTEROBACTERIACEAE;G__ESCHERICHIA;S__ESCHERICHIA|ATCGATCG"
```

### Key Capabilities:
- Disease mutation prediction
- Genome design and generation
- Cross-species DNA analysis
- 1M base pair context length
""",
        "recommended_parameters": {
            "generation": {
                "temperature": {"default": 1.0, "range": "0.5-1.5", "note": "Lower = more conservative"},
                "top_k": {"default": 4, "range": "1-50", "note": "Sampling diversity"},
                "num_tokens": {"default": 100, "range": "1-1000000", "note": "Up to 1M context"}
            }
        },
        "benchmark_papers": [
            {
                "title": "Evo: A model of DNA at the scale of evolution",
                "doi": "10.1126/science.ado9336",
                "note": "Original Evo paper"
            }
        ]
    },

    "drugclip": {
        "hardware_requirements": """
**Minimum Requirements:**
- CPU: Modern multi-core processor
- RAM: 16GB
- Storage: 10GB

**For Large-Scale Screening:**
- GPU: NVIDIA GPU with 8GB+ VRAM (optional, for acceleration)
- RAM: 64GB+ (for loading large molecule libraries)
- Storage: 100GB+ (for compound databases)
""",
        "dependencies": [
            "Python 3.8+",
            "RDKit 2022.9.5",
            "PyTorch",
            "UniMol framework",
            "numpy",
            "pandas"
        ],
        "help_text": """
DrugCLIP Usage:

# Encode protein pocket
python encode_pocket.py --input pockets.csv --output pocket_embeddings.pt

# Encode molecules
python encode_molecule.py --input molecules.smi --output mol_embeddings.pt

# Screen
python screen.py --pockets pocket_embeddings.pt --molecules mol_embeddings.pt --output hits.csv

# Full pipeline
python drugclip_screen.py --protein target.pdb --library compounds.smi --output results/
""",
        "usage_guide": """
## Quick Start Guide for DrugCLIP

### 1. Installation
```bash
git clone https://github.com/bowen-gao/DrugCLIP
cd DrugCLIP
pip install -r requirements.txt

# Install RDKit
conda install -c conda-forge rdkit=2022.9.5
```

### 2. Prepare Input Data
- Protein pocket: PDB file or pocket coordinates
- Molecule library: SMILES file

### 3. Run Screening
```python
from drugclip import DrugCLIP

model = DrugCLIP.load_pretrained()

# Encode target
pocket_embedding = model.encode_pocket(pocket_pdb="target_pocket.pdb")

# Encode molecules
mol_embeddings = model.encode_molecules(smiles_list=["CCO", "CC(=O)O", ...])

# Calculate similarity scores
scores = model.similarity(pocket_embedding, mol_embeddings)

# Get top hits
top_hits = scores.topk(100)
```

### Key Features:
- 10 million times faster than traditional docking
- Contrastive learning approach
- Genome-wide screening capability
""",
        "recommended_parameters": {
            "screening": {
                "top_k": {"default": 100, "note": "Number of hits to return"},
                "threshold": {"default": 0.5, "note": "Similarity threshold"}
            }
        },
        "install_instructions": """
```bash
# Clone repository
git clone https://github.com/bowen-gao/DrugCLIP
cd DrugCLIP

# Create environment
conda create -n drugclip python=3.8
conda activate drugclip

# Install RDKit (specific version required)
conda install -c conda-forge rdkit=2022.9.5

# Install other dependencies
pip install -r requirements.txt
```
"""
    },

    "scfv_pmpnn_af2": {
        "hardware_requirements": """
**Minimum Requirements:**
- GPU: NVIDIA GPU with 16GB VRAM
- RAM: 32GB
- Storage: 50GB

**Recommended:**
- GPU: NVIDIA A100 40GB
- RAM: 64GB
- Storage: 100GB (for ColabFold databases)

**Dependencies with GPU Requirements:**
- ColabFold/LocalColabFold: 16GB+ VRAM
- ProteinMPNN: 8GB+ VRAM
""",
        "dependencies": [
            "Python 3.8+",
            "ProteinMPNN",
            "LocalColabFold (or ColabFold)",
            "ANARCI (antibody numbering)",
            "PyTorch",
            "numpy",
            "pandas",
            "biopython"
        ],
        "help_text": """
scFv_Pmpnn_AF2 Pipeline:

# Step 1: Convert antibody to scFv format
python scripts/scfv_anarci.py --input antibody.fasta --output scfv.fasta

# Step 2: Run AlphaFold2 + ProteinMPNN pipeline
bash af2_pmpnn.sh scfv.fasta output_dir/

# Step 3: Analyze results
python scripts/analyze_designs.py --input output_dir/ --output results.csv

Key scripts:
- scfv_anarci.py: scFv-ification of antibody sequences
- af2_pmpnn.sh: Main AlphaFold2 + ProteinMPNN pipeline
- analyze_designs.py: Result analysis
""",
        "usage_guide": """
## Quick Start Guide for scFv_Pmpnn_AF2

### 1. Installation
```bash
# Clone repository
git clone https://github.com/jbderoo/scFv_Pmpnn_AF2
cd scFv_Pmpnn_AF2

# Install dependencies
pip install -r requirements.txt

# Install ANARCI for antibody numbering
pip install anarci

# Install ProteinMPNN
git clone https://github.com/dauparas/ProteinMPNN
cd ProteinMPNN && pip install -e .

# Install LocalColabFold (follow their instructions)
```

### 2. Prepare Antibody Sequence
- Input: Heavy and light chain sequences
- Format: FASTA file

### 3. Run Pipeline
```bash
# Convert to scFv format
python scripts/scfv_anarci.py \\
    --vh_sequence "EVQLVESGG..." \\
    --vl_sequence "DIQMTQSPS..." \\
    --output scfv.fasta

# Run design pipeline
bash af2_pmpnn.sh scfv.fasta results/
```

### 4. Key Success Metrics
- 73% conversion success rate (vs 31% standard)
- 19/26 antibodies successfully converted
""",
        "recommended_parameters": {
            "design": {
                "num_designs": {"default": 100, "note": "Number of designs to generate"},
                "sampling_temp": {"default": 0.1, "note": "ProteinMPNN sampling temperature"}
            }
        },
        "install_instructions": """
```bash
# Clone repository
git clone https://github.com/jbderoo/scFv_Pmpnn_AF2
cd scFv_Pmpnn_AF2

# Create conda environment
conda create -n scfv python=3.8
conda activate scfv

# Install dependencies
pip install -r requirements.txt
pip install anarci

# Install ProteinMPNN
git clone https://github.com/dauparas/ProteinMPNN
pip install -e ProteinMPNN/

# Install LocalColabFold (optional but recommended)
# Follow instructions at: https://github.com/YoshitakaMo/localcolabfold
```
"""
    },

    "protrek": {
        "hardware_requirements": """
**For Web API (search-protrek.com):**
- No local requirements
- Free access to 5B+ proteins

**For Local Deployment:**
- GPU: NVIDIA GPU with 8GB+ VRAM
- RAM: 32GB
- Storage: 50GB (for models)
- Storage: 500GB+ (for FAISS indices of protein databases)

**For Custom Embeddings:**
- GPU: NVIDIA A100 40GB recommended
- RAM: 64GB
""",
        "dependencies": [
            "Python 3.10+",
            "PyTorch 2.0+",
            "Transformers",
            "FAISS (for similarity search)",
            "HuggingFace Hub",
            "gradio (for web interface)"
        ],
        "help_text": """
ProTrek Usage:

# Search modes:
- Sequence → Function: Find function from protein sequence
- Structure → Function: Find function from structure
- Function → Sequence: Find sequences matching description
- Sequence → Structure: Find structurally similar proteins
- All pairwise combinations supported

# Python API
from protrek import ProTrekTrimodalModel

model = ProTrekTrimodalModel.from_pretrained("westlake-repl/ProTrek_650M")

# Get embeddings
seq_emb = model.get_protein_repr(["MKTVRQERLK..."])
text_emb = model.get_text_repr(["ATP-binding kinase"])
struct_emb = model.get_structure_repr([foldseek_seq])

# Calculate similarity
similarity = torch.dot(seq_emb, text_emb) / model.temperature
""",
        "usage_guide": """
## Quick Start Guide for ProTrek

### 1. Web Interface (Easiest)
Visit: https://search-protrek.com
- No installation required
- Access to 5B+ proteins
- All search modes available

### 2. Local Installation
```bash
# Create environment
conda create -n protrek python=3.10
conda activate protrek

# Clone repository
git clone https://github.com/westlake-repl/ProTrek
cd ProTrek

# Download model weights
huggingface-cli download westlake-repl/ProTrek_650M \\
    --repo-type model \\
    --local-dir weights/ProTrek_650M
```

### 3. Run Local Server
```bash
python demo/run_pipeline.py
# Access at http://127.0.0.1:7860/
```

### 4. Python API for Custom Embeddings
```python
from model.ProTrek.protrek_trimodal_model import ProTrekTrimodalModel

config = {"model_path": "weights/ProTrek_650M"}
model = ProTrekTrimodalModel(**config).eval().cuda()

# Get 1024-dimensional embeddings
seq_embedding = model.get_protein_repr(["MKTVRQERLKSIVRILERSKEPVSGAQ"])
```

### Databases Available:
- SwissProt, UniRef50, ESMAtlas
- NCBI (700M sequences)
- GOPC (2B ocean microbiome)
- Total: 5B+ proteins
""",
        "recommended_parameters": {
            "search": {
                "top_k": {"default": 10, "note": "Number of results"},
                "temperature": {"default": 0.05, "note": "Similarity scaling"}
            }
        },
        "install_instructions": """
```bash
# Create environment
conda create -n protrek python=3.10 --yes
conda activate protrek

# Clone repository
git clone https://github.com/westlake-repl/ProTrek
cd ProTrek
pip install -r requirements.txt

# Download model weights from HuggingFace
huggingface-cli download westlake-repl/ProTrek_650M \\
    --repo-type model \\
    --local-dir weights/ProTrek_650M

# (Optional) Download FAISS indices for protein databases
# See README for database download instructions
```
"""
    },

    "profam1": {
        "primary_citation": {
            "doi": "10.1101/2025.12.19.695431",
            "title": "ProFam: Open-Source Protein Family Language Modelling for Fitness Prediction and Design",
            "authors": ["Alex Hh", "Jude Wells"],
            "journal": "bioRxiv",
            "year": 2025,
            "url": "https://www.biorxiv.org/content/10.1101/2025.12.19.695431"
        },
        "hardware_requirements": """
**Minimum Requirements:**
- GPU: NVIDIA GPU with 8GB VRAM
- RAM: 16GB
- Storage: 10GB

**Recommended:**
- GPU: NVIDIA A100 or better (for training)
- RAM: 32GB
- Storage: 50GB (for training data)

**For Inference Only:**
- GPU: NVIDIA T4 or consumer GPU
- RAM: 16GB
""",
        "dependencies": [
            "Python 3.8+",
            "PyTorch 2.0+",
            "Flash Attention (recommended for training)",
            "transformers",
            "numpy",
            "pandas"
        ],
        "help_text": """
ProFam-1 Usage:

# Load model
from profam import ProFam

model = ProFam.from_pretrained("profam-1")

# Predict fitness
fitness_scores = model.predict_fitness(
    sequences=["MKTVRQERLK...", "MKTVRQERLR..."],
    reference="MKTVRQERLK..."
)

# Generate variants
variants = model.generate(
    seed_sequence="MKTVRQERLK...",
    num_variants=100
)
""",
        "usage_guide": """
## Quick Start Guide for ProFam-1

### 1. Installation
```bash
git clone https://github.com/alex-hh/profam
cd profam
pip install -e .

# (Optional) Install Flash Attention for faster training
pip install flash-attn --no-build-isolation
```

### 2. Fitness Prediction
```python
from profam import ProFam

model = ProFam.from_pretrained("profam-1")

# Predict fitness of variants
sequences = [
    "MKTVRQERLKSIVRILERSKEPVSGAQ",  # Variant 1
    "MKTVRQERLKSIVRILERSKEPVSGAA",  # Variant 2
]
reference = "MKTVRQERLKSIVRILERSKEPVSGAQ"

fitness_scores = model.predict_fitness(
    sequences=sequences,
    reference=reference
)

for seq, score in zip(sequences, fitness_scores):
    print(f"Score: {score:.3f}")
```

### Key Features:
- 251M parameters
- State-of-the-art on ProteinGym benchmark
- No MSA required at inference
- Trained on 40M protein families
""",
        "recommended_parameters": {
            "prediction": {
                "batch_size": {"default": 32, "note": "Adjust based on GPU memory"},
                "temperature": {"default": 1.0, "note": "For generation"}
            }
        },
        "install_instructions": """
```bash
# Clone repository
git clone https://github.com/alex-hh/profam
cd profam

# Install package
pip install -e .

# (Optional) For training with Flash Attention
pip install flash-attn --no-build-isolation

# Download pre-trained weights (automatic on first use)
```
"""
    },

    "syncraft": {
        "primary_citation": {
            "doi": None,
            "arxiv": "2512.20333",
            "title": "SynCraft: Guiding Large Language Models to Predict Edit Sequences for Molecular Synthesizability Optimization",
            "authors": ["Peking University"],
            "journal": "arXiv",
            "year": 2025,
            "url": "https://arxiv.org/abs/2512.20333"
        },
        "hardware_requirements": """
**Requirements:**
- CPU: Modern multi-core processor
- RAM: 16GB
- Storage: 5GB
- Internet: Required for Gemini API calls

**No Local GPU Required** - uses Gemini-2.5-Pro API

**API Costs:**
- Gemini API: Pay-per-use
- Typical cost: ~$0.01-0.10 per molecule optimization
""",
        "dependencies": [
            "Python 3.8+",
            "RDKit",
            "AutoDock Vina",
            "PLIP (Protein-Ligand Interaction Profiler)",
            "Google Generative AI SDK (for Gemini)",
            "numpy",
            "pandas"
        ],
        "help_text": """
SynCraft Usage:

# Basic optimization
python syncraft.py --input molecule.smi --output optimized.smi

# With docking constraints
python syncraft.py \\
    --input molecule.smi \\
    --protein target.pdb \\
    --output optimized.smi \\
    --max_iterations 5

# Edit operations:
- DEL_ATOM: Delete an atom
- ADD_BOND: Add a bond
- DEL_BOND: Delete a bond
- CHANGE_BOND: Change bond type
""",
        "usage_guide": """
## Quick Start Guide for SynCraft

### 1. Installation
```bash
git clone https://github.com/catalystforyou/SynCraft-Core
cd SynCraft-Core
pip install -r requirements.txt

# Install AutoDock Vina
conda install -c conda-forge autodock-vina

# Set up Gemini API key
export GOOGLE_API_KEY="your-api-key"
```

### 2. Basic Usage
```python
from syncraft import SynCraft

optimizer = SynCraft(api_key="your-gemini-api-key")

# Optimize a molecule for synthesizability
result = optimizer.optimize(
    smiles="CC(=O)Nc1ccc(O)cc1",  # Input molecule
    max_iterations=5
)

print(f"Original: {result.original_smiles}")
print(f"Optimized: {result.optimized_smiles}")
print(f"Synthesizability improvement: {result.improvement}")
```

### 3. With Protein Target Constraint
```python
result = optimizer.optimize(
    smiles="CC(=O)Nc1ccc(O)cc1",
    protein_pdb="target.pdb",
    binding_site_residues=[45, 46, 47, 48],
    max_iterations=5
)
```

### Key Features:
- Chain-of-Thought prompting for interpretable edits
- Maintains binding activity while improving synthesis
- Uses AutoDock Vina for docking validation
""",
        "recommended_parameters": {
            "optimization": {
                "max_iterations": {"default": 5, "range": "1-10", "note": "More iterations = better but slower"},
                "temperature": {"default": 0.7, "note": "Gemini sampling temperature"}
            }
        }
    },

    "alphafold3": {
        "hardware_requirements": """
**For Local Installation:**
- GPU: NVIDIA GPU with 80GB+ VRAM (A100 or H100)
- GPU Compute Capability: 8.0+
- RAM: 128GB+
- Storage: Up to 1TB (for databases and model weights)
- OS: Linux only

**For AlphaFold Server (Recommended):**
- No local requirements
- Web browser only
- Limit: 20 predictions/day

**Note:** Consider using Boltz-2 (MIT license) for commercial use
""",
        "dependencies": [
            "Python 3.11",
            "Docker",
            "NVIDIA Container Toolkit",
            "CUDA 12.6+",
            "Model weights (request required)"
        ],
        "help_text": """
AlphaFold 3 Usage:

# Via AlphaFold Server (Recommended)
1. Visit: https://alphafoldserver.com
2. Sign in with Google account
3. Input sequences and run prediction
4. Download results

# Via AlphaFold Database API (Pre-computed)
curl "https://alphafold.ebi.ac.uk/api/prediction/P00520"

# Local Installation (Advanced)
docker run --gpus all alphafold3 \\
    --input input.json \\
    --output results/
""",
        "usage_guide": """
## Quick Start Guide for AlphaFold 3

### Option 1: AlphaFold Server (Easiest)
1. Visit https://alphafoldserver.com
2. Sign in with Google account
3. Enter sequences (protein, DNA, RNA, ligands)
4. Submit job (max 20/day)
5. Download PDB results

### Option 2: AlphaFold Database API (Pre-computed)
```python
import requests

# Get pre-computed structure
uniprot_id = "P00520"
response = requests.get(
    f"https://alphafold.ebi.ac.uk/api/prediction/{uniprot_id}"
)
data = response.json()

# Download PDB file
pdb_url = data["pdbUrl"]
pdb_content = requests.get(pdb_url).text
```

### Option 3: Local Installation (Advanced)
```bash
# Clone repository
git clone https://github.com/google-deepmind/alphafold3

# Request model weights (requires approval)
# Fill form at: https://forms.gle/svvpY4u2jsHEwWYS6

# Build Docker container
docker build -t alphafold3 .

# Run prediction
docker run --gpus all -v /data:/data alphafold3 \\
    --input /data/input.json \\
    --output /data/results
```

### Alternative: Use Boltz-2 (MIT License)
For commercial use, consider Boltz-2:
```bash
pip install boltz
boltz predict input.fasta
```

### Limitations:
- Non-commercial license (CC-BY-NC-SA)
- Web server: 20 predictions/day
- No drug-protein interaction predictions on server
""",
        "recommended_parameters": {
            "prediction": {
                "num_models": {"default": 5, "note": "Number of structure models"},
                "num_recycles": {"default": 3, "note": "Recycling iterations"}
            }
        },
        "install_instructions": """
**For AlphaFold Server (Recommended):**
No installation required - visit https://alphafoldserver.com

**For Local Installation:**
```bash
# Clone repository
git clone https://github.com/google-deepmind/alphafold3
cd alphafold3

# Request model weights (approval required)
# Form: https://forms.gle/svvpY4u2jsHEwWYS6

# Build Docker image
docker build -t alphafold3 .

# Run with Docker
docker run --gpus all \\
    -v /path/to/data:/data \\
    alphafold3 \\
    --input /data/input.json \\
    --output /data/output
```

**Note:** Model weights require separate request and approval from DeepMind.
"""
    }
}


def update_knowledge_json(json_path: Path):
    """Update the knowledge JSON with enhanced data"""
    with open(json_path) as f:
        data = json.load(f)

    for tool_id, enhanced in ENHANCED_DATA.items():
        if tool_id in data:
            for key, value in enhanced.items():
                if value is not None:
                    # Only update if current value is None/empty
                    current = data[tool_id].get(key)
                    if current is None or current == "" or current == []:
                        data[tool_id][key] = value
                        logger.info(f"Updated {tool_id}.{key}")
                    elif key == "primary_citation" and current is None:
                        data[tool_id][key] = value
                        logger.info(f"Updated {tool_id}.{key}")

    # Update timestamp
    for tool_id in data:
        data[tool_id]["last_updated"] = datetime.now().isoformat()

    with open(json_path, 'w') as f:
        json.dump(data, f, indent=2)

    logger.info(f"Saved enhanced knowledge to {json_path}")
    return data


def update_database(data: dict, db_path: Path):
    """Update the tool_knowledge table with enhanced data"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    for tool_id, tool in data.items():
        try:
            cursor.execute("""
                UPDATE tool_knowledge SET
                    primary_citation = ?,
                    use_cases = ?,
                    limitations = ?,
                    alternatives = ?,
                    recommended_parameters = ?,
                    benchmark_papers = ?,
                    last_updated = ?
                WHERE tool_id = ?
            """, (
                json.dumps(tool.get("primary_citation")) if tool.get("primary_citation") else None,
                json.dumps(tool.get("use_cases")) if tool.get("use_cases") else None,
                json.dumps(tool.get("limitations")) if tool.get("limitations") else None,
                json.dumps(tool.get("alternatives")) if tool.get("alternatives") else None,
                json.dumps(tool.get("recommended_parameters")) if tool.get("recommended_parameters") else None,
                json.dumps(tool.get("benchmark_papers")) if tool.get("benchmark_papers") else None,
                tool.get("last_updated"),
                tool_id
            ))
            logger.info(f"Updated database for {tool_id}")
        except Exception as e:
            logger.error(f"Error updating {tool_id}: {e}")

    conn.commit()
    conn.close()


def print_audit(data: dict):
    """Print final audit"""
    print("\n" + "=" * 80)
    print("ENHANCED KNOWLEDGE AUDIT")
    print("=" * 80)

    fields = ['primary_citation', 'hardware_requirements', 'dependencies',
              'help_text', 'usage_guide', 'recommended_parameters',
              'install_instructions', 'benchmark_papers']

    for tool_id, tool in data.items():
        present = sum(1 for f in fields if tool.get(f) and tool[f] != "" and tool[f] != [])
        total = len(fields)
        pct = present / total * 100
        status = "✓" if pct >= 80 else "△" if pct >= 50 else "✗"
        print(f"{status} {tool_id:20} {present}/{total} fields ({pct:.0f}%)")

    print()


def main():
    script_dir = Path(__file__).parent.parent
    json_path = script_dir / "data/new_tools_knowledge.json"
    db_path = Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db")

    # Update JSON
    data = update_knowledge_json(json_path)

    # Update database
    update_database(data, db_path)

    # Print audit
    print_audit(data)


if __name__ == "__main__":
    main()
