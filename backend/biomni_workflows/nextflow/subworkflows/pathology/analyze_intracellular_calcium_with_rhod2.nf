#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_intracellular_calcium_with_rhod2
 * Analyzes intracellular calcium concentration using Rhod-2 fluorescent indicator from microscopy images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.background_image_path = null
params.control_image_path = null
params.sample_image_path = null
params.output_dir = './output'

// Main process
process ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_intracellular_calcium_with_rhod2_results.json"), emit: results
    path("analyze_intracellular_calcium_with_rhod2_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pathology import analyze_intracellular_calcium_with_rhod2

# Run the tool
try:
    result = analyze_intracellular_calcium_with_rhod2(
    background_image_path="${params.background_image_path}",
    control_image_path="${params.control_image_path}",
    sample_image_path="${params.sample_image_path}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_intracellular_calcium_with_rhod2_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_intracellular_calcium_with_rhod2_output.txt", "w") as f:
    f.write("Biomni: Analyze Intracellular Calcium With Rhod2 Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_intracellular_calcium_with_rhod2 completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PATHOLOGY_ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 {
    take:
    // No file inputs

    main:
    ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2()

    emit:
    results = ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2.out.results
    output = ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2.out.output
}

// Entry workflow
workflow {
    if (!params.background_image_path) {
        error "Please provide --background_image_path parameter"
    }
    if (!params.control_image_path) {
        error "Please provide --control_image_path parameter"
    }
    if (!params.sample_image_path) {
        error "Please provide --sample_image_path parameter"
    }


    BIOMNI_PATHOLOGY_ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2()
}
