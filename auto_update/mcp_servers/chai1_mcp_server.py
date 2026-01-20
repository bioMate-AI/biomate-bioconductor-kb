#!/usr/bin/env python3
"""
Chai-1 MCP Server
Model Context Protocol server for Chai-1 structure prediction

This wraps the chai_lab package to provide MCP-compatible endpoints.

Usage:
    python chai1_mcp_server.py

Environment:
    CHAI1_DEVICE: GPU device (default: cuda:0)
    CHAI1_OUTPUT_DIR: Output directory for structures (default: /tmp/chai1_output)
"""

import asyncio
import json
import logging
import os
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Check if fastmcp is available
try:
    from fastmcp import FastMCP
    HAS_FASTMCP = True
except ImportError:
    HAS_FASTMCP = False
    logger.warning("fastmcp not installed. Install with: pip install fastmcp")

# Check if chai_lab is available
try:
    from chai_lab.chai1 import run_inference
    HAS_CHAI = True
except ImportError:
    HAS_CHAI = False
    logger.warning("chai_lab not installed. Install with: pip install chai_lab")


# Configuration
DEVICE = os.environ.get("CHAI1_DEVICE", "cuda:0")
OUTPUT_DIR = Path(os.environ.get("CHAI1_OUTPUT_DIR", "/tmp/chai1_output"))
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def create_fasta_file(sequences: List[Dict[str, str]], output_path: Path) -> Path:
    """Create a FASTA file from sequence dictionaries."""
    fasta_path = output_path / "input.fasta"
    with open(fasta_path, "w") as f:
        for i, seq in enumerate(sequences):
            name = seq.get("name", f"seq_{i}")
            sequence = seq.get("sequence", "")
            entity_type = seq.get("type", "protein")
            f.write(f">{name}|{entity_type}\n{sequence}\n")
    return fasta_path


async def predict_structure(
    sequences: List[Dict[str, str]],
    ligands: Optional[List[str]] = None,
    num_diffusion_samples: int = 1,
    seed: int = 42,
) -> Dict[str, Any]:
    """
    Predict structure using Chai-1.

    Args:
        sequences: List of dicts with 'name', 'sequence', and 'type' (protein/dna/rna)
        ligands: Optional list of SMILES strings
        num_diffusion_samples: Number of samples to generate
        seed: Random seed

    Returns:
        Dictionary with prediction results
    """
    if not HAS_CHAI:
        return {"error": "chai_lab not installed"}

    # Create temporary directory for this prediction
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir = Path(tmpdir)

        # Create input FASTA
        fasta_path = create_fasta_file(sequences, tmpdir)

        # Run inference
        try:
            candidates = run_inference(
                fasta_file=fasta_path,
                output_dir=tmpdir / "output",
                num_trunk_recycles=3,
                num_diffn_timesteps=200,
                seed=seed,
                device=DEVICE,
                use_esm_embeddings=True,
            )

            # Collect results
            results = []
            output_path = tmpdir / "output"

            for cif_file in output_path.glob("*.cif"):
                with open(cif_file) as f:
                    cif_content = f.read()
                results.append({
                    "name": cif_file.stem,
                    "cif": cif_content,
                })

            # Read scores if available
            scores_file = output_path / "scores.json"
            scores = {}
            if scores_file.exists():
                with open(scores_file) as f:
                    scores = json.load(f)

            return {
                "success": True,
                "structures": results,
                "scores": scores,
                "num_predictions": len(results),
            }

        except Exception as e:
            logger.error(f"Prediction failed: {e}")
            return {"error": str(e), "success": False}


# MCP Server setup
if HAS_FASTMCP:
    mcp = FastMCP("chai1")

    @mcp.tool()
    async def chai1_predict(
        sequences: List[Dict[str, str]],
        ligands: Optional[List[str]] = None,
        num_samples: int = 1,
        seed: int = 42,
    ) -> Dict[str, Any]:
        """
        Predict biomolecular structure using Chai-1.

        Chai-1 is a multi-modal foundation model for molecular structure prediction
        that supports proteins, nucleic acids, small molecules, and their complexes.

        Args:
            sequences: List of molecules, each with:
                - name: Identifier for the molecule
                - sequence: Amino acid sequence (protein) or nucleotide sequence (DNA/RNA)
                - type: One of 'protein', 'dna', 'rna'
            ligands: Optional list of small molecule SMILES strings
            num_samples: Number of structure samples to generate (1-5)
            seed: Random seed for reproducibility

        Returns:
            Dictionary containing:
                - success: Boolean indicating if prediction succeeded
                - structures: List of predicted structures in CIF format
                - scores: Confidence scores (pLDDT, PAE)

        Example:
            chai1_predict([
                {"name": "protein_A", "sequence": "MKFLILLFNILC...", "type": "protein"},
                {"name": "dna_B", "sequence": "ATCGATCG...", "type": "dna"}
            ])
        """
        return await predict_structure(
            sequences=sequences,
            ligands=ligands,
            num_diffusion_samples=num_samples,
            seed=seed,
        )

    @mcp.tool()
    async def chai1_health() -> Dict[str, Any]:
        """
        Check Chai-1 server health and GPU availability.

        Returns:
            Dictionary with health status and GPU info
        """
        import torch

        return {
            "status": "healthy" if HAS_CHAI else "chai_lab not installed",
            "chai_lab_installed": HAS_CHAI,
            "cuda_available": torch.cuda.is_available(),
            "cuda_device_count": torch.cuda.device_count() if torch.cuda.is_available() else 0,
            "device": DEVICE,
            "output_dir": str(OUTPUT_DIR),
        }


def main():
    """Run the MCP server."""
    if not HAS_FASTMCP:
        print("Error: fastmcp not installed. Install with: pip install fastmcp")
        sys.exit(1)

    if not HAS_CHAI:
        print("Warning: chai_lab not installed. Server will return errors for predictions.")
        print("Install with: pip install chai_lab")

    print("Starting Chai-1 MCP Server...")
    print(f"Device: {DEVICE}")
    print(f"Output directory: {OUTPUT_DIR}")

    mcp.run()


if __name__ == "__main__":
    main()
