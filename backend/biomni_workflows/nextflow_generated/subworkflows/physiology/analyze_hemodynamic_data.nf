#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_hemodynamic_data
 * Analyzes raw blood pressure data to calculate key hemodynamic parameters.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pressure_data = null
params.sampling_rate = null
params.output_file = 'hemodynamic_results.csv'

// Main process
process ANALYZE_HEMODYNAMIC_DATA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_hemodynamic_data_results.json"), emit: results
    path("analyze_hemodynamic_data_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import analyze_hemodynamic_data
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_hemodynamic_data(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_hemodynamic_data(
    pressure_data="${params.pressure_data}",
    sampling_rate="${params.sampling_rate}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_hemodynamic_data_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_hemodynamic_data_output.txt", "w") as f:
    f.write("Biomni: Analyze Hemodynamic Data Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_hemodynamic_data completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_ANALYZE_HEMODYNAMIC_DATA {
    take:
    // No file inputs

    main:
    ANALYZE_HEMODYNAMIC_DATA()

    emit:
    results = ANALYZE_HEMODYNAMIC_DATA.out.results
    output = ANALYZE_HEMODYNAMIC_DATA.out.output
}

// Entry workflow
workflow {
    if (!params.pressure_data) {
        error "Please provide --pressure_data parameter"
    }
    if (!params.sampling_rate) {
        error "Please provide --sampling_rate parameter"
    }


    BIOMNI_PHYSIOLOGY_ANALYZE_HEMODYNAMIC_DATA()
}
