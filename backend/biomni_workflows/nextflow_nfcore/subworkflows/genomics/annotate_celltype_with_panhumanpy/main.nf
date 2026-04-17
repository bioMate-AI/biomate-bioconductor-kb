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
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

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

    export NUMBA_CACHE_DIR=/tmp/numba_cache
    export MPLCONFIGDIR=/tmp/matplotlib
    mkdir -p /tmp/numba_cache /tmp/matplotlib
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
    try:
        subprocess.run(["conda", "--version"], capture_output=True, check=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return "Conda is not available in this environment. panhumanpy requires a dedicated conda environment with Python 3.10. Please install conda and run again, or use a Docker image with conda pre-installed."

    if not conda_env_exists(PANHUMANPY_ENV):
        create_panhumanpy_env(PANHUMANPY_ENV)

    # 2. Write a temp script to run in the panhumanpy_env
    temp_dir = tempfile.mkdtemp()
    script_path = os.path.join(temp_dir, "run_panhumanpy.py")
    result_path = os.path.join(temp_dir, "result.json")
    with open(script_path, "w") as f:
        script_lines = []
        script_lines.append("import os")
        script_lines.append("import sys")
        script_lines.append("import json")
        script_lines.append("import numpy as np")
        script_lines.append("os.environ['NUMBA_CACHE_DIR'] = '/tmp/numba_cache'")
        script_lines.append("import scanpy as sc")
        script_lines.append("import pandas as pd")
        script_lines.append("try:")
        script_lines.append("    import panhumanpy as ph")
        script_lines.append("except ImportError as e:")
        script_lines.append(f"    with open('{result_path}', 'w') as out:")
        script_lines.append("        out.write(json.dumps({'error': str(e)}))")
        script_lines.append("    sys.exit(1)")
        script_lines.append(f"adata_path = '{adata_path}'")
        script_lines.append(f"feature_names_col = {repr(feature_names_col)}")
        script_lines.append(f"refine = {refine}")
        script_lines.append(f"umap_flag = {umap}")
        script_lines.append(f"output_dir = '{output_dir}'")
        # Write the main script body using single-line writes to avoid triple-quote issues
        body = []
        body.append("log = []")
        body.append("try:")
        body.append("    os.makedirs(output_dir, exist_ok=True)")
        body.append("    log.append('Performing cell type annotation with Panhuman Azimuth')")
        body.append("    adata = sc.read_h5ad(adata_path)")
        body.append("    log.append(f'Loaded object with {adata.n_obs} cells and {adata.n_vars} genes')")
        body.append("    if feature_names_col is None:")
        body.append("        azimuth = ph.AzimuthNN(adata)")
        body.append("    else:")
        body.append("        azimuth = ph.AzimuthNN(adata, feature_names_col=feature_names_col)")
        body.append("    cell_metadata = azimuth.cells_meta")
        body.append("    log.append('Successfully annotated all cells')")
        body.append("    if umap_flag:")
        body.append("        try:")
        body.append("            embeddings = azimuth.azimuth_embed()")
        body.append("            azimuth.azimuth_umap()")
        body.append("            log.append('Generated UMAP of ANN embeddings')")
        body.append("        except Exception as e:")
        body.append("            log.append(f'Error generating embeddings: {str(e)}')")
        body.append("    if refine:")
        body.append("        try:")
        body.append("            azimuth.azimuth_refine()")
        body.append("            log.append('Applied label refinement')")
        body.append("        except Exception as e:")
        body.append("            log.append(f'Error during refinement: {str(e)}')")
        body.append("    log.append('Saving results')")
        body.append("    metadata_file = output_dir + '/annotated_cell_metadata.csv'")
        body.append("    cell_metadata.to_csv(metadata_file)")
        body.append("    annotated_save_path = output_dir + '/annotated_obj.h5ad'")
        body.append("    azimuth.pack_adata(save_path=annotated_save_path)")
        body.append("    log.append('All results saved to: ' + output_dir)")
        body.append(f"    with open('{result_path}', 'w') as out:")
        body.append("        out.write(json.dumps({'log': log}))")
        body.append("except Exception as e:")
        body.append(f"    with open('{result_path}', 'w') as out:")
        body.append("        out.write(json.dumps({'error': str(e)}))")
        body.append("    sys.exit(1)")
        f.write("\\n".join(script_lines) + "\\n")
        f.write("\\n".join(body) + "\\n")

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
