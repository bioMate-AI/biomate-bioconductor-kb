#!/usr/bin/env python3
"""
Register API-based tools in Biomate database for immediate use.
These tools use external APIs and don't require local GPU.
"""

import json
import sqlite3
from pathlib import Path
from datetime import datetime

DB_PATH = Path(__file__).parent.parent.parent / "backend" / "database" / "galaxy_ai_tools.db"

API_TOOLS = [
    {
        "tool_id": "api_chai1",
        "name": "Chai-1 API",
        "version": "0.6.1",
        "category": "Structure Prediction",
        "description": "Predict protein/DNA/RNA/ligand complex structures using Chai-1 via BioLM API. No local GPU required.",
        "help_text": """## Chai-1 API Access

### Quick Start
```python
from biomate_ai_tools.api_tools import chai1_predict_structure

result = chai1_predict_structure([
    {"type": "protein", "sequence": "MKFLILLFNILCLFPVLAADNH..."}
])
```

### API Key Setup
```bash
export BIOLM_API_KEY="your-key-from-biolm.ai"
```

### Get API Key
Visit https://biolm.ai to create account and get API key.""",
        "usage_guide": """## Using Chai-1 via API

### Step 1: Get API Key
1. Go to https://biolm.ai
2. Create account
3. Get API key from dashboard

### Step 2: Set Environment Variable
```bash
export BIOLM_API_KEY="your-key"
```

### Step 3: Run Prediction
```python
from biomate_ai_tools.api_tools import chai1_predict_structure

# Single protein
result = chai1_predict_structure([
    {"type": "protein", "sequence": "MKTVRQERLKSIVRILERSKEPVSGAQ..."}
])

# Protein-ligand complex
result = chai1_predict_structure([
    {"type": "protein", "sequence": "MKTVRQERLKSIVRILERSKEPVSGAQ..."},
    {"type": "ligand", "sequence": "CC(=O)OC1=CC=CC=C1C(=O)O"}  # Aspirin SMILES
])

# Protein-DNA complex
result = chai1_predict_structure([
    {"type": "protein", "sequence": "MKTVRQERLKSIVRILERSKEPVSGAQ..."},
    {"type": "dna", "sequence": "ATCGATCGATCG"}
])
```

### Output
Returns CIF structure file and confidence scores (pLDDT, PAE).""",
        "examples": """```python
# Basic protein structure prediction
from biomate_ai_tools.api_tools import chai1_predict_structure

result = chai1_predict_structure([
    {"type": "protein", "sequence": "MNIFEMLRIDEGLRLKIYKDTEGYYTIGIGHLL"}
])

# Access structure
cif_content = result.get("cif")
confidence = result.get("plddt")
```""",
        "parameters": json.dumps({
            "sequences": {"type": "list", "required": True, "description": "List of molecules with type and sequence"},
            "num_diffusion_samples": {"type": "int", "default": 1, "description": "Number of samples (1-5)"},
            "use_esm_embeddings": {"type": "bool", "default": True, "description": "Use ESM embeddings"}
        }),
        "requirements": '["BIOLM_API_KEY environment variable"]',
        "api_endpoint": "https://biolm.ai/api/v3/chai1/predict/",
        "quality_score": 0.98,
    },
    {
        "tool_id": "api_evo2",
        "name": "Evo 2 API",
        "version": "40b",
        "category": "Genomics",
        "description": "DNA foundation model for sequence generation and analysis via NVIDIA NIM API. 40B parameters, trained on 9 trillion tokens.",
        "help_text": """## Evo 2 via NVIDIA NIM

### Quick Start
```python
from biomate_ai_tools.api_tools import evo2_generate

# Generate DNA sequence
result = evo2_generate("ATCGATCG", task="generation", num_tokens=100)
```

### API Key Setup
```bash
export NVIDIA_API_KEY="your-key-from-build.nvidia.com"
```

### Get API Key
Visit https://build.nvidia.com/arcinstitute/evo-2-40b""",
        "usage_guide": """## Using Evo 2 via NVIDIA NIM

### Step 1: Get API Key
1. Go to https://build.nvidia.com
2. Find Evo 2 model
3. Get API key

### Step 2: Set Environment Variable
```bash
export NVIDIA_API_KEY="nvapi-..."
```

### Step 3: Run Tasks
```python
from biomate_ai_tools.api_tools import evo2_generate

# DNA generation
result = evo2_generate(
    sequence="ATCGATCGATCG",
    task="generation",
    num_tokens=100,
    temperature=1.0
)

# Sequence scoring
result = evo2_generate(
    sequence="ATCGATCGATCG",
    task="scoring"
)
```""",
        "examples": """```python
from biomate_ai_tools.api_tools import evo2_generate

# Generate continuation of DNA sequence
result = evo2_generate(
    "ATCGATCGATCGATCG",
    task="generation",
    num_tokens=50
)
generated = result["choices"][0]["message"]["content"]
```""",
        "parameters": json.dumps({
            "sequence": {"type": "str", "required": True, "description": "Input DNA sequence"},
            "task": {"type": "str", "default": "generation", "description": "generation, scoring, or embedding"},
            "num_tokens": {"type": "int", "default": 100, "description": "Tokens to generate"},
            "temperature": {"type": "float", "default": 1.0, "description": "Sampling temperature"}
        }),
        "requirements": '["NVIDIA_API_KEY environment variable"]',
        "api_endpoint": "https://integrate.api.nvidia.com/v1/chat/completions",
        "quality_score": 0.97,
    },
    {
        "tool_id": "api_alphafold3",
        "name": "AlphaFold 3 Server",
        "version": "3.0",
        "category": "Structure Prediction",
        "description": "AlphaFold 3 structure prediction via alphafoldserver.com. Free, 20 jobs/day limit. Best for protein-ligand, protein-DNA, protein-RNA complexes.",
        "help_text": """## AlphaFold 3 Server

### Access
Go to https://alphafoldserver.com

### Usage
1. Sign in with Google account
2. Enter sequences (protein, DNA, RNA, ligands)
3. Submit job
4. Download results when ready

### Limits
- 20 jobs per day
- Max 5000 residues per job""",
        "usage_guide": """## Using AlphaFold Server

### Step 1: Access Server
Go to https://alphafoldserver.com

### Step 2: Sign In
Use Google account authentication

### Step 3: Submit Job
- Enter protein sequence(s)
- Add DNA/RNA if needed
- Add ligand SMILES if needed
- Click Submit

### Step 4: Wait for Results
- Typical time: 5-30 minutes
- Email notification when done

### Step 5: Download
- Download CIF structure
- View confidence scores
- Export for visualization""",
        "examples": """# AlphaFold 3 Server (Web Interface)

1. Go to alphafoldserver.com
2. Enter sequence:
   >protein_A
   MKTVRQERLKSIVRILERSKEPVSGAQ...

3. Add ligand (optional):
   CC(=O)OC1=CC=CC=C1C(=O)O  # Aspirin

4. Submit and wait for results""",
        "parameters": json.dumps({
            "sequences": {"type": "list", "required": True, "description": "Protein/DNA/RNA sequences"},
            "ligands": {"type": "list", "required": False, "description": "SMILES strings for small molecules"}
        }),
        "requirements": '["Google account for authentication"]',
        "api_endpoint": "https://alphafoldserver.com",
        "quality_score": 0.99,
    },
    {
        "tool_id": "api_protrek",
        "name": "ProTrek Search",
        "version": "1.0",
        "category": "Protein Analysis",
        "description": "Search proteins by function description, sequence, or structure using ProTrek trimodal language model.",
        "help_text": """## ProTrek Search

### Quick Start
```python
from biomate_ai_tools.api_tools import protrek_search

# Search by function
results = protrek_search("DNA binding transcription factor", mode="text")
```

### Web Interface
https://search-protrek.com""",
        "usage_guide": """## Using ProTrek

### Search by Function (Text)
```python
results = protrek_search(
    "kinase that phosphorylates tyrosine",
    mode="text",
    top_k=10
)
```

### Search by Sequence
```python
results = protrek_search(
    "MKTVRQERLKSIVRILERSKEPVSGAQ",
    mode="sequence",
    top_k=10
)
```

### Web Interface
Go to https://search-protrek.com for interactive search.""",
        "examples": """```python
from biomate_ai_tools.api_tools import protrek_search

# Find proteins by function
results = protrek_search(
    "membrane protein involved in ion transport",
    mode="text",
    top_k=20
)

for protein in results["hits"]:
    print(protein["name"], protein["score"])
```""",
        "parameters": json.dumps({
            "query": {"type": "str", "required": True, "description": "Search query"},
            "mode": {"type": "str", "default": "text", "description": "text, sequence, or structure"},
            "top_k": {"type": "int", "default": 10, "description": "Number of results"}
        }),
        "requirements": '[]',
        "api_endpoint": "https://search-protrek.com",
        "quality_score": 0.96,
    },
]


def register_tools():
    """Register API tools in the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    print("=" * 60)
    print("REGISTERING API TOOLS IN BIOMATE")
    print("=" * 60)

    for tool in API_TOOLS:
        # Check if tool already exists
        cursor.execute("SELECT tool_id FROM tools WHERE tool_id = ?", (tool["tool_id"],))
        exists = cursor.fetchone()

        if exists:
            # Update existing
            cursor.execute("""
                UPDATE tools SET
                    name = ?,
                    version = ?,
                    category = ?,
                    description = ?,
                    help_text = ?,
                    usage_guide = ?,
                    examples = ?,
                    parameters = ?,
                    requirements = ?,
                    quality_score = ?,
                    updated_at = ?
                WHERE tool_id = ?
            """, (
                tool["name"],
                tool["version"],
                tool["category"],
                tool["description"],
                tool["help_text"],
                tool["usage_guide"],
                tool["examples"],
                tool["parameters"],
                tool["requirements"],
                tool["quality_score"],
                datetime.now().isoformat(),
                tool["tool_id"],
            ))
            print(f"✓ Updated: {tool['name']}")
        else:
            # Insert new
            cursor.execute("""
                INSERT INTO tools (
                    tool_id, name, version, category, description,
                    help_text, usage_guide, examples, parameters,
                    requirements, quality_score, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                tool["tool_id"],
                tool["name"],
                tool["version"],
                tool["category"],
                tool["description"],
                tool["help_text"],
                tool["usage_guide"],
                tool["examples"],
                tool["parameters"],
                tool["requirements"],
                tool["quality_score"],
                datetime.now().isoformat(),
                datetime.now().isoformat(),
            ))
            print(f"✓ Registered: {tool['name']}")

    conn.commit()
    conn.close()

    print()
    print("=" * 60)
    print(f"✓ {len(API_TOOLS)} API tools registered")
    print("=" * 60)


if __name__ == "__main__":
    register_tools()
