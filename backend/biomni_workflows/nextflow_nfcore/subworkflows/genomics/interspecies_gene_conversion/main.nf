#!/usr/bin/env nextflow
/*
 * genomics/interspecies_gene_conversion
 * Convert ENSEMBL gene IDs between different species using BioMart homology mapping.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Test: Convert human cancer genes to mouse orthologs
params.gene_list = '["ENSG00000141510", "ENSG00000121879", "ENSG00000198793"]'  // TP53, PIK3CA, MTOR
params.source_species = 'human'
params.target_species = 'mouse'

process INTERSPECIES_GENE_CONVERSION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("interspecies_gene_conversion_results.json"), emit: results
    tuple val(meta), path("interspecies_gene_conversion_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENE_LIST="${params.gene_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SOURCE_SPECIES="${params.source_species?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_SPECIES="${params.target_species?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
from pybiomart import Dataset
import numpy as np
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



def interspecies_gene_conversion(
    gene_list: list[str],
    source_species: str,
    target_species: str,
) -> str:
    '''Convert ENSEMBL gene IDs between different species using BioMart homology mapping.

    This function converts a list of ENSEMBL gene IDs from one species to their
    homologous counterparts in another species using the Ensembl BioMart database.
    The conversion is based on one-to-one ortholog mappings between species.

    Parameters
    ----------
    gene_list : list[str]
        List of ENSEMBL gene IDs to convert (e.g., ['ENSG00000007372', 'ENSG00000181449'])
    source_species : str
        Source species name. Supported species: human, mouse, rat, zebrafish, fly,
        drosophila, worm, yeast, chicken, pig, cow, dog, macaque
    target_species : str
        Target species name. Same supported species as source_species.

    Returns
    -------
    str
        Multi-line string containing the steps performed and file paths where
        results were saved. Returns empty string if source and target species are the same.

    Raises
    ------
    ValueError
        If source_species or target_species is not in the supported species list.

    Notes
    -----
    - The function saves conversion results to a CSV file named
      '{source_species}_to_{target_species}_gene_conversion.csv'
    - Genes that cannot be converted will have NaN values in the output
    - The function includes fallback mechanisms for robust data retrieval
    - Species synonyms are supported (e.g., 'drosophila' maps to 'fly')

    Examples
    --------
    >>> gene_ids = ["ENSG00000007372", "ENSG00000181449"]
    >>> result = interspecies_gene_conversion(gene_ids, "human", "mouse")
    >>> print(result)
    Gene conversion results saved to: human_to_mouse_gene_conversion.csv
    '''

    steps = []

    species_mapping = {
        "human": "hsapiens_gene_ensembl",
        "mouse": "mmusculus_gene_ensembl",
        "rat": "rnorvegicus_gene_ensembl",
        "zebrafish": "drerio_gene_ensembl",
        "fly": "dmelanogaster_gene_ensembl",
        "drosophila": "dmelanogaster_gene_ensembl",
        "worm": "celegans_gene_ensembl",
        "yeast": "scerevisiae_gene_ensembl",
        "chicken": "ggallus_gene_ensembl",
        "pig": "sscrofa_gene_ensembl",
        "cow": "btaurus_gene_ensembl",
        "dog": "cfamiliaris_gene_ensembl",
        "macaque": "mmulatta_gene_ensembl",
    }

    homolog_mapping = {
        "human": "hsapiens_homolog_ensembl_gene",
        "mouse": "mmusculus_homolog_ensembl_gene",
        "rat": "rnorvegicus_homolog_ensembl_gene",
        "zebrafish": "drerio_homolog_ensembl_gene",
        "fly": "dmelanogaster_homolog_ensembl_gene",
        "drosophila": "dmelanogaster_homolog_ensembl_gene",
        "worm": "celegans_homolog_ensembl_gene",
        "yeast": "scerevisiae_homolog_ensembl_gene",
        "chicken": "ggallus_homolog_ensembl_gene",
        "pig": "sscrofa_homolog_ensembl_gene",
        "cow": "btaurus_homolog_ensembl_gene",
        "dog": "cfamiliaris_homolog_ensembl_gene",
        "macaque": "mmulatta_homolog_ensembl_gene",
    }

    if source_species not in species_mapping:
        raise ValueError(
            f"Source species '{source_species}' not supported. Available species: {list(species_mapping.keys())}"
        )

    if target_species not in homolog_mapping:
        raise ValueError(
            f"Target species '{target_species}' not supported. Available species: {list(homolog_mapping.keys())}"
        )

    original_length = len(gene_list)

    if source_species == target_species:
        return "\\n".join(steps)

    source_dataset_name = species_mapping[source_species]
    homolog_attribute = homolog_mapping[target_species]

    try:
        source_dataset = Dataset(name=source_dataset_name, host="http://www.ensembl.org")

        mapping = source_dataset.query(
            attributes=["ensembl_gene_id", homolog_attribute], filters={"link_ensembl_gene_id": gene_list}
        )

        if mapping.empty:
            all_mapping = source_dataset.query(attributes=["ensembl_gene_id", homolog_attribute])
            mapping = all_mapping[all_mapping["ensembl_gene_id"].isin(gene_list)]

        mapping_filtered = mapping[mapping.iloc[:, 1].notna() & (mapping.iloc[:, 1] != "")]
        gene_mapping = dict(zip(mapping_filtered.iloc[:, 0], mapping_filtered.iloc[:, 1], strict=False))

        converted_genes = []
        for gene in gene_list:
            if gene in gene_mapping:
                converted_genes.append(gene_mapping[gene])
            else:
                converted_genes.append(np.nan)

        assert len(converted_genes) == original_length, "Input and output gene list shapes must be the same"

        conversion_df = pd.DataFrame({f"{source_species}_genes": gene_list, f"{target_species}_genes": converted_genes})
        filename = f"{source_species}_to_{target_species}_gene_conversion.csv"
        conversion_df.to_csv(filename, index=False)
        steps.append(f"Gene conversion results saved to: {filename}")

        return "\\n".join(steps)

    except Exception as e:
        steps.append(f"Error during gene conversion from {source_species} to {target_species}: {e}")
        try:
            source_dataset = Dataset(name=source_dataset_name, host="http://www.ensembl.org")

            all_mapping = source_dataset.query(attributes=["ensembl_gene_id", homolog_attribute])

            mapping = all_mapping[all_mapping["ensembl_gene_id"].isin(gene_list)]

            mapping_filtered = mapping[mapping.iloc[:, 1].notna() & (mapping.iloc[:, 1] != "")]
            gene_mapping = dict(zip(mapping_filtered.iloc[:, 0], mapping_filtered.iloc[:, 1], strict=False))

            converted_genes = []
            for gene in gene_list:
                if gene in gene_mapping:
                    converted_genes.append(gene_mapping[gene])
                else:
                    converted_genes.append(np.nan)

            assert len(converted_genes) == original_length, "Input and output gene list shapes must be the same"

            conversion_df = pd.DataFrame(
                {f"{source_species}_genes": gene_list, f"{target_species}_genes": converted_genes}
            )
            filename = f"{source_species}_to_{target_species}_gene_conversion.csv"
            conversion_df.to_csv(filename, index=False)
            steps.append(f"Gene conversion results saved to: {filename}")

            return "\\n".join(steps)

        except Exception as e2:
            steps.append(f"Alternative approach also failed: {e2}")
            converted_genes = [np.nan] * original_length

            assert len(converted_genes) == original_length, "Input and output gene list shapes must be the same"

            conversion_df = pd.DataFrame(
                {f"{source_species}_genes": gene_list, f"{target_species}_genes": converted_genes}
            )
            filename = f"{source_species}_to_{target_species}_gene_conversion.csv"
            conversion_df.to_csv(filename, index=False)
            steps.append(f"Gene conversion results (failed) saved to: {filename}")

            return "\\n".join(steps)

# Execute the function
try:
    result = interspecies_gene_conversion(
        gene_list=auto_convert(os.environ.get("PARAM_GENE_LIST", "")),
        source_species=auto_convert(os.environ.get("PARAM_SOURCE_SPECIES", "")),
        target_species=auto_convert(os.environ.get("PARAM_TARGET_SPECIES", "")),
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
    "function": "interspecies_gene_conversion",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("interspecies_gene_conversion_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("interspecies_gene_conversion_output.txt", "w") as f:
    f.write("Biomni: Interspecies Gene Conversion" + NL)
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
        biomni_function: "interspecies_gene_conversion"
    END_VERSIONS
    """
}

workflow INTERSPECIES_GENE_CONVERSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    INTERSPECIES_GENE_CONVERSION(ch_input)

    emit:
    results = INTERSPECIES_GENE_CONVERSION.out.results
    output = INTERSPECIES_GENE_CONVERSION.out.output
    versions = INTERSPECIES_GENE_CONVERSION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    INTERSPECIES_GENE_CONVERSION_WORKFLOW(ch_input)

    INTERSPECIES_GENE_CONVERSION_WORKFLOW.out.output.view { "Output: $it" }
}
