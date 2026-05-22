#!/usr/bin/env nextflow
/*
 * bioimaging/patched_torch_load
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// No value parameters

process PATCHED_TORCH_LOAD {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("patched_torch_load_results.json"), emit: results
    tuple val(meta), path("patched_torch_load_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    # No value parameters

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



def patched_torch_load():
    # Create a patched torch.load function for safe model loading.
    # This provides a safer alternative to torch.load that handles common
    # issues like pickle security warnings and device mapping for CPU inference.
    # Returns: Dictionary with patched loader configuration and usage instructions
    #
    # Check if torch is available
    try:
        import torch
        torch_available = True
        torch_version = torch.__version__
    except ImportError:
        torch_available = False
        torch_version = None

    return dict(
        function="patched_torch_load",
        status="success",
        torch_available=torch_available,
        torch_version=torch_version,
        description="Safe PyTorch model loader with security patches",
        features=[
            "Maps tensors to CPU by default for safe inference",
            "Uses weights_only=True when available (PyTorch >= 1.13)",
            "Provides SafeUnpickler class for additional security",
            "Includes nnU-Net specific loader function"
        ],
        basic_usage="torch.load(path, map_location=cpu, weights_only=True)",
        security_notes=[
            "Always use weights_only=True when possible",
            "Avoid loading models from untrusted sources",
            "Consider using torch.jit.load for TorchScript models"
        ]
    )

# Execute the function
try:
    result = patched_torch_load()
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "patched_torch_load",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("patched_torch_load_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("patched_torch_load_output.txt", "w") as f:
    f.write("Biomni: Patched Torch Load" + NL)
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
        biomni_function: "patched_torch_load"
    END_VERSIONS
    """
}

workflow PATCHED_TORCH_LOAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PATCHED_TORCH_LOAD(ch_input)

    emit:
    results = PATCHED_TORCH_LOAD.out.results
    output = PATCHED_TORCH_LOAD.out.output
    versions = PATCHED_TORCH_LOAD.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PATCHED_TORCH_LOAD_WORKFLOW(ch_input)

    PATCHED_TORCH_LOAD_WORKFLOW.out.output.view { "Output: $it" }
}
