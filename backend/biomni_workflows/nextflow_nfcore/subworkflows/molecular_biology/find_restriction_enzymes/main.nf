#!/usr/bin/env nextflow
/*
 * molecular_biology/find_restriction_enzymes
 * Finds common restriction enzyme sites in a DNA sequence.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.is_circular = null

process FIND_RESTRICTION_ENZYMES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("find_restriction_enzymes_results.json"), emit: results
    tuple val(meta), path("find_restriction_enzymes_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_CIRCULAR="${params.is_circular?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from Bio import Restriction
from Bio.Seq import Seq
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



def find_restriction_enzymes(sequence: str, is_circular: bool = False) -> dict[str, list]:
    '''Finds common restriction enzyme sites in a DNA sequence.

    Args:
        sequence (str): DNA sequence to analyze
        is_circular (bool): Whether the sequence is circular (default: False)

    Returns:
        Dict[str, list]: Dictionary of enzymes and their cut positions

    '''
    # Convert to Bio.Seq and analyze
    seq = Seq(sequence.upper())
    analysis = Restriction.CommOnly.search(seq, linear=not is_circular)

    # Keep only enzymes that have sites
    sites = {str(enzyme): list(positions) for enzyme, positions in analysis.items() if positions}

    return {
        "explanation": (
            "Output fields:\\n"
            "- enzyme_sites: Dictionary where keys are enzyme names and values are:\\n"
            "  * List of cut positions in the sequence (0-based)\\n"
            "  * Empty list means enzyme has no recognition sites\\n"
            "  * Positions indicate where the enzyme's recognition sequence begins\\n"
            "  * For circular sequences, positions wrap around the sequence end"
        ),
        "enzyme_sites": sites,
    }

# Execute the function
try:
    result = find_restriction_enzymes(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        is_circular=auto_convert(os.environ.get("PARAM_IS_CIRCULAR", "")),
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
    "function": "find_restriction_enzymes",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("find_restriction_enzymes_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("find_restriction_enzymes_output.txt", "w") as f:
    f.write("Biomni: Find Restriction Enzymes" + NL)
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
        biomni_function: "find_restriction_enzymes"
    END_VERSIONS
    """
}

workflow FIND_RESTRICTION_ENZYMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIND_RESTRICTION_ENZYMES(ch_input)

    emit:
    results = FIND_RESTRICTION_ENZYMES.out.results
    output = FIND_RESTRICTION_ENZYMES.out.output
    versions = FIND_RESTRICTION_ENZYMES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIND_RESTRICTION_ENZYMES_WORKFLOW(ch_input)

    FIND_RESTRICTION_ENZYMES_WORKFLOW.out.output.view { "Output: $it" }
}
