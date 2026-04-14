#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_analyze_mitochondrial_morphology_and_potential
 * Quantifies metrics of mitochondrial morphology and membrane potential from fluorescence microscopy images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.morphology_image_path = null
params.potential_image_path = null
params.output_dir = './output'

// Main process
process ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_mitochondrial_morphology_and_potential_results.json"), emit: results
    path("analyze_mitochondrial_morphology_and_potential_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.cell_biology import analyze_mitochondrial_morphology_and_potential

# Run the tool
try:
    result = analyze_mitochondrial_morphology_and_potential(
    morphology_image_path="${params.morphology_image_path}",
    potential_image_path="${params.potential_image_path}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_mitochondrial_morphology_and_potential_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_mitochondrial_morphology_and_potential_output.txt", "w") as f:
    f.write("Biomni: Analyze Mitochondrial Morphology And Potential Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_mitochondrial_morphology_and_potential completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CELL_BIOLOGY_ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL {
    take:
    // No file inputs

    main:
    ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL()

    emit:
    results = ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL.out.results
    output = ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL.out.output
}

// Entry workflow
workflow {
    if (!params.morphology_image_path) {
        error "Please provide --morphology_image_path parameter"
    }
    if (!params.potential_image_path) {
        error "Please provide --potential_image_path parameter"
    }


    BIOMNI_CELL_BIOLOGY_ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL()
}
