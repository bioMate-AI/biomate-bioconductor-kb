#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_analyze_bifurcation_diagram
 * Performs bifurcation analysis on a dynamical system and generates a bifurcation diagram.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_series_data = null
params.parameter_values = null
params.system_name = 'Dynamical System'
params.output_dir = './'

// Main process
process ANALYZE_BIFURCATION_DIAGRAM {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_bifurcation_diagram_results.json"), emit: results
    path("analyze_bifurcation_diagram_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.synthetic_biology import analyze_bifurcation_diagram

# Run the tool
try:
    result = analyze_bifurcation_diagram(
    time_series_data="${params.time_series_data}",
    parameter_values="${params.parameter_values}",
    system_name="${params.system_name}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_bifurcation_diagram_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_bifurcation_diagram_output.txt", "w") as f:
    f.write("Biomni: Analyze Bifurcation Diagram Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_bifurcation_diagram completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BIFURCATION_DIAGRAM {
    take:
    // No file inputs

    main:
    ANALYZE_BIFURCATION_DIAGRAM()

    emit:
    results = ANALYZE_BIFURCATION_DIAGRAM.out.results
    output = ANALYZE_BIFURCATION_DIAGRAM.out.output
}

// Entry workflow
workflow {
    if (!params.time_series_data) {
        error "Please provide --time_series_data parameter"
    }
    if (!params.parameter_values) {
        error "Please provide --parameter_values parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BIFURCATION_DIAGRAM()
}
