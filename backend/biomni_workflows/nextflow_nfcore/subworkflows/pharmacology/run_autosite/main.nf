#!/usr/bin/env nextflow
/*
 * pharmacology/run_autosite
 * Run AutoSite to identify binding sites on a protein receptor.
 * AutoSite detects pockets and cavities on protein surfaces for molecular docking.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pdb_file = null
params.output_dir = './autosite_results'
params.spacing = '1.0'

process RUN_AUTOSITE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("run_autosite_results.json"), emit: results
    tuple val(meta), path("run_autosite_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    export PARAM_PDB_FILE="${params.pdb_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: './autosite_results'}"
    export PARAM_SPACING="${params.spacing?.toString()?.replace('"', '\\"') ?: '1.0'}"

    python3 << 'PYEOF'
import os
import json
import subprocess
import re

def auto_convert(val):
    if val is None or val == '' or val == 'null':
        return None
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    try:
        return float(val)
    except ValueError:
        pass
    return val


def run_autosite(pdb_file, output_dir='./autosite_results', spacing=1.0):
    '''Run AutoSite to identify binding sites on a protein receptor.

    Parameters
    ----------
    pdb_file : str
        Path to PDB file of the protein receptor
    output_dir : str
        Directory to save output files (default: ./autosite_results)
    spacing : float
        Grid spacing in Angstroms (default: 1.0)

    Returns
    -------
    str
        Research log detailing the binding site identification
    '''
    os.makedirs(output_dir or './autosite_results', exist_ok=True)
    output_dir = output_dir or './autosite_results'

    research_log = f"AutoSite Binding Site Identification\\n"
    research_log += "=" * 60 + "\\n\\n"
    research_log += f"Parameters:\\n"
    research_log += f"- PDB file: {pdb_file}\\n"
    research_log += f"- Output directory: {output_dir}\\n"
    research_log += f"- Grid spacing: {spacing} Angstroms\\n\\n"

    # Check if PDB file exists
    if pdb_file is None or not os.path.exists(str(pdb_file)):
        research_log += "Note: PDB file not provided or not found.\\n"
        research_log += "Running in demo mode with simulated results.\\n\\n"
        research_log += "## Demo Binding Site Results\\n"
        research_log += "In production, AutoSite would:\\n"
        research_log += "1. Convert PDB to PDBQT format using prepare_receptor\\n"
        research_log += "2. Run AutoSite grid-based pocket detection\\n"
        research_log += "3. Identify binding pockets ranked by volume and buriedness\\n\\n"
        research_log += "Example binding site (simulated):\\n"
        research_log += "- Pocket 1: Center (12.5, 34.2, 8.7), Volume: 245.3 A^3\\n"
        research_log += "- Pocket 2: Center (5.1, 22.8, 15.3), Volume: 178.6 A^3\\n"
        return research_log

    # Try to run AutoSite
    try:
        pdbqt_file = pdb_file.replace(".pdb", ".pdbqt")
        subprocess.run(["prepare_receptor", "-r", pdb_file, "-o", pdbqt_file], check=True, capture_output=True)
        research_log += "Converted PDB to PDBQT format.\\n"

        autosite_cmd = ["autosite", "-r", pdbqt_file, "--spacing", str(spacing), "-o", output_dir]
        subprocess.run(autosite_cmd, check=True, capture_output=True)
        research_log += "AutoSite completed successfully.\\n\\n"

        log_path = os.path.join(output_dir, "_AutoSiteSummary.log")
        if os.path.exists(log_path):
            with open(log_path) as log_file:
                log_content = log_file.read()
            box_center_match = re.search(r"Box center:\\s*\\(([^)]+)\\)", log_content)
            box_size_match = re.search(r"Box size:\\s*\\(([^)]+)\\)", log_content)
            if box_center_match:
                research_log += f"Box Center: {box_center_match.group(1)}\\n"
            if box_size_match:
                research_log += f"Box Size: {box_size_match.group(1)}\\n"
    except FileNotFoundError:
        research_log += "AutoSite/ADFR suite not installed. Requires biomate/biomni-docking Docker image.\\n"
        research_log += "Install ADFR suite from: https://ccsb.scripps.edu/adfr/downloads/\\n"
    except subprocess.CalledProcessError as e:
        research_log += f"AutoSite execution error: {e}\\n"

    return research_log


try:
    result = run_autosite(
        pdb_file=auto_convert(os.environ.get("PARAM_PDB_FILE", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./autosite_results")),
        spacing=auto_convert(os.environ.get("PARAM_SPACING", "1.0")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

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

NL = chr(10)
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
    ch_input

    main:
    RUN_AUTOSITE(ch_input)

    emit:
    results = RUN_AUTOSITE.out.results
    output = RUN_AUTOSITE.out.output
    versions = RUN_AUTOSITE.out.versions
}

workflow {
    ch_input = Channel.of([id: 'run'])
    RUN_AUTOSITE_WORKFLOW(ch_input)
    RUN_AUTOSITE_WORKFLOW.out.output.view { "Output: $it" }
}
