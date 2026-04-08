#!/usr/bin/env nextflow
/*
 * molecular_biology/get_golden_gate_assembly_protocol
 * Return a customized protocol for Golden Gate assembly based on the number of inserts
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Golden Gate assembly protocol for single insert
params.num_inserts = 1
params.enzyme_name = 'BsaI'
params.vector_length = 3000
params.vector_amount_ng = 75.0
params.insert_lengths = '[500]'
params.is_library_prep = 'false'

process GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_golden_gate_assembly_protocol_results.json"), emit: results
    tuple val(meta), path("get_golden_gate_assembly_protocol_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_NUM_INSERTS="${params.num_inserts?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_NAME="${params.enzyme_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_VECTOR_LENGTH="${params.vector_length?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_VECTOR_AMOUNT_NG="${params.vector_amount_ng?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INSERT_LENGTHS="${params.insert_lengths?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_LIBRARY_PREP="${params.is_library_prep?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def get_golden_gate_assembly_protocol(
    num_inserts: int = 1,
    enzyme_name: str = None,
    vector_length: int = None,
    vector_amount_ng: float = 75.0,
    insert_lengths: list[int] = None,
    is_library_prep: bool = False,
) -> dict[str, Any]:
    '''Return a customized protocol for Golden Gate assembly based on the number of inserts
    and specific DNA sequences.

    Args:
        num_inserts (int): Number of inserts to be assembled (default: 1)
        enzyme_name (str): Type IIS restriction enzyme to be used
        vector_length (int): Length of the destination vector in bp
        vector_amount_ng (float): Amount of vector to use in ng (default: 75.0)
        insert_lengths (List[int]): List of insert lengths in bp (optional)
        is_library_prep (bool): Whether this is for library preparation (default: False)

    Returns:
        Dict: Dictionary containing detailed protocol steps for Golden Gate assembly

    '''
    # Validate required parameters
    if vector_length is None:
        raise ValueError("vector_length is required and must be a positive integer (bp)")
    if enzyme_name is None:
        raise ValueError("enzyme_name is required")

    # Validate enzyme name
    supported_enzymes = ["BsaI", "BsmBI", "BbsI", "Esp3I", "BtgZI", "SapI"]
    if enzyme_name not in supported_enzymes:
        raise ValueError(f"Unsupported enzyme: {enzyme_name}. Currently supporting: {', '.join(supported_enzymes)}")

    # Determine which protocol to use based on number of inserts
    if num_inserts == 1:
        if is_library_prep:
            thermal_protocol = [
                {
                    "temperature": "37°C",
                    "time": "1 hour",
                    "description": "Cleavage and ligation",
                }
            ]
        else:
            thermal_protocol = [
                {
                    "temperature": "37°C",
                    "time": "5 minutes",
                    "description": "Cleavage and ligation",
                }
            ]
        thermal_protocol.append(
            {
                "temperature": "60°C",
                "time": "5 minutes",
                "description": "Enzyme inactivation",
            }
        )
    elif 2 <= num_inserts <= 10:
        thermal_protocol = [
            {
                "temperature": "Cycle (30x)",
                "description": "Cleavage and ligation cycles",
                "cycles": [
                    {
                        "temperature": "37°C",
                        "time": "1 minute",
                        "description": "Restriction digestion",
                    },
                    {
                        "temperature": "16°C",
                        "time": "1 minute",
                        "description": "Ligation",
                    },
                ],
            },
            {
                "temperature": "60°C",
                "time": "5 minutes",
                "description": "Enzyme inactivation",
            },
        ]
    else:  # 11+ inserts
        thermal_protocol = [
            {
                "temperature": "Cycle (30x)",
                "description": "Cleavage and ligation cycles",
                "cycles": [
                    {
                        "temperature": "37°C",
                        "time": "5 minutes",
                        "description": "Restriction digestion",
                    },
                    {
                        "temperature": "16°C",
                        "time": "5 minutes",
                        "description": "Ligation",
                    },
                ],
            },
            {
                "temperature": "60°C",
                "time": "5 minutes",
                "description": "Enzyme inactivation",
            },
        ]

    # Determine NEB Golden Gate Assembly Mix amount
    assembly_mix_volume = "2 μl" if num_inserts > 10 else "1 μl"

    # Calculate molar amounts
    # Formula: pmol = (weight in ng) / (base pairs × 650 g/mol per bp) × 10^6
    vector_pmol = vector_amount_ng / (vector_length * 650) * 1000000

    # Calculate insert amounts
    insert_components = []

    # If lengths are provided, use them for calculations
    if insert_lengths:
        for i, length in enumerate(insert_lengths):
            # Calculate for 2:1 molar ratio (insert:vector)
            insert_pmol = 2 * vector_pmol
            insert_ng = (insert_pmol * length * 650) / 1000000

            insert_components.append(
                {
                    "name": f"Insert {i + 1} ({length} bp)",
                    "amount": f"{insert_ng:.1f} ng ({insert_pmol:.3f} pmol)",
                    "molar_ratio": "2:1 (insert:vector)",
                }
            )
    else:
        # Generic insert information when no lengths provided
        insert_components = [
            {
                "name": "Insert DNA (precloned or amplicon)",
                "amount": "Variable based on length and concentration",
                "note": "Use 2:1 molar ratio (insert:vector) for optimal assembly",
            }
        ]

    # Create component list for the protocol
    reaction_components = [
        {
            "name": f"Destination Vector ({vector_length} bp)",
            "amount": f"{vector_amount_ng} ng ({vector_pmol:.3f} pmol)",
        }
    ]

    # Add insert components
    for component in insert_components:
        reaction_components.append(component)

    # Add remaining reagents
    reaction_components.extend(
        [
            {"name": "T4 DNA Ligase Buffer (10X)", "volume": "2 μl"},
            {
                "name": f"NEB Golden Gate Assembly Mix ({enzyme_name})",
                "volume": assembly_mix_volume,
            },
            {"name": "Nuclease-free H₂O", "volume": "to 20 μl"},
        ]
    )

    protocol = {
        "title": f"Golden Gate Assembly Protocol ({enzyme_name})",
        "description": f"Customized protocol for Golden Gate assembly with {enzyme_name} and {num_inserts} insert(s)",
        "steps": [
            {
                "step_number": 1,
                "title": "Prepare assembly reaction",
                "description": "Mix the following components in a PCR tube:",
                "components": reaction_components,
                "total_volume": "20 μl",
            },
            {
                "step_number": 2,
                "title": "Run assembly reaction",
                "description": "Run the following program on a thermocycler:",
                "program": thermal_protocol,
            },
        ],
        "notes": [
            f"Destination vector must possess {enzyme_name} restriction sites in the proper orientation",
            f"Inserts must possess {enzyme_name} restriction sites at both ends in the proper orientation",
            "For amplicon inserts, add 5′ flanking bases (6 recommended) before the restriction sites",
            f"Vector amount: {vector_amount_ng} ng = {vector_pmol:.3f} pmol",
            "Insert:vector molar ratio is 2:1 for optimal assembly efficiency",
        ],
    }

    return protocol

# Execute the function
try:
    result = get_golden_gate_assembly_protocol(
        num_inserts=auto_convert(os.environ.get("PARAM_NUM_INSERTS", "1")),
        enzyme_name=auto_convert(os.environ.get("PARAM_ENZYME_NAME", "")),
        vector_length=auto_convert(os.environ.get("PARAM_VECTOR_LENGTH", "")),
        vector_amount_ng=auto_convert(os.environ.get("PARAM_VECTOR_AMOUNT_NG", "75.0")),
        insert_lengths=auto_convert(os.environ.get("PARAM_INSERT_LENGTHS", "")),
        is_library_prep=auto_convert(os.environ.get("PARAM_IS_LIBRARY_PREP", "")),
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
    "function": "get_golden_gate_assembly_protocol",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_golden_gate_assembly_protocol_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_golden_gate_assembly_protocol_output.txt", "w") as f:
    f.write("Biomni: Get Golden Gate Assembly Protocol" + NL)
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
        biomni_function: "get_golden_gate_assembly_protocol"
    END_VERSIONS
    """
}

workflow GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL(ch_input)

    emit:
    results = GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL.out.results
    output = GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL.out.output
    versions = GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL_WORKFLOW(ch_input)

    GET_GOLDEN_GATE_ASSEMBLY_PROTOCOL_WORKFLOW.out.output.view { "Output: $it" }
}
