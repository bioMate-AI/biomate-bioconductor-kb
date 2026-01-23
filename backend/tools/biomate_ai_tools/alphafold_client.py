#!/usr/bin/env python3
"""
AlphaFold Direct Client - HTTP API access to AlphaFold database.
No MCP required - direct REST API calls.
"""

import json
import requests
from typing import Any, Dict, List, Optional

ALPHAFOLD_API = "https://alphafold.ebi.ac.uk/api"


def get_structure(uniprot_id: str, format: str = "pdb") -> Dict[str, Any]:
    """
    Get AlphaFold predicted structure.

    Args:
        uniprot_id: UniProt accession (e.g., 'P00533')
        format: 'pdb', 'cif', or 'json'

    Returns:
        Structure data or error
    """
    try:
        # Get prediction info
        response = requests.get(
            f"{ALPHAFOLD_API}/prediction/{uniprot_id}",
            timeout=30
        )

        if response.status_code == 404:
            return {"error": f"No structure found for {uniprot_id}"}

        response.raise_for_status()
        data = response.json()

        if isinstance(data, list) and len(data) > 0:
            entry = data[0]

            # Get structure file URL based on format
            if format == "pdb":
                url = entry.get("pdbUrl")
            elif format == "cif":
                url = entry.get("cifUrl")
            else:
                return entry  # Return metadata

            if url:
                struct_response = requests.get(url, timeout=60)
                struct_response.raise_for_status()
                return {
                    "uniprot_id": uniprot_id,
                    "format": format,
                    "structure": struct_response.text,
                    "metadata": entry
                }

        return data

    except requests.exceptions.RequestException as e:
        return {"error": str(e)}


def check_availability(uniprot_id: str) -> Dict[str, Any]:
    """Check if structure is available for a UniProt ID."""
    try:
        response = requests.get(
            f"{ALPHAFOLD_API}/prediction/{uniprot_id}",
            timeout=15
        )

        if response.status_code == 404:
            return {"available": False, "uniprot_id": uniprot_id}

        response.raise_for_status()
        data = response.json()

        if isinstance(data, list) and len(data) > 0:
            return {
                "available": True,
                "uniprot_id": uniprot_id,
                "versions": len(data),
                "latest_version": data[0].get("latestVersion"),
                "gene": data[0].get("gene"),
                "organism": data[0].get("organismScientificName"),
            }

        return {"available": False, "uniprot_id": uniprot_id}

    except requests.exceptions.RequestException as e:
        return {"error": str(e), "available": False}


def search_by_gene(gene_name: str, organism: str = "Homo sapiens") -> List[Dict]:
    """Search AlphaFold by gene name."""
    try:
        # Use UniProt API to find proteins, then check AlphaFold
        uniprot_url = f"https://rest.uniprot.org/uniprotkb/search?query=gene:{gene_name}+AND+organism_name:{organism}&format=json&size=5"
        response = requests.get(uniprot_url, timeout=30)
        response.raise_for_status()
        data = response.json()

        results = []
        for entry in data.get("results", [])[:5]:
            uniprot_id = entry.get("primaryAccession")
            if uniprot_id:
                avail = check_availability(uniprot_id)
                if avail.get("available"):
                    results.append({
                        "uniprot_id": uniprot_id,
                        "gene": entry.get("genes", [{}])[0].get("geneName", {}).get("value"),
                        "protein_name": entry.get("proteinDescription", {}).get("recommendedName", {}).get("fullName", {}).get("value"),
                        "organism": organism,
                        "alphafold_available": True
                    })

        return results

    except Exception as e:
        return [{"error": str(e)}]


def download_structure(uniprot_id: str, output_path: str, format: str = "pdb") -> Dict[str, Any]:
    """Download structure to file."""
    result = get_structure(uniprot_id, format)

    if "error" in result:
        return result

    if "structure" in result:
        with open(output_path, "w") as f:
            f.write(result["structure"])
        return {
            "success": True,
            "uniprot_id": uniprot_id,
            "path": output_path,
            "format": format
        }

    return {"error": "No structure data in response"}


# =============================================================================
# TEST
# =============================================================================

if __name__ == "__main__":
    print("=" * 60)
    print("AlphaFold Direct Client Test")
    print("=" * 60)

    # Test availability
    print("\n1. Checking P00533 (EGFR)...")
    result = check_availability("P00533")
    print(f"   Available: {result.get('available')}")
    print(f"   Gene: {result.get('gene')}")
    print(f"   Organism: {result.get('organism')}")

    # Test gene search
    print("\n2. Searching for TP53...")
    results = search_by_gene("TP53")
    for r in results[:3]:
        print(f"   {r.get('uniprot_id')}: {r.get('protein_name', 'N/A')[:50]}")

    # Test structure retrieval (metadata only)
    print("\n3. Getting P00533 metadata...")
    result = get_structure("P00533", format="json")
    if isinstance(result, list) and result:
        print(f"   Model: {result[0].get('modelCreatedDate')}")
        print(f"   Confidence: {result[0].get('pdbUrl', 'N/A')[:60]}...")

    print("\n✓ AlphaFold client ready")
