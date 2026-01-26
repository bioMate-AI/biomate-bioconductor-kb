#!/usr/bin/env nextflow
/*
 * genomics/create_scvi_embeddings_scRNA
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_filename = null
params.batch_key = null
params.label_key = null
params.data_dir = null

process CREATE_SCVI_EMBEDDINGS_SCRNA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("create_scvi_embeddings_scRNA_results.json"), emit: results
    tuple val(meta), path("create_scvi_embeddings_scRNA_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ADATA_FILENAME="${params.adata_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BATCH_KEY="${params.batch_key?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LABEL_KEY="${params.label_key?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def create_scvi_embeddings_scRNA(adata_filename, batch_key, label_key, data_dir):
    # Import scvi-tools correctly - the package name is still 'scvi' when installed
    try:
        import scvi
    except ImportError:
        return "Please install scvi-tools: pip install scvi-tools"

    steps = []
    steps.append(f"Loading AnnData from {data_dir}/{adata_filename}")
    adata = sc.read_h5ad(f"{data_dir}/{adata_filename}")

    steps.append(f"Setting up AnnData for scVI with batch key: {batch_key}")
    scvi.model.SCVI.setup_anndata(adata, batch_key=batch_key)

    steps.append("Creating and training scVI model")
    model = scvi.model.SCVI(adata)
    model.train()

    steps.append("Generating latent representation using scVI")
    adata.obsm["X_scVI"] = model.get_latent_representation()

    steps.append(f"Creating scANVI model with label key: {label_key}")
    lvae = scvi.model.SCANVI.from_scvi_model(
        model,
        adata=adata,
        labels_key=label_key,
        unlabeled_category="Unknown",
    )
    steps.append("Training scANVI model")
    lvae.train()

    steps.append("Generating latent representation using scANVI")
    adata.obsm["X_scANVI"] = lvae.get_latent_representation(adata)

    output_filename = f"{data_dir}/scvi_emb_data.h5ad"
    adata.write(output_filename)
    steps.append(f"Saving AnnData with scVI and scANVI embeddings to {output_filename}")

    return "\\n".join(steps)

# Execute the function
try:
    result = create_scvi_embeddings_scRNA(
        adata_filename=auto_convert(os.environ.get("PARAM_ADATA_FILENAME", "")),
        batch_key=auto_convert(os.environ.get("PARAM_BATCH_KEY", "")),
        label_key=auto_convert(os.environ.get("PARAM_LABEL_KEY", "")),
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
    "function": "create_scvi_embeddings_scRNA",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("create_scvi_embeddings_scRNA_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("create_scvi_embeddings_scRNA_output.txt", "w") as f:
    f.write("Biomni: Create Scvi Embeddings Scrna" + NL)
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
        biomni_function: "create_scvi_embeddings_scRNA"
    END_VERSIONS
    """
}

workflow CREATE_SCVI_EMBEDDINGS_SCRNA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CREATE_SCVI_EMBEDDINGS_SCRNA(ch_input)

    emit:
    results = CREATE_SCVI_EMBEDDINGS_SCRNA.out.results
    output = CREATE_SCVI_EMBEDDINGS_SCRNA.out.output
    versions = CREATE_SCVI_EMBEDDINGS_SCRNA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CREATE_SCVI_EMBEDDINGS_SCRNA_WORKFLOW(ch_input)

    CREATE_SCVI_EMBEDDINGS_SCRNA_WORKFLOW.out.output.view { "Output: $it" }
}
