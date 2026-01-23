"""
Biomate AI Tools - Cutting-edge bioinformatics tools

API Tools (no local GPU required):
- Chai-1 API: Structure prediction via BioLM
- Evo 2 API: DNA generation via NVIDIA NIM
- AlphaFold: Structure database via EBI API
- ProTrek: Protein search via search-protrek.com

Local Tools (require GPU):
- Boltz-2: Protein-ligand docking
- State: Perturbation response prediction
- DrugCLIP: Virtual screening
- And more...

Usage:
    from biomate_ai_tools import alphafold, chai1_predict_structure

    # Get AlphaFold structure
    result = alphafold.get_structure("P00533")

    # Predict with Chai-1 (requires BIOLM_API_KEY)
    result = chai1_predict_structure([{"type": "protein", "sequence": "..."}])
"""

# API tools
from .api_tools import (
    chai1_predict_structure,
    evo2_generate,
    alphafold3_predict,
    protrek_search,
    list_available_tools,
    run_tool,
    BIOMATE_API_TOOLS,
)

# AlphaFold direct client
from . import alphafold_client as alphafold

__all__ = [
    # API tools
    "chai1_predict_structure",
    "evo2_generate",
    "alphafold3_predict",
    "protrek_search",
    "list_available_tools",
    "run_tool",
    "BIOMATE_API_TOOLS",
    # AlphaFold
    "alphafold",
]

__version__ = "1.0.0"

