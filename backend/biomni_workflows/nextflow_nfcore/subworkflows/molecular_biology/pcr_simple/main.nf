#!/usr/bin/env nextflow
/*
 * molecular_biology/pcr_simple
 * Simulate PCR amplification with given primers and sequence.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PCR amplification of GFP from pEGFP-N1 plasmid
// Template sequence containing GFP with flanking regions
params.sequence = 'ATGGTGAGCAAGGGCGAGGAGCTGTTCACCGGGGTGGTGCCCATCCTGGTCGAGCTGGACGGCGACGTAAACGGCCACAAGTTCAGCGTGTCCGGCGAGGGCGAGGGCGATGCCACCTACGGCAAGCTGACCCTGAAGTTCATCTGCACCACCGGCAAGCTGCCCGTGCCCTGGCCCACCCTCGTGACCACCTTCGGCTACGGCCTGATGTGCTTTGCCCGCTACCCCGACCACATGAAGCAGCACGACTTCTTCAAGTCCGCCATGCCCGAAGGCTACGTCCAGGAGCGCACCATCTTCTTCAAGGACGACGGCAACTACAAGACACGCGCCGAGGTGAAGTTCGAGGGCGACACCCTGGTGAACCGCATCGAGCTGAAGGGCATCGACTTCAAGGAGGACGGCAACATCCTGGGGCACAAGCTGGAGTACAACTACAACAGCCACAACGTCTATATCATGGCCGACAAGCAGAAGAACGGCATCAAGGTGAACTTCAAGATCCGCCACAACATCGAGGACGGCAGCGTGCAGCTCGCCGACCACTACCAGCAGAACACCCCCATCGGCGACGGCCCCGTGCTGCTGCCCGACAACCACTACCTGAGCACCCAGTCCGCCCTGAGCAAAGACCCCAACGAGAAGCGCGATCACATGGTCCTGCTGGAGTTCGTGACCGCCGCCGGGATCACTCTCGGCATGGACGAGCTGTACAAGTAA'
// Primers designed to amplify full-length GFP
params.forward_primer = 'ATGGTGAGCAAGGGCGAG'
params.reverse_primer = 'TTACTTGTACAGCTCGTCCATGCC'
params.circular = 'false'

process PCR_SIMPLE {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("pcr_simple_results.json"), emit: results
    tuple val(meta), path("pcr_simple_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FORWARD_PRIMER="${params.forward_primer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REVERSE_PRIMER="${params.reverse_primer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CIRCULAR="${params.circular?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
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

def pcr_simple(sequence: str, forward_primer: str, reverse_primer: str, circular: bool = False) -> dict:
    '''Simulate PCR amplification with given primers and sequence.

    Args:
        sequence (str): Either a sequence string or path to plasmid file
        forward_primer (str): Forward primer sequence (5' to 3')
        reverse_primer (str): Reverse primer sequence (5' to 3')
        circular (bool): Whether the sequence is circular (default: False)

    Returns:
        dict: Results of PCR simulation including products and primer binding details

    '''
    # First check if primers are valid using existing function
    fwd_result = align_sequences(sequence, forward_primer)["sequences"][0]["alignments"]
    rev_result = align_sequences(sequence, str(Seq(reverse_primer).reverse_complement()))["sequences"][0]["alignments"]

    if not fwd_result or not rev_result:
        return {
            "explanation": (
                "Output fields:\\n"
                "- success: Boolean indicating if any PCR products were found\\n"
                "- message: Error message if no products found\\n"
                "- products: Empty list when no products found\\n"
                "- forward_binding_sites: Number of forward primer binding locations\\n"
                "- reverse_binding_sites: Number of reverse primer binding locations"
            ),
            "success": False,
            "message": "One or both primers do not align to the sequence.",
            "products": [],
            "forward_binding_sites": len(fwd_result),
            "reverse_binding_sites": len(rev_result),
        }

    # Get primer positions
    fwd_positions = [align["position"] for align in fwd_result]
    rev_positions = [align["position"] for align in rev_result]
    sequence_length = len(sequence)

    # Find all possible PCR products
    products = []

    for fwd_pos in fwd_positions:
        for rev_pos in rev_positions:
            # Calculate product size and sequence
            if fwd_pos < rev_pos:
                # Standard linear product
                size = rev_pos - fwd_pos + len(reverse_primer)
                product = sequence[fwd_pos : rev_pos + len(reverse_primer)]
            elif circular:
                # Handle circular template - wrap around from end to start
                size = sequence_length - fwd_pos + rev_pos + len(reverse_primer)
                product = sequence[fwd_pos:] + sequence[: rev_pos + len(reverse_primer)]
            else:
                # Skip invalid combinations for linear sequences
                continue

            products.append(
                {
                    "size": size,
                    "forward_position": fwd_pos,
                    "reverse_position": rev_pos,
                    "sequence": product,
                    "forward_mismatches": fwd_result[fwd_positions.index(fwd_pos)]["mismatches"],
                    "reverse_mismatches": rev_result[rev_positions.index(rev_pos)]["mismatches"],
                }
            )

    if not products:
        return {
            "explanation": (
                "Output fields:\\n"
                "- success: Boolean indicating if any PCR products were found\\n"
                "- message: Error message if no products found\\n"
                "- products: Empty list when no products found\\n"
                "- forward_binding_sites: Number of forward primer binding locations\\n"
                "- reverse_binding_sites: Number of reverse primer binding locations"
            ),
            "success": False,
            "message": "No valid PCR products found with these primers.",
            "products": [],
            "forward_binding_sites": len(fwd_positions),
            "reverse_binding_sites": len(rev_positions),
        }

    return {
        "explanation": (
            "Output fields:\\n"
            "- success: Boolean indicating if any PCR products were found\\n"
            "- products: List of all possible PCR products, where each contains:\\n"
            "  * size: Length of the PCR product in base pairs\\n"
            "  * sequence: The actual DNA sequence of the product\\n"
            "  * forward_position: Starting position of forward primer binding\\n"
            "  * reverse_position: Starting position of reverse primer binding\\n"
            "  * forward_mismatches: List of mismatches in forward primer binding\\n"
            "  * reverse_mismatches: List of mismatches in reverse primer binding\\n"
            "- forward_binding_sites: Number of locations where forward primer can bind\\n"
            "- reverse_binding_sites: Number of locations where reverse primer can bind"
        ),
        "success": True,
        "products": products,
        "forward_binding_sites": len(fwd_positions),
        "reverse_binding_sites": len(rev_positions),
    }

# Execute the function
try:
    result = pcr_simple(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        forward_primer=auto_convert(os.environ.get("PARAM_FORWARD_PRIMER", "")),
        reverse_primer=auto_convert(os.environ.get("PARAM_REVERSE_PRIMER", "")),
        circular=auto_convert(os.environ.get("PARAM_CIRCULAR", "")),
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
    "function": "pcr_simple",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("pcr_simple_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("pcr_simple_output.txt", "w") as f:
    f.write("Biomni: Pcr Simple" + NL)
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
        biomni_function: "pcr_simple"
    END_VERSIONS
    """
}

workflow PCR_SIMPLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PCR_SIMPLE(ch_input)

    emit:
    results = PCR_SIMPLE.out.results
    output = PCR_SIMPLE.out.output
    versions = PCR_SIMPLE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PCR_SIMPLE_WORKFLOW(ch_input)

    PCR_SIMPLE_WORKFLOW.out.output.view { "Output: $it" }
}
