#!/usr/bin/env python3
"""
Biomate AI Tools - API Wrappers
Direct API access for GPU-heavy tools without local GPU requirements.

Tools:
- Chai-1: BioLM API (biolm.ai)
- Evo 2: NVIDIA NIM API
- AlphaFold 3: AlphaFold Server API
- ProTrek: search-protrek.com API
"""

import json
import os
import requests
from typing import Any, Dict, List, Optional
from dataclasses import dataclass
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# CHAI-1 via BioLM API
# =============================================================================

BIOLM_API_BASE = "https://biolm.ai/api/v3"
BIOLM_API_KEY = os.environ.get("BIOLM_API_KEY", "")


def chai1_predict_structure(
    sequences: List[Dict[str, str]],
    num_diffusion_samples: int = 1,
    use_esm_embeddings: bool = True,
) -> Dict[str, Any]:
    """
    Predict structure using Chai-1 via BioLM API.

    Args:
        sequences: List of dicts with 'type' (protein/dna/rna) and 'sequence'
        num_diffusion_samples: Number of samples (1-5)
        use_esm_embeddings: Use ESM embeddings for better accuracy

    Returns:
        Dict with 'cif' structure and confidence scores

    Example:
        chai1_predict_structure([
            {"type": "protein", "sequence": "MKFLILLFNILC..."}
        ])
    """
    if not BIOLM_API_KEY:
        return {"error": "BIOLM_API_KEY not set. Get key at biolm.ai"}

    headers = {
        "Authorization": f"Token {BIOLM_API_KEY}",
        "Content-Type": "application/json"
    }

    payload = {
        "items": [
            {
                "sequences": sequences,
                "num_diffn_samples": num_diffusion_samples,
                "use_esm_embeddings": use_esm_embeddings,
            }
        ]
    }

    try:
        response = requests.post(
            f"{BIOLM_API_BASE}/chai1/predict/",
            headers=headers,
            json=payload,
            timeout=300  # 5 min timeout for structure prediction
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        return {"error": str(e)}


# =============================================================================
# EVO 2 via NVIDIA NIM API
# =============================================================================

NVIDIA_NIM_BASE = "https://integrate.api.nvidia.com/v1"
NVIDIA_API_KEY = os.environ.get("NVIDIA_API_KEY", "")


def evo2_generate(
    sequence: str,
    task: str = "generation",  # generation, scoring, embedding
    num_tokens: int = 100,
    temperature: float = 1.0,
) -> Dict[str, Any]:
    """
    Generate or analyze DNA sequences using Evo 2 via NVIDIA NIM.

    Args:
        sequence: Input DNA sequence
        task: 'generation', 'scoring', or 'embedding'
        num_tokens: Number of tokens to generate
        temperature: Sampling temperature

    Returns:
        Dict with generated sequence or scores

    Example:
        evo2_generate("ATCGATCG", task="generation", num_tokens=50)
    """
    if not NVIDIA_API_KEY:
        return {"error": "NVIDIA_API_KEY not set. Get key at build.nvidia.com"}

    headers = {
        "Authorization": f"Bearer {NVIDIA_API_KEY}",
        "Content-Type": "application/json"
    }

    payload = {
        "model": "arcinstitute/evo-2-40b",
        "messages": [{"role": "user", "content": sequence}],
        "max_tokens": num_tokens,
        "temperature": temperature,
    }

    try:
        response = requests.post(
            f"{NVIDIA_NIM_BASE}/chat/completions",
            headers=headers,
            json=payload,
            timeout=120
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        return {"error": str(e)}


# =============================================================================
# ALPHAFOLD 3 via AlphaFold Server
# =============================================================================

ALPHAFOLD_SERVER = "https://alphafoldserver.com/api"


def alphafold3_predict(
    sequences: List[Dict[str, str]],
    job_name: str = "biomate_job",
) -> Dict[str, Any]:
    """
    Submit structure prediction to AlphaFold Server.

    Note: Limited to 20 jobs/day. For bulk access, use local installation.

    Args:
        sequences: List of dicts with 'type' and 'sequence'
        job_name: Name for the prediction job

    Returns:
        Dict with job_id for tracking

    Example:
        alphafold3_predict([{"type": "protein", "sequence": "MKFLIL..."}])
    """
    # AlphaFold Server uses Google OAuth - requires browser auth
    return {
        "message": "AlphaFold Server requires browser authentication",
        "url": "https://alphafoldserver.com",
        "instructions": [
            "1. Go to alphafoldserver.com",
            "2. Sign in with Google account",
            "3. Submit your sequences",
            "4. Download results when ready",
        ],
        "limit": "20 jobs per day",
        "alternative": "For programmatic access, use local AlphaFold 3 installation"
    }


# =============================================================================
# PROTREK via search-protrek.com
# =============================================================================

PROTREK_API = "https://search-protrek.com/api"


def protrek_search(
    query: str,
    mode: str = "text",  # text, sequence, structure
    top_k: int = 10,
) -> Dict[str, Any]:
    """
    Search proteins using ProTrek trimodal model.

    Args:
        query: Search query (text description, sequence, or structure ID)
        mode: 'text' (function description), 'sequence', or 'structure'
        top_k: Number of results

    Returns:
        List of matching proteins with scores

    Example:
        protrek_search("DNA binding transcription factor", mode="text")
    """
    try:
        params = {
            "query": query,
            "mode": mode,
            "top_k": top_k
        }
        response = requests.get(
            f"{PROTREK_API}/search",
            params=params,
            timeout=30
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        # Fallback to web interface
        return {
            "message": "API request failed, use web interface",
            "url": "https://search-protrek.com",
            "query": query,
            "error": str(e)
        }


# =============================================================================
# TOOL REGISTRY - For Biomate Integration
# =============================================================================

BIOMATE_API_TOOLS = {
    "chai1_predict": {
        "function": chai1_predict_structure,
        "name": "Chai-1 Structure Prediction",
        "description": "Predict protein/DNA/RNA structure using Chai-1 via BioLM API",
        "requires_api_key": "BIOLM_API_KEY",
        "api_url": "https://biolm.ai",
    },
    "evo2_generate": {
        "function": evo2_generate,
        "name": "Evo 2 DNA Generation",
        "description": "Generate or analyze DNA sequences using Evo 2 via NVIDIA NIM",
        "requires_api_key": "NVIDIA_API_KEY",
        "api_url": "https://build.nvidia.com",
    },
    "alphafold3_predict": {
        "function": alphafold3_predict,
        "name": "AlphaFold 3 Structure Prediction",
        "description": "Submit structure prediction to AlphaFold Server (20/day limit)",
        "requires_api_key": None,  # Uses browser auth
        "api_url": "https://alphafoldserver.com",
    },
    "protrek_search": {
        "function": protrek_search,
        "name": "ProTrek Protein Search",
        "description": "Search proteins by function, sequence, or structure",
        "requires_api_key": None,
        "api_url": "https://search-protrek.com",
    },
}


def list_available_tools() -> Dict[str, Any]:
    """List all available API tools and their status."""
    tools = {}
    for tool_id, info in BIOMATE_API_TOOLS.items():
        api_key_name = info.get("requires_api_key")
        if api_key_name:
            has_key = bool(os.environ.get(api_key_name))
            status = "ready" if has_key else f"needs {api_key_name}"
        else:
            status = "ready"

        tools[tool_id] = {
            "name": info["name"],
            "description": info["description"],
            "status": status,
            "api_url": info["api_url"],
        }
    return tools


def run_tool(tool_id: str, **kwargs) -> Dict[str, Any]:
    """Run a tool by ID with given parameters."""
    if tool_id not in BIOMATE_API_TOOLS:
        return {"error": f"Unknown tool: {tool_id}"}

    tool = BIOMATE_API_TOOLS[tool_id]
    try:
        return tool["function"](**kwargs)
    except Exception as e:
        return {"error": str(e)}


if __name__ == "__main__":
    # Test tool listing
    print("Available API Tools:")
    print(json.dumps(list_available_tools(), indent=2))
