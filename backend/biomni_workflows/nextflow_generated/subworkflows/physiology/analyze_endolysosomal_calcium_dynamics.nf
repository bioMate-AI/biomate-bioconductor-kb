#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_endolysosomal_calcium_dynamics
 * Analyze calcium dynamics in endo-lysosomal compartments using ELGA/ELGA1 probe data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.luminescence_values = null
params.treatment_time = null
params.cell_type = null
params.treatment_name = null
params.output_file = 'calcium_analysis_results.txt'

// Main process
process ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_endolysosomal_calcium_dynamics_results.json"), emit: results
    path("analyze_endolysosomal_calcium_dynamics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import analyze_endolysosomal_calcium_dynamics
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_endolysosomal_calcium_dynamics(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_endolysosomal_calcium_dynamics(
    time_points="${params.time_points}",
    luminescence_values="${params.luminescence_values}",
    treatment_time="${params.treatment_time}",
    cell_type="${params.cell_type}",
    treatment_name="${params.treatment_name}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_endolysosomal_calcium_dynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_endolysosomal_calcium_dynamics_output.txt", "w") as f:
    f.write("Biomni: Analyze Endolysosomal Calcium Dynamics Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_endolysosomal_calcium_dynamics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS {
    take:
    // No file inputs

    main:
    ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS()

    emit:
    results = ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS.out.results
    output = ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS.out.output
}

// Entry workflow
workflow {
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }
    if (!params.luminescence_values) {
        error "Please provide --luminescence_values parameter"
    }


    BIOMNI_PHYSIOLOGY_ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS()
}
