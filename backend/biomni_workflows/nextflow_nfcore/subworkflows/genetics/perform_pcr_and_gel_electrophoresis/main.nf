#!/usr/bin/env nextflow
/*
 * genetics/perform_pcr_and_gel_electrophoresis
 * Performs PCR amplification of a target transgene and visualizes results using agarose gel electrophoresis.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PCR amplification of EGFR exon 19 region for mutation detection
params.genomic_dna = 'ATGCGACCCTCCGGGACGGCCGGGGCAGCGCTCCTGGCGCTGCTGGCTGCGCTCTGCCCGGCGAGTCGGGCTCTGGAGGAAAAGAAAGTTTGCCAAGGCACGAGTAACAAGCTCACGCAGTTGGGCACTTTTGAAGATCATTTTCTCAGCCTCCAGAGGATGTTCAATAACTGTGAGGTGGTCCTTGGGAATTTGGAAATTACCTATGTGCAGAGGAATTATGATCTTTCCTTCTTAAAGACCATCCAGGAGGTGGCTGGTTATGTCCTCATTGCCCTCAACACAGTGGAGCGAATTCCTTTGGAAAACCTGCAGATCATCAGAGGAAATATGTACTACGAAAATTCCTATGCCTTAGCAGTCTTATCTAACTATGATGCAAATAAAACCGGACTGAAGGAGCTGCCCATG'
params.forward_primer = 'ATGCGACCCTCCGGGACGGC'
params.reverse_primer = 'CATGGGCAGCTCCTTCAGTC'
params.target_region = '[50, 350]'
params.annealing_temp = '58'
params.extension_time = '30'
params.cycles = '35'
params.gel_percentage = '2.0'
params.output_prefix = 'pcr_result'

process PERFORM_PCR_AND_GEL_ELECTROPHORESIS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_pcr_and_gel_electrophoresis_results.json"), emit: results
    tuple val(meta), path("perform_pcr_and_gel_electrophoresis_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENOMIC_DNA="${params.genomic_dna?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FORWARD_PRIMER="${params.forward_primer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REVERSE_PRIMER="${params.reverse_primer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_REGION="${params.target_region?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ANNEALING_TEMP="${params.annealing_temp?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EXTENSION_TIME="${params.extension_time?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CYCLES="${params.cycles?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GEL_PERCENTAGE="${params.gel_percentage?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PREFIX="${params.output_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
from datetime import datetime
import numpy as np
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



def perform_pcr_and_gel_electrophoresis(
    genomic_dna,
    forward_primer=None,
    reverse_primer=None,
    target_region=None,
    annealing_temp=58,
    extension_time=30,
    cycles=35,
    gel_percentage=2.0,
    output_prefix="pcr_result",
):
    '''Performs PCR amplification of a target transgene and visualizes results using agarose gel electrophoresis.

    Parameters
    ----------
    genomic_dna : str
        Path to file containing genomic DNA sequence in FASTA format or the sequence itself
    forward_primer : str, optional
        Forward primer sequence. If not provided, will be designed based on target_region
    reverse_primer : str, optional
        Reverse primer sequence. If not provided, will be designed based on target_region
    target_region : tuple, optional
        Tuple of (start, end) positions for the target region in the genomic DNA
    annealing_temp : float, default=58
        Annealing temperature for PCR in °C
    extension_time : int, default=30
        Extension time in seconds
    cycles : int, default=35
        Number of PCR cycles
    gel_percentage : float, default=2.0
        Percentage of agarose gel
    output_prefix : str, default="pcr_result"
        Prefix for output files

    Returns
    -------
    str
        Research log summarizing the PCR and gel electrophoresis procedures and results

    '''
    import datetime

    import matplotlib.pyplot as plt
    import numpy as np
    from Bio import SeqIO
    from Bio.Seq import Seq

    log = f"PCR AMPLIFICATION AND GEL ELECTROPHORESIS LOG - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}\\n"
    log += "=" * 80 + "\\n\\n"

    # Step 1: Load the genomic DNA
    log += "STEP 1: PREPARING GENOMIC DNA\\n"
    if os.path.isfile(genomic_dna):
        try:
            record = SeqIO.read(genomic_dna, "fasta")
            dna_sequence = str(record.seq)
            log += f"- Loaded genomic DNA from file: {genomic_dna}\\n"
            log += f"- Sequence length: {len(dna_sequence)} bp\\n"
        except Exception as e:
            log += f"- Error loading DNA file: {str(e)}\\n"
            return log
    else:
        dna_sequence = genomic_dna
        log += "- Using provided DNA sequence\\n"
        log += f"- Sequence length: {len(dna_sequence)} bp\\n"

    log += "\\n"

    # Step 2: Design or validate primers
    log += "STEP 2: PCR PRIMER PREPARATION\\n"

    if forward_primer is None or reverse_primer is None:
        if target_region is None:
            log += "- Error: Either primers or target region must be provided\\n"
            return log

        # Simple primer design based on target region
        start, end = target_region

        if forward_primer is None:
            # Take 20bp from the start of the target region for forward primer
            forward_primer = dna_sequence[start : start + 20]
            log += "- Designed forward primer based on target region\\n"

        if reverse_primer is None:
            # Take 20bp from the end of the target region for reverse primer (reverse complement)
            reverse_seq = Seq(dna_sequence[end - 20 : end])
            reverse_primer = str(reverse_seq.reverse_complement())
            log += "- Designed reverse primer based on target region\\n"

    log += f"- Forward primer: 5'-{forward_primer}-3' ({len(forward_primer)} bp)\\n"
    log += f"- Reverse primer: 5'-{reverse_primer}-3' ({len(reverse_primer)} bp)\\n"

    # Step 3: PCR Setup and Amplification
    log += "\\nSTEP 3: PCR AMPLIFICATION\\n"
    log += "- PCR reaction setup:\\n"
    log += "  * Template DNA: Genomic DNA\\n"
    log += f"  * Forward primer: 5'-{forward_primer}-3'\\n"
    log += f"  * Reverse primer: 5'-{reverse_primer}-3'\\n"
    log += f"  * Annealing temperature: {annealing_temp}°C\\n"
    log += f"  * Extension time: {extension_time} seconds\\n"
    log += f"  * Number of cycles: {cycles}\\n"

    # Simulate PCR by finding binding sites and determining amplicon size
    amplicon_size = None
    amplicon_sequence = None

    # Find forward primer binding site
    fwd_pos = dna_sequence.find(forward_primer)
    if fwd_pos == -1:
        log += "- Warning: Forward primer binding site not found in sequence\\n"

    # Find reverse primer binding site (need to search for reverse complement)
    rev_primer_seq = Seq(reverse_primer)
    rev_primer_rc = str(rev_primer_seq.reverse_complement())
    rev_pos = dna_sequence.find(rev_primer_rc)
    if rev_pos == -1:
        log += "- Warning: Reverse primer binding site not found in sequence\\n"

    # If we found both binding sites, calculate amplicon size
    if fwd_pos != -1 and rev_pos != -1:
        if fwd_pos < rev_pos:
            amplicon_size = rev_pos + len(reverse_primer) - fwd_pos
            amplicon_sequence = dna_sequence[fwd_pos : rev_pos + len(reverse_primer)]
            log += "- PCR amplification successful\\n"
            log += f"- Amplicon size: {amplicon_size} bp\\n"
        else:
            log += "- Error: Primer binding sites are in incorrect orientation\\n"
    # Simulate based on target region if provided
    elif target_region is not None:
        start, end = target_region
        amplicon_size = end - start + len(forward_primer) + len(reverse_primer)
        log += "- PCR amplification simulated based on target region\\n"
        log += f"- Expected amplicon size: {amplicon_size} bp\\n"
    else:
        log += "- PCR amplification failed: could not determine amplicon size\\n"
        return log

    # Step 4: Gel Electrophoresis
    log += "\\nSTEP 4: AGAROSE GEL ELECTROPHORESIS\\n"
    log += f"- Prepared {gel_percentage}% agarose gel\\n"
    log += "- Loaded PCR product alongside DNA ladder\\n"
    log += "- Ran electrophoresis at 100V for 45 minutes\\n"

    # Create a simulated gel image
    fig, ax = plt.subplots(figsize=(6, 8))

    # Draw gel lanes
    ax.add_patch(plt.Rectangle((0, 0), 6, 10, color="lightgray", alpha=0.5))

    # DNA Ladder (100bp increments)
    ladder_sizes = [100, 200, 300, 500, 700, 1000, 1500, 2000]
    ladder_positions = [10 - (np.log(size) / np.log(2000) * 8) for size in ladder_sizes]

    # Plot ladder
    for pos, size in zip(ladder_positions, ladder_sizes, strict=False):
        ax.add_patch(plt.Rectangle((0.5, pos - 0.1), 1, 0.2, color="black", alpha=0.8))
        ax.text(0.2, pos, f"{size}bp", fontsize=8, ha="right", va="center")

    # Plot sample band
    if amplicon_size:
        sample_position = 10 - (np.log(amplicon_size) / np.log(2000) * 8)
        ax.add_patch(plt.Rectangle((3.5, sample_position - 0.15), 1, 0.3, color="black", alpha=0.8))
        ax.text(
            4.5,
            sample_position,
            f"{amplicon_size}bp",
            fontsize=8,
            ha="left",
            va="center",
        )

    # Set up the plot
    ax.set_xlim(0, 6)
    ax.set_ylim(0, 10)
    ax.set_xticks([0.5, 3.5])
    ax.set_xticklabels(["Ladder", "Sample"])
    ax.set_yticks([])
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.spines["left"].set_visible(False)
    ax.set_title(f"{gel_percentage}% Agarose Gel")

    # Save the gel image
    gel_image_path = f"{output_prefix}_gel.png"
    plt.savefig(gel_image_path, dpi=300, bbox_inches="tight")
    plt.close()

    log += f"- Gel image saved as: {gel_image_path}\\n"

    # Results interpretation
    log += "\\nRESULTS INTERPRETATION:\\n"
    if amplicon_size:
        log += f"- Detected band at approximately {amplicon_size} bp\\n"

        # Save amplicon sequence if available
        if amplicon_sequence:
            seq_file = f"{output_prefix}_amplicon.fasta"
            with open(seq_file, "w") as f:
                f.write(f">PCR_Amplicon_{amplicon_size}bp\\n")
                f.write(amplicon_sequence)
            log += f"- Amplicon sequence saved as: {seq_file}\\n"
    else:
        log += "- No bands detected\\n"

    return log

# Execute the function
try:
    result = perform_pcr_and_gel_electrophoresis(
        genomic_dna=auto_convert(os.environ.get("PARAM_GENOMIC_DNA", "")),
        forward_primer=auto_convert(os.environ.get("PARAM_FORWARD_PRIMER", "")),
        reverse_primer=auto_convert(os.environ.get("PARAM_REVERSE_PRIMER", "")),
        target_region=auto_convert(os.environ.get("PARAM_TARGET_REGION", "")),
        annealing_temp=auto_convert(os.environ.get("PARAM_ANNEALING_TEMP", "58")),
        extension_time=auto_convert(os.environ.get("PARAM_EXTENSION_TIME", "30")),
        cycles=auto_convert(os.environ.get("PARAM_CYCLES", "35")),
        gel_percentage=auto_convert(os.environ.get("PARAM_GEL_PERCENTAGE", "2.0")),
        output_prefix=auto_convert(os.environ.get("PARAM_OUTPUT_PREFIX", "pcr_result")),
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
    "function": "perform_pcr_and_gel_electrophoresis",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_pcr_and_gel_electrophoresis_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_pcr_and_gel_electrophoresis_output.txt", "w") as f:
    f.write("Biomni: Perform Pcr And Gel Electrophoresis" + NL)
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
        biomni_function: "perform_pcr_and_gel_electrophoresis"
    END_VERSIONS
    """
}

workflow PERFORM_PCR_AND_GEL_ELECTROPHORESIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_PCR_AND_GEL_ELECTROPHORESIS(ch_input)

    emit:
    results = PERFORM_PCR_AND_GEL_ELECTROPHORESIS.out.results
    output = PERFORM_PCR_AND_GEL_ELECTROPHORESIS.out.output
    versions = PERFORM_PCR_AND_GEL_ELECTROPHORESIS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_PCR_AND_GEL_ELECTROPHORESIS_WORKFLOW(ch_input)

    PERFORM_PCR_AND_GEL_ELECTROPHORESIS_WORKFLOW.out.output.view { "Output: $it" }
}
