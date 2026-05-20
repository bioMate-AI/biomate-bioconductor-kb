#!/usr/bin/env nextflow
/*
 * genomics/get_rna_seq_archs4
 * Given a gene name, this function returns the steps it performs and the max K transcripts-per-million (TPM)
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_name = null
params.K = 10

process GET_RNA_SEQ_ARCHS4 {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_rna_seq_archs4_results.json"), emit: results
    tuple val(meta), path("get_rna_seq_archs4_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENE_NAME="${params.gene_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K="${params.K?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import gget
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



def get_rna_seq_archs4(gene_name: str, K: int = 10) -> str:
    '''Given a gene name, this function returns the steps it performs and the max K transcripts-per-million (TPM)
    per tissue from the RNA-seq expression.

    Parameters
    ----------
    - gene_name (str): The gene name for which RNA-seq data is being fetched.
    - K (int): The number of tissues to return. Default is 10.

    Returns
    -------
    - str: The steps performed and the result.

    '''
    steps_log = f"Starting RNA-seq data fetch for gene: {gene_name} with K: {K}\\n"

    try:
        # Fetch RNA-seq data using gget
        steps_log += "Fetching RNA-seq data using gget.archs4...\\n"
        data = gget.archs4(gene_name, which="tissue")

        if data.empty:
            steps_log += f"No RNA-seq data found for the gene {gene_name}.\\n"
            return steps_log

        # Create a readable output string
        steps_log += f"RNA-seq expression data for {gene_name} fetched successfully. Formatting the top {K} tissues:\\n"
        readable_output = ""
        for index, row in data.iterrows():
            if index < K:
                tissue = row["id"]
                median_tpm = row["median"]
                readable_output += f"\\nTissue: {tissue}\\n  - Median TPM: {median_tpm}\\n"
            else:
                break

        steps_log += readable_output
        return steps_log

    except Exception as e:
        return f"An error occurred: {e}"

# Execute the function
try:
    result = get_rna_seq_archs4(
        gene_name=auto_convert(os.environ.get("PARAM_GENE_NAME", "")),
        K=auto_convert(os.environ.get("PARAM_K", "10")),
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
    "function": "get_rna_seq_archs4",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_rna_seq_archs4_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_rna_seq_archs4_output.txt", "w") as f:
    f.write("Biomni: Get Rna Seq Archs4" + NL)
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
        biomni_function: "get_rna_seq_archs4"
    END_VERSIONS
    """
}

workflow GET_RNA_SEQ_ARCHS4_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_RNA_SEQ_ARCHS4(ch_input)

    emit:
    results = GET_RNA_SEQ_ARCHS4.out.results
    output = GET_RNA_SEQ_ARCHS4.out.output
    versions = GET_RNA_SEQ_ARCHS4.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_RNA_SEQ_ARCHS4_WORKFLOW(ch_input)

    GET_RNA_SEQ_ARCHS4_WORKFLOW.out.output.view { "Output: $it" }
}
