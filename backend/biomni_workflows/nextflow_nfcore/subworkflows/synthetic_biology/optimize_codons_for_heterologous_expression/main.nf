#!/usr/bin/env nextflow
/*
 * synthetic_biology/optimize_codons_for_heterologous_expression
 * Analyzes and optimizes a DNA/RNA sequence for improved expression in a heterologous host organism.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: GFP coding sequence fragment for E. coli expression
params.target_sequence = 'ATGAGTAAAGGAGAAGAACTTTTCACTGGAGTTGTCCCAATTCTTGTTGAATTAGATGGTGATGTTAATGGGCACAAATTTTCTGTCAGTGGAGAGGGTGAAGGTGATGCAACATACGGAAAACTTACCCTTAAATTTATTTGCACTACTGGAAAACTACCTGTTCCATGG'
// E. coli codon usage table (subset)
params.host_codon_usage = '{"TTT": 0.58, "TTC": 0.42, "TTA": 0.14, "TTG": 0.13, "CTT": 0.12, "CTC": 0.10, "CTA": 0.04, "CTG": 0.47, "ATT": 0.49, "ATC": 0.39, "ATA": 0.11, "ATG": 1.00, "GTT": 0.28, "GTC": 0.20, "GTA": 0.17, "GTG": 0.35}'

process OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("optimize_codons_for_heterologous_expression_results.json"), emit: results
    tuple val(meta), path("optimize_codons_for_heterologous_expression_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TARGET_SEQUENCE="${params.target_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_HOST_CODON_USAGE="${params.host_codon_usage?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def optimize_codons_for_heterologous_expression(target_sequence, host_codon_usage):
    '''Analyzes and optimizes a DNA/RNA sequence for improved expression in a heterologous host organism.

    Parameters
    ----------
    target_sequence : str
        The DNA or RNA sequence of the target gene to be optimized.
        Should contain complete codons (length divisible by 3).

    host_codon_usage : dict
        Dictionary mapping codons to their usage frequency in the host organism.
        Format: {'AUG': 0.8, 'GCC': 0.6, ...} or {'ATG': 0.8, 'GCC': 0.6, ...}

    Returns
    -------
    str
        A research log summarizing the optimization process and results.

    '''
    from Bio.Data import CodonTable

    # Validate inputs
    if target_sequence is None:
        return "Error: target_sequence is required"
    if not isinstance(target_sequence, str):
        target_sequence = str(target_sequence)

    # Ensure host_codon_usage is a dict
    if host_codon_usage is None or not isinstance(host_codon_usage, dict):
        # Use default E. coli codon usage as fallback
        host_codon_usage = {
            'TTT': 0.58, 'TTC': 0.42, 'TTA': 0.14, 'TTG': 0.13,
            'CTT': 0.12, 'CTC': 0.10, 'CTA': 0.04, 'CTG': 0.47,
            'ATT': 0.49, 'ATC': 0.39, 'ATA': 0.11, 'ATG': 1.00,
            'GTT': 0.28, 'GTC': 0.20, 'GTA': 0.17, 'GTG': 0.35,
            'TCT': 0.17, 'TCC': 0.15, 'TCA': 0.14, 'TCG': 0.14,
            'CCT': 0.18, 'CCC': 0.13, 'CCA': 0.20, 'CCG': 0.49,
            'ACT': 0.19, 'ACC': 0.40, 'ACA': 0.17, 'ACG': 0.25,
            'GCT': 0.18, 'GCC': 0.26, 'GCA': 0.23, 'GCG': 0.33,
            'TAT': 0.59, 'TAC': 0.41, 'TAA': 0.61, 'TAG': 0.09,
            'CAT': 0.57, 'CAC': 0.43, 'CAA': 0.34, 'CAG': 0.66,
            'AAT': 0.49, 'AAC': 0.51, 'AAA': 0.74, 'AAG': 0.26,
            'GAT': 0.63, 'GAC': 0.37, 'GAA': 0.68, 'GAG': 0.32,
            'TGT': 0.46, 'TGC': 0.54, 'TGA': 0.30, 'TGG': 1.00,
            'CGT': 0.36, 'CGC': 0.36, 'CGA': 0.07, 'CGG': 0.11,
            'AGT': 0.16, 'AGC': 0.25, 'AGA': 0.07, 'AGG': 0.04,
            'GGT': 0.35, 'GGC': 0.37, 'GGA': 0.13, 'GGG': 0.15,
        }

    # Initialize research log
    log = "# Codon Optimization Analysis Research Log\\n\\n"

    # Check if sequence is DNA or RNA and standardize to DNA
    is_rna = "U" in target_sequence
    working_seq = target_sequence.replace("U", "T") if is_rna else target_sequence

    log += "## Input Sequence Analysis\\n"
    log += f"- Sequence type: {'RNA' if is_rna else 'DNA'}\\n"
    log += f"- Sequence length: {len(working_seq)} nucleotides\\n"

    # Verify sequence length is divisible by 3
    if len(working_seq) % 3 != 0:
        log += (
            f"- WARNING: Sequence length ({len(working_seq)}) is not divisible by 3. Optimization may be incomplete.\\n"
        )

    # Extract codons from the sequence
    original_codons = [working_seq[i : i + 3] for i in range(0, len(working_seq), 3)]
    log += f"- Number of codons: {len(original_codons)}\\n\\n"

    # Get standard genetic code
    standard_table = CodonTable.standard_dna_table

    # Create codon to amino acid mapping
    codon_to_aa = {}
    for codon, amino_acid in standard_table.forward_table.items():
        codon_to_aa[codon] = amino_acid

    # Add stop codons
    for stop_codon in standard_table.stop_codons:
        codon_to_aa[stop_codon] = "*"  # * represents stop codon

    # Create amino acid to codon mapping with host frequencies
    aa_to_codons = {}
    for codon, aa in codon_to_aa.items():
        if aa not in aa_to_codons:
            aa_to_codons[aa] = []
        # Use host frequency or default to 0 if not provided
        frequency = host_codon_usage.get(codon, 0)
        aa_to_codons[aa].append((codon, frequency))

    # Sort codons by frequency for each amino acid
    for aa in aa_to_codons:
        aa_to_codons[aa] = sorted(aa_to_codons[aa], key=lambda x: x[1], reverse=True)

    # Optimize codons
    optimized_codons = []
    for codon in original_codons:
        try:
            aa = codon_to_aa[codon]
            # Select the highest frequency codon for this amino acid
            best_codon = aa_to_codons[aa][0][0] if aa_to_codons[aa] else codon
            optimized_codons.append(best_codon)
        except KeyError:
            # If codon not in standard table, keep original
            optimized_codons.append(codon)
            log += f"- WARNING: Non-standard codon detected: {codon}. Keeping original.\\n"

    # Combine optimized codons into sequence
    optimized_sequence = "".join(optimized_codons)

    # Convert back to RNA if input was RNA
    if is_rna:
        optimized_sequence = optimized_sequence.replace("T", "U")

    # Calculate optimization statistics
    codon_changes = sum(1 for i, j in zip(original_codons, optimized_codons, strict=False) if i != j)
    percent_changed = (codon_changes / len(original_codons)) * 100 if original_codons else 0

    log += "## Optimization Results\\n"
    log += f"- Codons modified: {codon_changes} out of {len(original_codons)} ({percent_changed:.2f}%)\\n"

    # Save sequences to files
    with open("original_sequence.txt", "w") as f:
        f.write(target_sequence)

    with open("optimized_sequence.txt", "w") as f:
        f.write(optimized_sequence)

    log += "- Original sequence saved to: original_sequence.txt\\n"
    log += "- Optimized sequence saved to: optimized_sequence.txt\\n\\n"

    # Add summary
    log += "## Summary\\n"
    log += "The target gene sequence has been optimized for expression in the provided host organism. "
    log += f"The optimization process replaced {codon_changes} codons ({percent_changed:.2f}%) "
    log += "with synonymous codons that have higher usage frequency in the host.\\n"

    return log

# Execute the function
try:
    result = optimize_codons_for_heterologous_expression(
        target_sequence=auto_convert(os.environ.get("PARAM_TARGET_SEQUENCE", "")),
        host_codon_usage=auto_convert(os.environ.get("PARAM_HOST_CODON_USAGE", "")),
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
    "function": "optimize_codons_for_heterologous_expression",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("optimize_codons_for_heterologous_expression_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("optimize_codons_for_heterologous_expression_output.txt", "w") as f:
    f.write("Biomni: Optimize Codons For Heterologous Expression" + NL)
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
        biomni_function: "optimize_codons_for_heterologous_expression"
    END_VERSIONS
    """
}

workflow OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION(ch_input)

    emit:
    results = OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION.out.results
    output = OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION.out.output
    versions = OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION_WORKFLOW(ch_input)

    OPTIMIZE_CODONS_FOR_HETEROLOGOUS_EXPRESSION_WORKFLOW.out.output.view { "Output: $it" }
}
