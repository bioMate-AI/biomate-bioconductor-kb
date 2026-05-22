#!/usr/bin/env nextflow
/*
 * genomics/is_model_downloaded
 * Check if a machine learning model is downloaded by looking for key files
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Check for model files in a demo path
params.checkpoint_path = '/models/demo_model'
params.model_type = 'generic'

process IS_MODEL_DOWNLOADED {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("is_model_downloaded_results.json"), emit: results
    tuple val(meta), path("is_model_downloaded_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CHECKPOINT_PATH="${params.checkpoint_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os
from pathlib import Path

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


def is_model_downloaded(checkpoint_path=None, model_type='generic'):
    '''Check if a machine learning model is downloaded by looking for key files.

    This function checks for common model file patterns based on model type:
    - pytorch: .pt, .pth, .bin files
    - tensorflow: .pb, .h5, saved_model directory
    - onnx: .onnx files
    - huggingface: config.json, model.safetensors, pytorch_model.bin
    - scvi: model.pt, model_params.pt
    - generic: any common model file extension

    Parameters
    ----------
    checkpoint_path : str
        Path to check for model files
    model_type : str
        Type of model: 'pytorch', 'tensorflow', 'onnx', 'huggingface', 'scvi', 'generic'

    Returns
    -------
    dict
        Status of model download with details about found files
    '''
    result = {
        "checkpoint_path": checkpoint_path,
        "model_type": model_type,
        "is_downloaded": False,
        "files_found": [],
        "files_missing": [],
    }

    # Define expected file patterns for each model type
    model_patterns = {
        "pytorch": [".pt", ".pth", ".bin"],
        "tensorflow": [".pb", ".h5", "saved_model"],
        "onnx": [".onnx"],
        "huggingface": ["config.json", "model.safetensors", "pytorch_model.bin", "tokenizer.json"],
        "scvi": ["model.pt", "model_params.pt", "attr.pkl"],
        "generic": [".pt", ".pth", ".bin", ".h5", ".onnx", ".pb", "config.json", ".safetensors"],
    }

    if checkpoint_path is None:
        result["status"] = "demo_mode"
        result["message"] = "No checkpoint_path provided. Running in demo mode."
        result["demo_info"] = {
            "supported_model_types": list(model_patterns.keys()),
            "usage": "Provide checkpoint_path to check for model files",
            "example": "/path/to/model/directory or /path/to/model.pt",
        }
        result["is_downloaded"] = None
        return result

    path = Path(checkpoint_path)
    patterns = model_patterns.get(model_type, model_patterns["generic"])

    # Check if path exists
    if not path.exists():
        result["status"] = "path_not_found"
        result["message"] = f"Path does not exist: {checkpoint_path}"
        result["is_downloaded"] = False
        return result

    # If path is a file, check if it matches expected patterns
    if path.is_file():
        file_ext = path.suffix
        file_name = path.name
        for pattern in patterns:
            if pattern.startswith("."):
                if file_ext == pattern:
                    result["files_found"].append(str(path))
                    result["is_downloaded"] = True
                    break
            else:
                if pattern in file_name:
                    result["files_found"].append(str(path))
                    result["is_downloaded"] = True
                    break

        if not result["is_downloaded"]:
            result["files_missing"].append(f"Expected pattern from: {patterns}")

        result["status"] = "file_checked"
        return result

    # If path is a directory, scan for model files
    if path.is_dir():
        all_files = list(path.rglob("*"))
        for f in all_files:
            if f.is_file():
                for pattern in patterns:
                    if pattern.startswith("."):
                        if f.suffix == pattern:
                            result["files_found"].append(str(f.relative_to(path)))
                            break
                    else:
                        if pattern in f.name:
                            result["files_found"].append(str(f.relative_to(path)))
                            break

        result["is_downloaded"] = len(result["files_found"]) > 0
        result["total_files_in_dir"] = len([f for f in all_files if f.is_file()])

        # Check for specific required files based on model type
        if model_type == "huggingface":
            required = ["config.json"]
            for req in required:
                if not any(req in f for f in result["files_found"]):
                    result["files_missing"].append(req)

        result["status"] = "directory_scanned"
        return result

    result["status"] = "unknown_path_type"
    return result

# Execute the function
try:
    result = is_model_downloaded(
        checkpoint_path=auto_convert(os.environ.get("PARAM_CHECKPOINT_PATH", "")),
        model_type=auto_convert(os.environ.get("PARAM_MODEL_TYPE", "generic")) or "generic",
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
    "function": "is_model_downloaded",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("is_model_downloaded_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("is_model_downloaded_output.txt", "w") as f:
    f.write("Biomni: Is Model Downloaded" + NL)
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
        biomni_function: "is_model_downloaded"
    END_VERSIONS
    """
}

workflow IS_MODEL_DOWNLOADED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    IS_MODEL_DOWNLOADED(ch_input)

    emit:
    results = IS_MODEL_DOWNLOADED.out.results
    output = IS_MODEL_DOWNLOADED.out.output
    versions = IS_MODEL_DOWNLOADED.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    IS_MODEL_DOWNLOADED_WORKFLOW(ch_input)

    IS_MODEL_DOWNLOADED_WORKFLOW.out.output.view { "Output: $it" }
}
