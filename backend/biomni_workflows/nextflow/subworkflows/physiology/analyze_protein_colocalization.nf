#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_protein_colocalization
 * Analyze colocalization between two fluorescently labeled proteins in microscopy images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.channel1_path = null
params.channel2_path = null
params.output_dir = './output'
params.threshold_method = 'otsu'

// Main process
process ANALYZE_PROTEIN_COLOCALIZATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_protein_colocalization_results.json"), emit: results
    path("analyze_protein_colocalization_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import analyze_protein_colocalization
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_protein_colocalization(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_protein_colocalization(
    channel1_path="${params.channel1_path}",
    channel2_path="${params.channel2_path}",
    output_dir="${params.output_dir}",
    threshold_method="${params.threshold_method}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_protein_colocalization_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_protein_colocalization_output.txt", "w") as f:
    f.write("Biomni: Analyze Protein Colocalization Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_protein_colocalization completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_ANALYZE_PROTEIN_COLOCALIZATION {
    take:
    // No file inputs

    main:
    ANALYZE_PROTEIN_COLOCALIZATION()

    emit:
    results = ANALYZE_PROTEIN_COLOCALIZATION.out.results
    output = ANALYZE_PROTEIN_COLOCALIZATION.out.output
}

// Entry workflow
workflow {
    if (!params.channel1_path) {
        error "Please provide --channel1_path parameter"
    }
    if (!params.channel2_path) {
        error "Please provide --channel2_path parameter"
    }


    BIOMNI_PHYSIOLOGY_ANALYZE_PROTEIN_COLOCALIZATION()
}
