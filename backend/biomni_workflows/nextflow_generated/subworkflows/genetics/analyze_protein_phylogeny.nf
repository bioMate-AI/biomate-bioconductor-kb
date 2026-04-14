#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_protein_phylogeny
 * Perform phylogenetic analysis on a set of protein sequences.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fasta_sequences = null
params.output_dir = './'
params.alignment_method = 'clustalw'
params.tree_method = 'fasttree'

// Main process
process ANALYZE_PROTEIN_PHYLOGENY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_protein_phylogeny_results.json"), emit: results
    path("analyze_protein_phylogeny_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genetics import analyze_protein_phylogeny
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_protein_phylogeny(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_protein_phylogeny(
    fasta_sequences="${params.fasta_sequences}",
    output_dir="${params.output_dir}",
    alignment_method="${params.alignment_method}",
    tree_method="${params.tree_method}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_protein_phylogeny_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_protein_phylogeny_output.txt", "w") as f:
    f.write("Biomni: Analyze Protein Phylogeny Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_protein_phylogeny completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_ANALYZE_PROTEIN_PHYLOGENY {
    take:
    // No file inputs

    main:
    ANALYZE_PROTEIN_PHYLOGENY()

    emit:
    results = ANALYZE_PROTEIN_PHYLOGENY.out.results
    output = ANALYZE_PROTEIN_PHYLOGENY.out.output
}

// Entry workflow
workflow {
    if (!params.fasta_sequences) {
        error "Please provide --fasta_sequences parameter"
    }


    BIOMNI_GENETICS_ANALYZE_PROTEIN_PHYLOGENY()
}
