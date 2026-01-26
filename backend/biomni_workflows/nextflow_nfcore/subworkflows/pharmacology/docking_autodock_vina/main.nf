#!/usr/bin/env nextflow
/*
 * pharmacology/docking_autodock_vina
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.smiles_list = null
params.receptor_pdb_file = null
params.box_center = null
params.box_size = null
params.ncpu = '1'

process DOCKING_AUTODOCK_VINA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("docking_autodock_vina_results.json"), emit: results
    tuple val(meta), path("docking_autodock_vina_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SMILES_LIST="${params.smiles_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RECEPTOR_PDB_FILE="${params.receptor_pdb_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BOX_CENTER="${params.box_center?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BOX_SIZE="${params.box_size?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NCPU="${params.ncpu?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def docking_autodock_vina(smiles_list, receptor_pdb_file, box_center, box_size, ncpu=1):
    from tdc import Oracle

    log = []

    # Log the start of the process
    log.append("Step 1: Initializing the Oracle")
    log.append(f"Receptor PDB File: {receptor_pdb_file}")
    log.append(f"Box Center: {box_center}")
    log.append(f"Box Size: {box_size}")

    # Initialize the Oracle object
    oracle = Oracle(
        name="pyscreener",
        receptor_pdb_file=receptor_pdb_file,
        box_center=box_center,
        box_size=box_size,
        ncpu=ncpu,
    )
    log.append("Oracle initialized successfully.")

    # Log the list of SMILES strings
    log.append(f"\\nStep 2: Processing SMILES strings: {smiles_list}")

    # Get the docking scores
    docking_scores = oracle(smiles_list)
    log.append(f"Docking scores calculated: {docking_scores}")

    # Create a dictionary mapping SMILES to their docking scores
    results_dict = dict(zip(smiles_list, docking_scores, strict=False))

    # Log the result mapping
    log.append("\\nStep 3: Mapping SMILES to docking scores:")
    log.append(f"Results: {results_dict}")

    # Convert the log to a string and return it
    research_log = "\\n".join(log)
    return research_log

# Execute the function
try:
    result = docking_autodock_vina(
        smiles_list=auto_convert(os.environ.get("PARAM_SMILES_LIST", "")),
        receptor_pdb_file=auto_convert(os.environ.get("PARAM_RECEPTOR_PDB_FILE", "")),
        box_center=auto_convert(os.environ.get("PARAM_BOX_CENTER", "")),
        box_size=auto_convert(os.environ.get("PARAM_BOX_SIZE", "")),
        ncpu=auto_convert(os.environ.get("PARAM_NCPU", "1")),
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
    "function": "docking_autodock_vina",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("docking_autodock_vina_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("docking_autodock_vina_output.txt", "w") as f:
    f.write("Biomni: Docking Autodock Vina" + NL)
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
        biomni_function: "docking_autodock_vina"
    END_VERSIONS
    """
}

workflow DOCKING_AUTODOCK_VINA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DOCKING_AUTODOCK_VINA(ch_input)

    emit:
    results = DOCKING_AUTODOCK_VINA.out.results
    output = DOCKING_AUTODOCK_VINA.out.output
    versions = DOCKING_AUTODOCK_VINA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DOCKING_AUTODOCK_VINA_WORKFLOW(ch_input)

    DOCKING_AUTODOCK_VINA_WORKFLOW.out.output.view { "Output: $it" }
}
