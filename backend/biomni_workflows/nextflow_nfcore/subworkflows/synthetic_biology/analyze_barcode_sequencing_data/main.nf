#!/usr/bin/env nextflow
/*
 * synthetic_biology/analyze_barcode_sequencing_data
 * Analyze sequencing data to extract, quantify and determine lineage relationships of barcodes.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: use inline-generated FASTA with barcodes
params.input_file = 'test_barcodes.fasta'
params.barcode_pattern = 'ATCG[ATCG]{8}GCTA'
params.flanking_seq_5prime = 'ATCG'
params.flanking_seq_3prime = 'GCTA'
params.min_count = '2'
params.output_dir = './results'

process ANALYZE_BARCODE_SEQUENCING_DATA {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_barcode_sequencing_data_results.json"), emit: results
    tuple val(meta), path("analyze_barcode_sequencing_data_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Create mock FASTA file with barcoded sequences for testing
    cat > test_barcodes.fasta << 'FASTAEOF'
>seq1
AAAAAATCGACGTACGTGCTATTTTTT
>seq2
AAAAAATCGACGTACGTGCTATTTTTT
>seq3
AAAAAATCGACGTACGTGCTATTTTTT
>seq4
AAAAAATCGACGTACGTGCTATTTTTT
>seq5
AAAAAATCGACGTACGTGCTATTTTTT
>seq6
AAAAAATCGTTTTAAAAGCTATTTTTT
>seq7
AAAAAATCGTTTTAAAAGCTATTTTTT
>seq8
AAAAAATCGTTTTAAAAGCTATTTTTT
>seq9
AAAAAATCGGGGGCCCCGCTATTTTTT
>seq10
AAAAAATCGGGGGCCCCGCTATTTTTT
FASTAEOF

    # Export parameters as environment variables
    export PARAM_INPUT_FILE="${params.input_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BARCODE_PATTERN="${params.barcode_pattern?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FLANKING_SEQ_5PRIME="${params.flanking_seq_5prime?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FLANKING_SEQ_3PRIME="${params.flanking_seq_3prime?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_COUNT="${params.min_count?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_barcode_sequencing_data(
    input_file,
    barcode_pattern=None,
    flanking_seq_5prime=None,
    flanking_seq_3prime=None,
    min_count=5,
    output_dir="./results",
):
    '''Analyze sequencing data to extract, quantify and determine lineage relationships of barcodes.

    Parameters
    ----------
    input_file : str
        Path to the input sequencing file in FASTQ or FASTA format
    barcode_pattern : str, optional
        Regular expression pattern to identify barcodes. If None, will use flanking sequences
    flanking_seq_5prime : str, optional
        5' flanking sequence of the barcode region
    flanking_seq_3prime : str, optional
        3' flanking sequence of the barcode region
    min_count : int, default=5
        Minimum count threshold for considering a barcode
    output_dir : str, default="./results"
        Directory to save output files

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    import re
    from collections import Counter

    import numpy as np
    from Bio import SeqIO
    from scipy.cluster.hierarchy import fcluster, linkage
    from scipy.spatial.distance import pdist

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Initialize research log
    log = "# Barcode Sequencing Analysis Research Log\\n\\n"
    log += f"## Input Data\\n- File: {input_file}\\n\\n"

    # Step 1: Read sequences and extract barcodes
    log += "## Step 1: Extracting barcodes from sequencing data\\n"

    # Determine file format based on extension
    file_format = "fastq" if input_file.endswith((".fastq", ".fq")) else "fasta"

    barcodes = []
    total_reads = 0

    for record in SeqIO.parse(input_file, file_format):
        total_reads += 1
        seq_str = str(record.seq)

        # Extract barcode using pattern or flanking sequences
        if barcode_pattern:
            match = re.search(barcode_pattern, seq_str)
            if match:
                barcodes.append(match.group(0))
        elif flanking_seq_5prime and flanking_seq_3prime:
            pattern = f"{flanking_seq_5prime}(.*?){flanking_seq_3prime}"
            match = re.search(pattern, seq_str)
            if match:
                barcodes.append(match.group(1))

    log += f"- Total reads processed: {total_reads}\\n"
    log += f"- Barcodes extracted: {len(barcodes)}\\n\\n"

    if len(barcodes) == 0:
        log += "ERROR: No barcodes found. Check your barcode pattern or flanking sequences.\\n"
        return log

    # Step 2: Quantify barcode abundances
    log += "## Step 2: Quantifying barcode abundances\\n"
    barcode_counts = Counter(barcodes)

    # Filter low-abundance barcodes
    filtered_barcodes = {bc: count for bc, count in barcode_counts.items() if count >= min_count}

    log += f"- Unique barcodes: {len(barcode_counts)}\\n"
    log += f"- Barcodes with count ≥ {min_count}: {len(filtered_barcodes)}\\n"

    # Save barcode counts to file
    count_file = os.path.join(output_dir, "barcode_counts.tsv")
    with open(count_file, "w") as f:
        f.write("Barcode\\tCount\\tFrequency\\n")
        for bc, count in sorted(filtered_barcodes.items(), key=lambda x: x[1], reverse=True):
            freq = count / total_reads
            f.write(f"{bc}\\t{count}\\t{freq:.6f}\\n")

    log += f"- Barcode abundances saved to: {count_file}\\n\\n"

    # Step 3: Analyze barcode relationships (lineage analysis)
    log += "## Step 3: Analyzing barcode relationships and lineages\\n"

    # Only proceed if we have enough barcodes
    if len(filtered_barcodes) < 2:
        log += "- Not enough barcodes for lineage analysis after filtering\\n\\n"
    else:
        # Convert barcodes to numerical representation for distance calculation
        barcode_list = list(filtered_barcodes.keys())

        # Create a simple distance matrix based on Hamming distance
        def hamming_distance(s1, s2):
            # If sequences have different lengths, pad the shorter one
            if len(s1) != len(s2):
                max_len = max(len(s1), len(s2))
                s1 = s1.ljust(max_len)
                s2 = s2.ljust(max_len)
            return sum(c1 != c2 for c1, c2 in zip(s1, s2, strict=False))

        # Create distance matrix
        n = len(barcode_list)
        dist_matrix = np.zeros((n, n))
        for i in range(n):
            for j in range(i + 1, n):
                dist = hamming_distance(barcode_list[i], barcode_list[j])
                dist_matrix[i, j] = dist
                dist_matrix[j, i] = dist

        # Perform hierarchical clustering
        try:
            condensed_dist = pdist(dist_matrix)
            Z = linkage(condensed_dist, method="average")
            max_dist = 3  # Max Hamming distance to consider barcodes in same lineage
            clusters = fcluster(Z, max_dist, criterion="distance")

            # Count clusters
            cluster_counts = Counter(clusters)

            log += f"- Identified {len(cluster_counts)} potential lineages\\n"
            log += f"- Largest lineage contains {max(cluster_counts.values())} barcodes\\n"

            # Save lineage information
            lineage_file = os.path.join(output_dir, "barcode_lineages.tsv")
            with open(lineage_file, "w") as f:
                f.write("Barcode\\tCount\\tLineage\\n")
                for i, bc in enumerate(barcode_list):
                    f.write(f"{bc}\\t{filtered_barcodes[bc]}\\t{clusters[i]}\\n")

            log += f"- Lineage assignments saved to: {lineage_file}\\n\\n"
        except Exception as e:
            log += f"- Error in lineage analysis: {str(e)}\\n\\n"

    # Step 4: Summary
    log += "## Summary\\n"
    log += f"- Processed {total_reads} sequencing reads\\n"
    log += f"- Identified {len(barcode_counts)} unique barcodes\\n"
    log += f"- {len(filtered_barcodes)} barcodes passed abundance threshold (≥ {min_count})\\n"

    return log

# Execute the function
try:
    result = analyze_barcode_sequencing_data(
        input_file=auto_convert(os.environ.get("PARAM_INPUT_FILE", "")),
        barcode_pattern=auto_convert(os.environ.get("PARAM_BARCODE_PATTERN", "")),
        flanking_seq_5prime=auto_convert(os.environ.get("PARAM_FLANKING_SEQ_5PRIME", "")),
        flanking_seq_3prime=auto_convert(os.environ.get("PARAM_FLANKING_SEQ_3PRIME", "")),
        min_count=auto_convert(os.environ.get("PARAM_MIN_COUNT", "5")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
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
    "function": "analyze_barcode_sequencing_data",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_barcode_sequencing_data_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_barcode_sequencing_data_output.txt", "w") as f:
    f.write("Biomni: Analyze Barcode Sequencing Data" + NL)
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
        biomni_function: "analyze_barcode_sequencing_data"
    END_VERSIONS
    """
}

workflow ANALYZE_BARCODE_SEQUENCING_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_BARCODE_SEQUENCING_DATA(ch_input)

    emit:
    results = ANALYZE_BARCODE_SEQUENCING_DATA.out.results
    output = ANALYZE_BARCODE_SEQUENCING_DATA.out.output
    versions = ANALYZE_BARCODE_SEQUENCING_DATA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_BARCODE_SEQUENCING_DATA_WORKFLOW(ch_input)

    ANALYZE_BARCODE_SEQUENCING_DATA_WORKFLOW.out.output.view { "Output: $it" }
}
