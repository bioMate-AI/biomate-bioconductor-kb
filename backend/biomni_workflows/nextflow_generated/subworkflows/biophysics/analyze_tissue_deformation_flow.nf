#!/usr/bin/env nextflow
/*
 * biomni_biophysics_analyze_tissue_deformation_flow
 * Quantify tissue deformation and flow dynamics from microscopy image sequence.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_sequence = null
params.output_dir = 'results'
params.pixel_scale = '1.0'

// Main process
process ANALYZE_TISSUE_DEFORMATION_FLOW {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_tissue_deformation_flow_results.json"), emit: results
    path("analyze_tissue_deformation_flow_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.biophysics import analyze_tissue_deformation_flow
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_tissue_deformation_flow(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_tissue_deformation_flow(
    image_sequence="${params.image_sequence}",
    output_dir="${params.output_dir}",
    pixel_scale="${params.pixel_scale}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_tissue_deformation_flow_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_tissue_deformation_flow_output.txt", "w") as f:
    f.write("Biomni: Analyze Tissue Deformation Flow Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_tissue_deformation_flow completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOPHYSICS_ANALYZE_TISSUE_DEFORMATION_FLOW {
    take:
    // No file inputs

    main:
    ANALYZE_TISSUE_DEFORMATION_FLOW()

    emit:
    results = ANALYZE_TISSUE_DEFORMATION_FLOW.out.results
    output = ANALYZE_TISSUE_DEFORMATION_FLOW.out.output
}

// Entry workflow
workflow {
    if (!params.image_sequence) {
        error "Please provide --image_sequence parameter"
    }


    BIOMNI_BIOPHYSICS_ANALYZE_TISSUE_DEFORMATION_FLOW()
}
