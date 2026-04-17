#!/usr/bin/env nextflow
/*
 * synthetic_biology/hamming_distance
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Two DNA barcodes with 3 differences
params.seq1 = 'ATCGATCGATCG'
params.seq2 = 'ATCGTTCGTTCG'

process HAMMING_DISTANCE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("hamming_distance_results.json"), emit: results
    tuple val(meta), path("hamming_distance_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_SEQ1="${params.seq1?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEQ2="${params.seq2?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def hamming_distance(seq1, seq2):
    '''Count positions where sequences differ.
    Args: seq1, seq2: sequences of equal length
    '''
    # Validate inputs - use defaults if None
    if seq1 is None:
        seq1 = "ATCGATCG"
    if seq2 is None:
        seq2 = "ATCGATCG"
    seq1 = str(seq1)
    seq2 = str(seq2)

    if len(seq1) != len(seq2):
        return {"error": "Sequences must be same length", "distance": -1}
    distance = sum(c1 != c2 for c1, c2 in zip(seq1, seq2))
    return {"distance": distance, "length": len(seq1), "identity": 1 - distance/len(seq1)}

# Execute the function
try:
    result = hamming_distance(
        seq1=auto_convert(os.environ.get("PARAM_SEQ1", "")),
        seq2=auto_convert(os.environ.get("PARAM_SEQ2", "")),
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
    "function": "hamming_distance",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("hamming_distance_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("hamming_distance_output.txt", "w") as f:
    f.write("Biomni: Hamming Distance" + NL)
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
        biomni_function: "hamming_distance"
    END_VERSIONS
    """
}

workflow HAMMING_DISTANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    HAMMING_DISTANCE(ch_input)

    emit:
    results = HAMMING_DISTANCE.out.results
    output = HAMMING_DISTANCE.out.output
    versions = HAMMING_DISTANCE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    HAMMING_DISTANCE_WORKFLOW(ch_input)

    HAMMING_DISTANCE_WORKFLOW.out.output.view { "Output: $it" }
}
