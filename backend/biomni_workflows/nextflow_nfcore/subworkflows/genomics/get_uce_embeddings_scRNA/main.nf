#!/usr/bin/env nextflow
/*
 * genomics/get_uce_embeddings_scRNA
 * The UCE embeddings are usually our default tools to get cell embeddings, we map UCE embeddings to IMA referece dataset and get the cell types for a better understanding.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PBMC 3k single-cell dataset from Galaxy test data
params.adata_filename = '/home/yzhang/biomate/backend/lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad'
params.data_dir = null
params.DATA_ROOT = '/dfs/project/bioagentos/data/singlecell/'
params.custom_args = null

process GET_UCE_EMBEDDINGS_SCRNA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_uce_embeddings_scRNA_results.json"), emit: results
    tuple val(meta), path("get_uce_embeddings_scRNA_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ADATA_FILENAME="${params.adata_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_DIR="${params.data_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_ROOT="${params.DATA_ROOT?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CUSTOM_ARGS="${params.custom_args?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
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



def get_uce_embeddings_scRNA(
    adata_filename,
    data_dir,
    DATA_ROOT="/dfs/project/bioagentos/data/singlecell/",
    custom_args=None,
):
    '''The UCE embeddings are usually our default tools to get cell embeddings, we map UCE embeddings to IMA referece dataset and get the cell types for a better understanding.
    The custom_args is a list of strings that will be passed as command line arguments to the UCE script,
    like ["--adata_path", adata_file, "--dir", output_dir]. The default value is None.
    '''
    import sys

    steps = []

    try:
        from eval_single_anndata import main, parse_args_uce

        steps.append("Successfully imported UCE main function")
    except Exception:
        steps.append("Please install the UCE package first. Follow https://github.com/snap-stanford/UCE.git.")
        return "\\n".join(steps)

    from accelerate import Accelerator

    _base_name = os.path.basename(adata_filename).split(".")[0]
    adata_file_proc = f"{data_dir}/{_base_name}_uce_adata.h5ad"
    if os.path.exists(adata_file_proc):
        steps.append(f"{adata_file_proc} already exists, skipping. The UCE embeddings are stored as adata.obs['X_uce']")
        return "\\n".join(steps)

    uce_dir = f"{DATA_ROOT}/UCE"
    sys.path.append(uce_dir)
    steps.append(f"Added {uce_dir} to sys.path")

    # Prepare and parse arguments
    if custom_args is None:
        custom_args = []
    custom_args.extend(["--adata_path", f"{data_dir}/{adata_filename}", "--dir", f"{data_dir}/uce/"])
    parsed_args = parse_args_uce(custom_args)
    steps.append(f"Parsed arguments: {vars(parsed_args)}")

    # Initialize Accelerator
    accelerator = Accelerator(project_dir=parsed_args.dir)
    steps.append("Initialized Accelerator")

    # Run UCE main function
    main(parsed_args, accelerator)
    steps.append("UCE main function completed successfully.")
    steps.append(f"{adata_file_proc} is saved, the UCE embeddings are stored as adata.obs['X_uce']")

    return "\\n".join(steps)

# Execute the function
try:
    result = get_uce_embeddings_scRNA(
        adata_filename=auto_convert(os.environ.get("PARAM_ADATA_FILENAME", "")),
        data_dir=auto_convert(os.environ.get("PARAM_DATA_DIR", "")),
        DATA_ROOT=auto_convert(os.environ.get("PARAM_DATA_ROOT", "/dfs/project/bioagentos/data/singlecell/")),
        custom_args=auto_convert(os.environ.get("PARAM_CUSTOM_ARGS", "")),
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
    "function": "get_uce_embeddings_scRNA",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_uce_embeddings_scRNA_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_uce_embeddings_scRNA_output.txt", "w") as f:
    f.write("Biomni: Get Uce Embeddings Scrna" + NL)
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
        biomni_function: "get_uce_embeddings_scRNA"
    END_VERSIONS
    """
}

workflow GET_UCE_EMBEDDINGS_SCRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_UCE_EMBEDDINGS_SCRNA(ch_input)

    emit:
    results = GET_UCE_EMBEDDINGS_SCRNA.out.results
    output = GET_UCE_EMBEDDINGS_SCRNA.out.output
    versions = GET_UCE_EMBEDDINGS_SCRNA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_UCE_EMBEDDINGS_SCRNA_WORKFLOW(ch_input)

    GET_UCE_EMBEDDINGS_SCRNA_WORKFLOW.out.output.view { "Output: $it" }
}
