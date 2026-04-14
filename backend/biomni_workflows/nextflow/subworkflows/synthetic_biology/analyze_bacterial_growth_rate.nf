#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_analyze_bacterial_growth_rate
 * Analyze bacterial growth data and extract growth parameters from OD600 measurements.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.od_measurements = null
params.strain_name = 'Unknown strain'
params.output_dir = './'

// Main process
process ANALYZE_BACTERIAL_GROWTH_RATE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_bacterial_growth_rate_results.json"), emit: results
    path("analyze_bacterial_growth_rate_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.synthetic_biology import analyze_bacterial_growth_rate

# Run the tool
try:
    result = analyze_bacterial_growth_rate(
    time_points="${params.time_points}",
    od_measurements="${params.od_measurements}",
    strain_name="${params.strain_name}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_bacterial_growth_rate_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_bacterial_growth_rate_output.txt", "w") as f:
    f.write("Biomni: Analyze Bacterial Growth Rate Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_bacterial_growth_rate completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BACTERIAL_GROWTH_RATE {
    take:
    // No file inputs

    main:
    ANALYZE_BACTERIAL_GROWTH_RATE()

    emit:
    results = ANALYZE_BACTERIAL_GROWTH_RATE.out.results
    output = ANALYZE_BACTERIAL_GROWTH_RATE.out.output
}

// Entry workflow
workflow {
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }
    if (!params.od_measurements) {
        error "Please provide --od_measurements parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_ANALYZE_BACTERIAL_GROWTH_RATE()
}
