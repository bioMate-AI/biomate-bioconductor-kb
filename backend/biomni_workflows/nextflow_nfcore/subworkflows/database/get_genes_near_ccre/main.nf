#!/usr/bin/env nextflow
/*
 * database/get_genes_near_ccre
 * Given a cCRE (Candidate cis-Regulatory Element), this function returns a string containing the
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Find genes near a cCRE in the MYC locus on chromosome 8
params.accession = 'EH38E1516972'
params.assembly = 'GRCh38'
params.chromosome = 'chr8'
params.k = 10

process GET_GENES_NEAR_CCRE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_genes_near_ccre_results.json"), emit: results
    tuple val(meta), path("get_genes_near_ccre_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ACCESSION="${params.accession?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ASSEMBLY="${params.assembly?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CHROMOSOME="${params.chromosome?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K="${params.k?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import requests
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



def get_genes_near_ccre(accession: str, assembly: str, chromosome: str, k: int = 10) -> str:
    '''Given a cCRE (Candidate cis-Regulatory Element), this function returns a string containing the
    steps it performs and the k nearest genes sorted by distance.

    Parameters
    ----------
    - accession (str): ENCODE Accession ID of query cCRE, e.g., EH38E1516980.
    - assembly (str): Assembly of the gene, e.g., 'GRCh38'.
    - chromosome (str): Chromosome of the gene, e.g., 'chr12'.
    - k (int): Number of nearby genes to return, sorted by distance. Default is 10.

    Returns
    -------
    - str: Steps performed and the result.

    '''
    steps_log = (
        f"Starting process with accession: {accession}, assembly: {assembly}, chromosome: {chromosome}, k: {k}\\n"
    )

    url = "https://screen-beta-api.wenglab.org/dataws/re_detail/nearbyGenomic"
    data = {"accession": accession, "assembly": assembly, "coord_chrom": chromosome}

    steps_log += "Sending POST request to API with given data.\\n"
    response = requests.post(url, json=data)

    if not response.ok:
        steps_log += f"API request failed with response: {response.text}\\n"
        return steps_log

    response_json = response.json()

    if "errors" in response_json:
        steps_log += f"API returned errors: {response_json['errors']}\\n"
        return steps_log

    nearby_genes = response_json.get(accession, {}).get("nearby_genes", [])
    if not nearby_genes:
        steps_log += "No nearby genes found for the given accession.\\n"
        return steps_log

    steps_log += "Successfully retrieved nearby genes. Sorting them by distance.\\n"
    sorted_genes = sorted(nearby_genes, key=lambda x: x["distance"])[:k]

    steps_log += f"Returning the top {k} nearest genes.\\n"
    steps_log += "Result:\\n"

    for gene in sorted_genes:
        gene_name = gene.get("name", "Unknown")
        distance = gene.get("distance", "N/A")
        ensembl_id = gene.get("ensemblid_ver", "N/A")
        start = gene.get("start", "N/A")
        stop = gene.get("stop", "N/A")
        chrom = gene.get("chrom", "N/A")
        steps_log += f"Gene: {gene_name}, Distance: {distance}, Ensembl ID: {ensembl_id}, Chromosome: {chrom}, Start: {start}, Stop: {stop}\\n"

    return steps_log

# Execute the function
try:
    result = get_genes_near_ccre(
        accession=auto_convert(os.environ.get("PARAM_ACCESSION", "")),
        assembly=auto_convert(os.environ.get("PARAM_ASSEMBLY", "")),
        chromosome=auto_convert(os.environ.get("PARAM_CHROMOSOME", "")),
        k=auto_convert(os.environ.get("PARAM_K", "10")),
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
    "function": "get_genes_near_ccre",
    "domain": "database",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_genes_near_ccre_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_genes_near_ccre_output.txt", "w") as f:
    f.write("Biomni: Get Genes Near Ccre" + NL)
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
        biomni_function: "get_genes_near_ccre"
    END_VERSIONS
    """
}

workflow GET_GENES_NEAR_CCRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_GENES_NEAR_CCRE(ch_input)

    emit:
    results = GET_GENES_NEAR_CCRE.out.results
    output = GET_GENES_NEAR_CCRE.out.output
    versions = GET_GENES_NEAR_CCRE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_GENES_NEAR_CCRE_WORKFLOW(ch_input)

    GET_GENES_NEAR_CCRE_WORKFLOW.out.output.view { "Output: $it" }
}
