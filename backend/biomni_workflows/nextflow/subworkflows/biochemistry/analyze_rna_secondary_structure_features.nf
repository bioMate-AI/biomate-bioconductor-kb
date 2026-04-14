#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_rna_secondary_structure_features
 * Calculate numeric values for various structural features of an RNA secondary structure.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.dot_bracket_structure = null
params.sequence = null

// Main process
process ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_rna_secondary_structure_features_results.json"), emit: results
    path("analyze_rna_secondary_structure_features_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.biochemistry import analyze_rna_secondary_structure_features

# Run the tool
try:
    result = analyze_rna_secondary_structure_features(
    dot_bracket_structure="${params.dot_bracket_structure}",
    sequence="${params.sequence}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_rna_secondary_structure_features_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_rna_secondary_structure_features_output.txt", "w") as f:
    f.write("Biomni: Analyze Rna Secondary Structure Features Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_rna_secondary_structure_features completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES {
    take:
    // No file inputs

    main:
    ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES()

    emit:
    results = ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES.out.results
    output = ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES.out.output
}

// Entry workflow
workflow {
    if (!params.dot_bracket_structure) {
        error "Please provide --dot_bracket_structure parameter"
    }


    BIOMNI_BIOCHEMISTRY_ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES()
}
