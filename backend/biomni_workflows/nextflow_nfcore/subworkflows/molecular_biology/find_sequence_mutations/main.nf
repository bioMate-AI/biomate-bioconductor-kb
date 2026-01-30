#!/usr/bin/env nextflow
/*
 * molecular_biology/find_sequence_mutations
 * Compare query sequence against reference sequence to identify mutations.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Detect mutations between query and reference sequences
params.query_sequence = 'ATGGTGAGCAAGGGCGAGGAGCTGTTCACCGGGGTGGTGCCCATCCTGGTCGAGCTGGACGGC'
params.reference_sequence = 'ATGGTGAGCAAGGGCGAGGAGCTGTTCACCGGGGTGGTGCCCATCCTGGTCGAGCTGGATGGC'
params.query_start = '1'

process FIND_SEQUENCE_MUTATIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("find_sequence_mutations_results.json"), emit: results
    tuple val(meta), path("find_sequence_mutations_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_QUERY_SEQUENCE="${params.query_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REFERENCE_SEQUENCE="${params.reference_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_QUERY_START="${params.query_start?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def find_sequence_mutations(query_sequence, reference_sequence, query_start=1):
    '''Compare query sequence against reference sequence to identify mutations.

    Args:
        query_sequence (str): The sequence being analyzed
        reference_sequence (str): The reference sequence to compare against
        query_start (int): The start position of the query sequence

    Returns:
        list: List of mutations in format RefAA_Position_QueryAA

    Example:
        If query_sequence = "ACGT" and reference_sequence = "AGGT",
        the output would be ["A1C", "G2T"] indicating mutations at positions 1 and 2.

    '''
    if not all([query_sequence, reference_sequence, query_start]):
        return {
            "explanation": (
                "Output fields:\\n"
                "- mutations: List of mutations found, where each mutation is formatted as:\\n"
                "  * RefAA_Position_QueryAA\\n"
                "  * RefAA: Original amino acid/base in reference sequence\\n"
                "  * Position: Position where mutation occurs (1-based)\\n"
                "  * QueryAA: New amino acid/base in query sequence\\n"
                "  * Example: 'A123T' means position 123 changed from A to T\\n"
                "- success: Boolean indicating if comparison was successful"
            ),
            "mutations": [],
            "success": False,
        }

    mutations = []
    for i, (query_aa, ref_aa) in enumerate(zip(query_sequence, reference_sequence, strict=False)):
        if ref_aa not in (query_aa, "-") and query_aa != "-":  # Ignore gaps
            position = query_start + i
            mutations.append(f"{ref_aa}{position}{query_aa}")

    return {
        "explanation": (
            "Output fields:\\n"
            "- mutations: List of mutations found, where each mutation is formatted as:\\n"
            "  * RefAA_Position_QueryAA\\n"
            "  * RefAA: Original amino acid/base in reference sequence\\n"
            "  * Position: Position where mutation occurs (1-based)\\n"
            "  * QueryAA: New amino acid/base in query sequence\\n"
            "  * Example: 'A123T' means position 123 changed from A to T\\n"
            "- success: Boolean indicating if comparison was successful"
        ),
        "mutations": mutations,
        "success": True,
    }

# Execute the function
try:
    result = find_sequence_mutations(
        query_sequence=auto_convert(os.environ.get("PARAM_QUERY_SEQUENCE", "")),
        reference_sequence=auto_convert(os.environ.get("PARAM_REFERENCE_SEQUENCE", "")),
        query_start=auto_convert(os.environ.get("PARAM_QUERY_START", "1")),
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
    "function": "find_sequence_mutations",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("find_sequence_mutations_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("find_sequence_mutations_output.txt", "w") as f:
    f.write("Biomni: Find Sequence Mutations" + NL)
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
        biomni_function: "find_sequence_mutations"
    END_VERSIONS
    """
}

workflow FIND_SEQUENCE_MUTATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIND_SEQUENCE_MUTATIONS(ch_input)

    emit:
    results = FIND_SEQUENCE_MUTATIONS.out.results
    output = FIND_SEQUENCE_MUTATIONS.out.output
    versions = FIND_SEQUENCE_MUTATIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIND_SEQUENCE_MUTATIONS_WORKFLOW(ch_input)

    FIND_SEQUENCE_MUTATIONS_WORKFLOW.out.output.view { "Output: $it" }
}
