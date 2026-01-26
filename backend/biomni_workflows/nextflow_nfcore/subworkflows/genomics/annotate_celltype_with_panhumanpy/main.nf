#!/usr/bin/env nextflow
/*
 * genomics/annotate_celltype_with_panhumanpy
 * Perform hierarchical cell type annotation using panhumanpy and Azimuth Neural Network.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_path = null
params.feature_names_col = null
params.refine = 'True'
params.umap = 'True'
params.output_dir = './output'

process ANNOTATE_CELLTYPE_WITH_PANHUMANPY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("annotate_celltype_with_panhumanpy_results.json"), emit: results
    tuple val(meta), path("annotate_celltype_with_panhumanpy_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ADATA_PATH="${params.adata_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FEATURE_NAMES_COL="${params.feature_names_col?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REFINE="${params.refine?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_UMAP="${params.umap?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
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



def annotate_celltype_with_panhumanpy(
    adata_path,
    feature_names_col=None,
    refine=True,
    umap=True,
    output_dir="./output",
):
    '''Perform hierarchical cell type annotation using panhumanpy and Azimuth Neural Network.

    This function implements the panhumanpy workflow for cell type annotation using the
    Azimuth Neural Network, providing hierarchical cell type labels with confidence scores.

    Parameters
    ----------
    adata_path : str
        Path to the AnnData file containing scRNA-seq data
    feature_names_col : str, optional
        Column name in adata.var containing gene names (default: None, uses index)
    refine : bool, optional
        Whether to perform label refinement for consistent granularity (default: True)
    umap : bool, optional
        Whether to generate ANN embeddings and UMAP (default: True)
    output_dir : str, optional
        Directory to save results (default: "./output")

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    Notes
    -----
    Performance is not ensured for diseased and/or non-human cells.
    '''
    import json
    import shutil
    import subprocess
    import tempfile

    def conda_env_exists(env_name):
        try:
            result = subprocess.run(["conda", "env", "list"], capture_output=True, text=True, check=True)
            return any(env_name in line.split() for line in result.stdout.splitlines())
        except Exception:
            return False

    def create_panhumanpy_env(env_name):
        # Create env and install panhumanpy
        subprocess.run(["conda", "create", "-y", "-n", env_name, "python=3.10"], check=True)
        # Install panhumanpy in the new env
        subprocess.run(
            ["conda", "run", "-n", env_name, "pip", "install", "git+https://github.com/satijalab/panhumanpy.git"],
            check=True,
        )

    PANHUMANPY_ENV = "panhumanpy_env"

    # 1. Check/create panhumanpy_env
    if not conda_env_exists(PANHUMANPY_ENV):
        create_panhumanpy_env(PANHUMANPY_ENV)

    # 2. Write a temp script to run in the panhumanpy_env
    temp_dir = tempfile.mkdtemp()
    script_path = os.path.join(temp_dir, "run_panhumanpy.py")
    result_path = os.path.join(temp_dir, "result.json")
    with open(script_path, "w") as f:
        f.write(
            f'''
import os
import sys
import json
import numpy as np
import scanpy as sc
import pandas as pd
try:
    import panhumanpy as ph
except ImportError as e:
    with open(r'{result_path}', 'w') as out:
        out.write(json.dumps({{"error": str(e)}}))
    sys.exit(1)

adata_path = r'''{adata_path}'''
feature_names_col = {repr(feature_names_col)}
refine = {refine}
umap = {umap}
output_dir = r'''{output_dir}'''
log = []
try:
    os.makedirs(output_dir, exist_ok=True)
    log.append("# Performing cell type annotation with Panhuman Azimuth")
    log.append(f"Loading object from: {{adata_path}}")
    adata = sc.read_h5ad(adata_path)
    log.append(f"✓ Successfully loaded object with {{adata.n_obs}} cells and {{adata.n_vars}} genes")
    if feature_names_col is None:
        log.append("Using gene names from adata.var.index")
    else:
        log.append(f"Using gene names from column: {{feature_names_col}}")
        if feature_names_col not in adata.var.columns:
            log.append(f"⚠ Warning: Column '{{feature_names_col}}' not found in adata.var")
            log.append(f"Available columns: {{list(adata.var.columns)}}")
            log.append("Falling back to index")
            feature_names_col = None
    if feature_names_col is None:
        azimuth = ph.AzimuthNN(adata)
    else:
        azimuth = ph.AzimuthNN(adata, feature_names_col=feature_names_col)
    cell_metadata = azimuth.cells_meta
    log.append("✓ Successfully annotated all cells")
    if umap:
        log.append("## Generating ANN embeddings")
        try:
            embeddings = azimuth.azimuth_embed()
        except Exception as e:
            log.append(f"✗ Error generating embeddings: {{str(e)}}")
            with open(r'{result_path}', 'w') as out:
                out.write(json.dumps({{"log": log}}))
            sys.exit(0)
        log.append("## Calculating UMAP")
        try:
            azimuth.azimuth_umap()
            log.append("✓ Generated UMAP of ANN embeddings")
        except Exception as e:
            log.append(f"✗ Error generating UMAP: {{str(e)}}")
            with open(r'{result_path}', 'w') as out:
                out.write(json.dumps({{"log": log}}))
            sys.exit(0)
    else:
        log.append("## Skipping embeddings and UMAP generation")
        embeddings = None
        umap = None
    if refine:
        log.append("## Performing label refinement")
        try:
            azimuth.azimuth_refine()
            cell_metadata = azimuth.cells_meta
            refined_columns = [col for col in cell_metadata.columns if col.startswith("azimuth_")]
            log.append(f"✓ Applied label refinement, results are in columns: {{refined_columns}}")
        except Exception as e:
            log.append(f"✗ Error during label refinement: {{str(e)}}")
    log.append("## Saving results")
    try:
        metadata_file = f"{output_dir}/annotated_cell_metadata.csv"
        cell_metadata.to_csv(metadata_file)
        log.append(f"✓ Saved cell metadata to: {{metadata_file}}")
        if umap and embeddings is not None:
            embeddings_file = f"{output_dir}/ann_embeddings.npy"
            np.save(embeddings_file, embeddings)
            log.append(f"✓ Saved embeddings to: {{embeddings_file}}")
            umap_file = f"{output_dir}/ann_umap.npy"
            np.save(umap_file, umap)
            log.append(f"✓ Saved UMAP to: {{umap_file}}")
        else:
            log.append("Skipped saving embeddings and UMAP (umap=False)")
        annotated_save_path = f"{output_dir}/annotated_obj.h5ad"
        azimuth.pack_adata(save_path=annotated_save_path)
        log.append(f"✓ Saved annotated object to: {{annotated_save_path}}")
    except Exception as e:
        log.append(f"✗ Error saving results: {{str(e)}}")
        with open(r'{result_path}', 'w') as out:
            out.write(json.dumps({{"log": log}}))
        sys.exit(0)
    log.append(f"- All results saved to: {output_dir}")
    with open(r'{result_path}', 'w') as out:
        out.write(json.dumps({{"log": log}}))
except Exception as e:
    with open(r'{result_path}', 'w') as out:
        out.write(json.dumps({{"error": str(e)}}))
    sys.exit(1)
'''
        )

    # 3. Run the script in the panhumanpy_env
    try:
        run_cmd = ["conda", "run", "-n", PANHUMANPY_ENV, "python", script_path]
        subprocess.run(run_cmd, check=True)
    except subprocess.CalledProcessError as e:
        shutil.rmtree(temp_dir)
        return f"Error running panhumanpy in conda env: {e}"

    # 4. Read the result
    try:
        with open(result_path) as f:
            result = json.load(f)
        if "log" in result:
            log = result["log"]
        elif "error" in result:
            log = [f"Error: {result['error']}"]
        else:
            log = ["Unknown error running panhumanpy script."]
    except Exception as e:
        log = [f"Error reading result: {e}"]

    # 5. Clean up temp files
    shutil.rmtree(temp_dir)

    return "\\n".join(log)

# Execute the function
try:
    result = annotate_celltype_with_panhumanpy(
        adata_path=auto_convert(os.environ.get("PARAM_ADATA_PATH", "")),
        feature_names_col=auto_convert(os.environ.get("PARAM_FEATURE_NAMES_COL", "")),
        refine=auto_convert(os.environ.get("PARAM_REFINE", "True")),
        umap=auto_convert(os.environ.get("PARAM_UMAP", "True")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./output")),
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
    "function": "annotate_celltype_with_panhumanpy",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("annotate_celltype_with_panhumanpy_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("annotate_celltype_with_panhumanpy_output.txt", "w") as f:
    f.write("Biomni: Annotate Celltype With Panhumanpy" + NL)
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
        biomni_function: "annotate_celltype_with_panhumanpy"
    END_VERSIONS
    """
}

workflow ANNOTATE_CELLTYPE_WITH_PANHUMANPY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANNOTATE_CELLTYPE_WITH_PANHUMANPY(ch_input)

    emit:
    results = ANNOTATE_CELLTYPE_WITH_PANHUMANPY.out.results
    output = ANNOTATE_CELLTYPE_WITH_PANHUMANPY.out.output
    versions = ANNOTATE_CELLTYPE_WITH_PANHUMANPY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANNOTATE_CELLTYPE_WITH_PANHUMANPY_WORKFLOW(ch_input)

    ANNOTATE_CELLTYPE_WITH_PANHUMANPY_WORKFLOW.out.output.view { "Output: $it" }
}
