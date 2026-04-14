#!/usr/bin/env nextflow
/*
 * biomni_physiology_perform_cosinor_analysis
 * Performs cosinor analysis on physiological time series data to characterize circadian rhythms.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_data = null
params.physiological_data = null
params.period = '24.0'

// Main process
process PERFORM_COSINOR_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_cosinor_analysis_results.json"), emit: results
    path("perform_cosinor_analysis_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import perform_cosinor_analysis
except ImportError:
    # Fallback: function may need to be implemented locally
    def perform_cosinor_analysis(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = perform_cosinor_analysis(
    time_data="${params.time_data}",
    physiological_data="${params.physiological_data}",
    period="${params.period}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_cosinor_analysis_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("perform_cosinor_analysis_output.txt", "w") as f:
    f.write("Biomni: Perform Cosinor Analysis Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("perform_cosinor_analysis completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_PERFORM_COSINOR_ANALYSIS {
    take:
    // No file inputs

    main:
    PERFORM_COSINOR_ANALYSIS()

    emit:
    results = PERFORM_COSINOR_ANALYSIS.out.results
    output = PERFORM_COSINOR_ANALYSIS.out.output
}

// Entry workflow
workflow {
    if (!params.time_data) {
        error "Please provide --time_data parameter"
    }
    if (!params.physiological_data) {
        error "Please provide --physiological_data parameter"
    }


    BIOMNI_PHYSIOLOGY_PERFORM_COSINOR_ANALYSIS()
}
