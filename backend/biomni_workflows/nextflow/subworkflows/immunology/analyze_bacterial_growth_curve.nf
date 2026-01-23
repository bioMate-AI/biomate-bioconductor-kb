#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_bacterial_growth_curve
 * Analyzes bacterial growth curve data to determine growth parameters.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.od_values = null
params.strain_name = null
params.output_dir = '.'

// Main process
process ANALYZE_BACTERIAL_GROWTH_CURVE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_bacterial_growth_curve_results.json"), emit: results
    path("analyze_bacterial_growth_curve_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.immunology import analyze_bacterial_growth_curve

# Run the tool
try:
    result = analyze_bacterial_growth_curve(
    time_points="${params.time_points}",
    od_values="${params.od_values}",
    strain_name="${params.strain_name}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_bacterial_growth_curve_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_bacterial_growth_curve_output.txt", "w") as f:
    f.write("Biomni: Analyze Bacterial Growth Curve Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_bacterial_growth_curve completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ANALYZE_BACTERIAL_GROWTH_CURVE {
    take:
    // No file inputs

    main:
    ANALYZE_BACTERIAL_GROWTH_CURVE()

    emit:
    results = ANALYZE_BACTERIAL_GROWTH_CURVE.out.results
    output = ANALYZE_BACTERIAL_GROWTH_CURVE.out.output
}

// Entry workflow
workflow {
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }
    if (!params.od_values) {
        error "Please provide --od_values parameter"
    }
    if (!params.strain_name) {
        error "Please provide --strain_name parameter"
    }


    BIOMNI_IMMUNOLOGY_ANALYZE_BACTERIAL_GROWTH_CURVE()
}
