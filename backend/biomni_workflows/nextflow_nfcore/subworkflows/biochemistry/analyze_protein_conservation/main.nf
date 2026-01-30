#!/usr/bin/env nextflow
/*
 * biochemistry/analyze_protein_conservation
 * Perform multiple sequence alignment and phylogenetic analysis to identify conserved protein regions.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Test: Hemoglobin alpha sequences from human, mouse, and chicken
params.protein_sequences = '["MVLSPADKTNVKAAWGKVGAHAGEYGAEALERMFLSFPTTKTYFPHFDLSH", "MVLSGEDKSNIKAAWGKIGGHGAEYGAEALERMFASFPTTKTYFPHFDVSH", "MVLSAADKNNVKGIFTKIAGHAEEYGAETLERMFTTYPPTKTYFPHFDLSH"]'
params.output_dir = './'

process ANALYZE_PROTEIN_CONSERVATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_protein_conservation_results.json"), emit: results
    tuple val(meta), path("analyze_protein_conservation_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PROTEIN_SEQUENCES="${params.protein_sequences?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_protein_conservation(protein_sequences, output_dir="./"):
    '''Perform multiple sequence alignment and phylogenetic analysis to identify conserved protein regions.

    Parameters
    ----------
    protein_sequences : list of str
        List of protein sequences in FASTA format from multiple organisms.
    output_dir : str, optional
        Directory to save output files (default: "./output")

    Returns
    -------
    str
        Research log summarizing the analysis steps and results, including filenames of saved outputs.

    '''
    import os
    import subprocess

    from Bio import AlignIO, Phylo, SeqIO
    from Bio.Phylo.TreeConstruction import DistanceCalculator, DistanceTreeConstructor

    # Create a research log
    log = []
    log.append("# Protein Sequence Alignment and Conservation Analysis")

    # Ensure output directory exists
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Step 1: Save input sequences to a temporary file
    log.append("\\n## Step 1: Preparing Input Sequences")
    input_file = os.path.join(output_dir, "input.fasta")

    # Check if input is already in FASTA format or needs conversion
    if isinstance(protein_sequences, list):
        if all(">" in seq for seq in protein_sequences):
            # Already in FASTA format
            with open(input_file, "w") as f:
                f.write("\\n".join(protein_sequences))
        else:
            # Convert to FASTA format
            with open(input_file, "w") as f:
                for i, seq in enumerate(protein_sequences):
                    f.write(f">Sequence_{i + 1}\\n{seq}\\n")
    else:
        # Assume it's a single string in FASTA format
        with open(input_file, "w") as f:
            f.write(protein_sequences)

    log.append(f"Input sequences saved to {input_file}")
    log.append(f"Number of sequences: {len(list(SeqIO.parse(input_file, 'fasta')))}")

    # Step 2: Perform multiple sequence alignment using MUSCLE
    log.append("\\n## Step 2: Multiple Sequence Alignment")
    aligned_file = os.path.join(output_dir, "aligned.fasta")

    try:
        # Run MUSCLE for multiple sequence alignment using subprocess
        result = subprocess.run(
            ["muscle", "-in", input_file, "-out", aligned_file],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(f"MUSCLE failed: {result.stderr}")
        log.append("Multiple sequence alignment completed using MUSCLE")
        log.append(f"Alignment saved to {aligned_file}")

        # Load the alignment
        alignment = AlignIO.read(aligned_file, "fasta")
        log.append(f"Alignment length: {alignment.get_alignment_length()} positions")

    except Exception as e:
        log.append(f"MUSCLE alignment failed: {str(e)}")
        log.append("Attempting to use Biopython's built-in alignment methods...")

        # Fallback to a simpler approach without pairwise2
        from Bio.Align import MultipleSeqAlignment
        from Bio.Seq import Seq
        from Bio.SeqRecord import SeqRecord

        sequences = list(SeqIO.parse(input_file, "fasta"))

        # Simple approach: just pad sequences to the same length
        max_length = max(len(seq.seq) for seq in sequences)
        alignments = []

        for seq in sequences:
            # Pad sequence to max length
            padded_seq = str(seq.seq).ljust(max_length, "-")
            new_seq = SeqRecord(Seq(padded_seq), id=seq.id, description=seq.description)
            alignments.append(new_seq)

        # Create and save the alignment
        msa = MultipleSeqAlignment(alignments)
        AlignIO.write(msa, aligned_file, "fasta")
        alignment = msa
        log.append("Simple padding alignment completed as fallback method")
        log.append(f"Alignment saved to {aligned_file}")

    # Step 3: Generate a phylogenetic tree
    log.append("\\n## Step 3: Phylogenetic Analysis")
    tree_file = os.path.join(output_dir, "tree.newick")

    # Calculate distance matrix
    calculator = DistanceCalculator("identity")
    dm = calculator.get_distance(alignment)

    # Construct the phylogenetic tree using neighbor-joining method
    constructor = DistanceTreeConstructor()
    tree = constructor.nj(dm)

    # Save the tree
    Phylo.write(tree, tree_file, "newick")
    log.append("Phylogenetic tree constructed using neighbor-joining method")
    log.append(f"Tree saved to {tree_file}")

    # Step 4: Analyze conserved regions
    log.append("\\n## Step 4: Conservation Analysis")
    conservation_file = os.path.join(output_dir, "conservation.txt")

    # Simple conservation analysis
    alignment_length = alignment.get_alignment_length()
    conserved_positions = []

    with open(conservation_file, "w") as f:
        f.write("Position\\tConservation_Score\\tConsensus\\n")

        for i in range(alignment_length):
            # Get all amino acids at this position
            column = alignment[:, i]
            set(column)

            # Calculate a simple conservation score (percentage of most common AA)
            most_common_aa = max(column, key=column.count)
            conservation_score = column.count(most_common_aa) / len(column)

            f.write(f"{i + 1}\\t{conservation_score:.2f}\\t{most_common_aa}\\n")

            # Consider positions with >80% conservation as conserved
            if conservation_score > 0.8:
                conserved_positions.append(i + 1)

    log.append(f"Conservation analysis completed and saved to {conservation_file}")
    log.append(f"Identified {len(conserved_positions)} highly conserved positions (>80% conservation)")

    if conserved_positions:
        log.append(f"Conserved positions: {', '.join(map(str, conserved_positions[:10]))}")
        if len(conserved_positions) > 10:
            log.append(f"... and {len(conserved_positions) - 10} more")

    # Final summary
    log.append("\\n## Summary")
    log.append("The analysis successfully completed with the following outputs:")
    log.append(f"1. Multiple sequence alignment: {aligned_file}")
    log.append(f"2. Phylogenetic tree: {tree_file}")
    log.append(f"3. Conservation analysis: {conservation_file}")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_protein_conservation(
        protein_sequences=auto_convert(os.environ.get("PARAM_PROTEIN_SEQUENCES", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./")),
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
    "function": "analyze_protein_conservation",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_protein_conservation_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_protein_conservation_output.txt", "w") as f:
    f.write("Biomni: Analyze Protein Conservation" + NL)
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
        biomni_function: "analyze_protein_conservation"
    END_VERSIONS
    """
}

workflow ANALYZE_PROTEIN_CONSERVATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_PROTEIN_CONSERVATION(ch_input)

    emit:
    results = ANALYZE_PROTEIN_CONSERVATION.out.results
    output = ANALYZE_PROTEIN_CONSERVATION.out.output
    versions = ANALYZE_PROTEIN_CONSERVATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_PROTEIN_CONSERVATION_WORKFLOW(ch_input)

    ANALYZE_PROTEIN_CONSERVATION_WORKFLOW.out.output.view { "Output: $it" }
}
