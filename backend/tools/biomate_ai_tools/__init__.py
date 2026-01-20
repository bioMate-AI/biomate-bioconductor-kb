"""
Biomate AI Tools - Cutting-edge bioinformatics tools

API Tools (no local GPU required):
- Chai-1 API: Structure prediction via BioLM
- Evo 2 API: DNA generation via NVIDIA NIM
- AlphaFold 3: Structure prediction via alphafoldserver.com
- ProTrek: Protein search via search-protrek.com

Local Tools (require GPU):
- Boltz-2: Protein-ligand docking
- State: Perturbation response prediction
- DrugCLIP: Virtual screening
- And more...
"""

from .api_tools import (
    chai1_predict_structure,
    evo2_generate,
    alphafold3_predict,
    protrek_search,
    list_available_tools,
    run_tool,
    BIOMATE_API_TOOLS,
)

__all__ = [
    "chai1_predict_structure",
    "evo2_generate",
    "alphafold3_predict",
    "protrek_search",
    "list_available_tools",
    "run_tool",
    "BIOMATE_API_TOOLS",
]

__version__ = "1.0.0"
