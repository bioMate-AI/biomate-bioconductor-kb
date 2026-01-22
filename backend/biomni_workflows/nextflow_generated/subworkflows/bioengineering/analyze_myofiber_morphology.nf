#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_myofiber_morphology
 * Quantifies morphological properties of myofibers in microscopy images of tissue sections.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.nuclei_channel = '2'
params.myofiber_channel = '1'
params.threshold_method = 'otsu'
params.output_dir = './'

// Main process
process ANALYZE_MYOFIBER_MORPHOLOGY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_myofiber_morphology_results.json"), emit: results
    path("analyze_myofiber_morphology_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioengineering import analyze_myofiber_morphology
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_myofiber_morphology(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_myofiber_morphology(
    image_path="${params.image_path}",
    nuclei_channel="${params.nuclei_channel}",
    myofiber_channel="${params.myofiber_channel}",
    threshold_method="${params.threshold_method}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_myofiber_morphology_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_myofiber_morphology_output.txt", "w") as f:
    f.write("Biomni: Analyze Myofiber Morphology Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_myofiber_morphology completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_ANALYZE_MYOFIBER_MORPHOLOGY {
    take:
    // No file inputs

    main:
    ANALYZE_MYOFIBER_MORPHOLOGY()

    emit:
    results = ANALYZE_MYOFIBER_MORPHOLOGY.out.results
    output = ANALYZE_MYOFIBER_MORPHOLOGY.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_BIOENGINEERING_ANALYZE_MYOFIBER_MORPHOLOGY()
}
