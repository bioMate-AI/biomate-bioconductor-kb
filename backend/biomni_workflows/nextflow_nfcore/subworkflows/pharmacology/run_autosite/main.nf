#!/usr/bin/env nextflow
/*
 * pharmacology/run_autosite
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pdb_file = null
params.output_dir = null
params.spacing = '1.0'

process RUN_AUTOSITE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("run_autosite_results.json"), emit: results
    tuple val(meta), path("run_autosite_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PDB_FILE="${params.pdb_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SPACING="${params.spacing?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import re
import subprocess
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



def run_autosite(pdb_file, output_dir, spacing=1.0):
    # Prepare the output directory
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Convert the PDB file to PDBQT format (assuming prepare_receptor4.py is accessible)
    pdbqt_file = pdb_file.replace(".pdb", ".pdbqt")
    subprocess.run(["prepare_receptor", "-r", pdb_file, "-o", pdbqt_file], check=True)

    # Run AutoSite
    autosite_cmd = [
        "autosite",
        "-r",
        pdbqt_file,
        "--spacing",
        str(spacing),
        "-o",
        output_dir,
    ]
    subprocess.run(autosite_cmd, check=True)

    # Parse the results to find the box center and size
    box_center, box_size = None, None
    log_path = os.path.join(output_dir, "_AutoSiteSummary.log")
    with open(log_path) as log_file:
        log_content = log_file.read()

        # Extract box center and size from the log (assuming standard output format)
        box_center_match = re.search(r"Box center:\s*\(([^)]+)\)", log_content)
        box_size_match = re.search(r"Box size:\s*\(([^)]+)\)", log_content)

        if box_center_match:
            box_center = box_center_match.group(1)
        if box_size_match:
            box_size = box_size_match.group(1)

    # Create a research log string
    research_log = f"AutoSite run for {pdb_file} with spacing {spacing}\\n"
    research_log += f"Output directory: {output_dir}\\n"
    if box_center and box_size:
        research_log += f"Box Center: {box_center}\\nBox Size: {box_size}"
    else:
        research_log += "Box Center and Size information not found in log."

    return research_log

# Execute the function
try:
    result = run_autosite(
        pdb_file=auto_convert(os.environ.get("PARAM_PDB_FILE", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        spacing=auto_convert(os.environ.get("PARAM_SPACING", "1.0")),
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
    "function": "run_autosite",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("run_autosite_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("run_autosite_output.txt", "w") as f:
    f.write("Biomni: Run Autosite" + NL)
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
        biomni_function: "run_autosite"
    END_VERSIONS
    """
}

workflow RUN_AUTOSITE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    RUN_AUTOSITE(ch_input)

    emit:
    results = RUN_AUTOSITE.out.results
    output = RUN_AUTOSITE.out.output
    versions = RUN_AUTOSITE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    RUN_AUTOSITE_WORKFLOW(ch_input)

    RUN_AUTOSITE_WORKFLOW.out.output.view { "Output: $it" }
}
