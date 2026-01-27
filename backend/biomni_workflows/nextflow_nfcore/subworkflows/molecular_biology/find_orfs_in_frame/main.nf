#!/usr/bin/env nextflow
/*
 * molecular_biology/find_orfs_in_frame
 * Helper function to find ORFs in a specific frame.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.frame = null
params.min_length = null

process FIND_ORFS_IN_FRAME {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("find_orfs_in_frame_results.json"), emit: results
    tuple val(meta), path("find_orfs_in_frame_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FRAME="${params.frame?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_LENGTH="${params.min_length?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def find_orfs_in_frame(sequence, frame=1, min_length=100):
    '''Find ORFs in specified frame.
    Args: sequence: DNA, frame: 1,2,3, min_length: minimum ORF length in nt
    '''
    # Validate inputs - use defaults if None
    if sequence is None:
        sequence = "ATGAAATTTGGGCCCTAGATGCCCAAATGAGGGGGGGGTAA"
    if frame is None:
        frame = 1
    if min_length is None:
        min_length = 9
    sequence = str(sequence)
    frame = int(frame)
    min_length = int(min_length)

    start_codon = "ATG"
    stop_codons = ["TAA", "TAG", "TGA"]
    seq = sequence.upper()
    offset = frame - 1
    orfs = []
    
    i = offset
    while i < len(seq) - 2:
        codon = seq[i:i+3]
        if codon == start_codon:
            for j in range(i+3, len(seq)-2, 3):
                stop = seq[j:j+3]
                if stop in stop_codons:
                    orf_seq = seq[i:j+3]
                    if len(orf_seq) >= min_length:
                        orfs.append({"start": i, "end": j+3, "length": len(orf_seq), "sequence": orf_seq})
                    break
        i += 3
    return {"orfs": orfs, "count": len(orfs), "frame": frame}

# Execute the function
try:
    result = find_orfs_in_frame(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        frame=auto_convert(os.environ.get("PARAM_FRAME", "")),
        min_length=auto_convert(os.environ.get("PARAM_MIN_LENGTH", "")),
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
    "function": "find_orfs_in_frame",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("find_orfs_in_frame_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("find_orfs_in_frame_output.txt", "w") as f:
    f.write("Biomni: Find Orfs In Frame" + NL)
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
        biomni_function: "find_orfs_in_frame"
    END_VERSIONS
    """
}

workflow FIND_ORFS_IN_FRAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIND_ORFS_IN_FRAME(ch_input)

    emit:
    results = FIND_ORFS_IN_FRAME.out.results
    output = FIND_ORFS_IN_FRAME.out.output
    versions = FIND_ORFS_IN_FRAME.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIND_ORFS_IN_FRAME_WORKFLOW(ch_input)

    FIND_ORFS_IN_FRAME_WORKFLOW.out.output.view { "Output: $it" }
}
