#!/usr/bin/env nextflow
/*
 * molecular_biology/design_knockout_sgrna
 * Design sgRNAs for CRISPR knockout by searching pre-computed sgRNA libraries.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Test: Design sgRNA for TP53 tumor suppressor gene
params.gene_name = 'TP53'
params.data_lake_path = null
params.species = 'human'
params.num_guides = 3

process DESIGN_KNOCKOUT_SGRNA {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("design_knockout_sgrna_results.json"), emit: results
    tuple val(meta), path("design_knockout_sgrna_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENE_NAME="${params.gene_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_LAKE_PATH="${params.data_lake_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SPECIES="${params.species?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_GUIDES="${params.num_guides?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
import os
from typing import Any
import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def design_knockout_sgrna(
    gene_name: str,
    data_lake_path: str,
    species: str = "human",
    num_guides: int = 1,
) -> dict[str, Any]:
    '''Design sgRNAs for CRISPR knockout by searching pre-computed sgRNA libraries.
    Returns optimized guide RNAs for targeting a specific gene.

    Args:
        gene_name (str): Target gene symbol/name (e.g., "EGFR", "TP53")
        species (str): Target organism species (default: "human")
        num_guides (int): Number of guides to return (default: 1)

    Returns:
        Dict: Dictionary containing:
            - explanation: Explanation of the output fields
            - gene_name: Target gene name
            - species: Target species
            - guides: List of sgRNA sequences

    '''
    # Handle missing data_lake_path gracefully
    if data_lake_path is None:
        return {
            "explanation": "sgRNA library data lake path not configured. In production, set data_lake_path to the directory containing sgRNA_KO_SP_human.txt and sgRNA_KO_SP_mouse.txt",
            "gene_name": gene_name,
            "species": species,
            "guides": [],
            "note": "No data lake path provided - returning empty guide list. Configure data_lake_path for actual sgRNA lookup."
        }

    DEFAULT_LIBRARIES = {
        "human": data_lake_path + "/sgRNA_KO_SP_human.txt",
        "mouse": data_lake_path + "/sgRNA_KO_SP_mouse.txt",
    }

    # Use fixed library path
    library_path = DEFAULT_LIBRARIES.get(species.lower())
    if library_path is None:
        return {
            "explanation": f"No sgRNA library available for species: {species}",
            "gene_name": gene_name,
            "species": species,
            "guides": [],
        }

    # Check if library file exists
    if not os.path.exists(library_path):
        return {
            "explanation": f"Library file for {species} not found at path: {library_path}. Data lake files not available.",
            "gene_name": gene_name,
            "species": species,
            "guides": [],
        }

    # Load sgRNA library from S3
    try:
        df = pd.read_csv(library_path, delimiter="\\t")
    except Exception as e:
        raise RuntimeError(f"Failed to load sgRNA library: {str(e)}") from None

    # Filter for target gene
    gene_name = gene_name.upper()  # Ensure consistent capitalization
    gene_df = df[df["Target Gene Symbol"].str.upper() == gene_name]

    if gene_df.empty:
        # Try partial matching if exact match fails
        gene_df = df[df["Target Gene Symbol"].str.upper().str.contains(gene_name)]

    if gene_df.empty:
        return {
            "explanation": "Output contains target gene name, species, and list of sgRNA sequences",
            "gene_name": gene_name,
            "species": species,
            "guides": [],
        }

    # Sort by combined rank (default priority)
    gene_df = gene_df.sort_values(by=["Combined Rank"])

    # Get top guides
    top_guides = gene_df.head(num_guides)

    # Extract just the sgRNA sequences
    guides = top_guides["sgRNA Sequence"].tolist()

    return {
        "explanation": "Output contains target gene name, species, and list of sgRNA sequences",
        "gene_name": gene_name,
        "species": species,
        "guides": guides,
    }

# Execute the function
try:
    result = design_knockout_sgrna(
        gene_name=auto_convert(os.environ.get("PARAM_GENE_NAME", "")),
        data_lake_path=auto_convert(os.environ.get("PARAM_DATA_LAKE_PATH", "")),
        species=auto_convert(os.environ.get("PARAM_SPECIES", "human")),
        num_guides=auto_convert(os.environ.get("PARAM_NUM_GUIDES", "1")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "design_knockout_sgrna",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("design_knockout_sgrna_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("design_knockout_sgrna_output.txt", "w") as f:
    f.write("Biomni: Design Knockout Sgrna" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "design_knockout_sgrna"
    END_VERSIONS
    """
}

workflow DESIGN_KNOCKOUT_SGRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DESIGN_KNOCKOUT_SGRNA(ch_input)

    emit:
    results = DESIGN_KNOCKOUT_SGRNA.out.results
    output = DESIGN_KNOCKOUT_SGRNA.out.output
    versions = DESIGN_KNOCKOUT_SGRNA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DESIGN_KNOCKOUT_SGRNA_WORKFLOW(ch_input)

    DESIGN_KNOCKOUT_SGRNA_WORKFLOW.out.output.view { "Output: $it" }
}
