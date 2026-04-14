#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_crispr_genome_editing
 * Analyzes CRISPR-Cas9 genome editing results by comparing original and edited sequences.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.original_sequence = null
params.edited_sequence = null
params.guide_rna = null
params.repair_template = null

// Main process
process ANALYZE_CRISPR_GENOME_EDITING {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_crispr_genome_editing_results.json"), emit: results
    path("analyze_crispr_genome_editing_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genetics import analyze_crispr_genome_editing

# Run the tool
try:
    result = analyze_crispr_genome_editing(
    original_sequence="${params.original_sequence}",
    edited_sequence="${params.edited_sequence}",
    guide_rna="${params.guide_rna}",
    repair_template="${params.repair_template}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_crispr_genome_editing_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_crispr_genome_editing_output.txt", "w") as f:
    f.write("Biomni: Analyze Crispr Genome Editing Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_crispr_genome_editing completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_ANALYZE_CRISPR_GENOME_EDITING {
    take:
    // No file inputs

    main:
    ANALYZE_CRISPR_GENOME_EDITING()

    emit:
    results = ANALYZE_CRISPR_GENOME_EDITING.out.results
    output = ANALYZE_CRISPR_GENOME_EDITING.out.output
}

// Entry workflow
workflow {
    if (!params.original_sequence) {
        error "Please provide --original_sequence parameter"
    }
    if (!params.edited_sequence) {
        error "Please provide --edited_sequence parameter"
    }
    if (!params.guide_rna) {
        error "Please provide --guide_rna parameter"
    }


    BIOMNI_GENETICS_ANALYZE_CRISPR_GENOME_EDITING()
}
