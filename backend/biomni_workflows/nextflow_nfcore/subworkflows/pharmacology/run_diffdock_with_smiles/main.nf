#!/usr/bin/env nextflow
/*
 * pharmacology/run_diffdock_with_smiles
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pdb_path = null  // Required: path to PDB file of the protein receptor
// Demo: Aspirin SMILES for docking
params.smiles_string = 'CC(=O)OC1=CC=CC=C1C(=O)O'
params.local_output_dir = './diffdock_results'
params.gpu_device = '0'
params.use_gpu = 'True'

process RUN_DIFFDOCK_WITH_SMILES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("run_diffdock_with_smiles_results.json"), emit: results
    tuple val(meta), path("run_diffdock_with_smiles_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PDB_PATH="${params.pdb_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SMILES_STRING="${params.smiles_string?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LOCAL_OUTPUT_DIR="${params.local_output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GPU_DEVICE="${params.gpu_device?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_USE_GPU="${params.use_gpu?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
import subprocess
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



def run_diffdock_with_smiles(pdb_path, smiles_string, local_output_dir, gpu_device=0, use_gpu=True):
    try:
        summary = []

        # Check if PDB file exists
        if not os.path.exists(pdb_path):
            raise FileNotFoundError(f"The PDB file '{pdb_path}' does not exist.")
        summary.append(f"PDB file '{pdb_path}' found.")

        # Ensure the output directory exists
        if not os.path.exists(local_output_dir):
            os.makedirs(local_output_dir)
        summary.append(f"Output directory '{local_output_dir}' is ready.")

        # Pull the pre-built container from Docker Hub
        summary.append("Pulling DiffDock container from Docker Hub...")
        subprocess.run(["docker", "pull", "rbgcsail/diffdock"], check=True)
        summary.append("DiffDock container pulled successfully.")

        # Check for GPU availability (if using GPU)
        if use_gpu:
            summary.append("Checking for GPU availability...")
            gpu_check = subprocess.run(
                [
                    "docker",
                    "run",
                    "--rm",
                    "--gpus",
                    "all",
                    "nvidia/cuda:11.7.1-devel-ubuntu22.04",
                    "nvidia-smi",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            summary.append(f"GPU Status: {gpu_check.stdout.strip()}")

        # Prepare the GPU flag
        gpu_flag = ["--gpus", f"device={gpu_device}"] if use_gpu else []

        # Docker run command
        summary.append("Running DiffDock inference...")
        run_command = (
            ["docker", "run"]
            + gpu_flag
            + [
                # Mount the local directory to /home/appuser/output inside the container
                "-v",
                f"{os.path.abspath(pdb_path)}:/home/appuser/input/protein.pdb",  # PDB file mount
                "-v",
                f"{os.path.abspath(local_output_dir)}:/home/appuser/output",  # Output directory mount
                "--entrypoint",
                "/bin/bash",
                "rbgcsail/diffdock",
                "-c",
                # Command to run inference using micromamba environment
                f"micromamba run -n diffdock python -m inference --config default_inference_args.yaml "
                f"--protein_path /home/appuser/input/protein.pdb --ligand '{smiles_string}' --out_dir /home/appuser/output",
            ]
        )

        # Execute the Docker command
        result = subprocess.run(run_command, check=False, capture_output=True, text=True)

        # Check for errors
        if result.returncode != 0:
            summary.append(f"Error during inference: {result.stderr.strip()}")
            return "\\n".join(summary)
        else:
            summary.append("DiffDock inference completed successfully.")
            summary.append(f"Results stored in '{local_output_dir}'.")

        return "\\n".join(summary)

    except FileNotFoundError as e:
        return f"File error: {e}"
    except subprocess.CalledProcessError as e:
        return f"Command execution error: {e}"
    except Exception as e:
        return f"An error occurred: {e}"

# Execute the function
try:
    result = run_diffdock_with_smiles(
        pdb_path=auto_convert(os.environ.get("PARAM_PDB_PATH", "")),
        smiles_string=auto_convert(os.environ.get("PARAM_SMILES_STRING", "")),
        local_output_dir=auto_convert(os.environ.get("PARAM_LOCAL_OUTPUT_DIR", "")),
        gpu_device=auto_convert(os.environ.get("PARAM_GPU_DEVICE", "0")),
        use_gpu=auto_convert(os.environ.get("PARAM_USE_GPU", "True")),
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
    "function": "run_diffdock_with_smiles",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("run_diffdock_with_smiles_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("run_diffdock_with_smiles_output.txt", "w") as f:
    f.write("Biomni: Run Diffdock With Smiles" + NL)
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
        biomni_function: "run_diffdock_with_smiles"
    END_VERSIONS
    """
}

workflow RUN_DIFFDOCK_WITH_SMILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    RUN_DIFFDOCK_WITH_SMILES(ch_input)

    emit:
    results = RUN_DIFFDOCK_WITH_SMILES.out.results
    output = RUN_DIFFDOCK_WITH_SMILES.out.output
    versions = RUN_DIFFDOCK_WITH_SMILES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    RUN_DIFFDOCK_WITH_SMILES_WORKFLOW(ch_input)

    RUN_DIFFDOCK_WITH_SMILES_WORKFLOW.out.output.view { "Output: $it" }
}
