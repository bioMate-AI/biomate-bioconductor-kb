#!/usr/bin/env nextflow
/*
 * molecular_biology/digest_sequence
 * Simulates restriction enzyme digestion using Biopython's catalyze method and returns the resulting DNA fragments.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: pUC19 fragment with common restriction sites
params.dna_sequence = 'ATGAATTCGAGCTCGGTACCCGGGGATCCTCTAGAGTCGACCTGCAGGCATGCAAGCTT'
params.enzyme_names = '["EcoRI", "BamHI", "HindIII"]'
params.is_circular = 'false'

process DIGEST_SEQUENCE {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("digest_sequence_results.json"), emit: results
    tuple val(meta), path("digest_sequence_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DNA_SEQUENCE="${params.dna_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_NAMES="${params.enzyme_names?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def digest_sequence(dna_sequence: str, enzyme_names: list[str], is_circular: bool = True) -> dict:
    '''Simulates restriction enzyme digestion using Biopython's catalyze method and returns the resulting DNA fragments.

    Args:
        enzyme_names (str | list): Name of the restriction enzyme or list of enzyme names
        dna_sequence (str): Input DNA sequence
        is_circular (bool): Whether the DNA sequence is circular (True) or linear (False)

    Returns:
        Dict: Dictionary containing the digestion fragments and their properties including positions

    '''
    # Convert sequence to Biopython Seq object
    seq = Seq(dna_sequence)
    seq_length = len(seq)

    # Get all cut positions for all enzymes
    all_cut_positions = []
    for enzyme_name in enzyme_names:
        enzyme_obj = getattr(Restriction, enzyme_name)
        cut_sites = enzyme_obj.search(seq, linear=not is_circular)
        all_cut_positions.extend(cut_sites)

    # Sort cut positions and remove duplicates
    all_cut_positions = sorted(set(all_cut_positions))

    # Calculate fragments with positions
    fragments = []
    if not all_cut_positions:
        # No cuts - return full sequence
        fragments.append({"fragment": str(seq), "length": seq_length, "start": 0, "end": seq_length})
    # Handle linear and circular cases
    elif is_circular:
        for i in range(len(all_cut_positions)):
            start = all_cut_positions[i]
            end = all_cut_positions[0] + seq_length if i == len(all_cut_positions) - 1 else all_cut_positions[i + 1]

            # Get fragment sequence
            if end > seq_length:
                fragment_seq = dna_sequence[start:] + dna_sequence[: end - seq_length]
            else:
                fragment_seq = dna_sequence[start:end]

            fragments.append(
                {
                    "fragment": fragment_seq,
                    "length": len(fragment_seq),
                    "start": start,
                    "end": end if end <= seq_length else end - seq_length,
                    "is_wrapped": end > seq_length,
                }
            )
    else:
        # First fragment
        if all_cut_positions[0] > 0:
            fragments.append(
                {
                    "fragment": dna_sequence[: all_cut_positions[0]],
                    "length": all_cut_positions[0],
                    "start": 0,
                    "end": all_cut_positions[0],
                }
            )

        # Middle fragments
        for i in range(len(all_cut_positions) - 1):
            start = all_cut_positions[i]
            end = all_cut_positions[i + 1]
            fragments.append(
                {
                    "fragment": dna_sequence[start:end],
                    "length": end - start,
                    "start": start,
                    "end": end,
                }
            )

        # Last fragment
        if all_cut_positions[-1] < seq_length:
            fragments.append(
                {
                    "fragment": dna_sequence[all_cut_positions[-1] :],
                    "length": seq_length - all_cut_positions[-1],
                    "start": all_cut_positions[-1],
                    "end": seq_length,
                }
            )

    # Sort fragments by length (descending)
    fragments.sort(key=lambda x: x["length"], reverse=True)

    results = {
        "explanation": (
            "Output fields:\\n"
            "- sequence_info: Information about the input sequence\\n"
            "  * length: Length of the sequence in base pairs\\n"
            "  * is_circular: Whether sequence is circular or linear\\n"
            "- digestion_info: Overview of digestion results\\n"
            "  * enzymes_used: List of restriction enzymes used\\n"
            "  * number_of_fragments: Total number of fragments produced\\n"
            "  * cut_positions: List of all cut positions in sequence\\n"
            "- fragments: List of all fragments produced, where each contains:\\n"
            "  * fragment: The DNA sequence of the fragment\\n"
            "  * length: Length of the fragment in base pairs\\n"
            "  * start: Start position in original sequence (0-based)\\n"
            "  * end: End position in original sequence\\n"
            "  * is_wrapped: (Only for circular) Whether fragment wraps around sequence end"
        ),
        "sequence_info": {
            "length": len(seq),
            "is_circular": is_circular,
        },
        "digestion_info": {
            "enzymes_used": enzyme_names,
            "number_of_fragments": len(fragments),
            "cut_positions": all_cut_positions,
        },
        "fragments": fragments,
    }

    return results

# Execute the function
try:
    result = digest_sequence(
        dna_sequence=auto_convert(os.environ.get("PARAM_DNA_SEQUENCE", "")),
        enzyme_names=auto_convert(os.environ.get("PARAM_ENZYME_NAMES", "")),
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
    "function": "digest_sequence",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("digest_sequence_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("digest_sequence_output.txt", "w") as f:
    f.write("Biomni: Digest Sequence" + NL)
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
        biomni_function: "digest_sequence"
    END_VERSIONS
    """
}

workflow DIGEST_SEQUENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DIGEST_SEQUENCE(ch_input)

    emit:
    results = DIGEST_SEQUENCE.out.results
    output = DIGEST_SEQUENCE.out.output
    versions = DIGEST_SEQUENCE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DIGEST_SEQUENCE_WORKFLOW(ch_input)

    DIGEST_SEQUENCE_WORKFLOW.out.output.view { "Output: $it" }
}
