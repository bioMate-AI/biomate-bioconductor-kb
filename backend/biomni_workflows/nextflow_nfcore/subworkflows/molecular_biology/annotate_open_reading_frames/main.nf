#!/usr/bin/env nextflow
/*
 * molecular_biology/annotate_open_reading_frames
 * Find all Open Reading Frames (ORFs) in a DNA sequence using Biopython.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.min_length = null
params.search_reverse = 'False'
params.filter_subsets = 'False'

process ANNOTATE_OPEN_READING_FRAMES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("annotate_open_reading_frames_results.json"), emit: results
    tuple val(meta), path("annotate_open_reading_frames_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_LENGTH="${params.min_length?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEARCH_REVERSE="${params.search_reverse?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FILTER_SUBSETS="${params.filter_subsets?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from collections import namedtuple
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



def annotate_open_reading_frames(sequence, min_length, search_reverse=False, filter_subsets=False):
    '''Find all Open Reading Frames (ORFs) in a DNA sequence using Biopython.
    Searches both forward and reverse complement strands.

    Args:
        sequence (str): DNA sequence
        min_length (int): Minimum length of ORF in nucleotides
        search_reverse (bool): Whether to search the reverse complement strand (default: False unless you want to search for reverse ORFs)
        filter_nested (bool): Whether to filter out ORFs with same end but later start (default: False unless you want to remove nested ORFs)

    Returns:
        dict: Dictionary containing:
            - explanation: Explanation of the output fields
            - summary_stats: Statistical overview of found ORFs
            - orfs: List of all found ORFs, where each ORF contains:
                - sequence: Nucleotide sequence of the ORF
                - aa_sequence: Translated amino acid sequence
                - start: Start position in original sequence (0-based)
                - end: End position in original sequence
                - strand: '+' for forward strand, '-' for reverse complement
                - frame: Reading frame (1,2,3 for forward; -1,-2,-3 for reverse)

    '''
    ORF = namedtuple("ORF", ["sequence", "aa_sequence", "start", "end", "strand", "frame"])

    def find_orfs_in_frame(seq_str, frame, strand):
        '''Helper function to find ORFs in a specific frame.'''
        orfs = []
        seq_length = len(seq_str)

        # Adjust sequence based on frame
        offset = frame - 1  # Convert 1-based frame to 0-based index
        frame_seq = seq_str[offset:]

        # Find all start codons
        start_positions = []
        stop_positions = []

        for i in range(0, len(frame_seq) - 2, 3):
            codon = frame_seq[i : i + 3]
            if len(codon) != 3:  # Skip incomplete codons
                continue

            # Record positions of start and stop codons
            if codon == "ATG":
                start_positions.append(i)
            elif codon in ["TAA", "TAG", "TGA"]:
                stop_positions.append(i)

                # Process any active ORFs that end at this stop codon
                while start_positions and start_positions[0] < i:
                    start_pos = start_positions.pop(0)
                    orf_seq = frame_seq[start_pos : i + 3]

                    # Check if ORF meets minimum length requirement
                    if len(orf_seq) >= min_length:
                        # Convert positions to original sequence coordinates
                        orig_start = start_pos + offset
                        orig_end = i + offset + 3

                        # For reverse strand, convert positions
                        if strand == "-":
                            orig_start = seq_length - orig_end
                            orig_end = seq_length - (start_pos + offset)

                        # Create Seq object for translation
                        orf_bio_seq = Seq(orf_seq)
                        aa_seq = str(orf_bio_seq.translate(to_stop=True))

                        orfs.append(
                            ORF(
                                sequence=orf_seq,
                                aa_sequence=aa_seq,
                                start=orig_start,
                                end=orig_end,
                                strand=strand,
                                frame=frame if strand == "+" else -frame,
                            )
                        )

        return orfs

    # Convert input to string and uppercase
    sequence = str(sequence).upper()
    seq_obj = Seq(sequence)

    all_orfs = []

    # Search forward strand
    for frame in range(1, 4):
        all_orfs.extend(find_orfs_in_frame(sequence, frame, "+"))

    # Search reverse complement strand
    if search_reverse:
        rev_comp = str(seq_obj.reverse_complement())
        for frame in range(1, 4):
            all_orfs.extend(find_orfs_in_frame(rev_comp, frame, "-"))

    if filter_subsets:
        # Sort ORFs by length first (longest first)
        all_orfs.sort(key=lambda x: len(x.sequence), reverse=True)

        # Filter out ORFs that are contained within other ORFs on the same strand
        filtered_orfs = []
        for _i, orf in enumerate(all_orfs):
            is_subset = False
            for larger_orf in filtered_orfs:
                if orf.strand == larger_orf.strand and orf.start >= larger_orf.start and orf.end <= larger_orf.end:
                    is_subset = True
                    break
            if not is_subset:
                filtered_orfs.append(orf)
        all_orfs = filtered_orfs

    # Sort ORFs by length (longest first)
    all_orfs.sort(key=lambda x: len(x.sequence), reverse=True)

    # Calculate summary statistics
    forward_orfs = len([orf for orf in all_orfs if orf.strand == "+"])
    reverse_orfs = len([orf for orf in all_orfs if orf.strand == "-"])
    avg_length = sum(len(orf.sequence) for orf in all_orfs) / len(all_orfs) if all_orfs else 0

    summary_stats = {
        "total_orfs": len(all_orfs),
        "forward_orfs": forward_orfs,
        "reverse_orfs": reverse_orfs,
        "avg_length": round(avg_length, 1),
    }

    explanation = (
        "Output fields:\\n"
        "- summary_stats: Statistical overview of found ORFs\\n"
        "  * total_orfs: Total number of ORFs found\\n"
        "  * forward_orfs: Number of ORFs on forward strand\\n"
        "  * reverse_orfs: Number of ORFs on reverse strand\\n"
        "  * avg_length: Average length of all ORFs in base pairs\\n"
        "- orfs: List of all found ORFs, where each ORF contains:\\n"
        "  * sequence: Nucleotide sequence of the ORF\\n"
        "  * aa_sequence: Translated amino acid sequence\\n"
        "  * start: Start position in original sequence (0-based)\\n"
        "  * end: End position in original sequence\\n"
        "  * strand: '+' for forward strand, '-' for reverse complement\\n"
        "  * frame: Reading frame (1,2,3 for forward; -1,-2,-3 for reverse)"
    )

    return {
        "explanation": explanation,
        "summary_stats": summary_stats,
        "orfs": all_orfs,
    }

# Execute the function
try:
    result = annotate_open_reading_frames(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        min_length=auto_convert(os.environ.get("PARAM_MIN_LENGTH", "")),
        search_reverse=auto_convert(os.environ.get("PARAM_SEARCH_REVERSE", "False")),
        filter_subsets=auto_convert(os.environ.get("PARAM_FILTER_SUBSETS", "False")),
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
    "function": "annotate_open_reading_frames",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("annotate_open_reading_frames_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("annotate_open_reading_frames_output.txt", "w") as f:
    f.write("Biomni: Annotate Open Reading Frames" + NL)
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
        biomni_function: "annotate_open_reading_frames"
    END_VERSIONS
    """
}

workflow ANNOTATE_OPEN_READING_FRAMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANNOTATE_OPEN_READING_FRAMES(ch_input)

    emit:
    results = ANNOTATE_OPEN_READING_FRAMES.out.results
    output = ANNOTATE_OPEN_READING_FRAMES.out.output
    versions = ANNOTATE_OPEN_READING_FRAMES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANNOTATE_OPEN_READING_FRAMES_WORKFLOW(ch_input)

    ANNOTATE_OPEN_READING_FRAMES_WORKFLOW.out.output.view { "Output: $it" }
}
