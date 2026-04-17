#!/usr/bin/env nextflow
/*
 * molecular_biology/get_bacterial_transformation_protocol
 * Return a standard protocol for bacterial transformation.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Bacterial transformation protocol for standard plasmid
params.antibiotic = 'ampicillin'
params.is_repetitive = 'false'

process GET_BACTERIAL_TRANSFORMATION_PROTOCOL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_bacterial_transformation_protocol_results.json"), emit: results
    tuple val(meta), path("get_bacterial_transformation_protocol_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ANTIBIOTIC="${params.antibiotic?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_REPETITIVE="${params.is_repetitive?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from typing import Any
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



def get_bacterial_transformation_protocol(
    antibiotic: str = "ampicillin", is_repetitive: bool = False
) -> dict[str, Any]:
    '''Return a standard protocol for bacterial transformation.

    Args:
        antibiotic (str): Selection antibiotic (default: "ampicillin")
        is_repetitive (bool): Whether the sequence contains repetitive elements (default: False)

    Returns:
        Dict: Dictionary containing detailed protocol steps for bacterial transformation

    '''
    # Set incubation temperature based on whether sequence is repetitive
    incubation_temp = "30°C" if is_repetitive else "37°C"

    protocol = {
        "title": "Bacterial Transformation Protocol",
        "description": "Standard protocol for transforming DNA into competent E. coli cells",
        "steps": [
            {
                "step_number": 1,
                "title": "Add DNA to competent cells",
                "description": "Add 5 μl of DNA to 50 μl of competent E. coli cells",
                "note": "Keep cells on ice during this step and handle gently",
            },
            {
                "step_number": 2,
                "title": "Ice incubation",
                "description": "Incubate on ice for 30 minutes",
                "note": "This allows DNA to associate with the cell membrane",
            },
            {
                "step_number": 3,
                "title": "Heat shock",
                "description": "Heat shock at 42°C for 45 seconds",
                "note": "Precise timing is critical",
            },
            {
                "step_number": 4,
                "title": "Recovery on ice",
                "description": "Return to ice for 2 minutes",
                "note": "This step helps cells recover from heat shock",
            },
            {
                "step_number": 5,
                "title": "Add recovery medium",
                "description": "Add 950 μl of SOC medium",
                "note": "SOC is preferred, but LB can be used if necessary",
            },
            {
                "step_number": 6,
                "title": "Recovery incubation",
                "description": f"Incubate at {incubation_temp} for 1 hour with shaking (200-250 rpm)",
                "note": "This allows expression of antibiotic resistance genes",
            },
            {
                "step_number": 7,
                "title": "Plate on selective media",
                "description": f"Plate 100 μl on LB agar plates containing 100 μg/ml {antibiotic}",
                "note": "Spread thoroughly using sterile glass beads or a spreader",
            },
            {
                "step_number": 8,
                "title": "Incubate plates",
                "description": f"Incubate overnight (16-18 hours) at {incubation_temp}",
                "note": "Invert plates to prevent condensation from dripping onto colonies",
            },
        ],
        "notes": [
            "Always include positive and negative controls for transformation",
            f"For repetitive sequences, the lower temperature ({incubation_temp}) helps maintain sequence integrity"
            if is_repetitive
            else "Standard incubation at 37°C works well for most plasmids",
            f"Use fresh plates containing {antibiotic} for best results",
        ],
    }

    return protocol

# Execute the function
try:
    result = get_bacterial_transformation_protocol(
        antibiotic=auto_convert(os.environ.get("PARAM_ANTIBIOTIC", "ampicillin")),
        is_repetitive=auto_convert(os.environ.get("PARAM_IS_REPETITIVE", "")),
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
    "function": "get_bacterial_transformation_protocol",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_bacterial_transformation_protocol_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_bacterial_transformation_protocol_output.txt", "w") as f:
    f.write("Biomni: Get Bacterial Transformation Protocol" + NL)
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
        biomni_function: "get_bacterial_transformation_protocol"
    END_VERSIONS
    """
}

workflow GET_BACTERIAL_TRANSFORMATION_PROTOCOL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_BACTERIAL_TRANSFORMATION_PROTOCOL(ch_input)

    emit:
    results = GET_BACTERIAL_TRANSFORMATION_PROTOCOL.out.results
    output = GET_BACTERIAL_TRANSFORMATION_PROTOCOL.out.output
    versions = GET_BACTERIAL_TRANSFORMATION_PROTOCOL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_BACTERIAL_TRANSFORMATION_PROTOCOL_WORKFLOW(ch_input)

    GET_BACTERIAL_TRANSFORMATION_PROTOCOL_WORKFLOW.out.output.view { "Output: $it" }
}
