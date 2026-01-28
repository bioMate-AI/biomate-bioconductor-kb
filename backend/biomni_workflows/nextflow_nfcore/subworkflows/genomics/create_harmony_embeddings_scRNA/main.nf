#!/usr/bin/env nextflow
/*
 * genomics/create_harmony_embeddings_scRNA
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PBMC 3k single-cell dataset from Galaxy test data
params.adata_filename = '/home/yzhang/biomate/backend/lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad'
params.batch_key = null
params.data_dir = null

process CREATE_HARMONY_EMBEDDINGS_SCRNA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("create_harmony_embeddings_scRNA_results.json"), emit: results
    tuple val(meta), path("create_harmony_embeddings_scRNA_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ADATA_FILENAME="${params.adata_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BATCH_KEY="${params.batch_key?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_DIR="${params.data_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import scanpy as sc
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



def create_harmony_embeddings_scRNA(adata_filename, batch_key, data_dir):
    # https://pypi.org/project/harmony-pytorch/
    from harmony import harmonize

    steps = []
    steps.append(f"Loading AnnData from {data_dir}/{adata_filename}")
    adata = sc.read_h5ad(f"{data_dir}/{adata_filename}")

    steps.append(f"Running Harmony integration with batch key: {batch_key}")
    adata.obsm["X_harmony"] = harmonize(adata.obsm["X_pca"], adata.obs, batch_key=batch_key)

    output_filename = f"{data_dir}/harmony_emb_data.h5ad"
    steps.append(f"Saving the Harmony embeddings to {output_filename}.")
    adata.write(output_filename)

    return "\\n".join(steps)

# Execute the function
try:
    result = create_harmony_embeddings_scRNA(
        adata_filename=auto_convert(os.environ.get("PARAM_ADATA_FILENAME", "")),
        batch_key=auto_convert(os.environ.get("PARAM_BATCH_KEY", "")),
        data_dir=auto_convert(os.environ.get("PARAM_DATA_DIR", "")),
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
    "function": "create_harmony_embeddings_scRNA",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("create_harmony_embeddings_scRNA_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("create_harmony_embeddings_scRNA_output.txt", "w") as f:
    f.write("Biomni: Create Harmony Embeddings Scrna" + NL)
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
        biomni_function: "create_harmony_embeddings_scRNA"
    END_VERSIONS
    """
}

workflow CREATE_HARMONY_EMBEDDINGS_SCRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CREATE_HARMONY_EMBEDDINGS_SCRNA(ch_input)

    emit:
    results = CREATE_HARMONY_EMBEDDINGS_SCRNA.out.results
    output = CREATE_HARMONY_EMBEDDINGS_SCRNA.out.output
    versions = CREATE_HARMONY_EMBEDDINGS_SCRNA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CREATE_HARMONY_EMBEDDINGS_SCRNA_WORKFLOW(ch_input)

    CREATE_HARMONY_EMBEDDINGS_SCRNA_WORKFLOW.out.output.view { "Output: $it" }
}
