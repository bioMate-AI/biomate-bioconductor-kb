#!/usr/bin/env nextflow
/*
 * molecular_biology/design_verification_primers
 * Design Sanger sequencing primers to verify a specific region in a plasmid.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: pUC19-like plasmid with MCS for Sanger sequencing verification
params.plasmid_sequence = 'ATGACCATGATTACGCCAAGCTTGCATGCCTGCAGGTCGACTCTAGAGGATCCCCGGGTACCGAGCTCGAATTCACTGGCCGTCGTTTTACAACGTCGTGACTGGGAAAACCCTGGCGTTACCCAACTTAATCGCCTTGCAGCACATCCCCCTTTCGCCAGCTGGCGTAATAGCGAAGAGGCCCGCACCGATCGCCCTTCCCAACAGTTGCGCAGCCTGAATGGCGAATGGCGCCTGATGCGGTATTTTCTCCTTACGCATCTGTGCGGTATTTCACACCGCATATGGTGCACTCTCAGTACAATCTGCTCTGATGCCGCATAGTTAAGCCAGCCCCGACACCCGCCAACACCCGCTGACGCGCCCTGACGGGCTTGTCTGCTCCCGGCATCCGCTTACAGACAAGCTGTGACCGTCTCCGGGAGCTGCATGTGTCAGAGGTTTTCACCGTCATCACCGAAACGCGCGAGACGAAAGGGCCTCGTGATACGCCTATTTTTATAGGTTAATGTCATGATAATAATGGTTTCTTAGACGTCAGGTGGCACTTTTCGGGGAAATGTGCGCGGAACCCCTATTTGTTTATTTTTCTAAATACATTCAAATATGTATCCGCTCATGAGACAATAACCCTGATAAATGCTTCAATAATATTGAAAAAGGAAGAGTATGAGTATTCAACATTTCCGTGTCGCCCTTATTCCCTTTTTTGCGGCATTTTGCCTTCCTGTTTTTGCTCACCCAGAAACGCTGGTGAAAGTAAAAGATGCTGAAGATCAGTTGGGTGCACGAGTGGGTTACATCGAACTGGATCTCAACAGCGGTAAGATCCTTGAGAGTTTTCGCCCCGAAGAACGTTTTCCAATGATGAGCACTTTTAAAGTTCTGCTATGTGGCGCGGTATTATCCCGTATTGACGCCGGGCAAGAGCAACTCGGTCGCCGCATACACTATTCTCAGAATGACTTGGTTGAGTACTCACCAGTCACAGAAAAGCATCTTACGGATGGCATGACAGTAAGAGAATTATGCAGTGCTGCCATAACCATGAGTGATAACACTGCGGCCAACTTACTTCTGACAACGATCGGAGGACCGAAGGAGCTAACCGCTTTTTTGCACAACATGGGGGATCATGTAACTCGCCTTGATCGTTGGGAACCGGAGCTGAATGAAGCCATACCAAACGACGAGCGTGACACCACGATGCCTGTAGCAATGGCAACAACGTTGCGCAAACTATTAACTGGCGAACTACTTACTCTAGCTTCCCGGCAACAATTAATAGACTGGATGGAGGCGGATAAAGTTGCAGGACCACTTCTGCGCTCGGCCCTTCCGGCTGGCTGGTTTATTGCTGATAAATCTGGAGCCGGTGAGCGTGGGTCTCGCGGTATCATTGCAGCACTGGGGCCAGATGGTAAGCCCTCCCGTATCGTAGTTATCTACACGACGGGGAGTCAGGCAACTATGGATGAACGAAATAGACAGATCGCTGAGATAGGTGCCTCACTGATTAAGCATTGGTAA'
params.target_region = '[100, 500]'
params.existing_primers = null
params.is_circular = 'true'
params.coverage_length = 800
params.primer_length = 20
params.min_gc = 0.4
params.max_gc = 0.6
params.min_tm = 55.0
params.max_tm = 65.0

process DESIGN_VERIFICATION_PRIMERS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("design_verification_primers_results.json"), emit: results
    tuple val(meta), path("design_verification_primers_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PLASMID_SEQUENCE="${params.plasmid_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_REGION="${params.target_region?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EXISTING_PRIMERS="${params.existing_primers?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IS_CIRCULAR="${params.is_circular?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COVERAGE_LENGTH="${params.coverage_length?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PRIMER_LENGTH="${params.primer_length?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_GC="${params.min_gc?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_GC="${params.max_gc?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_TM="${params.min_tm?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_TM="${params.max_tm?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from Bio.SeqUtils import MeltingTemp as mt
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

def design_primer(
    sequence: str,
    start_pos: int,
    primer_length: int = 20,
    min_gc: float = 0.4,
    max_gc: float = 0.6,
    min_tm: float = 55.0,
    max_tm: float = 65.0,
    search_window: int = 100,
) -> dict[str, Any] | None:
    '''Design a single primer within the given sequence window.

    Args:
        sequence (str): Target DNA sequence
        start_pos (int): Starting position for primer search
        primer_length (int): Length of the primer to design (default: 20)
        min_gc (float): Minimum GC content (default: 0.4)
        max_gc (float): Maximum GC content (default: 0.6)
        min_tm (float): Minimum melting temperature in °C (default: 55.0)
        max_tm (float): Maximum melting temperature in °C (default: 65.0)
        search_window (int): Size of window to search for primers (default: 100)

    Returns:
        Optional[Dict[str, Any]]: Dictionary with primer information or None if no suitable primer found

    '''
    # Extract candidate region for primer design
    primer_region_start = start_pos
    primer_region_end = min(start_pos + search_window, len(sequence))
    primer_region = sequence[primer_region_start:primer_region_end]

    # Handle case where region is too small
    if len(primer_region) < primer_length:
        return None

    # Generate candidate primers
    best_primer = None
    best_score = float("inf")  # Lower is better

    for j in range(len(primer_region) - primer_length + 1):
        candidate = primer_region[j : j + primer_length]

        # Calculate GC content
        gc_content = (candidate.count("G") + candidate.count("C")) / primer_length
        # Skip if GC content is outside acceptable range
        if gc_content < min_gc or gc_content > max_gc:
            continue

        # Calculate melting temperature
        tm = mt.Tm_Wallace(candidate)

        # Skip if Tm is outside acceptable range
        if tm < min_tm or tm > max_tm:
            continue

        # Score the candidate (distance from ideal GC and Tm)
        ideal_gc = (min_gc + max_gc) / 2
        ideal_tm = (min_tm + max_tm) / 2
        gc_penalty = abs(gc_content - ideal_gc) * 100
        tm_penalty = abs(tm - ideal_tm)

        score = gc_penalty + tm_penalty

        if score < best_score:
            best_score = score
            best_primer = {
                "sequence": candidate,
                "position": primer_region_start + j,
                "gc": gc_content,
                "tm": tm,
                "score": score,
            }

    return best_primer

def design_verification_primers(
    plasmid_sequence: str,
    target_region: tuple[int, int],
    existing_primers: list[dict[str, str]] | None = None,
    is_circular: bool = True,
    coverage_length: int = 800,
    primer_length: int = 20,
    min_gc: float = 0.4,
    max_gc: float = 0.6,
    min_tm: float = 55.0,
    max_tm: float = 65.0,
) -> dict[str, Any]:
    '''Design Sanger sequencing primers to verify a specific region in a plasmid.

    First tries to use primers from an existing primer pool. If they cannot fully
    cover the region, designs additional primers as needed.

    Args:
        plasmid_sequence (str): The complete plasmid sequence
        target_region (Tuple[int, int]): Start and end positions to verify (0-based indexing)
        existing_primers (Optional[List[Dict[str, str]]]): List of existing primers with
                                                         their sequences and optional names.
                                                         If None, uses common lab primers.
        is_circular (bool): Whether the plasmid is circular (default: True)
        coverage_length (int): Typical read length for each primer (default: 800bp)
        primer_length (int): Length of newly designed primers (default: 20)
        min_gc (float): Minimum GC content for new primers (default: 0.4)
        max_gc (float): Maximum GC content for new primers (default: 0.6)
        min_tm (float): Minimum melting temperature in °C (default: 55.0)
        max_tm (float): Maximum melting temperature in °C (default: 65.0)

    Returns:
        Dict: Dictionary containing:
            - target_region: The region to be verified
            - recommended_primers: List of primers to use (from existing and/or newly designed)
            - coverage_map: How the primers cover the target region

    '''
    # Use default primers if none are provided
    if existing_primers is None:
        # Common laboratory primers
        existing_primers = [
            {"name": "T7", "sequence": "TAATACGACTCACTATAGGG"},
            {"name": "T7_Term", "sequence": "GCTAGTTATTGCTCAGCGG"},
            {"name": "T3", "sequence": "ATTAACCCTCACTAAAGGGA"},
            {"name": "SP6", "sequence": "GATTTAGGTGACACTATAG"},
            {"name": "U6", "sequence": "GACTATCATATGCTTACCGT"},
            {"name": "BGHR", "sequence": "TAGAAGGCACAGTCGAGG"},
            {"name": "M13F", "sequence": "GTAAAACGACGGCCAG"},
            {"name": "M13R", "sequence": "CAGGAAACAGCTATGAC"},
            {"name": "M13-40FOR", "sequence": "GTTTTCCCAGTCACGAC"},
            {"name": "M13-48REV", "sequence": "CGGATAACAATTTCACACAG"},
            {"name": "CMV-Forward", "sequence": "CGCAAATGGGCGGTAGGCGTG"},
            {"name": "5GEX", "sequence": "GGGCTGGCAAGCCACGTTTGGTG"},
            {"name": "3GEX", "sequence": "CCGGGAGCTGCATGTGTCAGAGG"},
            {"name": "pFastBacF", "sequence": "GGATTATTCATACCGTCCCA"},
            {"name": "pFastBacR", "sequence": "CAAATGTGGTATGGCTGATT"},
            {"name": "pBAD_Forward", "sequence": "ATGCCATAGCATTTTTATCC"},
            {"name": "pBAD_Reverse", "sequence": "GATTTAATCTGTATCAGG"},
            {"name": "EGFP-C-For", "sequence": "CATGGTCCTGCTGGAGTTCGTG"},
            {"name": "EGFP-C-REV", "sequence": "GTTCAGGGGGAGGTGTG"},
            {"name": "EGFP-N", "sequence": "CGTCGCCGTCCAGCTCGACCA"},
            {"name": "SV40pA-R", "sequence": "GAAATTTGTGATGCTATTGC"},
            {"name": "ATTB1", "sequence": "GTTTGTACAAAAAAGCAGGC"},
            {"name": "ATTB2", "sequence": "CCACTTTGTACAAGAAAGCTGGGT"},
            {"name": "ATTL1", "sequence": "CGCGTTAACGCTAGCATGGATCTC"},
            {"name": "ATTL2", "sequence": "CATCAGAGATTTTGAGACAC"},
            {"name": "ITS1", "sequence": "TCCGTAGGTGAACCTGCGG"},
            {"name": "ITS4", "sequence": "TCCTCCGCTTATTGATATGC"},
            {"name": "PJET1-2F", "sequence": "CGACTCACTATAGGGAGAGCGGC"},
            {"name": "PJET1-2R", "sequence": "AAGAACATCGATTTTCCATGGCAG"},
        ]

    # Helper functions for region coverage calculations
    def is_position_covered(pos, covered_regions):
        '''Check if a position is covered by any region.'''
        return any(region["start"] <= pos <= region["end"] for region in covered_regions)

    def is_region_fully_covered(covered_regions, start, end):
        '''Check if the target region is fully covered.'''
        # Merge overlapping regions first
        merged = merge_overlapping_regions(covered_regions)

        # Check if merged regions cover the entire target
        return all(any(r["start"] <= pos <= r["end"] for r in merged) for pos in range(start, end + 1))

    def merge_overlapping_regions(regions):
        '''Merge overlapping regions in the list.'''
        if not regions:
            return []

        # Sort by start position
        sorted_regions = sorted(regions, key=lambda x: x["start"])

        # Merge overlapping
        merged = [sorted_regions[0]]
        for region in sorted_regions[1:]:
            prev = merged[-1]
            # If regions overlap or are adjacent
            if region["start"] <= prev["end"] + 1:
                # Extend previous region
                prev["end"] = max(prev["end"], region["end"])
            else:
                # Add as new region
                merged.append(region)

        return merged

    # Clean and prepare the plasmid sequence
    plasmid_sequence = plasmid_sequence.upper()

    # Handle target region
    start, end = target_region
    region_length = end - start + 1
    if region_length <= 0:
        raise ValueError("Target region end must be greater than start")

    # Prepare result containers
    recommended_primers = []
    coverage_map = []

    # If plasmid is circular, we may need to handle wrapping
    if is_circular and end >= len(plasmid_sequence):
        # Adjust for circular plasmid wrapping
        effective_sequence = plasmid_sequence + plasmid_sequence[: end - len(plasmid_sequence) + coverage_length]
    else:
        effective_sequence = plasmid_sequence

    # Step 1: Try to use existing primers if provided
    used_existing_primers = False

    if existing_primers:
        # Create a structured representation of existing primers
        primer_pool = []
        for i, primer in enumerate(existing_primers):
            if isinstance(primer, str):
                primer_info = {"name": f"Existing_{i + 1}", "sequence": primer}
            else:
                primer_info = primer.copy()
                if "name" not in primer_info:
                    primer_info["name"] = f"Existing_{i + 1}"

            primer_pool.append(primer_info)

        # Find alignments for all existing primers
        alignment_results = align_sequences(effective_sequence, [p["sequence"] for p in primer_pool])

        # Create list of all potential primer matches with their coverage
        potential_primers = []

        for i, result in enumerate(alignment_results.get("sequences", [])):
            primer_info = primer_pool[i]
            primer_seq = primer_info["sequence"]

            for alignment in result.get("alignments", []):
                position = alignment["position"]
                strand = alignment["strand"]

                # Calculate coverage range based on primer position and orientation
                if strand == "+":
                    coverage_start = position
                    coverage_end = position + coverage_length
                else:  # Reverse primer
                    coverage_end = position + len(primer_seq)
                    coverage_start = coverage_end - coverage_length

                # Check if this primer covers any part of the target region
                if coverage_start <= end and coverage_end >= start:
                    # Calculate the coverage within the target region
                    covered_start = max(start, coverage_start)
                    covered_end = min(end, coverage_end)

                    # Add to potential primers list
                    potential_primers.append(
                        {
                            "name": primer_info["name"],
                            "sequence": primer_seq,
                            "position": position,
                            "strand": strand,
                            "source": "existing",
                            "covers": [covered_start, covered_end],
                            "coverage_length": covered_end - covered_start + 1,
                        }
                    )

        # Sort potential primers by coverage length (descending)
        potential_primers.sort(key=lambda x: x["coverage_length"], reverse=True)

        # Select primers using a greedy approach to minimize the number used
        # while achieving maximum coverage
        if potential_primers:
            # Initialize covered regions
            covered_regions = []
            selected_primers = []

            # Keep selecting primers until we've covered everything or run out of primers
            while potential_primers and not is_region_fully_covered(covered_regions, start, end):
                # Take the first remaining primer (with most coverage)
                best_primer = potential_primers.pop(0)

                # Check if this primer adds any new coverage
                new_covered_start, new_covered_end = best_primer["covers"]
                adds_new_coverage = False

                for s in range(new_covered_start, new_covered_end + 1):
                    if not is_position_covered(s, covered_regions):
                        adds_new_coverage = True
                        break

                if adds_new_coverage:
                    # Add primer to selected list
                    selected_primers.append(best_primer)

                    # Update covered regions
                    covered_regions.append({"start": new_covered_start, "end": new_covered_end})

                    # Merge overlapping regions
                    covered_regions = merge_overlapping_regions(covered_regions)

            # Update recommended primers and coverage map
            for primer in selected_primers:
                recommended_primers.append(primer)
                coverage_map.append(
                    {
                        "primer": primer["name"],
                        "start": primer["covers"][0],
                        "end": primer["covers"][1],
                        "length": primer["covers"][1] - primer["covers"][0] + 1,
                    }
                )

                used_existing_primers = True

    # Step 2: Identify uncovered regions for new primer design
    if not used_existing_primers:
        # No existing primers used, the entire region is uncovered
        uncovered_regions = [{"start": start, "end": end}]
    else:
        # Sort and merge coverage map
        covered_regions = [{"start": cm["start"], "end": cm["end"]} for cm in coverage_map]
        covered_regions = merge_overlapping_regions(covered_regions)

        # Find gaps
        uncovered_regions = []
        current_pos = start

        for region in covered_regions:
            if current_pos < region["start"]:
                uncovered_regions.append({"start": current_pos, "end": region["start"] - 1})
            current_pos = max(current_pos, region["end"] + 1)

        if current_pos <= end:
            uncovered_regions.append({"start": current_pos, "end": end})

    # Step 3: Design new primers for uncovered regions
    for region in uncovered_regions:
        gap_start = region["start"]
        gap_end = region["end"]
        gap_length = gap_end - gap_start + 1

        # Determine how many primers we need for this gap
        num_primers_needed = max(
            1,
            (gap_length // (coverage_length // 2)) + (1 if gap_length % (coverage_length // 2) > 0 else 0),
        )

        # Calculate positions for even distribution of primers
        positions = []
        if num_primers_needed == 1:
            positions.append(max(0, gap_start - 100))  # Start primer a bit before the gap
        else:
            interval = gap_length / (num_primers_needed - 0.5)  # Distribute primers evenly
            for i in range(num_primers_needed):
                pos = max(0, int(gap_start - 100 + i * interval))
                positions.append(min(pos, len(effective_sequence) - primer_length))

        # Design primers for each position
        for pos in positions:
            # Design a new primer
            new_primer = design_primer(
                effective_sequence,
                pos,
                primer_length=primer_length,
                min_gc=min_gc,
                max_gc=max_gc,
                min_tm=min_tm,
                max_tm=max_tm,
            )

            # If we found a suitable primer
            if new_primer:
                primer_name = f"New_primer_{len(recommended_primers) + 1}"

                # Calculate coverage
                coverage_start = new_primer["position"]
                coverage_end = coverage_start + coverage_length

                # Adjust to target region boundaries
                covered_start = max(start, coverage_start)
                covered_end = min(end, coverage_end)

                # Add to recommended primers
                recommended_primers.append(
                    {
                        "name": primer_name,
                        "sequence": new_primer["sequence"],
                        "position": new_primer["position"],
                        "strand": "+",  # Forward strand primer
                        "source": "newly_designed",
                        "gc": new_primer["gc"],
                        "tm": new_primer["tm"],
                        "covers": [covered_start, covered_end],
                    }
                )

                # Add to coverage map
                coverage_map.append(
                    {
                        "primer": primer_name,
                        "start": covered_start,
                        "end": covered_end,
                        "length": covered_end - covered_start + 1,
                    }
                )

    # Recalculate coverage to account for new primers
    coverage_map.sort(key=lambda x: x["start"])

    # Check if the target region is fully covered
    covered_regions = [{"start": cm["start"], "end": cm["end"]} for cm in coverage_map]
    is_fully_covered = is_region_fully_covered(covered_regions, start, end)

    # Prepare the final result
    result = {
        "target_region": {"start": start, "end": end, "length": region_length},
        "recommended_primers": recommended_primers,
        "coverage_map": coverage_map,
        "is_fully_covered": is_fully_covered,
    }

    if not is_fully_covered:
        result["warning"] = "The target region may not be fully covered. Consider manually reviewing the coverage map."

    return result

# Execute the function
try:
    result = design_verification_primers(
        plasmid_sequence=auto_convert(os.environ.get("PARAM_PLASMID_SEQUENCE", "")),
        target_region=auto_convert(os.environ.get("PARAM_TARGET_REGION", "")),
        existing_primers=auto_convert(os.environ.get("PARAM_EXISTING_PRIMERS", "")),
        is_circular=auto_convert(os.environ.get("PARAM_IS_CIRCULAR", "")),
        coverage_length=auto_convert(os.environ.get("PARAM_COVERAGE_LENGTH", "800")),
        primer_length=auto_convert(os.environ.get("PARAM_PRIMER_LENGTH", "20")),
        min_gc=auto_convert(os.environ.get("PARAM_MIN_GC", "0.4")),
        max_gc=auto_convert(os.environ.get("PARAM_MAX_GC", "0.6")),
        min_tm=auto_convert(os.environ.get("PARAM_MIN_TM", "55.0")),
        max_tm=auto_convert(os.environ.get("PARAM_MAX_TM", "65.0")),
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
    "function": "design_verification_primers",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("design_verification_primers_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("design_verification_primers_output.txt", "w") as f:
    f.write("Biomni: Design Verification Primers" + NL)
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
        biomni_function: "design_verification_primers"
    END_VERSIONS
    """
}

workflow DESIGN_VERIFICATION_PRIMERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DESIGN_VERIFICATION_PRIMERS(ch_input)

    emit:
    results = DESIGN_VERIFICATION_PRIMERS.out.results
    output = DESIGN_VERIFICATION_PRIMERS.out.output
    versions = DESIGN_VERIFICATION_PRIMERS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DESIGN_VERIFICATION_PRIMERS_WORKFLOW(ch_input)

    DESIGN_VERIFICATION_PRIMERS_WORKFLOW.out.output.view { "Output: $it" }
}
