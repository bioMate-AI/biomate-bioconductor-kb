#!/usr/bin/env nextflow
/*
 * biomni_genomics_analyze_chromatin_interactions
 * Analyze chromatin interactions from Hi-C data to identify enhancer-promoter interactions and TADs.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.hic_file_path = null
params.regulatory_elements_bed = null
params.output_dir = './output'

// Main process
process ANALYZE_CHROMATIN_INTERACTIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_chromatin_interactions_results.json"), emit: results
    path("analyze_chromatin_interactions_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import analyze_chromatin_interactions

# Run the tool
try:
    result = analyze_chromatin_interactions(
    hic_file_path="${params.hic_file_path}",
    regulatory_elements_bed="${params.regulatory_elements_bed}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_chromatin_interactions_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_chromatin_interactions_output.txt", "w") as f:
    f.write("Biomni: Analyze Chromatin Interactions Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_chromatin_interactions completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_ANALYZE_CHROMATIN_INTERACTIONS {
    take:
    // No file inputs

    main:
    ANALYZE_CHROMATIN_INTERACTIONS()

    emit:
    results = ANALYZE_CHROMATIN_INTERACTIONS.out.results
    output = ANALYZE_CHROMATIN_INTERACTIONS.out.output
}

// Entry workflow
workflow {
    if (!params.hic_file_path) {
        error "Please provide --hic_file_path parameter"
    }
    if (!params.regulatory_elements_bed) {
        error "Please provide --regulatory_elements_bed parameter"
    }


    BIOMNI_GENOMICS_ANALYZE_CHROMATIN_INTERACTIONS()
}
