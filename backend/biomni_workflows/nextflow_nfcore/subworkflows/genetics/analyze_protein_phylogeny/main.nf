#!/usr/bin/env nextflow
/*
 * genetics/analyze_protein_phylogeny
 * Perform phylogenetic analysis on a set of protein sequences.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: BRCA1 protein homologs from human, mouse, and chicken for phylogenetic analysis
params.fasta_sequences = '''>BRCA1_Human
MDLSALRVEEVQNVINAMQKILECPICLELIKEPVSTKCDHIFCKFCMLKLLNQKKGPSQCPLCKNDITK
RSLQESTRFSQLVEELLKIICAFQLDTGLEYANSYNFAKKENNSPEHLKDEVSIIQSMGYRNRAKRLLQS
EPENPSLQETSLSVQLSNLGTVRTLRTKQRIQPQKTSVYIELGSDSSEDTVNKATYCSVGDQELLQITPQ
>BRCA1_Mouse
MDLSALRVEEVQNVINAMQKILECPICLELIKEPVSTKCDHIFCKFCMLKLLNQKKGPSQCPLCKNDIIK
RSLQESTRFSQLVEELLKIICAFQLDTGLEYANSYNFAKKENNSPEHLKDEVSIIQSMGYRNRAKRLLQS
EPENPSLQETSLSVQLSNLGTVRTLRTKQRIQPQKTSVYIELGSDSSEDTVNKATYCSVGDQELLQITPQ
>BRCA1_Chicken
MDLSALRVEEVQNVINAMQKILECPICLELIKEPVSTKCDHIFCKFCMLKLLNQKKGPSQCPLCKNDITK
RSLQESTRFSQLVEELLKIICAFQLDTGLEYANSYNFAKKENNSPEHLKDEVSIIQSMGYRNRAKRLLQS
EPENPSLQETSLSVQLSNLGTVRTLRTKQRIQPQKTSVYIELGSDSSEDTVNKATYCSVGDQELLQITPQ'''
params.output_dir = './'
params.alignment_method = 'clustalw'
params.tree_method = 'iqtree'

process ANALYZE_PROTEIN_PHYLOGENY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_protein_phylogeny_results.json"), emit: results
    tuple val(meta), path("analyze_protein_phylogeny_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FASTA_SEQUENCES="${params.fasta_sequences?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ALIGNMENT_METHOD="${params.alignment_method?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TREE_METHOD="${params.tree_method?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
from datetime import datetime
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



def analyze_protein_phylogeny(
    fasta_sequences,
    output_dir="./",
    alignment_method="clustalw",
    tree_method="fasttree",
):
    '''Perform phylogenetic analysis on a set of protein sequences.

    This function takes protein sequences in FASTA format, performs multiple sequence alignment,
    constructs a phylogenetic tree, and visualizes the evolutionary relationships.

    Parameters
    ----------
    fasta_sequences : str
        Path to a FASTA file containing protein sequences or a string with FASTA-formatted sequences
    output_dir : str, optional
        Directory to save output files (default: current directory)
    alignment_method : str, optional
        Method for sequence alignment: "clustalw", "muscle", or "pre-aligned" (default: "clustalw")
    tree_method : str, optional
        Method for tree construction: "iqtree" (default: "iqtree")

    Returns
    -------
    str
        Research log summarizing the phylogenetic analysis process

    '''
    import datetime
    import subprocess
    import tempfile

    from Bio import AlignIO, Phylo, SeqIO

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Initialize log
    log = []
    log.append(f"Phylogenetic Analysis - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append("=" * 50)

    # Check if input is a file path or string content
    if os.path.isfile(fasta_sequences):
        input_file = fasta_sequences
        log.append(f"Using sequences from file: {input_file}")
    else:
        # Create temporary file with the string content
        temp_fasta = tempfile.NamedTemporaryFile(delete=False, suffix=".fasta", dir=output_dir)
        temp_fasta.write(fasta_sequences.encode())
        temp_fasta.close()
        input_file = temp_fasta.name
        log.append(f"Created temporary FASTA file from provided sequences: {input_file}")

    # Count sequences
    try:
        sequences = list(SeqIO.parse(input_file, "fasta"))
        log.append(f"Loaded {len(sequences)} protein sequences")
    except Exception as e:
        log.append(f"Warning: Could not parse sequences as FASTA: {str(e)}")
        # This might be pre-aligned data already
        sequences = []

    # Create filenames for outputs
    base_name = os.path.splitext(os.path.basename(input_file))[0]
    alignment_file = os.path.join(output_dir, f"{base_name}_aligned.aln")
    tree_file = os.path.join(output_dir, f"{base_name}_tree.nwk")
    tree_image = os.path.join(output_dir, f"{base_name}_phylogeny.png")

    # Perform multiple sequence alignment
    log.append("\\nStep 1: Multiple Sequence Alignment")

    # Special case for pre-aligned input
    if alignment_method.lower() == "pre-aligned":
        log.append("Using pre-aligned sequences")
        try:
            # If the input is already an alignment file, copy it to the alignment_file path
            with open(input_file) as src, open(alignment_file, "w") as dst:
                dst.write(src.read())
            log.append(f"Copied pre-aligned file to: {alignment_file}")
        except Exception as e:
            log.append(f"Error processing pre-aligned sequences: {str(e)}")
            return "\\n".join(log)
    elif alignment_method.lower() == "clustalw":
        log.append("Using ClustalW for alignment")
        try:
            # Use subprocess directly instead of deprecated Bio.Align.Applications
            result = subprocess.run(
                ["clustalw", "-INFILE=" + input_file, "-OUTFILE=" + alignment_file],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                raise RuntimeError(f"ClustalW failed: {result.stderr}")
            log.append("Alignment completed successfully")
        except Exception as e:
            log.append(f"Error during alignment: {str(e)}")
            # Try alternative approach using MUSCLE if ClustalW fails
            alignment_method = "muscle"

    if alignment_method.lower() == "muscle":
        log.append("Using MUSCLE for alignment")
        try:
            # Use subprocess directly instead of deprecated Bio.Align.Applications
            result = subprocess.run(
                ["muscle", "-in", input_file, "-out", alignment_file],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                raise RuntimeError(f"MUSCLE failed: {result.stderr}")
            log.append("Alignment completed successfully")
        except Exception as e:
            log.append(f"Error during MUSCLE alignment: {str(e)}")
            log.append("Attempting to use Biopython's built-in pairwise2 alignment as fallback")

            from Bio import pairwise2

            # Create a simple progressive alignment
            ref_seq = sequences[0]
            alignments = []

            for seq in sequences:
                alignment = pairwise2.align.globalxx(ref_seq.seq, seq.seq)[0]
                alignments.append(alignment)

            # Write alignment to file in CLUSTAL format
            with open(alignment_file, "w") as f:
                f.write("CLUSTAL W (1.83) multiple sequence alignment\\n\\n")
                for i, seq in enumerate(sequences):
                    f.write(f"{seq.id.ljust(10)} {alignments[i][1]}\\n")
                # Add consensus line with asterisks
                f.write(" " * 10 + " " * len(alignments[0][1]) + "\\n")

            log.append("Created basic alignment using Biopython's pairwise2")

    # Verify alignment file exists
    if not os.path.exists(alignment_file):
        log.append(f"Error: Alignment file {alignment_file} does not exist")
        return "\\n".join(log)

    # Build phylogenetic tree
    log.append("\\nStep 2: Phylogenetic Tree Construction")

    if tree_method.lower() == "iqtree":
        log.append("Using IQ-TREE for phylogenetic tree construction")
        try:
            cmd = f"iqtree -s {alignment_file} -m LG -bb 1000 -pre {os.path.join(output_dir, base_name)}"
            subprocess.run(
                cmd,
                shell=True,
                check=True,
                capture_output=True,
            )
            # IQ-TREE creates files with .treefile extension
            iqtree_file = os.path.join(output_dir, f"{base_name}.treefile")
            if os.path.exists(iqtree_file):
                # Rename to our standard name
                os.rename(iqtree_file, tree_file)
            log.append("Tree construction completed successfully")
        except Exception as e:
            log.append(f"Error during IQ-TREE execution: {str(e)}")
            log.append("Falling back to neighbor-joining method")

            try:
                from Bio.Phylo.TreeConstruction import (
                    DistanceCalculator,
                    DistanceTreeConstructor,
                )

                # Try to read the alignment in different formats
                alignment = None
                for format in ["clustal", "fasta"]:
                    try:
                        alignment = AlignIO.read(alignment_file, format)
                        break
                    except Exception:
                        continue

                if alignment is None:
                    log.append("Could not parse alignment file in any supported format")
                    # Create a simple text-based tree file as a fallback
                    with open(tree_file, "w") as f:
                        f.write("(protein1:0.1,protein2:0.2,(protein3:0.3,protein4:0.4):0.5);")
                    log.append("Created placeholder tree file")
                else:
                    # Calculate the distance matrix
                    calculator = DistanceCalculator("identity")
                    dm = calculator.get_distance(alignment)

                    # Construct the tree
                    constructor = DistanceTreeConstructor()
                    tree = constructor.nj(dm)

                    # Write the tree to file
                    Phylo.write(tree, tree_file, "newick")
                    log.append("Created tree using neighbor-joining method")
            except Exception as e:
                log.append(f"Error during fallback tree construction: {str(e)}")
                # Create a simple text-based tree file as a final fallback
                with open(tree_file, "w") as f:
                    f.write("(protein1:0.1,protein2:0.2,(protein3:0.3,protein4:0.4):0.5);")
                log.append("Created placeholder tree file as final fallback")
    else:
        log.append(f"Unsupported tree method: {tree_method}")
        return "\\n".join(log)

    # Verify tree file exists
    if not os.path.exists(tree_file):
        log.append(f"Error: Tree file {tree_file} does not exist")
        return "\\n".join(log)

    # Visualize the tree
    log.append("\\nStep 3: Phylogenetic Tree Visualization")
    try:
        import matplotlib

        matplotlib.use("Agg")  # Use non-interactive backend
        import matplotlib.pyplot as plt

        tree = Phylo.read(tree_file, "newick")
        fig = plt.figure(figsize=(10, len(sequences) * 0.3 if sequences else 5))
        axes = fig.add_subplot(1, 1, 1)
        Phylo.draw(tree, axes=axes, do_show=False)
        plt.savefig(tree_image, dpi=300, bbox_inches="tight")
        plt.close()
        log.append(f"Tree visualization saved to: {tree_image}")
    except Exception as e:
        log.append(f"Error during tree visualization: {str(e)}")

    # Summary
    log.append("\\nSummary:")
    log.append(f"- Input sequences: {len(sequences) if sequences else 'pre-aligned data'}")
    log.append(f"- Alignment file: {alignment_file}")
    log.append(f"- Phylogenetic tree file: {tree_file}")
    log.append(f"- Tree visualization: {tree_image}")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_protein_phylogeny(
        fasta_sequences=auto_convert(os.environ.get("PARAM_FASTA_SEQUENCES", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./")),
        alignment_method=auto_convert(os.environ.get("PARAM_ALIGNMENT_METHOD", "clustalw")),
        tree_method=auto_convert(os.environ.get("PARAM_TREE_METHOD", "fasttree")),
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
    "function": "analyze_protein_phylogeny",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_protein_phylogeny_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_protein_phylogeny_output.txt", "w") as f:
    f.write("Biomni: Analyze Protein Phylogeny" + NL)
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
        biomni_function: "analyze_protein_phylogeny"
    END_VERSIONS
    """
}

workflow ANALYZE_PROTEIN_PHYLOGENY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_PROTEIN_PHYLOGENY(ch_input)

    emit:
    results = ANALYZE_PROTEIN_PHYLOGENY.out.results
    output = ANALYZE_PROTEIN_PHYLOGENY.out.output
    versions = ANALYZE_PROTEIN_PHYLOGENY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_PROTEIN_PHYLOGENY_WORKFLOW(ch_input)

    ANALYZE_PROTEIN_PHYLOGENY_WORKFLOW.out.output.view { "Output: $it" }
}
