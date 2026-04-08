#!/usr/bin/env nextflow
/*
 * bioimaging/setup_nnunet_environment
 * Setup nnU-Net environment variables according to official documentation
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: null values use default paths under ~/nnUNet_data/
params.results_folder = null
params.raw_data_base = null
params.preprocessed = null

process SETUP_NNUNET_ENVIRONMENT {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("setup_nnunet_environment_results.json"), emit: results
    tuple val(meta), path("setup_nnunet_environment_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_RESULTS_FOLDER="${params.results_folder?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RAW_DATA_BASE="${params.raw_data_base?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PREPROCESSED="${params.preprocessed?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def setup_nnunet_environment(results_folder=None, raw_data_base=None, preprocessed=None):
    '''Setup nnU-Net environment variables according to official documentation.

    nnU-Net requires specific environment variables to be set:
    - nnUNet_raw: Path to raw data
    - nnUNet_preprocessed: Path to preprocessed data
    - nnUNet_results: Path to store results/trained models

    Args:
        results_folder: Path for nnU-Net results (trained models)
        raw_data_base: Path for raw input data
        preprocessed: Path for preprocessed data

    Returns:
        Dictionary with environment setup details
    '''
    import os
    from pathlib import Path

    # Default paths if not specified
    home_dir = Path.home()
    default_base = home_dir / "nnUNet_data"

    # Set up paths
    if results_folder and results_folder != 'null':
        results_path = Path(results_folder)
    else:
        results_path = default_base / "nnUNet_results"

    if raw_data_base and raw_data_base != 'null':
        raw_path = Path(raw_data_base)
    else:
        raw_path = default_base / "nnUNet_raw"

    if preprocessed and preprocessed != 'null':
        preprocessed_path = Path(preprocessed)
    else:
        preprocessed_path = default_base / "nnUNet_preprocessed"

    # Create directories if they don't exist
    directories_created = []
    for path in [results_path, raw_path, preprocessed_path]:
        if not path.exists():
            try:
                path.mkdir(parents=True, exist_ok=True)
                directories_created.append(str(path))
            except PermissionError:
                pass  # May not have permissions in container

    # Set environment variables
    env_vars = {
        "nnUNet_results": str(results_path),
        "nnUNet_raw": str(raw_path),
        "nnUNet_preprocessed": str(preprocessed_path)
    }

    for var_name, var_value in env_vars.items():
        os.environ[var_name] = var_value

    # Verify environment is set correctly
    verification = {
        var: os.environ.get(var, "NOT SET") for var in env_vars.keys()
    }

    # Check for nnU-Net installation
    try:
        import nnunetv2
        nnunet_installed = True
        nnunet_version = getattr(nnunetv2, '__version__', 'unknown')
    except ImportError:
        try:
            import nnunet
            nnunet_installed = True
            nnunet_version = "v1 (legacy)"
        except ImportError:
            nnunet_installed = False
            nnunet_version = None

    return {
        "function": "setup_nnunet_environment",
        "status": "success",
        "environment_variables": env_vars,
        "verification": verification,
        "directories_created": directories_created,
        "nnunet_installed": nnunet_installed,
        "nnunet_version": nnunet_version,
        "paths": {
            "results": str(results_path),
            "raw_data": str(raw_path),
            "preprocessed": str(preprocessed_path)
        },
        "message": "nnU-Net environment configured successfully"
    }

# Execute the function
try:
    result = setup_nnunet_environment(
        results_folder=auto_convert(os.environ.get("PARAM_RESULTS_FOLDER", "")),
        raw_data_base=auto_convert(os.environ.get("PARAM_RAW_DATA_BASE", "")),
        preprocessed=auto_convert(os.environ.get("PARAM_PREPROCESSED", "")),
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
    "function": "setup_nnunet_environment",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("setup_nnunet_environment_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("setup_nnunet_environment_output.txt", "w") as f:
    f.write("Biomni: Setup Nnunet Environment" + NL)
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
        biomni_function: "setup_nnunet_environment"
    END_VERSIONS
    """
}

workflow SETUP_NNUNET_ENVIRONMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SETUP_NNUNET_ENVIRONMENT(ch_input)

    emit:
    results = SETUP_NNUNET_ENVIRONMENT.out.results
    output = SETUP_NNUNET_ENVIRONMENT.out.output
    versions = SETUP_NNUNET_ENVIRONMENT.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SETUP_NNUNET_ENVIRONMENT_WORKFLOW(ch_input)

    SETUP_NNUNET_ENVIRONMENT_WORKFLOW.out.output.view { "Output: $it" }
}
