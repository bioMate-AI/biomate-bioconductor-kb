#!/usr/bin/env python3
"""
Add New Tools to Main Tool Index

Adds the 10 new cutting-edge tools to the main `tools` table
with all detailed information for Biomate to use.
"""

import json
import sqlite3
import logging
from datetime import datetime
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Tool definitions with all fields for the tools table
TOOLS_DATA = [
    {
        "tool_id": "auto_state",
        "name": "State",
        "version": "1.0.0",
        "repo_owner": "ArcInstitute",
        "repo_name": "state",
        "category": "Single Cell Analysis",
        "description": "Arc Institute's virtual cell model for predicting cellular perturbation responses. Uses State Embedding (SE) for transcriptome vectorization and State Transition (ST) for response prediction. Trained on 270M+ cells including Tahoe-100M dataset.",
        "github_url": "https://github.com/ArcInstitute/state",
        "url": "https://arcinstitute.org/tools/state",
        "language": "Python",
        "topics": json.dumps(["single-cell", "perturbation", "virtual-cell", "drug-response", "transcriptomics"]),
        "help_text": """State CLI Commands:

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
  state tx preprocess_infer   # Preprocess inference data""",
        "usage_guide": """## Quick Start Guide for State

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
Download models from HuggingFace: https://huggingface.co/arcinstitute

```bash
state tx infer \\
  --output_dir /path/to/model/ \\
  --checkpoint final.ckpt \\
  --adata /path/to/data.h5ad \\
  --pert_col gene \\
  --embed_key X_hvg
```

### Key Concepts:
- **State Embedding (SE)**: Converts transcriptomes to vector space
- **State Transition (ST)**: Predicts perturbation responses
- **TOML config**: Defines datasets, splits, and evaluation paradigms""",
        "examples": """# Installation
uv tool install arc-state

# Training example
state tx train \\
  data.kwargs.toml_config_path="examples/fewshot.toml" \\
  data.kwargs.embed_key=X_hvg \\
  training.max_steps=40000 \\
  training.batch_size=8 \\
  model=pertsets

# Inference example
state tx infer \\
  --output_dir /path/to/model/ \\
  --checkpoint final.ckpt \\
  --adata /path/to/data.h5ad""",
        "scientific_context": "State is designed for predicting how cells respond to perturbations (drugs, genetic modifications, cytokines). It's particularly useful for drug screening, understanding disease mechanisms, and identifying therapeutic targets. The model excels at predicting responses across different cell types and perturbation conditions.",
        "parameters": json.dumps({
            "training": {
                "batch_size": {"default": 8, "type": "int", "description": "Training batch size"},
                "learning_rate": {"default": 1e-4, "type": "float", "description": "Learning rate"},
                "max_steps": {"default": 40000, "type": "int", "description": "Maximum training steps"}
            },
            "model": {
                "hidden_dim": {"default": 328, "type": "int", "description": "Hidden dimension"},
                "cell_set_len": {"default": 64, "type": "int", "description": "Cell set length"}
            }
        }),
        "inputs": json.dumps([
            {"name": "adata", "type": "h5ad", "description": "AnnData file with single-cell data"},
            {"name": "toml_config", "type": "toml", "description": "Configuration file for experiment"}
        ]),
        "outputs": json.dumps([
            {"name": "predictions", "type": "h5ad", "description": "Predicted perturbation responses"},
            {"name": "embeddings", "type": "h5ad", "description": "Cell embeddings (SE mode)"}
        ]),
        "requirements": json.dumps(["uv", "Python>=3.10", "PyTorch>=2.0", "scanpy", "anndata"]),
        "dependencies": json.dumps(["uv", "torch", "scanpy", "anndata", "numpy", "pandas", "wandb"]),
        "install_commands": "uv tool install arc-state",
        "best_practice_domains": json.dumps(["single-cell-analysis", "drug-discovery", "perturbation-biology"]),
        "best_practice_functions": json.dumps(["Predict drug responses", "Analyze perturbation effects", "Cell state modeling"]),
        "citations": "Arc Institute. Predicting cellular responses to perturbation across diverse contexts with State. bioRxiv 2025. doi:10.1101/2025.06.26.661135",
        "edam_operations": json.dumps(["operation_3223"]),  # Differential expression analysis
        "edam_topics": json.dumps(["topic_3308", "topic_0203"]),  # Transcriptomics, Gene expression
        "tags": json.dumps(["virtual-cell", "perturbation", "single-cell", "drug-response", "arc-institute"]),
        "quality_score": 0.95,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_chai1",
        "name": "Chai-1",
        "version": "0.6.1",
        "repo_owner": "chaidiscovery",
        "repo_name": "chai-lab",
        "category": "Structure Prediction",
        "description": "Multi-modal foundation model for molecular structure prediction. Achieves state-of-the-art accuracy for proteins, small molecules, DNA, RNA, glycosylations, and ligand complexes. Apache 2.0 licensed for commercial use.",
        "github_url": "https://github.com/chaidiscovery/chai-lab",
        "url": "https://lab.chaidiscovery.com",
        "language": "Python",
        "topics": json.dumps(["protein-structure", "structure-prediction", "deep-learning", "alphafold-alternative", "drug-discovery"]),
        "help_text": """Chai-1 CLI Commands:

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

Web Interface: https://lab.chaidiscovery.com""",
        "usage_guide": """## Quick Start Guide for Chai-1

### 1. Installation
```bash
pip install chai_lab==0.6.1
```

### 2. Basic Structure Prediction
```bash
chai-lab fold input.fasta output_folder
```

### 3. With MSA Enhancement (Recommended for best results)
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

### Hardware Requirements:
- GPU: A100 80GB or H100 80GB recommended
- Also works: L40S 48GB, A10, A30, RTX 4090 (smaller complexes)
- Proteins: up to 1,024 residues
- DNA/RNA: up to 3,072 bases""",
        "examples": """# Install
pip install chai_lab==0.6.1

# Basic prediction
chai-lab fold input.fasta output/

# With MSA (recommended)
chai-lab fold --use-msa-server --use-templates-server input.fasta output/

# Python API
from chai_lab.chai1 import run_inference
candidates = run_inference(
    fasta_file="complex.fasta",
    output_dir="./output"
)""",
        "scientific_context": "Chai-1 is ideal for predicting structures of biomolecular complexes including protein-ligand, protein-DNA, and protein-RNA interactions. It's particularly useful in drug discovery for understanding binding modes and in structural biology for hypothesis generation.",
        "parameters": json.dumps({
            "inference": {
                "num_trunk_recycles": {"default": 3, "type": "int", "description": "Number of trunk recycles (more = better but slower)"},
                "num_diffn_timesteps": {"default": 200, "type": "int", "description": "Diffusion timesteps (more = higher quality)"},
                "use_esm_embeddings": {"default": True, "type": "bool", "description": "Use ESM embeddings for improved accuracy"},
                "use_msa_server": {"default": False, "type": "bool", "description": "Use ColabFold MSA server"}
            }
        }),
        "inputs": json.dumps([
            {"name": "fasta_file", "type": "fasta", "description": "FASTA file with sequences"},
            {"name": "msa_file", "type": "a3m/pqt", "description": "Optional MSA file"}
        ]),
        "outputs": json.dumps([
            {"name": "structure", "type": "pdb/cif", "description": "Predicted structure"},
            {"name": "confidence", "type": "json", "description": "pLDDT and PAE scores"}
        ]),
        "requirements": json.dumps(["Python>=3.10", "PyTorch>=2.0", "CUDA", "bfloat16 GPU support", "Linux"]),
        "dependencies": json.dumps(["torch", "numpy", "biopython"]),
        "install_commands": "pip install chai_lab==0.6.1",
        "container_info": json.dumps({"gpu_required": True, "min_vram": "24GB", "recommended_vram": "80GB"}),
        "best_practice_domains": json.dumps(["structure-prediction", "drug-discovery", "structural-biology"]),
        "best_practice_functions": json.dumps(["Predict protein structures", "Model protein-ligand complexes", "Analyze binding modes"]),
        "citations": "Chai Discovery. Chai-1: Decoding the molecular interactions of life. bioRxiv 2024. doi:10.1101/2024.10.10.615955",
        "edam_operations": json.dumps(["operation_0474"]),  # Protein structure prediction
        "edam_topics": json.dumps(["topic_0082", "topic_2275"]),  # Structure prediction, Molecular modelling
        "tags": json.dumps(["structure-prediction", "protein-folding", "drug-discovery", "alphafold-alternative", "apache-license"]),
        "quality_score": 0.98,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_boltz2",
        "name": "Boltz-2",
        "version": "latest",
        "repo_owner": "jwohlwend",
        "repo_name": "boltz",
        "category": "Structure Prediction",
        "description": "Biomolecular foundation model for predicting structures of proteins, RNA, DNA, ligands, and binding affinities. MIT licensed - fully open for commercial use. 1000x faster than physics-based FEP methods.",
        "github_url": "https://github.com/jwohlwend/boltz",
        "url": "https://github.com/jwohlwend/boltz",
        "language": "Python",
        "topics": json.dumps(["protein-structure", "binding-affinity", "drug-discovery", "molecular-docking", "mit-license"]),
        "help_text": """Boltz CLI Commands:

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

boltz --help                 Show all commands""",
        "usage_guide": """## Quick Start Guide for Boltz-2

### 1. Installation
```bash
pip install boltz
```

### 2. Predict Structure
```bash
boltz predict input.fasta --output_dir results/
```

### 3. Protein-Ligand Complex (YAML input)
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
- **MIT License** - fully commercial use allowed
- Joint structure + affinity prediction
- 1000x faster than FEP methods""",
        "examples": """# Install
pip install boltz

# Predict structure
boltz predict input.fasta --output_dir results/

# With ligand (YAML)
boltz predict complex.yaml

# Python API
from boltz import Boltz
model = Boltz()
result = model.predict(
    protein_sequence="MKTVRQERLK...",
    ligand_smiles="CCO"
)""",
        "scientific_context": "Boltz-2 is the open-source alternative to AlphaFold 3 with MIT license. It jointly predicts structure and binding affinity, making it ideal for drug discovery applications where commercial use is required.",
        "parameters": json.dumps({
            "prediction": {
                "num_samples": {"default": 1, "type": "int", "description": "Number of samples"},
                "diffusion_samples": {"default": 1, "type": "int", "description": "Diffusion samples"},
                "recycling_steps": {"default": 3, "type": "int", "description": "Recycling iterations"}
            }
        }),
        "inputs": json.dumps([
            {"name": "sequence", "type": "fasta/yaml", "description": "Protein sequence or complex definition"},
            {"name": "ligand", "type": "smiles", "description": "Ligand SMILES (optional)"}
        ]),
        "outputs": json.dumps([
            {"name": "structure", "type": "cif", "description": "Predicted structure"},
            {"name": "affinity", "type": "json", "description": "Binding affinity prediction"}
        ]),
        "requirements": json.dumps(["Python>=3.10", "PyTorch>=2.0", "CUDA"]),
        "dependencies": json.dumps(["torch", "numpy"]),
        "install_commands": "pip install boltz",
        "container_info": json.dumps({"gpu_required": True, "min_vram": "16GB", "recommended_vram": "40GB"}),
        "best_practice_domains": json.dumps(["drug-discovery", "structure-prediction", "molecular-docking"]),
        "best_practice_functions": json.dumps(["Protein-ligand docking", "Binding affinity prediction", "Structure prediction"]),
        "citations": "Wohlwend et al. Boltz-2: A unified model for biomolecular structure and affinity prediction. MIT/Recursion 2025.",
        "edam_operations": json.dumps(["operation_0474", "operation_2492"]),  # Structure prediction, Docking
        "edam_topics": json.dumps(["topic_2275", "topic_3336"]),  # Molecular modelling, Drug discovery
        "tags": json.dumps(["structure-prediction", "binding-affinity", "drug-discovery", "mit-license", "open-source"]),
        "quality_score": 0.96,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_evo2",
        "name": "Evo 2",
        "version": "1.0.0",
        "repo_owner": "ArcInstitute",
        "repo_name": "evo2",
        "category": "Genomics",
        "description": "40 billion parameter DNA foundation model trained on 9 trillion nucleotides from 100,000+ species. Supports 1 million base pair context length for genome-scale predictions. Available via NVIDIA NIM API.",
        "github_url": "https://github.com/ArcInstitute/evo2",
        "url": "https://arcinstitute.org/news/evo2",
        "language": "Python",
        "topics": json.dumps(["genomics", "dna", "foundation-model", "mutation-prediction", "genome-design"]),
        "help_text": """Evo 2 Usage:

# NVIDIA NIM API (Recommended - no local GPU needed)
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

# Local Python API (requires large GPU)
from evo2 import Evo2
model = Evo2.from_pretrained("arcinstitute/evo2-7b")
output = model.generate(sequence="ATCG...", max_length=1000)""",
        "usage_guide": """## Quick Start Guide for Evo 2

### Option 1: NVIDIA NIM API (Recommended)
No local GPU required - 40 requests/minute free tier

```python
import requests

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

### Option 2: Local Installation (Large GPU required)
```bash
# Install dependencies
conda install -c nvidia cuda-nvcc cuda-cudart-dev
pip install flash-attn==2.8.0.post2 --no-build-isolation

# Install Evo 2
pip install evo2
```

### Taxonomy-Guided Generation
```python
# Bias toward E. coli genome patterns
sequence = "|D__BACTERIA;P__PSEUDOMONADOTA;C__GAMMAPROTEOBACTERIA|ATCGATCG"
```

### Key Capabilities:
- Disease mutation prediction
- Genome design and generation
- Cross-species DNA analysis
- 1M base pair context length""",
        "examples": """# NVIDIA NIM API
import requests
response = requests.post(
    "https://integrate.api.nvidia.com/v1/biology/arc/evo2/generate",
    headers={"Authorization": "Bearer $NGC_API_KEY"},
    json={"sequence": "ATCGATCG", "num_tokens": 100}
)

# Taxonomy-guided generation
sequence = "|D__BACTERIA;...|ATCGATCG"

# Local (requires A100+)
from evo2 import Evo2
model = Evo2.from_pretrained("arcinstitute/evo2-7b")
output = model.generate("ATCG...", max_length=1000)""",
        "scientific_context": "Evo 2 is designed for genome-scale DNA analysis and generation. It excels at predicting effects of mutations, designing synthetic genomes, and analyzing sequences across all domains of life with single-nucleotide resolution.",
        "parameters": json.dumps({
            "generation": {
                "temperature": {"default": 1.0, "type": "float", "description": "Sampling temperature"},
                "top_k": {"default": 4, "type": "int", "description": "Top-k sampling"},
                "num_tokens": {"default": 100, "type": "int", "description": "Tokens to generate (up to 1M)"}
            }
        }),
        "inputs": json.dumps([
            {"name": "sequence", "type": "dna", "description": "DNA sequence (ATCG)"},
            {"name": "taxonomy", "type": "string", "description": "Optional taxonomy prefix for guided generation"}
        ]),
        "outputs": json.dumps([
            {"name": "generated_sequence", "type": "dna", "description": "Generated DNA sequence"},
            {"name": "log_probs", "type": "json", "description": "Token log probabilities"}
        ]),
        "requirements": json.dumps(["NVIDIA NIM API key", "OR: Python>=3.10, CUDA 12.0+, A100 GPU"]),
        "dependencies": json.dumps(["torch", "flash-attn", "transformer-engine"]),
        "install_commands": "pip install evo2  # OR use NVIDIA NIM API",
        "container_info": json.dumps({"api_available": "NVIDIA NIM", "api_rate_limit": "40/min", "local_gpu": "A100 80GB+"}),
        "best_practice_domains": json.dumps(["genomics", "synthetic-biology", "variant-analysis"]),
        "best_practice_functions": json.dumps(["Mutation effect prediction", "Genome design", "Cross-species analysis"]),
        "citations": "Arc Institute et al. Evo 2: A 40 billion parameter DNA foundation model. Arc Institute 2025.",
        "edam_operations": json.dumps(["operation_3197", "operation_3227"]),  # Genetic variation analysis
        "edam_topics": json.dumps(["topic_0622", "topic_3053"]),  # Genomics, Genetics
        "tags": json.dumps(["genomics", "dna", "foundation-model", "nvidia-nim", "arc-institute"]),
        "quality_score": 0.97,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_drugclip",
        "name": "DrugCLIP",
        "version": "1.0.0",
        "repo_owner": "bowen-gao",
        "repo_name": "DrugCLIP",
        "category": "Drug Discovery",
        "description": "Contrastive learning framework for virtual screening that is 10 million times faster than traditional docking methods. Published in Science 2026. Screened 10K proteins × 500M compounds.",
        "github_url": "https://github.com/bowen-gao/DrugCLIP",
        "url": "https://drugclip.com",
        "language": "Python",
        "topics": json.dumps(["drug-discovery", "virtual-screening", "contrastive-learning", "deep-learning"]),
        "help_text": """DrugCLIP Usage:

# Encode protein pocket
python encode_pocket.py --input pockets.csv --output pocket_embeddings.pt

# Encode molecules
python encode_molecule.py --input molecules.smi --output mol_embeddings.pt

# Screen
python screen.py --pockets pocket_embeddings.pt --molecules mol_embeddings.pt --output hits.csv

# Full pipeline
python drugclip_screen.py --protein target.pdb --library compounds.smi --output results/""",
        "usage_guide": """## Quick Start Guide for DrugCLIP

### 1. Installation
```bash
git clone https://github.com/bowen-gao/DrugCLIP
cd DrugCLIP
conda create -n drugclip python=3.8
conda activate drugclip
conda install -c conda-forge rdkit=2022.9.5
pip install -r requirements.txt
```

### 2. Run Screening
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
- Genome-wide screening capability""",
        "examples": """# Installation
git clone https://github.com/bowen-gao/DrugCLIP
conda install -c conda-forge rdkit=2022.9.5

# Screening
from drugclip import DrugCLIP
model = DrugCLIP.load_pretrained()
pocket_emb = model.encode_pocket("target.pdb")
mol_embs = model.encode_molecules(["CCO", "CC(=O)O"])
scores = model.similarity(pocket_emb, mol_embs)""",
        "scientific_context": "DrugCLIP enables genome-wide virtual screening by reformulating the problem as dense retrieval using contrastive learning. It's ideal for early-stage drug discovery when screening large compound libraries against multiple targets.",
        "parameters": json.dumps({
            "screening": {
                "top_k": {"default": 100, "type": "int", "description": "Number of hits to return"},
                "threshold": {"default": 0.5, "type": "float", "description": "Similarity threshold"}
            }
        }),
        "inputs": json.dumps([
            {"name": "pocket", "type": "pdb", "description": "Protein pocket structure"},
            {"name": "molecules", "type": "smiles", "description": "Compound library"}
        ]),
        "outputs": json.dumps([
            {"name": "hits", "type": "csv", "description": "Ranked hit compounds"},
            {"name": "scores", "type": "tensor", "description": "Similarity scores"}
        ]),
        "requirements": json.dumps(["Python>=3.8", "RDKit 2022.9.5", "PyTorch"]),
        "dependencies": json.dumps(["torch", "rdkit", "numpy", "pandas"]),
        "install_commands": "git clone https://github.com/bowen-gao/DrugCLIP && pip install -r requirements.txt",
        "best_practice_domains": json.dumps(["drug-discovery", "virtual-screening", "hit-identification"]),
        "best_practice_functions": json.dumps(["Virtual screening", "Hit identification", "Target fishing"]),
        "citations": "Gao et al. DrugCLIP enables genome-wide virtual screening. Science 2026. doi:10.1126/science.ads9530",
        "edam_operations": json.dumps(["operation_0482"]),  # Protein-ligand docking
        "edam_topics": json.dumps(["topic_3336", "topic_3343"]),  # Drug discovery, Compound screening
        "tags": json.dumps(["virtual-screening", "drug-discovery", "contrastive-learning", "science-publication"]),
        "quality_score": 0.95,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_scfv_pmpnn_af2",
        "name": "scFv_Pmpnn_AF2",
        "version": "1.0.0",
        "repo_owner": "jbderoo",
        "repo_name": "scFv_Pmpnn_AF2",
        "category": "Protein Design",
        "description": "AI pipeline integrating AlphaFold2 and ProteinMPNN for converting antibodies to functional scFv intrabodies. Achieves 73% success rate compared to 31% with standard methods. Published in Science Advances 2026.",
        "github_url": "https://github.com/jbderoo/scFv_Pmpnn_AF2",
        "url": "https://github.com/jbderoo/scFv_Pmpnn_AF2",
        "language": "Python",
        "topics": json.dumps(["protein-design", "antibody", "intrabody", "alphafold", "proteinmpnn"]),
        "help_text": """scFv_Pmpnn_AF2 Pipeline:

# Step 1: Convert antibody to scFv format
python scripts/scfv_anarci.py --input antibody.fasta --output scfv.fasta

# Step 2: Run AlphaFold2 + ProteinMPNN pipeline
bash af2_pmpnn.sh scfv.fasta output_dir/

# Step 3: Analyze results
python scripts/analyze_designs.py --input output_dir/ --output results.csv

Key scripts:
- scfv_anarci.py: scFv-ification of antibody sequences (ANARCI numbering)
- af2_pmpnn.sh: Main AlphaFold2 + ProteinMPNN pipeline
- analyze_designs.py: Result analysis""",
        "usage_guide": """## Quick Start Guide for scFv_Pmpnn_AF2

### 1. Installation
```bash
git clone https://github.com/jbderoo/scFv_Pmpnn_AF2
cd scFv_Pmpnn_AF2
pip install -r requirements.txt
pip install anarci

# Install ProteinMPNN
git clone https://github.com/dauparas/ProteinMPNN
pip install -e ProteinMPNN/
```

### 2. Run Pipeline
```bash
# Convert to scFv format
python scripts/scfv_anarci.py \\
    --vh_sequence "EVQLVESGG..." \\
    --vl_sequence "DIQMTQSPS..." \\
    --output scfv.fasta

# Run design pipeline
bash af2_pmpnn.sh scfv.fasta results/
```

### Key Success Metrics:
- 73% conversion success rate (vs 31% standard)
- 19/26 antibodies successfully converted""",
        "examples": """# Install dependencies
pip install anarci
git clone https://github.com/dauparas/ProteinMPNN

# Convert antibody to scFv
python scripts/scfv_anarci.py \\
    --vh_sequence "EVQLVESGG..." \\
    --vl_sequence "DIQMTQSPS..." \\
    --output scfv.fasta

# Run pipeline
bash af2_pmpnn.sh scfv.fasta results/""",
        "scientific_context": "This pipeline is designed for researchers who need to convert existing antibodies into intrabodies for intracellular applications. It's particularly useful for creating tools to study chromatin dynamics and intracellular signaling.",
        "parameters": json.dumps({
            "design": {
                "num_designs": {"default": 100, "type": "int", "description": "Number of designs to generate"},
                "sampling_temp": {"default": 0.1, "type": "float", "description": "ProteinMPNN sampling temperature"}
            }
        }),
        "inputs": json.dumps([
            {"name": "vh_sequence", "type": "protein", "description": "Heavy chain variable region"},
            {"name": "vl_sequence", "type": "protein", "description": "Light chain variable region"}
        ]),
        "outputs": json.dumps([
            {"name": "scfv_designs", "type": "fasta", "description": "Designed scFv sequences"},
            {"name": "structures", "type": "pdb", "description": "Predicted structures"}
        ]),
        "requirements": json.dumps(["Python>=3.8", "ProteinMPNN", "LocalColabFold", "ANARCI"]),
        "dependencies": json.dumps(["torch", "anarci", "biopython", "numpy"]),
        "install_commands": "git clone https://github.com/jbderoo/scFv_Pmpnn_AF2 && pip install -r requirements.txt",
        "container_info": json.dumps({"gpu_required": True, "min_vram": "16GB"}),
        "best_practice_domains": json.dumps(["antibody-engineering", "protein-design", "intrabody-development"]),
        "best_practice_functions": json.dumps(["Convert antibodies to intrabodies", "scFv design", "Antibody engineering"]),
        "citations": "Deroo et al. AI-assisted protein design to rapidly convert sequences to intrabodies. Science Advances 2026. doi:10.1126/sciadv.adx8352",
        "edam_operations": json.dumps(["operation_0321"]),  # Protein model validation
        "edam_topics": json.dumps(["topic_2830", "topic_0130"]),  # Immunoproteins, Protein folding
        "tags": json.dumps(["antibody", "intrabody", "protein-design", "alphafold", "proteinmpnn"]),
        "quality_score": 0.92,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_protrek",
        "name": "ProTrek",
        "version": "650M",
        "repo_owner": "westlake-repl",
        "repo_name": "ProTrek",
        "category": "Protein Analysis",
        "description": "Trimodal protein language model unifying sequence, structure, and function through contrastive learning. Enables advanced protein searches across 5B+ proteins. Published in Nature Biotechnology 2025.",
        "github_url": "https://github.com/westlake-repl/ProTrek",
        "url": "https://search-protrek.com",
        "language": "Python",
        "topics": json.dumps(["protein-language-model", "protein-search", "embeddings", "trimodal", "function-prediction"]),
        "help_text": """ProTrek Usage:

# Web Interface (No installation)
Visit: https://search-protrek.com

# Search modes:
- Sequence → Function
- Structure → Function
- Function → Sequence
- Sequence → Structure
- All pairwise combinations

# Python API
from protrek import ProTrekTrimodalModel

model = ProTrekTrimodalModel.from_pretrained("westlake-repl/ProTrek_650M")

# Get embeddings
seq_emb = model.get_protein_repr(["MKTVRQERLK..."])
text_emb = model.get_text_repr(["ATP-binding kinase"])

# Calculate similarity
similarity = torch.dot(seq_emb, text_emb) / model.temperature""",
        "usage_guide": """## Quick Start Guide for ProTrek

### Option 1: Web Interface (Easiest)
Visit: https://search-protrek.com
- No installation required
- Access to 5B+ proteins

### Option 2: Local Installation
```bash
conda create -n protrek python=3.10
conda activate protrek
git clone https://github.com/westlake-repl/ProTrek
cd ProTrek

# Download model
huggingface-cli download westlake-repl/ProTrek_650M \\
    --repo-type model \\
    --local-dir weights/ProTrek_650M
```

### Python API for Custom Embeddings
```python
from model.ProTrek.protrek_trimodal_model import ProTrekTrimodalModel

config = {"model_path": "weights/ProTrek_650M"}
model = ProTrekTrimodalModel(**config).eval().cuda()

# Get 1024-dimensional embeddings
seq_embedding = model.get_protein_repr(["MKTVRQERLK..."])
```

### Databases Available:
- SwissProt, UniRef50, ESMAtlas
- NCBI (700M), GOPC (2B)
- Total: 5B+ proteins""",
        "examples": """# Web search
Visit https://search-protrek.com

# Local installation
conda create -n protrek python=3.10
huggingface-cli download westlake-repl/ProTrek_650M

# Python API
from protrek import ProTrekTrimodalModel
model = ProTrekTrimodalModel.from_pretrained("ProTrek_650M")
seq_emb = model.get_protein_repr(["MKTVRQERLK..."])
text_emb = model.get_text_repr(["kinase activity"])
similarity = torch.dot(seq_emb, text_emb)""",
        "scientific_context": "ProTrek enables searching proteins by function description, finding functionally similar proteins, and annotating unknown proteins. It's faster and more accurate than Foldseek and MMseqs2 for many tasks.",
        "parameters": json.dumps({
            "search": {
                "top_k": {"default": 10, "type": "int", "description": "Number of results"},
                "temperature": {"default": 0.05, "type": "float", "description": "Similarity scaling"}
            }
        }),
        "inputs": json.dumps([
            {"name": "sequence", "type": "protein", "description": "Protein sequence"},
            {"name": "structure", "type": "foldseek", "description": "3Di structure sequence"},
            {"name": "function", "type": "text", "description": "Function description"}
        ]),
        "outputs": json.dumps([
            {"name": "embeddings", "type": "tensor", "description": "1024-dim embeddings"},
            {"name": "search_results", "type": "json", "description": "Similar proteins"}
        ]),
        "requirements": json.dumps(["Python>=3.10", "PyTorch>=2.0", "HuggingFace"]),
        "dependencies": json.dumps(["torch", "transformers", "faiss", "gradio"]),
        "install_commands": "pip install protrek  # OR use web API at search-protrek.com",
        "container_info": json.dumps({"api_available": "search-protrek.com", "local_gpu": "8GB+"}),
        "best_practice_domains": json.dumps(["protein-function", "sequence-analysis", "database-search"]),
        "best_practice_functions": json.dumps(["Protein function search", "Functional annotation", "Similarity search"]),
        "citations": "Su et al. A trimodal protein language model enables advanced protein searches. Nature Biotechnology 2025. doi:10.1038/s41587-025-02836-0",
        "edam_operations": json.dumps(["operation_0346", "operation_2421"]),  # Sequence similarity search
        "edam_topics": json.dumps(["topic_0078", "topic_0080"]),  # Proteins, Sequence analysis
        "tags": json.dumps(["protein-search", "embeddings", "trimodal", "nature-biotechnology", "function-prediction"]),
        "quality_score": 0.96,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_profam1",
        "name": "ProFam-1",
        "version": "1.0.0",
        "repo_owner": "alex-hh",
        "repo_name": "profam",
        "category": "Protein Analysis",
        "description": "251M parameter autoregressive protein family language model for fitness prediction. Achieves state-of-the-art on ProteinGym benchmark (0.47 substitutions, 0.53 indels) without requiring MSA at inference.",
        "github_url": "https://github.com/alex-hh/profam",
        "url": "https://github.com/alex-hh/profam",
        "language": "Python",
        "topics": json.dumps(["protein-language-model", "fitness-prediction", "protein-family", "autoregressive"]),
        "help_text": """ProFam-1 Usage:

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
)""",
        "usage_guide": """## Quick Start Guide for ProFam-1

### 1. Installation
```bash
git clone https://github.com/alex-hh/profam
cd profam
pip install -e .

# Optional: Flash Attention for faster training
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
- State-of-the-art on ProteinGym
- No MSA required at inference
- Trained on 40M protein families""",
        "examples": """# Install
git clone https://github.com/alex-hh/profam
pip install -e .

# Fitness prediction
from profam import ProFam
model = ProFam.from_pretrained("profam-1")

fitness = model.predict_fitness(
    sequences=["MKTVRQERLK...", "MKTVRQERLR..."],
    reference="MKTVRQERLK..."
)""",
        "scientific_context": "ProFam-1 is designed for predicting the fitness effects of protein mutations without requiring multiple sequence alignments. It's ideal for directed evolution experiments and variant effect prediction.",
        "parameters": json.dumps({
            "prediction": {
                "batch_size": {"default": 32, "type": "int", "description": "Inference batch size"},
                "temperature": {"default": 1.0, "type": "float", "description": "Generation temperature"}
            }
        }),
        "inputs": json.dumps([
            {"name": "sequences", "type": "protein", "description": "Variant sequences"},
            {"name": "reference", "type": "protein", "description": "Reference sequence"}
        ]),
        "outputs": json.dumps([
            {"name": "fitness_scores", "type": "float", "description": "Predicted fitness values"}
        ]),
        "requirements": json.dumps(["Python>=3.8", "PyTorch>=2.0"]),
        "dependencies": json.dumps(["torch", "transformers", "numpy"]),
        "install_commands": "git clone https://github.com/alex-hh/profam && pip install -e .",
        "best_practice_domains": json.dumps(["protein-engineering", "directed-evolution", "variant-analysis"]),
        "best_practice_functions": json.dumps(["Fitness prediction", "Variant effect prediction", "Protein design"]),
        "citations": "Hh & Wells. ProFam: Open-Source Protein Family Language Modelling for Fitness Prediction and Design. bioRxiv 2025. doi:10.1101/2025.12.19.695431",
        "edam_operations": json.dumps(["operation_0331"]),  # Protein modelling (mutation)
        "edam_topics": json.dumps(["topic_3510", "topic_0130"]),  # Protein sites, Protein folding
        "tags": json.dumps(["fitness-prediction", "protein-family", "directed-evolution", "proteingym"]),
        "quality_score": 0.91,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_syncraft",
        "name": "SynCraft",
        "version": "1.0.0",
        "repo_owner": "catalystforyou",
        "repo_name": "SynCraft-Core",
        "category": "Drug Discovery",
        "description": "LLM-guided framework for molecular synthesizability optimization using Chain-of-Thought prompting with Gemini-2.5-Pro. Predicts atom-level edits (DEL_ATOM, ADD_BOND, DEL_BOND, CHANGE_BOND).",
        "github_url": "https://github.com/catalystforyou/SynCraft-Core",
        "url": "https://github.com/catalystforyou/SynCraft-Core",
        "language": "Python",
        "topics": json.dumps(["drug-discovery", "synthesizability", "llm", "molecule-optimization"]),
        "help_text": """SynCraft Usage:

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
- CHANGE_BOND: Change bond type""",
        "usage_guide": """## Quick Start Guide for SynCraft

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

# Optimize for synthesizability
result = optimizer.optimize(
    smiles="CC(=O)Nc1ccc(O)cc1",
    max_iterations=5
)

print(f"Optimized: {result.optimized_smiles}")
```

### 3. With Protein Constraint
```python
result = optimizer.optimize(
    smiles="CC(=O)Nc1ccc(O)cc1",
    protein_pdb="target.pdb",
    binding_site_residues=[45, 46, 47, 48]
)
```

### Key Features:
- Chain-of-Thought for interpretable edits
- Maintains binding while improving synthesis
- Uses AutoDock Vina for validation""",
        "examples": """# Install
git clone https://github.com/catalystforyou/SynCraft-Core
export GOOGLE_API_KEY="your-key"

# Optimize molecule
from syncraft import SynCraft
optimizer = SynCraft(api_key="your-key")
result = optimizer.optimize(
    smiles="CC(=O)Nc1ccc(O)cc1",
    max_iterations=5
)""",
        "scientific_context": "SynCraft navigates the 'synthesis cliff' where minimal molecular modifications yield significant synthesizability gains. It replicates expert medicinal chemistry intuition using LLM reasoning.",
        "parameters": json.dumps({
            "optimization": {
                "max_iterations": {"default": 5, "type": "int", "description": "Maximum optimization iterations"},
                "temperature": {"default": 0.7, "type": "float", "description": "Gemini sampling temperature"}
            }
        }),
        "inputs": json.dumps([
            {"name": "smiles", "type": "smiles", "description": "Input molecule SMILES"},
            {"name": "protein", "type": "pdb", "description": "Optional protein target"}
        ]),
        "outputs": json.dumps([
            {"name": "optimized_smiles", "type": "smiles", "description": "Optimized molecule"},
            {"name": "edit_sequence", "type": "json", "description": "Applied edits"}
        ]),
        "requirements": json.dumps(["Python>=3.8", "RDKit", "AutoDock Vina", "Gemini API"]),
        "dependencies": json.dumps(["rdkit", "autodock-vina", "google-generativeai", "plip"]),
        "install_commands": "git clone https://github.com/catalystforyou/SynCraft-Core && pip install -r requirements.txt",
        "container_info": json.dumps({"api_required": "Google Gemini", "no_gpu_needed": True}),
        "best_practice_domains": json.dumps(["medicinal-chemistry", "lead-optimization", "drug-design"]),
        "best_practice_functions": json.dumps(["Synthesizability optimization", "Lead optimization", "Molecule editing"]),
        "citations": "Peking University. SynCraft: Guiding Large Language Models to Predict Edit Sequences for Molecular Synthesizability Optimization. arXiv 2025. arXiv:2512.20333",
        "edam_operations": json.dumps(["operation_2430"]),  # Design
        "edam_topics": json.dumps(["topic_3336", "topic_3373"]),  # Drug discovery, Drug development
        "tags": json.dumps(["synthesizability", "llm", "molecule-optimization", "drug-discovery"]),
        "quality_score": 0.88,
        "auto_discovered": True
    },
    {
        "tool_id": "auto_alphafold3",
        "name": "AlphaFold 3",
        "version": "3.0.0",
        "repo_owner": "google-deepmind",
        "repo_name": "alphafold3",
        "category": "Structure Prediction",
        "description": "DeepMind's model for predicting structures of biomolecular complexes with proteins, DNA, RNA, ligands, and ions. 50%+ improvement over AlphaFold 2. Non-commercial license (CC-BY-NC-SA).",
        "github_url": "https://github.com/google-deepmind/alphafold3",
        "url": "https://alphafoldserver.com",
        "language": "Python",
        "topics": json.dumps(["protein-structure", "structure-prediction", "alphafold", "deep-learning", "biomolecular-complex"]),
        "help_text": """AlphaFold 3 Usage:

# Option 1: AlphaFold Server (Recommended)
Visit: https://alphafoldserver.com
- Sign in with Google
- Enter sequences
- Max 20 predictions/day

# Option 2: AlphaFold Database API
curl "https://alphafold.ebi.ac.uk/api/prediction/P00520"

# Option 3: Local Installation
docker run --gpus all alphafold3 \\
    --input input.json \\
    --output results/

Note: Model weights require separate request from DeepMind
Non-commercial use only - consider Boltz-2 (MIT) for commercial""",
        "usage_guide": """## Quick Start Guide for AlphaFold 3

### Option 1: AlphaFold Server (Easiest)
1. Visit https://alphafoldserver.com
2. Sign in with Google account
3. Enter sequences (protein, DNA, RNA, ligands)
4. Submit job (max 20/day)
5. Download PDB results

### Option 2: AlphaFold Database API
```python
import requests

uniprot_id = "P00520"
response = requests.get(
    f"https://alphafold.ebi.ac.uk/api/prediction/{uniprot_id}"
)
pdb_url = response.json()["pdbUrl"]
```

### Option 3: Local Installation (Advanced)
```bash
git clone https://github.com/google-deepmind/alphafold3
# Request weights: https://forms.gle/svvpY4u2jsHEwWYS6
docker build -t alphafold3 .
docker run --gpus all alphafold3 --input input.json
```

### Commercial Alternative: Boltz-2 (MIT License)
```bash
pip install boltz
boltz predict input.fasta
```""",
        "examples": """# AlphaFold Server
Visit https://alphafoldserver.com

# Database API
import requests
response = requests.get("https://alphafold.ebi.ac.uk/api/prediction/P00520")
pdb_url = response.json()["pdbUrl"]

# Local Docker
docker run --gpus all alphafold3 --input input.json

# Alternative: Boltz-2 (MIT license)
pip install boltz
boltz predict input.fasta""",
        "scientific_context": "AlphaFold 3 extends structure prediction to full biomolecular complexes including DNA, RNA, and small molecules. For commercial use, consider Boltz-2 which has MIT license and similar accuracy.",
        "parameters": json.dumps({
            "prediction": {
                "num_models": {"default": 5, "type": "int", "description": "Number of models"},
                "num_recycles": {"default": 3, "type": "int", "description": "Recycling iterations"}
            }
        }),
        "inputs": json.dumps([
            {"name": "sequences", "type": "json", "description": "Protein, DNA, RNA sequences"},
            {"name": "ligands", "type": "smiles", "description": "Small molecule ligands"}
        ]),
        "outputs": json.dumps([
            {"name": "structure", "type": "cif/pdb", "description": "Predicted structure"},
            {"name": "confidence", "type": "json", "description": "pLDDT, PAE scores"}
        ]),
        "requirements": json.dumps(["Docker", "NVIDIA GPU 80GB+", "CUDA 12.6+", "1TB disk"]),
        "dependencies": json.dumps(["docker", "nvidia-container-toolkit"]),
        "install_commands": "Visit https://alphafoldserver.com OR docker pull alphafold3",
        "container_info": json.dumps({
            "server_available": "alphafoldserver.com",
            "server_limit": "20/day",
            "local_gpu": "A100/H100 80GB",
            "disk": "~1TB"
        }),
        "best_practice_domains": json.dumps(["structure-prediction", "structural-biology", "drug-discovery"]),
        "best_practice_functions": json.dumps(["Complex structure prediction", "Protein-DNA/RNA interactions", "Ligand binding"]),
        "citations": "Abramson et al. Accurate structure prediction of biomolecular interactions with AlphaFold 3. Nature 2024. doi:10.1038/s41586-024-07487-w",
        "edam_operations": json.dumps(["operation_0474"]),  # Protein structure prediction
        "edam_topics": json.dumps(["topic_0082", "topic_2814"]),  # Structure prediction, Protein structure
        "tags": json.dumps(["structure-prediction", "alphafold", "deepmind", "non-commercial", "nobel-prize"]),
        "quality_score": 0.99,
        "auto_discovered": True
    }
]


def add_tools_to_database(db_path: Path):
    """Add all tools to the main tools table"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    now = datetime.now().isoformat()

    for tool in TOOLS_DATA:
        try:
            # Check if tool exists
            cursor.execute("SELECT id FROM tools WHERE tool_id = ?", (tool["tool_id"],))
            existing = cursor.fetchone()

            if existing:
                # Update existing tool
                update_fields = []
                update_values = []
                for key, value in tool.items():
                    if key != "tool_id":
                        update_fields.append(f"{key} = ?")
                        update_values.append(value)
                update_fields.append("updated_at = ?")
                update_values.append(now)
                update_values.append(tool["tool_id"])

                cursor.execute(f"""
                    UPDATE tools SET {', '.join(update_fields)}
                    WHERE tool_id = ?
                """, update_values)
                logger.info(f"Updated tool: {tool['tool_id']}")
            else:
                # Insert new tool
                tool["created_at"] = now
                tool["updated_at"] = now
                tool["discovery_date"] = now

                columns = list(tool.keys())
                placeholders = ["?" for _ in columns]

                cursor.execute(f"""
                    INSERT INTO tools ({', '.join(columns)})
                    VALUES ({', '.join(placeholders)})
                """, list(tool.values()))
                logger.info(f"Added tool: {tool['tool_id']}")

        except Exception as e:
            logger.error(f"Error adding {tool['tool_id']}: {e}")

    conn.commit()
    conn.close()
    logger.info(f"Successfully processed {len(TOOLS_DATA)} tools")


def verify_tools(db_path: Path):
    """Verify tools were added correctly"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    print("\n" + "=" * 80)
    print("TOOL INDEX VERIFICATION")
    print("=" * 80)

    for tool in TOOLS_DATA:
        cursor.execute("""
            SELECT tool_id, name, category,
                   CASE WHEN help_text IS NOT NULL AND help_text != '' THEN 'Y' ELSE 'N' END as has_help,
                   CASE WHEN usage_guide IS NOT NULL AND usage_guide != '' THEN 'Y' ELSE 'N' END as has_guide,
                   CASE WHEN examples IS NOT NULL AND examples != '' THEN 'Y' ELSE 'N' END as has_examples,
                   CASE WHEN parameters IS NOT NULL AND parameters != '' THEN 'Y' ELSE 'N' END as has_params,
                   quality_score
            FROM tools WHERE tool_id = ?
        """, (tool["tool_id"],))

        row = cursor.fetchone()
        if row:
            print(f"✓ {row[1]:20} | {row[2]:20} | help:{row[3]} guide:{row[4]} ex:{row[5]} params:{row[6]} | score:{row[7]}")
        else:
            print(f"✗ {tool['tool_id']:20} | NOT FOUND")

    conn.close()


def main():
    db_path = Path("/home/yzhang/biomate/backend/database/galaxy_ai_tools.db")

    logger.info("Adding tools to main index...")
    add_tools_to_database(db_path)

    verify_tools(db_path)


if __name__ == "__main__":
    main()
