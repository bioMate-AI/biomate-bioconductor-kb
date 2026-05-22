#!/usr/bin/env nextflow
/*
 * bioimaging/check_model_files_exist
 * Check if actual model weight files exist for the specified folds
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: null values to run in demo mode (no actual model needed)
params.model_folder = null
params.folds = '[0, 1, 2, 3, 4]'

process CHECK_MODEL_FILES_EXIST {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("check_model_files_exist_results.json"), emit: results
    tuple val(meta), path("check_model_files_exist_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_MODEL_FOLDER="${params.model_folder?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FOLDS="${params.folds?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def check_model_files_exist(model_folder=None, folds=None):
    '''Check if nnU-Net model weight files exist for specified folds.

    Args:
        model_folder: Path to the nnU-Net model folder
        folds: List of fold numbers to check (e.g., [0, 1, 2, 3, 4] or "all")

    Returns:
        Dictionary with model file existence status
    '''
    import os
    from pathlib import Path

    # Handle demo/test mode - if no model folder, return simulated result
    if model_folder is None or model_folder == 'null':
        return {
            "function": "check_model_files_exist",
            "status": "demo_mode",
            "message": "No model folder specified - running in demo mode",
            "model_folder": None,
            "folds_checked": [],
            "files_found": {},
            "all_exist": False
        }

    model_path = Path(model_folder)

    # Parse folds parameter
    if folds is None or folds == 'null' or folds == 'all':
        fold_list = [0, 1, 2, 3, 4]  # Default nnU-Net folds
    elif isinstance(folds, list):
        fold_list = folds
    elif isinstance(folds, str):
        # Try to parse as JSON or comma-separated
        try:
            fold_list = json.loads(folds)
        except:
            fold_list = [int(f.strip()) for f in folds.split(',')]
    else:
        fold_list = [int(folds)]

    # Check for model files
    files_found = {}
    missing_files = []

    for fold in fold_list:
        fold_dir = model_path / f"fold_{fold}"

        # nnU-Net model files to check
        model_files = [
            "checkpoint_final.pth",
            "checkpoint_best.pth",
            "model_final_checkpoint.model",
            "model_final_checkpoint.model.pkl"
        ]

        fold_files = {}
        for model_file in model_files:
            file_path = fold_dir / model_file
            exists = file_path.exists() if model_path.exists() else False
            fold_files[model_file] = exists

        files_found[f"fold_{fold}"] = fold_files

        # Check if at least one model file exists for this fold
        if not any(fold_files.values()):
            missing_files.append(f"fold_{fold}")

    all_exist = len(missing_files) == 0

    return {
        "function": "check_model_files_exist",
        "status": "success",
        "model_folder": str(model_folder),
        "folds_checked": fold_list,
        "files_found": files_found,
        "missing_folds": missing_files,
        "all_exist": all_exist,
        "message": "All model files found" if all_exist else f"Missing files for folds: {missing_files}"
    }

# Execute the function
try:
    result = check_model_files_exist(
        model_folder=auto_convert(os.environ.get("PARAM_MODEL_FOLDER", "")),
        folds=auto_convert(os.environ.get("PARAM_FOLDS", "")),
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
    "function": "check_model_files_exist",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("check_model_files_exist_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("check_model_files_exist_output.txt", "w") as f:
    f.write("Biomni: Check Model Files Exist" + NL)
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
        biomni_function: "check_model_files_exist"
    END_VERSIONS
    """
}

workflow CHECK_MODEL_FILES_EXIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CHECK_MODEL_FILES_EXIST(ch_input)

    emit:
    results = CHECK_MODEL_FILES_EXIST.out.results
    output = CHECK_MODEL_FILES_EXIST.out.output
    versions = CHECK_MODEL_FILES_EXIST.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CHECK_MODEL_FILES_EXIST_WORKFLOW(ch_input)

    CHECK_MODEL_FILES_EXIST_WORKFLOW.out.output.view { "Output: $it" }
}
