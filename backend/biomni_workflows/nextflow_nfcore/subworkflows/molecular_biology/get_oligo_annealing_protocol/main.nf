#!/usr/bin/env nextflow
/*
 * molecular_biology/get_oligo_annealing_protocol
 * Return a standard protocol for annealing oligonucleotides without phosphorylation.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// No value parameters

process GET_OLIGO_ANNEALING_PROTOCOL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_oligo_annealing_protocol_results.json"), emit: results
    tuple val(meta), path("get_oligo_annealing_protocol_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    # No value parameters

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



def get_oligo_annealing_protocol() -> dict[str, Any]:
    '''Return a standard protocol for annealing oligonucleotides without phosphorylation.

    Returns:
        Dict: Dictionary containing detailed protocol steps for oligo annealing

    '''
    protocol = {
        "title": "Oligo Annealing Protocol",
        "description": "Standard protocol for annealing complementary oligonucleotides",
        "steps": [
            {
                "step_number": 1,
                "title": "Prepare annealing reaction",
                "description": "Mix the following components in a PCR tube:",
                "components": [
                    {"name": "Forward oligo (100 μM)", "volume": "1 μl"},
                    {"name": "Reverse oligo (100 μM)", "volume": "1 μl"},
                    {"name": "Nuclease-free water", "volume": "8 μl"},
                ],
                "total_volume": "10 μl",
            },
            {
                "step_number": 2,
                "title": "Anneal in thermocycler",
                "description": "Run the following program on a thermocycler:",
                "program": [
                    {
                        "temperature": "95°C",
                        "time": "5 minutes",
                        "description": "Initial denaturation",
                    },
                    {
                        "temperature": "Ramp down to 25°C",
                        "rate": "5°C/minute",
                        "description": "Slow cooling for proper annealing",
                    },
                ],
            },
            {
                "step_number": 3,
                "title": "Dilute annealed oligos",
                "description": "Dilute the annealed oligos 1:200 in nuclease-free water",
                "details": "Add 1 μl of annealed oligos to 199 μl of nuclease-free water",
            },
        ],
        "notes": [
            "Store annealed and diluted oligos at -20°C for long-term storage",
            "Diluted oligos can be used directly in ligation reactions",
        ],
    }

    return protocol

# Execute the function
try:
    result = get_oligo_annealing_protocol(

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
    "function": "get_oligo_annealing_protocol",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_oligo_annealing_protocol_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_oligo_annealing_protocol_output.txt", "w") as f:
    f.write("Biomni: Get Oligo Annealing Protocol" + NL)
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
        biomni_function: "get_oligo_annealing_protocol"
    END_VERSIONS
    """
}

workflow GET_OLIGO_ANNEALING_PROTOCOL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_OLIGO_ANNEALING_PROTOCOL(ch_input)

    emit:
    results = GET_OLIGO_ANNEALING_PROTOCOL.out.results
    output = GET_OLIGO_ANNEALING_PROTOCOL.out.output
    versions = GET_OLIGO_ANNEALING_PROTOCOL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_OLIGO_ANNEALING_PROTOCOL_WORKFLOW(ch_input)

    GET_OLIGO_ANNEALING_PROTOCOL_WORKFLOW.out.output.view { "Output: $it" }
}
