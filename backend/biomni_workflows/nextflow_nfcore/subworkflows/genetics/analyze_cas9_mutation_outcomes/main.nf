#!/usr/bin/env nextflow
/*
 * genetics/analyze_cas9_mutation_outcomes
 * Analyzes and categorizes mutations induced by Cas9 at target sites.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Cas9 editing of TP53 gene target site
params.reference_sequences = '{"TP53_site1": "ATGCTAGCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAG", "TP53_site2": "GCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAGCTAGC"}'
params.edited_sequences = '{"TP53_site1": {"read1": "ATGCTAGCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAG", "read2": "ATGCTAGCTA---AGCTAGCATGCTAGCTAGCTAGCTAG", "read3": "ATGCTAGCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAG", "read4": "ATGCTAGCTAGATTAGCTAGCATGCTAGCTAGCTAGCTAG"}, "TP53_site2": {"read1": "GCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAGCTAGC", "read2": "GCTAGCTA---GCATGCTAGCTAGCTAGCTAGCTAGC"}}'
params.cell_line_info = '{"TP53_site1": "HEK293T", "TP53_site2": "HEK293T"}'
params.output_prefix = 'cas9_mutation_analysis'

process ANALYZE_CAS9_MUTATION_OUTCOMES {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_cas9_mutation_outcomes_results.json"), emit: results
    tuple val(meta), path("analyze_cas9_mutation_outcomes_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_REFERENCE_SEQUENCES="${params.reference_sequences?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EDITED_SEQUENCES="${params.edited_sequences?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CELL_LINE_INFO="${params.cell_line_info?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PREFIX="${params.output_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
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



def analyze_cas9_mutation_outcomes(
    reference_sequences,
    edited_sequences,
    cell_line_info=None,
    output_prefix="cas9_mutation_analysis",
):
    '''Analyzes and categorizes mutations induced by Cas9 at target sites.

    Parameters
    ----------
    reference_sequences : dict
        Dictionary mapping sequence IDs to reference DNA sequences (strings)
    edited_sequences : dict of dict
        Nested dictionary: {sequence_id: {read_id: sequence}}
        Contains the edited/mutated sequences for each reference
    cell_line_info : dict, optional
        Dictionary mapping sequence IDs to cell line information (e.g., wildtype, knockout gene)
    output_prefix : str, optional
        Prefix for output files

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    from collections import defaultdict

    from Bio import pairwise2

    # Initialize results storage
    results = []
    mutation_counts = defaultdict(lambda: defaultdict(int))

    # Define mutation categories
    categories = {
        "no_mutation": "No mutation detected",
        "short_deletion": "Short deletion (1-10 bp)",
        "medium_deletion": "Medium deletion (11-30 bp)",
        "long_deletion": "Long deletion (>30 bp)",
        "single_insertion": "Single base insertion",
        "longer_insertion": "Longer insertion (>1 bp)",
        "indel": "Insertion and deletion",
    }

    log = "# Cas9-Induced Mutation Outcome Analysis\\n\\n"
    log += "## Analysis Steps:\\n\\n"
    log += "1. Loading and processing sequence data\\n"
    log += f"2. Analyzing {len(reference_sequences)} target sites\\n"

    # Process each reference sequence and its edited versions
    for seq_id, ref_seq in reference_sequences.items():
        cell_line = cell_line_info.get(seq_id, "Unknown") if cell_line_info else "Unknown"
        log += f"\\n### Processing target site: {seq_id} (Cell line: {cell_line})\\n"

        site_results = []
        site_mutation_counts = defaultdict(int)
        total_reads = len(edited_sequences.get(seq_id, {}))

        if total_reads == 0:
            log += f"No edited sequences found for {seq_id}\\n"
            continue

        log += f"Analyzing {total_reads} sequence reads...\\n"

        # Process each edited sequence for this reference
        for read_id, edited_seq in edited_sequences.get(seq_id, {}).items():
            # Perform sequence alignment
            alignments = pairwise2.align.globalms(ref_seq, edited_seq, 2, -1, -2, -0.5)

            if not alignments:
                log += f"Warning: Could not align read {read_id}\\n"
                continue

            best_alignment = alignments[0]
            ref_aligned, edited_aligned, score, start, end = best_alignment

            # Analyze mutations
            deletions = []
            insertions = []
            del_count = 0
            ins_count = 0

            i, j = 0, 0
            while i < len(ref_aligned) and j < len(edited_aligned):
                if ref_aligned[i] == "-":  # Insertion in edited sequence
                    ins_start = j
                    while i < len(ref_aligned) and ref_aligned[i] == "-":
                        i += 1
                        j += 1
                    insertions.append((ins_start, j - ins_start))
                    ins_count += j - ins_start
                elif edited_aligned[j] == "-":  # Deletion in edited sequence
                    del_start = i
                    while j < len(edited_aligned) and edited_aligned[j] == "-":
                        i += 1
                        j += 1
                    deletions.append((del_start, i - del_start))
                    del_count += i - del_start
                else:
                    i += 1
                    j += 1

            # Categorize mutation
            mutation_type = "no_mutation"
            if del_count > 0 and ins_count > 0:
                mutation_type = "indel"
            elif del_count > 0:
                if del_count <= 10:
                    mutation_type = "short_deletion"
                elif del_count <= 30:
                    mutation_type = "medium_deletion"
                else:
                    mutation_type = "long_deletion"
            elif ins_count > 0:
                mutation_type = "single_insertion" if ins_count == 1 else "longer_insertion"

            # Add to results
            site_results.append(
                {
                    "sequence_id": seq_id,
                    "read_id": read_id,
                    "cell_line": cell_line,
                    "mutation_type": mutation_type,
                    "deletion_count": del_count,
                    "insertion_count": ins_count,
                }
            )

            site_mutation_counts[mutation_type] += 1
            mutation_counts[cell_line][mutation_type] += 1

        # Calculate percentages for this site
        log += "\\nMutation distribution for this target site:\\n"
        for mut_type, count in site_mutation_counts.items():
            percentage = (count / total_reads) * 100
            log += f"- {categories[mut_type]}: {count} reads ({percentage:.1f}%)\\n"

        # Add site results to overall results
        results.extend(site_results)

    # Create results dataframe and save to CSV
    results_df = pd.DataFrame(results)
    output_file = f"{output_prefix}_detailed_results.csv"
    results_df.to_csv(output_file, index=False)

    # Create summary dataframe
    summary_data = []
    for cell_line, mut_counts in mutation_counts.items():
        total = sum(mut_counts.values())
        for mut_type, count in mut_counts.items():
            percentage = (count / total) * 100 if total > 0 else 0
            summary_data.append(
                {
                    "cell_line": cell_line,
                    "mutation_type": mut_type,
                    "count": count,
                    "percentage": percentage,
                }
            )

    summary_df = pd.DataFrame(summary_data)
    summary_file = f"{output_prefix}_summary.csv"
    summary_df.to_csv(summary_file, index=False)

    # Add summary to log
    log += "\\n## Overall Results Summary\\n\\n"
    log += f"Total sequences analyzed: {len(results)}\\n"
    log += f"Detailed results saved to: {output_file}\\n"
    log += f"Summary results saved to: {summary_file}\\n\\n"

    if cell_line_info:
        log += "### Mutation Distribution by Cell Line\\n\\n"
        for cell_line, mut_counts in mutation_counts.items():
            total = sum(mut_counts.values())
            if total == 0:
                continue

            log += f"#### {cell_line}\\n"
            for mut_type, count in sorted(mut_counts.items(), key=lambda x: x[1], reverse=True):
                percentage = (count / total) * 100
                log += f"- {categories[mut_type]}: {count} ({percentage:.1f}%)\\n"
            log += "\\n"

    return log

# Execute the function
try:
    result = analyze_cas9_mutation_outcomes(
        reference_sequences=auto_convert(os.environ.get("PARAM_REFERENCE_SEQUENCES", "")),
        edited_sequences=auto_convert(os.environ.get("PARAM_EDITED_SEQUENCES", "")),
        cell_line_info=auto_convert(os.environ.get("PARAM_CELL_LINE_INFO", "")),
        output_prefix=auto_convert(os.environ.get("PARAM_OUTPUT_PREFIX", "cas9_mutation_analysis")),
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
    "function": "analyze_cas9_mutation_outcomes",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_cas9_mutation_outcomes_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_cas9_mutation_outcomes_output.txt", "w") as f:
    f.write("Biomni: Analyze Cas9 Mutation Outcomes" + NL)
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
        biomni_function: "analyze_cas9_mutation_outcomes"
    END_VERSIONS
    """
}

workflow ANALYZE_CAS9_MUTATION_OUTCOMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CAS9_MUTATION_OUTCOMES(ch_input)

    emit:
    results = ANALYZE_CAS9_MUTATION_OUTCOMES.out.results
    output = ANALYZE_CAS9_MUTATION_OUTCOMES.out.output
    versions = ANALYZE_CAS9_MUTATION_OUTCOMES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CAS9_MUTATION_OUTCOMES_WORKFLOW(ch_input)

    ANALYZE_CAS9_MUTATION_OUTCOMES_WORKFLOW.out.output.view { "Output: $it" }
}
