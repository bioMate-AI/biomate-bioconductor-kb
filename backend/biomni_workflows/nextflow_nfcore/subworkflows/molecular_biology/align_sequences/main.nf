#!/usr/bin/env nextflow
/*
 * molecular_biology/align_sequences
 * Align short sequences (primers) to a longer sequence, allowing for one mismatch.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Align primers to a target sequence
params.long_seq = 'ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGCTATGCAGAAAATCTTAGAGTGTCCCATCTGTCTGGAGTTGATCAAGGAACCTGTCTCCACAAAGTGTGACCACATATTTTGCAAATTTTGCATGCTGAAACTTCTCAACCAGAAGAAAGGGCCTTCACAGTGTCCTTTATGTAAGAATGATATAACCAAAAG'
params.short_seqs = '["ATGGATTTATCTGCT", "GTCTCCACAAAGTGT", "CTTTTGGTTATAT"]'

process ALIGN_SEQUENCES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("align_sequences_results.json"), emit: results
    tuple val(meta), path("align_sequences_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_LONG_SEQ="${params.long_seq?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SHORT_SEQS="${params.short_seqs?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def align_sequences(long_seq: str, short_seqs: str | list[str]) -> list[dict]:
    '''Align short sequences (primers) to a longer sequence, allowing for one mismatch.
    Checks both forward and reverse complement strands.

    Args:
        long_seq (str): Target DNA sequence
        short_seqs (Union[str, List[str]]): Single primer or list of primers

    Returns:
        List[Dict]: List of alignment results for each short sequence, including:
            - explanation: Explanation of the output fields
            - sequence: the short sequence that was aligned
            - alignments: list of dictionaries containing:
                - position: 0-based start position in the target sequence
                - strand: '+' for forward strand, '-' for reverse complement
                - mismatches: list of tuples (position, expected_base, found_base)
                  for any mismatches

    '''
    # Standardize input
    long_seq = long_seq.upper()
    short_seqs = [short_seqs.upper()] if isinstance(short_seqs, str) else [seq.upper() for seq in short_seqs]

    def reverse_complement(seq):
        '''Helper function to get reverse complement of a sequence.'''
        complement = {"A": "T", "T": "A", "C": "G", "G": "C"}
        return "".join(complement.get(base, base) for base in reversed(seq))

    results = []

    for short_seq in short_seqs:
        alignments = []
        seq_len = len(short_seq)

        # Check both forward and reverse complement orientations
        sequences_to_check = [
            (short_seq, "+"),  # Forward strand
            (reverse_complement(short_seq), "-"),  # Reverse complement
        ]

        for seq_to_align, strand in sequences_to_check:
            # Check each possible position in the long sequence
            for i in range(len(long_seq) - seq_len + 1):
                window = long_seq[i : i + seq_len]
                mismatches = []

                # Compare sequences base by base
                for j in range(seq_len):
                    if window[j] != seq_to_align[j]:
                        mismatches.append((j, seq_to_align[j], window[j]))

                # If we have 0 or 1 mismatches, record the alignment
                if len(mismatches) <= 1:
                    alignments.append({"position": i, "strand": strand, "mismatches": mismatches})

        results.append({"sequence": short_seq, "alignments": alignments})

    return {
        "explanation": (
            "Output fields:\\n"
            "- sequences: List of alignment results, where each contains:\\n"
            "  * sequence: The short sequence that was aligned\\n"
            "  * alignments: List of all alignment positions found, where each contains:\\n"
            "    - position: 0-based start position in the target sequence\\n"
            "    - strand: '+' for forward strand, '-' for reverse complement\\n"
            "    - mismatches: List of mismatches, each containing:\\n"
            "      * position: Position in the short sequence where mismatch occurs\\n"
            "      * expected: Base expected from short sequence\\n"
            "      * found: Base found in target sequence"
        ),
        "sequences": results,
    }

# Execute the function
try:
    result = align_sequences(
        long_seq=auto_convert(os.environ.get("PARAM_LONG_SEQ", "")),
        short_seqs=auto_convert(os.environ.get("PARAM_SHORT_SEQS", "")),
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
    "function": "align_sequences",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("align_sequences_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("align_sequences_output.txt", "w") as f:
    f.write("Biomni: Align Sequences" + NL)
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
        biomni_function: "align_sequences"
    END_VERSIONS
    """
}

workflow ALIGN_SEQUENCES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ALIGN_SEQUENCES(ch_input)

    emit:
    results = ALIGN_SEQUENCES.out.results
    output = ALIGN_SEQUENCES.out.output
    versions = ALIGN_SEQUENCES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ALIGN_SEQUENCES_WORKFLOW(ch_input)

    ALIGN_SEQUENCES_WORKFLOW.out.output.view { "Output: $it" }
}
