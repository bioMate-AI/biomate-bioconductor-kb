#!/usr/bin/env nextflow
/*
 * genomics/annotate_celltype_scRNA
 * Annotate cell types based on gene markers and transferred labels using LLM.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PBMC 3k single-cell dataset from Galaxy test data
params.adata_filename = '/home/yzhang/biomate/backend/lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad'
params.data_dir = null
params.data_info = null
params.data_lake_path = null
params.cluster = 'leiden'
params.llm = 'claude-sonnet-4-5'
params.composition = null

process ANNOTATE_CELLTYPE_SCRNA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("annotate_celltype_scRNA_results.json"), emit: results
    tuple val(meta), path("annotate_celltype_scRNA_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ADATA_FILENAME="${params.adata_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_DIR="${params.data_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_INFO="${params.data_info?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_LAKE_PATH="${params.data_lake_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CLUSTER="${params.cluster?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LLM="${params.llm?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COMPOSITION="${params.composition?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def annotate_celltype_scRNA(**kwargs):
    '''Placeholder for annotate_celltype_scRNA. Actual implementation requires specific dependencies.
    '''
    return {"function": "annotate_celltype_scRNA", "status": "placeholder", "args": kwargs,
            "note": "This function requires specific dependencies not available in this context"}

# Execute the function
try:
    result = annotate_celltype_scRNA(
        adata_filename=auto_convert(os.environ.get("PARAM_ADATA_FILENAME", "")),
        data_dir=auto_convert(os.environ.get("PARAM_DATA_DIR", "")),
        data_info=auto_convert(os.environ.get("PARAM_DATA_INFO", "")),
        data_lake_path=auto_convert(os.environ.get("PARAM_DATA_LAKE_PATH", "")),
        cluster=auto_convert(os.environ.get("PARAM_CLUSTER", "leiden")),
        llm=auto_convert(os.environ.get("PARAM_LLM", "claude-sonnet-4-5")),
        composition=auto_convert(os.environ.get("PARAM_COMPOSITION", "")),
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
    "function": "annotate_celltype_scRNA",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("annotate_celltype_scRNA_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("annotate_celltype_scRNA_output.txt", "w") as f:
    f.write("Biomni: Annotate Celltype Scrna" + NL)
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
        biomni_function: "annotate_celltype_scRNA"
    END_VERSIONS
    """
}

workflow ANNOTATE_CELLTYPE_SCRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANNOTATE_CELLTYPE_SCRNA(ch_input)

    emit:
    results = ANNOTATE_CELLTYPE_SCRNA.out.results
    output = ANNOTATE_CELLTYPE_SCRNA.out.output
    versions = ANNOTATE_CELLTYPE_SCRNA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANNOTATE_CELLTYPE_SCRNA_WORKFLOW(ch_input)

    ANNOTATE_CELLTYPE_SCRNA_WORKFLOW.out.output.view { "Output: $it" }
}
