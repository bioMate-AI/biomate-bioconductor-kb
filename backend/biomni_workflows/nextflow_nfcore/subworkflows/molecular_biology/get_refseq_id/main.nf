#!/usr/bin/env nextflow
/*
 * molecular_biology/get_refseq_id
 * Get RefSeq ID from gene record.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_symbol = null
params.organism = null

process GET_REFSEQ_ID {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_refseq_id_results.json"), emit: results
    tuple val(meta), path("get_refseq_id_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_GENE_SYMBOL="${params.gene_symbol?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ORGANISM="${params.organism?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

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



def get_refseq_id(gene_symbol, organism="human"):
    '''Look up RefSeq ID for gene symbol. Returns placeholder - actual lookup requires API.
    Args: gene_symbol: gene name, organism: species
    '''
    # This would normally query NCBI - return placeholder
    return {"gene_symbol": gene_symbol, "organism": organism, "refseq_id": f"NM_placeholder_{gene_symbol}", 
            "note": "Actual RefSeq lookup requires NCBI Entrez API"}

# Execute the function
try:
    result = get_refseq_id(
        gene_symbol=auto_convert(os.environ.get("PARAM_GENE_SYMBOL", "")),
        organism=auto_convert(os.environ.get("PARAM_ORGANISM", "")),
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
    "function": "get_refseq_id",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_refseq_id_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_refseq_id_output.txt", "w") as f:
    f.write("Biomni: Get Refseq Id" + NL)
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
        biomni_function: "get_refseq_id"
    END_VERSIONS
    """
}

workflow GET_REFSEQ_ID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_REFSEQ_ID(ch_input)

    emit:
    results = GET_REFSEQ_ID.out.results
    output = GET_REFSEQ_ID.out.output
    versions = GET_REFSEQ_ID.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_REFSEQ_ID_WORKFLOW(ch_input)

    GET_REFSEQ_ID_WORKFLOW.out.output.view { "Output: $it" }
}
