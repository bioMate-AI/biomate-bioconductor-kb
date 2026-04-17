#!/usr/bin/env nextflow
/*
 * molecular_biology/design_primer
 * Design a single primer within the given sequence window.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: BRCA1 gene fragment for primer design
params.sequence = 'ATGGATTTATCTGCTCTTCGCGTTGAAGAAGTACAAAATGTCATTAATGCTATGCAGAAAATCTTAGAGTGTCCCATCTGTCTGGAGTTGATCAAGGAACCTGTCTCCACAAAGTGTGACCACATATTTTGCAAATTTTGCATGCTGAAACTTCTCAACCAGAAGAAAGGGCCTTCACAGTGTCCTTTATGTAAGAATGATATAACCAAAAGGAGCCTACAAGAAAGTACGAGATTTAGTCAACTTGTTGAAGAGCTATTGAAAATCATTTGTGCTTTTCAGCTTGACACAGGTTTGGAGTATGCAAACAGCTATAATTTTGCAAAAAAGGAAAATAACTCTCCTGAACATCTAAAAGATGAAGTTTCTATCATCCAAAGTATGGGCTACAGAAACCGTGCCAAAAGACTTCTACAGAGTGAACCCGAAAATCCTTCCTTGCAGGAAACCAGTCTCAGTGTCCAACTCTCTAACCTTGGAACTGTGAGAACTCTGAGGACAAAGCAGCGGATACAACCTCAAAAGACGTCTGTCTACATTGAATTGGGATCTGATTCTTCTGAAGATACCGTTAATAAGGCAACTTATTGCAGTGTGGGAGATCAAGAATTGTTACAAATCACCCCTCAAGGAACCAGGGATGAAATCAGTTTGGATTCTGCAAAAAAGGCTGCTTGTGAATTTTCTGAGACGGATG'
params.start_pos = 0
params.primer_length = 20
params.min_gc = 0.4
params.max_gc = 0.6
params.min_tm = 55.0
params.max_tm = 65.0
params.search_window = 100

process DESIGN_PRIMER {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("design_primer_results.json"), emit: results
    tuple val(meta), path("design_primer_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_START_POS="${params.start_pos?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PRIMER_LENGTH="${params.primer_length?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_GC="${params.min_gc?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_GC="${params.max_gc?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_TM="${params.min_tm?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_TM="${params.max_tm?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEARCH_WINDOW="${params.search_window?.toString()?.replace('"', '\\"') ?: 'null'}"

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
    # Validate inputs - use defaults if None
    if sequence is None:
        sequence = "ATGCATGCATGCATGCATGCATGCATGCATGC"
    if start_pos is None:
        start_pos = 0
    if primer_length is None:
        primer_length = 20
    if min_gc is None:
        min_gc = 0.4
    if max_gc is None:
        max_gc = 0.6
    if min_tm is None:
        min_tm = 55.0
    if max_tm is None:
        max_tm = 65.0
    if search_window is None:
        search_window = 100
    sequence = str(sequence).upper()
    start_pos = int(start_pos)
    primer_length = int(primer_length)
    search_window = int(search_window)
    min_gc, max_gc = float(min_gc), float(max_gc)
    min_tm, max_tm = float(min_tm), float(max_tm)

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

# Execute the function
try:
    result = design_primer(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        start_pos=auto_convert(os.environ.get("PARAM_START_POS", "")),
        primer_length=auto_convert(os.environ.get("PARAM_PRIMER_LENGTH", "20")),
        min_gc=auto_convert(os.environ.get("PARAM_MIN_GC", "0.4")),
        max_gc=auto_convert(os.environ.get("PARAM_MAX_GC", "0.6")),
        min_tm=auto_convert(os.environ.get("PARAM_MIN_TM", "55.0")),
        max_tm=auto_convert(os.environ.get("PARAM_MAX_TM", "65.0")),
        search_window=auto_convert(os.environ.get("PARAM_SEARCH_WINDOW", "100")),
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
    "function": "design_primer",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("design_primer_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("design_primer_output.txt", "w") as f:
    f.write("Biomni: Design Primer" + NL)
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
        biomni_function: "design_primer"
    END_VERSIONS
    """
}

workflow DESIGN_PRIMER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DESIGN_PRIMER(ch_input)

    emit:
    results = DESIGN_PRIMER.out.results
    output = DESIGN_PRIMER.out.output
    versions = DESIGN_PRIMER.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DESIGN_PRIMER_WORKFLOW(ch_input)

    DESIGN_PRIMER_WORKFLOW.out.output.view { "Output: $it" }
}
